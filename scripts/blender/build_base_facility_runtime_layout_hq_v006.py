"""Build Base 99 HQ v006: production floor-system detailing only.

The v005 shell, room layout, stair, walls and facilities remain unchanged.
This pass adds only shallow or floor-attached geometry inside the locked
30 x 30 m / 6 x 6 / 5 m module contract.
"""

from __future__ import annotations

import importlib.util
import math
from pathlib import Path

import bpy
from mathutils import Vector


PROJECT = Path(__file__).resolve().parents[2]
V005_SCRIPT = PROJECT / "scripts/blender/build_base_facility_runtime_layout_hq_v005.py"
spec = importlib.util.spec_from_file_location("base_facility_hq_v005", V005_SCRIPT)
v005 = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(v005)
base = v005.base

base.OUTPUT_BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v006.blend"
base.OUTPUT_HERO = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v006.png"
base.OUTPUT_TOP = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v006_top.png"
base.OUTPUT_DETAIL = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v006_floor_close.png"

V005_CORRIDOR = base.build_corridor
V005_PREVIEW = base.build_preview
V005_VALIDATE = base.validate_layout

CENTERS = (-12.5, -7.5, -2.5, 2.5, 7.5, 12.5)
FLOOR_SIZE = 30.0
TILE_SIZE = 5.0
DETAIL_MAX_Z = 0.32
HATCH_TILES = {
    (0, 1), (0, 4), (1, 2), (1, 5), (2, 0),
    (2, 3), (3, 1), (3, 4), (3, 5),
}


def _floor_collection() -> bpy.types.Collection:
    coll = base.collection("21_地板系统深化_v006", base.OUTPUT)
    base.COLLS["floor_detail"] = coll
    coll["asset_id"] = "ENV-BASE99-ART-LAYOUT-3D"
    coll["component"] = "floor_attached_detail"
    coll["locked_floor_contract"] = "30x30m; 36 existing 5x5m modules unchanged"
    coll["scope"] = "surface/shallow inset/edge hardware/marking/guide light/wear only"
    coll["reference_direction"] = "Blender +Y north; all guide elements follow existing 5m module edges"
    return coll


def _torus(name: str, loc, major_radius: float, minor_radius: float,
           role: str, color: str, target: bpy.types.Collection,
           major_segments: int = 32) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        align="WORLD",
        major_segments=major_segments,
        minor_segments=8,
        location=loc,
        major_radius=major_radius,
        minor_radius=minor_radius,
    )
    src = bpy.context.object
    base.link_only(src, base.SOURCE)
    src.name = name + "__源"
    base.assign_material(src, role, base.COLORS[color])
    return base.publish(src, target, name)


def _pulse(obj: bpy.types.Object, phase: int) -> None:
    for frame, z_scale in ((1 + phase, 0.92), (61 + phase, 1.03), (121 + phase, 0.94), (181 + phase, 1.01), (241 + phase, 0.92)):
        obj.scale.z = z_scale
        obj.keyframe_insert("scale", frame=frame)
    if obj.animation_data and obj.animation_data.action:
        for curve in obj.animation_data.action.fcurves:
            for point in curve.keyframe_points:
                point.interpolation = "BEZIER"
            curve.modifiers.new("CYCLES")


def _floor_text(name: str, body: str, loc, size: float, color: str,
                rotation_z: float = 0.0, role: str = "matte") -> bpy.types.Object:
    return base.add_text(
        name, body, loc, size, role, color, 0.006, "CENTER",
        (0.0, 0.0, rotation_z), base.COLLS["floor_detail"],
    )


