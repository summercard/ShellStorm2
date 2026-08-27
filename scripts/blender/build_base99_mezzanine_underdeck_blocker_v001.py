"""Build the independent Base99 mezzanine underdeck warehouse blocker.

The visible enclosure is intentionally inset from the mezzanine steel frame.
Godot owns its solid collision volume so the visual asset remains replaceable.
"""

from __future__ import annotations

import json
from pathlib import Path

import bpy
from mathutils import Vector


PROJECT_ROOT = Path(__file__).resolve().parents[2]
ASSET_ROOT = PROJECT_ROOT / "assets/art/environments/base_facility_3d"
ASSET_SLUG = "env_base99_mezzanine_underdeck_blocker"
ASSET_ID = "ENV-BASE99-MEZZANINE-UNDERDECK-BLOCKER"
VERSION = "v001"
SOURCE_DIR = ASSET_ROOT / "source" / ASSET_SLUG
OUTPUT_BLEND = SOURCE_DIR / f"{ASSET_SLUG}_source_{VERSION}.blend"
OUTPUT_GLB = (
    ASSET_ROOT / "components" / ASSET_SLUG
    / f"{ASSET_SLUG}_visual_top3d_{VERSION}.glb"
)
PREVIEW = SOURCE_DIR / "previews" / f"{ASSET_SLUG}_preview.png"
MANIFEST = SOURCE_DIR / f"{ASSET_SLUG}_manifest_{VERSION}.json"
PALETTE_PATH = (
    ASSET_ROOT / "source/env_base99_modular_room/textures/多巴胺色盘_10x10_512.png"
)

INSET_M = 0.55
OUTER_HALF_WIDTH_M = 10.0
OUTER_HALF_DEPTH_M = 5.0
PANEL_HEIGHT_M = 4.65
PANEL_THICKNESS_M = 0.28
PANEL_HALF_WIDTH_M = OUTER_HALF_WIDTH_M - INSET_M
PANEL_HALF_DEPTH_M = OUTER_HALF_DEPTH_M - INSET_M


def ensure_collection(name: str, parent: bpy.types.Collection | None = None) -> bpy.types.Collection:
    collection = bpy.data.collections.new(name)
    (parent.children if parent else bpy.context.scene.collection.children).link(collection)
    return collection


def project_relative(path: Path) -> str:
    return path.relative_to(PROJECT_ROOT).as_posix()


def palette_material(name: str, metallic: float, roughness: float, uv_cell: tuple[int, int]) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    uv_map = nodes.new("ShaderNodeUVMap")
    uv_map.uv_map = "PaletteUV"
    image = nodes.new("ShaderNodeTexImage")
    image.image = bpy.data.images.load(str(PALETTE_PATH), check_existing=True)
    image.interpolation = "Closest"
    links.new(uv_map.outputs["UV"], image.inputs["Vector"])
    links.new(image.outputs["Color"], shader.inputs["Base Color"])
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    material["palette_cell"] = list(uv_cell)
    material["palette_uv"] = "PaletteUV"
    return material


def assign_palette_uv(obj: bpy.types.Object, cell: tuple[int, int]) -> None:
    while obj.data.uv_layers:
        obj.data.uv_layers.remove(obj.data.uv_layers[0])
    uv = obj.data.uv_layers.new(name="PaletteUV")
    obj.data.uv_layers.active = uv
    uv.active_render = True
    column, row = cell
    left = (column + 0.22) / 10.0
    bottom = (row + 0.22) / 10.0
    right = (column + 0.78) / 10.0
    top = (row + 0.78) / 10.0
    corners = ((left, bottom), (right, bottom), (right, top), (left, top))
    for polygon in obj.data.polygons:
        for offset, loop_index in enumerate(polygon.loop_indices):
            uv.data[loop_index].uv = corners[offset % 4]


