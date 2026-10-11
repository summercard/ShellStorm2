# -*- coding: utf-8 -*-
"""零依赖 xlsx 读取器（stdlib: zipfile + ElementTree）。

避开 openpyxl（本机偶发 OpenBLAS 内存报错）与中文路径的 MCP 路径解析问题。

用法:
    python xlsx_read.py <file.xlsx>                     # 列出所有 sheet
    python xlsx_read.py <file.xlsx> <sheet名或序号>      # 打印该 sheet 为 TSV
    python xlsx_read.py <file.xlsx> <sheet> --rows 1,2,3 # 只打印指定行（1-based）
"""

import re
import sys
import zipfile
import xml.etree.ElementTree as ET

NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
NS_R = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
NS_PKG = "{http://schemas.openxmlformats.org/package/2006/relationships}"


def _col_to_idx(ref):
    m = re.match(r"([A-Z]+)", ref or "")
    if not m:
        return 0
    n = 0
    for ch in m.group(1):
        n = n * 26 + (ord(ch) - 64)
    return n - 1


def load(path):
    z = zipfile.ZipFile(path)

    # sharedStrings
    shared = []
    if "xl/sharedStrings.xml" in z.namelist():
        root = ET.fromstring(z.read("xl/sharedStrings.xml"))
        for si in root.findall(f"{NS}si"):
            shared.append("".join(t.text or "" for t in si.iter(f"{NS}t")))

    # workbook -> sheet 名与 rId
    wb = ET.fromstring(z.read("xl/workbook.xml"))
    rels = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
    rid_to_target = {r.get("Id"): r.get("Target") for r in rels}

    sheets = []
    for sh in wb.find(f"{NS}sheets"):
        rid = sh.get(f"{NS_R}id")
        target = rid_to_target.get(rid, "")
        if target.startswith("/"):
            target = target.lstrip("/")
        elif not target.startswith("xl/"):
            target = "xl/" + target
        sheets.append((sh.get("name"), target, sh.get("state", "visible")))

    return z, shared, sheets


def read_sheet(z, shared, target):
    root = ET.fromstring(z.read(target))
    rows = {}
    maxc = 0
    for row in root.iter(f"{NS}row"):
        r = int(row.get("r"))
        cells = {}
        for c in row.findall(f"{NS}c"):
            ref = c.get("r")
            ci = _col_to_idx(ref)
            t = c.get("t")
            v = c.find(f"{NS}v")
            isel = c.find(f"{NS}is")
            if t == "s" and v is not None:
                val = shared[int(v.text)] if v.text else ""
            elif t == "inlineStr" and isel is not None:
                val = "".join(x.text or "" for x in isel.iter(f"{NS}t"))
            elif v is not None:
                val = v.text or ""
            else:
                val = ""
            if val != "":
                cells[ci] = val
                maxc = max(maxc, ci)
        if cells:
            rows[r] = cells
    return rows, maxc


def main():
    path = sys.argv[1]
    z, shared, sheets = load(path)

    if len(sys.argv) < 3:
        print("sheets:")
        for i, (name, target, state) in enumerate(sheets, 1):
            print(f"  {i}. {name}  [{state}]  -> {target}")
        return

    key = sys.argv[2]
    idx = int(key) - 1 if key.isdigit() else next(
        i for i, s in enumerate(sheets) if s[0] == key)
    name, target, _ = sheets[idx]
    rows, maxc = read_sheet(z, shared, target)
    print(f"### {name}  (rows={len(rows)}, max_col={maxc + 1})")

    want = None
    if "--rows" in sys.argv:
        spec = sys.argv[sys.argv.index("--rows") + 1]
        want = set()
        for part in spec.split(","):
            if "-" in part:
                a, b = part.split("-")
                want.update(range(int(a), int(b) + 1))
            else:
                want.add(int(part))

    for r in sorted(rows):
        if want and r not in want:
            continue
        line = []
        for c in range(maxc + 1):
            line.append((rows[r].get(c, "") or "").replace("\n", "\\n"))
        print(f"{r}\t" + "\t".join(line))


if __name__ == "__main__":
    main()
