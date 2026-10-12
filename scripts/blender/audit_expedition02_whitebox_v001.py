"""Read-only probe for the expedition 02 layer-1 whitebox .blend.

Run with:
    blender --background --python scripts/blender/audit_expedition02_whitebox_v001.py

Opens the saved .blend and prints one JSON object. Everything it reports comes
from the artifact itself — floor slabs are used to recover the room rectangles,
so the door-lane check does not trust the build script's tables.

Two things it deliberately checks that the build-time validator cannot:

  * 门槽合法性 —— 门心必须是**相邻两间房各自那面墙**的合法槽
    (`RoomDoorLane.lane_offsets()`：15m -> 0；10m -> ±2.5；75m -> ±30 步进 5)，
    而不是「落在整条网格线的某个位置」。整条网格线可以由几面不同长度的墙拼成，
    按线判会假红。
  * 外墙是否贴齐包络 —— 外墙面必须落在 block 边线上，内墙压在网格线上。
"""

from __future__ import annotations

import json
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND = (
    ROOT
    / "art_source/design/whitebox/tower_zones/expedition_02/v001/blender"
    / "远征关卡02_白模_第1层_长廊与客房_v001.blend"
)

GRID_UNIT = 5.0
WALL_THICKNESS = 0.30
WALL_H_LOW = 3.0
WALL_H_TALL = 11.9


def world_bounds(obj):
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return (
        Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points))),
        Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points))),
    )


def lane_offsets(length_m: float) -> list[float]:
    """RoomDoorLane.lane_offsets() 的同义重写（只用于只读核对）。"""
    count = max(1, int(round(length_m / GRID_UNIT)))
    first = 1 if count >= 3 else 0
    last = count - 2 if count >= 3 else count - 1
    return [-length_m * 0.5 + GRID_UNIT * (i + 0.5) for i in range(first, last + 1)]


def parse_line(label: str):
    """'Vn045' -> ('v', -45.0)；'Hp005' -> ('h', 5.0)。"""
    axis = "v" if label[0] == "V" else "h"
    sign = -1.0 if label[1] == "n" else 1.0
    return axis, sign * float(int(label[2:]))


