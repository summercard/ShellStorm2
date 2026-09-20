#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""2026-09-20 批次：登记 / 升级「100F 上层围护（天台 v002 房间墙体 + 房顶模块）」到场景账本。

背景（用户口径）：
  100F 上层围护（env_base100_upper_shell_30x30_h12）的东西南三面 17 块 5m 墙
  与 24m 封顶 36 格，改由「天台区块 参考组件库 v002」的正式美术承接：
    墙 = ENV-ROOFTOP-REF-ROOM-WALL（prp_rooftop_room_wall_5x12）
    封顶 = ENV-ROOFTOP-REF-ROOF-{CORNER,EDGE,FULL}_5m（4 + 16 + 16 格）
  北面 4 大窗 + 东面门洞槽保留 base99（东门槽是 100F 唯一外梯过场门，
  RoomDoor3D 净尺寸写死 TOWER_GEOMETRY.DOOR_CLEAR_* = 2.2×2.5，不能换厚石门洞墙）。

写入规则（遵守 assets/registry/README.md）：
  * 组件级行落在《3D-场景通用》分页（既有 47 个天台 v002 组件行也在这里）；
  * **AssetID 已存在 → 升级既有行，不新增行**（否则 duplicate_asset_id）；
    本批只有 ENV-ROOFTOP-REF-ROOM-DOOR / -ROOM-DOOR-LEAF 是全新 AssetID，追加两行；
  * 父库行 ENV-ROOFTOP-REFERENCE-COMPONENT-LIBRARY 的《资产主表》行同步刷新备注；
  * 《资产主表》里 ENV-BASE100-UPPER-SHELL-30X30-H12 的 SHA-256 必须跟着重生成后的
    tscn 一起刷新，否则 sha_mismatch（基线红项 ⊆ 已知 47 条，不许因本批新增）。

用法：
    python _scratch/task_house/update_ledger_rooftop_room_v002.py            # 只打印计划
    python _scratch/task_house/update_ledger_rooftop_room_v002.py --apply    # 落盘
