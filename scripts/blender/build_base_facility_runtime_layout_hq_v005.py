"""Build Base 99 HQ layout v005 with the L stair in the marked NW wall zone.

The stair uses measured wall interfaces and exact platform seams:
- west wall inner face: X=-14.82; stair west edge: X=-14.80;
- north wall inner face: Y=14.82; stair north edge: Y=14.80;
- 20 equal risers finish at Z=6.09, matching the loft finish floor;
- run/platform edges meet exactly with no gap, overlap, or non-uniform scaling.
"""

from __future__ import annotations

import importlib.util
import math
from pathlib import Path

import bpy
from mathutils import Vector


PROJECT = Path(__file__).resolve().parents[2]
V004_SCRIPT = PROJECT / "scripts/blender/build_base_facility_runtime_layout_hq_v004.py"
spec = importlib.util.spec_from_file_location("base_facility_hq_v004", V004_SCRIPT)
v004 = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(v004)
base = v004.base

base.OUTPUT_BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v005.blend"
base.OUTPUT_HERO = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v005.png"
base.OUTPUT_TOP = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v005_top.png"
base.OUTPUT_DETAIL = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v005_stair.png"

V004_MEZZANINE = base.build_mezzanine_and_stairs
V004_VISUAL_CENTER = base.build_visual_center
V004_PREVIEW = base.build_preview
V004_VALIDATE = base.validate_layout

STAIR_WALL_EDGE = 14.80
STAIR_CENTER = 13.80
STAIR_WIDTH = 2.00
TREAD = 0.456
RUN_LENGTH = TREAD * 10
FIRST_SOUTH = STAIR_CENTER - STAIR_WIDTH / 2 - RUN_LENGTH
CORNER_SOUTH = STAIR_CENTER - STAIR_WIDTH / 2
SECOND_EAST = -STAIR_CENTER + STAIR_WIDTH / 2 + RUN_LENGTH
# The structural slab begins at X=-5.00; its 0.10m finish floor is inset to
# X=-4.80.  The landing uses a 0.09m finish plate that rests on the slab for
# the last 0.20m and meets the visible walking surface without a height seam.
LOFT_WEST = -4.80
FINISH_Z = 6.09
RISE = FINISH_Z / 20.0
CORNER_Z = RISE * 10
PLATFORM_THICKNESS = 0.24
TOP_PLATFORM_THICKNESS = 0.09


def _delete_matching(prefixes: tuple[str, ...]) -> None:
    for obj in list(bpy.data.objects):
        if obj.name.startswith(prefixes):
            bpy.data.objects.remove(obj, do_unlink=True)


def _step_light(name: str, loc, size, start_frame: int) -> None:
    strip = base.add_box(name, loc, size, "emit", "cyan", 0.005, base.COLLS["motion"])
    for frame, value in ((start_frame, 0.22), (start_frame + 11, 1.0), (start_frame + 70, 0.22)):
        strip.scale = (1, 1, value)
        strip.keyframe_insert("scale", frame=frame)


def _post(name: str, loc_xy, surface_z: float, top_z: float) -> None:
    base.add_beam(
        name,
        (loc_xy[0], loc_xy[1], surface_z),
        (loc_xy[0], loc_xy[1], top_z),
        0.060,
        "metal",
        "black",
        base.COLLS["mezz"],
    )


def _add_vertical_west_guard() -> None:
    """Guard only the closed portion of the loft west edge, leaving NW access open."""
    c = base.COLLS["mezz"]
    x = -4.77
    y0, y1 = 5.25, 12.64
    base.add_beam("楼中楼_西护栏南段_顶杆", (x, y0, 7.28), (x, y1, 7.28), 0.09, "metal", "black", c)
    base.add_beam("楼中楼_西护栏南段_中杆", (x, y0, 6.74), (x, y1, 6.74), 0.055, "metal", "purple", c)
    for i in range(7):
        y = y0 + (y1 - y0) * i / 6.0
        base.add_beam(f"楼中楼_西护栏南段_立柱_{i:02d}", (x, y, 6.08), (x, y, 7.28), 0.065, "metal", "black", c)
    for i in range(1, 5):
        z = 6.08 + i * 0.20
        base.add_beam(f"楼中楼_西护栏南段_网丝_{i:02d}", (x, y0, z), (x, y1, z), 0.018, "metal", "mid_gray", c)


