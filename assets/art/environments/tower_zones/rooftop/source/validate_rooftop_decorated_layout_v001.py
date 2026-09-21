"""Structural QA for the 100F decorated rooftop placement source.

判据分三层：
  1. Blender 侧 —— 实例模式、包数、无自有几何、无缩放；
  2. **Godot 侧** —— 把每个实例按项目坐标契约 (world.x = bx, world.z = −by) 换算后，
     必须落在 ROOFTOP_WORLD_RECT 内，且房屋围护必须与 Base100UpperShell（30×30）
     的墙中心线 / 门洞 / 封顶网格逐个同位。
第 2 层是 2026-09-21 补的防再犯断言：旧版少了 by = −gz 一步换算，整份布局在 Godot 里
南北镜像、偏北 10m，而当时没有任何断言盯着「换算后落在哪」。
  3. **竖向基准与净空**（2026-09-21 二次补）——
     · 落地件必须 h=0：运行时承重面就是 y=0，而布局源曾把落地装饰写在 h=0.3
       （= 自持地砖顶面），地砖组又不进重放 ⇒ 实机花草整块砖厚悬空 0.30m；
     · 自持参照地砖的**顶面**必须落在 0.0（⇒ 写 h=−0.30）；
     · 基地东门净空：门洞世界 gz∈[−3.6,−1.4]，东侧落地件按**旋转后包络**判侵入，
       不只看中心点（藤蔓 4.26m 宽，中心离门 2.5m 时叶面已经盖进门洞）。
这三组都是**可反向对照**的：把 author 脚本里的 h=GROUND_H 改回 0.3、或把东侧件挪回
原位，它们立刻变红。
  4. **实例朝向分量与墙挂/落地契约**（2026-09-21 三次补）——
     · 墙挂空调必须绕自身 X 轴倾倒 90°：判据不看欧拉角，直接看**实测包络的长宽高换位**
       （组件原高 1.87 变成「沿墙法线的进深」、原进深 2.365 变成「竖向高度」），
       并核对机背埋在墙外皮内 0.05m；
     · 立管必须**落地**：每处两段（下段倒装 180°）合起来覆盖 0 ~ 2×4.945m，
       最低点落在承重面 y=0 —— 旧版单段放在 h=5.8，管底悬空 5.8m（业主实机报的
       「水管要接下来接到地板」）。
"""
import bpy
import json
import math
from mathutils import Vector
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[6]
ROOT = PROJECT / "assets/art/environments/tower_zones/rooftop/source/layouts/100f_decorated_v001"
BLEND = ROOT / "rooftop_100f_decorated_layout_v001.blend"
MANIFEST = ROOT / "rooftop_100f_decorated_layout_v001.json"
CATALOG = PROJECT / "assets/art/environments/tower_zones/rooftop/source/reference_components/v002/component_packages_v002/catalog.json"

# —— Godot 世界平面口径（与 TowerFloorStage3D / Base100UpperShell3D 对齐）——
GRID = 5.0
RX, RZ, RW, RD = -50.0, -35.0, 90.0, 80.0     # ROOFTOP_WORLD_RECT
SHELL_CX, SHELL_CZ, SHELL_HALF = 0.0, 5.0, 15.0
SHELL_DOOR_GZ = -2.5
SHELL_ROOF_Y = 12.0
TOL = 0.01

# —— 竖向基准与基地东门净空（与 runtime 对齐）——
# GROUND_Y：运行时天台承重面 = y=0（TowerFloorStage3D._floor_visual_origin_y 把地砖可视顶面对齐到 Y=0）。
GROUND_Y = 0.0
# TILE_H：自持参照地砖的底板 y，使砖顶面恰好落 0.0。（TowerFloorStage3D 地砖厚 0.30）
TILE_H = -0.30
# 基地东门净空：Base100UpperShell3D.DOOR_CLEAR_WIDTH/HEIGHT（本地门洞 ⇒ 世界 gz）。
SHELL_DOOR_CLEAR_HALF = 1.1   # DOOR_CLEAR_WIDTH / 2
SHELL_DOOR_CLEAR_H = 2.5      # DOOR_CLEAR_HEIGHT
DOOR_CLEAR_GZ = (SHELL_DOOR_GZ - SHELL_DOOR_CLEAR_HALF, SHELL_DOOR_GZ + SHELL_DOOR_CLEAR_HALF)
DOOR_APPROACH_X = (SHELL_CX + SHELL_HALF - 0.5, SHELL_CX + SHELL_HALF + 5.0)  # 门洞墙片 + 东侧 5m 进出通道

