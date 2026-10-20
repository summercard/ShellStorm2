"""大世界 · 地下街区 编号02 · v004（街面道具 0.1m 颗粒重写）

v003 的问题不是「建筑不够细」，是**建筑细了、道具没细**：酒店 6.7k 面，旁边的
轿车 176 面、路灯 96 面、空调外机 44 面。近景一放大，道具全是方块拼的。

本版只做一件事：按业主口径 **「0.1m 的零件都要表达清楚，0.1m 以下可以不做」**
重写 24 件街面道具 / 结构构件，并给 4 栋建筑补 0.1m 级颗粒层（螺栓、管卡、
窗台滴水块、避雷支架、女儿墙分仓缝）。

量化验收：`scripts/blender/audit_granularity.py`
  · `fine_count` = 尺寸 ≤0.20m 的独立零件数（0.1m 级零件的直接计数）
  · 门槛：每米包围盒至少 8 个零件、其中 4 个是 0.1m 级
  · v003 基线：30 个组件里 28 个不达标，轿车 / 路灯 / 空调的 fine 全是 **0**

组件数与预算不变（47 ≤ 50）：本版是「原地升级几何」，不新增也不删除组件。
"""

from __future__ import annotations

import json
import math
import os
import sys

PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if os.path.join(PROJECT, "scripts", "blender") not in sys.path:
    sys.path.insert(0, os.path.join(PROJECT, "scripts", "blender"))

import bpy  # noqa: E402

import ug_street_lib_v001 as L  # noqa: E402

_PREV_LIB_ONLY = os.environ.get("UG_STREET_BUILD_LIB_ONLY")
os.environ["UG_STREET_BUILD_LIB_ONLY"] = "1"
try:
    import build_openworld_underground_street_v003 as V3  # noqa: E402
finally:
    if _PREV_LIB_ONLY is None:
        os.environ.pop("UG_STREET_BUILD_LIB_ONLY", None)
    else:
        os.environ["UG_STREET_BUILD_LIB_ONLY"] = _PREV_LIB_ONLY

import ug_props_v004 as PROP_CAR       # noqa: E402
import ug_props_v004_street as PROP_ST  # noqa: E402
import ug_props_v004_facility as PROP_FC  # noqa: E402
import ug_props_v004_roof as PROP_RF   # noqa: E402
import ug_props_v004_struct as PROP_STC  # noqa: E402
import ug_props_v004_grain as GRAIN    # noqa: E402

VERSION = "v004"
SUITE = V3.SUITE
ASSET_ID_ROOT = V3.ASSET_ID_ROOT
OUT_DIR = os.path.join(PROJECT, "art_source", "environments", "open_world", "source",
                       "underground_street", VERSION)
BLEND_PATH = os.path.join(OUT_DIR, "env_underground_street_source_%s.blend" % VERSION)
REUSED_FROM = "art_source/environments/open_world/source/underground_street/v003"

