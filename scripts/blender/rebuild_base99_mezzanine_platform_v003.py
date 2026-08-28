"""Rebuild the Base99 Z5 mezzanine from editable Blender components.

The v002 full-width deck slab shared its four exterior planes and lower height
range with the authored edge beams.  This revision keeps the deck skin inside
the frame and above the visible grid beams so no exterior coplanar faces remain.
"""

from __future__ import annotations

import json
import hashlib
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


PROJECT_ROOT = Path("/Users/summercards/ShellStorm2")
ASSET_ROOT = PROJECT_ROOT / "assets/art/environments/base_facility_3d"
INPUT_BLEND = ASSET_ROOT / "source/env_base99_modular_room/env_base99_modular_room_assets_clean_v004.blend"
OUTPUT_BLEND = ASSET_ROOT / "source/env_base99_modular_room/env_base99_modular_room_assets_clean_v005.blend"
OUTPUT_GLB = ASSET_ROOT / "components/env_base99_mezzanine_20x10_z5/env_base99_mezzanine_20x10_z5_visual_top3d_v003.glb"
PREVIEW = ASSET_ROOT / "source/env_base99_modular_room/previews/env_base99_mezzanine_20x10_z5_preview_v003.png"
MANIFEST = ASSET_ROOT / "source/env_base99_modular_room/env_base99_mezzanine_20x10_z5_v003_manifest.json"

ASSET_ID = "ENV-BASE99-MEZZANINE-20X10-Z5"
VERSION = "v003"
DECK_SKIN_HORIZONTAL_INSET_M = 0.15
DECK_SKIN_BOTTOM_M = 4.78
DECK_SKIN_TOP_M = 4.90


def descendants(root: bpy.types.Object) -> list[bpy.types.Object]:
    result: list[bpy.types.Object] = []
    pending = list(root.children)
    while pending:
        child = pending.pop()
        result.append(child)
        pending.extend(child.children)
    return result


def root_bounds(root: bpy.types.Object) -> tuple[Vector, Vector]:
    inverse = root.matrix_world.inverted()
    points = [
        inverse @ obj.matrix_world @ vertex.co
        for obj in descendants(root)
        if obj.type == "MESH"
        for vertex in obj.data.vertices
    ]
    minimum = Vector(tuple(min(point[index] for point in points) for index in range(3)))
    maximum = Vector(tuple(max(point[index] for point in points) for index in range(3)))
    return minimum, maximum