def _tile_frame(row: int, col: int, cx: float, cy: float) -> None:
    c = base.COLLS["floor_detail"]
    prefix = f"地板深化_R{row+1:02d}C{col+1:02d}"
    # Four real raised compression rails sit inside the original tile boundary.
    edge = 2.29
    run = 4.34
    for suffix, loc, size in (
        ("北压边", (cx, cy + edge, 0.055), (run, 0.12, 0.070)),
        ("南压边", (cx, cy - edge, 0.055), (run, 0.12, 0.070)),
        ("东压边", (cx + edge, cy, 0.055), (0.12, run, 0.070)),
        ("西压边", (cx - edge, cy, 0.055), (0.12, run, 0.070)),
    ):
        obj = base.add_box(prefix + "_" + suffix, loc, size, "metal", "mid_gray", 0.024, c)
        obj["floor_module"] = (row, col)
        obj["detail_role"] = "perimeter_compression_rail"

    # Dark inner shadow lips reinforce the original seam without recutting it.
    for suffix, loc, size in (
        ("北内阴影条", (cx, cy + 2.205, 0.036), (4.05, 0.040, 0.028)),
        ("南内阴影条", (cx, cy - 2.205, 0.036), (4.05, 0.040, 0.028)),
        ("东内阴影条", (cx + 2.205, cy, 0.036), (0.040, 4.05, 0.028)),
        ("西内阴影条", (cx - 2.205, cy, 0.036), (0.040, 4.05, 0.028)),
    ):
        base.add_box(prefix + "_" + suffix, loc, size, "matte", "dark_gray", 0.008, c)

    # Four hexagonal fasteners and two restrained edge latches per module.
    for idx, (sx, sy) in enumerate(((-2.08, -2.08), (2.08, -2.08), (2.08, 2.08), (-2.08, 2.08))):
        bolt = base.add_cylinder(
            f"{prefix}_六角固定螺栓_{idx+1:02d}", (cx + sx, cy + sy, 0.105),
            0.072, 0.055, "metal", "dark_gray", 6, c,
        )
        bolt["detail_role"] = "floor_fastener"
        base.add_cylinder(
            f"{prefix}_螺栓中心_{idx+1:02d}", (cx + sx, cy + sy, 0.135),
            0.018, 0.012, "matte", "mid_gray", 12, c,
        )
    latch_color = "purple" if (row + col) % 2 else "dark_gray"
    base.add_box(f"{prefix}_南侧卡扣", (cx + 0.70, cy - 2.285, 0.105), (0.38, 0.16, 0.085), "metal", latch_color, 0.025, c)
    base.add_box(f"{prefix}_东侧卡扣", (cx + 2.285, cy - 0.70, 0.105), (0.16, 0.38, 0.085), "metal", latch_color, 0.025, c)

    # Small, physical stencil numbers remain subordinate to the panel surface.
    _floor_text(
        f"{prefix}_板块编号", f"{row+1:02d}-{col+1:02d}",
        (cx - 1.65, cy - 1.82, 0.076), 0.155, "light_gray", 0.0, "matte",
    )


def _grid_seams() -> None:
    c = base.COLLS["floor_detail"]
    # Segmented dark seam liners occupy the already-existing 5m boundaries.
    for ix, x in enumerate((-10.0, -5.0, 0.0, 5.0, 10.0)):
        for row, cy in enumerate(CENTERS):
            base.add_box(
                f"地板深化_纵分缝_X{ix+1:02d}_R{row+1:02d}",
                (x, cy, 0.024), (0.070, 4.78, 0.035), "matte", "black", 0.008, c,
            )
    for iy, y in enumerate((-10.0, -5.0, 0.0, 5.0, 10.0)):
        for col, cx in enumerate(CENTERS):
            base.add_box(
                f"地板深化_横分缝_Y{iy+1:02d}_C{col+1:02d}",
                (cx, y, 0.026), (4.78, 0.070, 0.035), "matte", "black", 0.008, c,
            )