def _build_wall_hugging_stair() -> None:
    c = base.COLLS["mezz"]
    c["stair_layout_v005"] = (
        "first run X[-14.80,-12.80] Y[8.24,12.80]; "
        "corner X[-14.80,-12.80] Y[12.80,14.80]; "
        "second run X[-12.80,-8.24] Y[12.80,14.80]; "
        "top landing X[-8.24,-4.80] Y[12.80,14.80]"
    )
    c["stair_finish_z_m"] = FINISH_Z
    c["wall_clearance_m"] = 0.02
    c["collision_contract"] = "visual steps; runtime wrapper should use continuous ramps and separate rail blockers"

    # First run: hugs the west wall and rises north to the corner landing.
    x_center = -STAIR_CENTER
    for i in range(10):
        y = FIRST_SOUTH + TREAD * (i + 0.5)
        z_bottom = RISE * i
        z_top = RISE * (i + 1)
        step = base.add_box(
            f"L梯_西墙第一跑踏步_{i+1:02d}",
            (x_center, y, (z_bottom + z_top) / 2),
            (STAIR_WIDTH, TREAD, RISE),
            "metal", "dark_gray", 0.018, c, True,
        )
        step["camera_clearance"] = "stair"
        _step_light(
            f"L梯_西墙第一跑导光_{i+1:02d}",
            (-STAIR_CENTER, y - TREAD / 2 + 0.018, z_top - 0.025),
            (1.72, 0.028, 0.032),
            1 + i * 4,
        )

    corner = base.add_box(
        "L梯_西北转角平台",
        (-STAIR_CENTER, STAIR_CENTER, CORNER_Z - PLATFORM_THICKNESS / 2),
        (STAIR_WIDTH, STAIR_WIDTH, PLATFORM_THICKNESS),
        "metal", "dark_gray", 0.025, c, True,
    )
    corner["camera_clearance"] = "stair_landing"

    # Second run: hugs the north wall and rises east to the loft landing.
    for i in range(10):
        x = -STAIR_CENTER + STAIR_WIDTH / 2 + TREAD * (i + 0.5)
        z_bottom = CORNER_Z + RISE * i
        z_top = CORNER_Z + RISE * (i + 1)
        step = base.add_box(
            f"L梯_北墙第二跑踏步_{i+1:02d}",
            (x, STAIR_CENTER, (z_bottom + z_top) / 2),
            (TREAD, STAIR_WIDTH, RISE),
            "metal", "dark_gray", 0.018, c, True,
        )
        step["camera_clearance"] = "stair"
        _step_light(
            f"L梯_北墙第二跑导光_{i+1:02d}",
            (x - TREAD / 2 + 0.018, STAIR_CENTER, z_top - 0.025),
            (0.028, 1.72, 0.032),
            45 + i * 4,
        )

    landing_width = LOFT_WEST - SECOND_EAST
    top_landing = base.add_box(
        "L梯_阁楼顶层接驳平台",
        ((SECOND_EAST + LOFT_WEST) / 2, STAIR_CENTER, FINISH_Z - TOP_PLATFORM_THICKNESS / 2),
        (landing_width, STAIR_WIDTH, TOP_PLATFORM_THICKNESS),
        "metal", "dark_gray", 0.025, c, True,
    )
    top_landing["camera_clearance"] = "stair_top_landing"
    top_landing["interface"] = "east edge X=-4.80; top Z=6.09; exact loft finish connection"

    # Two continuous structural side stringers per run, below the tread surfaces.
    for x in (-14.62, -12.98):
        base.add_beam(
            f"L梯_西墙第一跑侧梁_{x}",
            (x, FIRST_SOUTH + 0.08, 0.10),
            (x, CORNER_SOUTH - 0.08, CORNER_Z - 0.18),
            0.12, "metal", "purple", c,
        )
    for y in (12.98, 14.62):
        base.add_beam(
            f"L梯_北墙第二跑侧梁_{y}",
            (-STAIR_CENTER + STAIR_WIDTH / 2 + 0.08, y, CORNER_Z + 0.10),
            (SECOND_EAST - 0.08, y, FINISH_Z - 0.18),
            0.12, "metal", "purple", c,
        )

    # Handrails: wall-side and open-side tubes follow the exact stair slopes.
    for x in (-14.63, -12.93):
        base.add_beam(
            f"L梯_西墙第一跑扶手_{x}",
            (x, FIRST_SOUTH, 1.00),
            (x, CORNER_SOUTH, CORNER_Z + 1.00),
            0.075, "metal", "black", c,
        )
        for i in range(6):
            t = i / 5.0
            y = FIRST_SOUTH + RUN_LENGTH * t
            surface = CORNER_Z * t
            _post(f"L梯_西墙第一跑栏杆柱_{x}_{i:02d}", (x, y), surface, surface + 1.00)

    for y in (12.93, 14.63):
        base.add_beam(
            f"L梯_北墙第二跑扶手_{y}",
            (-STAIR_CENTER + STAIR_WIDTH / 2, y, CORNER_Z + 1.00),
            (SECOND_EAST, y, FINISH_Z + 1.00),
            0.075, "metal", "black", c,
        )
        for i in range(6):
            t = i / 5.0
            x = -STAIR_CENTER + STAIR_WIDTH / 2 + RUN_LENGTH * t
            surface = CORNER_Z + CORNER_Z * t
            _post(f"L梯_北墙第二跑栏杆柱_{y}_{i:02d}", (x, y), surface, surface + 1.00)

    # Top landing rails stop short of the loft entry; the east seam remains fully open.
    for y in (12.93, 14.63):
        base.add_beam(
            f"L梯_顶层平台护栏_{y}",
            (SECOND_EAST, y, FINISH_Z + 1.00),
            (LOFT_WEST - 0.08, y, FINISH_Z + 1.00),
            0.075, "metal", "black", c,
        )
        for i in range(4):
            x = SECOND_EAST + (LOFT_WEST - 0.08 - SECOND_EAST) * i / 3.0
            _post(f"L梯_顶层平台栏杆柱_{y}_{i:02d}", (x, y), FINISH_Z, FINISH_Z + 1.00)

    # Wall-mounted access items do not occupy either landing surface.
    base.add_box("L梯_西墙门禁面板", (-14.67, 11.55, CORNER_Z + 0.42), (0.08, 0.42, 0.62), "gloss", "cyan", 0.025, c)
    base.add_box("L梯_北墙应急灯", (-10.45, 14.67, FINISH_Z + 0.88), (0.62, 0.08, 0.20), "emit", "red", 0.025, c)


