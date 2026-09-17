# -*- coding: utf-8 -*-
"""B4：在台账里定位 rooftop_shelter_3d 的带版本单元格。

只读，不写盘。目的：先看清「哪些 sheet / 哪些列 / 哪些格」持有 B4 的旧路径，
再决定白名单补丁的范围（B3 的教训：禁止整文件无差别替换）。

判据：单元格文本同时含 `rooftop_shelter` 与 `_v\\d{3}`（即仍带版本的旧登记）。
另单列「提及 rooftop_shelter 但不带版本」的格子作参照。
"""
from __future__ import annotations

import re
import zipfile
from pathlib import Path

PROJECT = Path(r"I:/工作项目/shellstrom2/ShellStorm2")
LEDGER = PROJECT / "assets/registry/ShellStorm2_美术资产台账_v001.xlsx"

NEEDLE = "rooftop_shelter"
VER = re.compile(r"_v\d{3}")

CELL = re.compile(r"<(?:x:)?c\b([^>]*?)>(.*?)</(?:x:)?c>", re.S)


def sst_text(si: str) -> str:
    return "".join(re.findall(r"<(?:x:)?t[^>]*>(.*?)</(?:x:)?t>", si, re.S))


def cell_text(inner: str) -> str:
    ts = re.findall(r"<(?:x:)?t[^>]*>(.*?)</(?:x:)?t>", inner, re.S)
    if ts:
        return "".join(ts)
    v = re.search(r"<(?:x:)?v>(.*?)</(?:x:)?v>", inner, re.S)
    return v.group(1) if v else ""


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

    sst = []
    if "xl/sharedStrings.xml" in members:
        sst = re.findall(r"<(?:x:)?si>(.*?)</(?:x:)?si>",
                         blobs["xl/sharedStrings.xml"].decode("utf8", "ignore"), re.S)

    print("=== sheet 名 -> zip 成员 ===")
    for n, m in name2member.items():
        print(f"   {n}  ->  {m}")

    ver_hits = []      # 含 rooftop_shelter 且带 _vNNN
    plain_hits = []    # 含 rooftop_shelter 但不带版本

    for name, member in name2member.items():
        if member not in members:
            continue
        txt = blobs[member].decode("utf8")
        for m in CELL.finditer(txt):
            attrs, inner = m.group(1), m.group(2)
            r = re.search(r'r="([A-Z]+)(\d+)"', attrs)
            if not r:
                continue
            t = re.search(r't="([^"]*)"', attrs)
            tval = t.group(1) if t else ""
            if tval == "s":
                vm = re.search(r"<(?:x:)?v>(\d+)</(?:x:)?v>", inner)
                real = ""
                if vm and int(vm.group(1)) < len(sst):
                    real = sst_text(sst[int(vm.group(1))])
                if NEEDLE not in real:
                    continue
                rec = (name, r.group(1), int(r.group(2)), "sharedStr", real.strip())
                (ver_hits if VER.search(real) else plain_hits).append(rec)
                continue
            val = cell_text(inner)
            if not val or NEEDLE not in val:
                continue
            rec = (name, r.group(1), int(r.group(2)), tval or "n", val.strip())
            (ver_hits if VER.search(val) else plain_hits).append(rec)

    print(f"\n=== [A] 带版本命中 {len(ver_hits)} ===")
    for name, col, row, tval, txt in sorted(ver_hits, key=lambda x: (x[0], x[1], x[2])):
        print(f"   [{name}!{col}{row}] ({tval})  {txt[:200]}")

    print(f"\n=== [B] 不带版本、仅提及 rooftop_shelter 命中 {len(plain_hits)} ===")
    for name, col, row, tval, txt in sorted(plain_hits, key=lambda x: (x[0], x[1], x[2])):
        print(f"   [{name}!{col}{row}] ({tval})  {txt[:160]}")

    print("\n=== 按 sheet!列 聚合（仅带版本）===")
    agg: dict[str, int] = {}
    for name, col, _row, _t, _txt in ver_hits:
        agg[f"{name}!{col}"] = agg.get(f"{name}!{col}", 0) + 1
    for k in sorted(agg):
        print(f"   {k}: {agg[k]}")

    print("\n=== 可安全改写候选（整格恰好是路径 / 简单说明，且带版本）===")
    n = 0
    for name, col, row, tval, txt in sorted(ver_hits, key=lambda x: (x[0], x[1], x[2])):
        if not any(ch in txt for ch in ("；", "\n", "（")) and "/source/" not in txt \
           and not txt.endswith(".blend"):
            n += 1
            print(f"   [{name}!{col}{row}]  {txt}")
    print(f"   候选数 = {n}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
