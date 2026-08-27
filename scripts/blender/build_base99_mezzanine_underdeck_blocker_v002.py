"""Build v002 of the Base99 mezzanine underdeck warehouse blocker.

This visual revision replaces the former vertical corrugation with grey,
horizontal warehouse cladding and regularly spaced upright steel supports.
Collision remains in the Godot wrapper, so every face stays permanently solid.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path

import bpy
from mathutils import Vector


LEGACY_PATH = Path(__file__).with_name("build_base99_mezzanine_underdeck_blocker_v001.py")
SPEC = importlib.util.spec_from_file_location("base99_underdeck_v001", LEGACY_PATH)
assert SPEC is not None and SPEC.loader is not None
base = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(base)

VERSION = "v002"
base.VERSION = VERSION
base.OUTPUT_BLEND = base.SOURCE_DIR / f"{base.ASSET_SLUG}_source_{VERSION}.blend"
base.OUTPUT_GLB = (
    base.ASSET_ROOT / "components" / base.ASSET_SLUG
    / f"{base.ASSET_SLUG}_visual_top3d_{VERSION}.glb"
)
base.PREVIEW = base.SOURCE_DIR / "previews" / f"{base.ASSET_SLUG}_preview_{VERSION}.png"
base.MANIFEST = base.SOURCE_DIR / f"{base.ASSET_SLUG}_manifest_{VERSION}.json"

GREY_MATERIALS = {
    "01_精工金属_冷灰骨架": (0.88, 0.27, (9, 2)),
    "02_细腻哑光_中灰横向板": (0.02, 0.70, (9, 5)),
    "03_清漆反光_浅灰边条": (0.18, 0.14, (9, 8)),
}


def palette_material(_: str, metallic: float, roughness: float, uv_cell: tuple[int, int]) -> bpy.types.Material:
    """Keep the three established material roles while fixing all colors to grey."""
    for name, (expected_metallic, expected_roughness, cell) in GREY_MATERIALS.items():
        if abs(metallic - expected_metallic) < 0.001 and abs(roughness - expected_roughness) < 0.001:
            return original_palette_material(name, metallic, roughness, cell)
    raise RuntimeError("Unexpected Base99 blocker material role: %s" % (uv_cell,))


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
    """Create inset horizontal cladding with visible upright warehouse framing."""
    if root.name.endswith("v001"):
        root.name = root.name[:-4] + VERSION
    is_x_span = horizontal_axis == "X"
    longitudinal = Vector((1.0, 0.0, 0.0)) if is_x_span else Vector((0.0, 1.0, 0.0))
    frame_depth = base.PANEL_THICKNESS_M + 0.12
    inner_span = width - 0.42
    bottom_clearance = 0.22
    top_clearance = 0.22
    slat_count = 7
    gap = 0.065
    slat_height = (base.PANEL_HEIGHT_M - bottom_clearance - top_clearance - gap * (slat_count - 1)) / slat_count

    # Separate horizontal planks make the intended warehouse-cladding direction
    # legible at a distance, without the former dense vertical corrugation.
    for index in range(slat_count):
        z = bottom_clearance + slat_height * 0.5 + index * (slat_height + gap)
        slat_center = center + Vector((0.0, 0.0, z - base.PANEL_HEIGHT_M * 0.5))
        dims = (inner_span, base.PANEL_THICKNESS_M, slat_height) if is_x_span else (base.PANEL_THICKNESS_M, inner_span, slat_height)
        base.add_box(collection, root, panel_name + "_横向仓库板", tuple(slat_center), dims, matte, (9, 5), 0.025)

    # End posts plus regularly spaced uprights form the visible rack structure.
    post_count = max(3, int(width / 2.4) + 1)
    for index in range(post_count):
        ratio = index / (post_count - 1) - 0.5
        post_center = center + longitudinal * (ratio * (width - 0.20))
        dims = (0.18, frame_depth, base.PANEL_HEIGHT_M) if is_x_span else (frame_depth, 0.18, base.PANEL_HEIGHT_M)
        base.add_box(collection, root, panel_name + "_竖向钢架", tuple(post_center), dims, metal, (9, 2), 0.025)

    for z in (0.16, base.PANEL_HEIGHT_M - 0.16):
        beam_center = center + Vector((0.0, 0.0, z - base.PANEL_HEIGHT_M * 0.5))
        dims = (width, frame_depth, 0.16) if is_x_span else (frame_depth, width, 0.16)
        base.add_box(collection, root, panel_name + "_横向边梁", tuple(beam_center), dims, metal, (9, 2), 0.025)

    for index in range(slat_count - 1):
        z = bottom_clearance + (index + 1) * slat_height + (index + 0.5) * gap
        seam_center = center + Vector((0.0, 0.0, z - base.PANEL_HEIGHT_M * 0.5))
        dims = (inner_span, frame_depth + 0.015, 0.045) if is_x_span else (frame_depth + 0.015, inner_span, 0.045)
        base.add_box(collection, root, panel_name + "_横向分隔条", tuple(seam_center), dims, accent, (9, 8), 0.010)


def duplicate_output(
    source_objects: list[bpy.types.Object],
    output_collection: bpy.types.Collection,
    output_root: bpy.types.Object,
) -> bpy.types.Object:
    output_root.name = "ENV-BASE99-MEZZANINE-UNDERDECK-BLOCKER_输出根节点_" + VERSION
    return original_duplicate_output(source_objects, output_collection, output_root)


def render_preview(root: bpy.types.Object) -> None:
    """Render a neutral, cool-grey preview that cannot tint the asset green."""
    preview_collection = base.ensure_collection("90_展示环境_灯光相机")
    bpy.ops.mesh.primitive_plane_add(size=42, location=(0.0, 0.0, 0.0))
    floor = bpy.context.active_object
    for linked_collection in list(floor.users_collection):
        linked_collection.objects.unlink(floor)
    preview_collection.objects.link(floor)
    floor.name = "DISPLAY_Ground_preview_only"
    floor_mat = bpy.data.materials.new("展示地面_预览专用")
    floor_mat.diffuse_color = (0.045, 0.060, 0.085, 1.0)
    floor.data.materials.append(floor_mat)
    camera_data = bpy.data.cameras.new("挡板预览相机")
    camera = bpy.data.objects.new("挡板预览相机", camera_data)
    preview_collection.objects.link(camera)
    camera.location = (13.5, -17.5, 10.5)
    camera.rotation_euler = (Vector((0.0, 0.0, 2.3)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera
    for location, energy, color in (
        ((-8.0, -10.0, 11.0), 1350.0, (0.62, 0.72, 1.0)),
        ((10.0, -2.0, 8.0), 950.0, (0.95, 0.92, 1.0)),
        ((0.0, 8.0, 5.0), 650.0, (0.72, 0.78, 0.92)),
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
    scene.render.filepath = str(base.PREVIEW)
    scene.world.color = (0.008, 0.016, 0.030)
    bpy.ops.render.render(write_still=True)
    for obj in list(preview_collection.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(preview_collection)


original_palette_material = base.palette_material
original_duplicate_output = base.duplicate_output
base.palette_material = palette_material
base.build_panel = build_panel
base.duplicate_output = duplicate_output
base.render_preview = render_preview


if __name__ == "__main__":
    base.main()
