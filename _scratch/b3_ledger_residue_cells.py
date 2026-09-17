# -*- coding: utf-8 -*-
"""把台账里所有 B3 带版本 token 的落点逐格列出（sheet + 单元格 + 列名），
用于确认它们只出现在「历史列」（P 关联文件清单 / Y 变更日志 / E 源文件）而没有任何路径列残留。
只读。"""
import re
import zipfile
from pathlib import Path

REPO = Path(r"I:/工作项目/shellstrom2/ShellStorm2")
XLSX = REPO / "assets/registry/ShellStorm2_美术资产台账_v001.xlsx"
PREFIX = "assets/art/environments/base_facility_3d"
V = re.compile(r"_v\d{3}")

z = zipfile.ZipFile(XLSX)
names = z.namelist()

# sheet 名 -> 文件
wb = z.read("xl/workbook.xml").decode("utf8", "ignore")
rels = z.read("xl/_rels/workbook.xml.rels").decode("utf8", "ignore")
relmap = {}
for m in re.finditer(r"<Relationship\b([^>]*)/?>", rels):
    a = m.group(1)
    rid = re.search(r'Id="([^"]+)"', a)
    tgt = re.search(r'Target="([^"]+)"', a)
    if rid and tgt:
        relmap[rid.group(1)] = tgt.group(1)
sheet2file = {}
for m in re.finditer(r"<(?:x:)?sheet\b([^>]*)/?>", wb):
    a = m.group(1)
    nm = re.search(r'name="([^"]*)"', a)
    rid = re.search(r'r:id="([^"]+)"', a)
    if nm and rid and rid.group(1) in relmap:
        t = relmap[rid.group(1)].lstrip("/")
        if not t.startswith("xl/"):
            t = "xl/" + t
        sheet2file[nm.group(1)] = t

sst_raw = z.read("xl/sharedStrings.xml").decode("utf8", "ignore")
sst = ["".join(re.findall(r"<(?:x:)?t[^>]*>(.*?)</(?:x:)?t>", si, re.S))
       for si in re.findall(r"<(?:x:)?si>(.*?)</(?:x:)?si>", sst_raw, re.S)]

PAT = re.compile(r"assets/[A-Za-z0-9_./\-]+")

hits = {}
for nm, f in sorted(sheet2file.items(), key=lambda kv: kv[1]):
    if f not in names:
        continue
    d = z.read(f).decode("utf8", "ignore")
    for m in re.finditer(r"<(?:x:)?c\b([^>]*?)>(.*?)</(?:x:)?c>", d, re.S):
        a, i = m.group(1), m.group(2)
        r = re.search(r'r="([A-Z]+)(\d+)"', a)
        if not r:
            continue
        col, row = r.group(1), r.group(2)
        t = re.search(r't="([^"]*)"', a)
        val = ""
        if t and t.group(1) == "s":
            vm = re.search(r"<(?:x:)?v>(\d+)</(?:x:)?v>", i)
            if vm and int(vm.group(1)) < len(sst):
                val = sst[int(vm.group(1))]
        else:
            vm = re.search(r"<(?:x:)?v>(.*?)</(?:x:)?v>", i, re.S)
            val = vm.group(1) if vm else ""
            if not val:
                im = re.search(r"<(?:x:)?is>(.*?)</(?:x:)?is>", i, re.S)
                if im:
                    val = "".join(re.findall(r"<(?:x:)?t[^>]*>(.*?)</(?:x:)?t>", im.group(1), re.S))
        if not val:
            continue
        for tok in PAT.findall(val):
            if tok.startswith(PREFIX) and V.search(tok) and "/source/" not in tok:
                hits.setdefault((nm, f"{col}{row}"), set()).add(tok)

print(f"非 source 的 B3 带版本 token 落点：{len(hits)} 个单元格\n")
bycol = {}
for (nm, ref), toks in sorted(hits.items()):
    col = re.match(r"[A-Z]+", ref).group(0)
    bycol.setdefault((nm, col), []).append(ref)
    for tok in sorted(toks):
        print(f"  {nm:<10} {ref:<8} {tok}")
print("\n按 (sheet, 列) 汇总：")
for (nm, col), refs in sorted(bycol.items()):
    print(f"  {nm:<10} 列 {col:<3} -> {len(refs)} 格  ({', '.join(refs[:8])}{' ...' if len(refs) > 8 else ''})")
