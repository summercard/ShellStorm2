# -*- coding: utf-8 -*-
"""查 D65/D66 完整值 + 定位每个非 source 残留 token 所在单元格（确认是否都在历史列）。只读。"""
import re
import zipfile
from collections import defaultdict
from pathlib import Path

REPO = Path(r"I:/工作项目/shellstrom2/ShellStorm2")
XLSX = REPO / "assets/registry/ShellStorm2_美术资产台账_v001.xlsx"
PREFIX = "assets/art/environments/base_facility_3d"
V = re.compile(r"_v\d{3}")
z = zipfile.ZipFile(XLSX)
names = z.namelist()
sst = re.findall(r"<(?:x:)?si>(.*?)</(?:x:)?si>",
                 z.read("xl/sharedStrings.xml").decode("utf8", "ignore"), re.S)


def st(si):
    return "".join(re.findall(r"<(?:x:)?t[^>]*>(.*?)</(?:x:)?t>", si, re.S))


wb = z.read("xl/workbook.xml").decode("utf8", "ignore")
rels = z.read("xl/_rels/workbook.xml.rels").decode("utf8", "ignore")
relmap = {}
for m in re.finditer(r"<Relationship\b[^>]*/>", rels):
    tag = m.group(0)
    i = re.search(r'Id="([^"]+)"', tag)
    t = re.search(r'Target="([^"]+)"', tag)
    if i and t:
        relmap[i.group(1)] = t.group(1)
name2file = {}
for m in re.finditer(r"<(?:x:)?sheet\b[^>]*/>", wb):
    tag = m.group(0)
    nm = re.search(r'name="([^"]+)"', tag)
    rid = re.search(r'r:id="([^"]+)"', tag)
    if nm and rid:
        t = relmap.get(rid.group(1), "").lstrip("/")
        if not t.startswith("xl/"):
            t = "xl/" + t
        name2file[nm.group(1)] = t

# 1) D65/D66 完整值
for f, nm in [("xl/worksheets/sheet10.xml", "3D-场景通用")]:
    d = z.read(f).decode("utf8", "ignore")
    for m in re.finditer(r"<(?:x:)?c\b([^>]*?)>(.*?)</(?:x:)?c>", d, re.S):
        a, i = m.group(1), m.group(2)
        r = re.search(r'r="([A-Z]+)(\d+)"', a)
        if not r or f"{r.group(1)}{r.group(2)}" not in ("D65", "D66"):
            continue
        t = re.search(r't="([^"]*)"', a)
        val = None
        if t and t.group(1) == "s":
            vm = re.search(r"<(?:x:)?v>(\d+)</(?:x:)?v>", i)
            if vm and int(vm.group(1)) < len(sst):
                val = st(sst[int(vm.group(1))])
        else:
            vm = re.search(r"<(?:x:)?v>(.*?)</(?:x:)?v>", i, re.S)
            if vm:
                val = vm.group(1)
        print(f"[{nm}] {r.group(1)}{r.group(2)}  t={t.group(1) if t else ''!r}")
        print(f"    完整值: {val!r}")
        print()

# 2) 每个非 source 残留 token 所在单元格
PAT = re.compile(r"assets/[A-Za-z0-9_./\-]+")
loc = defaultdict(list)
for nm, f in name2file.items():
    if f not in names:
        continue
    d = z.read(f).decode("utf8", "ignore")
    for m in re.finditer(r"<(?:x:)?c\b([^>]*?)>(.*?)</(?:x:)?c>", d, re.S):
        a, i = m.group(1), m.group(2)
        r = re.search(r'r="([A-Z]+)(\d+)"', a)
        if not r:
            continue
        t = re.search(r't="([^"]*)"', a)
        val = None
        if t and t.group(1) == "s":
            vm = re.search(r"<(?:x:)?v>(\d+)</(?:x:)?v>", i)
            if vm and int(vm.group(1)) < len(sst):
                val = st(sst[int(vm.group(1))])
        else:
            vm = re.search(r"<(?:x:)?v>(.*?)</(?:x:)?v>", i, re.S)
            if vm:
                val = vm.group(1)
        if not val:
            continue
        for tok in PAT.findall(val):
            if tok.startswith(PREFIX) and V.search(tok) and "/source/" not in tok:
                loc[tok].append(f"{nm}!{r.group(1)}{r.group(2)}")

print("=== 非 source 残留 token -> 所在单元格 ===")
for tok in sorted(loc):
    print(f"  {tok}")
    print(f"      @ {sorted(set(loc[tok]))}")
