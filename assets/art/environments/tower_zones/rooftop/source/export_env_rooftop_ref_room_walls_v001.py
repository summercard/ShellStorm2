"""Export the rooftop reference component library's ROOM-WALL / DOOR / ROOF sets to runtime GLB.

Source blend : assets/art/environments/tower_zones/rooftop/source/reference_components/v002/
               天台区块_参考组件库_v002.blend
Run          : blender.exe --background <blend> --python export_env_rooftop_ref_room_walls_v001.py

Origin contract
---------------
每个 _资产包 的网格顶点已经落在「根_<件>」局部坐标系里（底面中心：XY 居中、Z 向上、底面 Z=0），
对象自己的 matrix_world 只负责把它停在展示阵列的某一行上。沿用
export_env_rooftop_ref_floor_facade_v001.py 的口径：先做 rebase = Translation(-根_世界位置)
再导出，对这批件等价于恒等变换，因此每个 GLB 的根节点都是恒等变换。

门 / 门扇 拆分（用户口径：拆成两个 prefab）
-----------------------------------------
门与暖灯_资产包 的「门与暖灯_主体」是 528 顶点的焊接网格，但它由 22 个松散部件拼成，
其中恰好有 5 件属于门扇本体：门扇板 / 门板 / 窥窗框 / 窥窗玻璃 / 门把手。
本脚本用 门与暖灯_制作组件 里 5 个同名制作件的局部 AABB 精确核对（不靠顶点数猜），
把这 5 个松散部件切出来单独导出，其余 17 件导出为门组件（含门框 / 铰链 / 门槛 /
厚石材门柱 / 厚门楣 / 进深门槛 / 门灯罩 + UI灯光自发光灯芯）。
这是对游戏输出网格的精确二分，不重导美术、不改任何尺寸。

门扇的原点重新定到「门扇板自身的底面中心」（与 prp_tower_door_leaf_5m 同口径）：
门扇板局部 y ∈ [0.327, 0.507] → 平移 -0.417 后厚度精确对称于 0。
装配时门扇相对门组件原点的偏移 = Godot (0, 0, -0.417)。

导出清单（11 件）
-----------------
房间标准墙_资产包        -> env_rooftop_ref_room_wall_top3d.glb          (5.0 x 11.9 x 0.3)
房间窗墙_资产包          -> env_rooftop_ref_room_window_top3d.glb        (5.0 x 11.9 x 0.3)
房间门洞墙_资产包        -> env_rooftop_ref_room_doorwall_top3d.glb      (5.0 x 11.9 x 0.3, 门洞 3.8 x 6.8)
房间实墙挂藤_资产包      -> env_rooftop_ref_room_wall_ivy_top3d.glb
房间窗墙挂藤_资产包      -> env_rooftop_ref_room_window_ivy_top3d.glb
房间门洞墙挂藤_资产包    -> env_rooftop_ref_room_doorwall_ivy_top3d.glb
门与暖灯_资产包 (去门扇) -> env_rooftop_ref_room_door_top3d.glb          (4.9 x 7.57 x 1.555)
门与暖灯_主体 门扇部件   -> env_rooftop_ref_room_door_leaf_top3d.glb     (3.68 x 6.80 x 0.18 结构 / 0.41 可视)
房顶完整板_资产包        -> env_rooftop_ref_roof_full_top3d.glb          (5.0 x 0.3 x 5.0)
房顶边缘板_资产包        -> env_rooftop_ref_roof_edge_top3d.glb          (5.0 x 0.3 x 5.0)
房顶角板_资产包          -> env_rooftop_ref_roof_corner_top3d.glb        (5.0 x 0.3 x 5.0)
"""

from pathlib import Path

import bpy
import bmesh
from mathutils import Matrix, Vector

SOURCE_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SOURCE_DIR.parent / "components"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------- 简单件（整包导出）
EXPORTS = {
    "房间标准墙_资产包": ("根_房间标准墙", "env_rooftop_ref_room_wall_top3d.glb"),
    "房间窗墙_资产包": ("根_房间窗墙", "env_rooftop_ref_room_window_top3d.glb"),
    "房间门洞墙_资产包": ("根_房间门洞墙", "env_rooftop_ref_room_doorwall_top3d.glb"),
    "房间实墙挂藤_资产包": ("根_房间实墙挂藤", "env_rooftop_ref_room_wall_ivy_top3d.glb"),
    "房间窗墙挂藤_资产包": ("根_房间窗墙挂藤", "env_rooftop_ref_room_window_ivy_top3d.glb"),
    "房间门洞墙挂藤_资产包": ("根_房间门洞墙挂藤", "env_rooftop_ref_room_doorwall_ivy_top3d.glb"),
    "房顶完整板_资产包": ("根_房顶完整板", "env_rooftop_ref_roof_full_top3d.glb"),
    "房顶边缘板_资产包": ("根_房顶边缘板", "env_rooftop_ref_roof_edge_top3d.glb"),
    "房顶角板_资产包": ("根_房顶角板", "env_rooftop_ref_roof_corner_top3d.glb"),
}

