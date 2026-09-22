"""Read-only probe for the expedition 01 arena whitebox .blend.

Run with:
    blender --background --python scripts/blender/audit_expedition01_whitebox_v001.py

Prints one JSON object to stdout. It opens the saved .blend and reports what
actually landed in the file, so the numbers in asset_manifest.json can be
checked against the artifact instead of against the build script's intent.
"""

from __future__ import annotations

import json
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND = (
    ROOT
    / "source/art/whitebox/tower_zones/expedition_01/v001/blender"
    / "远征关卡01_白模_Boss竞技场_50x40m_v001.blend"
)


def world_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return (
        Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points))),
        Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points))),
    )


def main() -> None:
    bpy.ops.wm.open_mainfile(filepath=str(BLEND))

    output_collections = [
        collection
        for collection in bpy.data.collections
        if collection.name.startswith("02_游戏输出")
    ]
    objects = [
        obj for collection in output_collections for obj in collection.all_objects
    ]

    min_all: list[float] = []
    max_all: list[float] = []
    for obj in objects:
        low, high = world_bounds(obj)
        min_all.append(low)
        max_all.append(high)

    door_objects = []
    wall_objects = []
    scale_bad = []
    origin_bad = []
    for obj in objects:
        if any(abs(float(v) - 1.0) > 0.0001 for v in obj.scale):
            scale_bad.append(obj.name)
        low, high = world_bounds(obj)
        if str(obj.get("component_kind", "")) in {"wall", "door_wall"}:
            wall_objects.append(
                {
                    "name": obj.name,
                    "side": obj.name.split("_")[1] if obj.name.startswith("WALL_") else None,
                    "slot": obj.get("wall_slot_index"),
                    "slot_center_m": obj.get("wall_slot_center_m"),
                    "module_type": obj.get("wall_module_type"),
                    "door_target": obj.get("door_target"),
                    "bounds": [
                        [round(v, 4) for v in low],
                        [round(v, 4) for v in high],
                    ],
                }
            )
        if str(obj.get("component_kind", "")) == "door_wall":
            door_objects.append(obj.name)
        if str(obj.get("origin_contract", "")) != "world_origin_stored_on_object_location":
            origin_bad.append(obj.name)

    # 门洞净宽核验：门楣在世界 X/Y 上的跨距应恰为 DOOR_WIDTH。
    lintels = [
        record
        for record in wall_objects
        if record["module_type"] == "door_5m" and record["name"].endswith("_LINTEL")
    ]
    openings = []
    for record in lintels:
        low, high = record["bounds"]
        openings.append(
            {
                "name": record["name"],
                "door_target": record["door_target"],
                "clear_span_m": round(max(high[0] - low[0], high[1] - low[1]), 4),
                "opening_center_m": record["slot_center_m"],
            }
        )

    by_side: dict[str, dict[str, int]] = {}
    for record in wall_objects:
        if record["side"] is None:
            continue
        side_bucket = by_side.setdefault(record["side"], {})
        key = str(record["module_type"])
        side_bucket[key] = side_bucket.get(key, 0) + 1

    longest = 0.0
    for record in wall_objects:
        low, high = record["bounds"]
        longest = max(longest, high[0] - low[0], high[1] - low[1])

    scene = bpy.context.scene
    print(
        "EXPEDITION01_WHITEBOX_V001_AUDIT",
        json.dumps(
            {
                "blend": str(BLEND.relative_to(ROOT)).replace("\\", "/"),
                "scene_version": scene.get("expedition01_whitebox_version"),
                "output_collections": [c.name for c in output_collections],
                "object_count": len(objects),
                "bounds_world_m": {
                    "min": [
                        round(min(v.x for v in min_all), 4),
                        round(min(v.y for v in min_all), 4),
                        round(min(v.z for v in min_all), 4),
                    ],
                    "max": [
                        round(max(v.x for v in max_all), 4),
                        round(max(v.y for v in max_all), 4),
                        round(max(v.z for v in max_all), 4),
                    ],
                },
                "wall_counts_by_side": by_side,
                "longest_wall_or_door_horizontal_m": round(longest, 4),
                "door_objects": sorted(door_objects),
                "door_openings": openings,
                "non_unit_scale_objects": scale_bad,
                "origin_contract_violations": origin_bad,
            },
            ensure_ascii=False,
        ),
    )


if __name__ == "__main__":
    main()
