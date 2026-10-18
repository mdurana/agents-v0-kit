#!/bin/sh
# check-openapi.sh — validate a feature contract draft and its merge into the org catalog.
#
# Usage:
#   sh .agents-v0/ci/check-openapi.sh lint   <file>              kit rules on one OpenAPI 3.0 document
#   sh .agents-v0/ci/check-openapi.sh compat <draft> <catalog>   the draft does not break what the catalog already promises
#   sh .agents-v0/ci/check-openapi.sh merged <draft> <catalog>   the catalog contains every operation and component of the draft
#   sh .agents-v0/ci/check-openapi.sh merge  <draft> <catalog>   write the draft into the catalog, then run "merged"
#
# lint checks: OpenAPI 3.0; info; every path under /api/v1/; every $ref is local and resolves;
# every operation has a unique operationId, a 2xx response, and security (an empty security list
# needs x-public: true); every POST has an Idempotency-Key header parameter unless it says
# x-idempotency: not-applicable; one error envelope per document (application/problem+json or a
# plain JSON envelope, not both); path placeholders are declared.
# compat checks only operations that exist in both documents (the draft is a fragment): no removed
# 2xx response, no new required parameter or request field, no removed response property, and no
# component of the same name with a different definition.
# merge rewrites the catalog through a YAML library: comments and key layout are not preserved.
# Review the diff, or merge by hand and run "merged". Needs python3 and PyYAML
# (python3 -m pip install pyyaml, apk add py3-yaml, or on Intel macOS:
# sh .agents-v0/scripts/host-tools-macports.sh). JSON files need only python3.
# Exit 0 when every check passes; 1 otherwise.

set -eu

mode="${1:-}"
case "$mode" in
  lint) [ $# -eq 2 ] || { printf 'usage: %s lint <file>\n' "$0" >&2; exit 1; } ;;
  compat | merged | merge) [ $# -eq 3 ] || { printf 'usage: %s %s <draft> <catalog>\n' "$0" "$mode" >&2; exit 1; } ;;
  *) printf 'usage: %s lint <file> | compat|merged|merge <draft> <catalog>\n' "$0" >&2; exit 1 ;;
esac
command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

MODE="$mode" ARG1="${2:-}" ARG2="${3:-}" python3 - <<'PY'
import copy
import json
import os
import sys

mode, arg1, arg2 = os.environ["MODE"], os.environ["ARG1"], os.environ["ARG2"]
METHODS = ("get", "put", "post", "delete", "patch", "options", "head")
COMPONENT_KINDS = ("schemas", "parameters", "responses", "requestBodies", "headers", "securitySchemes")
failures = []


def fail(msg):
    failures.append(msg)


def load(path):
    if not os.path.isfile(path):
        print(f"FAIL: file not found: {path}", file=sys.stderr)
        raise SystemExit(1)
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    if path.endswith(".json"):
        return json.loads(text)
    try:
        import yaml
    except ImportError:
        print("FAIL: PyYAML is required for YAML contracts (python3 -m pip install pyyaml, apk add py3-yaml, or on Intel macOS: sh .agents-v0/scripts/host-tools-macports.sh)", file=sys.stderr)
        raise SystemExit(1)
    return yaml.safe_load(text)


def resolve(doc, node):
    seen = 0
    while isinstance(node, dict) and "$ref" in node and seen < 20:
        ref = node["$ref"]
        if not isinstance(ref, str) or not ref.startswith("#/"):
            return node
        target = doc
        for part in ref[2:].split("/"):
            part = part.replace("~1", "/").replace("~0", "~")
            if not isinstance(target, dict) or part not in target:
                return {}
            target = target[part]
        node = target
        seen += 1
    return node


