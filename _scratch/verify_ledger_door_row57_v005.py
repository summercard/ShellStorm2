# -*- coding: utf-8 -*-
"""核对 v005 账本补丁：只动了第 57 行的 M/N/O/P/T/W/Y 七格，其余全部逐字节未变。

对比对象 = 补丁前备份（.bak_tower_wall_door_5m_v005）与当前账本。
"""
import re
import sys
import zipfile
from pathlib import Path

DIR = Path(r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ledgers")
CUR = DIR / "ShellStorm2_场景账本_v001.xlsx"
OLD = DIR / "ShellStorm2_场景账本_v001.xlsx.bak_tower_wall_door_5m_v005"
SHEET = "xl/worksheets/sheet3.xml"
CELL = re.compile(r'<c r="(?P<ref>[A-Z]+\d+)"(?P<attrs>[^>]*?)(?:/>|>.*?</c>)', re.S)


def cells(xml):
    return {m.group("ref"): m.group(0) for m in CELL.finditer(xml)}


def main():
    zo, zc = zipfile.ZipFile(OLD), zipfile.ZipFile(CUR)
    no, nc = zo.namelist(), zc.namelist()
    print("zip 条目数 旧/新 = %d / %d   %s" % (len(no), len(nc), "一致" if no == nc else "★不一致"))
    changed_entries = [n for n in no if zo.read(n) != zc.read(n)]
    print("字节有差异的 zip 条目 = %s" % (changed_entries or "无"))

    a, b = cells(zo.read(SHEET).decode("utf-8")), cells(zc.read(SHEET).decode("utf-8"))
    diff = sorted(
        ref for ref in set(a) | set(b) if a.get(ref) != b.get(ref)
    )
    print("sheet3 发生变化的单元格 = %s" % (diff or "无"))

    refs = sorted({int(re.sub(r"\D", "", r)) for r in set(a) | set(b)})
    print("行号范围 = %d..%d（共 %d 行）" % (refs[0], refs[-1], len(refs)))

    for ref in ("R57", "S57"):
        print("%s 未变 = %s" % (ref, a.get(ref) == b.get(ref)))
    m = re.search(r"COUNTIF\(\$R\$6:\$R\$241,R57\)", b["S57"])
    print("S57 仍是数组/范围公式 = %s" % bool(m))

    ok = (
        changed_entries == [SHEET]
        and diff == sorted(["%s57" % c for c in "MNPTWY"])
        and a.get("O57") == b.get("O57")
        and a.get("R57") == b.get("R57")
        and a.get("S57") == b.get("S57")
    )
    print("（O57 未出现在变化清单是**预期**：v004 起它就已经是稳定路径，本次原样回写）")
    print("判据 LEDGER_ROW57_PATCH_OK = %s" % ok)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
