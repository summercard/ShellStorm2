"""Build the chibi anime head as a HeadJoint-aligned Bunny accessory."""

from pathlib import Path
import json
import math

import bpy
from mathutils import Vector


PROJECT_ROOT = Path(__file__).resolve().parents[2]
ASSET_ROOT = (
    PROJECT_ROOT
    / "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01"
    / "accessories/head/chibi_anime_head_v001"
)
SOURCE_DIR = ASSET_ROOT / "source"
RUNTIME_DIR = ASSET_ROOT / "runtime"
PREVIEW_DIR = ASSET_ROOT / "previews"
RAW_FBX = SOURCE_DIR / "chr_player_bunny01_head_chibi_anime_raw_v001.fbx"
BASE_COLOR = SOURCE_DIR / "chr_player_bunny01_head_chibi_anime_basecolor_v001.jpg"
SOURCE_BLEND = SOURCE_DIR / "chr_player_bunny01_head_chibi_anime_source_v001.blend"
OUTPUT_GLB = RUNTIME_DIR / "chr_player_bunny01_head_chibi_anime_top3d_v001.glb"
REFERENCE_HEAD = (
    PROJECT_ROOT
    / "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components"
    / "chr_player_capsule01_bunny01_head_top3d_v006.glb"
)

TARGET_HEIGHT_M = 0.8454768001638794
CORRECTION_ROTATION_DEGREES = 90.0
OUTPUT_NAME = "EXPORT_chr_player_bunny01_head_chibi_anime_top3d_v001_00"


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        bpy.data.collections.remove(collection)


def make_collection(name: str, parent: bpy.types.Collection) -> bpy.types.Collection:
    collection = bpy.data.collections.new(name)
    parent.children.link(collection)
    return collection


def move_to_collection(obj: bpy.types.Object, collection: bpy.types.Collection) -> None:
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    collection.objects.link(obj)


def mesh_bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    minimum = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    maximum = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return minimum, maximum


def import_source(collection: bpy.types.Collection) -> bpy.types.Object:
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.fbx(filepath=str(RAW_FBX))
    imported = [obj for obj in bpy.context.scene.objects if obj not in before]
    meshes = [obj for obj in imported if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError("FBX contains no mesh")
    for obj in imported:
        if obj.type != "MESH":
            bpy.data.objects.remove(obj, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = "制作组件_二次元头部_已对齐"
    obj.data.name = "MESH_二次元头部_v001"
    move_to_collection(obj, collection)

    # The supplied head faces +X, matching the Bunny raw source. Bake the
    # existing Bunny correction so the exported Blender forward is -Y.
    obj.rotation_euler.z = math.radians(CORRECTION_ROTATION_DEGREES)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)

    minimum, maximum = mesh_bounds([obj])
    scale_factor = TARGET_HEIGHT_M / (maximum.z - minimum.z)
    obj.scale = Vector((scale_factor, scale_factor, scale_factor))
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    minimum, maximum = mesh_bounds([obj])
    center = (minimum + maximum) * 0.5
    obj.location = Vector((-center.x, -center.y, -minimum.z))
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    obj.data.uv_layers.active.name = "UVMap"
    return obj


def build_material(obj: bpy.types.Object) -> bpy.types.Material:
    for image in list(bpy.data.images):
        if not image.has_data and image.name not in {"Render Result", "Viewer Node"}:
            bpy.data.images.remove(image)
    image = bpy.data.images.load(str(BASE_COLOR), check_existing=False)
    image.name = "TEX_chr_player_bunny01_head_chibi_anime_basecolor_v001"
    image.colorspace_settings.name = "sRGB"
    material = bpy.data.materials.new("MAT_chr_player_bunny01_head_chibi_anime_v001")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    texture.interpolation = "Linear"
    shader.inputs["Roughness"].default_value = 0.52
    shader.inputs["Metallic"].default_value = 0.0
    material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    material.node_tree.links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    obj.data.materials.clear()
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.material_index = 0
    return material


def add_reference(collection: bpy.types.Collection) -> None:
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(REFERENCE_HEAD))
    for obj in [value for value in bpy.context.scene.objects if value not in before]:
        move_to_collection(obj, collection)
        obj.name = "参考_原Bunny头部_" + obj.name
        obj.display_type = "WIRE"
        obj.hide_render = True
        obj.hide_set(True)