def walk_refs(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "$ref" and isinstance(value, str):
                yield value
            else:
                yield from walk_refs(value)
    elif isinstance(node, list):
        for item in node:
            yield from walk_refs(item)


def operations(doc):
    for path, item in (doc.get("paths") or {}).items():
        if not isinstance(item, dict):
            continue
        for method in METHODS:
            if isinstance(item.get(method), dict):
                yield path, method, item[method], item


def op_params(doc, op, item):
    out = []
    for source in (item.get("parameters") or [], op.get("parameters") or []):
        for param in source:
            param = resolve(doc, param)
            if isinstance(param, dict) and param.get("name"):
                out.append(param)
    return out


def server_urls(doc):
    out = []
    for srv in (doc.get("servers") or []):
        if isinstance(srv, dict) and isinstance(srv.get("url"), str):
            out.append(srv["url"].strip())
    return out


def has_api_v1_server(doc):
    urls = server_urls(doc)
    return bool(urls) and all(u.rstrip("/").endswith("/api/v1") for u in urls)


def canonical_path(doc, path):
    if has_api_v1_server(doc) and not path.startswith("/api/v1/") and path != "/api/v1":
        return "/api/v1" + (path if path.startswith("/") else "/" + path)
    return path


def is_placeholder_path(path):
    return "<" in path or ">" in path


def is_placeholder_name(name):
    return "<" in name or ">" in name


def real_operations(doc):
    for path, method, op, item in operations(doc):
        if not is_placeholder_path(path):
            yield path, method, op, item


def lint(doc, label):
    if not isinstance(doc, dict):
        fail(f"{label}: not an OpenAPI document")
        return
    if not str(doc.get("openapi", "")).startswith("3.0"):
        fail(f"{label}: openapi must be 3.0.x (got {doc.get('openapi')!r})")
    info = doc.get("info") or {}
    if not info.get("title") or not info.get("version"):
        fail(f"{label}: info.title and info.version are required")
    if not doc.get("paths"):
        fail(f"{label}: no paths")
    for ref in set(walk_refs(doc)):
        if not ref.startswith("#/"):
            fail(f"{label}: external $ref {ref} (inline it; a draft is one self-contained file)")
        elif resolve(doc, {"$ref": ref}) in ({}, None):
            fail(f"{label}: $ref does not resolve: {ref}")
    schemes = ((doc.get("components") or {}).get("securitySchemes") or {})
    global_security = doc.get("security")
    seen_ids, error_types = set(), set()
    has_real_ops = any(True for _ in real_operations(doc))
    srv_urls = server_urls(doc)
    for path, method, op, item in operations(doc):
        where = f"{label}: {method.upper()} {path}"
        for s_url in srv_urls:
            if s_url.rstrip("/").endswith("/api/v1") and (path.startswith("/api/v1/") or path == "/api/v1"):
                fail(f"{where}: server URL {s_url} with path {path} doubles /api/v1")
        if not canonical_path(doc, path).startswith("/api/v1/"):
            fail(f"{where}: paths live under /api/v1/")
        op_id = op.get("operationId")
        if not op_id:
            fail(f"{where}: operationId is required")
        elif op_id in seen_ids:
            fail(f"{where}: duplicate operationId {op_id}")
        seen_ids.add(op_id)
        responses = op.get("responses") or {}
        if not any(str(code).startswith(("2", "3")) for code in responses):
            fail(f"{where}: no 2xx response")
        for code, resp in responses.items():
            if str(code).startswith(("4", "5")):
                if has_real_ops and is_placeholder_path(path):
                    continue
                for ctype in (resolve(doc, resp).get("content") or {}):
                    error_types.add(ctype.split(";")[0].strip().lower())
        security = op.get("security", global_security)
        if security is None:
            fail(f"{where}: no security (set it on the operation or globally)")
        elif security == [] and not op.get("x-public"):
            fail(f"{where}: empty security needs x-public: true and a reason")
        else:
            for requirement in security or []:
                for name in (requirement or {}):
                    if name not in schemes:
                        fail(f"{where}: security scheme {name} is not in components.securitySchemes")
        params = op_params(doc, op, item)
        if method == "post" and op.get("x-idempotency") != "not-applicable":
            if not any(p.get("in") == "header" and str(p.get("name")).lower() == "idempotency-key" for p in params):
                fail(f"{where}: POST needs an Idempotency-Key header parameter (or x-idempotency: not-applicable)")
        declared = {p["name"] for p in params if p.get("in") == "path"}
        placeholders = {seg[1:-1] for seg in path.split("/") if seg.startswith("{") and seg.endswith("}")}
        if placeholders - declared:
            fail(f"{where}: path placeholder not declared as a parameter: {sorted(placeholders - declared)}")
    if "application/problem+json" in error_types and (error_types - {"application/problem+json"}):
        fail(f"{label}: mixed error envelopes ({sorted(error_types)}); pick one per API surface")


def required_of(doc, schema):
    schema = resolve(doc, schema)
    return set(schema.get("required") or []) if isinstance(schema, dict) else set()


def props_of(doc, schema):
    schema = resolve(doc, schema)
    return set((schema.get("properties") or {}).keys()) if isinstance(schema, dict) else set()


def json_schema(doc, holder):
    holder = resolve(doc, holder)
    content = (holder.get("content") or {}) if isinstance(holder, dict) else {}
    for ctype, media in content.items():
        if "json" in ctype:
            return (media or {}).get("schema")
    return None


def doc_error_types(doc):
    error_types = set()
    for path, method, op, item in real_operations(doc):
        for code, resp in (op.get("responses") or {}).items():
            if str(code).startswith(("4", "5")):
                for ctype in (resolve(doc, resp).get("content") or {}):
                    error_types.add(ctype.split(";")[0].strip().lower())
    return error_types


def compat(draft, catalog):
    cat_ops = {(canonical_path(catalog, p), m): (op, item) for p, m, op, item in operations(catalog)}
    for path, method, op, item in operations(draft):
        cpath = canonical_path(draft, path)
        if (cpath, method) not in cat_ops:
            continue
        cop, citem = cat_ops[(cpath, method)]
        where = f"{method.upper()} {path}"
        for code in cop.get("responses") or {}:
            if str(code).startswith("2") and code not in (op.get("responses") or {}):
                fail(f"{where}: the 2xx response {code} was removed")
        old = {(p["name"], p.get("in")) for p in op_params(catalog, cop, citem)}
        for param in op_params(draft, op, item):
            if param.get("required") and (param["name"], param.get("in")) not in old:
                fail(f"{where}: new required parameter {param['name']}")
        d_body, c_body = resolve(draft, op.get("requestBody") or {}), resolve(catalog, cop.get("requestBody") or {})
        if d_body.get("required") and not c_body.get("required"):
            fail(f"{where}: the request body became required")
        d_schema, c_schema = json_schema(draft, d_body), json_schema(catalog, c_body)
        if d_schema is not None and c_schema is not None:
            added = required_of(draft, d_schema) - required_of(catalog, c_schema)
            if added:
                fail(f"{where}: new required request fields {sorted(added)}")
        for code, resp in (cop.get("responses") or {}).items():
            if str(code).startswith("2") and code in (op.get("responses") or {}):
                old_s, new_s = json_schema(catalog, resp), json_schema(draft, op["responses"][code])
                if old_s is not None and new_s is not None:
                    removed = props_of(catalog, old_s) - props_of(draft, new_s)
                    if removed:
                        fail(f"{where}: response {code} lost properties {sorted(removed)}")
    d_errors = doc_error_types(draft)
    c_errors = doc_error_types(catalog)
    if c_errors and d_errors:
        combined = d_errors | c_errors
        if "application/problem+json" in combined and (combined - {"application/problem+json"}):
            fail(f"mixed error envelopes between draft ({sorted(d_errors)}) and catalog ({sorted(c_errors)}); pick one per API surface")
    for kind in COMPONENT_KINDS:
        mine = ((draft.get("components") or {}).get(kind) or {})
        theirs = ((catalog.get("components") or {}).get(kind) or {})
        for name, definition in mine.items():
            if is_placeholder_name(name):
                continue
            if name in theirs and not is_placeholder_name(name) and theirs[name] != definition:
                fail(f"components.{kind}.{name} differs from the catalog (rename it, or amend the catalog on purpose)")


def equal_or_tightened(draft_node, cat_node):
    if draft_node == cat_node:
        return True
    if isinstance(draft_node, dict) and isinstance(cat_node, dict):
        d_keys = set(draft_node.keys())
        c_keys = set(cat_node.keys())
        extra = c_keys - d_keys
        if extra <= {"additionalProperties"} and cat_node.get("additionalProperties") is False and "additionalProperties" not in draft_node:
            if d_keys == (c_keys - {"additionalProperties"}):
                return all(equal_or_tightened(draft_node[k], cat_node[k]) for k in d_keys)
        if d_keys == c_keys:
            return all(equal_or_tightened(draft_node[k], cat_node[k]) for k in d_keys)
        return False
    if isinstance(draft_node, list) and isinstance(cat_node, list) and len(draft_node) == len(cat_node):
        return all(equal_or_tightened(d, c) for d, c in zip(draft_node, cat_node))
    return False


def merged(draft, catalog):
    cat_paths = {canonical_path(catalog, p): v for p, v in (catalog.get("paths") or {}).items()}
    for path, item in (draft.get("paths") or {}).items():
        cpath = canonical_path(draft, path)
        if cpath not in cat_paths:
            fail(f"{path}: missing from the catalog")
            continue
        for key, value in item.items():
            if not equal_or_tightened(value, cat_paths[cpath].get(key)):
                fail(f"{path} {key}: the catalog differs from the approved draft")
    for kind in COMPONENT_KINDS:
        theirs = ((catalog.get("components") or {}).get(kind) or {})
        for name, definition in ((draft.get("components") or {}).get(kind) or {}).items():
            if name not in theirs:
                fail(f"components.{kind}.{name}: missing from the catalog")
            elif not equal_or_tightened(definition, theirs[name]):
                fail(f"components.{kind}.{name}: the catalog differs from the approved draft")


def merge(draft, catalog_path):
    import yaml
    if os.path.isfile(catalog_path):
        catalog = load(catalog_path)
    else:
        catalog = {"openapi": draft.get("openapi", "3.0.3"), "info": copy.deepcopy(draft.get("info")), "paths": {}}
    catalog.setdefault("paths", {})
    compat(draft, catalog)
    if failures:
        return None
    placeholder_paths = [p for p in catalog["paths"] if is_placeholder_path(p)]
    for p in placeholder_paths:
        del catalog["paths"][p]
    if "components" in catalog and isinstance(catalog["components"], dict):
        for kind in COMPONENT_KINDS:
            if kind in catalog["components"] and isinstance(catalog["components"][kind], dict):
                p_names = [n for n in catalog["components"][kind] if is_placeholder_name(n)]
                for n in p_names:
                    del catalog["components"][kind][n]
        if placeholder_paths and "schemas" in catalog["components"] and "ErrorResponse" in catalog["components"]["schemas"]:
            if "application/problem+json" in doc_error_types(draft):
                refs = set(walk_refs(catalog.get("paths") or {}))
                if "#/components/schemas/ErrorResponse" not in refs:
                    del catalog["components"]["schemas"]["ErrorResponse"]
    if draft.get("info") and catalog.get("info", {}).get("title") == "<service> API":
        catalog["info"] = copy.deepcopy(draft["info"])
    draft_paths = list((draft.get("paths") or {}).keys())
    existing_real_paths = [p for p in catalog["paths"] if not is_placeholder_path(p)]
    if has_api_v1_server(catalog) and not has_api_v1_server(draft) and any(p.startswith("/api/v1/") for p in draft_paths):
        if not existing_real_paths or all(p.startswith("/api/v1/") for p in existing_real_paths):
            catalog["servers"] = copy.deepcopy(draft["servers"]) if draft.get("servers") else [{"url": "/"}]
    elif draft.get("servers") and not catalog.get("servers"):
        catalog["servers"] = copy.deepcopy(draft["servers"])
    cat_has_v1_srv = has_api_v1_server(catalog)
    for path, item in (draft.get("paths") or {}).items():
        cpath = canonical_path(draft, path)
        if cat_has_v1_srv and cpath.startswith("/api/v1/"):
            target_path = cpath[len("/api/v1"):] or "/"
        else:
            target_path = cpath
        target = catalog["paths"].setdefault(target_path, {})
        for key, value in item.items():
            target[key] = copy.deepcopy(value)
    for kind in COMPONENT_KINDS:
        for name, definition in ((draft.get("components") or {}).get(kind) or {}).items():
            catalog.setdefault("components", {}).setdefault(kind, {})[name] = copy.deepcopy(definition)
    if draft.get("security") and not catalog.get("security"):
        catalog["security"] = copy.deepcopy(draft["security"])
    os.makedirs(os.path.dirname(catalog_path) or ".", exist_ok=True)
    with open(catalog_path, "w", encoding="utf-8") as handle:
        yaml.safe_dump(catalog, handle, sort_keys=False, default_flow_style=False, allow_unicode=True)
    return catalog


if mode == "lint":
    lint(load(arg1), arg1)
elif mode == "compat":
    compat(load(arg1), load(arg2))
elif mode == "merged":
    draft_doc, cat_doc = load(arg1), load(arg2)
    lint(cat_doc, arg2)
    merged(draft_doc, cat_doc)
elif mode == "merge":
    draft_doc = load(arg1)
    lint(draft_doc, arg1)
    if not failures:
        result = merge(draft_doc, arg2)
        if result is not None and not failures:
            lint(result, arg2)
            if not failures:
                merged(draft_doc, result)

if failures:
    for item in failures:
        print(f"FAIL: {item}", file=sys.stderr)
    raise SystemExit(1)
print(f"OK: openapi {mode} ({arg1}{' -> ' + arg2 if arg2 else ''})")
PY
