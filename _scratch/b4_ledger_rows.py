# -*- coding: utf-8 -*-
"""读台账指定 sheet 的指定行（全部列）与指定列的表头，用于判定列语义。

用法: python b4_ledger_rows.py <sheet.xml 成员> <行号,行号,...>
"""
from __future__ import annotations

import re
import sys
import zipfile
from pathlib import Path

PROJECT = Path(r"I:/工作项目/shellstrom2/ShellStorm2")
LEDGER = PROJECT / "assets/registry/ShellStorm2_美术资产台账_v001.xlsx"

CELL = re.compile(r"<(?:x:)?c\b([^>]*?)>(.*?)</(?:x:)?c>", re.S)


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
    member = sys.argv[1]
    rows = {int(x) for x in sys.argv[2].split(",") if x.strip()}
    with zipfile.ZipFile(LEDGER) as zin:
        blobs = {n: zin.read(n) for n in zin.namelist()}
    sst = re.findall(r"<(?:x:)?si>(.*?)</(?:x:)?si>",
                     blobs["xl/sharedStrings.xml"].decode("utf8", "ignore"), re.S)
    txt = blobs[member].decode("utf8")

    want = set(rows) | {1, 2}  # 总是带表头
    data: dict[int, dict[int, str]] = {}
    for m in CELL.finditer(txt):
        attrs, inner = m.group(1), m.group(2)
        r = re.search(r'r="([A-Z]+)(\d+)"', attrs)
        if not r:
            continue
        rr = int(r.group(2))
        if rr not in want:
            continue
        t = re.search(r't="([^"]*)"', attrs)
        tval = t.group(1) if t else ""
        if tval == "s":
            vm = re.search(r"<(?:x:)?v>(\d+)</(?:x:)?v>", inner)
            val = sst_text(sst[int(vm.group(1))]) if vm and int(vm.group(1)) < len(sst) else ""
        else:
            val = cell_text(inner)
        if val:
            data.setdefault(rr, {})[col_idx(r.group(1))] = val

    for rr in sorted(data):
        print(f"---- 行 {rr} ----")
        for ci in sorted(data[rr]):
            v = data[rr][ci]
            if len(v) > 220:
                v = v[:220] + " …"
            print(f"   {idx_col(ci)}{rr}: {v}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