# ---------------------------------------------------------------- 门 / 门扇
DOOR_COLLECTION = "门与暖灯_资产包"
DOOR_ROOT = "根_门与暖灯"
DOOR_BODY = "门与暖灯_主体"
DOOR_GLB = "env_rooftop_ref_room_door_top3d.glb"
LEAF_GLB = "env_rooftop_ref_room_door_leaf_top3d.glb"
# 5 个门扇部件在 制作组件 里的对象名（用于 AABB 核对；不是靠顶点数猜）
LEAF_MAKERS = (
    "门与暖灯_门扇_制作", "门与暖灯_门板_制作", "门与暖灯_窥窗框_制作",
    "门与暖灯_窥窗玻璃_制作", "门与暖灯_门把手_制作",
)
AABB_EPS = 1e-4


def collect_objects(source_collection):
    """Flatten a collection tree into a plain object list."""
    result = list(source_collection.objects)
    for child in source_collection.children:
        result.extend(collect_objects(child))
    return result


def local_aabb(obj):
    """AABB in the owner's local coordinate system (v.co, no matrix_world)."""
    mn = [float("inf")] * 3
    mx = [float("-inf")] * 3
    for v in obj.data.vertices:
        for axis in range(3):
            mn[axis] = min(mn[axis], v.co[axis])
            mx[axis] = max(mx[axis], v.co[axis])
    return mn, mx


def report_aabb(objects, label):
    mn = [float("inf")] * 3
    mx = [float("-inf")] * 3
    for obj in objects:
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            for axis in range(3):
                mn[axis] = min(mn[axis], world[axis])
                mx[axis] = max(mx[axis], world[axis])
    print(
        "AABB %-22s min=[%.4f, %.4f, %.4f] max=[%.4f, %.4f, %.4f] size=[%.4f, %.4f, %.4f]"
        % (label, mn[0], mn[1], mn[2], mx[0], mx[1], mx[2],
           mx[0]-mn[0], mx[1]-mn[1], mx[2]-mn[2])
    )


def export_selected(objects, filename):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    output_path = OUTPUT_DIR / filename
    bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_extras=True,
        export_materials="EXPORT",
        export_image_format="NONE",
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )
    print("EXPORTED %s -> %s" % (filename, output_path))


def export_package(collection_name, root_name, filename):
    collection = bpy.data.collections.get(collection_name)
    if collection is None:
        raise RuntimeError("Missing package collection: %s" % collection_name)
    root = bpy.data.objects.get(root_name)
    if root is None:
        raise RuntimeError("Missing package root object: %s" % root_name)

    meshes = [o for o in collect_objects(collection) if o.type == "MESH"]
    if not meshes:
        raise RuntimeError("Package has no mesh: %s" % collection_name)

    # Re-base onto the package root: bake (world - root) into the mesh data and drop the
    # object transform, so the exported node carries an identity transform with the package
    # origin (底面中心) at local Z=0.
    rebase = Matrix.Translation(-root.matrix_world.translation)
    for obj in meshes:
        if obj.data.users > 1:
            obj.data = obj.data.copy()
        obj.data.transform(rebase @ obj.matrix_world)
        obj.matrix_world = Matrix.Identity(4)

    report_aabb(meshes, collection_name)
    export_selected(meshes, filename)


# ================================================================ 1) 简单件
for package_collection, (package_root, package_filename) in EXPORTS.items():
    export_package(package_collection, package_root, package_filename)

# ================================================================ 2) 门 / 门扇
door_collection = bpy.data.collections.get(DOOR_COLLECTION)
door_root = bpy.data.objects.get(DOOR_ROOT)
door_body = bpy.data.objects.get(DOOR_BODY)
if door_collection is None or door_root is None or door_body is None:
    raise RuntimeError("Door package missing (collection/root/body)")

# 目标：5 个制作件的局部 AABB
leaf_targets = []
for name in LEAF_MAKERS:
    maker = bpy.data.objects.get(name)
    if maker is None:
        raise RuntimeError("Missing leaf maker object: %s" % name)
    leaf_targets.append((name, local_aabb(maker)))
leaf_union = (
    [min(t[1][0][i] for t in leaf_targets) for i in range(3)],
    [max(t[1][1][i] for t in leaf_targets) for i in range(3)],
)
print("LEAF target union min=[%.4f, %.4f, %.4f] max=[%.4f, %.4f, %.4f]"
      % (leaf_union[0][0], leaf_union[0][1], leaf_union[0][2],
         leaf_union[1][0], leaf_union[1][1], leaf_union[1][2]))

