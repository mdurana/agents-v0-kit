#!/bin/sh
# classify-change.sh — decide from the diff, not from the agent that made it, whether a
# change can use the Trivial maintenance lane (workflow-orchestration.mdc Change tiers).
#
# Usage: sh .agents-v0/ci/classify-change.sh <base> [<head>] [--require-trivial] [--max-lines N]
#   <base>            commit or ref to compare from
#   <head>            commit or ref to compare to; omitted = the working tree (staged, unstaged, new files)
#   --require-trivial exit 1 unless the change is eligible for the Trivial lane
#   --max-lines N     exit 1 when more than N source lines changed (docs, lockfiles, and
#                     docs/build|verify|maintain evidence are not counted)
#
# Output (key=value, one per line): class, security-surface, schema, major-bump, files,
# changed-lines, trivial-eligible, then one "reason:" line per disqualifier.
#   class=docs-only            only documentation changed
#   class=dependency-version   only version numbers in build files or lockfiles changed
#   class=code                 anything else
# Trivial-eligible = class docs-only or dependency-version, no security surface, no schema,
# no major version bump, no delivery artifact (docs/requirements, docs/milestones, the
# onboarding report), at most TRIVIAL_MAX_FILES files (default 10) and
# TRIVIAL_MAX_LINES source lines (default 200).
# Security surface is deliberately broad: a path or a changed line that touches
# authentication, authorization, sessions, uploads, controllers, routes, CORS, or deployment
# configuration. When in doubt it says yes.

set -eu
export PYTHONDONTWRITEBYTECODE=1

base="${1:-}"
if [ -z "$base" ]; then
  printf 'usage: %s <base> [<head>] [--require-trivial] [--max-lines N]\n' "$0" >&2
  exit 1
fi
shift
head=""
require_trivial=0
max_lines=""
while [ $# -gt 0 ]; do
  case "$1" in
    --require-trivial) require_trivial=1; shift ;;
    --max-lines) [ $# -ge 2 ] || { printf 'usage: --max-lines N\n' >&2; exit 1; }; max_lines="$2"; shift 2 ;;
    -*) printf 'FAIL: unknown option %s\n' "$1" >&2; exit 1 ;;
    *) head="$1"; shift ;;
  esac
done
command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

DIR="$(cd "$(dirname "$0")" && pwd)"
BASE="$base" HEAD="$head" REQUIRE_TRIVIAL="$require_trivial" MAX_LINES="$max_lines" PACKLIB_DIR="$DIR" python3 - <<'PY'
import os
import re
import subprocess
import sys

base, head = os.environ["BASE"], os.environ["HEAD"]
require_trivial = os.environ["REQUIRE_TRIVIAL"] == "1"
max_lines = os.environ["MAX_LINES"]
trivial_files = int(os.environ.get("TRIVIAL_MAX_FILES") or 10)
trivial_lines = int(os.environ.get("TRIVIAL_MAX_LINES") or 200)


def git(*args):
    proc = subprocess.run(["git", *args], capture_output=True, text=True)
    if proc.returncode != 0:
        print(f"FAIL: git {' '.join(args)}: {proc.stderr.strip()}", file=sys.stderr)
        raise SystemExit(1)
    return proc.stdout


span = [base, head] if head else [base]
names = [n for n in git("diff", "--name-only", *span).splitlines() if n]
if not head:
    names += [n for n in git("ls-files", "--others", "--exclude-standard").splitlines() if n and n not in names]