# ---------------------------------------------------------------- 细化覆盖
# 键是 v003 的 slug（不改 slug，实例引用不断），值是新的生成函数。
DETAIL_OVERRIDE = {
    # 交通工具
    "retro_cyber_sedan_car_01": PROP_CAR.c_sedan_detail,
    # 立杆类
    "industrial_street_lamp_pole_01": PROP_ST.c_street_lamp_detail,
    "traffic_signal_mast_02": PROP_ST.c_signal_mast_detail,
    "street_guardrail_fence_4m_01": PROP_ST.c_guardrail_detail,
    "glowing_hazard_bollard_02": PROP_ST.c_bollard_detail,
    # 设施类
    "street_utility_cabinet_02": PROP_FC.c_cabinet_detail,
    "drain_manhole_grate_set_01": PROP_FC.c_manhole_detail,
    "wall_ac_outdoor_unit_03": PROP_FC.c_wall_ac_detail,
    "facade_pipe_cluster_vertical_01": PROP_FC.c_pipe_cluster_detail,
    "facade_pipe_elbow_horizontal_02": PROP_FC.c_pipe_elbow_detail,
    "vending_machine_bank_02": PROP_FC.c_vending_detail,
    "hanging_lamp_industrial_01": PROP_FC.c_hanging_lamp_detail,
    "ceiling_exhaust_fan_3x3_01": PROP_FC.c_ceiling_fan_detail,
    # 屋顶 / 架空 / 附着
    "rooftop_exhaust_vent_box_02": PROP_RF.c_roof_vent_detail,
    "rooftop_twin_fan_chiller_01": PROP_RF.c_roof_chiller_detail,
    "neon_blade_sign_cluster_05": PROP_RF.c_blade_sign_detail,
    "street_rock_rubble_pile_04": PROP_RF.c_rubble_detail,
    "sky_cable_span_24m_01": PROP_RF.c_sky_cable_detail,
    "street_cable_harness_03": PROP_RF.c_cable_harness_detail,
    "facade_billboard_panel_03": PROP_RF.c_billboard_detail,
    # 结构构件
    "skybridge_truss_span_21m_01": PROP_STC.c_skybridge_detail,
    "skybridge_hazard_pillar_02": PROP_STC.c_bridge_pillar_detail,
    "ceiling_duct_bundle_20m_01": PROP_STC.c_duct_detail,
    "skybridge_sign_sector07_04": PROP_STC.c_sector_sign_detail,
    # 建筑：包一层 0.1m 颗粒层（不动原几何，只补螺栓/管卡/滴水块/分仓缝）
    "hotel_brick_tower_core_10x12_01": GRAIN.c_hotel_grain,
    "industrial_bar_building_10x12_01": GRAIN.c_bar_grain,
    "backdrop_tower_block_10x7_01": GRAIN.c_backdrop_grain,
    "narrow_alley_shophouse_02": GRAIN.c_alley_grain,
    "foreground_service_roof_15x15_01": GRAIN.c_service_roof_grain,
    # 窄条 / 特殊形体：招牌沿高度分件，蒸汽补碎粒
    "neon_sign_hotel_vertical_01": GRAIN.c_hotel_sign_grain,
    "neon_sign_bar_vertical_03": GRAIN.c_bar_sign_grain,
    "steam_vapor_vent_02": GRAIN.c_steam_grain,
}


COMPONENTS: list[dict] = []
for _e in V3.COMPONENTS:
    _detailed = _e["slug"] in DETAIL_OVERRIDE
    COMPONENTS.append(dict(
        slug=_e["slug"], name_zh=_e["name_zh"], family=_e["family"],
        category=_e["category"],
        builder=DETAIL_OVERRIDE.get(_e["slug"], _e["builder"]),
        note=_e.get("note", "") or "",
        reused_from=None if _detailed else REUSED_FROM,
        detailed=_detailed,
    ))

FRONT_AXIS = dict(V3.FRONT_AXIS)
FIXED_ROT = dict(V3.FIXED_ROT)
GROUP_ORDER = list(V3.GROUP_ORDER)
LAYOUT: list[dict] = []


def inst(slug, group, x, y, z=0.0, rz=0.0):
    LAYOUT.append(dict(slug=slug, group=group, loc=(x, y, z), rz=rz))


def build_layout():
    LAYOUT.clear()
    V3.build_layout()
    for it in V3.LAYOUT:
        LAYOUT.append(dict(it))

    # v001~v003 遗留的布局冲突：售货机柜 (-9.1, -8.4) 与配电柜 (-9.0, -8.6) 几乎重合，
    # 两者互相穿模（近景渲染实测：售货机整个埋在配电柜里，只露出一个角）。
    # 售货机沿墙向南挪 3.2m 到 -9.1, -11.6（药店与酒店之间的实墙段：
    # 那里没有蒸汽柱、没有配电柜、没有消防梯 —— 先试过 -4.2，正好压住蒸汽。
    for it in LAYOUT:
        if it["slug"] == "vending_machine_bank_02" and abs(it["loc"][1] + 8.4) < 0.3:
            it["loc"] = (it["loc"][0], -11.60, it["loc"][2])


