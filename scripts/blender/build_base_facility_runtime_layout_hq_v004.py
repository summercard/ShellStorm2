"""Build Base 99 HQ layout v004 from the maintained v003 component library.

Changes from v003:
- the 20 x 10 m mezzanine is attached to the east wall;
- its ground-level footprint is enclosed by the registered sheet-metal blocker
  and contains no furniture or facility props;
- the west L stair is rebuilt as two outside runs with a clean loft landing;
- the south warehouse is thinned and utilities are redistributed to side walls
  and the loft;
- corridor arrows and the strict 15 x 30 overlay are removed, retaining the
  registered 5 m tiled floor modules.
"""

from __future__ import annotations

import importlib.util
import math
from pathlib import Path

import bpy
from mathutils import Vector


PROJECT = Path(__file__).resolve().parents[2]
V003_SCRIPT = PROJECT / "scripts/blender/build_base_facility_runtime_layout_hq_v003.py"
spec = importlib.util.spec_from_file_location("base_facility_hq_v003", V003_SCRIPT)
base = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(base)

base.OUTPUT_BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v004.blend"
base.OUTPUT_HERO = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v004.png"
base.OUTPUT_TOP = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v004_top.png"
base.OUTPUT_DETAIL = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v004_facilities.png"
base.ASSETS["underdeck_blocker"] = (
    base.ENV
    / "env_base99_mezzanine_underdeck_blocker"
    / "env_base99_mezzanine_underdeck_blocker_visual_top3d_v003.glb"
)


def build_registered_shell(templates) -> None:
    """Keep the registered room shell and expose east/north walls in previews."""
    floor_coll = base.COLLS["shell"]
    centers = (-12.5, -7.5, -2.5, 2.5, 7.5, 12.5)
    for row, y in enumerate(centers):
        for col, x in enumerate(centers):
            key = "floor_rivet" if (row + col) % 2 else "floor_plain"
            base.place_template(templates[key], floor_coll, f"保留地板_{row:02d}_{col:02d}", (x, y, -0.30))
    for idx, x in enumerate(centers):
        base.place_template(templates["wall_plain"], floor_coll, f"保留北墙_{idx:02d}", (x, 15, 0), 0)
        south = base.place_template(
            templates["wall_plain"], floor_coll, f"保留南墙_{idx:02d}", (x, -15, 0), math.pi
        )
        base.set_tree_camera_visibility(south, False)
    for idx, y in enumerate(centers):
        key = "wall_door" if idx == 2 else "wall_plain"
        west = base.place_template(templates[key], floor_coll, f"保留西墙_{idx:02d}", (-15, y, 0), math.pi / 2)
        base.set_tree_camera_visibility(west, False)
        base.place_template(templates[key], floor_coll, f"保留东墙_{idx:02d}", (15, y, 0), -math.pi / 2)

    blocker = base.place_template(
        templates["underdeck_blocker"],
        base.COLLS["mezz"],
        "阁楼下方三面铁皮封闭体",
        (5.0, 10.0, 0.0),
    )
    blocker["asset_id"] = "ENV-BASE99-MEZZANINE-UNDERDECK-BLOCKER"
    blocker["layout_role"] = "south/west/east sheet-metal enclosure; interior intentionally empty"


def build_corridor() -> None:
    """The 5 m registered floor grid is the only circulation marking in v004."""
    base.COLLS["corridor"]["v004_note"] = "No arrows, words, epoxy overlay, or strict 15x30 exclusion zone."


def _animated_step_light(name: str, loc, size, start_frame: int) -> None:
    strip = base.add_box(name, loc, size, "emit", "cyan", 0.005, base.COLLS["motion"])
    for frame, value in ((start_frame, 0.22), (start_frame + 11, 1.0), (start_frame + 70, 0.22)):
        strip.scale = (1, 1, value)
        strip.keyframe_insert("scale", frame=frame)


