"""Decompose the accepted BOSS_ROOM room-type source into a normalized component library.

This script creates one component-library Blender source with independent output
Collections and per-component manifests. It never edits or saves the room-type
source, and it does not export GLB or touch Godot/runtime files.
"""
import bpy
import hashlib
import json
import math
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[2]
ROOM_DIR = ROOT / "assets/art/environments/tower_zones/expedition/source/room_types/boss_room/v002"
SOURCE_BLEND = ROOM_DIR / "Boss房种类_故障数据库_50x40m_v002.blend"
SOURCE_CATALOG = ROOM_DIR / "component_packages/catalog.json"
DEST = ROOT / "assets/art/environments/tower_zones/expedition/source/common_components/v001"
DEST_BLEND = DEST / "expedition_boss_room_components_source_v001.blend"
PALETTE = ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
RENDER_DIR = DEST / "renders"

ROLE_NAMES = {
    "01_精工金属_紫色骨架",
    "02_细腻哑光_青绿大面",
    "03_清漆反光_紫粉点缀",
    "04_柔和自发光_UI灯光",
}


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    path.write_bytes(text.replace("\n", "\r\n").encode("utf-8"))


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def all_objects(collection):
    result = list(collection.objects)
    for child in collection.children:
        result.extend(all_objects(child))
    return result


def all_mesh_objects(collection):
    return [obj for obj in all_objects(collection) if obj.type == "MESH"]


def new_collection(name, parent):
    collection = bpy.data.collections.new(name)
    parent.children.link(collection)
    collection.instance_offset = (0.0, 0.0, 0.0)
    return collection


def create_root(name, collection):
    root = bpy.data.objects.new(name, None)
    root.empty_display_type = "PLAIN_AXES"
    root.location = (0.0, 0.0, 0.0)
    root.rotation_euler = (0.0, 0.0, 0.0)
    root.scale = (1.0, 1.0, 1.0)
    root["component_root"] = True
    root["local_origin"] = [0.0, 0.0, 0.0]
    collection.objects.link(root)
    return root


def world_bounds(objects):
    points = []
    for obj in objects:
        if obj.type != "MESH":
            continue
        points.extend(obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
    assert points, "component package has no mesh vertices"
    low = [min(point[index] for point in points) for index in range(3)]
    high = [max(point[index] for point in points) for index in range(3)]
    return low, high


def copy_mesh_object(src_obj, name, origin, parent, collection):
    src_mesh = src_obj.data
    vertices = [tuple(src_obj.matrix_world @ vertex.co - Vector(origin)) for vertex in src_mesh.vertices]
    faces = [tuple(poly.vertices) for poly in src_mesh.polygons]
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    for material in src_mesh.materials:
        if material is not None:
            mesh.materials.append(material)

    if src_mesh.uv_layers:
        src_uv = src_mesh.uv_layers.active or src_mesh.uv_layers[0]
        uv = mesh.uv_layers.new(name="PaletteUV")
        uv.active_render = True
        for new_poly, old_poly in zip(mesh.polygons, src_mesh.polygons):
            for new_loop, old_loop in zip(new_poly.loop_indices, old_poly.loop_indices):
                uv.data[new_loop].uv = src_uv.data[old_loop].uv
    else:
        raise AssertionError("missing PaletteUV source: " + src_obj.name)

    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.parent = parent
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.location = (0.0, 0.0, 0.0)
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)
    obj["source_object"] = src_obj.name
    obj["local_origin"] = [0.0, 0.0, 0.0]
    obj["room_owned_geometry"] = False
    return obj


def copy_package(src_objects, slug, package_name, category, origin, output_category, editable_category):
    output_collection = new_collection(package_name + "_输出包", output_category)
    editable_collection = new_collection(package_name + "_制作源", editable_category)
    output_root = create_root("ROOT_" + slug + "_组件", output_collection)
    editable_root = create_root("ROOT_" + slug + "_制作源", editable_collection)
    output_objects = []
    editable_objects = []
    for index, src_obj in enumerate(src_objects):
        if src_obj.type != "MESH":
            raise AssertionError("non-mesh object in package: " + src_obj.name)
        suffix = "自发光" if any(material and material.name == "04_柔和自发光_UI灯光" for material in src_obj.data.materials) else "部件%02d" % index
        output_objects.append(copy_mesh_object(src_obj, package_name + "_输出_" + suffix, origin, output_root, output_collection))
        editable_objects.append(copy_mesh_object(src_obj, package_name + "_制作_" + suffix, origin, editable_root, editable_collection))
    return output_collection, editable_collection, output_root, editable_root, output_objects, editable_objects


