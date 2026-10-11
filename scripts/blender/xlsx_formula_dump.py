# -*- coding: utf-8 -*-
"""带公式的 xlsx 读取器（stdlib）。用法:
    python xlsx_formula_dump.py <file.xlsx> <sheet> [--rows 5-17] [--formula-only] [--cols R,S]
"""

import re
import sys
import zipfile
import xml.etree.ElementTree as ET

NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
NS_R = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"


def col_to_idx(ref):
    m = re.match(r"([A-Z]+)", ref or "")
    n = 0
    for ch in (m.group(1) if m else ""):
        n = n * 26 + (ord(ch) - 64)
    return n - 1


def idx_to_col(i):
    s = ""
    i += 1
    while i:
        i, r = divmod(i - 1, 26)
        s = chr(65 + r) + s
    return s


def load(path):
    z = zipfile.ZipFile(path)
    shared = []
    if "xl/sharedStrings.xml" in z.namelist():
        root = ET.fromstring(z.read("xl/sharedStrings.xml"))
        for si in root.findall(f"{NS}si"):
            shared.append("".join(t.text or "" for t in si.iter(f"{NS}t")))
    wb = ET.fromstring(z.read("xl/workbook.xml"))
    rels = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
    rid = {r.get("Id"): r.get("Target") for r in rels}
    sheets = []
    for sh in wb.find(f"{NS}sheets"):
        t = rid.get(sh.get(f"{NS_R}id"), "")
        if t.startswith("/"):
            t = t.lstrip("/")
        elif not t.startswith("xl/"):
            t = "xl/" + t
        sheets.append((sh.get("name"), t))
    return z, shared, sheets


def read(z, shared, target):
    root = ET.fromstring(z.read(target))
    dim = None
    d = root.find(f"{NS}dimension")
    if d is not None:
        dim = d.get("ref")
    rows = {}
    for row in root.iter(f"{NS}row"):
        r = int(row.get("r"))
        for c in row.findall(f"{NS}c"):
            ref = c.get("r")
            ci = col_to_idx(ref)
            t = c.get("t")
            f = c.find(f"{NS}f")
            v = c.find(f"{NS}v")
            isel = c.find(f"{NS}is")
            if t == "s" and v is not None and v.text:
                val = shared[int(v.text)]
            elif t == "inlineStr" and isel is not None:
                val = "".join(x.text or "" for x in isel.iter(f"{NS}t"))
            else:
                val = v.text if v is not None else ""
            if f is None and (val is None or val == ""):
                continue
            rows.setdefault(r, {})[ci] = {
                "formula": ("=" + (f.text or "") if f is not None else None),
                "value": val,
            }
    return rows, dim


path, sheet_key = sys.argv[1], sys.argv[2]
z, shared, sheets = load(path)
name, target = next(s for s in sheets if s[0] == sheet_key) if not sheet_key.isdigit() \
    else sheets[int(sheet_key) - 1]
rows, dim = read(z, shared, target)

want = None
if "--rows" in sys.argv:
    spec = sys.argv[sys.argv.index("--rows") + 1]
    want = set()
    for p in spec.split(","):
        if "-" in p:
            a, b = p.split("-")
            want.update(range(int(a), int(b) + 1))
        else:
            want.add(int(p))
cols = None
if "--cols" in sys.argv:
    cols = {col_to_idx(c.strip()) for c in sys.argv[sys.argv.index("--cols") + 1].split(",")}
fonly = "--formula-only" in sys.argv

print(f"### {name}  dim={dim}  data_rows={sorted(rows)}")
for r in sorted(rows):
    if want and r not in want:
        continue
    for ci in sorted(rows[r]):
        if cols and ci not in cols:
            continue
        cell = rows[r][ci]
        if fonly and not cell["formula"]:
            continue
        ref = f"{idx_to_col(ci)}{r}"
        if cell["formula"]:
            print(f"{ref}\tFORMULA\t{cell['formula']}\t|cached={cell['value']!r}")
        else:
            print(f"{ref}\tVALUE\t{str(cell['value'])[:200]!r}")
