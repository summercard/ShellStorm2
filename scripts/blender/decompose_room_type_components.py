"""Decompose one accepted room-type source into a per-room-type component library.

Generalized from decompose_boss_room_components_v001.py (the reference run that
produced common_components/v001). This script:

  * reads the room-type package list (component_packages/catalog.json or the
    top-level component_inventory.json),
  * copies every package mesh into a normalized component library blend with an
    output collection and an editable working collection per package,
  * normalizes the component origin to bottom-center of its bounds,
  * writes one asset_manifest.json per package plus catalog/tree/report files.

It never edits or saves the room-type source, and it does not export GLB or
touch Godot/runtime files.

Usage:
    blender --background --factory-startup --python decompose_room_type_components.py -- \
        --room-dir <rel> --ver <v001> --dest <rel> --dest-name <file.blend> \
        --room-type <OFFICE_ROOM> --library-version <v002> --asset-prefix <ENV-EXPEDITION-L01-OFFICE>
"""
import bpy
import hashlib
import json
import sys
from pathlib import Path
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]

_argv = sys.argv
_args = _argv[_argv.index("--") + 1:] if "--" in _argv else []
ARGS = dict(zip(_args[0::2], _args[1::2]))

ROOM_DIR = ROOT / ARGS["--room-dir"]
VER = ARGS.get("--ver", "")
DEST = ROOT / ARGS["--dest"]
DEST_BLEND = DEST / ARGS["--dest-name"]
ROOM_TYPE = ARGS["--room-type"]
LIB_VERSION = ARGS["--library-version"]
ASSET_PREFIX = ARGS.get("--asset-prefix", "ENV-EXPEDITION-COMP")
PALETTE = ROOT / ARGS.get("--palette", "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png")
LEDGER = ARGS.get("--ledger", "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx::资产主表")

CATEGORY_NAMES = {
    "architecture": "01_建筑结构",
    "floor": "02_地面系统",
    "facilities": "03_固定设施",
    "decor": "03_固定设施",
    "support": "04_环境支持",
    "environment": "04_环境支持",
}
CATEGORY_FALLBACK = "05_未分类"
# validate_game_prop.py accepts these markers on emissive meshes.
EMISSIVE_MARKERS = ("自发光", "ui灯光", "emissive", "glow")


def material_is_emissive_name(name):
    return any(marker in str(name).lower() for marker in EMISSIVE_MARKERS)


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    path.write_bytes(text.replace("\n", "\r\n").encode("utf-8"))


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return Path(path).resolve().relative_to(ROOT).as_posix()


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
        raise AssertionError("missing UV source: " + src_obj.name)

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


def copy_package(src_objects, slug, package_name, origin, output_category, editable_category):
    output_collection = new_collection(package_name + "_输出包", output_category)
    editable_collection = new_collection(package_name + "_制作源", editable_category)
    output_root = create_root("ROOT_" + slug + "_组件", output_collection)
    editable_root = create_root("ROOT_" + slug + "_制作源", editable_collection)
    output_objects = []
    editable_objects = []
    for index, src_obj in enumerate(src_objects):
        if src_obj.type != "MESH":
            raise AssertionError("non-mesh object in package: " + src_obj.name)
        # Emissive parts must carry a recognised marker in their object name:
        # validate_game_prop.py rejects emissive meshes unless the name contains
        # one of 自发光 / ui灯光 / emissive / glow.
        is_emissive = any(m is not None and material_is_emissive_name(m.name)
                          for m in src_obj.data.materials)
        suffix = "自发光" if is_emissive else "部件%02d" % index
        output_objects.append(copy_mesh_object(src_obj, package_name + "_输出_" + suffix, origin, output_root, output_collection))
        editable_objects.append(copy_mesh_object(src_obj, package_name + "_制作_" + suffix, origin, editable_root, editable_collection))
    return output_collection, editable_collection, output_root, editable_root, output_objects, editable_objects


def side_from_id(package_id):
    low = package_id.lower()
    for side in ("north", "south", "east", "west"):
        if ("wall_" + side) in low or ("skin_" + side) in low or low.endswith("_" + side):
            return side
    return None


def front_axis(row):
    side = side_from_id(row.get("package_id", ""))
    explicit = str(row.get("forward_axis", "") or "").strip()
    if explicit:
        return explicit
    if side == "north":
        return "-Y"
    if side == "south":
        return "+Y"
    if side == "east":
        return "-X"
    if side == "west":
        return "+X"
    if row.get("category") == "floor":
        return "+Z"
    return "-Y"


def allowed_rotations(row):
    package_id = str(row.get("package_id", ""))
    if row.get("category") == "floor" and "floor" in package_id.lower():
        return [0, 90, 180, 270]
    return [0]