# 会被「挡门」的构件（地板/女儿墙/围护/封顶不算：它们本就该在那儿）。
DOOR_BLOCKER_SLUGS = {
    "hvac_small", "hvac_large", "hvac_vent",
    "flowerbox", "plant_large", "plant_small", "ivy", "parapet_ivy",
    "pipe_straight", "pipe_elbow", "pipe_tee", "pipe_riser", "pipe_bracket",
}
# 落地件：运行时底面必须贴 y=0。ivy 只有基座层落地、上层是叠高件；
# pipe_riser 每处两段里**下段（倒装 180°）**落地，上段坐在它顶上。
GROUNDED_EXPECTED = {"flowerbox": 8, "plant_large": 6, "plant_small": 6, "ivy": 11,
                     "parapet_ivy": 8, "pipe_riser": 4}

EXPECTED_TOTAL = 482
EXPECTED = {
    "floor_full": 234,
    "parapet": 64,
    "parapet_outer": 4,
    "room_wall": 15,
    "room_window": 8,
    "room_doorwall": 1,
    "roof_full": 16,
    "roof_edge": 16,
    "roof_corner": 4,
    "hvac_small": 4,
    "hvac_vent": 2,
    "flowerbox": 8,
    "plant_large": 6,
    "plant_small": 6,
    "ivy": 16,
    "parapet_ivy": 8,
    "pipe_straight": 48,
    "pipe_elbow": 4,
    "pipe_tee": 2,
    "pipe_riser": 8,
    "pipe_bracket": 8,
}

failures = []
def expect(condition, message):
    if not condition:
        failures.append(message)

def godot_planar(obj):
    """Blender 实例 → Godot 世界平面坐标 (world.x, world.z, height)。"""
    return (round(float(obj.location.x), 4), round(-float(obj.location.y), 4), round(float(obj.location.z), 4))

bpy.ops.wm.open_mainfile(filepath=str(BLEND))
scene = bpy.context.scene
instances = bpy.data.collections.get("ROOFTOP_LAYOUT_INSTANCES")
expect(instances is not None, "missing ROOFTOP_LAYOUT_INSTANCES")
objects = list(instances.objects) if instances else []
expect(len(objects) == EXPECTED_TOTAL, f"instance count={len(objects)}, expected {EXPECTED_TOTAL}")
expect(all(o.instance_type == "COLLECTION" for o in objects), "layout contains non-collection instance")
expect(all(tuple(round(v, 6) for v in o.scale) == (1.0, 1.0, 1.0) for o in objects), "non-unit scale present")
expect(not any(o.type == "MESH" for o in objects), "layout collection owns mesh geometry")

counts = {}
for ob in objects:
    slug = ob.get("component_slug", "")
    counts[slug] = counts.get(slug, 0) + 1
for slug, value in EXPECTED.items():
    expect(counts.get(slug, 0) == value, f"{slug}={counts.get(slug, 0)}, expected {value}")

# ── 第 2 层：Godot 空间定位（防再犯） ──
planar = {ob.name: godot_planar(ob) for ob in objects}
expect(len(planar) == EXPECTED_TOTAL, f"planar sample count={len(planar)}")

out_of_rect = [name for name, (x, gz, _) in planar.items() if not (RX - TOL <= x <= RX + RW + TOL and RZ - TOL <= gz <= RZ + RD + TOL)]
expect(not out_of_rect, f"instances outside ROOFTOP_WORLD_RECT: {out_of_rect[:6]} (n={len(out_of_rect)})")

by_slug = {}
for ob in objects:
    by_slug.setdefault(ob.get("component_slug", ""), []).append(planar[ob.name])

# 地砖必须覆盖整个天台矩形（格心口径：外缘正好半个格）
tiles = by_slug.get("floor_full", [])
if tiles:
    xs = [p[0] for p in tiles]
    zs = [p[1] for p in tiles]
    expect(abs(min(xs) - (RX + GRID * 0.5)) < TOL, f"floor tile min x={min(xs)}")
    expect(abs(max(xs) - (RX + RW - GRID * 0.5)) < TOL, f"floor tile max x={max(xs)}")
    expect(abs(min(zs) - (RZ + GRID * 0.5)) < TOL, f"floor tile min z={min(zs)}")
    expect(abs(max(zs) - (RZ + RD - GRID * 0.5)) < TOL, f"floor tile max z={max(zs)}")