# 主体网格的松散部件分解
bm = bmesh.new()
bm.from_mesh(door_body.data)
bm.faces.ensure_lookup_table()
seen = set()
parts = []          # list of (face_index_list, aabb_min, aabb_max)
for face in bm.faces:
    if face.index in seen:
        continue
    stack = [face]
    seen.add(face.index)
    group = []
    while stack:
        cur = stack.pop()
        group.append(cur)
        for edge in cur.edges:
            for linked in edge.link_faces:
                if linked.index not in seen:
                    seen.add(linked.index)
                    stack.append(linked)
    mn = [float("inf")] * 3
    mx = [float("-inf")] * 3
    for f in group:
        for v in f.verts:
            for axis in range(3):
                mn[axis] = min(mn[axis], v.co[axis])
                mx[axis] = max(mx[axis], v.co[axis])
    parts.append(([f.index for f in group], mn, mx))
bm.free()
print("DOOR body loose parts = %d" % len(parts))


def matches(a, b):
    return all(abs(a[0][i] - b[0][i]) < AABB_EPS and abs(a[1][i] - b[1][i]) < AABB_EPS
               for i in range(3))


leaf_face_indices = set()
matched_makers = set()
for face_indices, mn, mx in parts:
    for maker_name, target in leaf_targets:
        if matches((mn, mx), target):
            if maker_name in matched_makers:
                raise RuntimeError("Leaf part matched twice for %s" % maker_name)
            matched_makers.add(maker_name)
            leaf_face_indices.update(face_indices)
            print("  leaf part <- %-28s faces=%-3d min=[%.3f,%.3f,%.3f] size=[%.3f,%.3f,%.3f]"
                  % (maker_name, len(face_indices), mn[0], mn[1], mn[2],
                     mx[0]-mn[0], mx[1]-mn[1], mx[2]-mn[2]))
            break
missing = [n for n, _ in leaf_targets if n not in matched_makers]
if missing:
    raise RuntimeError("Leaf makers not matched to any loose part: %s" % missing)

leaf_face_count = len(leaf_face_indices)
door_face_count = sum(len(f) for f, _, _ in parts) - leaf_face_count
if leaf_face_count <= 0 or door_face_count <= 0:
    raise RuntimeError("Degenerate split: leaf=%d door=%d" % (leaf_face_count, door_face_count))
print("SPLIT leaf_faces=%d door_faces=%d total=%d"
      % (leaf_face_count, door_face_count, leaf_face_count + door_face_count))

# 门扇原点平移：门扇板中心 -> 0（底边中心口径）
slab_name, (slab_min, slab_max) = leaf_targets[0]
leaf_shift = Vector((0.0, -(slab_min[1] + slab_max[1]) * 0.5, 0.0))
print("LEAF shift y=%.4f (slab %s)" % (leaf_shift.y, slab_name))

temp_collection = bpy.data.collections.new("_export_scratch")
bpy.context.scene.collection.children.link(temp_collection)


def make_split_object(name, source_mesh, remove_indices):
    mesh = source_mesh.copy()
    bmx = bmesh.new()
    bmx.from_mesh(mesh)
    bmx.faces.ensure_lookup_table()
    kill = [f for f in bmx.faces if f.index in remove_indices]
    if kill:
        bmesh.ops.delete(bmx, geom=kill, context="FACES")
    bmx.to_mesh(mesh)
    bmx.free()
    obj = bpy.data.objects.new(name, mesh)
    temp_collection.objects.link(obj)
    obj.matrix_world = Matrix.Identity(4)
    return obj


all_face_indices = set(range(len(door_body.data.polygons)))
door_obj = make_split_object("门与暖灯_门组件_主体", door_body.data, leaf_face_indices)
leaf_obj = make_split_object("门与暖灯_门扇_主体", door_body.data, all_face_indices - leaf_face_indices)
leaf_obj.data.transform(Matrix.Translation(leaf_shift))

# 门组件 = 拆分后的主体 + UI 灯光（自发光灯芯）
door_extras = [o for o in collect_objects(door_collection) if o.type == "MESH" and o is not door_body]
for obj in door_extras:
    if obj.data.users > 1:
        obj.data = obj.data.copy()
    obj.data.transform(Matrix.Translation(-door_root.matrix_world.translation) @ obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)
print("DOOR extras = %s" % [o.name for o in door_extras])

report_aabb([door_obj] + door_extras, "room_door")
report_aabb([leaf_obj], "room_door_leaf")
export_selected([door_obj] + door_extras, DOOR_GLB)
export_selected([leaf_obj], LEAF_GLB)

# ================================================================ 3) 收尾
for obj in list(temp_collection.objects):
    bpy.data.objects.remove(obj, do_unlink=True)
bpy.data.collections.remove(temp_collection)
for mesh in list(bpy.data.meshes):
    if mesh.users == 0:
        bpy.data.meshes.remove(mesh)

print("EXPORT_OK count=%d output=%s" % (len(EXPORTS) + 2, OUTPUT_DIR))
