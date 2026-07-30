"""QA checks for the refined v004 tower Blender source."""

from pathlib import Path
import math

import bpy
from mathutils import Vector


SOURCE_DIR = Path(__file__).resolve().parent
EXPECTED_BLEND = SOURCE_DIR / "env_tower_descent_kit_top3d_v004.blend"
CORE_SIZE = 30.0 * math.sqrt(5.0)
CORE_HALF = CORE_SIZE * 0.5
MAP_SIZE = CORE_SIZE * 5.0
MAP_HALF = MAP_SIZE * 0.5
EPSILON = 0.011


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


check(Path(bpy.data.filepath).resolve() == EXPECTED_BLEND.resolve(), "wrong blend path")
check(bpy.context.scene.unit_settings.system == "METRIC", "scene is not metric")
check(
    abs(float(bpy.context.scene["map_footprint_size_m"]) - MAP_SIZE) <= 0.0001,
    "scene map footprint metadata is wrong",
)

required_top_level = {
    "00_BUILDING_GUIDES",
    "01_FLOOR_ROOFTOP_Z000",
    "02_STAIRWELLS",
    "03_FLOOR_FACILITY_ZNEG009",
    "05_FLOOR_COMBAT_ZNEG018",
    "90_LIGHTS_CAMERAS",
}
top_level = {collection.name for collection in bpy.context.scene.collection.children}
check(required_top_level <= top_level, "missing required top-level collection")

stair_parent = bpy.data.collections.get("02_STAIRWELLS")
special_collection = bpy.data.collections.get("02A_STAIR_SPECIAL_ROOFTOP_TO_FACILITY")
generic_collection = bpy.data.collections.get("02B_STAIR_GENERIC_ROTATABLE")
check(stair_parent is not None, "missing stairwell parent collection")
check(special_collection is not None, "missing special stair collection")
check(generic_collection is not None, "missing generic stair collection")
if stair_parent and special_collection and generic_collection:
    child_names = {collection.name for collection in stair_parent.children}
    check(
        child_names
        == {
            "02A_STAIR_SPECIAL_ROOFTOP_TO_FACILITY",
            "02B_STAIR_GENERIC_ROTATABLE",
        },
        "stairwell folder children are not exact",
    )
    check(special_collection.name not in top_level, "special stair is still top-level")
    check(generic_collection.name not in top_level, "generic stair is still top-level")

generic_root = bpy.data.objects.get("Stair_Generic_Rotatable_ROOT")
special_root = bpy.data.objects.get("Stair_Special_Rooftop_ROOT")
check(generic_root is not None, "missing generic stair root")
check(special_root is not None, "missing special stair root")

if generic_root:
    check(
        (generic_root.location - Vector((CORE_HALF, 0.0, -9.0))).length <= 0.0001,
        "generic root is not on the east core edge",
    )
    check(abs(generic_root.rotation_euler.z) <= 0.0001, "generic root has drifted yaw")
    check(generic_root["variant"] == "GENERIC_ROTATABLE", "generic variant metadata wrong")
if special_root:
    check(
        (special_root.location - Vector((-CORE_HALF, 0.0, 0.0))).length <= 0.0001,
        "special root is not on the west core edge",
    )
    check(
        abs((special_root.rotation_euler.z % math.tau) - math.pi) <= 0.0001,
        "special root is not rotated 180 degrees",
    )
    check(special_root["variant"] == "SPECIAL_ROOFTOP", "special variant metadata wrong")
    check(bool(special_root["special_wall_height_override"]), "special wall override is lost")

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
        check(obj.parent is root, f"{obj.name} is not parented to its assembly root")

for prefix, expected_world in (
    ("Stair_Generic_Rotatable", (CORE_HALF, 0.0, -9.0)),
    ("Stair_Special_Rooftop", (-CORE_HALF, 0.0, 0.0)),
):
    upper = bpy.data.objects.get(f"{prefix}_SOCKET_UPPER_DOOR")
    lower = bpy.data.objects.get(f"{prefix}_SOCKET_LOWER_DOOR")
    check(upper is not None, f"{prefix} upper socket missing")
    check(lower is not None, f"{prefix} lower socket missing")
    if upper:
        check(
            (upper.matrix_world.translation - Vector(expected_world)).length <= 0.0001,
            f"{prefix} upper socket world position wrong",
        )
    if lower:
        expected_lower = Vector((expected_world[0], expected_world[1], expected_world[2] - 9.0))
        check(
            (lower.matrix_world.translation - expected_lower).length <= 0.0001,
            f"{prefix} lower socket world position wrong",
        )

for obj in bpy.data.objects:
    if obj.type != "MESH":
        continue
    check(
        all(abs(float(scale) - 1.0) <= 0.0001 for scale in obj.scale),
        f"{obj.name} has unapplied or negative scale {tuple(obj.scale)}",
    )
    check(not obj.name.endswith((".001", ".002", ".003")), f"{obj.name} has dirty duplicate suffix")