# 女儿墙直段必须贴运行时边界（中心线内缩 0.25m）
parapets = by_slug.get("parapet", [])
if parapets:
    south = [p for p in parapets if abs(p[1] - (RZ + RD - 0.25)) < TOL]
    north = [p for p in parapets if abs(p[1] - (RZ + 0.25)) < TOL]
    east = [p for p in parapets if abs(p[0] - (RX + RW - 0.25)) < TOL]
    west = [p for p in parapets if abs(p[0] - (RX + 0.25)) < TOL]
    expect(len(south) == 17, f"south parapet count={len(south)}")
    expect(len(north) == 17, f"north parapet count={len(north)}")
    expect(len(east) == 15, f"east parapet count={len(east)}")
    expect(len(west) == 15, f"west parapet count={len(west)}")

# 房屋围护 = Base100UpperShell（30×30）可视层：墙中心线、门洞、封顶网格逐个同位
walls = []
for slug in ("room_wall", "room_window", "room_doorwall"):
    walls.extend(by_slug.get(slug, []))
expect(len(walls) == 24, f"house wall runs={len(walls)}, expected 24")
for _, gz, height in walls:
    expect(abs(height) < TOL, "house wall must sit on y=0 (visual layer of Base100UpperShell)")

# ⛔ 参照层纪律：房屋围护只作 Blender 侧参照，运行时由 Base100UpperShell3D 独占。
# 一旦有人把它们改回 house_shell / house_roof 组名，运行时会重新重放这 60 件并逐面 z-fighting。
group_names = {o.get("layout_group", "") for o in objects}
expect("house_shell" not in group_names, "house_shell group must not exist (would be replayed by TowerFloorStage3D)")
expect("house_roof" not in group_names, "house_roof group must not exist (would be replayed by TowerFloorStage3D)")
expect("shell_reference" in group_names, "shell_reference group missing")
expect(
    sum(1 for o in objects if o.get("layout_group") == "shell_reference") == 60,
    "shell_reference must contain exactly 24 walls + 36 roof cells",
)
on_south = [p for p in walls if abs(p[1] - (SHELL_CZ + SHELL_HALF)) < TOL]
on_north = [p for p in walls if abs(p[1] - (SHELL_CZ - SHELL_HALF)) < TOL]
on_east = [p for p in walls if abs(p[0] - (SHELL_CX + SHELL_HALF)) < TOL]
on_west = [p for p in walls if abs(p[0] - (SHELL_CX - SHELL_HALF)) < TOL]
expect(len(on_south) == 6 and len(on_north) == 6, f"house wall south/north runs={len(on_south)}/{len(on_north)}")
expect(len(on_east) == 6 and len(on_west) == 6, f"house wall east/west runs={len(on_east)}/{len(on_west)}")

doors = by_slug.get("room_doorwall", [])
expect(len(doors) == 1, f"door wall count={len(doors)}")
if len(doors) == 1:
    dx, dgz, _ = doors[0]
    expect(abs(dx - (SHELL_CX + SHELL_HALF)) < TOL, f"door wall x={dx}, expected east wall 15.0")
    expect(abs(dgz - SHELL_DOOR_GZ) < TOL, f"door wall z={dgz}, expected {SHELL_DOOR_GZ} (Base100UpperShell3D.EAST_DOOR_CENTER_Z)")

roofs = []
for slug in ("roof_full", "roof_edge", "roof_corner"):
    roofs.extend(by_slug.get(slug, []))
expect(len(roofs) == 36, f"house roof cells={len(roofs)}, expected 36 (6x6)")
for _, _, height in roofs:
    expect(abs(height - SHELL_ROOF_Y) < TOL, f"roof cell height={height}, expected {SHELL_ROOF_Y}")
roof_x = sorted({round(p[0], 3) for p in roofs})
roof_z = sorted({round(p[1], 3) for p in roofs})
expect(len(roof_x) == 6 and len(roof_z) == 6, f"roof grid axes={len(roof_x)}x{len(roof_z)}, expected 6x6")
expect(abs(roof_x[0] - (SHELL_CX - SHELL_HALF + GRID * 0.5)) < TOL, f"roof min x={roof_x[0]}")
expect(abs(roof_z[0] - (SHELL_CZ - SHELL_HALF + GRID * 0.5)) < TOL, f"roof min z={roof_z[0]}")

