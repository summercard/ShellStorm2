# -*- coding: utf-8 -*-
"""步骤⑦ 复验：B3 台账补丁写入后的完整性与残留检查。只读。"""
import re
import zipfile
from pathlib import Path

REPO = Path(r"I:/工作项目/shellstrom2/ShellStorm2")
XLSX = REPO / "assets/registry/ShellStorm2_美术资产台账_v001.xlsx"
BAK = XLSX.with_name(XLSX.name + ".bak_b3_deversion")
PREFIX = "assets/art/environments/base_facility_3d"
V = re.compile(r"_v\d{3}")

zb = zipfile.ZipFile(BAK)
za = zipfile.ZipFile(XLSX)
nb, na = zb.namelist(), za.namelist()
print(f"1) zip 条目: {len(nb)} -> {len(na)}  相同={set(nb) == set(na)}")
diff = [n for n in na if zb.read(n) != za.read(n)]
print(f"2) 变化成员: {diff}")

sst = re.findall(r"<(?:x:)?si>(.*?)</(?:x:)?si>",
                 za.read("xl/sharedStrings.xml").decode("utf8", "ignore"), re.S)


def st(si):
    return "".join(re.findall(r"<(?:x:)?t[^>]*>(.*?)</(?:x:)?t>", si, re.S))


# 把三张目标表的「运行路径列」全部解析出来，看还有没有带版本残留
TARGETS = [("xl/worksheets/sheet10.xml", "3D-场景通用", ("C", "D")),
           ("xl/worksheets/sheet11.xml", "3D-设施", ("C", "D")),
           ("xl/worksheets/sheet2.xml", "资产主表", ("O",))]

print("\n3) 运行路径列残留（应为 0）：")
left = 0
for f, nm, cols in TARGETS:
    d = za.read(f).decode("utf8", "ignore")
    for m in re.finditer(r"<(?:x:)?c\b([^>]*?)>(.*?)</(?:x:)?c>", d, re.S):
        a, i = m.group(1), m.group(2)
        r = re.search(r'r="([A-Z]+)(\d+)"', a)
        if not r or r.group(1) not in cols:
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
            im = re.search(r"<(?:x:)?is>(.*?)</(?:x:)?is>", i, re.S)
            if vm is None and im:
                val = st(im.group(1))
        if val and val.strip().startswith(PREFIX) and V.search(val):
            left += 1
            print(f"   {nm}!{r.group(1)}{r.group(2)}  {val.strip()[:110]}")
print(f"   合计 {left}")

# 台账整体：B3 带版本 token 分布（应只剩 source 豁免）
t = b"".join(za.read(n) for n in na if n.startswith("xl/worksheets/sheet")).decode("utf8", "ignore")
PAT = re.compile(r"assets/[A-Za-z0-9_./\-]+")
toks = sorted({x for x in PAT.findall(t) if x.startswith(PREFIX) and V.search(x)})
src = [x for x in toks if "/source/" in x]
nonsrc = [x for x in toks if "/source/" not in x]
print(f"\n4) 台账内 B3 带版本 token: 共 {len(toks)}（source 豁免 {len(src)} / 非 source {len(nonsrc)}）")
for x in nonsrc:
    print(f"   [非source] {x}")