def side_from_package(row):
    package_id = row["package_id"]
    for side in ("north", "south", "east", "west"):
        if package_id.startswith("base_wall_" + side) or package_id.startswith("wall_skin_" + side):
            return side
    return None


def front_axis(row):
    side = side_from_package(row)
    if side == "north":
        return "-Y"
    if side == "south":
        return "+Y"
    if side == "east":
        return "-X"
    if side == "west":
        return "+X"
    if row["category"] == "floor":
        return "+Z"
    return "-Y"


def allowed_rotations(row):
    package_id = row["package_id"]
    if row["category"] == "floor" and package_id.startswith("base_floor"):
        return [0, 90, 180, 270]
    return [0]


def add_preview_copy(src_obj, name, location, collection):
    mesh = src_obj.data.copy()
    is_emissive = any(material and material.name == "04_柔和自发光_UI灯光" for material in mesh.materials)
    if is_emissive and "自发光" not in name:
        name += "_自发光"
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)
    return obj


def add_area_light(name, location, energy, color, size, target, collection):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.color = color
    data.shape = "DISK"
    data.size = size
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()
    return obj


def add_camera(name, location, target, scale, collection):
    data = bpy.data.cameras.new(name)
    data.type = "ORTHO"
    data.ortho_scale = scale
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()
    return obj


assert SOURCE_BLEND.exists(), SOURCE_BLEND
assert SOURCE_CATALOG.exists(), SOURCE_CATALOG
assert PALETTE.exists(), PALETTE
# The first run may have saved the source before a preview-render crash. This
# task owns that generated partial output, so a rerun may replace it after the
# source hash and package checks below pass.
source_hash = sha256(SOURCE_BLEND)
source_catalog = json.loads(SOURCE_CATALOG.read_text(encoding="utf-8"))
source_rows = source_catalog["packages"]
assert source_rows, "source catalog is empty"
assert len({row["package_id"] for row in source_rows}) == len(source_rows), "duplicate package_id"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE_BLEND))
bpy.context.view_layer.update()
source_output = next(collection for collection in bpy.data.collections if collection.name == "02_游戏输出_独立资产包_v002")
source_collections = {collection.name: collection for collection in source_output.children_recursive}
source_scene_objects = list(bpy.data.objects)
source_scene_collections = list(bpy.data.collections)
source_package_objects = {}
object_owners = {}
for row in source_rows:
    collection = source_collections.get(row["collection"])
    assert collection is not None, "missing source collection: " + row["collection"]
    objects = all_mesh_objects(collection)
    assert objects, "empty source package: " + row["package_id"]
    expected = set(row["objects"])
    actual = {obj.name for obj in objects}
    assert expected == actual, "source object list mismatch: " + row["package_id"]
    for obj in objects:
        if obj.name in object_owners:
            raise AssertionError("object assigned to multiple packages: " + obj.name)
        object_owners[obj.name] = row["package_id"]
    source_package_objects[row["package_id"]] = objects

# Keep the four shared material roles and their external palette image in memory.
source_materials = {material.name: material for material in bpy.data.materials if material.name in ROLE_NAMES}
assert set(source_materials) == ROLE_NAMES, "shared material role set changed"