# 装饰不得占用西侧楼梯口 / 南向门洞净空（Godot 口径）
for ob in objects:
    x, gz, _ = planar[ob.name]
    slug = ob.get("component_slug", "")
    if slug in {"flowerbox", "plant_large", "plant_small"}:
        expect(
            not (RX + 10.0 <= x <= RX + 17.0 and 5.0 <= gz <= 15.0),
            f"west stair opening blocked by {slug} at {x},{gz}",
        )

# ── 第 3 层：竖向基准与净空（2026-09-21 二次修正，防再犯） ──
# 判据一律取 **depsgraph 真实几何包络**，不读 instance.location：
#   · location 是「摆放点」；组件原点在底面（catalog bounds_min.z=0），二者只有在 h 正确时等价。
#   · 集合实例的渲染位置 = 实例矩阵 × 组件**根对象归零**后的包络（不是库场景绝对坐标，
#     也不是 ob.matrix_world —— 后者对 linked 对象返回源文件坐标，是陷阱）。
depsgraph = bpy.context.evaluated_depsgraph_get()
instancer_slug = {ob.name: ob.get("component_slug", "") for ob in objects}
real_aabb = {}
for instance in depsgraph.object_instances:
    if not instance.is_instance:
        continue
    parent = instance.parent
    if parent is None or parent.name not in instancer_slug:
        continue
    mesh = instance.object
    if mesh is None or mesh.type != "MESH":
        continue
    box = real_aabb.setdefault(parent.name, [Vector((1e9, 1e9, 1e9)), Vector((-1e9, -1e9, -1e9))])
    matrix = instance.matrix_world
    for corner in mesh.bound_box:
        world = matrix @ Vector(corner)
        for axis in range(3):
            box[0][axis] = min(box[0][axis], world[axis])
            box[1][axis] = max(box[1][axis], world[axis])

expect(len(real_aabb) == EXPECTED_TOTAL, f"depsgraph instance sample={len(real_aabb)}, expected {EXPECTED_TOTAL}")

# 3a. 竖向基准：落地件底面必须落 GROUND_Y（防「整块砖厚悬空」回潮）；地砖顶面必须落 GROUND_Y。
grounded = {slug: 0 for slug in GROUNDED_EXPECTED}
for name, (mn, mx) in real_aabb.items():
    slug = instancer_slug[name]
    if slug in GROUNDED_EXPECTED and abs(mn.z - GROUND_Y) < TOL:
        grounded[slug] += 1
    if slug in GROUNDED_EXPECTED:
        expect(mn.z >= GROUND_Y - TOL, f"{slug} {name} 底面 z={mn.z:.4f} 低于承重面（埋进楼板）")
    if slug == "floor_full":
        expect(abs(mx.z - GROUND_Y) < TOL, f"参照地砖顶面 z={mx.z:.4f}，应落 {GROUND_Y}（⇒ 底板 h={TILE_H}）")
for slug, want in GROUNDED_EXPECTED.items():
    expect(
        grounded[slug] == want,
        f"{slug} 落地件={grounded[slug]}，应 {want}（运行时承重面 y=0；其余为叠高件）",
    )

# 3b. 基地东门净空：门洞世界 gz∈[−3.6,−1.4]、门高 z∈[0,2.5]、东侧 5m 进出通道 x∈[14.5,20]。
#     按**旋转后包络**判侵入 —— 只看中心点会漏（藤蔓 4.26m 宽，中心离门 2.5m 时叶面已盖进门洞）。
door_blocks = []
for name, (mn, mx) in real_aabb.items():
    slug = instancer_slug[name]
    if slug not in DOOR_BLOCKER_SLUGS:
        continue
    if (
        mx.x > DOOR_APPROACH_X[0] + TOL and mn.x < DOOR_APPROACH_X[1] - TOL
        and mx.z > GROUND_Y + TOL and mn.z < SHELL_DOOR_CLEAR_H - TOL
        and -mx.y < DOOR_CLEAR_GZ[1] - TOL and -mn.y > DOOR_CLEAR_GZ[0] + TOL
    ):
        door_blocks.append(f"{slug}@{name} x=[{mn.x:.2f},{mx.x:.2f}] gz=[{-mx.y:.2f},{-mn.y:.2f}] z=[{mn.z:.2f},{mx.z:.2f}]")
