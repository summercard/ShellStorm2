"""Create a versioned Base99 source blend and export one lake-blue asset GLB."""

import sys
from pathlib import Path

import bpy
from mathutils import Vector

WHITE_SOURCE_CELL = (9, 0)
LAKE_BLUE_SOURCE_CELL = (3, 9)
EMISSION_MATERIAL = "04_柔和自发光_UI灯光"


def args():
    values = sys.argv[sys.argv.index("--") + 1 :]
    if len(values) != 3:
        raise RuntimeError("Expected: output_blend output_glb package_slug")
    return Path(values[0]), Path(values[1]), values[2]


def cell(uv):
    return min(9, max(0, int(uv.x * 10))), min(9, max(0, int(uv.y * 10)))


def package_for(slug):
    matches = [item for item in bpy.data.collections if item.get("资产包键") == slug]
    if len(matches) != 1:
        raise RuntimeError("Expected one package for %s, found %d" % (slug, len(matches)))
    return matches[0]


def meshes_in(collection):
    result = list(collection.objects)
    for child in collection.children:
        result.extend(meshes_in(child))
    return [obj for obj in result if obj.type == "MESH"]


def remap_source_uvs(objects):
    changed_faces = 0
    for obj in objects:
        uv = obj.data.uv_layers.get("PaletteUV")
        if uv is None:
            continue
        for polygon in obj.data.polygons:
            if polygon.material_index >= len(obj.material_slots):
                continue
            material = obj.material_slots[polygon.material_index].material
            if material is None or material.name != EMISSION_MATERIAL:
                continue
            loops = list(polygon.loop_indices)
            if not loops or any(cell(uv.data[index].uv) != WHITE_SOURCE_CELL for index in loops):
                continue
            center = sum((uv.data[index].uv for index in loops), start=uv.data[loops[0]].uv.copy() * 0.0) / len(loops)
            target = Vector(((LAKE_BLUE_SOURCE_CELL[0] + 0.5) / 10.0, (LAKE_BLUE_SOURCE_CELL[1] + 0.5) / 10.0))
            delta = target - center
            for index in loops:
                uv.data[index].uv += delta
            changed_faces += 1
        obj.data.update()
    if changed_faces == 0:
        raise RuntimeError("No white emissive faces found for remapping")
    return changed_faces


def export_visual(package, output_glb):
    staging = bpy.data.collections.new("lake_blue_export_staging")
    bpy.context.scene.collection.children.link(staging)
    clones = []
    for source in meshes_in(package):
        if source.name.upper().startswith("COLLISION_"):
            continue
        clone = source.copy()
        clone.data = source.data.copy()
        clone.parent = None
        clone.matrix_world = source.matrix_world.copy()
        staging.objects.link(clone)
        clones.append(clone)
    if not clones:
        raise RuntimeError("No visual meshes available for export")
    bpy.ops.object.select_all(action="DESELECT")
    for clone in clones:
        clone.select_set(True)
    bpy.context.view_layer.objects.active = clones[0]
    output_glb.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output_glb),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_materials="EXPORT",
        export_image_format="NONE",
        export_lights=False,
        export_cameras=False,
    )
    for clone in clones:
        bpy.data.objects.remove(clone, do_unlink=True)
    bpy.data.collections.remove(staging)


output_blend, output_glb, slug = args()
package = package_for(slug)
changed = remap_source_uvs(meshes_in(package))
bpy.context.scene["palette_revision"] = "lake_blue_emissive_v022"
bpy.context.scene["palette_revision_note"] = "%s: white emissive faces remapped to lake blue" % slug
output_blend.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(output_blend), compress=True)
export_visual(package, output_glb)
print("LAKE_BLUE_EXPORT_OK package=%s faces=%d blend=%s glb=%s" % (slug, changed, output_blend, output_glb))