def write_catalogs(records, inst_records, lo, hi):
    os.makedirs(OUT_DIR, exist_ok=True)
    pkg_root = os.path.join(OUT_DIR, "component_packages")
    if os.path.isdir(pkg_root):
        import shutil
        shutil.rmtree(pkg_root)
    os.makedirs(pkg_root, exist_ok=True)

    count_by_slug = {}
    for it in inst_records:
        count_by_slug[it["slug"]] = count_by_slug.get(it["slug"], 0) + 1

    comps = []
    for rec in records:
        e = rec["entry"]
        slug = e["slug"]
        dims = [round(v, 3) for v in rec["dims"]]
        man = {
            "schema": "shellstorm2.openworld.asset_manifest",
            "schema_version": 1,
            "asset_id": "%s-%s" % (ASSET_ID_ROOT, slug.upper()),
            "package_id": slug,
            "slug": slug,
            "name_zh": e["name_zh"],
            "suite": SUITE,
            "version": VERSION,
            "district": "地下街区",
            "category": e["category"],
            "family_id": e["family"],
            "serves_districts": ["地下街区"],
            "scope": "suite_local",
            "source_blend": os.path.relpath(BLEND_PATH, PROJECT).replace("\\", "/"),
            "reused_from": e.get("reused_from"),
            "geometry_source": "build_openworld_underground_street_%s.py::%s"
                               % (VERSION, e["builder"].__name__),
            "blender_collection": "资产包_%s" % slug,
            "source_collection": "组件源_%s" % slug,
            "objects": rec["objects"],
            "source_objects": rec["src_objects"],
            "pivot_rule": "bottom_center_z0",
            "local_origin": [0.0, 0.0, 0.0],
            "source_z_offset_m": round(rec["z_offset"], 4),
            "front_axis": FRONT_AXIS.get(slug, "+X"),
            "allowed_rotations_y_deg": FIXED_ROT.get(slug, [0, 90, 180, 270]),
            "dimensions_m": dims,
            "polygon_count": rec["polys"],
            "instance_count": count_by_slug.get(slug, 0),
            "material_roles": sorted({L.ROLE_METAL, L.ROLE_MATTE, L.ROLE_GLOSS}),
            "palette": "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png",
            "uv_layer": "PaletteUV",
            "collision": "none（Blender 源阶段；碰撞归后续 Godot 包装）",
            "export": {"glb": None, "exported": False},
            "note": e.get("note", ""),
        }
        d = os.path.join(pkg_root, slug)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "asset_manifest.json"), "w", encoding="utf-8") as f:
            json.dump(man, f, ensure_ascii=False, indent=2)
        comps.append({
            "component_id": "comp_%s" % slug,
            "slug": slug,
            "display_name": e["name_zh"],
            "family_id": e["family"],
            "category": e["category"],
            "dimensions_m": dims,
            "pivot_rule": "bottom_center_z0",
            "source_z_offset_m": round(rec["z_offset"], 4),
            "output_collection": "资产包_%s" % slug,
            "mesh_objects": rec["objects"],
            "polygon_count": rec["polys"],
            "instance_count": count_by_slug.get(slug, 0),
            "reused_from": e.get("reused_from"),
            "detailed_in_v004": bool(e.get("detailed")),
        })

    with open(os.path.join(OUT_DIR, "component_catalog.json"), "w", encoding="utf-8") as f:
        json.dump({
            "schema": "shellstorm2.openworld.component_catalog",
            "schema_version": 1,
            "suite_name": SUITE,
            "asset_id_root": ASSET_ID_ROOT,
            "version": VERSION,
            "block_id": "open_world",
            "district": "地下街区",
            "street_number": 2,
            "unique_component_count": len(comps),
            "total_instance_count": len(inst_records),
            "reused_component_count": len([c for c in comps if c["reused_from"]]),
            "new_component_count": len([c for c in comps if not c["reused_from"]]),
            "scene_bounds_m": [round(lo[k], 3) for k in range(3)]
                              + [round(hi[k], 3) for k in range(3)],
            "components": comps,
        }, f, ensure_ascii=False, indent=2)

    with open(os.path.join(OUT_DIR, "component_instances.json"), "w", encoding="utf-8") as f:
        json.dump({
            "schema": "shellstorm2.openworld.component_instances",
            "schema_version": 1,
            "suite_name": SUITE,
            "version": VERSION,
            "total_instance_count": len(inst_records),
            "note": "仅初始化与追溯；正式摆位由后续 Godot TSCN 拥有",
            "instances": inst_records,
        }, f, ensure_ascii=False, indent=2)

    fams = {}
    for c in comps:
        fams.setdefault(c["family_id"], []).append(c["slug"])
    with open(os.path.join(OUT_DIR, "component_plan.json"), "w", encoding="utf-8") as f:
        json.dump({
            "schema": "shellstorm2.openworld.component_plan",
            "schema_version": 1,
            "suite_name": SUITE,
            "version": VERSION,
            "street_number": 2,
            "component_budget": {"limit": 50, "unique": len(comps),
                                 "reused": len([c for c in comps if c["reused_from"]]),
                                 "new": len([c for c in comps if not c["reused_from"]])},
            "family_budget": "同族常规 ≤3、有明确状态轴 ≤5",
            "families": fams,
            "layout_groups": GROUP_ORDER,
            "reuse_policy": "v004 原地升级 24 件道具几何 + 5 栋建筑补颗粒层；"
                            "slug 与实例摆位不变，故不新增/不删除组件",
        }, f, ensure_ascii=False, indent=2)

    lines = ["%s (%s) - 大世界 地下街区 编号02 · 街面道具 0.1m 颗粒" % (SUITE, VERSION),
             "├── 01_制作组件_按组件拆分_%s (%d Master Components)" % (VERSION, len(records)),
             "├── 02_游戏输出_独立资产包_%s (%d Output Packages)" % (VERSION, len(records)),
             "├── 03_场景拼装_实例布局_%s (%d Collection Instances)"
             % (VERSION, len(inst_records)),
             "└── 90_展示与动态_灯光相机", "", "Components:"]
    for rec in records:
        c = rec["entry"]
        d = " × ".join("%.2f" % v for v in rec["dims"])
        tag = "  (v004 细化)" if c.get("detailed") else "  (reuse v003)"
        lines.append("  - [comp_%s] %s | %s m | polys=%d | instances=%d%s"
                     % (c["slug"], c["name_zh"], d, rec["polys"],
                        count_by_slug.get(c["slug"], 0), tag))
    with open(os.path.join(OUT_DIR, "component_tree.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main():
    L.purge_scene()
    mats = L.ensure_materials()
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    root_src = L.new_collection("01_制作组件_按组件拆分_%s" % VERSION, hide=True)
    root_pkg = L.new_collection("02_游戏输出_独立资产包_%s" % VERSION, hide=True)
    root_layout = L.new_collection("03_场景拼装_实例布局_%s" % VERSION)
    root_disp = L.new_collection("90_展示与动态_灯光相机")

    build_layout()
    groups = {g: L.new_collection(g, root_layout) for g in GROUP_ORDER}

    records = []
    pkg_colls = {}
    z_offsets = {}
    for entry in COMPONENTS:
        slug = entry["slug"]
        gpkg = L.Geo()
        entry["builder"](gpkg)
        min_z = min(v[2] for v in gpkg.verts)
        if abs(min_z) > 1e-6:
            gpkg.verts = [(v[0], v[1], v[2] - min_z) for v in gpkg.verts]
        z_offsets[slug] = min_z
        pkg = L.new_collection("资产包_%s" % slug, root_pkg)
        L.link_mesh(pkg, entry["name_zh"], gpkg, mats)
        pkg_colls[slug] = pkg
        gsrc = L.Geo()
        entry["builder"](gsrc)
        gsrc.verts = [(v[0], v[1], v[2] - min_z) for v in gsrc.verts]
        src_coll = L.new_collection("组件源_%s" % slug, root_src)
        L.link_mesh(src_coll, "源_%s" % entry["name_zh"], gsrc, mats)
        b = L.bounds_of(gpkg)
        records.append(dict(
            entry=entry,
            dims=(b[1] - b[0], b[3] - b[2], b[5] - b[4]),
            polys=L.poly_count(gpkg),
            z_offset=min_z,
            objects=[o.name for o in pkg.objects],
            src_objects=[o.name for o in src_coll.objects],
        ))

    inst_records = []
    for i, item in enumerate(LAYOUT):
        pkg = pkg_colls[item["slug"]]
        emp = bpy.data.objects.new("inst_%s_%03d" % (item["slug"], i + 1), None)
        emp.instance_type = "COLLECTION"
        emp.instance_collection = pkg
        emp.empty_display_type = "PLAIN_AXES"
        emp.empty_display_size = 0.6
        world_z = item["loc"][2] + z_offsets.get(item["slug"], 0.0)
        emp.location = (item["loc"][0], item["loc"][1], round(world_z, 6))
        emp.rotation_euler = (0.0, 0.0, math.radians(item["rz"]))
        groups[item["group"]].objects.link(emp)
        inst_records.append(dict(name=emp.name, slug=item["slug"], group=item["group"],
                                 loc=[item["loc"][0], item["loc"][1], round(world_z, 6)],
                                 rz=item["rz"]))

    lo = [1e9, 1e9, 1e9]
    hi = [-1e9, -1e9, -1e9]
    from mathutils import Vector
    for it in inst_records:
        emp = bpy.data.objects[it["name"]]
        for obj in pkg_colls[it["slug"]].all_objects:
            if obj.type != "MESH":
                continue
            for corner in obj.bound_box:
                w = emp.matrix_world @ obj.matrix_world @ Vector(corner)
                for k in range(3):
                    lo[k] = min(lo[k], w[k])
                    hi[k] = max(hi[k], w[k])

    # ---------------- 世界 / 灯光（沿用 v003 布光，只把道具近景补两盏） ----------------
    world = bpy.data.worlds.get("World") or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.010, 0.013, 0.024, 1.0)
        bg.inputs[1].default_value = 1.0

    def add_light(name, kind, loc, energy, color, rot=(0, 0, 0), size=None, spot=None):
        data = bpy.data.lights.new(name, kind)
        data.energy = energy
        data.color = color
        if kind == "AREA" and size:
            data.size = size
        if kind == "SPOT" and spot:
            data.spot_size = spot
            data.spot_blend = 0.45
        obj = bpy.data.objects.new(name, data)
        obj.location = loc
        obj.rotation_euler = rot
        root_disp.objects.link(obj)
        return obj

    add_light("补光_顶棚主光", "AREA", (0, 0, 26.6), 3200, (0.60, 0.71, 1.0), (0, 0, 0), size=30)
    add_light("补光_街心冷光", "AREA", (0, 0, 14.0), 1200, (0.52, 0.66, 1.0), (0, 0, 0), size=16)
    add_light("酒店洗墙_主", "AREA", (-8.6, 5.20, 17.0), 46, (0.66, 0.72, 1.0),
              (math.radians(52), 0, math.radians(90)), size=7)
    add_light("酒店洗墙_低", "AREA", (-8.8, 0.20, 4.60), 18, (0.62, 0.70, 1.0),
              (math.radians(74), 0, math.radians(90)), size=4)
    add_light("酒吧洗墙_主", "AREA", (8.6, -6.40, 12.0), 40, (0.70, 0.74, 1.0),
              (math.radians(56), 0, math.radians(-90)), size=6)
    add_light("药店洗墙_主", "AREA", (-8.5, -9.2, 8.6), 42, (0.62, 0.74, 1.0),
              (math.radians(58), 0, math.radians(90)), size=6)
    add_light("药店洗墙_补", "AREA", (-8.7, -12.4, 2.4), 16, (0.58, 0.70, 1.0),
              (math.radians(72), 0, math.radians(90)), size=4)
    add_light("霓虹_酒店粉", "POINT", (-8.4, -1.40, 10.6), 300, (1.0, 0.16, 0.34))
    add_light("霓虹_药店青", "POINT", (-8.4, -9.6, 5.0), 200, (0.20, 0.90, 0.86))
    add_light("霓虹_酒吧红", "POINT", (8.4, -9.6, 10.2), 240, (1.0, 0.2, 0.28))
    add_light("霓虹_高架橙", "POINT", (-1.0, 8.6, 12.4), 220, (1.0, 0.62, 0.18))
    add_light("街口射灯", "SPOT", (5.0, -14.0, 12.6), 300, (0.72, 0.82, 1.0),
              (math.radians(63), 0, math.radians(-24)), spot=math.radians(58))
    add_light("酒店门头暖光", "SPOT", (-8.2, 0.4, 3.6), 220, (1.0, 0.55, 0.3),
              (math.radians(74), 0, math.radians(90)), spot=math.radians(60))
    add_light("蒸汽逆光", "SPOT", (-1.0, 4.4, 6.0), 240, (0.75, 0.86, 1.0),
              (math.radians(96), 0, math.radians(-150)), spot=math.radians(46))
    add_light("地面回光_酒店粉", "POINT", (-6.0, 1.4, 1.2), 120, (1.0, 0.22, 0.40))
    add_light("地面回光_药店青", "POINT", (-6.4, -6.0, 1.0), 90, (0.16, 0.92, 0.86))
    add_light("地面回光_酒吧红", "POINT", (6.6, 0.0, 1.2), 110, (1.0, 0.24, 0.30))
    add_light("地面回光_桥底橙", "POINT", (0.0, 12.0, 1.4), 80, (1.0, 0.62, 0.20))
    # 道具近景补光：路灯 / 车 / 护栏的 0.1m 零件全在暗部，没有掠射光看不出结构。
    # 车身那两盏是实测需要的：车停在 (-2.6,-16)，正好是这条街最暗的一段（两侧
    # 建筑都高、又不在任何灯下），只靠场景主光时整车像素值只有 8–15，
    # 结构完全不可见。低功率面光补到 40–60 就够读出闸门缝与轮拱。
    add_light("道具_路灯侧光", "AREA", (6.0, -10.0, 5.6), 60, (0.70, 0.80, 1.0),
              (math.radians(80), 0, math.radians(-70)), size=3)
    add_light("道具_车身侧光", "AREA", (-2.6, -20.4, 3.0), 90, (0.76, 0.84, 1.0),
              (math.radians(78), 0, 0), size=6)
    add_light("道具_车身补光", "AREA", (0.8, -19.6, 1.9), 55, (0.72, 0.80, 1.0),
              (math.radians(84), 0, math.radians(40)), size=5)

    cam_data = bpy.data.cameras.new("CAM_参考构图")
    cam_data.lens = 22
    cam_obj = bpy.data.objects.new("CAM_参考构图", cam_data)
    cam_obj.location = (10.5, -23.0, 17.0)
    root_disp.objects.link(cam_obj)
    d = Vector((-5.0, 2.0, 5.5)) - cam_obj.location
    cam_obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam_obj

    top_data = bpy.data.cameras.new("CAM_俯视正交")
    top_data.type = "ORTHO"
    top_data.ortho_scale = 54
    top_cam = bpy.data.objects.new("CAM_俯视正交", top_data)
    top_cam.location = (0, 0, 70)
    root_disp.objects.link(top_cam)

    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.render.film_transparent = False
    eevee = getattr(scene, "eevee", None)
    if eevee is not None:
        if hasattr(eevee, "taa_render_samples"):
            eevee.taa_render_samples = 48
        if hasattr(eevee, "use_raytracing"):
            eevee.use_raytracing = True
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 1.15

    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH, check_existing=False)
    try:
        bpy.ops.file.make_paths_relative()
        bpy.ops.wm.save_mainfile()
    except Exception as exc:
        print("WARN make_paths_relative:", exc)

    write_catalogs(records, inst_records, lo, hi)
    print(json.dumps({
        "blend": BLEND_PATH,
        "components": len(records),
        "instances": len(inst_records),
        "polygons": sum(r["polys"] for r in records),
        "scene_bounds_m": [round(lo[k], 3) for k in range(3)]
                          + [round(hi[k], 3) for k in range(3)],
        "materials": [m.name for m in bpy.data.materials],
    }, ensure_ascii=False))


if os.environ.get("UG_STREET_BUILD_LIB_ONLY") != "1":
    try:
        main()
    except Exception as exc:
        import traceback
        traceback.print_exc()
        print("BUILD_FAILED:", exc)
        raise