expect(not door_blocks, f"基地东门净空被占: {door_blocks}")

# 3c. 女儿墙挂藤必须贴在女儿墙中心线上（四条线：gz=44.75/−34.75、x=39.75/−49.75）。
PARAPET_INSET = 0.25
PARAPET_LINES_X = (RX + RW - PARAPET_INSET, RX + PARAPET_INSET)
PARAPET_LINES_GZ = (RZ + RD - PARAPET_INSET, RZ + PARAPET_INSET)
for name, (mn, mx) in real_aabb.items():
    if instancer_slug[name] != "parapet_ivy":
        continue
    cx = (mn.x + mx.x) * 0.5
    cgz = (-mn.y + -mx.y) * 0.5
    on_x = any(abs(cx - line) < TOL for line in PARAPET_LINES_X)
    on_gz = any(abs(cgz - line) < TOL for line in PARAPET_LINES_GZ)
    expect(on_x or on_gz, f"parapet_ivy {name} 未贴女儿墙中心线: x={cx:.3f} gz={cgz:.3f}")

# 3d. 藤蔓高低错落：顶面至少 5 档、最大最小差 ≥ 3.0m（业主「有的延展高一点、高低错落」）。
ivy_tops = sorted(round(mx.z, 3) for name, (mn, mx) in real_aabb.items() if instancer_slug[name] == "ivy")
expect(len(set(ivy_tops)) >= 5, f"ivy 顶面档数={len(set(ivy_tops))}，应 ≥5（高低错落）")
if ivy_tops:
    expect(ivy_tops[-1] - ivy_tops[0] >= 3.0, f"ivy 顶高落差={ivy_tops[-1] - ivy_tops[0]:.3f}，应 ≥3.0m")

# 3e. 绿化背贴外皮（2026-09-21 五次修正，防再犯）：花箱 / 大盆栽 / 小盆栽必须**背贴**
#     房屋外皮 —— 件心到外皮 = 半进深 − 埋入，即背面埋进外皮内 0.05m。三件进深不同 ⇒
#     件心离外皮的距离不同，但**背面齐平**。判据取 depsgraph 实测包络：
#       · 沿墙法线跨度必须 = 2 × 半进深（顺带验证朝向没把长边转到法线上）；
#       · 背面埋进外皮量必须 = WALL_MOUNT_EMBED。
#     反向对照：把 author 里的 wall_flush_pairs 换回「+2.15 环线」，本组立刻变红。
GREENERY_HALF_DEPTH = {"flowerbox": 0.5925, "plant_large": 0.8727377, "plant_small": 0.5473868}
SHELL_WALL_HALF_T = 0.15    # = author 的 WALL_HALF_THICKNESS（SHELL_WALL_T 0.30 / 2）
GREENERY_EMBED = 0.05       # = author 的 WALL_MOUNT_EMBED（背面埋进外皮内 0.05m）
greenery_snug = {slug: 0 for slug in GREENERY_HALF_DEPTH}
for name, (mn, mx) in real_aabb.items():
    slug = instancer_slug[name]
    if slug not in GREENERY_HALF_DEPTH:
        continue
    cx = (mn.x + mx.x) * 0.5
    cgz = (-mn.y + -mx.y) * 0.5
    half = GREENERY_HALF_DEPTH[slug]
    dx = cx - SHELL_CX
    dgz = cgz - SHELL_CZ
    if abs(dx) > abs(dgz):
        face = SHELL_CX + (SHELL_HALF + SHELL_WALL_HALF_T) * (1 if dx > 0 else -1)
        back = mn.x if dx > 0 else mx.x                       # 外法线朝 ±x 时的机背
        inside = (face - back) if dx > 0 else (back - face)
        span = mx.x - mn.x
        center_gap = abs(cx - face)
    else:
        face = SHELL_CZ + (SHELL_HALF + SHELL_WALL_HALF_T) * (1 if dgz > 0 else -1)
        back_gz = -mx.y if dgz > 0 else -mn.y                 # gz = −blenderY，机背取贴墙一侧
        inside = (face - back_gz) if dgz > 0 else (back_gz - face)
        span = -mn.y - (-mx.y)
        center_gap = abs(cgz - face)
    expect(
        abs(span - 2 * half) < TOL,
        f"{slug} {name} 沿墙法线跨度={span:.4f}，应={2 * half:.4f}（朝向把长边转到法线上了？）",
    )
    expect(
        abs(inside - GREENERY_EMBED) < TOL,
        f"{slug} {name} 没贴墙：背面埋进外皮={inside:.4f}，应={GREENERY_EMBED}"
        f"（业主「花盆和花圃靠墙太远了，要挨着墙放」）",
    )
    expect(
        abs(center_gap - (half - GREENERY_EMBED)) < TOL,
        f"{slug} {name} 件心离外皮={center_gap:.4f}，应={half - GREENERY_EMBED:.4f}（= 半进深 − 埋入）",
    )
    greenery_snug[slug] += 1
