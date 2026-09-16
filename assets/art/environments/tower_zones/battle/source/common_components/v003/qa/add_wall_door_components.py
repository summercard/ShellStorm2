"""把「通用门墙」与「通用门」作为新资产包追加进 战局区块_通用组件库_v003.blend。

背景：v003 通用组件库此前只有 08_墙壁组件/wall_standard_5m 一个墙体资产，
且门墙、门从未进入 v003 规划。本次按 L 型转角确立的范式补齐三件：
  08_墙壁组件/wall_standard_5m  （已存在，本脚本不动它）
  08_墙壁组件/wall_door_5m      （新增，3 mesh：左门垛 + 右门垛 + 门楣）
  10_门组件/door_5m             （新增，1 mesh：门扇）

尺寸全部取自项目权威常量，不是美术估值：
  src/world3d/TowerGeometry3D.gd
    GRID_UNIT_M            = 5.0    → 墙宽
    WALL_VISUAL_HEIGHT_M   = 12.0 - 0.1 = 11.9 → 墙高
    DOOR_CLEAR_WIDTH_M     = 2.2    → 门洞宽 / 门扇宽
    DOOR_CLEAR_HEIGHT_M    = 2.5    → 门洞高 / 门扇高
  src/world3d/RoomDoor3D.gd
    PANEL_THICKNESS_M      = 0.18   → 门扇厚
  wall_standard_5m 既有 mesh       → 墙厚 0.3
这些值与老公版 MOD_WALL_DOOR_5M 系列实测值（门洞 2.2 x 2.5、总宽 5.0、总高 11.9、
门扇厚 0.18）逐项吻合，互为交叉验证。

坐标契约（与 v003 全库一致）：
  - 正面 = 本地 +Y                    → Godot -Z
  - 水平面 X/Y 居中、底面 Z = 0        → Godot 底面 Y=0、XZ 居中
  - 几何直接写进 mesh 数据，object.location 保持 (0,0,0)；
    组件原点由父级 EMPTY「ROOT_<slug>_通用组件」承担，
    导出脚本再用 root.matrix_world.inverted() 把世界变换折算回局部。

展示布局沿用 build_common_library_v003.py 的排布算法
（每件占位 x += size.x/2 + 1.5，行距 = max(size.y, 1) + 4.5），
使新件与既有 09 行的 y = -63.8444 自然衔接。

幂等：目标集合已存在则跳过该类，不重复建件。运行前自动备份 blend。
"""

from __future__ import annotations

import shutil
from pathlib import Path

import bpy
from mathutils import Matrix

V003 = Path(
    r"I:\工作项目\shellstrom2\ShellStorm2\assets\art\environments"
    r"\tower_zones\battle\source\common_components\v003"
)
BLEND = V003 / "战局区块_通用组件库_v003.blend"
BACKUP = BLEND.with_suffix(".blend.bak_before_wall_door")
PALETTE = Path(
    r"I:\工作项目\shellstrom2\ShellStorm2\assets\art\shared\palette"
    r"\设施低亮多巴胺色盘_10x10_512.png"
)

# 尺寸契约
HALF_WIDE = 5.0 / 2.0          # 2.5   墙半宽
HALF_THICK = 0.3 / 2.0         # 0.15  墙半厚
WALL_TOP = 11.9                # 墙高
DOOR_HALF_WIDE = 2.2 / 2.0     # 1.1   门洞半宽
DOOR_TOP = 2.5                 # 门洞高
DOOR_HALF_THICK = 0.18 / 2.0   # 0.09  门扇半厚

WALL_MATERIAL = "02_细腻哑光_青绿大面"
DOOR_MATERIAL = "01_精工金属_紫色骨架"

# PaletteUV 色块：col9 是中性灰蓝专用列，u 取 [0.912, 0.948] 避开格边防串色。
# 墙面沿用标准墙同一色块（col9,row1 #A5B2C1），保证墙系视觉统一；
# 门扇改用 (col9,row3 #718195) 的中灰蓝金属，与墙区分开。
WALL_UV = [(0.912, 0.112), (0.948, 0.112), (0.948, 0.148), (0.912, 0.148)]
DOOR_UV = [(0.912, 0.312), (0.948, 0.312), (0.948, 0.348), (0.912, 0.348)]

# 展示布局（沿用既有算法推导）
WALL_DOOR_SHOWCASE = (8.0, -58.3444, 0.0)   # 接在 wall_standard_5m 之后，同一行
DOOR_SHOWCASE = (2.6, -69.3444, 0.0)        # 新起一行

NEW_PACKAGES = {
    # slug: (分类, 展示位置, [(mesh 名, x0, x1, y0, y1, z0, z1, 材质, uv)])
    "wall_door_5m": (
        "08_墙壁组件",
        WALL_DOOR_SHOWCASE,
        [
            ("wall_door_5m_门垛左_输出", -HALF_WIDE, -DOOR_HALF_WIDE, -HALF_THICK, HALF_THICK, 0.0, WALL_TOP, WALL_MATERIAL, WALL_UV),
            ("wall_door_5m_门垛右_输出", DOOR_HALF_WIDE, HALF_WIDE, -HALF_THICK, HALF_THICK, 0.0, WALL_TOP, WALL_MATERIAL, WALL_UV),
            ("wall_door_5m_门楣_输出", -DOOR_HALF_WIDE, DOOR_HALF_WIDE, -HALF_THICK, HALF_THICK, DOOR_TOP, WALL_TOP, WALL_MATERIAL, WALL_UV),
        ],
    ),
    "door_5m": (
        "10_门组件",
        DOOR_SHOWCASE,
        [
            ("door_5m_门扇_输出", -DOOR_HALF_WIDE, DOOR_HALF_WIDE, -DOOR_HALF_THICK, DOOR_HALF_THICK, 0.0, DOOR_TOP, DOOR_MATERIAL, DOOR_UV),
        ],
    ),
}