def export_glb(output: bpy.types.Object) -> None:
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    output.hide_set(False)
    output.hide_viewport = False
    output.select_set(True)
    bpy.context.view_layer.objects.active = output
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT_GLB),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_materials="EXPORT",
    )


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def render_previews(output: bpy.types.Object, display: bpy.types.Collection) -> None:
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    camera_data = bpy.data.cameras.new("预览相机")
    camera = bpy.data.objects.new("预览相机", camera_data)
    display.objects.link(camera)
    bpy.context.scene.camera = camera
    camera_data.lens = 62.0

    key_data = bpy.data.lights.new("主光", "AREA")
    key_data.energy = 650.0
    key_data.shape = "DISK"
    key_data.size = 2.2
    key = bpy.data.objects.new("主光", key_data)
    display.objects.link(key)
    key.location = Vector((-1.5, -1.8, 2.0))
    look_at(key, Vector((0.0, 0.0, TARGET_HEIGHT_M * 0.5)))

    fill_data = bpy.data.lights.new("补光", "AREA")
    fill_data.energy = 360.0
    fill_data.size = 1.8
    fill = bpy.data.objects.new("补光", fill_data)
    display.objects.link(fill)
    fill.location = Vector((1.4, 0.8, 1.2))
    look_at(fill, Vector((0.0, 0.0, TARGET_HEIGHT_M * 0.5)))

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world.color = (0.025, 0.03, 0.04)
    target = Vector((0.0, 0.0, TARGET_HEIGHT_M * 0.52))
    views = {
        "front": Vector((0.0, -1.85, TARGET_HEIGHT_M * 0.55)),
        "right": Vector((1.85, 0.0, TARGET_HEIGHT_M * 0.55)),
        "back": Vector((0.0, 1.85, TARGET_HEIGHT_M * 0.55)),
        "left": Vector((-1.85, 0.0, TARGET_HEIGHT_M * 0.55)),
    }
    output.hide_render = False
    for name, position in views.items():
        camera.location = position
        look_at(camera, target)
        scene.render.filepath = str(PREVIEW_DIR / f"chr_player_bunny01_head_chibi_anime_{name}_v001.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    clear_scene()
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    master = make_collection("二次元头部配件_中文管理", scene.collection)
    source_collection = make_collection("01_制作组件_可编辑", master)
    output_collection = make_collection("02_游戏输出_头部配件", master)
    reference_collection = make_collection("90_参考_原Bunny头部", master)
    display_collection = make_collection("91_预览灯光相机", master)

    source = import_source(source_collection)
    build_material(source)
    output = source.copy()
    output.data = source.data.copy()
    output.name = OUTPUT_NAME
    output.data.name = "MESH_chr_player_bunny01_head_chibi_anime_v001"
    output_collection.objects.link(output)
    source.hide_render = True
    source.hide_set(True)
    output["attachment_slot"] = "head"
    output["attachment_anchor"] = "VisualRoot/BunnyRig/HeadJoint"
    output["blender_forward"] = "-Y"
    output["godot_forward"] = "-Z"
    output["runtime_root_scale"] = 1.0
    output["target_authored_height_m"] = TARGET_HEIGHT_M

    anchor = bpy.data.objects.new("ANCHOR_HeadJoint_原点", None)
    reference_collection.objects.link(anchor)
    anchor.empty_display_type = "PLAIN_AXES"
    anchor.empty_display_size = 0.18
    add_reference(reference_collection)
    export_glb(output)
    render_previews(output, display_collection)

    bpy.ops.file.pack_all()
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_BLEND))
    minimum, maximum = mesh_bounds([output])
    payload = {
        "source_fbx": str(RAW_FBX.relative_to(PROJECT_ROOT)).replace("\\", "/"),
        "source_texture": str(BASE_COLOR.relative_to(PROJECT_ROOT)).replace("\\", "/"),
        "output_glb": str(OUTPUT_GLB.relative_to(PROJECT_ROOT)).replace("\\", "/"),
        "minimum": list(minimum),
        "maximum": list(maximum),
        "dimensions": list(maximum - minimum),
        "vertex_count": len(output.data.vertices),
        "polygon_count": len(output.data.polygons),
        "material_count": len(output.data.materials),
    }
    print("CHIBI_ANIME_HEAD_BUILD=" + json.dumps(payload, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
