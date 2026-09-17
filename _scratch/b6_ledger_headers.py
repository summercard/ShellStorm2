# -*- coding: utf-8 -*-
"""转储台账指定 sheet 的表头行与指定格，用于判定「运行路径列」vs「历史/说明列」。

只读。共享字符串（t="s"）与内联字符串（inlineStr / t="str"）都解析。
"""
from __future__ import annotations

import re
import sys
import zipfile
from pathlib import Path

PROJECT = Path(r"I:/工作项目/shellstrom2/ShellStorm2")
LEDGER = PROJECT / "assets/registry/ShellStorm2_美术资产台账_v001.xlsx"

CELL = re.compile(r"<(?:x:)?c\b([^>]*?)>(.*?)</(?:x:)?c>", re.S)
ROW = re.compile(r"<(?:x:)?row\b([^>]*?)>(.*?)</(?:x:)?row>", re.S)


def sst_text(si: str) -> str:
    return "".join(re.findall(r"<(?:x:)?t[^>]*>(.*?)</(?:x:)?t>", si, re.S))


def cell_text(inner: str) -> str:
    ts = re.findall(r"<(?:x:)?t[^>]*>(.*?)</(?:x:)?t>", inner, re.S)
    if ts:
        return "".join(ts)
    v = re.search(r"<(?:x:)?v>(.*?)</(?:x:)?v>", inner, re.S)
    return v.group(1) if v else ""


def main() -> int:
    member = sys.argv[1] if len(sys.argv) > 1 else "xl/worksheets/sheet17.xml"
    want_rows = [int(x) for x in sys.argv[2].split(",")] if len(sys.argv) > 2 else [1, 2, 3]
    with zipfile.ZipFile(LEDGER) as z:
        blob = z.read(member).decode("utf8")
        sst = []
        if "xl/sharedStrings.xml" in z.namelist():
            sst = re.findall(r"<(?:x:)?si>(.*?)</(?:x:)?si>",
                             z.read("xl/sharedStrings.xml").decode("utf8", "ignore"), re.S)

    print(f"### {member}")
    for rm in ROW.finditer(blob):
        rn = re.search(r'r="(\d+)"', rm.group(1))
        if not rn:
            continue
        row = int(rn.group(1))
        if row not in want_rows:
            continue
        print(f"\n--- row {row} ---")
        for cm in CELL.finditer(rm.group(2)):
            attrs, inner = cm.group(1), cm.group(2)
            ref = re.search(r'r="([A-Z]+)\d+"', attrs)
            if not ref:
                continue
            tv = re.search(r't="([^"]*)"', attrs)
            tval = tv.group(1) if tv else ""
            if tval == "s":
                vm = re.search(r"<(?:x:)?v>(\d+)</(?:x:)?v>", inner)
                txt = sst_text(sst[int(vm.group(1))]) if vm else ""
            else:
                txt = cell_text(inner)
            txt = txt.replace("\n", "\\n")
            print(f"   {ref.group(1)}: [{tval}] {txt[:160]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
