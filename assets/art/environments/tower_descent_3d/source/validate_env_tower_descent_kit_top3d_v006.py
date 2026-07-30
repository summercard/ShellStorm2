"""QA checks for the v006 five-metre modular tower source."""

from pathlib import Path
import math
import re

import bpy
from mathutils import Vector


SOURCE_DIR = Path(__file__).resolve().parent
EXPECTED_BLEND = SOURCE_DIR / "env_tower_descent_kit_top3d_v006.blend"

GRID_UNIT = 5.0
MAP_UNITS = 67
MAP_SIZE = 335.0
MAP_HALF = 167.5
CORE_UNITS = 13
CORE_SIZE = 65.0
CORE_HALF = 32.5
EPSILON = 0.012

MODULE_FLOOR = "ENV-TOWER-FLOOR-TILE-5M"
MODULE_WALL = "ENV-TOWER-WALL-SOLID-5M"
MODULE_PARAPET = "ENV-TOWER-WALL-PARAPET-5M"
MODULE_DOOR = "ENV-TOWER-WALL-DOOR-5M"

errors = []
depsgraph = bpy.context.evaluated_depsgraph_get()


def check(condition, message):
    if not condition:
        errors.append(message)


def bounds(obj):
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return (
        Vector(
            (
                min(point.x for point in points),
                min(point.y for point in points),
                min(point.z for point in points),
            )
        ),
        Vector(
            (
                max(point.x for point in points),
                max(point.y for point in points),
                max(point.z for point in points),
            )
        ),
    )


def evaluated_bounds(obj):
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    points = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
    result = (
        Vector(
            (
                min(point.x for point in points),
                min(point.y for point in points),
                min(point.z for point in points),
            )
        ),
        Vector(
            (
                max(point.x for point in points),
                max(point.y for point in points),
                max(point.z for point in points),
            )
        ),
    )
    evaluated.to_mesh_clear()
    return result


def combined_evaluated_bounds(objects):
    object_bounds = [evaluated_bounds(obj) for obj in objects]
    return (
        Vector(
            (
                min(item[0].x for item in object_bounds),
                min(item[0].y for item in object_bounds),
                min(item[0].z for item in object_bounds),
            )
        ),
        Vector(
            (
                max(item[1].x for item in object_bounds),
                max(item[1].y for item in object_bounds),
                max(item[1].z for item in object_bounds),
            )
        ),
    )


def direct_objects(collection_name, roles=None):
    collection = bpy.data.collections.get(collection_name)
    if collection is None:
        return []
    if roles is None:
        return list(collection.objects)
    return [obj for obj in collection.objects if obj.get("asset_role") in roles]


def check_array_object(obj, expected_module_id):
    check(obj.get("asset_role") == "MODULE_ARRAY_ASSEMBLY", f"{obj.name} is not array assembly")
    check(obj.get("module_id") == expected_module_id, f"{obj.name} module ID wrong")
    check(not bool(obj.get("array_modifiers_applied")), f"{obj.name} array was marked applied")
    check(obj.scale == Vector((1.0, 1.0, 1.0)), f"{obj.name} has non-unit scale")
    modifiers = [modifier for modifier in obj.modifiers if modifier.type == "ARRAY"]
    expected_count = 2 if int(obj.get("array_count_y", 1)) > 1 else 1
    check(len(modifiers) == expected_count, f"{obj.name} array modifier count wrong")
    for modifier in modifiers:
        check(not modifier.use_relative_offset, f"{obj.name}/{modifier.name} uses relative offset")
        check(modifier.use_constant_offset, f"{obj.name}/{modifier.name} constant offset disabled")
        displacement = tuple(round(abs(value), 4) for value in modifier.constant_offset_displace)
        check(
            displacement in {(GRID_UNIT, 0.0, 0.0), (0.0, GRID_UNIT, 0.0)},
            f"{obj.name}/{modifier.name} is not spaced by 5 m: {displacement}",
        )


def check_group_bounds(objects, expected_bottom, expected_top, label):
    group_min, group_max = combined_evaluated_bounds(objects)
    check(abs(group_min.x + MAP_HALF) <= EPSILON, f"{label} west bound wrong")
    check(abs(group_min.y + MAP_HALF) <= EPSILON, f"{label} south bound wrong")
    check(abs(group_max.x - MAP_HALF) <= EPSILON, f"{label} east bound wrong")
    check(abs(group_max.y - MAP_HALF) <= EPSILON, f"{label} north bound wrong")
    check(abs(group_min.z - expected_bottom) <= EPSILON, f"{label} bottom Z wrong")
    check(abs(group_max.z - expected_top) <= EPSILON, f"{label} top Z wrong")


