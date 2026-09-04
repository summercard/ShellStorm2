#!/usr/bin/env python3
"""Read-only geometry report for the v017 western door-wall iteration."""
from __future__ import annotations

import json
from pathlib import Path

import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must run with v017 open")

NAMES = (
    "西墙带门墙体_主体_金属哑光反光",
    "西墙标准滑升门_主体_金属哑光反光",
    "西墙标准滑升门_状态灯_柔和自发光",
    "ENV-BASE99-WALL-DOOR-5X9_WEST_输出根节点",
    "ENV-BASE99-DOOR-LIFT-22X25_WEST_输出根节点",
    "普通墙体_主体_金属哑光反光.017",
    "普通墙体_主体_金属哑光反光.016",
    "带门墙体_主体_金属哑光反光.002",
)


def world_bounds(obj: bpy.types.Object):
    if obj.type != "MESH":
        return None
    points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    return {
        "min": [round(min(point[index] for point in points), 4) for index in range(3)],
        "max": [round(max(point[index] for point in points), 4) for index in range(3)],
    }


report = {}
for name in NAMES:
    obj = bpy.data.objects.get(name)
    if obj is None:
        continue
    report[name] = {
        "parent": obj.parent.name if obj.parent else None,
        "local_location": [round(float(value), 4) for value in obj.location],
        "world_location": [round(float(value), 4) for value in obj.matrix_world.translation],
        "world_rotation": [round(float(value), 4) for value in obj.matrix_world.to_euler()],
        "dimensions": [round(float(value), 4) for value in obj.dimensions],
        "world_bounds": world_bounds(obj),
    }
print(json.dumps(report, ensure_ascii=False, indent=2))