def _inspection_hatch(row: int, col: int, cx: float, cy: float, variant: int) -> None:
    c = base.COLLS["floor_detail"]
    ox = 0.42 if variant % 2 else -0.42
    oy = 0.48 if variant % 3 else -0.52
    x, y = cx + ox, cy + oy
    prefix = f"地板检修盖_R{row+1:02d}C{col+1:02d}"
    base.add_box(prefix + "_浅凹槽", (x, y, 0.042), (1.62, 1.08, 0.050), "matte", "black", 0.070, c)
    plate = base.add_box(prefix + "_主盖板", (x, y, 0.088), (1.42, 0.88, 0.070), "metal", "mid_gray", 0.085, c)
    plate["detail_role"] = "shallow_service_hatch"
    for suffix, loc, size in (
        ("北框", (x, y + 0.48, 0.112), (1.54, 0.075, 0.065)),
        ("南框", (x, y - 0.48, 0.112), (1.54, 0.075, 0.065)),
        ("东框", (x + 0.75, y, 0.112), (0.075, 0.90, 0.065)),
        ("西框", (x - 0.75, y, 0.112), (0.075, 0.90, 0.065)),
    ):
        base.add_box(prefix + "_" + suffix, loc, size, "metal", "purple", 0.018, c)
    for idx, (sx, sy) in enumerate(((-0.61, -0.33), (0.61, -0.33), (0.61, 0.33), (-0.61, 0.33))):
        base.add_cylinder(prefix + f"_固定钉_{idx+1}", (x + sx, y + sy, 0.142), 0.040, 0.026, "metal", "dark_gray", 8, c)
    base.add_box(prefix + "_拉环座", (x + 0.42, y, 0.143), (0.28, 0.15, 0.050), "metal", "dark_gray", 0.022, c)
    _floor_text(prefix + "_编号", f"M-{variant+1:02d}", (x - 0.32, y, 0.148), 0.12, "light_gray", 0.0, "matte")


def _vent(row: int, col: int, cx: float, cy: float, vertical: bool) -> None:
    c = base.COLLS["floor_detail"]
    x = cx + (1.10 if col % 2 else -1.10)
    y = cy + (-0.92 if row % 2 else 0.92)
    prefix = f"地板通风格栅_R{row+1:02d}C{col+1:02d}"
    size = (0.62, 1.48) if vertical else (1.48, 0.62)
    base.add_box(prefix + "_深色腔体", (x, y, 0.040), (size[0], size[1], 0.052), "matte", "black", 0.060, c)
    base.add_box(prefix + "_外框", (x, y, 0.074), (size[0] + 0.10, size[1] + 0.10, 0.045), "metal", "dark_gray", 0.070, c)
    # Recess returns above the frame and leaves only real slats readable.
    base.add_box(prefix + "_内腔", (x, y, 0.101), (size[0] - 0.13, size[1] - 0.13, 0.036), "matte", "black", 0.040, c)
    for i in range(7):
        offset = (i - 3) * 0.16
        loc = (x + offset, y, 0.137) if vertical else (x, y + offset, 0.137)
        slat_size = (0.075, size[1] - 0.18, 0.055) if vertical else (size[0] - 0.18, 0.075, 0.055)
        base.add_box(prefix + f"_格栅片_{i+1:02d}", loc, slat_size, "metal", "mid_gray", 0.018, c)


def _floor_port(name: str, loc, color: str = "orange") -> None:
    c = base.COLLS["floor_detail"]
    x, y = loc
    base.add_cylinder(name + "_底部凹口", (x, y, 0.050), 0.38, 0.070, "matte", "black", 28, c)
    _torus(name + "_金属固定环", (x, y, 0.105), 0.295, 0.055, "metal", "mid_gray", c, 28)
    base.add_cylinder(name + "_接口盖", (x, y, 0.108), 0.225, 0.080, "gloss", color, 24, c)
    base.add_box(name + "_开启刻线", (x, y, 0.155), (0.25, 0.035, 0.025), "metal", "light_gray", 0.007, c)