BOX_FACES = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (4, 0, 3, 7)]


def make_box_mesh(name, x0, x1, y0, y1, z0, z1, material_name, uv_coords):
    mesh = bpy.data.meshes.new(f"{name}_网格")
    verts = [
        (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
        (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1),
    ]
    mesh.from_pydata(verts, [], BOX_FACES)
    mesh.update()
    mesh.materials.append(bpy.data.materials[material_name])
    uv = mesh.uv_layers.new(name="PaletteUV")
    uv.active = True
    uv.active_render = True
    for poly in mesh.polygons:
        for i, loop_index in enumerate(poly.loop_indices):
            uv.data[loop_index].uv = uv_coords[i % 4]
    return mesh


def aabb_of(mesh):
    pts = [v.co for v in mesh.vertices]
    return (
        [min(p[i] for p in pts) for i in range(3)],
        [max(p[i] for p in pts) for i in range(3)],
    )


print(f"BLEND   = {BLEND}")
print(f"BACKUP  = {BACKUP}")

if not BLEND.is_file():
    raise SystemExit(f"缺少源 blend: {BLEND}")

bpy.ops.wm.open_mainfile(filepath=str(BLEND))

# 源 blend 的外链色盘记录的是作者机（macOS）绝对路径，本机需重新绑定。
image = bpy.data.images.get("设施低亮多巴胺色盘_10x10_512.png")
if image is not None and PALETTE.is_file():
    image.filepath = str(PALETTE)
    image.reload()
    print(f"palette rebound -> {image.filepath}")

out_root = bpy.data.collections.get("02_游戏输出_独立资产包_v003")
src_root = bpy.data.collections.get("01_制作组件_按设施拆分")
show_root = bpy.data.collections.get("90_展示与验收_灯光相机")
if out_root is None or src_root is None:
    raise SystemExit("blend 结构与预期不符：缺少输出/制作根集合")

report = {}
created_any = False

for slug, (category_name, showcase, parts) in NEW_PACKAGES.items():
    package_name = f"{slug}_通用包"
    if bpy.data.collections.get(package_name) is not None:
        print(f"SKIP {slug}: 集合 {package_name} 已存在（幂等）")
        report[slug] = {"status": "already_present"}
        continue

    category_col = bpy.data.collections.get(category_name)
    if category_col is None:
        category_col = bpy.data.collections.new(category_name)
        out_root.children.link(category_col)
        print(f"新增分类集合: {category_name}")

    source_group_name = f"{slug}_制作源"
    source_group = bpy.data.collections.new(source_group_name)
    src_category = bpy.data.collections.get(f"{category_name}.001")
    if src_category is None:
        src_category = bpy.data.collections.new(f"{category_name}.001")
        src_root.children.link(src_category)
    src_category.children.link(source_group)

    package_col = bpy.data.collections.new(package_name)
    category_col.children.link(package_col)

    root_obj = bpy.data.objects.new(f"ROOT_{slug}_通用组件", None)
    root_obj.empty_display_type = "PLAIN_AXES"
    root_obj.location = showcase
    root_obj["front_direction"] = "+Y"
    package_col.objects.link(root_obj)

    mesh_names = []
    for part_name, x0, x1, y0, y1, z0, z1, material_name, uv_coords in parts:
        mesh = make_box_mesh(part_name, x0, x1, y0, y1, z0, z1, material_name, uv_coords)

        obj = bpy.data.objects.new(part_name, mesh)
        obj.parent = root_obj
        obj.matrix_parent_inverse = Matrix.Identity(4)
        obj.location = (0.0, 0.0, 0.0)
        package_col.objects.link(obj)
        mesh_names.append(obj.name)

        # 制作源副本：与既有约定一致（AP_<slug>_<i>_<role>_制作源）
        source_obj = bpy.data.objects.new(f"AP_{slug}_{len(mesh_names) - 1:02d}_制作源", mesh.copy())
        source_obj.location = (0.0, 0.0, 0.0)
        source_group.objects.link(source_obj)

        mn, mx = aabb_of(mesh)
        print(f"  [{part_name}] local aabb min={[round(v, 4) for v in mn]} max={[round(v, 4) for v in mx]}")

    label_name = f"标签_{category_name}"
    if bpy.data.objects.get(label_name) is None:
        curve = bpy.data.curves.new(label_name, "FONT")
        curve.body = f"{category_name}  1件"
        curve.size = 0.72
        curve.extrude = 0.012
        label_obj = bpy.data.objects.new(label_name, curve)
        label_obj.location = (-2.5, showcase[1], 0.05)
        show_root.objects.link(label_obj)
        print(f"新增标签: {label_name}")

    report[slug] = {
        "status": "created",
        "category": category_name,
        "collection": package_name,
        "root_object": root_obj.name,
        "meshes": mesh_names,
        "showcase_position": list(showcase),
    }
    created_any = True

bpy.context.view_layer.update()

if not created_any:
    print("NOTHING_TO_DO 所有目标资产包均已存在，未写文件")
else:
    shutil.copy2(BLEND, BACKUP)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    print(f"BACKUP_WRITTEN {BACKUP}")
    print(f"SAVED {BLEND}")

print("ADD_REPORT " + str(report))
print(f"ADD_OK created={sum(1 for v in report.values() if v.get('status') == 'created')}")
