# -*- coding: utf-8 -*-
"""B6：在台账里定位 vfx/ui/training_range 六个套件的带版本单元格。

只读，不写盘。目的：先看清「哪些 sheet / 哪些列 / 哪些格」持有 B6 的 14 个旧路径，
再决定白名单补丁的范围（B3 的教训：禁止整文件无差别替换）。

输出：
  * 每个命中的 (sheet名, 列, 行, 单元格形态, 命中文本)
  * 按「列」聚合的统计 —— 用于分辨「运行路径列」与「历史记录列」
"""
from __future__ import annotations

import re
import zipfile
from pathlib import Path

PROJECT = Path(r"I:/工作项目/shellstrom2/ShellStorm2")
LEDGER = PROJECT / "assets/registry/ShellStorm2_美术资产台账_v001.xlsx"

# B6 六套件（旧带版本基名 → 新稳定基名）
STEMS = [
    "vfx_combat_kit_root_top3d",
    "vfx_damage_number_root_top3d",
    "vfx_explosion_root_top3d",
    "vfx_heal_number_root_top3d",
    "vfx_impact_root_top3d",
    "vfx_melee_impact_root_top3d",
    "vfx_melee_slash_root_top3d",
    "vfx_muzzle_flash_root_top3d",
    "vfx_base99_dust_particles_root_top3d",
    "vfx_hazard_field_root_top3d",
    "vfx_player_flashlight_root_top3d",
    "ui_item_model_icon_root",
    "ui_pause_overlay_screen",
    "env_training_range_kit_top3d",
]
HIT = re.compile(r"(?:" + "|".join(STEMS) + r")_v\d{3}\.(?:glb|tscn)")

CELL = re.compile(r"<(?:x:)?c\b([^>]*?)>(.*?)</(?:x:)?c>", re.S)
V = re.compile(r"_v\d{3}")


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

    # r:id -> Target 映射，取出 sheet 名与 xml 成员的对应
    # 注意：rels 里属性顺序是 Type/Target/Id（Id 在 Target 之后），不能假设 Id 在前。
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
        # Target 形如 /xl/worksheets/sheet1.xml 或 worksheets/sheet1.xml
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

    hits = []
    # 1) 工作表内联文本
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
                if vm and int(vm.group(1)) < len(sst):
                    real = sst_text(sst[int(vm.group(1))])
                    if HIT.search(real):
                        hits.append((name, r.group(1), int(r.group(2)),
                                     "sharedStr", real.strip()[:150]))
                continue
            val = cell_text(inner)
            if val and HIT.search(val):
                hits.append((name, r.group(1), int(r.group(2)), tval or "n", val.strip()[:150]))

    # 2) 共享字符串表本身
    shared_hits = [(i, sst_text(s).strip()[:150])
                   for i, s in enumerate(sst) if HIT.search(sst_text(s))]

    print(f"\n=== 单元格命中 {len(hits)} ===")
    for name, col, row, tval, txt in sorted(hits, key=lambda x: (x[0], x[1], x[2])):
        print(f"   [{name}!{col}{row}] ({tval})  {txt}")

    print(f"\n=== 共享字符串表命中 {len(shared_hits)} ===")
    for i, txt in shared_hits:
        print(f"   #{i}  {txt}")

    print("\n=== 按 sheet!列 聚合 ===")
    agg: dict[str, int] = {}
    for name, col, _row, _t, _txt in hits:
        agg[f"{name}!{col}"] = agg.get(f"{name}!{col}", 0) + 1
    for k in sorted(agg):
        print(f"   {k}: {agg[k]}")

    # 3) 反查：整格恰好是 B6 路径（可安全改写的候选）
    print("\n=== 可安全改写候选（整格恰好是路径、且带版本）===")
    n = 0
    for name, col, row, tval, txt in hits:
        if V.search(txt) and not any(ch in txt for ch in ("；", ";", "\n", "（")) \
           and "/source/" not in txt and not txt.endswith(".blend"):
            n += 1
            print(f"   [{name}!{col}{row}]  {txt}")
    print(f"   候选数 = {n}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