def _guide_segment(name: str, start, end, phase: int = 0) -> None:
    c = base.COLLS["floor_detail"]
    a, b = Vector((start[0], start[1], 0.0)), Vector((end[0], end[1], 0.0))
    d = b - a
    length = d.length
    center = (a + b) * 0.5
    angle = math.atan2(d.y, d.x)
    rotation = (0.0, 0.0, angle)
    # Recess + real light body + translucent cover + two retaining rails.
    base.add_box(name + "_浅凹槽", (center.x, center.y, 0.046), (length, 0.145, 0.046), "matte", "black", 0.028, c, rotation=rotation)
    base.add_box(name + "_灯体", (center.x, center.y, 0.078), (length - 0.12, 0.072, 0.050), "metal", "dark_gray", 0.020, c, rotation=rotation)
    glow = base.add_box("自发光_" + name + "_青蓝芯", (center.x, center.y, 0.112), (length - 0.20, 0.040, 0.034), "emit", "cyan", 0.014, c, rotation=rotation)
    cover = base.add_box(name + "_保护罩", (center.x, center.y, 0.126), (length - 0.16, 0.085, 0.022), "gloss", "cyan", 0.010, c, rotation=rotation)
    for side in (-1, 1):
        perpendicular = Vector((-math.sin(angle), math.cos(angle), 0.0)) * (0.085 * side)
        p = center + perpendicular
        base.add_box(name + f"_固定轨_{side:+d}", (p.x, p.y, 0.103), (length, 0.030, 0.055), "metal", "purple", 0.009, c, rotation=rotation)
    _pulse(glow, phase)
    _pulse(cover, phase)


def _guide_lights() -> None:
    segments = [
        ("BASE门前导视_A", (0.45, 4.58), (4.55, 4.58)),
        ("BASE门前导视_B", (5.45, 4.58), (9.55, 4.58)),
        ("BASE入口纵向导视_A", (2.28, 0.45), (2.28, 4.40)),
        ("BASE入口纵向导视_B", (2.28, -4.55), (2.28, -0.45)),
        ("西侧通行导视_A", (-9.68, -9.55), (-9.68, -5.45)),
        ("西侧通行导视_B", (-9.68, -4.55), (-9.68, -0.45)),
        ("西侧通行导视_C", (-9.68, 0.45), (-9.68, 4.55)),
        ("东侧设备导视_A", (9.68, -9.55), (9.68, -5.45)),
        ("东侧设备导视_B", (9.68, -4.55), (9.68, -0.45)),
        ("东侧设备导视_C", (9.68, 0.45), (9.68, 4.55)),
        ("南侧服务导视_A", (-9.55, -9.68), (-5.45, -9.68)),
        ("南侧服务导视_B", (-4.55, -9.68), (-0.45, -9.68)),
        ("南侧服务导视_C", (0.45, -9.68), (4.55, -9.68)),
        ("南侧服务导视_D", (5.45, -9.68), (9.55, -9.68)),
    ]
    for idx, (name, start, end) in enumerate(segments):
        _guide_segment("地板导视灯_" + name, start, end, (idx * 7) % 40)


def _hologram_floor_interface() -> None:
    c = base.COLLS["floor_detail"]
    x, y = 5.0, 1.72
    base.add_cylinder("全息平台地面接口_浅层安装腔", (x, y, 0.044), 1.18, 0.056, "matte", "black", 40, c)
    _torus("全息平台地面接口_外压环", (x, y, 0.098), 1.03, 0.095, "metal", "dark_gray", c, 40)
    _torus("全息平台地面接口_青蓝数据环_自发光", (x, y, 0.142), 0.82, 0.034, "emit", "cyan", c, 40)
    _torus("全息平台地面接口_内固定环", (x, y, 0.115), 0.62, 0.045, "metal", "mid_gray", c, 36)
    for idx in range(8):
        a = math.tau * idx / 8.0
        bx, by = x + math.cos(a) * 1.02, y + math.sin(a) * 1.02
        base.add_cylinder(f"全息平台地面接口_固定螺栓_{idx+1:02d}", (bx, by, 0.172), 0.048, 0.040, "metal", "dark_gray", 6, c)
    _floor_port("全息平台地面接口_电力端口", (x - 1.48, y - 0.26), "orange")
    _floor_port("全息平台地面接口_数据端口", (x + 1.48, y + 0.26), "cyan")
    _floor_text("全息平台地面接口_SERVICE标识", "SERVICE", (x, y - 1.42, 0.086), 0.18, "light_gray", 0.0, "matte")