def add_box(
    collection: bpy.types.Collection,
    parent: bpy.types.Object,
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    material: bpy.types.Material,
    uv_cell: tuple[int, int],
    bevel: float = 0.0,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.active_object
    for linked_collection in list(obj.users_collection):
        linked_collection.objects.unlink(obj)
    collection.objects.link(obj)
    obj.name = name
    obj.parent = parent
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    if bevel > 0.0:
        modifier = obj.modifiers.new("边缘倒角", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    assign_palette_uv(obj, uv_cell)
    return obj


def build_panel(
    collection: bpy.types.Collection,
    root: bpy.types.Object,
    panel_name: str,
    center: Vector,
    width: float,
    horizontal_axis: str,
    metal: bpy.types.Material,
    matte: bpy.types.Material,
    accent: bpy.types.Material,
) -> None:
    """Create a framed corrugated warehouse panel with dimensions in local XY."""
    is_x_span = horizontal_axis == "X"
    longitudinal = Vector((1.0, 0.0, 0.0)) if is_x_span else Vector((0.0, 1.0, 0.0))
    depth_axis = Vector((0.0, 1.0, 0.0)) if is_x_span else Vector((1.0, 0.0, 0.0))
    frame_depth = PANEL_THICKNESS_M + 0.12
    main_dims = (width, PANEL_THICKNESS_M, PANEL_HEIGHT_M) if is_x_span else (PANEL_THICKNESS_M, width, PANEL_HEIGHT_M)
    add_box(collection, root, panel_name + "_仓库板", tuple(center), main_dims, matte, (2, 5), 0.035)

    for edge, height in ((-1.0, PANEL_HEIGHT_M * 0.5), (1.0, PANEL_HEIGHT_M * 0.5)):
        frame_center = center + longitudinal * (edge * (width * 0.5 - 0.12))
        dims = (0.18, frame_depth, PANEL_HEIGHT_M) if is_x_span else (frame_depth, 0.18, PANEL_HEIGHT_M)
        add_box(collection, root, panel_name + "_立柱", tuple(frame_center), dims, metal, (6, 2), 0.025)

    for z in (0.18, PANEL_HEIGHT_M - 0.18):
        frame_center = center + Vector((0.0, 0.0, z - PANEL_HEIGHT_M * 0.5))
        dims = (width, frame_depth, 0.16) if is_x_span else (frame_depth, width, 0.16)
        add_box(collection, root, panel_name + "_横梁", tuple(frame_center), dims, metal, (6, 2), 0.025)

    rib_count = max(8, int(width / 0.72))
    for index in range(rib_count):
        ratio = (index + 0.5) / rib_count - 0.5
        rib_center = center + longitudinal * (ratio * (width - 0.42)) - depth_axis * 0.17
        dims = (0.075, 0.08, PANEL_HEIGHT_M - 0.46) if is_x_span else (0.08, 0.075, PANEL_HEIGHT_M - 0.46)
        add_box(collection, root, panel_name + "_波纹竖筋", tuple(rib_center), dims, metal, (6, 2), 0.015)

    # The reflective safety band adds a warehouse cue without crossing the
    # panel's declared vertical envelope or touching the outer steel frame.
    band_center = center + Vector((0.0, 0.0, PANEL_HEIGHT_M * 0.12))
    add_box(
        collection, root, panel_name + "_反光识别带", tuple(band_center),
        (width - 0.64, 0.09, 0.10) if is_x_span else (0.09, width - 0.64, 0.10),
        accent, (8, 3), 0.012,
    )


def duplicate_output(source_objects: list[bpy.types.Object], output_collection: bpy.types.Collection, output_root: bpy.types.Object) -> bpy.types.Object:
    copies: list[bpy.types.Object] = []
    for source in source_objects:
        duplicate = source.copy()
        duplicate.data = source.data.copy()
        output_collection.objects.link(duplicate)
        duplicate.parent = output_root
        duplicate.matrix_local = source.matrix_local.copy()
        duplicate.hide_viewport = False
        duplicate.hide_render = False
        copies.append(duplicate)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in copies:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = copies[0]
    bpy.ops.object.join()
    body = bpy.context.active_object
    body.name = "仓库挡板_主体_金属哑光反光"
    bpy.ops.object.material_slot_remove_unused()
    return body


def mesh_bounds(root: bpy.types.Object) -> tuple[Vector, Vector]:
    points: list[Vector] = []
    inverse = root.matrix_world.inverted()
    for child in root.children:
        if child.type != "MESH":
            continue
        points.extend(inverse @ child.matrix_world @ vertex.co for vertex in child.data.vertices)
    minimum = Vector(tuple(min(point[index] for point in points) for index in range(3)))
    maximum = Vector(tuple(max(point[index] for point in points) for index in range(3)))
    return minimum, maximum


def render_preview(root: bpy.types.Object) -> None:
    preview_collection = ensure_collection("90_展示环境_灯光相机")
    bpy.ops.mesh.primitive_plane_add(size=42, location=(0.0, 0.0, 0.0))
    floor = bpy.context.active_object
    for linked_collection in list(floor.users_collection):
        linked_collection.objects.unlink(floor)
    preview_collection.objects.link(floor)
    floor.name = "DISPLAY_Ground_preview_only"
    floor.hide_render = False
    floor_mat = bpy.data.materials.new("展示地面_预览专用")
    floor_mat.diffuse_color = (0.025, 0.05, 0.08, 1.0)
    floor.data.materials.append(floor_mat)
    camera_data = bpy.data.cameras.new("挡板预览相机")
    camera = bpy.data.objects.new("挡板预览相机", camera_data)
    preview_collection.objects.link(camera)
    camera.location = (13.5, -17.5, 10.5)
    direction = Vector((0.0, 0.0, 2.3)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera
    for location, energy, color in (
        ((-8.0, -10.0, 11.0), 1350.0, (0.36, 0.72, 1.0)),
        ((10.0, -2.0, 8.0), 950.0, (0.93, 0.28, 0.92)),
        ((0.0, 8.0, 5.0), 650.0, (0.4, 0.95, 0.82)),
    ):
        light_data = bpy.data.lights.new("挡板预览灯", "AREA")
        light_data.energy = energy
        light_data.color = color
        light_data.shape = "DISK"
        light_data.size = 6.0
        light = bpy.data.objects.new("挡板预览灯", light_data)
        preview_collection.objects.link(light)
        light.location = location
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(PREVIEW)
    scene.render.film_transparent = False
    scene.world.color = (0.008, 0.016, 0.03)
    bpy.ops.render.render(write_still=True)
    for obj in list(preview_collection.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(preview_collection)


def export_glb(output_root: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    output_root.select_set(True)
    for child in output_root.children:
        child.select_set(True)
    bpy.context.view_layer.objects.active = output_root
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT_GLB), export_format="GLB", use_selection=True,
        export_yup=True, export_apply=True, export_texcoords=True,
        export_normals=True, export_tangents=True, export_materials="EXPORT",
        export_extras=True, export_cameras=False, export_lights=False,
        export_animations=False,
    )


def main() -> None:
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_GLB.parent.mkdir(parents=True, exist_ok=True)
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    if not PALETTE_PATH.exists():
        raise RuntimeError("Missing required palette: %s" % PALETTE_PATH)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        bpy.data.collections.remove(collection)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    asset_collection = ensure_collection("基地99层_楼中楼下方工业仓库挡板_中文资产管理")
    source_collection = ensure_collection("01_制作组件_已统一材质", asset_collection)
    output_collection = ensure_collection("02_游戏输出_整合模型", asset_collection)
    metal = palette_material("01_精工金属_紫色骨架", 0.88, 0.27, (6, 2))
    matte = palette_material("02_细腻哑光_青绿大面", 0.02, 0.70, (2, 5))
    accent = palette_material("03_清漆反光_紫粉点缀", 0.18, 0.14, (8, 3))

    source_root = bpy.data.objects.new("ENV-BASE99-MEZZANINE-UNDERDECK-BLOCKER_制作根节点_v001", None)
    source_collection.objects.link(source_root)
    source_root["asset_id"] = ASSET_ID
    source_root["logic_id"] = "base99_mezzanine_underdeck_blocker"
    source_root["module_local_origin"] = "xy_center_bottom_z0"
    source_root["frame_inset_m"] = INSET_M
    source_root["front_axis"] = "-Y"
    # Three inset faces close the reachable underside; the north side is the base exterior wall.
    build_panel(source_collection, source_root, "南侧挡板", Vector((0.0, -PANEL_HALF_DEPTH_M, PANEL_HEIGHT_M * 0.5)), 19.0, "X", metal, matte, accent)
    build_panel(source_collection, source_root, "西侧挡板", Vector((-PANEL_HALF_WIDTH_M, 0.0, PANEL_HEIGHT_M * 0.5)), 8.9, "Y", metal, matte, accent)
    build_panel(source_collection, source_root, "东侧挡板", Vector((PANEL_HALF_WIDTH_M, 0.0, PANEL_HEIGHT_M * 0.5)), 8.9, "Y", metal, matte, accent)
    source_root.hide_set(True)
    source_root.hide_render = True

    output_root = bpy.data.objects.new("ENV-BASE99-MEZZANINE-UNDERDECK-BLOCKER_输出根节点_v001", None)
    output_collection.objects.link(output_root)
    output_root["asset_id"] = ASSET_ID
    output_root["logic_id"] = "base99_mezzanine_underdeck_blocker"
    output_root["module_local_origin"] = "xy_center_bottom_z0"
    output_root["blender_forward"] = "-Y"
    output_root["godot_forward"] = "-Z"
    output_root["frame_inset_m"] = INSET_M
    output_root["collision_owner"] = "Godot PackedScene"
    output_root["collision_contract"] = "permanent_underdeck_perimeter_blockers"
    body = duplicate_output(list(source_root.children), output_collection, output_root)
    body["palette_uv_contract"] = "PaletteUV"
    body["semantic_role"] = "underdeck_industrial_warehouse_blocker"
    minimum, maximum = mesh_bounds(output_root)
    output_root["local_bounds_min"] = list(minimum)
    output_root["local_bounds_max"] = list(maximum)
    output_root["local_dimensions"] = list(maximum - minimum)

    render_preview(output_root)
    export_glb(output_root)
    allowed_materials = {metal.name, matte.name, accent.name}
    for material in list(bpy.data.materials):
        if material.name not in allowed_materials:
            material.use_fake_user = False
            bpy.data.materials.remove(material)
    manifest = {
        "asset_id": ASSET_ID,
        "display_name": "基地99层楼中楼下方工业仓库挡板",
        "version": VERSION,
        "source": project_relative(OUTPUT_BLEND),
        "glb": project_relative(OUTPUT_GLB),
        "preview": project_relative(PREVIEW),
        "origin": "xy_center_bottom_z0",
        "forward": "Blender -Y / Godot -Z",
        "frame_inset_m": INSET_M,
        "visual_bounds_min": [round(value, 5) for value in minimum],
        "visual_bounds_max": [round(value, 5) for value in maximum],
        "materials": [metal.name, matte.name, accent.name],
        "collision": "Godot PackedScene owns permanent perimeter blockers",
        "usage": "Base99 mezzanine underside enclosure; no interaction",
    }
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND), compress=True)
    print("BASE99_UNDERDECK_BLOCKER_BLEND_WRITTEN:%s" % OUTPUT_BLEND)
    print("BASE99_UNDERDECK_BLOCKER_GLB_WRITTEN:%s" % OUTPUT_GLB)
    print("BASE99_UNDERDECK_BLOCKER_PREVIEW_WRITTEN:%s" % PREVIEW)


if __name__ == "__main__":
    main()
