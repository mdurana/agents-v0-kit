#!/usr/bin/env python3
"""next-story.py — derive story order from the plan the agent wrote. Never hard-codes story ids.

Usage:
  next-story.py map  <workspace>                 -> TSV: order id slug deps size surface manifest   (exit 2 on a broken plan)
  next-story.py next <workspace> [<released ids>]  -> TSV row of the first story, in roadmap order, that is not in
                                                    <released ids> and whose dependencies are all in <released ids>
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
    if len(sys.argv) < 3 or sys.argv[1] not in ("map", "next"):
        print(__doc__, file=sys.stderr); sys.exit(64)
    R = rows(sys.argv[2])
    if not R:
        print("NO STORIES", file=sys.stderr); sys.exit(2)
    if sys.argv[1] == "map":
        for i, r in enumerate(R, 1):
            print(tsv(i, r))
        sys.exit(0)
    done = set(x.upper() for x in " ".join(sys.argv[3:]).replace(",", " ").split())
    for i, r in enumerate(R, 1):
        if r["id"] not in done and all(d in done for d in r["deps"]):
            print(tsv(i, r)); sys.exit(0)
    print("NONE ELIGIBLE", file=sys.stderr); sys.exit(1)