def component_id_for(row):
    package_id = str(row.get("package_id", "")).strip()
    if package_id.upper().startswith("ENV-"):
        return package_id
    return (ASSET_PREFIX + "-" + package_id.upper().replace("-", "_")).replace("__", "_")


# ---------------------------------------------------------------- load inputs
blend = next(p for p in sorted(ROOM_DIR.glob("*.blend")))
assert blend.exists(), blend
assert PALETTE.exists(), PALETTE

def load_package_rows(room_dir, ver):
    """Per-package asset_manifest.json is the richest source (batch-level
    catalogs may omit 'collection'); fall back to the batch list."""
    manifests = sorted(room_dir.glob("**/asset_manifest.json"))
    if manifests:
        rows = []
        for path in manifests:
            row = json.loads(path.read_text(encoding="utf-8"))
            assert row.get("package_id"), "manifest without package_id: %s" % path
            rows.append(row)
        return rows, manifests[0].parent.parent
    candidates = [room_dir / "component_packages" / "catalog.json"]
    if ver:
        candidates.append(room_dir / ("component_packages_%s" % ver) / "catalog.json")
    candidates.append(room_dir / "component_inventory.json")
    for cand in candidates:
        if cand.exists():
            data = json.loads(cand.read_text(encoding="utf-8"))
            return (data["packages"] if isinstance(data, dict) else data), cand
    return None, None


source_rows, list_path = load_package_rows(ROOM_DIR, VER)
assert source_rows, "no package list found"
assert len({row.get("package_id") for row in source_rows}) == len(source_rows), "duplicate package_id"

source_hash = sha256(blend)

bpy.ops.wm.open_mainfile(filepath=str(blend))
bpy.context.view_layer.update()

collection_by_name = {c.name: c for c in bpy.data.collections}
source_scene_objects = list(bpy.data.objects)
source_scene_collections = list(bpy.data.collections)

source_package_objects = {}
object_owners = {}
for row in source_rows:
    cname = row.get("collection")
    assert cname, "manifest row without 'collection': " + str(row.get("package_id"))
    collection = collection_by_name.get(cname)
    assert collection is not None, "missing source collection: " + cname
    objects = all_mesh_objects(collection)
    assert objects, "empty source package: " + str(row.get("package_id"))
    declared = row.get("objects")
    if declared is not None:
        # batches differ: some list plain names, some list {name, location_m, ...}
        declared_names = {d if isinstance(d, str) else d.get("name") for d in declared}
        assert declared_names == {o.name for o in objects}, "source object list mismatch: " + str(row.get("package_id"))
    for obj in objects:
        if obj.name in object_owners:
            raise AssertionError("object assigned to multiple packages: " + obj.name)
        object_owners[obj.name] = row.get("package_id")
    source_package_objects[row.get("package_id")] = objects

source_materials = sorted({m.name for m in bpy.data.materials if m})
assert source_materials, "source blend has no materials"

# ---------------------------------------------------------------- build library
scene = bpy.context.scene
library_root = new_collection("EXPEDITION_%s_组件库_资产管理" % ROOM_TYPE, scene.collection)
editable_root_collection = new_collection("01_制作组件_按组件拆分", library_root)
output_root_collection = new_collection("02_游戏输出_独立资产包_%s" % LIB_VERSION, library_root)

used_categories = []
for row in source_rows:
    key = str(row.get("category", "")).strip()
    if key and key not in used_categories:
        used_categories.append(key)
output_categories = {
    key: new_collection(CATEGORY_NAMES.get(key, CATEGORY_FALLBACK), output_root_collection)
    for key in used_categories
}
editable_categories = {
    key: new_collection(CATEGORY_NAMES.get(key, CATEGORY_FALLBACK) + "_制作", editable_root_collection)
    for key in used_categories
}

