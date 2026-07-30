"""QA checks for the v005 full-footprint tower enclosure."""

from pathlib import Path
import math

import bpy
from mathutils import Vector


SOURCE_DIR = Path(__file__).resolve().parent
EXPECTED_BLEND = SOURCE_DIR / "env_tower_descent_kit_top3d_v005.blend"
CORE_SIZE = 30.0 * math.sqrt(5.0)
CORE_HALF = CORE_SIZE * 0.5
MAP_SIZE = CORE_SIZE * 5.0
MAP_HALF = MAP_SIZE * 0.5
FLOOR_HEIGHT = 9.0
WALL_THICKNESS = 0.30
EPSILON = 0.011

OLD_EXTERIOR_NAMES = {
    "Rooftop_Parapet_East_End",
    "Rooftop_Parapet_North_End",
    "Rooftop_Parapet_South_End",
    "Rooftop_Parapet_West_01",
    "Rooftop_Parapet_West_End",
    "Facility_East_Wall_00A",
    "Facility_East_Wall_End",
    "Facility_North_Wall_End",
    "Facility_South_Wall_End",
    "Facility_West_Wall_00A",
    "Facility_West_Wall_End",
    "Combat_East_Wall_00A",
    "Combat_East_Wall_End",
    "Combat_North_Wall_End",
    "Combat_South_Wall_End",
    "Combat_West_Wall_End",
}

errors = []


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


def check_perimeter(prefix, expected_floor_z, expected_top_z, expected_role):
    objects = [
        bpy.data.objects.get(f"{prefix}_{side}")
        for side in ("North", "South", "East", "West")
    ]
    check(all(obj is not None for obj in objects), f"{prefix} is missing a side")
    objects = [obj for obj in objects if obj is not None]
    if len(objects) != 4:
        return []

    group_min = Vector(
        (
            min(bounds(obj)[0].x for obj in objects),
            min(bounds(obj)[0].y for obj in objects),
            min(bounds(obj)[0].z for obj in objects),
        )
    )
    group_max = Vector(
        (
            max(bounds(obj)[1].x for obj in objects),
            max(bounds(obj)[1].y for obj in objects),
            max(bounds(obj)[1].z for obj in objects),
        )
    )
    check(abs(group_min.x + MAP_HALF) <= EPSILON, f"{prefix} west edge is wrong")
    check(abs(group_min.y + MAP_HALF) <= EPSILON, f"{prefix} south edge is wrong")
    check(abs(group_max.x - MAP_HALF) <= EPSILON, f"{prefix} east edge is wrong")
    check(abs(group_max.y - MAP_HALF) <= EPSILON, f"{prefix} north edge is wrong")
    check(abs(group_min.z - expected_floor_z) <= EPSILON, f"{prefix} bottom Z is wrong")
    check(abs(group_max.z - expected_top_z) <= EPSILON, f"{prefix} top Z is wrong")

    for obj in objects:
        check(obj.get("asset_role") == expected_role, f"{obj.name} role is wrong")
        check(
            abs(float(obj["map_size_m"]) - MAP_SIZE) <= 0.0001,
            f"{obj.name} map size metadata is wrong",
        )
        check(
            abs(float(obj["wall_thickness_m"]) - WALL_THICKNESS) <= 0.0001,
            f"{obj.name} thickness metadata is wrong",
        )
    return objects


check(Path(bpy.data.filepath).resolve() == EXPECTED_BLEND.resolve(), "wrong blend path")
scene = bpy.context.scene
check(scene.unit_settings.system == "METRIC", "scene is not metric")
check(scene.get("asset_version") == "v005", "scene version is not v005")
check(bool(scene.get("exterior_shell_matches_floor_footprint")), "shell metadata is false")
check(
    abs(float(scene["map_footprint_size_m"]) - MAP_SIZE) <= 0.0001,
    "scene map footprint metadata is wrong",
)

for name in OLD_EXTERIOR_NAMES:
    check(bpy.data.objects.get(name) is None, f"old core exterior remains: {name}")

required_children = {
    "01_FLOOR_ROOFTOP_Z000": "01A_EXTERIOR_ROOFTOP_FULL_FOOTPRINT",
    "03_FLOOR_FACILITY_ZNEG009": "03A_EXTERIOR_FACILITY_FULL_FOOTPRINT",
    "05_FLOOR_COMBAT_ZNEG018": "05A_EXTERIOR_COMBAT_FULL_FOOTPRINT",
}
for parent_name, child_name in required_children.items():
    parent = bpy.data.collections.get(parent_name)
    child = bpy.data.collections.get(child_name)
    check(parent is not None, f"missing parent collection {parent_name}")
    check(child is not None, f"missing exterior collection {child_name}")
    if parent and child:
        check(child_name in parent.children, f"{child_name} is not under {parent_name}")

rooftop = check_perimeter(
    "Rooftop_Exterior_Parapet",
    0.0,
    1.5,
    "FULL_FOOTPRINT_ROOFTOP_PARAPET",
)
facility = check_perimeter(
    "Facility_Exterior_Wall",
    -9.0,
    0.0,
    "FULL_FOOTPRINT_EXTERIOR_WALL",
)
combat = check_perimeter(
    "Combat_Exterior_Wall",
    -18.0,
    -9.0,
    "FULL_FOOTPRINT_EXTERIOR_WALL",
)