for slug, want in GREENERY_HALF_DEPTH.items():
    expect(greenery_snug[slug] == EXPECTED[slug],
           f"{slug} 贴墙件数={greenery_snug[slug]}，应={EXPECTED[slug]}")

# ── 第 4 层：实例朝向分量（墙挂倾倒）与立管落地（2026-09-21 三次修正，防再犯） ──
# 4a. 墙挂空调「风扇朝外」——组件顶面（局部 +Z）是出风风扇，挂到墙上必须绕自身 X 轴
#     倾倒 90°。判据**不看欧拉角**（那样只验证了搬运、没验证几何），而是看实测包络的
#     长宽高换位：组件原「高度」1.87 变成**沿墙法线**的进深、原「进深」2.365 变成
#     **竖向高度** —— 没倾倒时两轴正好反过来。
catalog = {entry["slug"]: entry for entry in json.loads(CATALOG.read_text(encoding="utf-8"))}
hvac_size = catalog["hvac_small"]["bounds_size"]          # [2.5, 2.365, 1.87]
WALL_MOUNT_EMBED = 0.05
WALL_HALF_THICKNESS = 0.15
tipped_units = 0
for name, (mn, mx) in real_aabb.items():
    if instancer_slug[name] != "hvac_small":
        continue
    cx_g = (mn.x + mx.x) * 0.5
    cgz_g = (-mn.y + -mx.y) * 0.5
    dx = cx_g - SHELL_CX
    dgz = cgz_g - SHELL_CZ
    # 该面墙的外法线与外皮位置（取平面主导轴）
    if abs(dx) > abs(dgz):
        outward = (1 if dx > 0 else -1, 0)
        face = SHELL_CX + (SHELL_HALF + WALL_HALF_THICKNESS) * outward[0]
        depth_span = mx.x - mn.x
        back = mn.x if outward[0] > 0 else mx.x
        # 由外皮往建筑内量：外法线朝 +x 时 mn.x 是机背
        inside = (face - back) if outward[0] > 0 else (back - face)
    else:
        outward = (0, 1 if dgz > 0 else -1)
        face = SHELL_CZ + (SHELL_HALF + WALL_HALF_THICKNESS) * outward[1]
        depth_span = -mn.y - (-mx.y)                     # gz 方向跨度
        # gz = -blenderY ⇒ 面朝建筑内侧的“机背”是 gz 较小的一侧（对应 mx.y）。
        # 外法线朝 +gz（南墙）时，机背 = -mx.y；朝 -gz（北墙）时，机背 = -mn.y。
        back_gz = -mx.y if outward[1] > 0 else -mn.y
        inside = (face - back_gz) if outward[1] > 0 else (back_gz - face)
    height_span = mx.z - mn.z
    expect(
        abs(depth_span - hvac_size[2]) < TOL,
        f"hvac_small {name} 沿墙法线进深={depth_span:.4f}，应={hvac_size[2]}（倾倒 90° 后原高度变成进深）",
    )
    expect(
        abs(height_span - hvac_size[1]) < TOL,
        f"hvac_small {name} 竖向高度={height_span:.4f}，应={hvac_size[1]}（倾倒 90° 后原进深变成高度）",
    )
    expect(
        abs(inside - WALL_MOUNT_EMBED) < TOL,
        f"hvac_small {name} 机背没贴墙：埋进外皮={inside:.4f}，应={WALL_MOUNT_EMBED}",
    )
    expect(mx.z <= SHELL_ROOF_Y + TOL, f"hvac_small {name} 顶面 {mx.z:.2f} 高过楼板 {SHELL_ROOF_Y}")
    tipped_units += 1
