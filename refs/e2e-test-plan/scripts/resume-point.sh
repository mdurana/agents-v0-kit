#!/usr/bin/env bash
# resume-point.sh <kit checkout> <old kit commit or tree id> <failed step>
# Prints the earliest step that must run again after a kit fix, so the resumed run never mixes work produced by the
# old kit with a fix that would have produced that work differently. Reasons go to stderr, one line per changed file.
#   step 2  the fix changes how the workspace is created: bootstrap/install/scaffold scripts, the app template, the
#           pack starters, or a seed-only template (a templates/<path> that install.sh --update does NOT refresh,
#           so an existing workspace would never receive the change)
#   step 3  the fix changes the program phases (roadmap, architecture, plan) that step 3 ran once
#   else    the failed step itself (the change reaches the workspace through install.sh --update)
# The result is never later than <failed step>. Compares the kit's working tree (HEAD + uncommitted patch) with the old
# kit as it was used (run-plan.sh passes a tree id of the old commit plus any earlier patch), so only this fix counts.
set -u
KITD="$1"; OLD="$2"; FAILED="$3"; best="$FAILED"
inst="$KITD/scripts/install.sh"
lower(){ [ "$1" -lt "$best" ] && best="$1"; }
git -C "$KITD" diff --name-only "$OLD" -- . > /tmp/resume-point.$$ || { echo "resume-point: git diff against $OLD failed" >&2; exit 1; }
git -C "$KITD" ls-files --others --exclude-standard >> /tmp/resume-point.$$
while IFS= read -r f; do
  [ -n "$f" ] || continue; s="$FAILED"
  case "$f" in
    scripts/bootstrap-greenfield.sh|scripts/install.sh|scripts/scaffold-app-template.sh|scripts/pack-app-template.sh|templates/app/*|core/*/starters/*) s=2;;
    *v0-roadmap.md|*v0-architecture.md|*v0-plan.md|*program-roadmap*|*program-architecture*|*program-planning*|*program-planner*|templates/docs/agents-v0/roadmap/*) s=3;;
    templates/*) rel="${f#templates/}"; grep -qF -- "$rel" "$inst" 2>/dev/null || s=2;;
  esac
  [ "$s" -le "$FAILED" ] || s="$FAILED"
  echo "resume-point: $f -> step $s" >&2; lower "$s"
done < /tmp/resume-point.$$
rm -f /tmp/resume-point.$$
echo "$best"