def check_module_collection(collection_name, expected_count, expected_doors, label):
    modules = direct_objects(
        collection_name,
        {"MODULE_INSTANCE", "MODULE_INSTANCE_DOOR"},
    )
    doors = [obj for obj in modules if obj.get("asset_role") == "MODULE_INSTANCE_DOOR"]
    check(len(modules) == expected_count, f"{label} expected {expected_count} modules, got {len(modules)}")
    check(len(doors) == expected_doors, f"{label} expected {expected_doors} doors, got {len(doors)}")
    for obj in modules:
        check(obj.scale == Vector((1.0, 1.0, 1.0)), f"{obj.name} has non-unit scale")
        step = int(obj.get("rotation_step_90", -1))
        check(step in {0, 1, 2, 3}, f"{obj.name} rotation step is invalid")
        if obj.get("asset_role") == "MODULE_INSTANCE":
            check(obj.get("module_id") == MODULE_WALL, f"{obj.name} is not solid-wall module")
        else:
            check(obj.get("module_id") == MODULE_DOOR, f"{obj.name} is not door module")
            leaves = [
                child
                for child in obj.children
                if child.get("door_component") == "DoorLeaf_OPEN"
            ]
            check(len(leaves) == 1, f"{obj.name} does not own one independent door leaf")
            if leaves:
                check(leaves[0].parent is obj, f"{obj.name} door leaf is not parented")
                check(
                    leaves[0].get("asset_role") == "MODULE_DOOR_COMPONENT_INSTANCE",
                    f"{obj.name} door leaf role is wrong",
                )
    return modules, doors


scene = bpy.context.scene
check(Path(bpy.data.filepath).resolve() == EXPECTED_BLEND.resolve(), "wrong blend path")
check(scene.unit_settings.system == "METRIC", "scene is not metric")
check(scene.get("asset_version") == "v006", "scene version is not v006")
check(abs(float(scene.get("grid_unit_m", 0.0)) - GRID_UNIT) <= 0.0001, "grid unit metadata wrong")
check(abs(float(scene.get("map_footprint_size_m", 0.0)) - MAP_SIZE) <= 0.0001, "map size metadata wrong")
check(abs(float(scene.get("functional_core_size_m", 0.0)) - CORE_SIZE) <= 0.0001, "core size metadata wrong")

required_collections = {
    "01B_TILE_GRID_5M",
    "01C_OUTER_PARAPET_GRID_5M",
    "01D_STAIR_ENTRY_WALL_GRID_5M",
    "03B_TILE_GRID_5M",
    "03C_OUTER_WALL_GRID_5M",
    "03D_CORE_WALL_GRID_5M",
    "03E_INTERIOR_WALL_GRID_5M",
    "05B_TILE_GRID_5M",
    "05C_OUTER_WALL_GRID_5M",
    "05D_CORE_WALL_GRID_5M",
    "05E_INTERIOR_WALL_GRID_5M",
    "10_MODULE_LIBRARY_5M",
    "10A_MOD_FLOOR_TILE_5M_U01",
    "10B_MOD_WALL_SOLID_5M_U01",
    "10C_MOD_WALL_PARAPET_5M_U01",
    "10D_MOD_WALL_DOOR_5M_U01",
}
check(
    required_collections <= set(bpy.data.collections.keys()),
    "missing modular collections",
)

for old_collection in (
    "01A_EXTERIOR_ROOFTOP_FULL_FOOTPRINT",
    "03A_EXTERIOR_FACILITY_FULL_FOOTPRINT",
    "05A_EXTERIOR_COMBAT_FULL_FOOTPRINT",
):
    check(bpy.data.collections.get(old_collection) is None, f"old collection remains: {old_collection}")

master_specs = (
    ("MOD_FLOOR_TILE_5M_U01", MODULE_FLOOR, (-2.5, -2.5, -0.3), (2.5, 2.5, 0.0)),
    ("MOD_WALL_SOLID_5M_U01", MODULE_WALL, (-2.5, -0.15, 0.0), (2.5, 0.15, 9.0)),
    ("MOD_WALL_PARAPET_5M_U01", MODULE_PARAPET, (-2.5, -0.15, 0.0), (2.5, 0.15, 1.5)),
)
for name, module_id, expected_min, expected_max in master_specs:
    master = bpy.data.objects.get(name)
    check(master is not None, f"missing master {name}")
    if master:
        check(master.get("module_id") == module_id, f"{name} module ID wrong")
        check(master.get("asset_role") == "MODULE_MASTER", f"{name} master role wrong")
        object_min, object_max = bounds(master)
        check((object_min - Vector(expected_min)).length <= EPSILON, f"{name} min bound wrong")
        check((object_max - Vector(expected_max)).length <= EPSILON, f"{name} max bound wrong")
        check(master.hide_viewport and master.hide_render, f"{name} master is not hidden")

