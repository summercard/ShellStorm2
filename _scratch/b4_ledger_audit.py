# -*- coding: utf-8 -*-
"""全台账审计：找出「运行路径列里、指向磁盘不存在文件」的单元格。

只读。目的：B4 改名/删除后，把所有指向已消失路径的登记格找全，
按 sheet!列 聚合，并用表头判定该列是否为「运行路径列」（可改）还是「记录列」（不改）。

判据：单元格文本含 assets/ 且含 _v\\d{3}\\.(glb|tscn)，且该路径在磁盘不存在。
"""
from __future__ import annotations

import re
import zipfile
from pathlib import Path

PROJECT = Path(r"I:/工作项目/shellstrom2/ShellStorm2")
LEDGER = PROJECT / "assets/registry/ShellStorm2_美术资产台账_v001.xlsx"

CELL = re.compile(r"<(?:x:)?c\b([^>]*?)>(.*?)</(?:x:)?c>", re.S)
PATH = re.compile(r"assets/[A-Za-z0-9_./\u4e00-\u9fff\-]*?_v\d{3}\.(?:glb|tscn)")


def sst_text(si: str) -> str:
    return "".join(re.findall(r"<(?:x:)?t[^>]*>(.*?)</(?:x:)?t>", si, re.S))


def cell_text(inner: str) -> str:
    ts = re.findall(r"<(?:x:)?t[^>]*>(.*?)</(?:x:)?t>", inner, re.S)
    if ts:
        return "".join(ts)
    v = re.search(r"<(?:x:)?v>(.*?)</(?:x:)?v>", inner, re.S)
    return v.group(1) if v else ""


def col_idx(letters: str) -> int:
    n = 0
    for ch in letters:
        n = n * 26 + (ord(ch) - 64)
    return n


def idx_col(n: int) -> str:
    s = ""
    while n:
        n, r = divmod(n - 1, 26)
        s = chr(65 + r) + s
    return s


def main() -> int:
    with zipfile.ZipFile(LEDGER) as zin:
        members = zin.namelist()
        blobs = {n: zin.read(n) for n in members}

    rels = blobs["xl/_rels/workbook.xml.rels"].decode("utf8")
    rid2tgt = {}
    for tag in re.findall(r"<(?:x:)?Relationship\b[^>]*/?>", rels):
        tid = re.search(r'Id="([^"]+)"', tag)
        tgt = re.search(r'Target="([^"]+)"', tag)
        if tid and tgt:
            rid2tgt[tid.group(1)] = tgt.group(1)
    wb = blobs["xl/workbook.xml"].decode("utf8")
    name2member = {}
    for tag in re.findall(r"<(?:x:)?sheet\b[^>]*/?>", wb):
        nm = re.search(r'name="([^"]+)"', tag)
        rid = re.search(r'r:id="([^"]+)"', tag)
        if not nm or not rid:
            continue
        t = rid2tgt.get(rid.group(1), "")
        if not t:
            continue
        norm = t.lstrip("/")
        if not norm.startswith("xl/"):
            norm = "xl/" + norm
        name2member[nm.group(1)] = norm

    sst = re.findall(r"<(?:x:)?si>(.*?)</(?:x:)?si>",
                     blobs["xl/sharedStrings.xml"].decode("utf8", "ignore"), re.S)

    stale: list[tuple[str, str, int, str, str]] = []   # sheet, col, row, path, fulltext
    headers: dict[tuple[str, str], str] = {}

    for name, member in name2member.items():
        if member not in members:
            continue
        txt = blobs[member].decode("utf8")
        cells: dict[tuple[int, int], str] = {}
        for m in CELL.finditer(txt):
            attrs, inner = m.group(1), m.group(2)
            r = re.search(r'r="([A-Z]+)(\d+)"', attrs)
            if not r:
                continue
            t = re.search(r't="([^"]*)"', attrs)
            tval = t.group(1) if t else ""
            if tval == "s":
                vm = re.search(r"<(?:x:)?v>(\d+)</(?:x:)?v>", inner)
                val = sst_text(sst[int(vm.group(1))]) if vm and int(vm.group(1)) < len(sst) else ""
            else:
                val = cell_text(inner)
            if val:
                cells[(int(r.group(2)), col_idx(r.group(1)))] = val
        # 表头：取前 3 行
        for (rr, cc), val in cells.items():
            if rr <= 3:
                headers.setdefault((name, idx_col(cc)), val.strip()[:34])
        for (rr, cc), val in sorted(cells.items()):
            if rr <= 3:
                continue
            for p in set(PATH.findall(val)):
                if not (PROJECT / p).exists():
                    stale.append((name, idx_col(cc), rr, p, val.strip()))

    print("=== 表头参照（前 3 行）===")
    for (nm, col) in sorted(headers):
        print(f"   {nm}!{col}  =  {headers[(nm, col)]}")

    print(f"\n=== 指向磁盘不存在文件的带版本格 {len(stale)} ===")
    for nm, col, rr, p, full in sorted(stale, key=lambda x: (x[0], x[1], x[2])):
        print(f"   [{nm}!{col}{rr}]  ->  {p}")
        if len(full) > len(p):
            print(f"        (整格) {full[:180]}")

    print("\n=== 按 sheet!列 聚合 ===")
    agg: dict[str, int] = {}
    for nm, col, _rr, _p, _f in stale:
        agg[f"{nm}!{col}"] = agg.get(f"{nm}!{col}", 0) + 1
    for k in sorted(agg):
        print(f"   {k}: {agg[k]}   (表头: {headers.get(tuple(k.split('!')), '?')})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
