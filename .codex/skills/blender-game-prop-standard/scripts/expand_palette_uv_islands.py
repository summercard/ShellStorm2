"""Expand point-like PaletteUV data into editable per-face islands inside each color cell."""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


TARGET_SPAN = 0.062
MIN_SPAN = 0.014
MIN_AREA = 1.0e-7


def parse_args() -> argparse.Namespace:
    values = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--glb", type=Path)
    parser.add_argument("--palette", type=Path, help="relink and pack the canonical palette before saving/export")
    return parser.parse_args(values)


def projection_axes(normal: Vector) -> tuple[int, int]:
    dominant = max(range(3), key=lambda index: abs(normal[index]))
    return ((1, 2), (0, 2), (0, 1))[dominant]


def polygon_area(points: list[Vector]) -> float:
    return abs(sum(
        points[index].x * points[(index + 1) % len(points)].y
        - points[(index + 1) % len(points)].x * points[index].y
        for index in range(len(points))
    )) * 0.5


def expand_mesh(mesh: bpy.types.Mesh) -> int:
    layer = mesh.uv_layers.get("PaletteUV")
    if layer is None:
        raise RuntimeError(f"{mesh.name} 缺少 PaletteUV")
    changed = 0
    for polygon in mesh.polygons:
        loop_indices = list(polygon.loop_indices)
        if len(loop_indices) < 3:
            continue
        old_uvs = [layer.data[index].uv for index in loop_indices]
        average_u = sum(uv.x for uv in old_uvs) / len(old_uvs)
        average_v = sum(uv.y for uv in old_uvs) / len(old_uvs)
        column = min(9, max(0, math.floor(max(0.0, min(0.999999, average_u)) * 10.0)))
        row = min(9, max(0, math.floor(max(0.0, min(0.999999, average_v)) * 10.0)))
        cell_center = Vector(((column + 0.5) / 10.0, (row + 0.5) / 10.0))

        axis_u, axis_v = projection_axes(polygon.normal)
        projected = [
            Vector((mesh.vertices[mesh.loops[index].vertex_index].co[axis_u], mesh.vertices[mesh.loops[index].vertex_index].co[axis_v]))
            for index in loop_indices
        ]
        minimum = Vector((min(point.x for point in projected), min(point.y for point in projected)))
        maximum = Vector((max(point.x for point in projected), max(point.y for point in projected)))
        source_center = (minimum + maximum) * 0.5
        source_span = maximum - minimum
        largest_span = max(source_span.x, source_span.y)

        if largest_span <= 1.0e-12:
            projected = [
                Vector((math.cos(2.0 * math.pi * index / len(loop_indices)), math.sin(2.0 * math.pi * index / len(loop_indices))))
                for index in range(len(loop_indices))
            ]
            source_center = Vector((0.0, 0.0))
            source_span = Vector((2.0, 2.0))
            largest_span = 2.0

        scale = TARGET_SPAN / largest_span
        island = [(point - source_center) * scale for point in projected]
        span_u = max(point.x for point in island) - min(point.x for point in island)
        span_v = max(point.y for point in island) - min(point.y for point in island)
        stretch_u = max(1.0, MIN_SPAN / max(span_u, 1.0e-12))
        stretch_v = max(1.0, MIN_SPAN / max(span_v, 1.0e-12))
        island = [Vector((point.x * stretch_u, point.y * stretch_v)) for point in island]
        if polygon_area(island) < MIN_AREA:
            radius = TARGET_SPAN * 0.5
            island = [
                Vector((math.cos(2.0 * math.pi * index / len(loop_indices)) * radius,
                        math.sin(2.0 * math.pi * index / len(loop_indices)) * radius))
                for index in range(len(loop_indices))
            ]

        for loop_index, point in zip(loop_indices, island):
            uv = cell_center + point
            layer.data[loop_index].uv = uv
            changed += 1

    mesh.uv_layers.active = layer
    layer.active_render = True
    mesh.update()
    return changed


def export_glb(path: Path) -> None:
    outputs = [collection for collection in bpy.data.collections if collection.name.startswith("02_游戏输出")]
    objects = {obj for collection in outputs for obj in collection.all_objects if obj.type == "MESH"}
    if not objects:
        raise RuntimeError("GLB导出要求存在 02_游戏输出 集合")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = next(iter(objects))
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLB", use_selection=True, export_yup=True, export_apply=True
    )


def relink_palette(path: Path) -> None:
    if not path.exists():
        raise FileNotFoundError(path)
    for image in bpy.data.images:
        if image.source != "FILE" or "色盘" not in image.name:
            continue
        image.filepath = str(path)
        image.reload()
        image.pack()


def main() -> None:
    options = parse_args()
    # 批处理原位更新时不在正式验收目录旁生成 .blend1；历史版本由资产目录统一归档。
    bpy.context.preferences.filepaths.save_version = 0
    meshes = {obj.data for obj in bpy.context.scene.objects if obj.type == "MESH"}
    changed = sum(expand_mesh(mesh) for mesh in meshes)
    if options.palette:
        relink_palette(options.palette)
    for material in bpy.data.materials:
        if not material.use_nodes or material.node_tree is None:
            continue
        for node in material.node_tree.nodes:
            if node.type == "UVMAP":
                node.uv_map = "PaletteUV"
            elif node.type == "TEX_IMAGE":
                node.interpolation = "Closest"
    options.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(options.output), compress=True)
    if options.glb:
        export_glb(options.glb)
    print("EXPANDED_PALETTE_UV_LOOPS", changed)


if __name__ == "__main__":
    main()