def build_mezzanine_and_stairs() -> None:
    V004_MEZZANINE()
    _delete_matching((
        "L梯_",
        "平台鞋柜", "平台钥匙盒", "平台门禁面板", "平台监控屏幕", "平台公告板", "平台应急灯",
        "楼中楼_西护栏",
    ))
    _add_vertical_west_guard()
    _build_wall_hugging_stair()


def build_visual_center() -> None:
    V004_VISUAL_CENTER()
    # Clear the user's marked NW stair zone by moving the armory to the west wall's south half.
    tokens = (
        "武器台锁柜主体", "武器台加固木台面", "武器挂墙板", "武器挂架孔列_",
        "武器台弹药箱_", "ARMORY_霓虹字", "武器台红色警示灯",
    )
    for obj in bpy.data.objects:
        if obj.name.startswith(tokens):
            obj.location.y -= 12.0


def build_preview():
    hero, top, detail = V004_PREVIEW()
    # Review-only lights make both stair runs and the two exact seams readable.
    base.add_area_light(
        "楼梯验收冷白主光", (-7.0, 6.5, 12.5), 2100, (0.52, 0.76, 1.0), 6.5,
        (-12.2, 12.0, 3.7), False, base.COLLS["preview"],
    )
    base.add_area_light(
        "楼梯验收暖色侧光", (-8.0, 10.0, 8.0), 1050, (1.0, 0.30, 0.08), 4.0,
        (-13.4, 12.0, 3.1), False, base.COLLS["preview"],
    )
    detail.name = "基地微缩模型_西北贴墙L梯近景相机"
    detail.data.name = detail.name
    detail.location = (-2.5, 1.5, 12.0)
    detail.rotation_euler = (Vector((-11.2, 12.0, 3.8)) - detail.location).to_track_quat("-Z", "Y").to_euler()
    detail.data.ortho_scale = 12.2
    return hero, top, detail


