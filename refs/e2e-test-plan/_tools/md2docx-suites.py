#!/usr/bin/env python3
"""Markdown -> docx for the suite documents. Handles headings, paragraphs, bullet/numbered lists,
fenced code, pipe tables (with \\| escapes and | inside `code`), **bold**, `code`."""
import re, sys
from docx import Document
from docx.shared import Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

def split_row(line):
    s = line.strip()
    if s.startswith("|"): s = s[1:]
    if s.endswith("|") and not s.endswith("\\|"): s = s[:-1]
    cells, cur, in_code, i = [], "", False, 0
    while i < len(s):
        ch = s[i]
        if ch == "\\" and i + 1 < len(s) and s[i+1] == "|":
            cur += "|"; i += 2; continue
        if ch == "`": in_code = not in_code
        if ch == "|" and not in_code:
            cells.append(cur.strip()); cur = ""
        else:
            cur += ch
        i += 1
    cells.append(cur.strip())
    return cells

INLINE = re.compile(r"(\*\*[^*]+\*\*|`[^`]+`)")
def add_inline(par, text, size=None, bold=False):
    for part in INLINE.split(text):
        if not part: continue
        if part.startswith("`") and part.endswith("`") and len(part) > 1:
            r = par.add_run(part[1:-1]); r.font.name = "Consolas"; r._element.rPr.rFonts.set(qn("w:eastAsia"), "Consolas")
            r.font.color.rgb = RGBColor(0x8B, 0x1A, 0x1A)
            if bold: r.bold = True
        elif part.startswith("**") and part.endswith("**") and len(part) > 4:
            add_inline(par, part[2:-2], size, True); continue
        else:
            r = par.add_run(part.replace("\\|", "|"))
            if bold: r.bold = True
        if size: r.font.size = Pt(size)

def shade(cell, hexcolor):
    tcPr = cell._element.get_or_add_tcPr(); shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear"); shd.set(qn("w:color"), "auto"); shd.set(qn("w:fill"), hexcolor); tcPr.append(shd)

def convert(src, dst):
    lines = open(src, encoding="utf-8").read().splitlines()
    doc = Document()
    st = doc.styles["Normal"]; st.font.name = "Calibri"; st.font.size = Pt(10)
    i = 0
    while i < len(lines):
        ln = lines[i]
        if ln.startswith("```"):
            i += 1; buf = []
            while i < len(lines) and not lines[i].startswith("```"):
                buf.append(lines[i]); i += 1
            i += 1
            p = doc.add_paragraph(); r = p.add_run("\n".join(buf)); r.font.name = "Consolas"; r.font.size = Pt(7.5)
            r._element.rPr.rFonts.set(qn("w:eastAsia"), "Consolas")
            pPr = p._element.get_or_add_pPr(); shd = OxmlElement("w:shd"); shd.set(qn("w:val"), "clear"); shd.set(qn("w:fill"), "F2F2F2"); pPr.append(shd)
            continue
        m = re.match(r"^(#{1,6})\s+(.*)$", ln)
        if m:
            lvl = min(len(m.group(1)), 4)
            h = doc.add_heading(level=lvl); add_inline(h, m.group(2)); i += 1; continue
        if ln.strip().startswith("|") and i + 1 < len(lines) and re.match(r"^\s*\|?\s*:?-{2,}", lines[i+1]):
            hdr = split_row(ln); i += 2; rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append(split_row(lines[i])); i += 1
            n = len(hdr)
            t = doc.add_table(rows=1 + len(rows), cols=n); t.style = "Table Grid"
            for j, c in enumerate(hdr):
                cell = t.rows[0].cells[j]; cell.text = ""; add_inline(cell.paragraphs[0], c, 8); shade(cell, "D9E2F3")
                for r in cell.paragraphs[0].runs: r.bold = True
            for k, row in enumerate(rows, 1):
                row = (row + [""] * n)[:n] if len(row) <= n else row[:n-1] + [" | ".join(row[n-1:])]
                for j, c in enumerate(row):
                    cell = t.rows[k].cells[j]; cell.text = ""; add_inline(cell.paragraphs[0], c, 8)
            doc.add_paragraph()
            continue
        m = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)$", ln)
        if m:
            style = "List Number" if m.group(2)[0].isdigit() else "List Bullet"
            if len(m.group(1)) >= 2: style += " 2"
            p = doc.add_paragraph(style=style); add_inline(p, m.group(3)); i += 1; continue
        if not ln.strip():
            i += 1; continue
        buf = [ln]; i += 1
        while i < len(lines) and lines[i].strip() and not re.match(r"^(#|```|\s*\||\s*([-*]|\d+\.)\s)", lines[i]):
            buf.append(lines[i]); i += 1
        p = doc.add_paragraph(); add_inline(p, " ".join(x.strip() for x in buf))
    doc.save(dst)

if __name__ == "__main__":
    for s in sys.argv[1:]:
        d = s[:-3] + ".docx"; convert(s, d); print(d)
