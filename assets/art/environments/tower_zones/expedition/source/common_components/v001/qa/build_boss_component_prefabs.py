# -*- coding: utf-8 -*-
"""为远征关卡01 Boss 房 6 件专属组件生成自包含 PackedScene（范式 B）。

上游：export_boss_shell_components.py 已把 6 件导成 GLB 到
       assets/art/environments/tower_zones/expedition/components/common_components/<slug>/
本脚本接着按范式 B 建稳定根 tscn 到
       assets/art/environments/tower_zones/expedition/runtime/common_components/<slug>/

范式 B 正本 = 战局通用组件库 battle/runtime/common_components/*（模型 + 契约同包，逐实例化）。

碰撞判定（逐件，遵循入口安全房 v007 已确立的同类件判例）：
  * 地板底盘      → 承重底板，碰撞归 TowerFloorStage3D._build_support()，包内不持有。
                    同判例：battle/runtime/entry_safe_room/floor_base。
  * 主屏          → 底面离走行面 3.805 m，玩家够不着 → 不持有阻挡。
                    同判例：entry_safe_room/north_nexus_sign（6.28 m）。
  * 粗重桥架      → 支撑管网，轴向包络 47.31×32.30 m；实心盒会封死整个房间，
                    故不按包络盒持有阻挡。同判例：entry_safe_room/overhead_services。
                    ⚠ 本件是 6 件里唯一「底部落在走行面附近」的实体，若后续美术确认
                    它确实占据玩家通路，须由房间层另行下发分段碰撞盒，不能改用包络盒。
  * 墙面标识      → 底面离走行面 7.446 m，够不着 → 不持有阻挡。
  * 入口地砖标识  → 12 mm 地面贴花 → 不持有阻挡。同判例：entry_safe_room/debris_papers。
  * 固定碎屑      → 220 mm 地面固定碎屑 → 不持有阻挡。

单一真源：字段取自 component_catalog.json（v001）＋ export_boss_shell_components_summary.json。
本脚本只做「catalog → tscn」的机械翻译＋上面这张已裁决的碰撞决定表，不再另断尺寸。
"""

from __future__ import annotations

import json
from pathlib import Path

def _find_root(start: Path) -> Path:
    """向上找到含 project.godot 的项目根，避免按层数硬编码。"""
    for p in [start, *start.parents]:
        if (p / "project.godot").is_file():
            return p
    raise SystemExit("找不到项目根（缺 project.godot）")


ROOT = _find_root(Path(__file__).resolve().parent)
BASE = ROOT / "assets/art/environments/tower_zones/expedition"
SRC = BASE / "source/common_components/v001"
CATALOG = SRC / "component_catalog.json"
SUMMARY = SRC / "qa/export_boss_shell_components_summary.json"
GLB_DIR = "assets/art/environments/tower_zones/expedition/components/common_components"
OUT_BASE = BASE / "runtime/common_components"

LIBRARY_ID = "ENV-EXPEDITION-L01-COMMON-COMPONENT-LIBRARY"
LIBRARY_ROOT = "res://assets/art/environments/tower_zones/expedition"