exterior_objects = rooftop + facility + combat
check(len(exterior_objects) == 12, "expected exactly 12 full-footprint exterior pieces")

outer_panels = [
    obj for obj in bpy.data.objects if obj.get("asset_role") == "EMPTY_EXPANSION_FIELD"
]
check(len(outer_panels) == 12, "expected 12 outer floor panels")
for level_prefix in ("Rooftop", "Facility", "Combat"):
    panels = [obj for obj in outer_panels if obj.name.startswith(level_prefix)]
    check(len(panels) == 4, f"{level_prefix} does not have four outer panels")
    if panels:
        min_x = min(bounds(obj)[0].x for obj in panels)
        min_y = min(bounds(obj)[0].y for obj in panels)
        max_x = max(bounds(obj)[1].x for obj in panels)
        max_y = max(bounds(obj)[1].y for obj in panels)
        check(abs(min_x + MAP_HALF) <= EPSILON, f"{level_prefix} floor west edge wrong")
        check(abs(min_y + MAP_HALF) <= EPSILON, f"{level_prefix} floor south edge wrong")
        check(abs(max_x - MAP_HALF) <= EPSILON, f"{level_prefix} floor east edge wrong")
        check(abs(max_y - MAP_HALF) <= EPSILON, f"{level_prefix} floor north edge wrong")

facility_slab = bpy.data.objects.get("Facility_Slab")
combat_slab = bpy.data.objects.get("Combat_Slab")
check(facility_slab is not None, "facility core slab missing")
check(combat_slab is not None, "combat core slab missing")
if facility_slab:
    check(abs(facility_slab.dimensions.x - CORE_SIZE) <= 0.001, "facility core resized")
    check(abs(facility_slab.dimensions.y - CORE_SIZE) <= 0.001, "facility core resized")
if combat_slab:
    check(abs(combat_slab.dimensions.x - CORE_SIZE) <= 0.001, "combat core resized")
    check(abs(combat_slab.dimensions.y - CORE_SIZE) <= 0.001, "combat core resized")

generic_root = bpy.data.objects.get("Stair_Generic_Rotatable_ROOT")
special_root = bpy.data.objects.get("Stair_Special_Rooftop_ROOT")
check(generic_root is not None, "generic stair root missing")
check(special_root is not None, "special stair root missing")
if generic_root:
    check(
        (generic_root.location - Vector((CORE_HALF, 0.0, -9.0))).length <= 0.0001,
        "generic stair root moved",
    )
    check(generic_root.get("variant") == "GENERIC_ROTATABLE", "generic metadata lost")
if special_root:
    check(
        (special_root.location - Vector((-CORE_HALF, 0.0, 0.0))).length <= 0.0001,
        "special stair root moved",
    )
    check(special_root.get("variant") == "SPECIAL_ROOFTOP", "special metadata lost")
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
        check(obj.parent is root, f"{obj.name} detached from its stair root")

for connector_name, expected_top in (
    ("Stair_Special_Rooftop_CoreConnector_Walkable", 0.0),
    ("Stair_Generic_Rotatable_CoreConnector_Walkable", -9.0),
):
    connector = bpy.data.objects.get(connector_name)
    check(connector is not None, f"{connector_name} missing")
    if connector:
        check(abs(bounds(connector)[1].z - expected_top) <= EPSILON, f"{connector_name} Z moved")

fences = [
    obj for obj in bpy.data.objects if obj.get("asset_role") == "CORE_BOUNDARY_FENCE"
]
check(len(fences) >= 10, "core fence is incomplete")
for fence in fences:
    fence_min, fence_max = bounds(fence)
    check(
        fence_min.x > -MAP_HALF and fence_max.x < MAP_HALF,
        f"{fence.name} no longer describes the inner core",
    )
    check(
        fence_min.y > -MAP_HALF and fence_max.y < MAP_HALF,
        f"{fence.name} no longer describes the inner core",
    )

for obj in bpy.data.objects:
    if obj.type != "MESH":
        continue
    check(
        all(abs(float(scale) - 1.0) <= 0.0001 for scale in obj.scale),
        f"{obj.name} has unapplied scale {tuple(obj.scale)}",
    )
    check(not obj.name.endswith((".001", ".002", ".003")), f"{obj.name} has dirty suffix")

if errors:
    print("QA_FAIL")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("QA_PASS")
print(f"OBJECTS={len(bpy.data.objects)}")
print(f"MESHES={sum(obj.type == 'MESH' for obj in bpy.data.objects)}")
print(f"MAP_SIZE={MAP_SIZE:.6f}")
print(f"EXTERIOR_BOUNDARY=+/-{MAP_HALF:.6f}")
print(f"FULL_FOOTPRINT_EXTERIOR_PIECES={len(exterior_objects)}")
print(f"OUTER_FIELD_PANELS={len(outer_panels)}")
print(f"CORE_FENCES={len(fences)}")
print("STAIR_COLLECTIONS=2")