door_master = bpy.data.objects.get("MOD_WALL_DOOR_5M_U01_ROOT")
check(door_master is not None, "missing door module master")
if door_master:
    check(door_master.get("module_id") == MODULE_DOOR, "door master ID wrong")
    check(bool(door_master.get("door_leaf_independent")), "door independence metadata lost")
    master_leaves = [
        child for child in door_master.children if child.get("door_component") == "DoorLeaf_OPEN"
    ]
    check(len(master_leaves) == 1, "door master does not have exactly one door leaf")
    check(len([child for child in door_master.children if child.type == "MESH"]) == 7, "door master pieces wrong")

floor_master = bpy.data.objects.get("MOD_FLOOR_TILE_5M_U01")
wall_master = bpy.data.objects.get("MOD_WALL_SOLID_5M_U01")
parapet_master = bpy.data.objects.get("MOD_WALL_PARAPET_5M_U01")

floor_groups = (
    ("01B_TILE_GRID_5M", 4, 4474, -0.3, 0.0, "rooftop tiles"),
    ("03B_TILE_GRID_5M", 1, 4489, -9.3, -9.0, "facility tiles"),
    ("05B_TILE_GRID_5M", 1, 4489, -18.3, -18.0, "combat tiles"),
)
for collection_name, object_count, virtual_count, bottom, top, label in floor_groups:
    objects = direct_objects(collection_name, {"MODULE_ARRAY_ASSEMBLY"})
    check(len(objects) == object_count, f"{label} array object count wrong")
    check(
        sum(int(obj.get("virtual_module_count", 0)) for obj in objects) == virtual_count,
        f"{label} virtual tile count wrong",
    )
    for obj in objects:
        check_array_object(obj, MODULE_FLOOR)
        if floor_master:
            check(obj.data is floor_master.data, f"{obj.name} does not share floor master mesh")
    if objects:
        check_group_bounds(objects, bottom, top, label)

outer_groups = (
    ("01C_OUTER_PARAPET_GRID_5M", MODULE_PARAPET, 0.0, 1.5, "rooftop parapet"),
    ("03C_OUTER_WALL_GRID_5M", MODULE_WALL, -9.0, 0.0, "facility outer wall"),
    ("05C_OUTER_WALL_GRID_5M", MODULE_WALL, -18.0, -9.0, "combat outer wall"),
)
for collection_name, module_id, bottom, top, label in outer_groups:
    objects = direct_objects(collection_name, {"MODULE_ARRAY_ASSEMBLY"})
    check(len(objects) == 4, f"{label} does not have four side arrays")
    check(
        sum(int(obj.get("virtual_module_count", 0)) for obj in objects) == 268,
        f"{label} virtual module count wrong",
    )
    for obj in objects:
        check_array_object(obj, module_id)
        expected_master = parapet_master if module_id == MODULE_PARAPET else wall_master
        if expected_master:
            check(obj.data is expected_master.data, f"{obj.name} does not share wall master mesh")
        check(int(obj.get("array_count_x", 0)) == MAP_UNITS, f"{obj.name} is not 67 modules")
    if objects:
        check_group_bounds(objects, bottom, top, label)

facility_core_modules, facility_core_doors = check_module_collection(
    "03D_CORE_WALL_GRID_5M",
    52,
    2,
    "facility core",
)
combat_core_modules, combat_core_doors = check_module_collection(
    "05D_CORE_WALL_GRID_5M",
    52,
    2,
    "combat core",
)
facility_interior_modules, facility_interior_doors = check_module_collection(
    "03E_INTERIOR_WALL_GRID_5M",
    21,
    5,
    "facility interior",
)
combat_interior_modules, combat_interior_doors = check_module_collection(
    "05E_INTERIOR_WALL_GRID_5M",
    32,
    6,
    "combat interior",
)
roof_entry_modules, roof_entry_doors = check_module_collection(
    "01D_STAIR_ENTRY_WALL_GRID_5M",
    1,
    1,
    "rooftop stair entry",
)