expect(tipped_units == EXPECTED["hvac_small"], f"墙挂空调数={tipped_units}，应={EXPECTED['hvac_small']}")

# 4b. 立管落地：每处两段（下段倒装 180°）合起来覆盖 0 ~ 2×件高，最低点落承重面 y=0。
riser_h = catalog["pipe_riser"]["bounds_size"][2]         # 4.945
riser_runs = {}
for name, (mn, mx) in real_aabb.items():
    if instancer_slug[name] != "pipe_riser":
        continue
    record = next(o for o in objects if o.name == name)
    x, gz, _ = planar[name]
    riser_runs.setdefault((round(x, 3), round(gz, 3)), []).append((mn.z, mx.z, round(math.degrees(record.rotation_euler[0]), 3)))
expect(len(riser_runs) == 4, f"立管处数={len(riser_runs)}，应=4")
for key, segments in sorted(riser_runs.items()):
    segments.sort()
    if len(segments) != 2:
        expect(False, f"立管 {key} 段数={len(segments)}，应=2（落地需要两段）")
        continue
    (lower_lo, lower_hi, lower_tip), (upper_lo, upper_hi, upper_tip) = segments
    expect(abs(lower_tip - 180.0) < TOL, f"立管 {key} 下段 rotation_x={lower_tip}，应=180（倒装让管底贴地）")
    expect(abs(upper_tip) < TOL, f"立管 {key} 上段 rotation_x={upper_tip}，应=0")
    expect(abs(lower_lo - GROUND_Y) < TOL, f"立管 {key} 管底 z={lower_lo:.4f}，应落承重面 {GROUND_Y}（悬空）")
    expect(abs(lower_hi - riser_h) < TOL, f"立管 {key} 下段顶 z={lower_hi:.4f}，应={riser_h}")
    expect(abs(upper_lo - riser_h) < TOL, f"立管 {key} 上段底 z={upper_lo:.4f}，应={riser_h}（与下段对接）")
    expect(abs(upper_hi - 2 * riser_h) < TOL, f"立管 {key} 管顶 z={upper_hi:.4f}，应={2 * riser_h:.3f}")

# 四条直管跑道 2.5m 插座间距（30m 边长 ⇒ 12 段）
for group, axis in [("PIPE_LOOP_SOUTH", 0), ("PIPE_LOOP_EAST", 1), ("PIPE_LOOP_NORTH", 0), ("PIPE_LOOP_WEST", 1)]:
    values = sorted(
        planar[o.name][axis] for o in objects if o.get("connection_id") == group
    )
    expect(len(values) == 12, f"{group} has {len(values)} pieces, expected 12")
    if len(values) == 12:
        gaps = [round(values[i + 1] - values[i], 4) for i in range(11)]
        expect(all(abs(abs(g) - 2.5) < TOL for g in gaps), f"{group} socket pitch={gaps}")

# ── 第 5 层：逐件碰撞策略（2026-09-21 四次修正；业主「花盆和花圃没有阻挡」）──
# 运行时（TowerFloorStage3D 的 collision_policy 分支）按该字段决定是否生成碰撞代理：
#   blocking    ⇒ 按实测可视包络生成一个 BoxShape3D 代理（layer=1）挡玩家；
#   visual_only ⇒ 禁用组件自带碰撞。
# ⛔ 两侧词表必须一致；blocking 只允许白名单内的 slug —— 少了=可穿过的实体，多了=越权挡人。
BLOCKING_SLUGS = {"flowerbox", "plant_large", "plant_small"}
POLICY_VALUES = {"visual_only", "blocking"}
blocking_objects = [ob for ob in objects if ob.get("collision_policy", "") == "blocking"]
visual_only_objects = [ob for ob in objects if ob.get("collision_policy", "") == "visual_only"]
bad_policy = sorted({str(ob.get("collision_policy", "")) for ob in objects} - POLICY_VALUES)
expect(not bad_policy, f"unknown collision_policy values: {bad_policy}")
expect(len(blocking_objects) + len(visual_only_objects) == EXPECTED_TOTAL,
       f"collision policy covers {len(blocking_objects) + len(visual_only_objects)} / {EXPECTED_TOTAL} instances")
