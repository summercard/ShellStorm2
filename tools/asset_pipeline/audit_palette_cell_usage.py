"""Print per-object PaletteUV cell usage for Blender asset audits."""

from __future__ import annotations

from collections import Counter

import bpy


def cell_for_polygon(mesh: bpy.types.Mesh, polygon: bpy.types.MeshPolygon) -> tuple[int, int]:
    layer = mesh.uv_layers.get("PaletteUV")
    values = [layer.data[index].uv for index in polygon.loop_indices]
    u = sum(value.x for value in values) / len(values)
    v = sum(value.y for value in values) / len(values)
    return min(9, max(0, int(u * 10))), min(9, max(0, int(v * 10)))


for obj in bpy.context.scene.objects:
    if obj.type != "MESH" or "PaletteUV" not in obj.data.uv_layers:
        continue
    counts = Counter(cell_for_polygon(obj.data, polygon) for polygon in obj.data.polygons)
    print("PALETTE_USAGE", obj.name, len(obj.data.polygons), sorted(counts.items()))
