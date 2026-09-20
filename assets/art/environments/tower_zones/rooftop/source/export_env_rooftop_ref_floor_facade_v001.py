"""Export the rooftop reference FLOOR tile and FACADE (exterior wall) modules to runtime GLB.

Source blend : assets/art/environments/tower_zones/rooftop/source/reference_components/v002/
               天台区块_参考组件库_v002.blend
Run          : blender.exe --background <blend> --python export_env_rooftop_ref_floor_facade_v001.py

Origin contract
---------------
Each package keeps its geometry parked at its showcase world position (地砖 at y=-17,
外墙 at y=-170) with the package 根_ empty marking the intended origin. This script
re-bases every package onto its 根_ before exporting, so each GLB is XY-centred with the
base face at local Z=0 —— 与已导出的女儿墙 (env_rooftop_ref_parapet_top3d.glb) 完全同口径。

Exported packages
-----------------
完整地砖_资产包        -> env_rooftop_ref_floor_full_top3d.glb   (5.0 x 5.0 x 0.3 m)
标准外墙实墙_资产包     -> env_rooftop_ref_facade_solid_top3d.glb (5.0 x 0.3 x 11.9 m)
标准外墙窗墙_资产包     -> env_rooftop_ref_facade_window_top3d.glb (5.0 x 0.3 x 11.9 m)

挂藤 (vine) 变体不导出：用户口径是「实墙 + 窗墙」两种，藤蔓件留给后续可选装饰波次。
"""

from pathlib import Path

import bpy
from mathutils import Matrix, Vector

SOURCE_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SOURCE_DIR.parent / "components"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

EXPORTS = {
    "完整地砖_资产包": ("根_完整地砖", "env_rooftop_ref_floor_full_top3d.glb"),
    "标准外墙实墙_资产包": ("根_标准外墙实墙", "env_rooftop_ref_facade_solid_top3d.glb"),
    "标准外墙窗墙_资产包": ("根_标准外墙窗墙", "env_rooftop_ref_facade_window_top3d.glb"),
}


def collect_objects(source_collection):
    """Flatten a collection tree into a plain object list."""
    result = list(source_collection.objects)
    for child in source_collection.children:
        result.extend(collect_objects(child))
    return result


def report_aabb(objects, label):
    mins = [float("inf")] * 3
    maxs = [float("-inf")] * 3
    for obj in objects:
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            for axis in range(3):
                mins[axis] = min(mins[axis], world[axis])
                maxs[axis] = max(maxs[axis], world[axis])
    print(
        "AABB %-16s min=[%.4f, %.4f, %.4f] max=[%.4f, %.4f, %.4f] size=[%.4f, %.4f, %.4f]"
        % (
            label,
            mins[0], mins[1], mins[2],
            maxs[0], maxs[1], maxs[2],
            maxs[0] - mins[0], maxs[1] - mins[1], maxs[2] - mins[2],
        )
    )


def export_package(collection_name, root_name, filename):
    collection = bpy.data.collections.get(collection_name)
    if collection is None:
        raise RuntimeError("Missing package collection: %s" % collection_name)
    root = bpy.data.objects.get(root_name)
    if root is None:
        raise RuntimeError("Missing package root object: %s" % root_name)

    bpy.ops.object.select_all(action="DESELECT")

    meshes = []
    for obj in collect_objects(collection):
        if obj.type != "MESH":
            continue
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False
        meshes.append(obj)
    if not meshes:
        raise RuntimeError("Package has no mesh: %s" % collection_name)

    # Re-base onto the package root: bake (world - root) into the mesh data and drop the
    # object transform, so the exported node carries an identity transform with the package
    # origin (底面中心) at local Z=0.
    offset = root.matrix_world.translation.copy()
    rebase = Matrix.Translation(-offset)
    for obj in meshes:
        if obj.data.users > 1:
            obj.data = obj.data.copy()
        obj.data.transform(rebase @ obj.matrix_world)
        obj.matrix_world = Matrix.Identity(4)
        obj.select_set(True)

    report_aabb(meshes, collection_name)

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

print("EXPORT_OK count=%d output=%s" % (len(EXPORTS), OUTPUT_DIR))
