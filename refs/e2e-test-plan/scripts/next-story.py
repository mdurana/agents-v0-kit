#!/usr/bin/env python3
"""next-story.py — derive story order from the plan the agent wrote. Never hard-codes story ids.

Usage:
  next-story.py map  <workspace>                 -> TSV: order id slug deps size surface manifest   (exit 2 on a broken plan)
  next-story.py next <workspace> [<released ids>]  -> TSV row of the first story, in roadmap order, that is not in
                                                    <released ids> and whose dependencies are all in <released ids>
  next-story.py chain <workspace> <surface> [<released ids>]
                                                 -> TSV rows: every story the TARGET depends on (directly or not) that
                                                    is not in <released ids>, in roadmap order, then the TARGET itself.
                                                    TARGET = the first story in roadmap order whose Surface cell holds
                                                    the word <surface> (case-insensitive, e.g. "frontend").
                                                    Exit 2 when no story has that surface. (HARNESS-FIX 2026-10-29)
Roadmap order = milestone manifests sorted by file name (p0-*, p1-*, ...), then row order inside each manifest.
A story row is a row of a pipe table whose header has "Story ID" and "Dependency" columns; the slug is the file name
of its "Feature artifact" cell (docs/agents-v0/requirements/<slug>.md), else the lowercased id + title.
"""
import glob, os, re, sys

def rows(ws):
    out, seen = [], set()
    mdir = os.path.join(ws, "docs/agents-v0/milestones")
    for m in sorted(glob.glob(os.path.join(mdir, "*.md"))):
        b = os.path.basename(m)
        if b.startswith("_") or b == "plan.md" or b.endswith(".phase-result.md"):
            continue
        t = re.sub(r"<!--.*?-->", "", open(m, encoding="utf-8").read(), flags=re.S)
        h = None
        for l in t.splitlines():
            s = l.strip()
            if not s.startswith("|"):
                h = None; continue
            c = [x.strip() for x in s.strip("|").split("|")]
            low = [x.lower() for x in c]
            if "story id" in low and "dependency" in low:
                h = low; continue
            if h is None or set(s.replace("|", "").strip()) <= set("-: "):
                continue
            r = dict(zip(h, c))
            sid = r.get("story id", "").strip("`* ").upper()
            if not sid:
                continue
            if sid in seen:
                print("DUPLICATE", sid, file=sys.stderr); sys.exit(2)
            seen.add(sid)
            deps = [d.strip("`* ").upper() for d in re.split(r"[,;/ ]+", r.get("dependency", ""))
                    if d.strip("`* ") and d.strip("`* ").upper() not in ("—", "-", "NONE", "N/A", "NA")]
            art = r.get("feature artifact", "")
            mm = re.search(r"requirements/([a-z0-9][a-z0-9-]*)\.md", art)
            slug = mm.group(1) if mm else re.sub(r"[^a-z0-9]+", "-", (sid + "-" + r.get("title", "")).lower()).strip("-")
            out.append(dict(id=sid, slug=slug, deps=deps, size=r.get("size", ""), surface=r.get("surface", ""), manifest=b))
    ids = {r["id"] for r in out}
    for r in out:
        for d in r["deps"]:
            if d not in ids:
                print("UNKNOWN DEP", r["id"], "->", d, file=sys.stderr); sys.exit(2)
    return out

def tsv(i, r):
    return "\t".join([str(i), r["id"], r["slug"], ",".join(r["deps"]) or "-", r["size"], r["surface"], r["manifest"]])

if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in ("map", "next", "chain") or (sys.argv[1] == "chain" and len(sys.argv) < 4):
        print(__doc__, file=sys.stderr); sys.exit(64)
    R = rows(sys.argv[2])
    if not R:
        print("NO STORIES", file=sys.stderr); sys.exit(2)
    if sys.argv[1] == "map":
        for i, r in enumerate(R, 1):
            print(tsv(i, r))
        sys.exit(0)
    if sys.argv[1] == "chain":
        # HARNESS-FIX 2026-10-29 (chain mode): the e2e run can stop at the first story of one surface
        # (TARGET_SURFACE=frontend). Plain words: find the first frontend story in roadmap order, list every story it
        # needs (its dependencies, their dependencies, ...) in roadmap order, then the story itself. Stories already
        # released are left out. The roadmap order is the same order "next" uses, so each listed story's
        # dependencies are always listed (or released) before it.
        want = sys.argv[3].strip().lower()
        done = set(x.upper() for x in " ".join(sys.argv[4:]).replace(",", " ").split())
        pos = {r["id"]: i for i, r in enumerate(R, 1)}
        by_id = {r["id"]: r for r in R}
        target = next((r for r in R if want and re.search(r"(^|[^a-z0-9])" + re.escape(want) + r"($|[^a-z0-9])",
                                                          r["surface"].strip("`* ").lower())), None)
        if target is None:
            print("NO STORY WITH SURFACE", want, file=sys.stderr); sys.exit(2)
        need, stack = set(), list(target["deps"])
        while stack:
            d = stack.pop()
            if d in need or d in done:
                continue
            need.add(d); stack.extend(by_id[d]["deps"])
        for sid in sorted(need, key=lambda x: pos[x]):
            print(tsv(pos[sid], by_id[sid]))
        print(tsv(pos[target["id"]], target)); sys.exit(0)
    done = set(x.upper() for x in " ".join(sys.argv[3:]).replace(",", " ").split())
    for i, r in enumerate(R, 1):
        if r["id"] not in done and all(d in done for d in r["deps"]):
            print(tsv(i, r)); sys.exit(0)
    print("NONE ELIGIBLE", file=sys.stderr); sys.exit(1)
