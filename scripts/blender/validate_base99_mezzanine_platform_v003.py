"""Strict source/output validation for the Base99 mezzanine platform v003."""

from __future__ import annotations

import math

import bpy
from mathutils import Vector


ASSET_ID = "ENV-BASE99-MEZZANINE-20X10-Z5"
VERSION = "v003"
PALETTE_UV = "PaletteUV"
EXPECTED_MATERIALS = {
    "01_精工金属_紫色骨架",
    "02_细腻哑光_青绿大面",
    "04_柔和自发光_UI灯光",
}


def bounds(root: bpy.types.Object, obj: bpy.types.Object) -> tuple[Vector, Vector]:
    inverse = root.matrix_world.inverted()
    points = [inverse @ obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    minimum = Vector(tuple(min(point[index] for point in points) for index in range(3)))
    maximum = Vector(tuple(max(point[index] for point in points) for index in range(3)))
    return minimum, maximum


def uv_area(points) -> float:
    return abs(sum(
        points[index].x * points[(index + 1) % len(points)].y
        - points[(index + 1) % len(points)].x * points[index].y
        for index in range(len(points))
    )) * 0.5


source_root = next(
    obj for obj in bpy.data.objects
    if obj.get("asset_id") == ASSET_ID
    and obj.get("asset_version") == VERSION
    and "制作根节点" in obj.name
)
output_root = next(
    obj for obj in bpy.data.objects
    if obj.get("asset_id") == ASSET_ID
    and obj.get("asset_version") == VERSION
    and "输出根节点" in obj.name
)
slab = next(obj for obj in source_root.children if "整体承重框" in obj.name)
slab_minimum, slab_maximum = bounds(source_root, slab)
assert (slab_minimum - Vector((-9.72625, -4.72625, 4.78))).length < 1.0e-4
assert (slab_maximum - Vector((9.97375, 4.97375, 4.90))).length < 1.0e-4

edge_tokens = ("东侧边梁", "西侧边梁", "南侧边梁", "北侧边梁")
edges = [obj for obj in source_root.children if any(token in obj.name for token in edge_tokens)]
assert len(edges) == 4, "Expected four authored edge beams"
edge_bounds = {obj.name: bounds(source_root, obj) for obj in edges}
assert all(abs(slab_minimum.y - minimum.y) > 0.10 for name, (minimum, _) in edge_bounds.items() if "南侧" in name)
assert all(abs(slab_maximum.y - maximum.y) > 0.10 for name, (_, maximum) in edge_bounds.items() if "北侧" in name)
assert all(abs(slab_minimum.x - minimum.x) > 0.10 for name, (minimum, _) in edge_bounds.items() if "西侧" in name)
assert all(abs(slab_maximum.x - maximum.x) > 0.10 for name, (_, maximum) in edge_bounds.items() if "东侧" in name)
assert slab_minimum.z > 4.75, "Deck skin still overlaps the full grid-beam height"

output_meshes = [obj for obj in output_root.children if obj.type == "MESH"]
assert len(output_meshes) == 2, "Expected body and emissive output meshes"
used_materials = {material.name for obj in output_meshes for material in obj.data.materials if material}
assert used_materials == EXPECTED_MATERIALS
valid_faces = 0
total_faces = 0
for obj in output_meshes:
    uv = obj.data.uv_layers.get(PALETTE_UV)
    assert uv is not None and obj.data.uv_layers.active == uv and uv.active_render
    assert len(obj.data.uv_layers) == 1
    for polygon in obj.data.polygons:
        total_faces += 1
        points = [uv.data[index].uv for index in polygon.loop_indices]
        columns = {min(9, max(0, math.floor(point.x * 10.0))) for point in points}
        rows = {min(9, max(0, math.floor(point.y * 10.0))) for point in points}
        assert uv_area(points) > 1.0e-7
        assert len(columns) == 1 and len(rows) == 1
        valid_faces += 1
assert int(output_root.get("coplanar_edge_face_count", -1)) == 0
print(
    "BASE99_MEZZANINE_PLATFORM_V003_BLEND_VALID: faces=%d/%d materials=%d coplanar_edge_faces=0"
    % (valid_faces, total_faces, len(used_materials))
)
