"""Validate the v0.1 tower runtime-sync Blender source.

Legacy PH-prefixed Blender collection names are retained as source-file identifiers.
"""

from pathlib import Path

import bpy
from mathutils import Vector


SOURCE_DIR = Path(__file__).resolve().parent
EXPECTED_BLEND = SOURCE_DIR / "env_tower_descent_kit_top3d_v007.blend"
EPSILON = 0.03

errors = []


def check(condition, message):
    if not condition:
        errors.append(message)


scene = bpy.context.scene
check(Path(bpy.data.filepath).resolve() == EXPECTED_BLEND.resolve(), "wrong blend path")
check(scene.unit_settings.system == "METRIC", "scene is not metric")
check(scene.get("asset_version") == "v007", "scene version is not v007")
check(abs(float(scene.get("map_footprint_size_m", 0.0)) - 250.0) <= EPSILON, "map size is not 250 m")
check(abs(float(scene.get("base_room_size_m", 0.0)) - 30.0) <= EPSILON, "base size is not 30 m")
check(scene.get("base_grid_tiles") == "6x6", "base grid metadata is not 6x6")
check(abs(float(scene.get("door_clear_width_m", 0.0)) - 2.2) <= EPSILON, "door width is not 2.2 m")
check(abs(float(scene.get("door_clear_height_m", 0.0)) - 2.5) <= EPSILON, "door height is not 2.5 m")
check(scene.get("elevator_placement") == "standalone_wall_edge", "elevator placement contract is wrong")

required_collections = {
    "20_PH49_RUNTIME_SYNC",
    "20A_LEVEL_GUIDES_250M",
    "20B_BASE_99_30M",
    "20C_ROOMS_98_95",
    "20D_STANDALONE_ELEVATORS",
    "20E_DOOR_CONTRACT_V002",
    "10D_MOD_WALL_DOOR_5M_U01",
}
check(required_collections <= set(bpy.data.collections.keys()), "runtime-sync collections are missing")

base_tiles = [
    obj
    for obj in bpy.data.objects
    if obj.get("asset_role") == "BASE_GRID_TILE"
]
check(len(base_tiles) == 36, f"expected 36 base tiles, got {len(base_tiles)}")
if base_tiles:
    xs = sorted({round(obj.location.x, 2) for obj in base_tiles})
    ys = sorted({round(obj.location.y, 2) for obj in base_tiles})
    check(len(xs) == 6 and len(ys) == 6, "base tile coordinates are not a 6x6 grid")
    check(abs(xs[0] + 10.0) <= EPSILON, "base west tile center is wrong")
    check(abs(xs[-1] - 15.0) <= EPSILON, "base east tile center is wrong")

stages = [
    obj
    for obj in bpy.data.objects
    if obj.get("asset_role") == "RUNTIME_FLOOR_STAGE"
]
check(len(stages) == 6, f"expected six 100--95 stages, got {len(stages)}")
for stage in stages:
    check(
        (Vector(stage.dimensions) - Vector((250.0, 250.0, 0.12))).length <= EPSILON,
        f"{stage.name} is not 250 m square",
    )

footprints = [
    obj
    for obj in bpy.data.objects
    if obj.get("asset_role") == "RUNTIME_ROOM_FOOTPRINT"
]
counts = {}
for footprint in footprints:
    floor = int(footprint.get("floor_number", 0))
    counts[floor] = counts.get(floor, 0) + 1
check(counts.get(98) == 12, f"98F room count wrong: {counts.get(98)}")
check(counts.get(97) == 12, f"97F room count wrong: {counts.get(97)}")
check(counts.get(96) == 12, f"96F room count wrong: {counts.get(96)}")
check(counts.get(95) == 10, f"95F room count wrong: {counts.get(95)}")

entry98 = bpy.data.objects.get("Floor98_entry_Footprint")
check(entry98 is not None, "98F entry footprint is missing")
if entry98 is not None:
    check(abs(entry98.location.x - 27.5) <= EPSILON, "98F entry is not left/inward of east door")
    check(abs(entry98.location.y - 2.5) <= EPSILON, "98F entry axis is wrong")

elevators = [
    obj
    for obj in bpy.data.objects
    if obj.get("asset_role") == "STANDALONE_ELEVATOR_FACILITY"
]
check(len(elevators) == 5, f"expected five independent elevators, got {len(elevators)}")
check(all(not bool(obj.get("is_room_content", True)) for obj in elevators), "an elevator is still room content")

corridors = [
    obj
    for obj in bpy.data.objects
    if obj.get("asset_role") == "BASE_TO_STAIR_CORRIDOR"
]
check(len(corridors) == 2, f"expected two base stair corridors, got {len(corridors)}")
check(
    all(abs(float(obj.get("corridor_length_m", 0.0)) - 17.5) <= EPSILON for obj in corridors),
    "base stair corridor length is not 17.5 m",
)

door_root = bpy.data.objects.get("MOD_WALL_DOOR_5M_U01_ROOT")
check(door_root is not None, "door master root is missing")
if door_root is not None:
    check(door_root.get("asset_version") == "v002", "door master version is not v002")
    check(abs(float(door_root.get("clear_width_m", 0.0)) - 2.2) <= EPSILON, "door master width is wrong")
    check(abs(float(door_root.get("clear_height_m", 0.0)) - 2.5) <= EPSILON, "door master height is wrong")
    components = [child for child in door_root.children if child.type == "MESH"]
    check(len(components) == 7, f"door master component count wrong: {len(components)}")

if errors:
    print("VALIDATE_V007_FAIL")
    for error in errors:
        print(f" - {error}")
    raise SystemExit(1)

print(
    "VALIDATE_V007_OK "
    f"tiles={len(base_tiles)} footprints={len(footprints)} "
    f"elevators={len(elevators)} corridors={len(corridors)}"
)