# Keep source datablocks alive while copying every package. They are removed
# only after the normalized output and editable copies are complete.
scene = bpy.context.scene
root = new_collection("EXPEDITION_BOSS_ROOM_组件库_资产管理", scene.collection)
editable_root_collection = new_collection("01_制作组件_按组件拆分", root)
output_root_collection = new_collection("02_游戏输出_独立资产包_v001", root)
preview_collection = new_collection("90_展示与验收_灯光相机", root)
category_names = {
    "architecture": "01_建筑结构",
    "floor": "02_地面系统",
    "facilities": "03_固定设施",
    "support": "04_环境支持",
}
output_categories = {key: new_collection(name, output_root_collection) for key, name in category_names.items()}
editable_categories = {key: new_collection(name + "_制作", editable_root_collection) for key, name in category_names.items()}

manifest = []
preview_samples = []
for row in source_rows:
    package_id = row["package_id"]
    src_objects = source_package_objects[package_id]
    low, high = world_bounds(src_objects)
    origin = [(low[0] + high[0]) / 2.0, (low[1] + high[1]) / 2.0, low[2]]
    output_collection, editable_collection, output_root, editable_root, output_objects, editable_objects = copy_package(
        src_objects,
        package_id,
        row["name_zh"],
        row["category"],
        origin,
        output_categories[row["category"]],
        editable_categories[row["category"]],
    )
    for collection in (output_collection, editable_collection):
        collection.instance_offset = (0.0, 0.0, 0.0)
    for root_object in (output_root, editable_root):
        assert tuple(root_object.location) == (0.0, 0.0, 0.0)
        assert tuple(root_object.rotation_euler) == (0.0, 0.0, 0.0)
        assert tuple(root_object.scale) == (1.0, 1.0, 1.0)
    local_low, local_high = world_bounds(output_objects)
    local_size = [local_high[index] - local_low[index] for index in range(3)]
    assert max(abs(value) for value in local_low[:2]) > 0.0 or max(abs(value) for value in local_high[:2]) > 0.0
    assert abs(local_low[2]) < 0.00001, (package_id, local_low)
    assert all(tuple(obj.location) == (0.0, 0.0, 0.0) for obj in output_objects)
    assert all(tuple(obj.scale) == (1.0, 1.0, 1.0) for obj in output_objects)
    materials = sorted({material.name for obj in output_objects for material in obj.data.materials if material})
    emissive = [obj.name for obj in output_objects if any(material and material.name == "04_柔和自发光_UI灯光" for material in obj.data.materials)]
    asset_id = "ENV-EXPEDITION-BOSSROOM-V002-" + package_id.upper().replace("-", "_")
    component = {
        "component_id": asset_id,
        "room_type": "BOSS_ROOM",
        "source_room_type_blend": str(SOURCE_BLEND.relative_to(ROOT)).replace("\\", "/"),
        "source_room_type_sha256": source_hash,
        "component_blend": str(DEST_BLEND.relative_to(ROOT)).replace("\\", "/"),
        "collection": output_collection.name,
        "editable_collection": editable_collection.name,
        "root_object": output_root.name,
        "bounds_size_m": [round(float(value), 6) for value in local_size],
        "bounds_lo_m": [round(float(value), 6) for value in local_low],
        "bounds_hi_m": [round(float(value), 6) for value in local_high],
        "local_origin": [0.0, 0.0, 0.0],
        "front_axis": front_axis(row),
        "allowed_rotations_y_deg": allowed_rotations(row),
        "collision_owner": "godot_wrapper",
        "palette_uv_layer": "PaletteUV",
        "asset_ledger": "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx::3D-场景通用",
        "room_owned_geometry": False,
        "instance_offset": [0.0, 0.0, 0.0],
        "emissive_objects": emissive,
        "material_roles": materials,
        "source_package_id": package_id,
        "version": "v001",
        "collision": "not_authored",
        "exported": False,
        "runtime_connected": False,
    }
    manifest.append(component)
    write_json(DEST / "component_packages" / package_id / "asset_manifest.json", component)
    if package_id in {"north_complete_00", "north_damaged_01", "heavy_conduits", "workstation_00", "base_wall_north_slot_01_solid"}:
        preview_samples.append((package_id, output_objects))

# Source scene objects are no longer needed after all package copies are made.
# Remove only the snapshotted source datablocks; normalized library objects stay.
for obj in source_scene_objects:
    if obj.name in bpy.data.objects:
        bpy.data.objects.remove(obj, do_unlink=True)