"""
from __future__ import annotations

import argparse
import hashlib
import shutil
import sys
from datetime import date
from pathlib import Path

from openpyxl import load_workbook

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from ledger_registry import LedgerIndex  # noqa: E402

STAMP = date(2026, 9, 20)
PREFAB_DIR = "assets/art/props/dungeon_3d"
GLB_DIR = "assets/art/environments/tower_zones/rooftop/components"
V002_BLEND = (
    "assets/art/environments/tower_zones/rooftop/source/reference_components/v002/"
    "天台区块_参考组件库_v002.blend"
)
SHELL_SCENE = (
    "assets/art/environments/base_facility_3d/runtime/env_base100_upper_shell_30x30_h12/"
    "env_base100_upper_shell_30x30_h12_root_top3d.tscn"
)

ORIGIN_NOTE = (
    "bottom_center（几何 Y=0 起）；+Z 朝外。⚠️ 与 99F 系（ENV-BASE99-*，-Z 朝外）差 180°："
    "同一条边 base99 用 -90°、本套件用 +90°。"
)
COLLISION_ON = (
    "开",
    "Base100UpperShell3D",
    "BoxShape3D；由 Base100UpperShell3D._build_structure_collision() 生成 30×30 连续结构层代理，"
    "Prefab 自身不带碰撞节点（内嵌会与结构层重复阻挡）",
)
COLLISION_OFF = (
    "未创建",
    "Base100UpperShell3D",
    "Prefab 已声明 collision_owner；尚未在 100F 上层围护场景实例化",
)

# AssetID -> 该行要写的字段
UPGRADES: dict[str, dict[str, object]] = {
    "ENV-ROOFTOP-REF-ROOM-WALL": {
        "prefab": f"{PREFAB_DIR}/prp_rooftop_room_wall_5x12.tscn",
        "glb": f"{GLB_DIR}/env_rooftop_ref_room_wall_top3d.glb",
        "script": "src/world3d/Base100UpperShell3D.gd",
        "collision": COLLISION_ON,
        "size": "5.000×11.900×0.300 m（逻辑高 12.000，顶面留 0.10 给 24m 封顶）",
        "usage": "100F 上层围护东西南三面 17 块（南 6 / 西 6 / 东 5，东面 z=-7.5 门洞槽除外）",
        "status": "正式美术已接入",
        "note": (
            "2026-09-20：由「仅 Blender 源」升为运行时正式资产，本行不新增 AssetID。"
            "用户要求「把天台参考组件库里的房间墙体与房顶做成正规 prefab，"
            "替换 100F 上层围护的东西南三面，北面大窗不动」。"
            "导出 GLB 后建立 prefab prp_rooftop_room_wall_5x12.tscn；"
            "场景 env_base100_upper_shell_30x30_h12_root_top3d.tscn 用 17 个实例承接，"
            "rotation_y = 0（南）/ -90°（西）/ +90°（东）；北面 2 普通墙 + 4 窗墙与"
            "东面 1 门墙仍为 base99。碰撞交 Base100UpperShell3D 连续结构层（9 片不变）。"
            "验收 verify_base99_wall_visual_replacement（含 base100_rooftop_room_wall_count=17）。"
        ),
    },
    "ENV-ROOFTOP-REF-ROOM-WINDOW": {
        "prefab": f"{PREFAB_DIR}/prp_rooftop_room_window_5x12.tscn",
        "glb": f"{GLB_DIR}/env_rooftop_ref_room_window_top3d.glb",
        "script": None,
        "collision": COLLISION_OFF,
        "size": "5.000×11.900×0.300 m（逻辑高 12.000）",
        "usage": "已制作并登记；100F 上层围护**未使用**（北面 4 大窗仍用 base99 窗墙）",
        "status": "正式美术已接入",
        "note": (
            "2026-09-20：随房间墙体套件一并导出 GLB 并建立 prefab；"
            "本批场景未摆放 —— 用户口径是「北面大窗不动」，北面 4 块沿用 base99 窗墙。"
            "留作后续把北面大窗换成天台 v002 窗墙时直接引用。"
        ),
    },
    "ENV-ROOFTOP-REF-ROOM-DOORWALL": {
        "prefab": f"{PREFAB_DIR}/prp_rooftop_room_doorwall_5x12.tscn",
        "glb": f"{GLB_DIR}/env_rooftop_ref_room_doorwall_top3d.glb",
        "script": None,
        "collision": COLLISION_OFF,
        "size": "5.000×11.900×0.300 m；门洞净空 3.80×6.80 m（两侧垛各 0.60 m）",
        "usage": "已制作并登记；100F 上层围护**未使用**（东面门洞槽仍用 base99 门墙）",
        "status": "正式美术已接入",
        "note": (
            "2026-09-20：随房间墙体套件一并导出 GLB 并建立 prefab；本批场景未摆放。"
            "原因：东面 z=-7.5 门洞槽是 100F 唯一的外梯过场门位，由 "
            "TowerDescent3D._install_base_rooftop_transit_door() 挂 RoomDoor3D，"
            "其净尺寸写死 TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M/HEIGHT_M = 2.2×2.5；"
            "换成本件的 3.80×6.80 洞等于改全游戏所有门的尺寸与碰撞。"
            "用户决策「东门不动，新门只入库」。"
        ),
    },
    "ENV-ROOFTOP-REF-ROOF-FULL": {
        "prefab": f"{PREFAB_DIR}/prp_rooftop_roof_full_5m.tscn",
        "glb": f"{GLB_DIR}/env_rooftop_ref_roof_full_top3d.glb",
        "script": "src/world3d/Base100UpperShell3D.gd",
        "collision": COLLISION_ON,
        "size": "5.000×5.000×0.300 m（底面原点到顶面 0.30，摆 y=24 占 24.00..24.30）",
        "usage": "100F 24m 封顶 6×6 网格的 16 个内圈格",
        "status": "正式美术已接入",
        "note": (
            "2026-09-20：由「仅 Blender 源」升为运行时正式资产，本行不新增 AssetID。"
            "用户要求「36 格 base99 地砖换成新房顶模块」。"
            "prefab prp_rooftop_roof_full_5m.tscn 只铺 6×6 的 16 个内圈格（rotation_y=0）。"
        ),
    },
    "ENV-ROOFTOP-REF-ROOF-EDGE": {
        "prefab": f"{PREFAB_DIR}/prp_rooftop_roof_edge_5m.tscn",
        "glb": f"{GLB_DIR}/env_rooftop_ref_roof_edge_top3d.glb",
        "script": "src/world3d/Base100UpperShell3D.gd",
        "collision": COLLISION_ON,
        "size": "5.000×5.000×0.300 m（收口线脚在板厚之内，不外扩包络）",
        "usage": "100F 24m 封顶 6×6 网格的 16 个外圈非角格",
        "status": "正式美术已接入",
        "note": (
            "2026-09-20：由「仅 Blender 源」升为运行时正式资产，本行不新增 AssetID。"
            "收口侧 = 局部 +Z 朝外，按边取 rotation：max z→0° / min z→180° / max x→+90° / min x→-90°。"
        ),
    },
    "ENV-ROOFTOP-REF-ROOF-CORNER": {
        "prefab": f"{PREFAB_DIR}/prp_rooftop_roof_corner_5m.tscn",
        "glb": f"{GLB_DIR}/env_rooftop_ref_roof_corner_top3d.glb",
        "script": "src/world3d/Base100UpperShell3D.gd",
        "collision": COLLISION_ON,
        "size": "5.000×5.000×0.300 m；2 个表面（骨架收口线脚 + 青绿大面）",
        "usage": "100F 24m 封顶 6×6 网格的 4 个角格",
        "status": "正式美术已接入",
        "note": (
            "2026-09-20：由「仅 Blender 源」升为运行时正式资产，本行不新增 AssetID。"
            "⚠️ 本件收口在**局部 +Z 与 -X 两侧**（不是对称角板），由 reference_assembly.json "
            "四个角格的 rotation_z 反解验证：(min x,max z)→0° / (max x,max z)→+90° / "
            "(max x,min z)→180° / (min x,min z)→-90°。"
        ),
    },
    "ENV-ROOFTOP-REF-ROOM-WALL-IVY": {
        "prefab": f"{PREFAB_DIR}/prp_rooftop_room_wall_ivy_5x12.tscn",
        "glb": f"{GLB_DIR}/env_rooftop_ref_room_wall_ivy_top3d.glb",
        "script": None,
        "collision": COLLISION_OFF,
        "size": "5.000×11.900×0.300 m（挂藤装饰在包络之内）",
        "usage": "已制作并登记；100F 上层围护**未使用**（挂藤留给后续装饰批次）",
        "status": "正式美术已接入",
        "note": (
            "2026-09-20：随房间墙体套件一并导出 GLB 并建立 prefab；本批场景未摆放。"
            "外墙植物包络不进入阻挡（沿用 v002 组件库口径）。"
        ),
    },
    "ENV-ROOFTOP-REF-ROOM-WINDOW-IVY": {
        "prefab": f"{PREFAB_DIR}/prp_rooftop_room_window_ivy_5x12.tscn",
        "glb": f"{GLB_DIR}/env_rooftop_ref_room_window_ivy_top3d.glb",
        "script": None,
        "collision": COLLISION_OFF,
        "size": "5.000×11.900×0.300 m（挂藤装饰在包络之内）",
        "usage": "已制作并登记；100F 上层围护**未使用**",
        "status": "正式美术已接入",
        "note": "2026-09-20：随房间墙体套件一并导出 GLB 并建立 prefab；本批场景未摆放。",
    },
    "ENV-ROOFTOP-REF-ROOM-DOORWALL-IVY": {
        "prefab": f"{PREFAB_DIR}/prp_rooftop_room_doorwall_ivy_5x12.tscn",
        "glb": f"{GLB_DIR}/env_rooftop_ref_room_doorwall_ivy_top3d.glb",
        "script": None,
        "collision": COLLISION_OFF,
        "size": "5.000×11.900×0.300 m；门洞净空 3.80×6.80 m",
        "usage": "已制作并登记；100F 上层围护**未使用**",
        "status": "正式美术已接入",
        "note": "2026-09-20：随房间墙体套件一并导出 GLB 并建立 prefab；本批场景未摆放。",
    },
}

NEW_ROWS: list[dict[str, object]] = [
    {
        "asset_id": "ENV-ROOFTOP-REF-ROOM-DOOR",
        "cn": "房间门组件（门框+门垛）",
        "prefab": f"{PREFAB_DIR}/prp_rooftop_room_door.tscn",
        "glb": f"{GLB_DIR}/env_rooftop_ref_room_door_top3d.glb",
        "blend": (
            f"{V002_BLEND}#门与暖灯_资产包"
            "（导出脚本 assets/art/environments/tower_zones/rooftop/source/"
            "export_env_rooftop_ref_room_walls_v001.py）"
        ),
        "func": (
            "厚石门洞的门框与门垛视觉；与 ENV-ROOFTOP-REF-ROOM-DOOR-LEAF 成对使用。"
            "门组件 = 门洞墙基准位 + 0.4175×外法线（沿 +Z 外移半个门洞墙厚 + 半板厚）"
        ),
        "script": None,
        "collision": COLLISION_OFF,
        "size": "门洞净空 3.80×6.80 m；门垛各 0.60 m（外廓随基墙 5.000×11.900×0.300）",
        "usage": "已制作并登记；100F 上层围护**未使用**（东门槽保留 base99 门墙与 RoomDoor3D）",
        "status": "正式美术已接入",
        "version": "v002",
        "note": (
            "2026-09-20 新建行（全新 AssetID）。来源：天台区块参考组件库 v002 的"
            "「门与暖灯_主体」（528 顶点焊接网格，含 22 个松散件）按 5 个制作件 AABB "
            "无损二分：130 面 → 门扇、418 面 → 本件（门组件）。"
            "与门洞墙同位、无偏移。⚠️ 本房型门是静态关闭态（Base100UpperShell3D 的门洞只是洞，"
            "没有挂 RoomDoor3D）；若日后要做开合动画，必须改 RoomDoor3D 的全局常量"
            "TOWER_GEOMETRY.DOOR_CLEAR_*，不能只改本件。"
        ),
    },
    {
        "asset_id": "ENV-ROOFTOP-REF-ROOM-DOOR-LEAF",
        "cn": "房间门扇（静态关闭态）",
        "prefab": f"{PREFAB_DIR}/prp_rooftop_room_door_leaf.tscn",
        "glb": f"{GLB_DIR}/env_rooftop_ref_room_door_leaf_top3d.glb",
        "blend": (
            f"{V002_BLEND}#门与暖灯_资产包"
            "（导出脚本 assets/art/environments/tower_zones/rooftop/source/"
            "export_env_rooftop_ref_room_walls_v001.py）"
        ),
        "func": "厚石门洞的单扇门板视觉；与 ENV-ROOFTOP-REF-ROOM-DOOR 成对；静态关闭态",
        "script": None,
        "collision": COLLISION_OFF,
        "size": "板 3.680×6.800×0.180 m；可视包络厚 0.410 m",
        "usage": "已制作并登记；100F 上层围护**未使用**",
        "status": "正式美术已接入",
        "version": "v002",
        "note": (
            "2026-09-20 新建行（全新 AssetID）。门扇板局部 z 中心已平移到 0（原点 = 底面中心），"
            "与门洞墙同位装配（不沿 +Z 偏移）；门组件才做 +0.4175×外法线偏移。"
            "3 个表面，共享色盘由 scene_facility_shared_palette_post_import.gd 绑定。"
            "本行不声明 open_mode：本房型门是静态关闭态；要做开合须改 RoomDoor3D 全局常量。"
        ),
    },
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="真正写盘（默认只打印计划）")
    args = parser.parse_args()

    index = LedgerIndex.load(ROOT)
    ledger_path = index.path_for_category("场景")
    page = "3D-场景通用"
    main_sheet = index.asset_sheet
    print("账本: %s" % ledger_path.relative_to(ROOT).as_posix())
    print("分页: %s / 主表: %s" % (page, main_sheet))

    wb = load_workbook(ledger_path, data_only=False)
    ws = wb[page]
    header = [str(ws.cell(row=4, column=c).value or "") for c in range(1, 17)]
    col = {name: i + 1 for i, name in enumerate(header)}

    # ---- 定位既有行 ----
    row_of: dict[str, int] = {}
    for r in range(5, ws.max_row + 1):
        aid = str(ws.cell(row=r, column=1).value or "").strip()
        if aid:
            row_of[aid] = r

    missing = [aid for aid in UPGRADES if aid not in row_of]
    if missing:
        print("!! 既有行缺失，终止：%s" % missing)
        return 2

    changed = 0
    for asset_id, spec in UPGRADES.items():
        r = row_of[asset_id]
        before = [ws.cell(row=r, column=col[k]).value for k in
                  ("Prefab路径", "GLB模型路径", "功能脚本路径", "制作状态")]
        ws.cell(row=r, column=col["Prefab路径"]).value = spec["prefab"]
        ws.cell(row=r, column=col["GLB模型路径"]).value = spec["glb"]
        ws.cell(row=r, column=col["功能脚本路径"]).value = spec["script"]
        ws.cell(row=r, column=col["碰撞开关"]).value = spec["collision"][0]
        ws.cell(row=r, column=col["碰撞归属"]).value = spec["collision"][1]
        ws.cell(row=r, column=col["碰撞方式"]).value = spec["collision"][2]
        ws.cell(row=r, column=col["标准尺寸"]).value = spec["size"]
        ws.cell(row=r, column=col["原点与朝向"]).value = ORIGIN_NOTE
        ws.cell(row=r, column=col["使用位置"]).value = spec["usage"]
        ws.cell(row=r, column=col["制作状态"]).value = spec["status"]
        ws.cell(row=r, column=col["版本"]).value = "v002"
        old_note = str(ws.cell(row=r, column=col["备注"]).value or "")
        ws.cell(row=r, column=col["备注"]).value = (old_note + "\n" + str(spec["note"])).strip()
        print("  UP   row %-4d %-42s %s -> 正式美术已接入" % (r, asset_id, before[3]))
        changed += 1

    # ---- 追加新行 ----
    next_row = ws.max_row + 1
    while next_row > 5 and not str(ws.cell(row=next_row - 1, column=1).value or "").strip():
        next_row -= 1
    for spec in NEW_ROWS:
        if spec["asset_id"] in row_of:
            print("  SKIP %s 已存在（row %d）" % (spec["asset_id"], row_of[spec["asset_id"]]))
            continue
        ws.cell(row=next_row, column=col["AssetID"]).value = spec["asset_id"]
        ws.cell(row=next_row, column=col["中文名"]).value = spec["cn"]
        ws.cell(row=next_row, column=col["Prefab路径"]).value = spec["prefab"]
        ws.cell(row=next_row, column=col["GLB模型路径"]).value = spec["glb"]
        ws.cell(row=next_row, column=col["Blender源文件"]).value = spec["blend"]
        ws.cell(row=next_row, column=col["功能说明"]).value = spec["func"]
        ws.cell(row=next_row, column=col["功能脚本路径"]).value = spec["script"]
        ws.cell(row=next_row, column=col["碰撞开关"]).value = spec["collision"][0]
        ws.cell(row=next_row, column=col["碰撞归属"]).value = spec["collision"][1]
        ws.cell(row=next_row, column=col["碰撞方式"]).value = spec["collision"][2]
        ws.cell(row=next_row, column=col["标准尺寸"]).value = spec["size"]
        ws.cell(row=next_row, column=col["原点与朝向"]).value = ORIGIN_NOTE
        ws.cell(row=next_row, column=col["使用位置"]).value = spec["usage"]
        ws.cell(row=next_row, column=col["制作状态"]).value = spec["status"]
        ws.cell(row=next_row, column=col["版本"]).value = spec["version"]
        ws.cell(row=next_row, column=col["备注"]).value = spec["note"]
        print("  NEW  row %-4d %s" % (next_row, spec["asset_id"]))
        next_row += 1
        changed += 1

    # ---- 主表：上层围护行的 SHA（重生成 tscn 后必须刷新，否则新增 sha_mismatch） ----
    main_ws = wb[main_sheet]
    for r in range(6, main_ws.max_row + 1):
        if str(main_ws.cell(row=r, column=1).value or "").strip() == "ENV-BASE100-UPPER-SHELL-30X30-H12":
            target = ROOT / SHELL_SCENE
            actual = sha256(target)
            recorded = str(main_ws.cell(row=r, column=20).value or "").strip().lower()
            if recorded != actual:
                print("  SHA  row %-4d ENV-BASE100-UPPER-SHELL-30X30-H12  %s -> %s"
                      % (r, recorded[:12], actual[:12]))
                main_ws.cell(row=r, column=20).value = actual
                changed += 1
            main_ws.cell(row=r, column=14).value = (
                "30×30m围护；本地12—24m墙体；24m封顶；墙视觉11.9m；"
                "东西南三面=天台v002房间标准墙17块；封顶=天台v002角4+边16+内圈16"
            )
            main_ws.cell(row=r, column=13).value = "v003"
            main_ws.cell(row=r, column=22).value = STAMP
            main_ws.cell(row=r, column=21).value = "Codex"
            old = str(main_ws.cell(row=r, column=25).value or "")
            main_ws.cell(row=r, column=25).value = (old + (
                "\n2026-09-20：东西南三面 17 块 5m 墙与 24m 封顶 36 格换成天台参考组件库 v002 "
                "（ENV-ROOFTOP-REF-ROOM-WALL + ROOF-{CORNER,EDGE,FULL}）；北面 4 大窗与东面门洞槽保留 base99。"
                "北面窗墙不动的原因是东门槽为 100F 唯一外梯过场门（RoomDoor3D 净尺寸写死 2.2×2.5）。"
                "场景 24 墙 = 17 v002 + 2 base99 普通墙 + 4 base99 窗墙 + 1 base99 门墙；封顶 36 格全换。"
                "旧 36 格 base99 地砖引用已移除。SHA 随重生成 tscn 刷新。"
                "验收 verify_base99_wall_visual_replacement（BASE99_MODULAR_ASSET_INTEGRATION_PASS）"
                "+ verify_rooftop_32x32_contract + verify_base_rooftop_transit_door_motion 全绿。"
            )).strip()
            break
    else:
        print("!! 主表未找到 ENV-BASE100-UPPER-SHELL-30X30-H12")
        return 2

    print("\n合计改动 %d 处" % changed)
    if not args.apply:
        print("（未加 --apply，未写盘）")
        return 0

    backup = ledger_path.with_name(
        ledger_path.name + ".bak_rooftop_room_v002"
    )
    shutil.copy2(ledger_path, backup)
    wb.save(ledger_path)
    print("已写盘；备份 %s" % backup.name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