def main() -> None:
    bpy.ops.wm.open_mainfile(filepath=str(BLEND))

    output_collections = [c for c in bpy.data.collections if c.name.startswith("02_游戏输出")]
    objects = [obj for coll in output_collections for obj in coll.all_objects]

    lo_all, hi_all = [], []
    scale_bad, origin_bad = [], []
    thickness_bad, height_bad, module_over = [], [], []
    walls, door_lintels = [], []
    rooms: dict = {}

    for obj in objects:
        lo, hi = world_bounds(obj)
        lo_all.append(lo)
        hi_all.append(hi)
        if any(abs(float(v) - 1.0) > 0.0001 for v in obj.scale):
            scale_bad.append(obj.name)
        if str(obj.get("origin_contract", "")) != "world_origin_stored_on_object_location":
            origin_bad.append(obj.name)

        kind = str(obj.get("component_kind", ""))
        if kind == "floor_slab":
            key = str(obj.get("room_key", obj.name))
            rooms[key] = dict(
                key=key, name_zh=str(obj.get("component_role", "")).split(" ")[0],
                x0=round(lo.x, 4), y0=round(lo.y, 4), x1=round(hi.x, 4), y1=round(hi.y, 4),
            )
        if kind in {"wall", "door_wall"}:
            longest = max(float(obj.dimensions.x), float(obj.dimensions.y))
            thickness = min(float(obj.dimensions.x), float(obj.dimensions.y))
            if longest > GRID_UNIT + 0.001:
                module_over.append(obj.name)
            if abs(thickness - WALL_THICKNESS) > 0.001:
                thickness_bad.append({"name": obj.name, "thickness": round(thickness, 4)})
            height = float(obj.dimensions.z)
            if "LINTEL" not in obj.name and abs(height - WALL_H_LOW) > 0.001 and abs(height - WALL_H_TALL) > 0.001:
                height_bad.append({"name": obj.name, "height": round(height, 4)})
            walls.append({
                "name": obj.name,
                "line": str(obj.get("wall_line", "")),
                "module_type": str(obj.get("wall_module_type", "")),
                "door_key": str(obj.get("door_key", "")),
                "bounds": [[round(v, 4) for v in lo], [round(v, 4) for v in hi]],
            })
            if "LINTEL" in obj.name and obj.get("door_key"):
                door_lintels.append(obj)

    # ---- 门洞净跨 + 门槽合法性（按相邻两间房各自那面墙判） -------------------
    openings = []
    lane_violations = []
    for obj in door_lintels:
        lo, hi = world_bounds(obj)
        span = max(hi.x - lo.x, hi.y - lo.y)
        line = str(obj.get("wall_line", ""))
        axis, coord = parse_line(line)
        center = float(obj.get("wall_slot_center_m", 0.0))
        kind = str(obj.get("wall_module_type", ""))
        door_key = str(obj.get("door_key", ""))

        if axis == "v":
            sides = [r for r in rooms.values() if abs(r["x1"] - coord) < 0.001 or abs(r["x0"] - coord) < 0.001]
        else:
            sides = [r for r in rooms.values() if abs(r["y1"] - coord) < 0.001 or abs(r["y0"] - coord) < 0.001]

        per_room = []
        for room in sides:
            if axis == "v":
                a, b = room["y0"], room["y1"]
            else:
                a, b = room["x0"], room["x1"]
            if not (a - 0.001 <= center <= b + 0.001):
                continue  # 这间房不邻着这扇门
            wall_len = b - a
            wall_center = (a + b) * 0.5
            offsets = lane_offsets(wall_len)
            legal = any(abs(center - (wall_center + o)) <= 0.001 for o in offsets)
            per_room.append({
                "room": room["key"], "wall_length_m": wall_len,
                "wall_center_m": wall_center, "legal_slots_m": offsets,
                "door_offset_from_wall_center_m": round(center - wall_center, 4),
                "legal": legal,
            })
        record = {
            "lintel": obj.name, "door_key": door_key, "kind": kind,
            "clear_span_m": round(span, 4),
            "opening_bottom_z_m": round(float(obj.location.z), 4),
            "wall_line": line, "door_center_m": center,
            "adjacent_rooms": per_room,
            "legal_on_all_adjacent_rooms": bool(per_room) and all(r["legal"] for r in per_room),
        }
        openings.append(record)
        if not record["legal_on_all_adjacent_rooms"]:
            lane_violations.append(record)

    # ---- 外墙必须贴齐包络 ------------------------------------------------------
    xs = [r["x0"] for r in rooms.values()] + [r["x1"] for r in rooms.values()]
    ys = [r["y0"] for r in rooms.values()] + [r["y1"] for r in rooms.values()]
    nominal = (min(xs), max(xs), min(ys), max(ys))
    measured = (
        round(min(v.x for v in lo_all), 4), round(max(v.x for v in hi_all), 4),
        round(min(v.y for v in lo_all), 4), round(max(v.y for v in hi_all), 4),
    )
    envelope_bad = [] if tuple(measured) == tuple(round(v, 4) for v in nominal) else [
        {"nominal": [round(v, 4) for v in nominal], "measured": list(measured)}
    ]

    # ---- 通洞必须是真空：open 洞那段网格上不许有任何墙件（否则走廊被堵） ----
    open_violations = []
    man_path = Path(str(BLEND)).parent.parent / (
        "data/component_packages/hotel_floor_01/远征关卡02_白模_第1层_长廊与客房/asset_manifest.json"
    )
    if man_path.exists():
        man = json.loads(man_path.read_text(encoding="utf-8"))
        for d in man.get("doors", []):
            if str(d.get("kind")) != "open":
                continue
            axis = str(d["axis"])
            coord = round(float(d["line_coord_m"]), 3)
            lo = round(float(d["opening_center_m"]) - float(d["opening_width_m"]) / 2 + 0.01, 3)
            hi = round(float(d["opening_center_m"]) + float(d["opening_width_m"]) / 2 - 0.01, 3)
            for w in walls:
                wl = str(w.get("line", ""))
                if not wl:
                    continue
                waxis, wcoord = parse_line(wl)
                if waxis != axis or abs(wcoord - coord) > 0.001:
                    continue
                blo, bhi = w["bounds"]
                wa, wb = (blo[1], bhi[1]) if axis == "h" else (blo[0], bhi[0])
                wa, wb = min(wa, wb), max(wa, wb)
                if wa < hi and wb > lo:
                    open_violations.append({"door": d["door_key"], "blocking_wall": w["name"]})

    by_line: dict = {}
    for record in walls:
        bucket = by_line.setdefault(record["line"], {})
        key = record["module_type"] or "solid"
        bucket[key] = bucket.get(key, 0) + 1

    scene = bpy.context.scene
    print(
        "EXPEDITION02_WHITEBOX_V001_AUDIT",
        json.dumps({
            "blend": str(BLEND.relative_to(ROOT)).replace("\\", "/"),
            "scene_version": scene.get("expedition02_whitebox_version"),
            "output_collections": [c.name for c in output_collections],
            "object_count": len(objects),
            "room_count": len(rooms),
            "rooms": sorted(rooms.values(), key=lambda r: r["key"]),
            "bounds_world_m": {
                "min": [round(min(v[i] for v in lo_all), 4) for i in range(3)],
                "max": [round(max(v[i] for v in hi_all), 4) for i in range(3)],
            },
            "nominal_envelope_m": [round(v, 4) for v in nominal],
            "measured_envelope_m": list(measured),
            "envelope_mismatch": envelope_bad,
            "wall_counts_by_line": by_line,
            "door_openings": openings,
            "door_lane_violations": lane_violations,
            "open_hole_blocked": open_violations,
            "non_unit_scale_objects": scale_bad,
            "origin_contract_violations": origin_bad,
            "wall_thickness_violations": thickness_bad,
            "wall_height_violations": height_bad,
            "module_length_violations": module_over,
        }, ensure_ascii=False),
    )


if __name__ == "__main__":
    main()
