import argparse
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_facility_volume_v2 import (
    bounds,
    build_integrated_output,
    clear_output_collection,
    organize_collections,
    purge_unused_materials,
    render_preview,
)


ASSETS = {
    "locker": "赛博储物站",
    "retro_tv": "复古游戏电视站",
}


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--asset", choices=ASSETS, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--preview", type=Path, required=True)
    parser.add_argument("--target-width", type=float, default=5.0)
    return parser.parse_args(bpy.app.driver_namespace.get("argv", []))


def root_objects(collection):
    members = set(collection.all_objects)
    return [obj for obj in members if obj.parent not in members]


def add_uniform_scale_controller(source, factor):
    controller = bpy.data.objects.new("比例控制_5米模数", None)
    source.objects.link(controller)
    roots = [obj for obj in root_objects(source) if obj != controller]
    for obj in roots:
        world_matrix = obj.matrix_world.copy()
        obj.parent = controller
        obj.matrix_world = world_matrix
    controller.scale = (factor, factor, factor)
    bpy.context.view_layer.update()
    return controller


def center_and_ground_controller(controller, mesh_objects):
    minimum, maximum = bounds(mesh_objects)
    controller.location += Vector(
        (-(minimum.x + maximum.x) * 0.5, -(minimum.y + maximum.y) * 0.5, -minimum.z)
    )
    bpy.context.view_layer.update()


def main(arguments):
    asset_name = ASSETS[arguments.asset]
    source = bpy.data.collections.get("01_制作组件_已统一材质")
    if source is None:
        raise RuntimeError("缺少 01_制作组件_已统一材质 集合")
    source.hide_viewport = False
    source.hide_render = False
    mesh_objects = [obj for obj in source.all_objects if obj.type == "MESH"]
    if not mesh_objects:
        raise RuntimeError("源文件中没有可处理的网格对象")

    before_minimum, before_maximum = bounds(mesh_objects)
    before_size = before_maximum - before_minimum
    factor = arguments.target_width / before_size.x
    controller = add_uniform_scale_controller(source, factor)
    mesh_objects = [obj for obj in source.all_objects if obj.type == "MESH"]
    center_and_ground_controller(controller, mesh_objects)

    output = clear_output_collection()
    output_objects = build_integrated_output(mesh_objects, output, asset_name)
    organize_collections(source, output, asset_name)
    purge_unused_materials()

    final_minimum, final_maximum = bounds(output_objects)
    final_size = final_maximum - final_minimum
    scene = bpy.context.scene
    scene["asset_name_cn"] = asset_name
    scene["asset_revision"] = "proportional_volume_v002"
    scene["asset_forward_axis"] = "Godot local -Z"
    scene["palette_revision"] = "dopamine_dark_v002"
    scene["target_module_width_m"] = arguments.target_width
    scene["uniform_scale_factor"] = round(factor, 6)
    scene["source_width_before_m"] = round(before_size.x, 4)
    scene["source_depth_before_m"] = round(before_size.y, 4)
    scene["source_height_before_m"] = round(before_size.z, 4)
    scene["facility_width_m"] = round(final_size.x, 4)
    scene["facility_depth_m"] = round(final_size.y, 4)
    scene["facility_height_m"] = round(final_size.z, 4)
    scene["proportion_policy"] = "整体等比例缩放，附件与主体保持原始相对比例"
    scene["chair_embedded"] = False

    bpy.ops.file.pack_all()
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(arguments.output), compress=True)
    render_preview(output_objects, arguments.preview)
    print(
        "BUILT",
        asset_name,
        "SCALE",
        round(factor, 6),
        "BEFORE",
        tuple(round(value, 4) for value in before_size),
        "AFTER",
        tuple(round(value, 4) for value in final_size),
    )


if __name__ == "__main__":
    separator = sys.argv.index("--") if "--" in sys.argv else len(sys.argv)
    bpy.app.driver_namespace["argv"] = sys.argv[separator + 1 :]
    main(parse_args())
