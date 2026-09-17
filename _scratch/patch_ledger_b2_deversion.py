# -*- coding: utf-8 -*-
"""B2：把台账「3D-场景通用」表里 B2 相关行的 C（Prefab）/D（GLB）路径就地去掉版本号。

（去版本化计划 §4.1 第 ⑦ 步；沿用 B1 的做法，见 patch_ledger_b1_deversion.py）

与 B1 的差别（有意收紧）：B1 是「整行字符串替换」，本脚本改为**只替换目标单元格内部**。
原因：B2 的目标行里有若干单元格是人工变更记录（P 列），例如 r48 写着
「占位 BoxMesh 替换为正式美术 env_tower_wall_solid_5m_top3d_v003.glb」——
那是历史事实（记录了当初接入的是 v003），整行替换会把它一起改掉，属篡改记录。
只动 C/D（运行路径列）既满足「运行资产路径不含版本号」，又保住版本事实。

为什么必须外科式 XML 补丁：台账是唯一登记源，openpyxl 整本重写会丢 styles /
mergeCells / dataValidations（项目自带校验会断言 (max_row,max_column) 不变）。

幂等：目标串已就位则不写。
落盘：就地在原文件上写（勿 tmp+replace，Windows 会 WinError 5）。

用法：
  python patch_ledger_b2_deversion.py            # dry-run
  python patch_ledger_b2_deversion.py --apply    # 落盘（先备份）
"""
from __future__ import annotations

import re
import shutil
import sys
import zipfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
LEDGER = PROJECT / "assets/registry/ShellStorm2_美术资产台账_v001.xlsx"
SHEET_MEMBER = "xl/worksheets/sheet10.xml"
BACKUP_SUFFIX = ".bak_b2_deversion"

# B2 目标单元格：(行, 列, 期望现值)。用「期望现值」而非 AssetID 做漂移防护：
# 一旦行号漂移或列被挪动，old 对不上就立刻停手，且这个期望值本身来自当前台账实测。
# r61D 指向 rooftop_shelter_3d（属后续批次），故不含。
TARGET_CELLS = [
    (5, "C", "assets/art/environments/tower_zones/base/runtime/zone_base_v002.tscn"),
    (7, "C", "assets/art/environments/base_world_3d/env_base_world_kit_top3d_v001.tscn"),
    (8, "C", "assets/art/environments/dungeon_3d/env_dungeon_runtime_kit_top3d_v001.tscn"),
    (42, "C", "assets/art/props/dungeon_3d/prp_tower_floor_tile_5m_v001.tscn"),
    (42, "D", "assets/art/environments/tower_descent_3d/components/floor_tile_5m/env_tower_floor_tile_5m_top3d_v002.glb"),
    (43, "C", "assets/art/environments/tower_descent_3d/runtime/env_tower_stairwell_generic_12m/env_tower_stairwell_generic_12m_root_top3d_v002.tscn"),
    (43, "D", "assets/art/environments/tower_descent_3d/components/env_tower_stairwell_generic_12m_top3d_v002.glb"),
    (44, "C", "assets/art/environments/tower_descent_3d/runtime/env_tower_stairwell_rooftop_12m/env_tower_stairwell_rooftop_12m_root_top3d_v002.tscn"),
    (44, "D", "assets/art/environments/tower_descent_3d/components/env_tower_stairwell_rooftop_12m_top3d_v002.glb"),
    (45, "C", "assets/art/props/dungeon_3d/prp_tower_wall_door_5m_v001.tscn"),
    (45, "D", "assets/art/environments/tower_descent_3d/components/env_tower_wall_door_5m_top3d_v003.glb"),
    (46, "C", "assets/art/props/dungeon_3d/prp_tower_wall_parapet_5m_v001.tscn"),
    (46, "D", "assets/art/environments/tower_descent_3d/components/env_tower_wall_parapet_5m_top3d_v001.glb"),
    (48, "C", "assets/art/props/dungeon_3d/prp_tower_wall_solid_5m_v001.tscn"),
    (48, "D", "assets/art/environments/tower_descent_3d/components/env_tower_wall_solid_5m_top3d_v003.glb"),
    (61, "C", "assets/art/environments/tower_zones/rooftop/runtime/zone_rooftop_v021.tscn"),
]