def build_mezzanine_and_stairs() -> None:
    c = base.COLLS["mezz"]
    # 20 x 10 m loft: east edge x=15 and north edge y=15.
    base.add_box("楼中楼_主承重楼板", (5, 10, 5.78), (20, 10, 0.44), "metal", "dark_gray", 0.05, c)
    base.add_box("楼中楼_深色木纹生活面", (5, 10, 6.04), (19.6, 9.6, 0.10), "matte", "wood", 0.02, c)
    for x in (-4.65, 14.65):
        for y in (5.45, 14.55):
            base.add_box(f"楼中楼_承重柱_{x}_{y}", (x, y, 2.9), (0.30, 0.30, 5.8), "metal", "purple", 0.04, c, True)
    for y in (5.15, 14.78):
        base.add_beam(f"楼板边梁_{y}", (-4.9, y, 5.52), (14.9, y, 5.52), 0.28, "metal", "purple", c)
    for x in (-4.9, 14.9):
        base.add_beam(f"楼板侧梁_{x}", (x, 5.25, 5.52), (x, 14.75, 5.52), 0.28, "metal", "purple", c)

    # East and north edges use the room walls. South/west guards keep a 2 m stair entrance.
    base.add_wire_guard("楼中楼_南护栏", -4.7, 14.7, 5.18, 6.08, target=c)
    base.add_wire_guard("楼中楼_西护栏北段", -4.78, -4.76, 7.35, 6.08, height=1.2, target=c)
    base.add_beam("楼中楼_西护栏北段_纵向顶杆", (-4.77, 7.35, 7.28), (-4.77, 14.68, 7.28), 0.09, "metal", "black", c)
    for y in (7.35, 8.55, 9.75, 10.95, 12.15, 13.35, 14.65):
        base.add_beam(f"楼中楼_西护栏立柱_{y}", (-4.77, y, 6.08), (-4.77, y, 7.28), 0.065, "metal", "black", c)

    # Corrected L stair entirely outside the loft footprint (x < -5).
    rise, tread = 0.30, 0.44
    for i in range(10):
        x = -12.55 + i * tread
        z = (i + 0.5) * rise
        base.add_box(f"L梯_第一跑踏步_{i+1:02d}", (x, 2.15, z), (tread, 2.0, rise), "metal", "dark_gray", 0.025, c, True)
        _animated_step_light(
            f"L梯_第一跑导光_{i+1:02d}", (x - tread * 0.44, 1.22, z + rise * 0.45), (0.035, 1.65, 0.035), 1 + i * 4
        )
    base.add_box("L梯_转角平台", (-7.65, 2.15, 3.02), (2.3, 2.2, 0.24), "metal", "dark_gray", 0.035, c, True)

    for i in range(10):
        y = 2.45 + i * tread
        z = 3.0 + (i + 0.5) * rise
        base.add_box(f"L梯_第二跑踏步_{i+1:02d}", (-6.48, y, z), (2.0, tread, rise), "metal", "dark_gray", 0.025, c, True)
        _animated_step_light(
            f"L梯_第二跑导光_{i+1:02d}", (-5.56, y - tread * 0.44, z + rise * 0.45), (1.65, 0.035, 0.035), 45 + i * 4
        )
    base.add_box("L梯_顶部接驳平台", (-5.72, 6.75, 6.02), (1.75, 1.75, 0.24), "metal", "dark_gray", 0.035, c, True)

    # Handrails follow the two true slopes and stop at the access opening.
    for y in (1.08, 3.22):
        base.add_beam(f"L梯_第一跑扶手_{y}", (-12.75, y, 1.02), (-8.15, y, 4.02), 0.075, "metal", "black", c)
        for i in range(5):
            x = -12.45 + i * 1.02
            z = 0.92 + (x + 12.75) * (3.0 / 4.6)
            base.add_beam(f"L梯_第一跑栏杆柱_{y}_{i}", (x, y, max(0.2, z - 0.9)), (x, y, z), 0.06, "metal", "black", c)
    for x in (-7.55, -5.41):
        base.add_beam(f"L梯_第二跑扶手_{x}", (x, 2.25, 4.02), (x, 6.85, 7.02), 0.075, "metal", "black", c)
        for i in range(5):
            y = 2.55 + i * 1.02
            z = 3.92 + (y - 2.25) * (3.0 / 4.6)
            base.add_beam(f"L梯_第二跑栏杆柱_{x}_{i}", (x, y, z - 0.9), (x, y, z), 0.06, "metal", "black", c)

    # Landing utilities are compact and stay outside the sheet-metal enclosure.
    base.add_box("平台鞋柜", (-7.65, 2.75, 3.62), (1.35, 0.45, 0.98), "matte", "teal", 0.05, c)
    base.add_box("平台钥匙盒", (-8.65, 2.15, 4.05), (0.36, 0.10, 0.48), "gloss", "orange", 0.03, c)
    base.add_box("平台门禁面板", (-7.90, 2.15, 4.15), (0.42, 0.10, 0.62), "gloss", "cyan", 0.03, c)
    base.add_box("平台监控屏幕", (-7.15, 2.15, 4.22), (0.68, 0.10, 0.50), "gloss", "blue", 0.025, c)
    base.add_box("平台公告板", (-7.65, 3.18, 4.25), (1.55, 0.10, 0.80), "matte", "wood", 0.025, c)
    base.add_box("平台应急灯", (-6.58, 2.15, 4.28), (0.45, 0.12, 0.20), "emit", "red", 0.025, c)

    # Exterior facade wash replaces the old lamps hanging inside the enclosure.
    for x in (-2.5, 2.5, 7.5, 12.5):
        base.add_box(f"铁皮外立面线性灯_{x}", (x, 5.02, 5.35), (3.2, 0.14, 0.10), "emit", "cyan", 0.02, base.COLLS["motion"])
        light = base.add_area_light(
            f"铁皮外立面呼吸灯_{x}", (x, 4.92, 5.2), 360, (0.10, 0.72, 1.0), 2.8, (x, 2.0, 1.0), False
        )
        base.animate_light_energy(light, [(1, 240), (60, 430), (120, 260), (180, 420), (240, 240)])


