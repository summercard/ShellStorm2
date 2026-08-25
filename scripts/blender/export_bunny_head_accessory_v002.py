"""Export the authored chibi head from the formal Bunny character Blend."""

from pathlib import Path
import json

import bpy
from mathutils import Vector


PROJECT_ROOT = Path(__file__).resolve().parents[2]
CHARACTER_BLEND = (
    PROJECT_ROOT
    / "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/source"
    / "chr_player_capsule01_bunny01_top3d_v008.blend"
)
ASSET_ROOT = (
    PROJECT_ROOT
    / "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01"
    / "accessories/head/chibi_anime_head_v002"
)
RUNTIME_DIR = ASSET_ROOT / "runtime"
OUTPUT_GLB = RUNTIME_DIR / "chr_player_bunny01_head_chibi_anime_top3d_v002.glb"

TOP_COLLECTION = "头部配件"
ASSET_COLLECTION = "二次元头部配件_中文管理"
SOURCE_COLLECTION = "01_制作组件_可编辑"
OUTPUT_COLLECTION = "02_游戏输出_头部配件"
SOURCE_OBJECT = "制作组件_二次元头部_已对齐"
ANCHOR_OBJECT = "PIVOT_HEAD"
OUTPUT_OBJECT = "EXPORT_chr_player_bunny01_head_chibi_anime_top3d_v002_00"


def require_collection_path(names: tuple[str, ...]) -> bpy.types.Collection:
    current = bpy.context.scene.collection
    for name in names:
        current = current.children.get(name)
        if current is None:
            raise RuntimeError("Missing collection path: " + "/".join(names))
    return current


def local_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    points = [Vector(corner) for corner in obj.bound_box]
    minimum = Vector(tuple(min(point[index] for point in points) for index in range(3)))
    maximum = Vector(tuple(max(point[index] for point in points) for index in range(3)))
    return minimum, maximum


def validate_source() -> tuple[bpy.types.Object, bpy.types.Object, bpy.types.Collection]:
    opened = Path(bpy.data.filepath).resolve()
    if opened != CHARACTER_BLEND.resolve():
        raise RuntimeError(f"Expected formal character Blend {CHARACTER_BLEND}, got {opened}")

    source_collection = require_collection_path(
        (TOP_COLLECTION, ASSET_COLLECTION, SOURCE_COLLECTION)
    )
    output_collection = require_collection_path(
        (TOP_COLLECTION, ASSET_COLLECTION, OUTPUT_COLLECTION)
    )
    source = bpy.data.objects.get(SOURCE_OBJECT)
    anchor = bpy.data.objects.get(ANCHOR_OBJECT)
    if source is None or source.type != "MESH":
        raise RuntimeError(f"Missing mesh source object: {SOURCE_OBJECT}")
    if source.name not in source_collection.objects:
        raise RuntimeError(f"{SOURCE_OBJECT} is not directly owned by {SOURCE_COLLECTION}")
    if anchor is None:
        raise RuntimeError(f"Missing formal attachment anchor: {ANCHOR_OBJECT}")
    if not source.data.materials:
        raise RuntimeError("Source head has no material")
    return source, anchor, output_collection


def replace_output(
    source: bpy.types.Object,
    anchor: bpy.types.Object,
    output_collection: bpy.types.Collection,
) -> bpy.types.Object:
    previous = bpy.data.objects.get(OUTPUT_OBJECT)
    if previous is not None:
        bpy.data.objects.remove(previous, do_unlink=True)

    output = source.copy()
    output.data = source.data.copy()
    output.name = OUTPUT_OBJECT
    output.data.name = "MESH_chr_player_bunny01_head_chibi_anime_v002"
    output_collection.objects.link(output)

    # Reproduce exactly what is authored against the formal HeadJoint, while
    # keeping the exported attachment root at identity for Godot.
    relative_transform = anchor.matrix_world.inverted() @ source.matrix_world
    output.data.transform(relative_transform)
    output.parent = None
    output.location = (0.0, 0.0, 0.0)
    output.rotation_mode = "XYZ"
    output.rotation_euler = (0.0, 0.0, 0.0)
    output.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()
    output.hide_render = False
    output.hide_viewport = False
    output.hide_set(False)
    output["attachment_slot"] = "head"
    output["attachment_anchor"] = "VisualRoot/BunnyRig/HeadJoint"
    output["source_collection"] = (
        f"{TOP_COLLECTION}/{ASSET_COLLECTION}/{SOURCE_COLLECTION}"
    )
    output["source_object"] = SOURCE_OBJECT
    output["blender_forward"] = "-Y"
    output["godot_forward"] = "-Z"
    output["runtime_root_scale"] = 1.0
    return output


def export_glb(output: bpy.types.Object) -> None:
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    output.select_set(True)
    bpy.context.view_layer.objects.active = output
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT_GLB),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
    )


def main() -> None:
    source, anchor, output_collection = validate_source()
    output = replace_output(source, anchor, output_collection)
    minimum, maximum = local_bounds(output)
    dimensions = maximum - minimum
    export_glb(output)
    bpy.ops.wm.save_as_mainfile(filepath=str(CHARACTER_BLEND))
    payload = {
        "source_blend": str(CHARACTER_BLEND.relative_to(PROJECT_ROOT)).replace("\\", "/"),
        "source_collection": f"{TOP_COLLECTION}/{ASSET_COLLECTION}/{SOURCE_COLLECTION}",
        "source_object": SOURCE_OBJECT,
        "output_collection": f"{TOP_COLLECTION}/{ASSET_COLLECTION}/{OUTPUT_COLLECTION}",
        "output_glb": str(OUTPUT_GLB.relative_to(PROJECT_ROOT)).replace("\\", "/"),
        "bounds_min": list(minimum),
        "bounds_max": list(maximum),
        "dimensions": list(dimensions),
        "vertex_count": len(output.data.vertices),
        "polygon_count": len(output.data.polygons),
        "material_count": len(output.data.materials),
        "texture_images": sorted(
            image.name
            for material in output.data.materials
            if material is not None and material.use_nodes
            for node in material.node_tree.nodes
            if node.type == "TEX_IMAGE" and node.image is not None
            for image in [node.image]
        ),
    }
    print("BUNNY_HEAD_ACCESSORY_V002=" + json.dumps(payload, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