blocking_slugs = sorted({str(ob.get("component_slug", "")) for ob in blocking_objects})
expect(blocking_slugs == sorted(BLOCKING_SLUGS),
       f"blocking slugs={blocking_slugs}, expected {sorted(BLOCKING_SLUGS)}")
expected_blocking = EXPECTED["flowerbox"] + EXPECTED["plant_large"] + EXPECTED["plant_small"]
expect(len(blocking_objects) == expected_blocking,
       f"blocking instances={len(blocking_objects)}, expected {expected_blocking}")
expect(len(visual_only_objects) == EXPECTED_TOTAL - expected_blocking,
       f"visual_only instances={len(visual_only_objects)}, expected {EXPECTED_TOTAL - expected_blocking}")

expect(scene.get("room_owned_geometry") is False, "room_owned_geometry is not false")
expect(scene.get("instance_mode") == "COLLECTION_INSTANCE", "instance mode contract missing")
# scene 级只留一句总述；真源是逐件记录（上方第 5 层已断言）。
expect(str(scene.get("collision_policy", "")).startswith("per_instance"),
       "scene collision policy summary does not declare per_instance")

manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
expect(len(manifest.get("instances", [])) == EXPECTED_TOTAL, "manifest instance count mismatch")
expect(manifest.get("validation", {}).get("non_unit_scale_count") == 0, "manifest non-unit scale contract failed")
expect(manifest.get("validation", {}).get("component_library_modified") is False, "manifest says component library modified")
expect(manifest.get("world_rect_m") == [RX, RZ, RW, RD], "manifest world_rect_m mismatch")
alignment = manifest.get("base_shell_alignment", {})
expect(alignment.get("center_m") == [SHELL_CX, SHELL_CZ], "manifest base_shell_alignment.center_m mismatch")
expect(alignment.get("door_gz_m") == SHELL_DOOR_GZ, "manifest base_shell_alignment.door_gz_m mismatch")

# manifest 自述的竖向基准 / 净空必须与实际几何一致（author 侧这两项曾是写死的字面量）。
man_val = manifest.get("validation", {})
expect(abs(man_val.get("ground_datum_m", 1e9) - GROUND_Y) < TOL, f"manifest ground_datum_m={man_val.get('ground_datum_m')}")
expect(abs(man_val.get("layout_tile_height_m", 1e9) - TILE_H) < TOL, f"manifest layout_tile_height_m={man_val.get('layout_tile_height_m')}")
expect(man_val.get("east_door_clearance_kept") is True, "manifest east_door_clearance_kept != true")

# manifest 自述的碰撞计数必须与 Blender 源实测一致（不是各写各的）。
expect(man_val.get("blocking_collision_count") == len(blocking_objects),
       f"manifest blocking_collision_count={man_val.get('blocking_collision_count')}, actual {len(blocking_objects)}")
expect(man_val.get("visual_only_collision_count") == len(visual_only_objects),
       f"manifest visual_only_collision_count={man_val.get('visual_only_collision_count')}, actual {len(visual_only_objects)}")
man_intent = manifest.get("design_intent", {})
expect(man_intent.get("blocking_slugs") == sorted(BLOCKING_SLUGS),
       f"manifest design_intent.blocking_slugs={man_intent.get('blocking_slugs')}")
expect(man_intent.get("collision_policy") == "per_instance",
       f"manifest design_intent.collision_policy={man_intent.get('collision_policy')}")

if failures:
    print("ROOFTOP_DECOR_LAYOUT_QA_FAIL")
    for failure in failures:
        print("FAIL", failure)
    raise SystemExit(1)
print(
    f"ROOFTOP_DECOR_LAYOUT_QA_OK instances={EXPECTED_TOTAL} collection_instances={EXPECTED_TOTAL} "
    f"mesh_owned=0 godot_rect_violations=0 grounded={grounded} door_blocks=0 "
    f"ivy_top_span={ivy_tops[-1] - ivy_tops[0]:.2f}m "
    f"wall_mount_tipped={tipped_units} riser_runs={len(riser_runs)} "
    f"riser_bottom={min(lo for segs in riser_runs.values() for lo, _, _ in segs):.3f} "
    f"riser_top={max(hi for segs in riser_runs.values() for _, hi, _ in segs):.3f} "
    f"blocking={len(blocking_objects)} visual_only={len(visual_only_objects)}"
)
print("COUNTS", json.dumps(counts, ensure_ascii=False, sort_keys=True))
