"""Export the 100F decorated-layout component subset from the v002 rooftop library.

Run with Blender 4.5:
  blender.exe --background <v002-library.blend> --python export_rooftop_decor_components_v001.py

Only the eleven decoration components missing from the existing Godot asset set are
exported here. Room walls and roof modules already have their own audited exporter.
Each package is rebased onto its declared root object before export. The source .blend
is never saved by this script.
"""
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

SOURCE_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SOURCE_DIR.parent / "components"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

EXPORTS = {
    "小型空调机组_资产包": ("根_小型空调机组", "env_rooftop_ref_hvac_small_top3d.glb"),
    "小通风口_资产包": ("根_小通风口", "env_rooftop_ref_hvac_vent_top3d.glb"),
    "直管段_资产包": ("根_直管段", "env_rooftop_ref_pipe_straight_top3d.glb"),
    "转角弯管_资产包": ("根_转角弯管", "env_rooftop_ref_pipe_elbow_top3d.glb"),
    "三通管_资产包": ("根_三通管", "env_rooftop_ref_pipe_tee_top3d.glb"),
    "立管下水管_资产包": ("根_立管下水管", "env_rooftop_ref_pipe_riser_top3d.glb"),
    "管道支架_资产包": ("根_管道支架", "env_rooftop_ref_pipe_bracket_top3d.glb"),
    "墙面攀爬藤蔓_资产包": ("根_墙面攀爬藤蔓", "env_rooftop_ref_ivy_top3d.glb"),
    "女儿墙挂藤_资产包": ("根_女儿墙挂藤", "env_rooftop_ref_parapet_ivy_top3d.glb"),
    "长条花箱_资产包": ("根_长条花箱", "env_rooftop_ref_flowerbox_top3d.glb"),
    "大盆栽_资产包": ("根_大盆栽", "env_rooftop_ref_plant_large_top3d.glb"),
    "小盆栽_资产包": ("根_小盆栽", "env_rooftop_ref_plant_small_top3d.glb"),
}


def collect_objects(collection):
    result = list(collection.objects)
    for child in collection.children:
        result.extend(collect_objects(child))
    return result


def world_aabb(objects):
    minimum = Vector((float("inf"),) * 3)
    maximum = Vector((float("-inf"),) * 3)
    for obj in objects:
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            minimum.x = min(minimum.x, world.x)
            minimum.y = min(minimum.y, world.y)
            minimum.z = min(minimum.z, world.z)
            maximum.x = max(maximum.x, world.x)
            maximum.y = max(maximum.y, world.y)
            maximum.z = max(maximum.z, world.z)
    return minimum, maximum


def export_package(collection_name, root_name, filename):
    collection = bpy.data.collections.get(collection_name)
    root = bpy.data.objects.get(root_name)
    if collection is None:
        raise RuntimeError("Missing package collection: %s" % collection_name)
    if root is None:
        raise RuntimeError("Missing package root: %s" % root_name)

    meshes = [obj for obj in collect_objects(collection) if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError("Package has no mesh: %s" % collection_name)

    bpy.ops.object.select_all(action="DESELECT")
    rebase = Matrix.Translation(-root.matrix_world.translation)
    for obj in meshes:
        if obj.data.users > 1:
            obj.data = obj.data.copy()
        obj.data.transform(rebase @ obj.matrix_world)
        obj.matrix_world = Matrix.Identity(4)
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]

    minimum, maximum = world_aabb(meshes)
    size = maximum - minimum
    print(
        "AABB %s min=[%.6f,%.6f,%.6f] max=[%.6f,%.6f,%.6f] size=[%.6f,%.6f,%.6f]"
        % (
            collection_name,
            minimum.x,
            minimum.y,
            minimum.z,
            maximum.x,
            maximum.y,
            maximum.z,
            size.x,
            size.y,
            size.z,
        )
    )

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
    print("EXPORTED %s -> %s" % (collection_name, output_path))


for package_collection, (package_root, package_filename) in EXPORTS.items():
    export_package(package_collection, package_root, package_filename)

print("ROOFTOP_DECOR_COMPONENT_EXPORT_OK count=%d output=%s" % (len(EXPORTS), OUTPUT_DIR))