for collection in source_scene_collections:
    if collection.name in bpy.data.collections:
        bpy.data.collections.remove(collection)
for child in list(scene.collection.children):
    if child.name != root.name:
        scene.collection.children.unlink(child)

# Preview scene uses copies of five representative package meshes. The library
# packages remain independent and the preview copies are not package ownership.
preview_positions = [(-8, 0, 0), (-2, 0, 0), (5, 0, 0), (-8, 7, 0), (4, 7, 0)]
for (package_id, objects), position in zip(preview_samples, preview_positions):
    for index, src_obj in enumerate(objects):
        add_preview_copy(src_obj, "预览_" + package_id + "_%02d" % index, position, preview_collection)

world = bpy.data.worlds.new("组件库展示环境")
world.use_nodes = True
world_nodes = world.node_tree.nodes
world_links = world.node_tree.links
world_nodes.clear()
world_background = world_nodes.new("ShaderNodeBackground")
world_background.name = "组件库背景"
world_output = world_nodes.new("ShaderNodeOutputWorld")
world_links.new(world_background.outputs["Background"], world_output.inputs["Surface"])
world_background.inputs["Color"].default_value = (0.08, 0.10, 0.13, 1.0)
world_background.inputs["Strength"].default_value = 0.35
scene.world = world
add_area_light("组件库主光", (4, -14, 18), 9000, (0.75, 0.84, 1.0), 16, (0, 3, 1.5), preview_collection)
add_area_light("组件库轮廓光", (-14, 5, 12), 7000, (0.65, 0.78, 1.0), 12, (0, 3, 1.5), preview_collection)
add_area_light("组件库暖填光", (14, 8, 8), 5000, (1.0, 0.72, 0.55), 10, (0, 3, 1.5), preview_collection)
scene.camera = add_camera("组件库代表组件相机", (18, -26, 15), (0, 3, 2.0), 25, preview_collection)
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 1200
scene.render.resolution_y = 700
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.view_settings.look = "AgX - Medium High Contrast"
scene.render.filepath = str(RENDER_DIR / "component_library_overview.png")
RENDER_DIR.mkdir(parents=True, exist_ok=True)

scene["component_library"] = True
scene["room_type"] = "BOSS_ROOM"
scene["block_id"] = "expedition"
scene["source_room_type_sha256"] = source_hash
scene["component_count"] = len(manifest)
scene["room_owned_geometry"] = False
scene["runtime_connected"] = False
scene["decomposition_stage"] = "component_source_only"

bpy.context.view_layer.update()
# Save the component source before any optional viewport/render work. The
# workstation has a known Blender 4.5 Eevee shader-memory crash, so rendering
# is intentionally not part of this decomposition transaction.
bpy.ops.wm.save_as_mainfile(filepath=str(DEST_BLEND))

catalog = {
    "schema": "shellstorm2.component_catalog.v001",
    "component_library": "expedition_boss_room_components_source_v001.blend",
    "source_room_type": str(SOURCE_BLEND.relative_to(ROOT)).replace("\\", "/"),
    "source_room_type_sha256": source_hash,
    "room_type": "BOSS_ROOM",
    "block_id": "expedition",
    "version": "v001",
    "runtime_connected": False,
    "packages": manifest,
}
write_json(DEST / "component_catalog.json", catalog)
(DEST / "component_tree.txt").write_bytes(("\r\n".join(component["collection"] + " -> " + component["root_object"] for component in manifest) + "\r\n").encode("utf-8"))
write_json(DEST / "decomposition_report.json", {
    "source_room_type_sha256": source_hash,
    "component_count": len(manifest),
    "object_assignment_count": len(object_owners),
    "duplicate_source_objects": False,
    "all_output_instance_offsets_zero": True,
    "all_output_roots_identity": True,
    "room_owned_geometry": False,
    "collision_authored": False,
    "glb_exported": False,
    "godot_runtime_connected": False,
})
print("BOSS_ROOM_COMPONENT_DECOMPOSE_OK", str(DEST_BLEND), len(manifest), len(object_owners), flush=True)
