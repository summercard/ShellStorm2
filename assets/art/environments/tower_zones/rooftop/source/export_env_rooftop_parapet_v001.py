"""Export the rooftop reference parapet straight run and outer corner to runtime GLB.

Source blend : assets/art/environments/tower_zones/rooftop/source/reference_components/v002/
               天台区块_参考组件库_v002.blend
Run          : blender.exe --background <blend> --python export_env_rooftop_parapet_v001.py

Origin contract
---------------
In the blend each package keeps its geometry parked at its showcase world position
(直段 at y=-34, 外角 at (16,-34)) with the package 根_ empty marking the intended
origin. This script re-bases every package onto its 根_ before exporting, so each GLB
is XY-centred with the base face at local Z=0 — matching bounds_min / bounds_max in the
package asset_manifest.json.

Exported packages (category 02_女儿墙)
--------------------------------------
女儿墙直段_资产包  -> env_rooftop_ref_parapet_top3d.glb        (5.0 x 0.5 x 1.8 m)
女儿墙外角_资产包  -> env_rooftop_ref_parapet_outer_top3d.glb  (2.5 x 2.5 x 1.8 m)

Only 直段 and 外角 are exported: the 100F rooftop is a plain rectangle, so all four of
its corners are outer (陽) corners and the inner-corner package has no consumer yet.
"""

from pathlib import Path

import bpy
from mathutils import Matrix, Vector

SOURCE_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SOURCE_DIR.parent / "components"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

EXPORTS = {
    "女儿墙直段_资产包": ("根_女儿墙直段", "env_rooftop_ref_parapet_top3d.glb"),
    "女儿墙外角_资产包": ("根_女儿墙外角", "env_rooftop_ref_parapet_outer_top3d.glb"),
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
        "AABB %-12s min=[%.4f, %.4f, %.4f] max=[%.4f, %.4f, %.4f]"
        % (label, mins[0], mins[1], mins[2], maxs[0], maxs[1], maxs[2])
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

    # Re-base onto the package root: bake (world - root) into the mesh data and drop
    # the object transform, so the exported node carries an identity transform with the
    # package origin at its intended place.
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