def _shift_objects_since(before: set[bpy.types.Object], delta: Vector) -> None:
    for obj in set(bpy.data.objects) - before:
        obj.location += delta


def build_bed_and_living() -> None:
    before = set(bpy.data.objects)
    base._v003_build_bed_and_living()
    _shift_objects_since(before, Vector((5.0, 0.0, 0.0)))

    c = base.COLLS["living"]
    # Selected south-side supplies are relocated upstairs along the east wall.
    base.add_box("阁楼东墙补给柜", (13.55, 8.45, 7.10), (1.55, 2.20, 1.85), "metal", "dark_gray", 0.07, c)
    for row, label, color in ((0, "FOOD", "orange"), (1, "BATTERY", "cyan"), (2, "MEDICAL", "red")):
        z = 6.55 + row * 0.58
        base.add_box(f"阁楼补给抽屉_{label}", (12.70, 8.45, z), (0.08, 1.72, 0.44), "matte", color, 0.025, c)
        base.add_text(
            f"阁楼补给标签_{label}", label, (12.64, 8.45, z), 0.16, "emit", "light_gray", 0.006,
            "CENTER", (math.pi / 2, 0, -math.pi / 2), c
        )
    base.add_box("阁楼备用电池箱", (10.4, 7.0, 6.45), (1.25, 0.72, 0.62), "matte", "teal", 0.06, base.COLLS["attachment"])
    base.add_box("阁楼工具箱", (8.8, 7.0, 6.43), (1.15, 0.65, 0.56), "matte", "red", 0.06, base.COLLS["attachment"])


def _facade_text(name: str, body: str, loc, size: float, color: str) -> None:
    base.add_text(name, body, loc, size, "emit", color, 0.025, "CENTER", (math.pi / 2, 0, 0), base.COLLS["facility"])