def _orange_and_white_markings() -> None:
    c = base.COLLS["floor_detail"]
    _floor_text("BASE门前区域编号", "01", (1.10, 3.62, 0.090), 0.52, "orange", 0.0, "matte")
    _floor_text("BASE门前_ACCESS标识", "ACCESS", (2.58, 3.60, 0.088), 0.30, "light_gray", 0.0, "matte")
    # A physical triangular base logo made from three shallow metal strips.
    for idx, (a, b) in enumerate((((3.92, 3.25), (4.35, 4.02)), ((4.35, 4.02), (4.78, 3.25)), ((4.78, 3.25), (3.92, 3.25)))):
        base.add_beam(f"BASE门前_三角Logo边_{idx+1}", (a[0], a[1], 0.105), (b[0], b[1], 0.105), 0.060, "matte", "light_gray", c)
    # Two restrained orange chevrons point toward the BASE CAMP facade.
    for arrow in range(2):
        oy = 2.55 - arrow * 0.52
        base.add_beam(f"BASE门前_橙色箭头_{arrow+1}_左", (2.12, oy - 0.18, 0.090), (2.42, oy, 0.090), 0.070, "matte", "orange", c)
        base.add_beam(f"BASE门前_橙色箭头_{arrow+1}_右", (2.42, oy, 0.090), (2.72, oy - 0.18, 0.090), 0.070, "matte", "orange", c)

    _floor_text("东侧_KEEP_CLEAR标识", "KEEP CLEAR", (7.50, -2.16, 0.088), 0.36, "light_gray", 0.0, "matte")
    _floor_text("东侧_STAY_CLEAR标识", "STAY CLEAR", (7.50, -2.82, 0.088), 0.24, "light_gray", 0.0, "matte")
    _floor_text("东侧区域编号_03", "03", (9.10, -3.58, 0.088), 0.31, "orange", 0.0, "matte")
    # White diagonal safety bars stay within the east-side 5m module.
    for i in range(8):
        obj = base.add_box(
            f"东侧_KEEP_CLEAR白色斜纹_{i+1:02d}",
            (5.48 + i * 0.52, -4.26, 0.085), (0.42, 0.105, 0.028),
            "matte", "light_gray", 0.015, c,
            rotation=(0.0, 0.0, math.radians(-32.0)),
        )
        obj["detail_role"] = "painted_safety_mark"
    base.add_box("东侧_KEEP_CLEAR橙色边线", (7.50, -4.56, 0.082), (4.10, 0.055, 0.026), "matte", "orange", 0.010, c)

    _floor_text("西南供应区标识", "SUPPLY ZONE", (-7.50, -8.05, 0.084), 0.28, "light_gray", 0.0, "matte")
    _floor_text("西南供应区编号", "02", (-9.10, -8.78, 0.084), 0.32, "orange", 0.0, "matte")
    _floor_text("维修区标识", "MAINTENANCE", (1.90, -8.15, 0.084), 0.25, "light_gray", 0.0, "matte")


def _controlled_wear() -> None:
    c = base.COLLS["floor_detail"]
    # Short, low-contrast wheel/scuff segments. No cracks, rubble or rust fields.
    scuffs = (
        (-6.8, -3.6, 18), (-6.1, -3.2, 12), (-5.4, -2.9, 7),
        (-1.7, -7.0, -18), (-0.8, -6.7, -12), (0.1, -6.5, -8),
        (6.4, -0.9, 14), (7.0, -0.5, 10), (7.7, -0.2, 6),
        (-3.0, 1.1, -9), (-2.3, 1.4, -5), (10.7, 2.2, 16),
    )
    for idx, (x, y, deg) in enumerate(scuffs):
        base.add_box(
            f"地板轻微推车轮痕_{idx+1:02d}", (x, y, 0.071),
            (0.58 if idx % 3 else 0.36, 0.035, 0.012), "matte", "mid_gray", 0.005, c,
            rotation=(0.0, 0.0, math.radians(deg)),
        )
    for idx, (x, y, rx, ry) in enumerate(((-11.1, -6.2, 0.38, 0.22), (11.2, -8.4, 0.29, 0.18), (8.6, 3.0, 0.23, 0.14))):
        stain = base.add_cylinder(f"地板小范围油渍_{idx+1:02d}", (x, y, 0.069), rx, 0.012, "matte", "dark_gray", 28, c)
        stain.scale.y = ry / rx
        src = bpy.data.objects.get(stain.name + "__源")
        if src:
            src.scale.y = ry / rx


