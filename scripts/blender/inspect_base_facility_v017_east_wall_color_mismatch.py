#!/usr/bin/env python3
"""Read-only material/PaletteUV comparison for the east door wall and neighbours."""
from __future__ import annotations

import collections
import json
from pathlib import Path

import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must run with v017 open")

target = bpy.data.objects["带门墙体_主体_金属哑光反光.002"]
neighbours = [
    obj for obj in bpy.data.objects
    if obj.type == "MESH" and obj.parent and obj.parent.parent
    and obj.parent.name.startswith("ENV-BASE99-WALL-PLAIN-5X9")
    and obj.parent.parent.name in {"保留东墙_02", "保留东墙_04"}
]


def inspect(obj):
    uv = obj.data.uv_layers.get("PaletteUV")
    cell_counts = collections.Counter()
    if uv:
        for polygon in obj.data.polygons:
            points = [uv.data[index].uv for index in polygon.loop_indices]
            cell = (int(sum(point.x for point in points) / len(points) * 10), int(sum(point.y for point in points) / len(points) * 10))
            cell_counts[cell] += 1
    return {
        "parent": obj.parent.name if obj.parent else None,
        "world_location": [round(float(value), 4) for value in obj.matrix_world.translation],
        "material_slots": [material.name if material else None for material in obj.data.materials],
        "material_polygon_counts": dict(collections.Counter(obj.data.polygons[index].material_index for index in range(len(obj.data.polygons)))),
        "palette_cell_polygon_counts": {f"{key[0]},{key[1]}": value for key, value in sorted(cell_counts.items())},
        "palette_uv": uv.name if uv else None,
    }

result = {"east_door_wall": inspect(target), "east_neighbour_walls": {obj.name: inspect(obj) for obj in neighbours}}
print(json.dumps(result, ensure_ascii=False, indent=2))