# —— 已裁决的编辑性决定（不来自 catalog，故显式登记在这里）——
DECISIONS: dict[str, dict[str, str]] = {
    "base_floor_base": {
        "node": "ExpeditionCommonBaseFloorBase",
        "display": "Boss房通用地板底盘 50×0.26×40m（承重归 TowerFloorStage3D）",
        "owner": "TowerFloorStage3D._build_support",
        "policy": "external_owner_no_shape_in_package",
        "reason": "承重底板，碰撞归 TowerFloorStage3D._build_support()，包内不持有"
                  "（与安全房 floor_base 同判例）",
        "contract": "structurally load-bearing; a replacement must keep bounds_size_m and seat the "
                    "5m floor tiles on its 0.26m top face; no shape in package",
    },
    "main_fault_screen": {
        "node": "ExpeditionCommonMainFaultScreen",
        "display": "Boss房主屏_破损数据库 21.52×7.09×1.575m（底面悬于走行面上方 3.805m）",
        "owner": "none",
        "policy": "no_blocking_by_design",
        "reason": "主屏底面离走行面 3.805m，超出玩家身位，够不着"
                  "（与安全房 north_nexus_sign 同判例）",
        "contract": "replaceable visual only; a replacement must keep bounds_size_m; must not change "
                    "room size, 5m grid, collision or navigation",
    },
    "heavy_conduits": {
        "node": "ExpeditionCommonHeavyConduits",
        "display": "Boss房粗重电线管与桥架 47.31×3.67×32.30m（支撑管网）",
        "owner": "none",
        "policy": "no_blocking_by_design",
        "reason": "支撑管网；轴向包络 47.31×32.30m，实心盒会封死整个房间，故不按包络盒持有阻挡"
                  "（与安全房 overhead_services 同判例）",
        "contract": "replaceable visual only; a replacement must keep bounds_size_m; must not change "
                    "room size, 5m grid, collision or navigation",
    },
    "north_wall_typography": {
        "node": "ExpeditionCommonNorthWallTypography",
        "display": "Boss房数据库墙面标识 35.90×2.32×0.042m（底面离走行面 7.446m）",
        "owner": "none",
        "policy": "no_blocking_by_design",
        "reason": "墙面标识，底面离走行面 7.446m，够不着（与安全房 north_nexus_sign 同判例）",
        "contract": "replaceable visual only; a replacement must keep bounds_size_m; must not change "
                    "room size, 5m grid, collision or navigation",
    },
    "south_floor_marking": {
        "node": "ExpeditionCommonSouthFloorMarking",
        "display": "Boss房入口地砖标识 3.70×0.012×2.73m（12mm 地面贴花）",
        "owner": "none",
        "policy": "no_blocking_by_design",
        "reason": "12mm 地面贴花，属地面装饰不属障碍（与安全房 debris_papers 同判例）",
        "contract": "replaceable visual only; a replacement must keep bounds_size_m; must not change "
                    "room size, 5m grid, collision or navigation",
    },
    "debris_00": {
        "node": "ExpeditionCommonDebris00",
        "display": "Boss房固定碎屑_00 2.43×0.22×1.99m（220mm 地面固定碎屑）",
        "owner": "none",
        "policy": "no_blocking_by_design",
        "reason": "220mm 地面固定碎屑，属地面装饰不属障碍（与安全房 debris_papers 同判例）",
        "contract": "replaceable visual only; a replacement must keep bounds_size_m; must not change "
                    "room size, 5m grid, collision or navigation",
    },
}

ORDER = [
    "base_floor_base",
    "main_fault_screen",
    "heavy_conduits",
    "north_wall_typography",
    "south_floor_marking",
    "debris_00",
]


def res(rel_posix: str) -> str:
    return "res://" + rel_posix


def fmt3(vals) -> str:
    """Godot Vector3 打印：整数不带小数尾巴，非整数最多 6 位有效小数。"""
    out = []
    for v in vals:
        f = float(v)
        if abs(f - round(f)) < 1e-9:
            out.append(str(int(round(f))))
        else:
            out.append(("%.6f" % f).rstrip("0").rstrip("."))
    return "Vector3(%s)" % ", ".join(out)