def _front_locker(prefix: str, x: float, label: str, color: str) -> None:
    c = base.COLLS["facility"]
    base.add_box(prefix + "_柜体", (x, 4.46, 1.45), (1.55, 0.72, 2.85), "metal", "dark_gray", 0.07, c, True)
    base.add_box(prefix + "_柜门", (x, 4.06, 1.45), (1.30, 0.07, 2.48), "matte", color, 0.035, c)
    base.add_box(prefix + "_铭牌", (x, 4.01, 2.38), (1.10, 0.025, 0.30), "emit", "cyan", 0.01, c)
    _facade_text(prefix + "_标签", label, (x, 3.98, 2.39), 0.17, "light_gray")


def build_visual_center() -> None:
    c = base.COLLS["facility"]
    # Facilities sit on the OUTSIDE of the blocker's south sheet-metal face.
    base.add_box("电视背景墙_钢板左", (2.7, 5.03, 2.35), (2.0, 0.16, 4.25), "metal", "dark_gray", 0.03, c)
    base.add_box("电视背景墙_旧木板中", (5.0, 5.00, 2.25), (2.6, 0.14, 4.05), "matte", "wood", 0.025, c)
    base.add_box("电视背景墙_水泥板右", (7.3, 5.03, 2.35), (2.0, 0.16, 4.25), "matte", "mid_gray", 0.025, c)
    for x in (1.8, 3.4, 5.0, 6.6, 8.2):
        base.add_box(f"电视背景墙_钢包边_{x}", (x, 4.89, 2.35), (0.08, 0.06, 4.2), "metal", "purple", 0.015, c)
    base.add_box("工业电视墙_主机壳", (5, 4.64, 2.20), (5.8, 0.40, 2.55), "metal", "black", 0.12, c, True)
    base.add_box("工业电视墙_屏幕", (5, 4.40, 2.34), (5.20, 0.06, 1.95), "emit", "blue", 0.035, c)
    base.add_box("工业电视墙_下方储物柜", (5, 4.18, 0.68), (6.2, 0.78, 1.15), "matte", "dark_gray", 0.08, c, True)
    for x in (2.7, 4.25, 5.75, 7.3):
        base.add_box(f"电视低柜门_{x}", (x, 3.76, 0.70), (1.30, 0.05, 0.86), "matte", "teal", 0.025, c)
    for i in range(7):
        line = base.add_box(
            f"电视扫描线_{i:02d}", (5, 4.355, 1.58 + i * 0.23), (4.95, 0.012, 0.016),
            "emit", "cyan" if i % 2 else "violet", 0.002, base.COLLS["motion"]
        )
        line.keyframe_insert("location", frame=1 + i * 3)
        line.location.z += 1.35
        line.keyframe_insert("location", frame=80 + i * 3)
        line.location.z -= 1.35
        line.keyframe_insert("location", frame=160 + i * 3)
    base.add_box("BASE_CAMP_金属背板", (5, 4.78, 4.43), (7.6, 0.16, 0.98), "metal", "purple", 0.10, c)
    _facade_text("BASE_CAMP_立体霓虹字", "BASE CAMP", (5, 4.64, 4.46), 0.82, "light_gray")
    for x, color in ((3.1, (0.10, 0.45, 1.0)), (6.9, (0.55, 0.12, 1.0))):
        lamp = base.add_area_light(f"BASE_CAMP_背光_{x}", (x, 4.18, 4.40), 390, color, 3.2, (x, 1.5, 3), False)
        base.animate_light_energy(lamp, [(1, 380), (47, 340), (50, 80), (53, 400), (121, 360), (124, 140), (127, 410), (240, 380)])

    # Four lockers replace the six under-loft lockers and flank the facade.
    for idx, (x, label, color) in enumerate(((-3.65, "MEDICAL", "red"), (-1.85, "TOOLS", "teal"), (11.85, "AMMO", "yellow"), (13.65, "CLOTHING", "violet"))):
        _front_locker(f"工业储物柜_{idx+1:02d}", x, label, color)
        base.add_box(f"柜顶工具箱_{idx}", (x, 4.30, 3.08), (0.92, 0.38, 0.32), "matte", "red" if idx % 2 == 0 else "teal", 0.05, base.COLLS["attachment"])

    # Armory moves to the west wall and faces east, clear of the enclosed volume.
    base.add_box("武器台锁柜主体", (-13.25, 8.6, 0.85), (1.10, 5.20, 1.45), "metal", "dark_gray", 0.08, c, True)
    base.add_box("武器台加固木台面", (-12.55, 8.6, 1.64), (1.48, 5.50, 0.20), "matte", "wood", 0.05, c)
    base.add_box("武器挂墙板", (-14.05, 8.6, 3.05), (0.18, 6.0, 2.15), "metal", "dark_gray", 0.035, c)
    for y in (6.5, 7.4, 8.3, 9.2, 10.1):
        base.add_box(f"武器挂架孔列_{y}", (-13.93, y, 3.05), (0.025, 0.04, 1.68), "emit", "cyan", 0.003, c)
    for idx, y in enumerate((7.0, 8.4, 9.8)):
        base.add_box(f"武器台弹药箱_{idx}", (-12.15, y, 1.98), (0.64, 1.05, 0.50), "matte", "teal", 0.05, base.COLLS["attachment"])
    base.add_text("ARMORY_霓虹字", "ARMORY", (-13.88, 8.6, 4.42), 0.48, "emit", "red", 0.03, "CENTER", (math.pi / 2, 0, -math.pi / 2), c)
    warning = base.add_area_light("武器台红色警示灯", (-12.7, 8.6, 4.3), 0, (1.0, 0.04, 0.03), 1.8, (-10.0, 8.6, 1.0), False)
    base.animate_light_energy(warning, [(1, 0), (35, 0), (38, 420), (46, 420), (49, 0), (120, 0)])


