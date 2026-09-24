#!/usr/bin/env python
"""生成 / 校验 远征关卡01 Boss 房「专属件摆位源」。

背景
====
Boss 竞技场（故障数据库 50x40）是远征关卡01 里**唯一带专属美术**的房间。
它的壳体（墙体 / L拐角 / 地砖 / 门扇 / 门墙）**不写死**：那 5 类是 5m 通用件，
由区块级组合器 ``RoomShellLayoutBuilder3D`` 在运行时按「房间尺寸 + 门位」现算
（门位随每局 constrained 版图变）。本文件只登记**通用件表达不了的 6 件专属件**。

  1. ENV-EXPEDITION-BOSSROOM-BASE-FLOOR-BASE        地板底盘 50x40x0.26（承重归 TowerFloorStage3D）
  2. ENV-EXPEDITION-BOSSROOM-MAIN-FAULT-SCREEN      主屏 21.52x1.575x7.09（底面悬 3.805m）
  3. ENV-EXPEDITION-BOSSROOM-HEAVY-CONDUITS         粗重电线管与桥架 47.31x32.30x3.67
  4. ENV-EXPEDITION-BOSSROOM-NORTH-WALL-TYPOGRAPHY  数据库墙面标识 35.90x0.042x2.32（底面悬 7.446m）
  5. ENV-EXPEDITION-BOSSROOM-SOUTH-FLOOR-MARKING    入口地砖标识 3.70x2.73x0.012
  6. ENV-EXPEDITION-BOSSROOM-DEBRIS-00              固定碎屑 2.43x1.99x0.22

坐标契约（与区块00 摆位源同一条，2026-09-24 复核）
=================================================
每件 GLB 导出时已把几何折算到「相对其 ROOT 组件的变换」，且 ROOT 只有平移
⇒ GLB 内几何 = 组件自身局部坐标（XY 居中、底面 z=0），**朝向保持源房间世界系**。
故摆位 = 该件**底面中心在源房间世界系的坐标**（= 源 manifest 的 world_origin_m），
旋转一律 0（本脚本用「导出包络 XY 居中」这一事实反证「只做了平移」）。

    Godot 房间局部 = ( bx - cbx,  bz,  -(by - cby) )
      bx / by / bz  = position_m（Blender 房间世界系，X=东、Y=北、Z=上）
      cbx / cby     = 本文件 rooms[].bounds 的中心（本房 = 0,0）
    推导：Blender(x,y,z) --export_yup--> Godot(x, z, -y)，再减房间中心。

⚠️ 与本房实测相关的两个口径
  · 悬空件必须保留 bz：主屏 bz=3.805、墙面标识 bz=7.4461。
    区块00 的 loader 把 y 写成常量 0.0（它那 90 个实例 position_m[2] 全为 0），
    本房不能照抄该简化 —— 见 --check 的 centered 断言与 README 的记录。
  · base_floor_base 厚 0.26m，而房间 manifest 的 floor_top_m = 0.30m，
    差 0.04m。本轮只登记事实，不裁决；落地时以 TowerFloorStage3D 支撑顶面为准。

用法
====
    python scripts/build_expedition01_boss_room_layout.py --write   # 重新落盘
    python scripts/build_expedition01_boss_room_layout.py --check    # 门禁：漂移即 exit 1
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

ROOM_TYPE_DIR = (
    ROOT / "assets/art/environments/tower_zones/expedition/source/room_types/boss_room/v002"
)
MANIFEST_PATH = ROOM_TYPE_DIR / "room_type_manifest.json"
OUTPUT_PATH = ROOM_TYPE_DIR / "boss_room_50x40_v002.layout.json"
CATALOG_PATH = (
    ROOT
    / "assets/art/environments/tower_zones/expedition/source/common_components/v001/component_catalog.json"
)
SUMMARY_PATH = (
    ROOT
    / "assets/art/environments/tower_zones/expedition/source/common_components/v001/qa"
    / "export_boss_shell_components_summary.json"
)
COMPONENTS_DIR = ROOT / "assets/art/environments/tower_zones/expedition/components/common_components"
PREFAB_DIR = ROOT / "assets/art/environments/tower_zones/expedition/runtime/common_components"

SCHEMA = "shellstorm2.battle.room_instance_layout"
LAYOUT_VERSION = "v002"
SCENE_ID = "expedition_01_boss_room"
EXCLUSIVE_SLOT_ROLE = "exclusive_component"

# 顺序即输出顺序（与导出脚本 TARGET_IDS 同序）。
TARGET_IDS = [
    "ENV-EXPEDITION-BOSSROOM-BASE-FLOOR-BASE",
    "ENV-EXPEDITION-BOSSROOM-MAIN-FAULT-SCREEN",
    "ENV-EXPEDITION-BOSSROOM-HEAVY-CONDUITS",
    "ENV-EXPEDITION-BOSSROOM-NORTH-WALL-TYPOGRAPHY",
    "ENV-EXPEDITION-BOSSROOM-SOUTH-FLOOR-MARKING",
    "ENV-EXPEDITION-BOSSROOM-DEBRIS-00",
]
# 承重件：壳体内嵌碰撞在房间层关掉，承重另有归属（不随摆位源实例化出碰撞）。
LOAD_BEARING_IDS = {"ENV-EXPEDITION-BOSSROOM-BASE-FLOOR-BASE"}

TOL_SIZE = 0.01
TOL_CENTER = 1e-3
TOL_ORIGIN = 1e-4


class Fail(RuntimeError):
    pass


def load_json(path: Path) -> object:
    if not path.is_file():
        raise Fail(f"缺文件: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def read_crlf_json(path: Path) -> dict:
    return json.loads(path.read_bytes().decode("utf-8"))


def dump_crlf(payload: dict) -> bytes:
    text = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    assert "\r" not in text
    return text.replace("\n", "\r\n").encode("utf-8")


def build() -> dict:
    catalog = load_json(CATALOG_PATH)
    manifest = load_json(MANIFEST_PATH)
    summary = load_json(SUMMARY_PATH)
    if not isinstance(catalog, dict) or not isinstance(manifest, dict) or not isinstance(summary, dict):
        raise Fail("catalog / manifest / summary 必须是 JSON 对象")

    catalog_by_id = {pkg["component_id"]: pkg for pkg in catalog["packages"]}
    manifest_by_pkg = {pkg["package_id"]: pkg for pkg in manifest["packages"]}

    missing = [cid for cid in TARGET_IDS if cid not in catalog_by_id]
    if missing:
        raise Fail(f"catalog 缺 component_id: {missing}")

    room_bounds_x: list[float] | None = None
    room_bounds_y: list[float] | None = None
    instances: list[dict] = []

    for component_id in TARGET_IDS:
        pkg = catalog_by_id[component_id]
        # catalog 的 source_package_id 在远征源里是具体批次号，与导出 slug 不等价；
        # 唯一稳定键是 component_blend 的文件名（= 组件包 slug）。
        slug = Path(str(pkg["component_blend"])).stem
        if slug not in manifest_by_pkg:
            raise Fail(f"{component_id}: manifest 里找不到 package_id={slug}")
        if slug not in summary:
            raise Fail(f"{component_id}: 导出 summary 里找不到 slug={slug}")

        mpkg = manifest_by_pkg[slug]
        spkg = summary[slug]

        # ---- 断言 1：world_origin_m == 包围盒底面中心 ----
        bmin = [float(v) for v in mpkg["bounds"]["min"]]
        bmax = [float(v) for v in mpkg["bounds"]["max"]]
        expect_origin = [
            (bmin[0] + bmax[0]) / 2.0,
            (bmin[1] + bmax[1]) / 2.0,
            bmin[2],
        ]
        got_origin = [float(v) for v in mpkg["world_origin_m"]]
        if max(abs(expect_origin[i] - got_origin[i]) for i in range(3)) > TOL_ORIGIN:
            raise Fail(
                f"{slug}: world_origin_m {got_origin} != 包围盒底面中心 {expect_origin}"
            )
        if not str(mpkg.get("local_origin_contract", "")).startswith("bottom_center_recorded"):
            raise Fail(f"{slug}: local_origin_contract 不是 bottom_center_recorded")

        # ---- 断言 2：导出包络尺寸 == manifest dimensions_m ----
        dims = [float(v) for v in mpkg["dimensions_m"]]
        exported = [float(v) for v in spkg["blender_size_xyz"]]
        if max(abs(dims[i] - exported[i]) for i in range(3)) > TOL_SIZE:
            raise Fail(f"{slug}: 导出包络 {exported} 与 manifest dimensions_m {dims} 不一致")

        # ---- 断言 3：导出只做了平移（包络 XY 居中 / 底面 z=0）⇒ 旋转恒为 0 ----
        amin = [float(v) for v in spkg["blender_aabb_min"]]
        amax = [float(v) for v in spkg["blender_aabb_max"]]
        for axis in (0, 1):
            if abs(amin[axis] + amax[axis]) > TOL_CENTER:
                raise Fail(f"{slug}: 导出包络 {axis} 轴未居中 {amin[axis]}..{amax[axis]}")
        if abs(amin[2]) > TOL_ORIGIN:
            raise Fail(f"{slug}: 导出包络底面 z != 0（{amin[2]}）")
        if 0 not in [int(v) for v in pkg["allowed_rotations_y_deg"]]:
            raise Fail(f"{slug}: catalog allowed_rotations_y_deg 不含 0")

        # ---- 断言 4：GLB 与运行时 PackedScene 都存在 ----
        glb_path = ROOT / str(spkg["glb"])
        if not glb_path.is_file():
            raise Fail(f"{slug}: 缺 GLB {glb_path}")
        prefab_path = PREFAB_DIR / slug / f"{slug}_root_top3d.tscn"
        if not prefab_path.is_file():
            raise Fail(f"{slug}: 缺运行时 PackedScene {prefab_path}")

        if slug == "base_floor_base":
            room_bounds_x = [bmin[0], bmax[0]]
            room_bounds_y = [bmin[1], bmax[1]]

        category = str(pkg.get("category", ""))
        collision_owner = "TowerFloorStage3D._build_support" if component_id in LOAD_BEARING_IDS else "none"
        instances.append(
            {
                "instance_id": f"EXCL_{slug.upper()}",
                "component_id": component_id,
                "slot_role": EXCLUSIVE_SLOT_ROLE,
                "category": category,
                "room_id": "boss",
                "position_m": [round(v, 4) for v in got_origin],
                "rotation_z_deg": 0.0,
                "scale": [1.0, 1.0, 1.0],
                "enabled": True,
                "prefab": "res://" + prefab_path.relative_to(ROOT).as_posix(),
                "bounds_size_m_godot": [round(float(v), 4) for v in spkg["godot_size_xyz"]],
                "forward_axis_godot": str(spkg["godot_front_axis"]),
                "collision_owner": collision_owner,
                "note": f"{mpkg['name_zh']}；底面离走行面 {round(bmin[2], 4)}m；导出包络 Blender {amin}..{amax}",
            }
        )

    if room_bounds_x is None or room_bounds_y is None:
        raise Fail("base_floor_base 未提供房间包络，无法确定 rooms[].bounds")

    # ---- 断言 5：房间包络 = 50x40，中心在源世界原点 ----
    size = [room_bounds_x[1] - room_bounds_x[0], room_bounds_y[1] - room_bounds_y[0]]
    declared_room = [float(v) for v in manifest["dimensions_m"][:2]]
    if max(abs(size[i] - declared_room[i]) for i in range(2)) > TOL_SIZE:
        raise Fail(f"房间包络 {size} 与 manifest dimensions_m {declared_room} 不一致")
    if abs(room_bounds_x[0] + room_bounds_x[1]) > TOL_CENTER or abs(
        room_bounds_y[0] + room_bounds_y[1]
    ) > TOL_CENTER:
        raise Fail(f"房间包络未以源世界原点居中: x={room_bounds_x} y={room_bounds_y}")

    floor_top_m = float(manifest.get("floor_top_m", 0.0))
    base_thickness = next(
        float(manifest_by_pkg["base_floor_base"]["dimensions_m"][2]) for _ in [0]
    )

    payload = {
        "schema": SCHEMA,
        "schema_version": 1,
        "scene_id": SCENE_ID,
        "block_id": "expedition",
        "display_name_zh": "远征关卡01 · Boss竞技场（故障数据库 50×40）· 专属件摆位源",
        "level_kind": "procedural_expedition_room",
        "layout_version": LAYOUT_VERSION,
        "scope": "exclusive_only",
        "scope_note": (
            "本摆位源只登记 6 件专属件。墙体 / L拐角 / 地砖 / 门扇 / 门墙由区块级 5m 通用件"
            "组合器 RoomShellLayoutBuilder3D 在运行时按房间尺寸与门位现算（门位随每局 constrained"
            " 版图变），不写死在本文件。"
        ),
        "floor_anchor": "远征关卡01 单层（floor_index 0；房间席位由 constrained 版图每局现算）",
        "source_room_type_manifest": "res://" + MANIFEST_PATH.relative_to(ROOT).as_posix(),
        "component_library": "res://" + CATALOG_PATH.relative_to(ROOT).as_posix(),
        "runtime_prefab_root": "res://" + PREFAB_DIR.relative_to(ROOT).as_posix(),
        "grid_unit_m": 5.0,
        "wall_structure_half_thickness_m": 0.15,
        "visible_wall_height_m": 11.9,
        "floor_top_m": floor_top_m,
        "coordinate_contract": {
            "axis": "Blender Z-up；X=东、Y=北；Blender(x,y,z) --export_yup--> Godot(x, z, -y)",
            "runtime_position": "position_m = 该件 GLB 原点（底面中心）在源房间世界系的坐标；房间中心 = 源世界原点",
            "room_local": "Godot 房间局部 = (bx - cbx, bz, -(by - cby))；cbx/cby = 本文件 rooms[].bounds 中心",
            "rotation": "rotation_z_deg 为 Blender 绕 Z 旋转；与 Godot rotation.y 同值（同号）。本房 6 件全 0",
            "origin_contract": "每件 GLB 原点 = 底面中心（XY 居中、底面 z=0）；导出仅平移、不改朝向",
            "derived_local_position_godot": (
                "instances[].derived_local_position_godot 是 position_m 按上式现算的派生值，"
                "仅供审阅与探针比对，不是真源；真源是 position_m。"
            ),
        },
        "placement_model": (
            "房间先按 constrained 版图定席位与门位 → 5m 通用件组合器出壳体实例 → 本文件 6 件专属件"
            "按房间局部坐标叠加。专属件全部 visual_only、包内 0 碰撞，不参与阻挡与导航。"
        ),
        "rooms": [
            {
                "room_id": "boss",
                "name_zh": "Boss竞技场（故障数据库）",
                "bounds_x_m": [round(v, 4) for v in room_bounds_x],
                "bounds_y_m": [round(v, 4) for v in room_bounds_y],
                "size_m": [round(size[0], 4), round(size[1], 4)],
                "exclusive_only": True,
            }
        ],
        "instances": instances,
        "notes": [
            f"base_floor_base 厚 {round(base_thickness, 4)}m，房间 manifest 的 floor_top_m = {floor_top_m}m，"
            "差 0.04m；本轮只登记事实不裁决，落地以 TowerFloorStage3D 支撑顶面为准。",
            "source_room_type_manifest.ports 记的是来源竞技场的语义门位（南进西出），不是本关版图门位；"
            "本关门位由 RoomDoorLane 从邻接几何推，本文件不含门。",
        ],
        "validation": {
            "instance_count": len(instances),
            "slot_role_counts": {EXCLUSIVE_SLOT_ROLE: len(instances)},
            "exclusive_component_ids": list(TARGET_IDS),
            "room_owned_geometry": False,
            "non_unit_scale_count": 0,
            "illegal_rotation_count": 0,
            "missing_components": [],
            "centered_export_aabb": True,
        },
    }

    # 派生房间局部坐标（写进实例，供审阅 / 探针比对）。
    cbx = (room_bounds_x[0] + room_bounds_x[1]) / 2.0
    cby = (room_bounds_y[0] + room_bounds_y[1]) / 2.0
    for inst in payload["instances"]:
        bx, by, bz = (float(v) for v in inst["position_m"])
        inst["derived_local_position_godot"] = [
            round(bx - cbx + 0.0, 4),
            round(bz + 0.0, 4),
            round(-(by - cby) + 0.0, 4),
        ]
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--write", action="store_true", help="重新生成并落盘")
    group.add_argument("--check", action="store_true", help="比对已落盘文件，漂移即退出码 1")
    args = parser.parse_args()

    try:
        payload = build()
    except Fail as exc:
        print(f"[FAIL] {exc}")
        return 1

    blob = dump_crlf(payload)

    if args.write:
        OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT_PATH.write_bytes(blob)
        print(f"[WRITE] {OUTPUT_PATH.relative_to(ROOT).as_posix()}  ({len(blob)} bytes)")
        return 0

    if not OUTPUT_PATH.is_file():
        print(f"[FAIL] 摆位源缺失: {OUTPUT_PATH.relative_to(ROOT).as_posix()}")
        return 1
    on_disk = OUTPUT_PATH.read_bytes()
    if on_disk != blob:
        print(
            "[FAIL] 摆位源与源数据不一致（room_type_manifest / component_catalog / 导出 summary 有改动）"
            f"：{OUTPUT_PATH.relative_to(ROOT).as_posix()}"
        )
        try:
            current = read_crlf_json(OUTPUT_PATH)
            want = payload
            for key in sorted(set(current) | set(want)):
                if current.get(key) != want.get(key):
                    print(f"  差异字段: {key}")
        except Exception as exc:  # noqa: BLE001
            print(f"  （无法逐字段比对: {exc}）")
        print("  修复: python scripts/build_expedition01_boss_room_layout.py --write")
        return 1

    count = len(payload["instances"])
    print(f"[OK] Boss 房专属件摆位源一致：{count} 件 / schema={SCHEMA} / {LAYOUT_VERSION}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