manifest = []
for row in source_rows:
    package_id = str(row.get("package_id"))
    slug = str(row.get("slug") or package_id).strip()
    package_name = str(row.get("name_zh") or slug).strip()
    category = str(row.get("category", "")).strip()
    src_objects = source_package_objects[package_id]
    low, high = world_bounds(src_objects)
    origin = [(low[0] + high[0]) / 2.0, (low[1] + high[1]) / 2.0, low[2]]
    output_collection, editable_collection, output_root, editable_root, output_objects, editable_objects = copy_package(
        src_objects, slug, package_name, origin,
        output_categories[category], editable_categories[category],
    )
    for collection in (output_collection, editable_collection):
        collection.instance_offset = (0.0, 0.0, 0.0)
    for root_object in (output_root, editable_root):
        assert tuple(root_object.location) == (0.0, 0.0, 0.0)
        assert tuple(root_object.rotation_euler) == (0.0, 0.0, 0.0)
        assert tuple(root_object.scale) == (1.0, 1.0, 1.0)
    local_low, local_high = world_bounds(output_objects)
    local_size = [local_high[index] - local_low[index] for index in range(3)]
    assert abs(local_low[2]) < 1e-5, (package_id, local_low)
    assert all(tuple(obj.location) == (0.0, 0.0, 0.0) for obj in output_objects)
    assert all(tuple(obj.scale) == (1.0, 1.0, 1.0) for obj in output_objects)
    materials = sorted({m.name for obj in output_objects for m in obj.data.materials if m})
    emissive = [obj.name for obj in output_objects
                if any(m and material_is_emissive_name(m.name) for m in obj.data.materials)]
    component = {
        "component_id": component_id_for(row),
        "asset_id": component_id_for(row),
        "room_type": ROOM_TYPE,
        "source_room_type_blend": rel(blend),
        "source_room_type_sha256": source_hash,
        "component_library_blend": rel(DEST_BLEND),
        "component_blend": rel(DEST / "component_packages" / slug / (slug + ".blend")),
        "collection": output_collection.name,
        "editable_collection": editable_collection.name,
        "root_object": output_root.name,
        "source_package_id": package_id,
        "slug": slug,
        "name_zh": package_name,
        "category": category,
        "bounds_size_m": [round(float(v), 6) for v in local_size],
        "bounds_lo_m": [round(float(v), 6) for v in local_low],
        "bounds_hi_m": [round(float(v), 6) for v in local_high],
        "local_origin": [0.0, 0.0, 0.0],
        "origin_contract": "bottom-center of component bounds; source placement only in traceability metadata",
        "front_axis": front_axis(row),
        "front_axis_coordinate_system": "Blender Z-up",
        "allowed_rotations_y_deg": allowed_rotations(row),
        "allowed_rotations_blender_z_deg": allowed_rotations(row),
        "collision_owner": str(row.get("collision_owner") or "godot_wrapper"),
        "palette_uv_layer": "PaletteUV",
        "asset_ledger": LEDGER,
        "room_owned_geometry": False,
        "instance_offset": [0.0, 0.0, 0.0],
        "emissive_objects": emissive,
        "material_roles": materials,
        "source_world_origin_m": row.get("world_origin_m"),
        "version": LIB_VERSION,
        "collision": "not_authored",
        "exported": False,
        "runtime_connected": False,
        "ledger_registration": "pending; component source only, not formal runtime asset",
        "objects": [obj.name for obj in output_objects],
    }
    manifest.append(component)
    write_json(DEST / "component_packages" / slug / "asset_manifest.json", component)

# ---------------------------------------------------------------- drop source
for obj in source_scene_objects:
    if obj.name in bpy.data.objects:
        bpy.data.objects.remove(obj, do_unlink=True)
for collection in source_scene_collections:
    if collection.name in bpy.data.collections:
        bpy.data.collections.remove(collection)
for child in list(scene.collection.children):
    if child.name != library_root.name:
        scene.collection.children.unlink(child)

scene["component_library"] = True
scene["room_type"] = ROOM_TYPE
scene["block_id"] = "expedition"
scene["source_room_type_sha256"] = source_hash
scene["component_count"] = len(manifest)
scene["room_owned_geometry"] = False
scene["runtime_connected"] = False
scene["decomposition_stage"] = "component_source_only"

bpy.context.view_layer.update()
DEST.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(DEST_BLEND))

catalog = {
    "schema": "shellstorm2.component_catalog.v001",
    "component_library": DEST_BLEND.name,
    "room_type": ROOM_TYPE,
    "block_id": "expedition",
    "version": LIB_VERSION,
    "source_room_type": rel(blend),
    "source_room_type_sha256": source_hash,
    "source_package_list": rel(list_path),
    "runtime_connected": False,
    "ledger_registration": "pending",
    "packages": manifest,
}
write_json(DEST / "component_catalog.json", catalog)
(DEST / "component_tree.txt").write_bytes(
    ("\r\n".join(c["collection"] + " -> " + c["root_object"] for c in manifest) + "\r\n").encode("utf-8")
)
write_json(DEST / "decomposition_report.json", {
    "room_type": ROOM_TYPE,
    "library_version": LIB_VERSION,
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
print("ROOM_TYPE_COMPONENT_DECOMPOSE_OK %s %s %d %d" % (
    ROOM_TYPE, rel(DEST_BLEND), len(manifest), len(object_owners)), flush=True)