EVIDENCE = re.compile(r"^docs/agents-v0/(maintain|verify|build)/")
DELIVERY = re.compile(r"^(docs/agents-v0/(requirements|milestones)/|docs/agents-v0/onboarding/report\.md$)")
DOC = re.compile(r"(^docs/)|(\.(md|mdc|txt|adoc)$)|(^|/)(README|CHANGELOG|LICENSE)(\.[a-z]+)?$", re.I)
LOCK = re.compile(
    r"(^|/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|gradle\.lockfile|poetry\.lock|"
    r"uv\.lock|Pipfile\.lock|Cargo\.lock|go\.sum|packages\.lock\.json|composer\.lock|Gemfile\.lock)$"
)
BUILD = re.compile(
    r"(^|/)(pom\.xml|build\.gradle(\.kts)?|gradle\.properties|package\.json|libs\.versions\.toml|"
    r"go\.mod|pyproject\.toml|requirements([\w.-]*)\.txt|Pipfile|Cargo\.toml|"
    r"Directory\.Build\.props|Directory\.Packages\.props|[^/]+\.csproj)$"
)

pack_detect = []
packlib_dir = os.environ.get("PACKLIB_DIR") or ""
if packlib_dir and os.path.isfile(os.path.join(packlib_dir, "packlib.py")):
    sys.path.insert(0, packlib_dir)
    import packlib
    for m in packlib.all_manifests():
        pack_detect.extend(m.get("detect") or [])


def is_build_file(path):
    if BUILD.search(path):
        return True
    bname = os.path.basename(path)
    for pat in pack_detect:
        if pat.startswith("*.") and bname.endswith(pat[1:]):
            return True
        if bname == pat:
            return True
    return False


SEC_PATH = re.compile(r"(secur|auth|login|logout|session|jwt|oauth|saml|upload|cors|csrf|permission|rbac|acl|"
                      r"hooks\.server|\+server\.|\+page\.server|\+layout\.server|nginx.*\.conf|^Dockerfile|/Dockerfile|"
                      r"\.gitlab-ci|\.github/workflows|application[\w.-]*\.(ya?ml|properties)$|appsettings[\w.-]*\.json$)", re.I)
SEC_LINE = re.compile(r"@(PreAuthorize|PostAuthorize|Secured|RolesAllowed|RestController|Controller|RequestMapping|"
                      r"GetMapping|PostMapping|PutMapping|PatchMapping|DeleteMapping|CrossOrigin|EnableWebSecurity|EnableMethodSecurity|UseGuards|Public)\b|"
                      r"\[(Authorize|AllowAnonymous|HttpGet|HttpPost|HttpPut|HttpPatch|HttpDelete)\b|"
                      r"\b(RequireAuthorization|AllowAnonymous|AuthMiddleware|RequireRole|permission_classes|login_required)\b|"
                      r"\b(Depends|Security)\(|"
                      r"permitAll|permit-all|csrf|HttpSecurity|SecurityFilterChain|JwtDecoder|MultipartFile|"
                      r"localStorage|sessionStorage|document\.cookie|Authorization|setAllowedOrigins", re.I)
SCHEMA_PATH = re.compile(r"(db/migrations?|db/changelog|alembic/versions|/migrations/|schema\.prisma$|\.sql$)", re.I)
SCHEMA_LINE = re.compile(r"@Entity\b|@Table\b|DbSet<|__tablename__|createTable|alter table|drop table", re.I)
VERSION_LINE = re.compile(
    r"^\s*(<([\w.-]*version[\w.-]*)>[^<]*</\2>|<version>[^<]*</version>|[\w.-]*[vV]ersion\s*[=:]\s*['\"]?[\w.\-+]+['\"]?,?"
    r"|<(PackageReference|PackageVersion)\s+Include=\"[^\"]+\"\s+Version=\"[\w.\-+]+\"\s*/>"
    r"|\"[@\w/.\-]+\":\s*\"[\^~<>=]*\s*\d[\w.\-+|<>=^~ *]*\",?"
    r"|\s*(api|implementation|compileOnly|runtimeOnly|testImplementation|classpath)\s*\(?['\"][\w.\-]+:[\w.\-]+:[\w.\-+]+['\"]\)?"
    r"|(?:require\s+)?[A-Za-z0-9_.\-/]+\s+v\d+\.\d+\.\d+[\w.\-+]*(\s+//\s*indirect)?"
    r"|[A-Za-z0-9_.\-]+(\[[A-Za-z0-9_,.\-]+\])?\s*(==|~=|>=|<=|\^)\s*\d+\.\d+[\w.\-+]*"
    r"|[\w.\-]+\s*=\s*\"[\w.\-+]+\"|\s*id\s+['\"][\w.\-]+['\"]\s+version\s+['\"][\w.\-+]+['\"])\s*$")
