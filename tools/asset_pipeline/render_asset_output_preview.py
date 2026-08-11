"""Render the standard 02_游戏输出 collection for visual acceptance."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def args() -> argparse.Namespace:
    values = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args(values)


def bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    corners = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    return Vector((min(v.x for v in corners), min(v.y for v in corners), min(v.z for v in corners))), Vector(
        (max(v.x for v in corners), max(v.y for v in corners), max(v.z for v in corners))
    )


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def main() -> None:
    options = args()
    collection = bpy.data.collections.get("02_游戏输出_整合模型")
    objects = [obj for obj in collection.all_objects if obj.type == "MESH"] if collection else []
    if not objects:
        raise RuntimeError("缺少标准游戏输出集合")
    for obj in objects:
        obj.hide_render = False
        obj.hide_set(False)
    minimum, maximum = bounds(objects)
    size = maximum - minimum
    center = (minimum + maximum) * 0.5
    preview = bpy.data.collections.new("临时验收灯光")
    bpy.context.scene.collection.children.link(preview)
    camera_data = bpy.data.cameras.new("验收相机")
    camera = bpy.data.objects.new("验收相机", camera_data)
    preview.objects.link(camera)
    distance = max(size.x, size.y, size.z) * 1.65
    camera.location = center + Vector((distance * 0.78, -distance, distance * 0.58))
    look_at(camera, center + Vector((0, 0, size.z * 0.05)))
    camera.data.lens = 58
    bpy.context.scene.camera = camera
    for name, location, energy, color, scale in (
        ("主光", center + Vector((-size.x, -size.y, size.z * 1.6)), 1050, (0.64, 0.78, 1.0), max(size.x, size.y)),
        ("辅光", center + Vector((size.x, -size.y * 0.3, size.z)), 650, (0.75, 0.48, 1.0), max(size.x, size.y) * 0.8),
        ("轮廓光", center + Vector((0, size.y, size.z * 1.5)), 850, (1.0, 0.48, 0.24), max(size.x, size.y) * 0.7),
    ):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy * max(0.08, min(1.0, max(size) / 5.0))
        data.color = color
        data.shape = "DISK"
        data.size = max(1.0, scale)
        light = bpy.data.objects.new(name, data)
        light.location = location
        look_at(light, center)
        preview.objects.link(light)
    bpy.ops.mesh.primitive_plane_add(size=max(size.x, size.y) * 3.0, location=(0, 0, minimum.z - 0.01))
    ground = bpy.context.object
    ground_material = bpy.data.materials.new("验收地面")
    ground_material.diffuse_color = (0.018, 0.025, 0.05, 1.0)
    ground.data.materials.append(ground_material)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(options.output)
    if scene.world is None:
        scene.world = bpy.data.worlds.new("验收世界")
    scene.world.color = (0.008, 0.012, 0.025)
    scene.view_settings.look = "AgX - Medium High Contrast"
    options.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