VERSION_SUFFIX = re.compile(r"_v(\d{3})(?=\.)")
VERSION_DIR = re.compile(r"^v\d{3}$")
B2_PATH = re.compile(r"assets/art/[A-Za-z0-9_/.\-]*?_v\d{3}\.(?:glb|tscn)")


def stable_path(rel: str) -> str:
    parts = [p for p in rel.split("/") if not VERSION_DIR.match(p)]
    parts[-1] = VERSION_SUFFIX.sub("", parts[-1], count=1)
    return "/".join(parts)


def cell_pattern(col: str, row: int) -> re.Pattern:
    return re.compile(
        r'(<(?:\w+:)?c[^>]*\br="%s%d"[^>]*>)(.*?)(</(?:\w+:)?c>)' % (col, row), re.S
    )


def cell_text(inner: str) -> str:
    """从单元格体里取文本（inlineStr 落 <t>，str 落 <v>）。"""
    ts = re.findall(r"<(?:\w+:)?t[^>]*>(.*?)</(?:\w+:)?t>", inner, re.S)
    if ts:
        return "".join(ts)
    v = re.search(r"<(?:\w+:)?v>(.*?)</(?:\w+:)?v>", inner, re.S)
    return v.group(1) if v else ""


def main() -> int:
    apply = "--apply" in sys.argv
    if not LEDGER.is_file():
        raise SystemExit(f"缺少台账：{LEDGER}")

    with zipfile.ZipFile(LEDGER) as zin:
        members = zin.namelist()
        blobs = {name: zin.read(name) for name in members}

    sheet = blobs[SHEET_MEMBER].decode("utf8")
    original_sheet = sheet
    changed: list[str] = []

    for row, col, expected_old in TARGET_CELLS:
        m = cell_pattern(col, row).search(sheet)
        if m is None:
            raise SystemExit(f"找不到 {col}{row}")
        inner = m.group(2)
        old_val = cell_text(inner)
        if old_val == stable_path(expected_old):
            print(f"  {col}{row}: 已就位（幂等跳过）")
            continue
        if old_val != expected_old:
            raise SystemExit(
                f"{col}{row} 现值与期望不符（行号/列可能已漂移）：\n"
                f"  期望 {expected_old}\n  实际 {old_val}"
            )
        new_val = stable_path(old_val)
        if not (PROJECT / new_val).is_file():
            raise SystemExit(f"{col}{row}: 稳定目标不存在 {new_val}")
        new_inner = inner.replace(old_val, new_val)
        sheet = sheet[: m.start()] + m.group(1) + new_inner + m.group(3) + sheet[m.end():]
        changed.append(f"{col}{row}")
        print(f"  {col}{row}  {old_val}\n         -> {new_val}")

    if sheet == original_sheet:
        print("LEDGER_B2_NO_CHANGE：目标串已全部就位（幂等）")
        return 0

    # —— 保真校验 ——
    for tag in ("dimension", "mergeCell", "dataValidation"):
        if len(re.findall(r"<(?:\w+:)?%s\b" % tag, original_sheet)) != \
           len(re.findall(r"<(?:\w+:)?%s\b" % tag, sheet)):
            raise SystemExit(f"{tag} 数量变化，拒绝写入")
    if len(re.findall(r"<(?:\w+:)?row\b", original_sheet)) != \
       len(re.findall(r"<(?:\w+:)?row\b", sheet)):
        raise SystemExit("行数变化，拒绝写入")

    print(f"\n将修改 {len(changed)} 个单元格：{changed}")
    if not apply:
        print("（dry-run，未写盘；加 --apply 落盘）")
        return 0

    backup = LEDGER.with_name(LEDGER.name + BACKUP_SUFFIX)
    shutil.copy2(LEDGER, backup)
    # 就地写（memory：勿 os.replace，Windows WinError 5）
    with zipfile.ZipFile(LEDGER, "w", zipfile.ZIP_DEFLATED) as zout:
        for name in members:
            zout.writestr(name, sheet.encode("utf8") if name == SHEET_MEMBER else blobs[name])

    with zipfile.ZipFile(LEDGER) as z:
        assert z.namelist() == members, "zip 条目集合变了"
        diff = [n for n in members if z.read(n) != blobs[n]]
    if diff != [SHEET_MEMBER]:
        raise SystemExit(f"非预期差异条目：{diff}")
    print(f"LEDGER_B2_OK 已写入（备份 {backup.name}）；仅 {SHEET_MEMBER} 变化")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