outer_panels = [
    obj
    for obj in bpy.data.objects
    if obj.get("asset_role") == "EMPTY_EXPANSION_FIELD"
]
check(len(outer_panels) == 12, "expected 12 outer-field panels")
for level_prefix in ("Rooftop", "Facility", "Combat"):
    panels = [obj for obj in outer_panels if obj.name.startswith(level_prefix)]
    check(len(panels) == 4, f"{level_prefix} does not have four outer panels")
    if panels:
        level_min = Vector(
            (
                min(bounds(obj)[0].x for obj in panels),
                min(bounds(obj)[0].y for obj in panels),
                0.0,
            )
        )
        level_max = Vector(
            (
                max(bounds(obj)[1].x for obj in panels),
                max(bounds(obj)[1].y for obj in panels),
                0.0,
            )
        )
        check(abs(level_min.x + MAP_HALF) <= 0.001, f"{level_prefix} west footprint wrong")
        check(abs(level_min.y + MAP_HALF) <= 0.001, f"{level_prefix} south footprint wrong")
        check(abs(level_max.x - MAP_HALF) <= 0.001, f"{level_prefix} east footprint wrong")
        check(abs(level_max.y - MAP_HALF) <= 0.001, f"{level_prefix} north footprint wrong")

facility_slab = bpy.data.objects.get("Facility_Slab")
combat_slab = bpy.data.objects.get("Combat_Slab")
check(facility_slab is not None, "facility core slab missing")
check(combat_slab is not None, "combat core slab missing")
if facility_slab:
    check(abs(facility_slab.dimensions.x - CORE_SIZE) <= 0.001, "facility core was resized")
    check(abs(facility_slab.dimensions.y - CORE_SIZE) <= 0.001, "facility core was resized")
if combat_slab:
    check(abs(combat_slab.dimensions.x - CORE_SIZE) <= 0.001, "combat core was resized")
    check(abs(combat_slab.dimensions.y - CORE_SIZE) <= 0.001, "combat core was resized")

generic_connector = bpy.data.objects.get(
    "Stair_Generic_Rotatable_CoreConnector_Walkable"
)
special_connector = bpy.data.objects.get("Stair_Special_Rooftop_CoreConnector_Walkable")
generic_upper = bpy.data.objects.get(
    "Stair_Generic_Rotatable_UpperDoorLanding_Walkable"
)
special_upper = bpy.data.objects.get("Stair_Special_Rooftop_UpperDoorLanding_Walkable")
check(generic_connector is not None, "generic connector missing")
check(special_connector is not None, "special connector missing")
if generic_connector and generic_upper:
    connector_bounds = bounds(generic_connector)
    landing_bounds = bounds(generic_upper)
    check(abs(connector_bounds[0].x - CORE_HALF) <= EPSILON, "generic connector misses core edge")
    check(
        abs(connector_bounds[1].x - landing_bounds[0].x) <= EPSILON,
        "generic connector misses upper landing",
    )
    check(abs(connector_bounds[1].z + 9.0) <= EPSILON, "generic connector top is off floor")
if special_connector and special_upper:
    connector_bounds = bounds(special_connector)
    landing_bounds = bounds(special_upper)
    check(abs(connector_bounds[1].x + CORE_HALF) <= EPSILON, "special connector misses core edge")
    check(
        abs(connector_bounds[0].x - landing_bounds[1].x) <= EPSILON,
        "special connector misses upper landing",
    )
    check(abs(connector_bounds[1].z) <= EPSILON, "special connector top is off roof")

generic_lower = bpy.data.objects.get(
    "Stair_Generic_Rotatable_LowerDoorLanding_Walkable"
)
special_lower = bpy.data.objects.get("Stair_Special_Rooftop_LowerDoorLanding_Walkable")
if generic_lower:
    generic_lower_bounds = bounds(generic_lower)
    check(generic_lower_bounds[0].x <= CORE_HALF + EPSILON, "generic lower landing misses core")
    check(abs(generic_lower_bounds[1].z + 18.0) <= EPSILON, "generic lower landing top is off combat")
if special_lower:
    special_lower_bounds = bounds(special_lower)
    check(special_lower_bounds[1].x >= -CORE_HALF - EPSILON, "special lower landing misses core")
    check(abs(special_lower_bounds[1].z + 9.0) <= EPSILON, "special lower landing top is off facility")

generic_outer_wall = bpy.data.objects.get("Stair_Generic_Rotatable_EnclosureWall_Outer")
special_outer_wall = bpy.data.objects.get("Stair_Special_Rooftop_EnclosureWall_Outer")
if generic_outer_wall and special_outer_wall:
    check(
        abs(generic_outer_wall.dimensions.z - special_outer_wall.dimensions.z) >= 1.0,
        "special rooftop wall-height design was flattened",
    )

fences = [
    obj for obj in bpy.data.objects if obj.get("asset_role") == "CORE_BOUNDARY_FENCE"
]
check(len(fences) >= 10, "core fence is incomplete")
for fence in fences:
    check(
        abs(max(bounds(fence)[0].x, -MAP_HALF)) <= MAP_HALF + EPSILON,
        f"{fence.name} exceeds map footprint",
    )

if errors:
    print("QA_FAIL")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("QA_PASS")
print(f"OBJECTS={len(bpy.data.objects)}")
print(f"MESHES={sum(obj.type == 'MESH' for obj in bpy.data.objects)}")
print(f"MAP_SIZE={MAP_SIZE:.6f}")
print(f"CORE_SIZE={CORE_SIZE:.6f}")
print("STAIR_COLLECTIONS=2")
print("OUTER_FIELD_PANELS=12")
print(f"CORE_FENCES={len(fences)}")