def build(slug: str, pkg: dict, summ: dict) -> str:
    d = DECISIONS[slug]
    b = pkg["bounds_size_m"]                     # Blender 系 [x, y, z]
    g = [b[0], b[2], b[1]]                       # Godot Y-up 系 [x, y, z]
    assert abs(g[0] - summ["godot_size_xyz"][0]) < 2e-4
    assert abs(g[1] - summ["godot_size_xyz"][1]) < 2e-4
    assert abs(g[2] - summ["godot_size_xyz"][2]) < 2e-4

    glb = res(f"{GLB_DIR}/{slug}/{slug}_visual_top3d.glb")
    src_blend = res(pkg["component_blend"])
    cat_rel = pkg["component_id"]

    L: list[str] = []
    L.append("[gd_scene load_steps=2 format=3]")
    L.append("")
    L.append(f"; Stable AssetID: {cat_rel}")
    L.append(f"; 远征关卡01 · Boss房通用组件库 v001 · {pkg['category']} · {slug}")
    L.append("; 范式 B（自包含可替换组件）：视觉 GLB + 稳定根；摆位与契约写在 metadata。")
    L.append("; 原点契约 = 底面中心（Blender 底面 Z=0 → Godot 底面 Y=0），与战局通用组件库一致。")
    L.append(f"; 本件无内嵌玩法阻挡：{d['reason']}")
    L.append(f"; 正面轴向：源 Blender {pkg['front_axis']} → Godot {pkg['godot_front_axis']}。")
    L.append(f"; 源 catalog: {CATALOG.relative_to(ROOT).as_posix()}")
    L.append("")
    L.append(f'[ext_resource type="PackedScene" path="{glb}" id="1_visual"]')
    L.append("")
    L.append(f'[node name="{d["node"]}" type="Node3D"]')
    L.append(f'metadata/asset_id = "{pkg["component_id"]}"')
    L.append('metadata/asset_version = "v001"')
    L.append(f'metadata/library_id = "{LIBRARY_ID}"')
    L.append(f'metadata/library_root = "{LIBRARY_ROOT}"')
    L.append(f'metadata/category = "{pkg["category"]}"')
    L.append(f'metadata/component = "{slug}"')
    L.append(f'metadata/logic_id = "{slug}"')
    L.append(f'metadata/display_name_zh = "{d["display"]}"')
    L.append(f'metadata/source_blend = "{src_blend}"')
    L.append(f'metadata/source_collection = "{pkg["collection"]}"')
    L.append(f'metadata/source_root_object = "{pkg["root_object"]}"')
    L.append('metadata/origin_contract = "bottom_center"')
    L.append(f'metadata/forward_axis = "{pkg["godot_front_axis"]}"')
    L.append('metadata/up_axis = "+Y"')
    L.append(f'metadata/blender_forward_axis = "{pkg["front_axis"]}"')
    L.append('metadata/blender_up_axis = "+Z"')
    L.append(f"metadata/bounds_size_m = {fmt3(g)}")
    L.append('metadata/bounds_note = "bounds_size_m 是组件轴向包络盒（Godot Y-up 系）；'
             '源 Blender 尺寸见 catalog 的 bounds_size_m。"')
    L.append("metadata/preserve_authored_palette = true")
    L.append("metadata/visual_only = true")
    L.append('metadata/geometry_ownership = "boss_room_shared_component"')
    L.append(f'metadata/replacement_contract = "{d["contract"]}"')
    L.append(f'metadata/collision_owner = "{d["owner"]}"')
    L.append(f'metadata/collision_policy = "{d["policy"]}"')
    L.append("metadata/collision_shape_count = 0")
    L.append(f'metadata/collision_exclusion_reason = "{d["reason"]}"')
    L.append('metadata/runtime_instantiation = "per_instance_prefab"')
    L.append("")
    L.append('[node name="ImportedModel" parent="." instance=ExtResource("1_visual")]')
    L.append("")
    return "\r\n".join(L)


def main() -> int:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    pkgs = catalog["packages"] if isinstance(catalog, dict) else catalog
    by_slug = {p["source_package_id"]: p for p in pkgs}
    summary = json.loads(SUMMARY.read_text(encoding="utf-8"))

    written = []
    for slug in ORDER:
        pkg = by_slug[slug]
        summ = summary[slug]
        assert pkg["component_id"] == summ["component_id"], slug
        text = build(slug, pkg, summ)
        out = OUT_BASE / slug / f"{slug}_root_top3d.tscn"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(text.encode("utf-8"))
        raw = out.read_bytes()
        crlf = raw.count(b"\r\n")
        bare = raw.count(b"\n") - crlf
        cr = raw.count(b"\r") - crlf
        assert bare == 0 and cr == 0, f"{slug}: 行尾不纯 bareLF={bare} bareCR={cr}"
        assert raw.startswith(b"[gd_scene load_steps=2 format=3]\r\n")
        assert b'; Stable AssetID: ' + pkg["component_id"].encode() in raw
        # 无内嵌碰撞：不应出现 StaticBody3D / BoxShape3D
        assert b"StaticBody3D" not in raw and b"BoxShape3D" not in raw, slug
        written.append((slug, out.relative_to(ROOT).as_posix(), len(raw), crlf))

    print("OK  6 件 PackedScene 已生成（范式 B，无内嵌阻挡）")
    for slug, rel, n, crlf in written:
        print(f"  - {slug:<22} {n:>5} B  CRLF={crlf:<4} {rel}")
    print(f"LIBRARY_ID = {LIBRARY_ID}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
