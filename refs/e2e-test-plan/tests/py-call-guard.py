#!/usr/bin/env python3
"""py-call-guard.py <file>... : print file:line: <call> for every Python start in shell scripts that is not isolated.

kitfix-20261031-n1 (Sakura B-3 and her re-review of 942f076): the harness's own Python must run as python3 -I -S, so
it loads neither the e2e user site nor a json.py/re.py from the working folder. Checked per call, not per line, so a
line with one good and one bare call is still caught. A call is:
  - an interpreter word: python, python3, python3.13, /usr/bin/python3, "$PY", ${PYTHON}, "$HOOK_PYTHON" ... followed
    by an argument (-x, a quote, a $, a heredoc "-", or a *.py word); it must start with -I -S (or -IS / -S -I);
  - a *.py file in command position (line start, after ; & | ( ` $( <( --, or after exec/then/do/else/env/nohup/time/
    command): that runs it through its shebang (#!/usr/bin/env python3), never isolated.
  - (N-1 final round) an interpreter word in command position with no argument, or whose program comes from a
    redirection: `… | python3`, `python3 <<'PY'`, `python3 < x.py`;
  - also the spellings "${PY:-python3}" (a variable with a default) and $(command -v python3) / $(which python3).
Comment lines are skipped.

Fails closed (N-1 final round, Sakura 7e91af9): usage py-call-guard.py [--min-files N] <file>...; it prints
"py-call-guard: scanned K file(s)" on stderr. Exit 0 only when every file was read, K >= N (default 1) and nothing
was found; exit 1 when a call is printed; exit 2 on a missing or unreadable file, too few files, or a crash.
"""
import re
import sys

NAME = (r"(?<![\w.$/-])(?:(?:/[\w.-]+)*/)?python(?:[0-9]+(?:\.[0-9]+)?)?(?![\w.-])"
        r"|\$\{(?:[A-Za-z0-9]+_)*(?:PY|py|PYTHON|python)[0-9]*(?::?[-=+?][^}]*)?\}"
        r"|\$(?:[A-Za-z0-9]+_)*(?:PY|py|PYTHON|python)[0-9]*(?![\w])"
        r"|\$\((?:command[ \t]+-v|which|type[ \t]+-P)[ \t]+python[0-9.]*\)")
INTERP = re.compile(r"(?:(?:/[\w.-]+)*/)?python(?:[0-9]+(?:\.[0-9]+)?)?"
                    r"|\$\{?(?:[A-Za-z0-9]+_)*(?:PY|py|PYTHON|python)[0-9]*(?::?[-=+?][^}]*)?\}?")
CALL = re.compile(r'"?(' + NAME + r')"?[ \t]+(\S+)')
ISOLATED = re.compile(r"(?:-I[ \t]+-S|-S[ \t]+-I|-IS|-SI)(?:\s|$)")
ARGLIKE = re.compile(r"""^(?:-|<|["'$]|\S*\.py["')]*$)""")
KEYWORDS = {"--", "exec", "then", "do", "else", "if", "elif", "while", "until", "env", "nohup", "time", "command", "!"}


def words(line):
    """Shell-ish tokens of one line: ("op", ch) for ; & | ( ) < > ` and $( ... ), ("w", word) otherwise. Quotes are
    kept in the word; a $( inside double quotes opens code again, so its first word can be in command position."""
    out, cur, st, i = [], "", [], 0
    def flush():
        nonlocal cur
        if cur:
            out.append(("w", cur))
            cur = ""
    while i < len(line):
        ch, top = line[i], (st[-1] if st else None)
        if top == "'":
            cur += ch
            if ch == "'":
                st.pop()
        elif ch == "\\":
            cur += line[i:i + 2]
            i += 1
        elif ch == "$" and line[i + 1:i + 2] == "(":
            flush()
            out.append(("op", "$("))
            st.append("(")
            i += 1
        elif ch == ")" and top == "(":
            flush()
            out.append(("op", ")"))
            st.pop()
        elif ch == '"':
            cur += ch
            if top == '"':
                st.pop()
            else:
                st.append('"')
        elif top == '"':
            cur += ch
        elif ch == "'":
            cur += ch
            st.append("'")
        elif ch.isspace():
            flush()
        elif ch in ";&|()<>`":
            flush()
            out.append(("op", ch))
        else:
            cur += ch
        i += 1
    flush()
    return out


def shebang_runs(line):
    """*.py words in command position: run through their shebang."""
    toks, hits = words(line), []
    for k, (kind, w) in enumerate(toks):
        bare = w.replace('"', "").replace("'", "")
        if kind != "w" or not bare.endswith(".py") or (w[:1] in "\"'" and " " in w):
            continue
        prev = toks[k - 1] if k else None
        if prev is None or (prev[0] == "op" and prev[1] not in "<>") or (prev[0] == "w" and prev[1] in KEYWORDS):
            hits.append(w)
    return hits


def stdin_runs(line):
    """An interpreter word in command position followed by nothing or an operator: it reads its program from stdin
    (… | python3, python3 <<'PY', python3 < x.py) and so is not isolated."""
    toks, hits = words(line), []
    for k, (kind, w) in enumerate(toks):
        if kind != "w" or not INTERP.fullmatch(w.strip('"')):
            continue
        prev = toks[k - 1] if k else None
        nxt = toks[k + 1] if k + 1 < len(toks) else None
        cmdpos = prev is None or (prev[0] == "op" and prev[1] not in "<>") or (prev[0] == "w" and prev[1] in KEYWORDS)
        if cmdpos and (nxt is None or nxt[0] == "op"):
            hits.append(w)
    return hits


def check(path):
    out = []
    for n, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        if line.lstrip().startswith("#"):
            continue
        for m in CALL.finditer(line):
            arg = m.group(2)
            if not ARGLIKE.match(arg):
                continue
            rest = line[m.end(1):].lstrip('"').lstrip()
            if not ISOLATED.match(rest):
                out.append(f"{path}:{n}: {line[m.start():m.end()].strip()}")
        for w in shebang_runs(line):
            out.append(f"{path}:{n}: runs {w} through its shebang")
        for w in stdin_runs(line):
            out.append(f"{path}:{n}: {w} reads its program from stdin")
    return list(dict.fromkeys(out))


def main(argv):
    min_files, files = 1, []
    i = 0
    while i < len(argv):
        if argv[i] == "--min-files" and i + 1 < len(argv):
            min_files = int(argv[i + 1])
            i += 2
            continue
        files.append(argv[i])
        i += 1
    found, scanned = [], 0
    for p in files:
        try:
            found.extend(check(p))
        except OSError as e:
            print(f"py-call-guard: cannot read {p}: {e}", file=sys.stderr)
            return 2
        scanned += 1
    print(f"py-call-guard: scanned {scanned} file(s)", file=sys.stderr)
    if scanned < min_files:
        print(f"py-call-guard: only {scanned} file(s) scanned, at least {min_files} required", file=sys.stderr)
        return 2
    if found:
        print("\n".join(found))
        return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except SystemExit:
        raise
    except BaseException as e:  # fail closed: a crash is never a clean result
        print(f"py-call-guard: crashed: {e!r}", file=sys.stderr)
        sys.exit(2)