for level, modules in (("FACILITY", facility_core_modules), ("COMBAT", combat_core_modules)):
    by_side = {
        side: sorted(
            int(obj.get("grid_index", -1))
            for obj in modules
            if obj.get("boundary_side") == side
        )
        for side in ("NORTH", "SOUTH", "EAST", "WEST")
    }
    for side, indices in by_side.items():
        check(indices == list(range(CORE_UNITS)), f"{level} core {side} grid is incomplete")

check(
    {door.get("connection_role") for door in facility_core_doors}
    == {"STAIR_UP_TO_ROOFTOP", "STAIR_DOWN_TO_COMBAT"},
    "facility core stair-door roles wrong",
)
check(
    {door.get("connection_role") for door in combat_core_doors}
    == {"STAIR_UP_TO_FACILITY", "RESERVED_RANDOM_STAIR_DOWN"},
    "combat core stair-door roles wrong",
)

generic_root = bpy.data.objects.get("Stair_Generic_Rotatable_ROOT")
special_root = bpy.data.objects.get("Stair_Special_Rooftop_ROOT")
check(generic_root is not None, "generic stair root missing")
check(special_root is not None, "special stair root missing")
if generic_root:
    check(
        (generic_root.location - Vector((CORE_HALF, 0.0, -9.0))).length <= 0.0001,
        "generic stair is not on 5m core boundary",
    )
if special_root:
    check(
        (special_root.location - Vector((-CORE_HALF, 0.0, 0.0))).length <= 0.0001,
        "special stair is not on 5m core boundary",
    )
    check(bool(special_root.get("special_wall_height_override")), "special wall override lost")

for prefix, root in (
    ("Stair_Generic_Rotatable_", generic_root),
    ("Stair_Special_Rooftop_", special_root),
):
    if root is None:
        continue
    assembly_objects = [obj for obj in bpy.data.objects if obj.name.startswith(prefix)]
    check(len(assembly_objects) >= 45, f"{prefix} lost stair geometry")
    for obj in assembly_objects:
        if obj is root:
            continue
        check(obj.parent is root, f"{obj.name} detached from stair root")

old_prefixes = (
    "Rooftop_Slab_",
    "Rooftop_OuterField_",
    "Rooftop_Exterior_Parapet_",
    "Facility_OuterField_",
    "Facility_Exterior_Wall_",
    "Facility_CoreFence_",
    "Facility_InteriorNorth_",
    "Facility_RightCorridor_",
    "Facility_SouthRoom_",
    "Combat_OuterField_",
    "Combat_Exterior_Wall_",
    "Combat_CoreFence_",
    "Combat_EastRooms_",
    "Combat_WestRooms_",
    "Combat_NorthRooms_",
    "Combat_SouthRooms_",
)
for obj in bpy.data.objects:
    check(not any(obj.name.startswith(prefix) for prefix in old_prefixes), f"old non-grid object remains: {obj.name}")
    if obj.type == "MESH":
        check(
            all(abs(float(scale) - 1.0) <= 0.0001 for scale in obj.scale),
            f"{obj.name} has non-unit scale {tuple(obj.scale)}",
        )
        check(not obj.name.endswith((".001", ".002", ".003")), f"{obj.name} has dirty suffix")

array_name_pattern = re.compile(r"^ASM_(ROOFTOP|FACILITY|COMBAT)_.+_ARRAY(?:_.+)?$")
for obj in bpy.data.objects:
    if obj.get("asset_role") == "MODULE_ARRAY_ASSEMBLY":
        check(bool(array_name_pattern.match(obj.name)), f"array name is not normalized: {obj.name}")

check(len(bpy.data.objects) <= 600, "modular review scene exceeds 600 object budget")
check(len(bpy.data.meshes) <= 140, "linked-module scene duplicates too many meshes")

if errors:
    print("QA_FAIL")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("QA_PASS")
print(f"OBJECTS={len(bpy.data.objects)}")
print(f"MESHES={len(bpy.data.meshes)}")
print("GRID_UNIT=5.000")
print("MAP_SIZE=335.000")
print("CORE_SIZE=65.000")
print("FLOOR_TILE_VIRTUAL_COUNT=13452")
print("OUTER_MODULE_VIRTUAL_COUNT=804")
print("ARRAY_OBJECTS=18")
print("EDITABLE_MODULE_INSTANCES=158")
print("DOOR_MODULES=16")
print("STAIR_COLLECTIONS=2")