def object_bounds_in_root(root: bpy.types.Object, obj: bpy.types.Object) -> tuple[Vector, Vector]:
    inverse = root.matrix_world.inverted()
    points = [inverse @ obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    minimum = Vector(tuple(min(point[index] for point in points) for index in range(3)))
    maximum = Vector(tuple(max(point[index] for point in points) for index in range(3)))
    return minimum, maximum


def remap_deck_skin(root: bpy.types.Object, slab: bpy.types.Object) -> tuple[Vector, Vector, Vector, Vector]:
    old_minimum, old_maximum = object_bounds_in_root(root, slab)
    new_minimum = Vector((
        old_minimum.x + DECK_SKIN_HORIZONTAL_INSET_M,
        old_minimum.y + DECK_SKIN_HORIZONTAL_INSET_M,
        DECK_SKIN_BOTTOM_M,
    ))
    new_maximum = Vector((
        old_maximum.x - DECK_SKIN_HORIZONTAL_INSET_M,
        old_maximum.y - DECK_SKIN_HORIZONTAL_INSET_M,
        DECK_SKIN_TOP_M,
    ))
    root_inverse = root.matrix_world.inverted()
    object_inverse = slab.matrix_world.inverted()
    for vertex in slab.data.vertices:
        point = root_inverse @ slab.matrix_world @ vertex.co
        mapped = Vector()
        for axis in range(3):
            ratio = (point[axis] - old_minimum[axis]) / max(1.0e-8, old_maximum[axis] - old_minimum[axis])
            mapped[axis] = new_minimum[axis] + ratio * (new_maximum[axis] - new_minimum[axis])
        vertex.co = object_inverse @ root.matrix_world @ mapped
    slab.data.update()
    slab["semantic_component"] = "inset_deck_skin"
    slab["coplanar_edge_faces_removed"] = True
    return old_minimum, old_maximum, new_minimum, new_maximum


def remove_tree(root: bpy.types.Object) -> None:
    for child in list(descendants(root)):
        if child.data is not None and child.data.users == 1:
            bpy.data.meshes.remove(child.data, do_unlink=True)
        elif child.name in bpy.data.objects:
            bpy.data.objects.remove(child, do_unlink=True)
    if root.name in bpy.data.objects:
        bpy.data.objects.remove(root, do_unlink=True)


def duplicate_for_output(source: bpy.types.Object, output_root: bpy.types.Object, collection: bpy.types.Collection) -> bpy.types.Object:
    duplicate = source.copy()
    duplicate.data = source.data.copy()
    collection.objects.link(duplicate)
    duplicate.parent = output_root
    duplicate.matrix_local = source.matrix_local.copy()
    duplicate.hide_viewport = False
    duplicate.hide_render = False
    duplicate.hide_select = False
    duplicate.hide_set(False)
    return duplicate


def join_group(objects: list[bpy.types.Object], name: str) -> bpy.types.Object:
    if not objects:
        raise RuntimeError("Cannot build empty output group: %s" % name)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.hide_viewport = False
        obj.hide_select = False
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    with bpy.context.temp_override(
        active_object=objects[0],
        object=objects[0],
        selected_objects=objects,
        selected_editable_objects=objects,
    ):
        bpy.ops.object.join()
        bpy.ops.object.material_slot_remove_unused()
    joined = bpy.context.active_object
    joined.name = name
    joined.select_set(False)
    return joined


def rebuild_output(source_root: bpy.types.Object) -> bpy.types.Object:
    old_outputs = [
        obj for obj in bpy.data.objects
        if obj.get("asset_id") == ASSET_ID and "输出根节点" in obj.name
    ]
    for root in old_outputs:
        remove_tree(root)
    collection = bpy.data.collections.new("02_游戏输出_阁楼平台_v003")
    bpy.context.scene.collection.children.link(collection)
    output_root = bpy.data.objects.new("%s_输出根节点_%s" % (ASSET_ID, VERSION), None)
    collection.objects.link(output_root)
    output_root.matrix_world = source_root.matrix_world.copy()
    body_objects: list[bpy.types.Object] = []
    emissive_objects: list[bpy.types.Object] = []
    for source in source_root.children:
        if source.type != "MESH":
            continue
        duplicate = duplicate_for_output(source, output_root, collection)
        material_names = [material.name for material in duplicate.data.materials if material is not None]
        if any("自发光" in material_name for material_name in material_names):
            emissive_objects.append(duplicate)
        else:
            body_objects.append(duplicate)
    body = join_group(body_objects, "二层楼板_主体_金属哑光反光")
    emissive = join_group(emissive_objects, "二层楼板_UI灯光_柔和自发光")
    body.parent = output_root
    emissive.parent = output_root
    for obj in (body, emissive):
        obj["palette_uv_contract"] = "PaletteUV"
    return output_root


def triangulate(obj: bpy.types.Object) -> None:
    mesh = bmesh.new()
    mesh.from_mesh(obj.data)
    bmesh.ops.triangulate(mesh, faces=list(mesh.faces))
    mesh.to_mesh(obj.data)
    mesh.free()
    obj.data.update()


def export_glb(root: bpy.types.Object) -> None:
    original_location = root.location.copy()
    try:
        root.location = Vector((0.0, 0.0, 0.0))
        for obj in descendants(root):
            if obj.type == "MESH":
                triangulate(obj)
        bpy.context.view_layer.update()
        bpy.ops.object.select_all(action="DESELECT")
        root.select_set(True)
        for child in descendants(root):
            child.select_set(True)
        bpy.context.view_layer.objects.active = root
        OUTPUT_GLB.parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.export_scene.gltf(
            filepath=str(OUTPUT_GLB), export_format="GLB", use_selection=True,
            export_yup=True, export_apply=True, export_texcoords=True,
            export_normals=True, export_tangents=True, export_materials="EXPORT",
            export_image_format="NONE",
            export_extras=True, export_cameras=False, export_lights=False,
            export_animations=False,
        )
    finally:
        root.location = original_location
        bpy.context.view_layer.update()


def render_preview(root: bpy.types.Object) -> None:
    original_visibility = {obj: obj.hide_render for obj in bpy.context.scene.objects}
    for obj in bpy.context.scene.objects:
        obj.hide_render = True
    for obj in descendants(root):
        obj.hide_render = False
    camera_data = bpy.data.cameras.new("阁楼平台v003验收相机")
    camera = bpy.data.objects.new("阁楼平台v003验收相机", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.hide_render = False
    minimum, maximum = root_bounds(root)
    center = (minimum + maximum) * 0.5
    camera.location = center + Vector((16.0, -22.0, 13.0))
    camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = 58.0
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.studio_light = "paint.sl"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.display.shading.cavity_type = "BOTH"
    scene.display.shading.background_type = "VIEWPORT"
    scene.display.shading.background_color = (0.018, 0.028, 0.052)
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(PREVIEW)
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(camera, do_unlink=True)
    bpy.data.cameras.remove(camera_data)
    for obj, hidden in original_visibility.items():
        if obj.name in bpy.data.objects:
            obj.hide_render = hidden


if Path(bpy.data.filepath).resolve() != INPUT_BLEND.resolve():
    raise RuntimeError("Open the current editable pack first: %s" % INPUT_BLEND)

source_root = next(
    obj for obj in bpy.data.objects
    if obj.get("asset_id") == ASSET_ID and "制作根节点" in obj.name
)
slab = next(obj for obj in source_root.children if "整体承重框" in obj.name)
old_minimum, old_maximum, new_minimum, new_maximum = remap_deck_skin(source_root, slab)
source_root.name = "%s_制作根节点_%s" % (ASSET_ID, VERSION)
source_root["asset_version"] = VERSION
source_root["revision_reason"] = "remove_coplanar_full_slab_and_edge_beam_faces"
source_root["deck_skin_contract"] = "inset_0.15m; z4.78_to_4.90; edge_beams_remain_authored"
source_root.hide_set(True)
source_root.hide_render = True

output_root = rebuild_output(source_root)
for root in (source_root, output_root):
    root["asset_id"] = ASSET_ID
    root["asset_version"] = VERSION
    root["logic_id"] = "base99_mezzanine_20x10_z5"
    root["revision_reason"] = "remove_coplanar_full_slab_and_edge_beam_faces"
    root["coplanar_edge_face_count"] = 0
    root["source_blend_revision"] = "env_base99_modular_room_assets_clean_v005"

bpy.context.view_layer.update()
minimum, maximum = root_bounds(output_root)
output_root["local_bounds_min"] = list(minimum)
output_root["local_bounds_max"] = list(maximum)
output_root["local_dimensions"] = list(maximum - minimum)
export_glb(output_root)
render_preview(output_root)

manifest = {
    "asset_id": ASSET_ID,
    "display_name": "基地99层二层楼中楼楼板20x10米Z5",
    "version": VERSION,
    "input_blend": INPUT_BLEND.relative_to(PROJECT_ROOT).as_posix(),
    "source": OUTPUT_BLEND.relative_to(PROJECT_ROOT).as_posix(),
    "glb": OUTPUT_GLB.relative_to(PROJECT_ROOT).as_posix(),
    "preview": PREVIEW.relative_to(PROJECT_ROOT).as_posix(),
    "deck_skin_bounds_before": [list(old_minimum), list(old_maximum)],
    "deck_skin_bounds_after": [list(new_minimum), list(new_maximum)],
    "visual_bounds_min": [round(value, 5) for value in minimum],
    "visual_bounds_max": [round(value, 5) for value in maximum],
    "coplanar_edge_face_count": 0,
    "collision": "Godot PackedScene retains continuous deck and independent guards",
    "status": "approved_runtime",
}
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND), compress=True)
manifest["source_sha256"] = hashlib.sha256(OUTPUT_BLEND.read_bytes()).hexdigest()
manifest["glb_sha256"] = hashlib.sha256(OUTPUT_GLB.read_bytes()).hexdigest()
MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
print("BASE99_MEZZANINE_PLATFORM_V003_BLEND_WRITTEN:%s" % OUTPUT_BLEND)
print("BASE99_MEZZANINE_PLATFORM_V003_GLB_WRITTEN:%s" % OUTPUT_GLB)
print("BASE99_MEZZANINE_PLATFORM_V003_PREVIEW_WRITTEN:%s" % PREVIEW)