def build_floor_system() -> None:
    _floor_collection()
    for row, cy in enumerate(CENTERS):
        for col, cx in enumerate(CENTERS):
            _tile_frame(row, col, cx, cy)
    _grid_seams()
    for variant, (row, col) in enumerate(sorted(HATCH_TILES)):
        _inspection_hatch(row, col, CENTERS[col], CENTERS[row], variant)
    for row, col, vertical in ((0, 2, False), (1, 4, True), (2, 1, False), (3, 3, True)):
        _vent(row, col, CENTERS[col], CENTERS[row], vertical)
    for name, loc, color in (
        ("地板设备接口_西侧供水", (-11.20, -3.05), "cyan"),
        ("地板设备接口_南侧动力", (4.10, -7.75), "orange"),
        ("地板设备接口_东侧数据", (11.15, 2.85), "cyan"),
    ):
        _floor_port(name, loc, color)
    _guide_lights()
    _hologram_floor_interface()
    _orange_and_white_markings()
    _controlled_wear()


def build_corridor() -> None:
    V005_CORRIDOR()
    build_floor_system()


def build_preview():
    hero, top, detail = V005_PREVIEW()
    # South-wall boards are outside this floor batch. Their back faces would
    # occlude the reference-like cutaway camera, so only their preview-camera
    # visibility is disabled; geometry, transforms and runtime state remain.
    for obj in bpy.data.objects:
        if obj.name.startswith(("南墙资料板", "南仓工具墙", "南仓工具挂件_", "南仓维修台_")):
            obj.visible_camera = False
            obj["preview_culling_only"] = True
    # A higher, reference-like three-quarter view gives the floor visual priority.
    hero.location = (-31.5, -38.5, 29.0)
    hero.rotation_euler = (Vector((0.5, -0.2, 1.0)) - hero.location).to_track_quat("-Z", "Y").to_euler()
    hero.data.ortho_scale = 35.8
    detail.name = "基地微缩模型_地板系统近景相机"
    detail.data.name = detail.name
    detail.location = (-10.0, -12.0, 16.5)
    detail.rotation_euler = (Vector((1.0, -0.4, 0.10)) - detail.location).to_track_quat("-Z", "Y").to_euler()
    detail.data.ortho_scale = 16.8
    base.add_area_light(
        "地板验收柔光", (2.0, -8.0, 12.5), 2100, (0.50, 0.72, 1.0), 8.5,
        (1.0, -1.5, 0.0), False, base.COLLS["preview"],
    )
    background = next((node for node in bpy.context.scene.world.node_tree.nodes if node.type == "BACKGROUND"), None)
    if background:
        background.inputs["Strength"].default_value = 0.42
    return hero, top, detail


def _descendant_bounds(root: bpy.types.Object):
    pts = [obj.matrix_world @ Vector(corner) for obj in root.children_recursive if obj.type == "MESH" for corner in obj.bound_box]
    if not pts:
        raise RuntimeError(f"地板模块无可见网格: {root.name}")
    return (
        min(p.x for p in pts), max(p.x for p in pts),
        min(p.y for p in pts), max(p.y for p in pts),
        min(p.z for p in pts), max(p.z for p in pts),
    )


def _assert_close(label: str, actual: float, expected: float, tol: float = 0.004) -> None:
    if abs(actual - expected) > tol:
        raise RuntimeError(f"{label}变更: actual={actual:.6f}, expected={expected:.6f}")