NUMBER = re.compile(r"\d+\.\d+(?:\.\d+)?")

doc_files, dep_files, other_files = [], [], []
delivery, security, schema, major = False, False, False, False
src_lines = 0
reasons = []

for name in names:
    if EVIDENCE.match(name):
        continue
    if DELIVERY.match(name):
        delivery = True
        reasons.append(f"delivery artifact changed: {name}")
        continue
    if DOC.search(name):
        doc_files.append(name)
        continue
    diff = git("diff", "-U0", *span, "--", name)
    if not head and not diff:
        try:
            with open(name, encoding="utf-8", errors="replace") as handle:
                diff = "".join(f"+{ln}" for ln in handle)
        except OSError:
            diff = ""
    added = [ln[1:] for ln in diff.splitlines() if ln.startswith("+") and not ln.startswith("+++")]
    removed = [ln[1:] for ln in diff.splitlines() if ln.startswith("-") and not ln.startswith("---")]
    changed = added + removed
    if LOCK.search(name):
        dep_files.append(name)
        continue
    if SEC_PATH.search(name) or any(SEC_LINE.search(ln) for ln in changed):
        security = True
        reasons.append(f"security surface: {name}")
    if SCHEMA_PATH.search(name) or any(SCHEMA_LINE.search(ln) for ln in changed):
        schema = True
        reasons.append(f"schema: {name}")
    src_lines += len(changed)
    # A bump replaces lines one for one; an added or removed line is a new or dropped dependency.
    if (is_build_file(name) and changed and len(added) == len(removed)
            and all(VERSION_LINE.match(ln) or not ln.strip() for ln in changed)):
        dep_files.append(name)
        old = [v for ln in removed for v in NUMBER.findall(ln)]
        new = [v for ln in added for v in NUMBER.findall(ln)]
        if any(o.split(".")[0] != n.split(".")[0] for o, n in zip(old, new)):
            major = True
            reasons.append(f"major version bump: {name}")
    else:
        other_files.append(name)

if other_files:
    cls = "code"
elif dep_files:
    cls = "dependency-version"
elif doc_files:
    cls = "docs-only"
else:
    cls = "docs-only"
files = len([n for n in names if not EVIDENCE.match(n)])

eligible = (cls in ("docs-only", "dependency-version") and not security and not schema and not major
            and not delivery and files <= trivial_files and src_lines <= trivial_lines)
if cls == "code":
    reasons.append("class code: files other than docs and version-only build changes")
if files > trivial_files:
    reasons.append(f"{files} files exceed TRIVIAL_MAX_FILES={trivial_files}")
if src_lines > trivial_lines:
    reasons.append(f"{src_lines} changed source lines exceed TRIVIAL_MAX_LINES={trivial_lines}")

print(f"class={cls}")
print(f"security-surface={'yes' if security else 'no'}")
print(f"schema={'yes' if schema else 'no'}")
print(f"major-bump={'yes' if major else 'no'}")
print(f"files={files}")
print(f"changed-lines={src_lines}")
print(f"trivial-eligible={'yes' if eligible else 'no'}")
for item in sorted(set(reasons)):
    print(f"reason: {item}")

if require_trivial and not eligible:
    print("FAIL: the change is not eligible for the Trivial lane; use Tier standard (or a feature artifact)", file=sys.stderr)
    raise SystemExit(1)
if max_lines.isdigit() and src_lines > int(max_lines):
    print(f"FAIL: {src_lines} changed source lines exceed --max-lines {max_lines}; use a feature artifact (Intake, Design, Build)", file=sys.stderr)
    raise SystemExit(1)
PY