def _rotate_new_objects(before: set[bpy.types.Object], old_center: Vector, new_center: Vector, angle: float) -> None:
    ca, sa = math.cos(angle), math.sin(angle)
    for obj in set(bpy.data.objects) - before:
        rel = obj.location - old_center
        obj.location = new_center + Vector((ca * rel.x - sa * rel.y, sa * rel.x + ca * rel.y, rel.z))
        if obj.rotation_mode == "QUATERNION":
            obj.rotation_mode = "XYZ"
        obj.rotation_euler.z += angle


def build_vending() -> None:
    before = set(bpy.data.objects)
    base._v003_build_vending()
    _rotate_new_objects(before, Vector((11.7, 9.0, 0.0)), Vector((13.0, -1.6, 0.0)), -math.pi / 2)


def build_warehouse() -> None:
    c = base.COLLS["warehouse"]
    # One readable shelf replaces the former wall-to-wall south warehouse row.
    base.add_shelf("南仓库重型货架_A", -10.8, -13.55, 5.2)
    base.add_box("南仓维修台_柜体", (6.2, -13.25, 0.92), (4.7, 1.15, 1.50), "metal", "dark_gray", 0.08, c, True)
    base.add_box("南仓维修台_厚钢台面", (6.2, -12.62, 1.72), (5.0, 1.42, 0.18), "metal", "mid_gray", 0.05, c)
    base.add_box("南仓工具墙", (6.2, -14.42, 3.05), (5.0, 0.14, 2.10), "matte", "teal", 0.035, c)
    for i in range(8):
        x = 4.35 + (i % 4) * 1.20
        z = 2.55 + (i // 4) * 0.80
        base.add_box(f"南仓工具挂件_{i:02d}", (x, -14.30, z), (0.12 + (i % 2) * 0.08, 0.09, 0.50), "metal", "yellow" if i % 3 == 0 else "light_gray", 0.02, base.COLLS["attachment"])

    # East-wall power cluster.
    base.add_box("备用发电机_底座", (13.25, -9.1, 0.55), (2.15, 3.1, 0.85), "metal", "purple", 0.10, c, True)
    base.add_cylinder("备用发电机_转子罩", (13.25, -9.1, 1.20), 0.58, 1.60, "metal", "dark_gray", 24, c, rotation=(math.pi / 2, 0, 0))
    base.add_box("备用发电机_控制屏", (12.08, -8.4, 1.35), (0.16, 0.78, 0.58), "emit", "cyan", 0.04, c)
    for i in range(3):
        base.add_box(f"蓄电池组_{i}", (12.9, -11.3 - i * 0.82, 0.52), (1.25, 0.64, 0.82), "matte", "dark_gray", 0.06, c, True)
        base.add_box(f"蓄电池组_状态灯_{i}", (12.22, -11.3 - i * 0.82, 0.65), (0.03, 0.22, 0.11), "emit", "green", 0.015, c)
    base.add_box("东墙配电箱", (14.15, -5.55, 2.35), (0.34, 1.55, 2.15), "metal", "dark_gray", 0.08, c)
    base.add_text("东墙配电箱标签", "POWER", (13.95, -5.55, 2.65), 0.23, "emit", "red", 0.008, "CENTER", (math.pi / 2, 0, -math.pi / 2), c)

    # West-wall water/air services.
    base.add_cylinder("工业水箱", (-13.15, -7.7, 1.35), 1.00, 2.55, "metal", "mid_gray", 24, c, True)
    base.add_box("净水器", (-13.10, -4.9, 1.30), (1.75, 1.50, 2.45), "matte", "teal", 0.12, c, True)
    base.add_cylinder("净水器滤芯_A", (-12.18, -5.25, 1.10), 0.20, 1.38, "gloss", "cyan", 18, c)
    base.add_cylinder("净水器滤芯_B", (-12.18, -4.58, 1.10), 0.20, 1.38, "gloss", "cyan", 18, c)
    base.add_box("空气压缩机", (-13.0, -1.55, 0.78), (2.0, 1.45, 1.20), "metal", "purple", 0.12, c, True)
    base.add_cylinder("空气压缩机储气罐", (-12.8, -1.55, 0.75), 0.46, 1.45, "metal", "dark_gray", 24, c, rotation=(0, math.pi / 2, 0))
    base.add_cylinder("水管卷盘", (-14.05, -10.6, 2.65), 0.62, 0.25, "metal", "yellow", 24, c, rotation=(math.pi / 2, 0, 0))

    # Compact sorting station on the southeast wall, away from the view-blocking south center.
    for i, (y, color, label) in enumerate(((-5.2, "dark_gray", "WASTE"), (-6.65, "red", "FLAMMABLE"), (-8.1, "teal", "RECYCLE"))):
        base.add_box(f"分类垃圾箱_{label}", (10.8, y, 0.70), (1.05, 1.05, 1.30), "matte", color, 0.10, c, True)
        base.add_text(f"分类垃圾箱标签_{label}", label, (10.22, y, 0.84), 0.14, "emit", "light_gray", 0.006, "CENTER", (math.pi / 2, 0, -math.pi / 2), c)

    # Only three south-wall boards remain, leaving the wall visually quieter.
    for i, (x, label) in enumerate(((-4.2, "BASE MAP"), (0.0, "MAINTENANCE"), (9.0, "SAFETY RULES"))):
        base.add_box(f"南墙资料板_{i}", (x, -14.55, 4.65), (3.0, 0.12, 1.30), "matte", "wood" if i == 1 else "mid_gray", 0.04, c)
        base.add_text(f"南墙资料板标题_{i}", label, (x, -14.42, 4.98), 0.21, "emit", "yellow", 0.008, "CENTER", (-math.pi / 2, 0, 0), c)


def build_preview():
    world = bpy.data.worlds.new("基地模型世界")
    bpy.context.scene.world = world
    world.use_nodes = True
    background = next((node for node in world.node_tree.nodes if node.type == "BACKGROUND"), None)
    background.inputs["Color"].default_value = (0.006, 0.008, 0.018, 1)
    background.inputs["Strength"].default_value = 0.30
    base.add_area_light("预览冷白主光", (-2, -8, 24), 2600, (0.52, 0.72, 1.0), 12, (2, 1, 2), True, base.COLLS["preview"])
    base.add_area_light("预览蓝紫轮廓光", (18, 12, 13), 1750, (0.25, 0.08, 1.0), 9, (5, 7, 3), False, base.COLLS["preview"])
    base.add_area_light("预览暖橙补光", (-18, -18, 10), 1350, (1.0, 0.25, 0.06), 8, (0, -6, 2), False, base.COLLS["preview"])
    hero = base.add_camera("基地微缩模型_英雄相机", (-34, -39, 27), (1.5, 1.5, 3.0), 35.5)
    top = base.add_camera("基地微缩模型_顶视相机", (0, 0, 46), (0, 0, 0), 35.0)
    detail = base.add_camera("基地微缩模型_铁皮外设施近景相机", (5, -7.5, 4.3), (5, 5.0, 2.7), 18.0)
    return hero, top, detail


def _world_bounds(obj: bpy.types.Object):
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return (
        min(v.x for v in corners), max(v.x for v in corners),
        min(v.y for v in corners), max(v.y for v in corners),
        min(v.z for v in corners), max(v.z for v in corners),
    )


def validate_layout() -> None:
    root = bpy.data.collections.get("基地99层高品质微缩模型_中文资产管理")
    root["version"] = "v004"
    root["main_corridor"] = "Loose east-west circulation on registered 5m tile grid; no arrows or strict overlay"
    root["v004_layout"] = "Mezzanine x[-5,15], y[5,15], east-wall attached; underdeck interior empty"

    loft = bpy.data.objects.get("楼中楼_主承重楼板")
    if loft is None:
        raise RuntimeError("缺少楼中楼主承重楼板")
    bounds = _world_bounds(loft)
    if abs(bounds[1] - 15.0) > 0.03 or abs(bounds[2] - 5.0) > 0.03 or abs(bounds[3] - 15.0) > 0.03:
        raise RuntimeError(f"楼中楼未贴东/北墙或尺寸错误: {bounds}")

    forbidden_tokens = ("箭头", "MAIN_CORRIDOR", "KEEP_CLEAR", "VEHICLE_PATH", "中央环氧主通道面层")
    leaked = [obj.name for obj in bpy.data.objects if any(token in obj.name for token in forbidden_tokens)]
    if leaked:
        raise RuntimeError(f"v004仍含通道箭头或覆层: {leaked[:20]}")

    # Enclosed volume leaves a margin for its three metal skins and excludes props/facilities.
    offenders = []
    for key in ("facility", "warehouse", "attachment"):
        for obj in base.COLLS[key].all_objects:
            if obj.type != "MESH":
                continue
            x0, x1, y0, y1, z0, z1 = _world_bounds(obj)
            if x1 > -4.45 and x0 < 14.45 and y1 > 5.65 and y0 < 14.35 and z0 < 5.45:
                offenders.append((obj.name, tuple(round(v, 2) for v in (x0, x1, y0, y1, z0, z1))))
    if offenders:
        raise RuntimeError(f"阁楼铁皮封闭体内部仍有设施: {offenders[:20]}")

    uv_missing = []
    for key in ("shell", "corridor", "mezz", "living", "facility", "warehouse", "attachment", "motion"):
        for obj in base.COLLS[key].all_objects:
            if obj.type == "MESH" and "PaletteUV" not in obj.data.uv_layers:
                uv_missing.append(obj.name)
    if uv_missing:
        raise RuntimeError(f"输出网格缺少PaletteUV: {uv_missing[:20]}")


# Preserve v003 implementations before replacing module entry points.
base._v003_build_bed_and_living = base.build_bed_and_living
base._v003_build_vending = base.build_vending
base.build_registered_shell = build_registered_shell
base.build_corridor = build_corridor
base.build_mezzanine_and_stairs = build_mezzanine_and_stairs
base.build_bed_and_living = build_bed_and_living
base.build_visual_center = build_visual_center
base.build_vending = build_vending
base.build_warehouse = build_warehouse
base.build_preview = build_preview
base.validate_layout = validate_layout


if __name__ == "__main__":
    base.main()