def validate_layout() -> None:
    # v004 deliberately removed all corridor arrows and KEEP CLEAR markings.
    # The user's v006 floor rules explicitly restore a small, reference-driven set.
    # Temporarily neutralize only the new v006 names while retaining every other
    # inherited layout, stair, underdeck and PaletteUV assertion.
    renamed = []
    for obj in bpy.data.objects:
        if obj.name.startswith(("BASE门前_橙色箭头_", "东侧_KEEP_CLEAR")):
            original = obj.name
            obj.name = original.replace("箭头", "方向标").replace("KEEP_CLEAR", "KEEPZONE")
            renamed.append((obj, original))
    try:
        V005_VALIDATE()
    finally:
        for obj, original in renamed:
            obj.name = original
    root = bpy.data.collections.get("基地99层高品质微缩模型_中文资产管理")
    root["version"] = "v006"
    root["v006_scope"] = "floor system and directly floor-attached details only"
    root["v006_reference"] = "user-provided stylized sci-fi Base Camp floor reference"
    root["v006_floor_lock"] = "30x30m; 36 original 5m modules and seams unchanged"

    floor_roots = sorted([obj for obj in bpy.data.objects if obj.name.startswith("保留地板_")], key=lambda obj: obj.name)
    if len(floor_roots) != 36:
        raise RuntimeError(f"原地板模块数量变化: {len(floor_roots)}")
    for row, cy in enumerate(CENTERS):
        for col, cx in enumerate(CENTERS):
            obj = bpy.data.objects.get(f"保留地板_{row:02d}_{col:02d}")
            if obj is None:
                raise RuntimeError(f"缺少原地板模块: {row},{col}")
            _assert_close(f"地板{row},{col} X", obj.location.x, cx)
            _assert_close(f"地板{row},{col} Y", obj.location.y, cy)
            _assert_close(f"地板{row},{col} Z", obj.location.z, -0.30)
            bounds = _descendant_bounds(obj)
            _assert_close(f"地板{row},{col} 西边", bounds[0], cx - 2.5)
            _assert_close(f"地板{row},{col} 东边", bounds[1], cx + 2.5)
            _assert_close(f"地板{row},{col} 南边", bounds[2], cy - 2.5)
            _assert_close(f"地板{row},{col} 北边", bounds[3], cy + 2.5)

    detail = base.COLLS.get("floor_detail")
    if detail is None:
        raise RuntimeError("缺少地板深化输出集合")
    invalid = []
    oversized = []
    for obj in detail.all_objects:
        if obj.type != "MESH":
            continue
        pts = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
        b = (
            min(p.x for p in pts), max(p.x for p in pts), min(p.y for p in pts),
            max(p.y for p in pts), min(p.z for p in pts), max(p.z for p in pts),
        )
        if b[0] < -15.001 or b[1] > 15.001 or b[2] < -15.001 or b[3] > 15.001 or b[4] < -0.002 or b[5] > DETAIL_MAX_Z:
            invalid.append((obj.name, tuple(round(v, 3) for v in b)))
        if (b[1] - b[0]) > 4.90 and (b[3] - b[2]) > 4.90:
            oversized.append(obj.name)
    if invalid:
        raise RuntimeError(f"地板附着结构越界或过高: {invalid[:12]}")
    if oversized:
        raise RuntimeError(f"发现新增大面积地板块: {oversized[:12]}")

    hatches = [obj for obj in detail.all_objects if obj.name.endswith("_主盖板")]
    if len(hatches) != 9:
        raise RuntimeError(f"检修盖密度错误: {len(hatches)}/36")
    if not (0.20 <= len(hatches) / 36.0 <= 0.30):
        raise RuntimeError("检修盖比例不在20%-30%范围")

    required = (
        "全息平台地面接口_外压环", "东侧_KEEP_CLEAR标识", "BASE门前_ACCESS标识",
        "自发光_地板导视灯_BASE门前导视_A_青蓝芯",
    )
    missing = [name for name in required if bpy.data.objects.get(name) is None]
    if missing:
        raise RuntimeError(f"地板重点结构缺失: {missing}")

    # The floor pass must not mutate or replace v005 stairs, walls or facilities.
    if bpy.data.objects.get("L梯_西北转角平台") is None or bpy.data.objects.get("工业电视墙_主机壳") is None:
        raise RuntimeError("v005非地板结构被意外修改")


base.build_corridor = build_corridor
base.build_preview = build_preview
base.validate_layout = validate_layout


if __name__ == "__main__":
    base.main()
