"""Isolate every component of a room-type component library into its own .blend,
then reopen and audit each file independently.

Generalized from finalize_boss_component_files_v001.py. Run after
decompose_room_type_components.py for the same library.

Per package it writes <dest>/component_packages/<slug>/<slug>.blend plus
component_probe.json and validation_game_prop.json, and finally
independent_files_validation.json for the whole library.

Usage:
    blender --background --factory-startup --python finalize_room_type_component_files.py -- \
        --dest <rel> --master <file.blend> --source-blend <rel> --room-type <OFFICE_ROOM> \
        --palette <rel>
"""
import bpy
import contextlib
import hashlib
import importlib.util
import io
import json
import sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
_argv = sys.argv
_args = _argv[_argv.index("--") + 1:] if "--" in _argv else []
ARGS = dict(zip(_args[0::2], _args[1::2]))

DEST = ROOT / ARGS["--dest"]
MASTER = DEST / ARGS["--master"]
SOURCE = ROOT / ARGS["--source-blend"]
ROOM_TYPE = ARGS.get("--room-type", "ROOM_TYPE")
PAL = ROOT / ARGS.get("--palette", "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png")
VALIDATOR = Path.home() / ".workbuddy/skills/blender-game-prop-standard/scripts/validate_game_prop.py"


def dump(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes((json.dumps(data, ensure_ascii=False, indent=2) + "\n").replace("\n", "\r\n").encode("utf-8"))


def hashfile(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return Path(path).resolve().relative_to(ROOT).as_posix()


def identity(matrix):
    return max(abs(matrix[i][j] - (1 if i == j else 0)) for i in range(4) for j in range(4)) < 1e-6


def camera_light(scene, bounds):
    lo, hi = map(Vector, bounds)
    center = (lo + hi) * 0.5
    size = hi - lo
    extent = max(size.length, 2.0)
    coll = bpy.data.collections.new("90_Preview_" + scene.name)
    scene.collection.children.link(coll)
    data = bpy.data.cameras.new("Camera_" + scene.name)
    data.type = "ORTHO"
    data.ortho_scale = extent * 1.25
    cam = bpy.data.objects.new("Camera_" + scene.name, data)
    coll.objects.link(cam)
    cam.location = center + Vector((0.8, -1.4, 0.9)).normalized() * extent * 2
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    for name, offset, power in [("Key", (1, -2, 3), 170), ("Fill", (-2, -1, 1), 100), ("Rim", (1, 2, 2), 130)]:
        light_data = bpy.data.lights.new(name + "_" + scene.name, "AREA")
        light_data.energy = power * extent * extent
        light_data.size = extent
        light_obj = bpy.data.objects.new(name + "_" + scene.name, light_data)
        coll.objects.link(light_obj)
        light_obj.location = center + Vector(offset) * extent * 0.8
        light_obj.rotation_euler = (center - light_obj.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 8
    scene.cycles.use_denoising = False
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 2
    scene.render.resolution_x = 800
    scene.render.resolution_y = 650
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.use_nodes = False
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.exposure = 0.5
    return coll


assert MASTER.exists(), MASTER
assert SOURCE.exists(), SOURCE
assert PAL.exists(), PAL
assert VALIDATOR.exists(), VALIDATOR

catalog = json.loads((DEST / "component_catalog.json").read_text(encoding="utf-8"))
source_hash = hashfile(SOURCE)
assert source_hash == catalog["source_room_type_sha256"], "room-type source changed since decomposition"

bpy.ops.wm.open_mainfile(filepath=str(MASTER))
bpy.context.preferences.filepaths.save_version = 0
master_scene = bpy.context.scene

for image in bpy.data.images:
    if image.source == "FILE":
        image.filepath = str(PAL)

world = bpy.data.worlds.new("Component_Studio")
world.use_nodes = True
bg = next(node for node in world.node_tree.nodes if node.type == "BACKGROUND")
bg.inputs["Color"].default_value = (0.30, 0.32, 0.36, 1)
bg.inputs["Strength"].default_value = 0.45

scenes = []
for row in catalog["packages"]:
    slug = row["slug"]
    out = bpy.data.collections[row["collection"]]
    edit = bpy.data.collections[row["editable_collection"]]
    meshes = [obj for obj in out.all_objects if obj.type == "MESH"]
    assert meshes, "empty component: " + slug
    path = DEST / "component_packages" / slug / (slug + ".blend")
    row["component_blend"] = rel(path)
    row["objects"] = [obj.name for obj in meshes]
    row["preview_render_status"] = "camera_ready; representative renders only"
    row["front_axis_coordinate_system"] = "Blender Z-up"
    row["godot_front_axis"] = {
        "-Y": "+Z", "+Y": "-Z", "-X": "-X", "+X": "+X", "+Z": "+Y",
    }.get(row.get("front_axis", "-Y"), "+Z")
    for obj in out.all_objects:
        obj["asset_id"] = row["asset_id"]

    scene = bpy.data.scenes.new("Component_" + slug)
    scene.world = world
    er = bpy.data.collections.new("01_制作组件_" + slug)
    scene.collection.children.link(er)
    er.children.link(edit)
    ort = bpy.data.collections.new("02_游戏输出_" + slug)
    scene.collection.children.link(ort)
    ort.children.link(out)
    scene.view_layers[0].layer_collection.children[er.name].exclude = True
    scene["asset_id"] = row["asset_id"]
    scene["room_owned_geometry"] = False
    scene["runtime_connected"] = False
    camera_light(scene, (row["bounds_lo_m"], row["bounds_hi_m"]))
    scene.render.filepath = str(DEST / "renders" / (slug + ".png"))
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                area.spaces.active.shading.type = "SOLID"
    bpy.data.libraries.write(str(path), {scene}, path_remap="RELATIVE_ALL", fake_user=False, compress=True)
    row["component_file_sha256"] = hashfile(path)
    dump(path.parent / "asset_manifest.json", row)
    scenes.append((row, scene, out))
    print("ISOLATED_FILE_WRITTEN %s" % slug, flush=True)

# Master keeps a separated gallery of real collection instances (never overlapped copies).
gallery = bpy.data.scenes.new("00_Component_Gallery")
gallery.world = world
xs = 0.0
ys = 0.0
rowdepth = 0.0
points = []
for row, scene, out in scenes:
    size = Vector(row["bounds_size_m"])
    lo = Vector(row["bounds_lo_m"])
    hi = Vector(row["bounds_hi_m"])
    if xs + size.x > 90 and xs > 0:
        xs = 0
        ys += rowdepth + 4
        rowdepth = 0
    inst = bpy.data.objects.new("Preview_" + row["slug"], None)
    gallery.collection.objects.link(inst)
    inst.instance_type = "COLLECTION"
    inst.instance_collection = out
    inst.location = (xs - lo.x, ys - lo.y, 0)
    points.extend([lo + inst.location, hi + inst.location])
    xs += size.x + 4
    rowdepth = max(rowdepth, size.y)
low = [min(p[k] for p in points) for k in range(3)]
high = [max(p[k] for p in points) for k in range(3)]
camera_light(gallery, (low, high))
bpy.context.window.scene = gallery
bpy.data.scenes.remove(master_scene)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == "VIEW_3D":
            area.spaces.active.region_3d.view_location = Vector([(low[k] + high[k]) / 2 for k in range(3)])
            area.spaces.active.region_3d.view_distance = max(high[0] - low[0], high[1] - low[1])
bpy.ops.wm.save_as_mainfile(filepath=str(MASTER))
catalog["independent_blend_count"] = len(scenes)
catalog["ledger_registration"] = "pending"
catalog["presentation"] = "separated collection-instance gallery; isolated component scenes with cameras"
dump(DEST / "component_catalog.json", catalog)

# Reopen EVERY independent .blend, not merely the mother library.
spec = importlib.util.spec_from_file_location("standard_validator", VALIDATOR)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)

reports = []
failures = []
for row in catalog["packages"]:
    path = ROOT / row["component_blend"]
    bpy.ops.wm.open_mainfile(filepath=str(path))
    bpy.context.view_layer.update()
    expected = bpy.data.scenes["Component_" + row["slug"]]
    bpy.context.window.scene = expected
    collection = bpy.data.collections[row["collection"]]
    root = bpy.data.objects[row["root_object"]]
    meshes = [obj for obj in collection.all_objects if obj.type == "MESH"]
    checks = {
        "exact_output_object_set": {obj.name for obj in meshes} == set(row["objects"]),
        "one_component_scene": len(bpy.data.scenes) == 1,
        "root_identity": root.parent is None and identity(root.matrix_local),
        "mesh_identity": all(obj.parent == root and identity(obj.matrix_local)
                             and identity(obj.matrix_parent_inverse) for obj in meshes),
        "collection_offset_zero": collection.instance_offset.length < 1e-8,
        "nonempty": bool(meshes),
        "output_membership_unique": all(len(obj.users_collection) == 1 for obj in meshes),
        "camera_ready": expected.camera is not None,
        "not_room_owned": all(not obj.get("room_owned_geometry", False) for obj in meshes),
    }
    points = [obj.matrix_world @ v.co for obj in meshes for v in obj.data.vertices]
    lo = [min(p[k] for p in points) for k in range(3)]
    hi = [max(p[k] for p in points) for k in range(3)]
    checks["bounds_match"] = max(abs(a - b) for a, b in
                                 zip(lo + hi, row["bounds_lo_m"] + row["bounds_hi_m"])) < 1e-5
    checks["bottom_zero"] = abs(lo[2]) < 1e-5
    sys.argv = ["validate", "--", "--all-meshes", "--max-materials", "4",
                "--shared-palette", str(PAL), "--json", str(path.parent / "validation_game_prop.json")]
    with contextlib.redirect_stdout(io.StringIO()):
        try:
            validator.main()
        except SystemExit as exc:
            checks["standard_material_uv"] = exc.code == 0
        except Exception as exc:  # keep auditing the rest of the library
            checks["standard_material_uv"] = False
            checks["standard_material_uv_error"] = str(exc)[:200]
    report = {
        "component_id": row["component_id"],
        "file": rel(path),
        "checks": checks,
        "passed": all(v for k, v in checks.items()),
        "output_mesh_count": len(meshes),
    }
    dump(path.parent / "component_probe.json", report)
    reports.append(report)
    if not report["passed"]:
        failures.append({"component_id": row["component_id"], "failed": [k for k, v in checks.items() if not v]})
    print("ISOLATED_FILE_%s %s" % ("PASS" if report["passed"] else "FAIL", row["slug"]), flush=True)

assert hashfile(SOURCE) == source_hash, "room-type source was modified during finalize"
summary = {
    "room_type": ROOM_TYPE,
    "passed": not failures,
    "independent_blend_count": len(reports),
    "output_mesh_count": sum(r["output_mesh_count"] for r in reports),
    "failure_count": len(failures),
    "failures": failures,
    "source_hash_unchanged": True,
    "source_sha256": source_hash,
    "files": reports,
}
dump(DEST / "independent_files_validation.json", summary)
print("FINALIZE_SUMMARY %s pass=%d fail=%d blends=%d meshes=%d" % (
    ROOM_TYPE, len(reports) - len(failures), len(failures), len(reports),
    summary["output_mesh_count"]), flush=True)
print("ALL_INDEPENDENT_COMPONENTS_OK" if not failures else "ALL_INDEPENDENT_COMPONENTS_HAVE_FAILURES", flush=True)