def _bounds(obj):
    pts = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return (
        min(p.x for p in pts), max(p.x for p in pts),
        min(p.y for p in pts), max(p.y for p in pts),
        min(p.z for p in pts), max(p.z for p in pts),
    )


def _assert_close(label: str, actual: float, expected: float, tol: float = 0.006) -> None:
    if abs(actual - expected) > tol:
        raise RuntimeError(f"{label}未对齐: actual={actual:.6f}, expected={expected:.6f}")


def validate_layout() -> None:
    V004_VALIDATE()
    root = bpy.data.collections.get("基地99层高品质微缩模型_中文资产管理")
    root["version"] = "v005"
    root["v005_stair"] = "NW red-box position; wall-hugging west+north runs; exact Z=6.09 loft seam"

    first = [_bounds(bpy.data.objects[f"L梯_西墙第一跑踏步_{i:02d}"]) for i in range(1, 11)]
    second = [_bounds(bpy.data.objects[f"L梯_北墙第二跑踏步_{i:02d}"]) for i in range(1, 11)]
    corner = _bounds(bpy.data.objects["L梯_西北转角平台"])
    landing = _bounds(bpy.data.objects["L梯_阁楼顶层接驳平台"])
    loft = _bounds(bpy.data.objects["楼中楼_深色木纹生活面"])

    # Wall attachment and horizontal seams.
    _assert_close("第一跑贴西墙", min(b[0] for b in first), -STAIR_WALL_EDGE)
    _assert_close("转角平台贴西墙", corner[0], -STAIR_WALL_EDGE)
    _assert_close("第二跑贴北墙", max(b[3] for b in second), STAIR_WALL_EDGE)
    _assert_close("顶层平台贴北墙", landing[3], STAIR_WALL_EDGE)
    _assert_close("第一跑至转角Y接口", max(b[3] for b in first), corner[2])
    _assert_close("转角至第二跑X接口", corner[1], min(b[0] for b in second))
    _assert_close("第二跑至顶层平台X接口", max(b[1] for b in second), landing[0])
    _assert_close("顶层平台至阁楼X接口", landing[1], loft[0])

    # Vertical seams: the tread, corner, top landing, and loft finish share exact top elevations.
    _assert_close("第一跑至转角Z接口", first[-1][5], corner[5])
    _assert_close("第二跑至顶层平台Z接口", second[-1][5], landing[5])
    _assert_close("顶层平台至阁楼完成面Z接口", landing[5], loft[5])
    _assert_close("目标完成面", landing[5], FINISH_Z)

    # Consecutive treads must meet edge-to-edge in plan and rise uniformly.
    for i in range(9):
        _assert_close(f"第一跑踏步{i+1}-{i+2}平面接口", first[i][3], first[i + 1][2])
        _assert_close(f"第一跑踏步{i+1}-{i+2}高度", first[i + 1][5] - first[i][5], RISE)
        _assert_close(f"第二跑踏步{i+1}-{i+2}平面接口", second[i][1], second[i + 1][0])
        _assert_close(f"第二跑踏步{i+1}-{i+2}高度", second[i + 1][5] - second[i][5], RISE)

    # No facility may overlap the marked stair envelope.
    offenders = []
    for key in ("facility", "warehouse", "attachment"):
        for obj in base.COLLS[key].all_objects:
            if obj.type != "MESH":
                continue
            b = _bounds(obj)
            in_west_run = b[1] > -14.80 and b[0] < -12.80 and b[3] > FIRST_SOUTH and b[2] < 14.80
            in_north_run = b[1] > -12.80 and b[0] < -4.80 and b[3] > 12.80 and b[2] < 14.80
            if (in_west_run or in_north_run) and b[4] < FINISH_Z + 1.1:
                offenders.append(obj.name)
    if offenders:
        raise RuntimeError(f"红框楼梯区仍与设施穿插: {offenders[:20]}")


base.build_mezzanine_and_stairs = build_mezzanine_and_stairs
base.build_visual_center = build_visual_center
base.build_preview = build_preview
base.validate_layout = validate_layout


if __name__ == "__main__":
    base.main()
