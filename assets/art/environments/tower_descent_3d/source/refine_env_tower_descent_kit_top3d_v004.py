"""Refine the user-edited v003 tower scene without rebuilding its stair geometry.

The script preserves the user's two stairwell designs, removes the measured
copy drift from the special rooftop variant, groups both stairwells under a
dedicated collection tree, adds core-edge connectors, and expands the empty
map footprint to five times the current core length and width.
"""

from pathlib import Path
import math

import bpy
from mathutils import Vector


PROJECT_ROOT = Path("/Users/summercards/ShellStorm2")
SOURCE_DIR = PROJECT_ROOT / "assets/art/environments/tower_descent_3d/source"
INPUT_BLEND = SOURCE_DIR / "env_tower_descent_kit_top3d_v003.blend"
OUTPUT_BLEND = SOURCE_DIR / "env_tower_descent_kit_top3d_v004.blend"

CORE_SIZE = 30.0 * math.sqrt(5.0)
CORE_HALF = CORE_SIZE * 0.5
ROOFTOP_CORE_SIZE = 50.0 * math.sqrt(5.0)
MAP_SIZE = CORE_SIZE * 5.0
FLOOR_HEIGHT = 9.0
SLAB_THICKNESS = 0.30
FENCE_HEIGHT = 1.20
FENCE_THICKNESS = 0.30
FENCE_OFFSET = 0.75
CONNECTOR_WIDTH = 6.0

ROOF_Z = 0.0
FACILITY_Z = -9.0
COMBAT_Z = -18.0

# The special copy was placed by rotating the generic stair 180 degrees, then
# accumulated this consistent manual translation drift.
SPECIAL_COPY_SIGNATURE = Vector((0.8029, 0.5218, 8.4016))
SPECIAL_IDEAL_SIGNATURE = Vector((0.0, 0.0, 9.0))
SPECIAL_ALIGNMENT_DELTA = SPECIAL_IDEAL_SIGNATURE - SPECIAL_COPY_SIGNATURE


def ensure_input_scene():
    if Path(bpy.data.filepath).resolve() != INPUT_BLEND.resolve():
        bpy.ops.wm.open_mainfile(filepath=str(INPUT_BLEND))


def move_collection_under(parent, child):
    scene_root = bpy.context.scene.collection
    if child.name in scene_root.children:
        scene_root.children.unlink(child)
    for collection in bpy.data.collections:
        if collection is parent:
            continue
        if child.name in collection.children and collection is not parent:
            collection.children.unlink(child)
    if child.name not in parent.children:
        parent.children.link(child)


def move_object_to_collection(obj, target):
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    target.objects.link(obj)


def set_parent_keep_world(obj, parent):
    world_matrix = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_parent_inverse.identity()
    obj.matrix_world = world_matrix


def add_box(name, location, dimensions, material, collection, bevel=0.04):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if material is not None:
        obj.data.materials.append(material)
    if bevel > 0.0:
        modifier = obj.modifiers.new("EdgeSoftening", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
    move_object_to_collection(obj, collection)
    return obj


def bounds_x(obj):
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return min(point.x for point in corners), max(point.x for point in corners)


def add_outer_ring(prefix, inner_size, elevation, material, collection):
    outer_half = MAP_SIZE * 0.5
    inner_half = inner_size * 0.5
    band = outer_half - inner_half
    z = elevation - SLAB_THICKNESS * 0.5
    panels = (
        (
            f"{prefix}_OuterField_West",
            (-(outer_half + inner_half) * 0.5, 0.0, z),
            (band, MAP_SIZE, SLAB_THICKNESS),
        ),
        (
            f"{prefix}_OuterField_East",
            ((outer_half + inner_half) * 0.5, 0.0, z),
            (band, MAP_SIZE, SLAB_THICKNESS),
        ),
        (
            f"{prefix}_OuterField_South",
            (0.0, -(outer_half + inner_half) * 0.5, z),
            (inner_size, band, SLAB_THICKNESS),
        ),
        (
            f"{prefix}_OuterField_North",
            (0.0, (outer_half + inner_half) * 0.5, z),
            (inner_size, band, SLAB_THICKNESS),
        ),
    )
    for name, location, dimensions in panels:
        panel = add_box(name, location, dimensions, material, collection, bevel=0.02)
        panel["asset_role"] = "EMPTY_EXPANSION_FIELD"
        panel["map_size_m"] = MAP_SIZE
        panel["preserved_inner_size_m"] = inner_size


def add_fence_segment(name, side, coordinate, start, end, elevation, collection, material):
    if end - start <= 0.001:
        return
    if side in {"EAST", "WEST"}:
        location = (coordinate, (start + end) * 0.5, elevation + FENCE_HEIGHT * 0.5)
        dimensions = (FENCE_THICKNESS, end - start, FENCE_HEIGHT)
    else:
        location = ((start + end) * 0.5, coordinate, elevation + FENCE_HEIGHT * 0.5)
        dimensions = (end - start, FENCE_THICKNESS, FENCE_HEIGHT)
    fence = add_box(name, location, dimensions, material, collection, bevel=0.025)
    fence["asset_role"] = "CORE_BOUNDARY_FENCE"
    fence["clearance_side"] = side


def add_core_fence(prefix, elevation, collection, material, east_open=None, west_open=None):
    fence_half = CORE_HALF + FENCE_OFFSET
    add_fence_segment(
        f"{prefix}_CoreFence_North",
        "NORTH",
        fence_half,
        -fence_half,
        fence_half,
        elevation,
        collection,
        material,
    )
    add_fence_segment(
        f"{prefix}_CoreFence_South",
        "SOUTH",
        -fence_half,
        -fence_half,
        fence_half,
        elevation,
        collection,
        material,
    )

    for side, coordinate, opening in (
        ("EAST", fence_half, east_open),
        ("WEST", -fence_half, west_open),
    ):
        intervals = [(-fence_half, fence_half)]
        if opening is not None:
            intervals = [(-fence_half, opening[0]), (opening[1], fence_half)]
        for index, (start, end) in enumerate(intervals, start=1):
            add_fence_segment(
                f"{prefix}_CoreFence_{side}_{index:02d}",
                side,
                coordinate,
                start,
                end,
                elevation,
                collection,
                material,
            )


def generic_name(old_name):
    tail = old_name.removeprefix("Stair_East_Facility_Combat_")
    explicit = {
        "UpperDoorLanding_Walkable": "UpperDoorLanding_Walkable",
        "UpperDoorLanding_Walkable.001": "LowerDoorLanding_Walkable",
        "EnclosureWall_01": "EnclosureWall_Outer",
        "EnclosureWall_02": "EnclosureWall_Far",
        "EnclosureWall_02.001": "EnclosureWall_DoorSide",
        "EnclosureWall_03": "EnclosureWall_Inner",
    }
    tail = explicit.get(tail, tail)
    return f"Stair_Generic_Rotatable_{tail}"


def special_name(old_name):
    tail = old_name.removeprefix("Stair_East_Facility_Combat_")
    explicit = {
        "UpperDoorLanding_Walkable.002": "UpperDoorLanding_Walkable",
        "UpperDoorLanding_Walkable.003": "LowerDoorLanding_Walkable",
        "EnclosureWall_01.001": "EnclosureWall_Outer",
        "EnclosureWall_02.002": "EnclosureWall_Far",
        "EnclosureWall_02.003": "EnclosureWall_DoorSide",
        "EnclosureWall_03.001": "EnclosureWall_Inner",
    }
    if tail in explicit:
        tail = explicit[tail]
    elif tail.endswith(".001"):
        tail = tail[:-4]
    return f"Stair_Special_Rooftop_{tail}"


def configure_root(root, upper_floor, lower_floor, special=False):
    root["asset_role"] = "STAIRWELL_ASSEMBLY_ROOT"
    root["variant"] = "SPECIAL_ROOFTOP" if special else "GENERIC_ROTATABLE"
    root["upper_floor"] = upper_floor
    root["lower_floor"] = lower_floor
    root["floor_delta_m"] = FLOOR_HEIGHT
    root["passage_width_m"] = CONNECTOR_WIDTH
    root["opening_forward_local"] = (1.0, 0.0, 0.0)
    root["rotation_reuse_step_deg"] = 90
    root["special_wall_height_override"] = bool(special)
    root["collision_contract"] = (
        "continuous walkable connector; child geometry moves only through assembly ROOT"
    )


ensure_input_scene()

scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0

special_collection = bpy.data.collections["02_STAIR_ROOF_TO_FACILITY"]
generic_collection = bpy.data.collections["04_STAIR_FACILITY_TO_COMBAT"]
special_collection.name = "02A_STAIR_SPECIAL_ROOFTOP_TO_FACILITY"
generic_collection.name = "02B_STAIR_GENERIC_ROTATABLE"

stair_parent = bpy.data.collections.get("02_STAIRWELLS")
if stair_parent is None:
    stair_parent = bpy.data.collections.new("02_STAIRWELLS")
    scene.collection.children.link(stair_parent)
move_collection_under(stair_parent, special_collection)
move_collection_under(stair_parent, generic_collection)
stair_parent["asset_role"] = "STAIRWELL_FOLDER"
special_collection["variant"] = "SPECIAL_ROOFTOP"
generic_collection["variant"] = "GENERIC_ROTATABLE"

# Separate the user's spatially duplicated west stair from the generic east
# stair, then remove only the measured global copy drift.
special_meshes = [
    obj
    for obj in list(generic_collection.objects)
    if obj.type == "MESH" and obj.location.x < -1.0
]
for obj in special_meshes:
    obj.location += SPECIAL_ALIGNMENT_DELTA
    move_object_to_collection(obj, special_collection)

# Snap the two hand-enlarged lower landings to the exact lower floor top.
generic_lower = bpy.data.objects.get(
    "Stair_East_Facility_Combat_UpperDoorLanding_Walkable.001"
)
special_lower = bpy.data.objects.get(
    "Stair_East_Facility_Combat_UpperDoorLanding_Walkable.003"
)
if generic_lower is not None:
    generic_lower.location.z = COMBAT_Z - SLAB_THICKNESS * 0.5
if special_lower is not None:
    special_lower.location.z = FACILITY_Z - SLAB_THICKNESS * 0.5

# Clean names after spatial separation. The special wall height overrides and
# the user's extra closing walls remain distinct objects.
for obj in sorted(list(generic_collection.objects), key=lambda item: item.name):
    if obj.name.startswith("Stair_East_Facility_Combat_") and obj.type == "MESH":
        obj.name = generic_name(obj.name)
        if obj.data:
            obj.data.name = f"{obj.name}_Mesh"
for obj in sorted(list(special_collection.objects), key=lambda item: item.name):
    if obj.name.startswith("Stair_East_Facility_Combat_") and obj.type == "MESH":
        obj.name = special_name(obj.name)
        if obj.data:
            obj.data.name = f"{obj.name}_Mesh"

generic_root = bpy.data.objects["Stair_East_Facility_Combat_ROOT"]
generic_upper_socket = bpy.data.objects["Stair_East_Facility_Combat_SOCKET_UPPER_DOOR"]
generic_lower_socket = bpy.data.objects["Stair_East_Facility_Combat_SOCKET_LOWER_DOOR"]
special_root = bpy.data.objects["Stair_West_Roof_Facility_ROOT"]
special_upper_socket = bpy.data.objects["Stair_West_Roof_Facility_SOCKET_UPPER_DOOR"]
special_lower_socket = bpy.data.objects["Stair_West_Roof_Facility_SOCKET_LOWER_DOOR"]

generic_root.name = "Stair_Generic_Rotatable_ROOT"
generic_upper_socket.name = "Stair_Generic_Rotatable_SOCKET_UPPER_DOOR"
generic_lower_socket.name = "Stair_Generic_Rotatable_SOCKET_LOWER_DOOR"
special_root.name = "Stair_Special_Rooftop_ROOT"
special_upper_socket.name = "Stair_Special_Rooftop_SOCKET_UPPER_DOOR"
special_lower_socket.name = "Stair_Special_Rooftop_SOCKET_LOWER_DOOR"

generic_root.location = (CORE_HALF, 0.0, FACILITY_Z)
generic_root.rotation_euler = (0.0, 0.0, 0.0)
special_root.location = (-CORE_HALF, 0.0, ROOF_Z)
special_root.rotation_euler = (0.0, 0.0, math.pi)
configure_root(generic_root, "FACILITY", "COMBAT", special=False)
configure_root(special_root, "ROOFTOP", "FACILITY", special=True)

for socket, parent, local_z in (
    (generic_upper_socket, generic_root, 0.0),
    (generic_lower_socket, generic_root, -FLOOR_HEIGHT),
    (special_upper_socket, special_root, 0.0),
    (special_lower_socket, special_root, -FLOOR_HEIGHT),
):
    socket.parent = parent
    socket.matrix_parent_inverse.identity()
    socket.location = (0.0, 0.0, local_z)
    socket.rotation_euler = (0.0, 0.0, 0.0)
    socket["asset_role"] = "STAIRWELL_DOOR_SOCKET"
    socket["opening_forward_local"] = (1.0, 0.0, 0.0)

landing_material = bpy.data.materials["MAT_Stair_Landing"]
structure_material = bpy.data.materials["MAT_Structure_DarkSteel"]
roof_material = bpy.data.materials["MAT_Rooftop"]
facility_material = bpy.data.materials["MAT_FacilityFloor"]
combat_material = bpy.data.materials["MAT_CombatFloor"]

# Fill only the short gap from the core door plane to each user-edited upper
# landing. The stair shape and opening turn remain unchanged.
generic_upper = bpy.data.objects["Stair_Generic_Rotatable_UpperDoorLanding_Walkable"]
special_upper = bpy.data.objects["Stair_Special_Rooftop_UpperDoorLanding_Walkable"]

bpy.context.view_layer.update()
generic_min_x, _ = bounds_x(generic_upper)
_, special_max_x = bounds_x(special_upper)
generic_connector_length = max(0.0, generic_min_x - CORE_HALF)
special_connector_length = max(0.0, -CORE_HALF - special_max_x)

generic_connector = add_box(
    "Stair_Generic_Rotatable_CoreConnector_Walkable",
    (
        CORE_HALF + generic_connector_length * 0.5,
        0.0,
        FACILITY_Z - SLAB_THICKNESS * 0.5,
    ),
    (generic_connector_length, CONNECTOR_WIDTH, SLAB_THICKNESS),
    landing_material,
    generic_collection,
    bevel=0.025,
)
special_connector = add_box(
    "Stair_Special_Rooftop_CoreConnector_Walkable",
    (
        -CORE_HALF - special_connector_length * 0.5,
        0.0,
        ROOF_Z - SLAB_THICKNESS * 0.5,
    ),
    (special_connector_length, CONNECTOR_WIDTH, SLAB_THICKNESS),
    landing_material,
    special_collection,
    bevel=0.025,
)
for connector in (generic_connector, special_connector):
    connector["asset_role"] = "CORE_EDGE_CONNECTOR"
    connector["clear_width_m"] = CONNECTOR_WIDTH

for prefix, connector, elevation, collection in (
    ("Stair_Generic_Rotatable", generic_connector, FACILITY_Z, generic_collection),
    ("Stair_Special_Rooftop", special_connector, ROOF_Z, special_collection),
):
    for side_name, side_sign in (("Left", -1.0), ("Right", 1.0)):
        guard = add_box(
            f"{prefix}_CoreConnector_Guard_{side_name}",
            (
                connector.location.x,
                side_sign * (CONNECTOR_WIDTH * 0.5 + FENCE_THICKNESS * 0.5),
                elevation + FENCE_HEIGHT * 0.5,
            ),
            (connector.dimensions.x, FENCE_THICKNESS, FENCE_HEIGHT),
            structure_material,
            collection,
            bevel=0.025,
        )
        guard["asset_role"] = "CONNECTOR_GUARD"

# Parent each complete stair assembly after all objects are in their final
# world positions. This makes the generic stair reusable by rotating its ROOT.
for obj in list(generic_collection.objects):
    if obj is not generic_root and obj.parent is None:
        set_parent_keep_world(obj, generic_root)
for obj in list(special_collection.objects):
    if obj is not special_root and obj.parent is None:
        set_parent_keep_world(obj, special_root)

roof_collection = bpy.data.collections["01_FLOOR_ROOFTOP_Z000"]
facility_collection = bpy.data.collections["03_FLOOR_FACILITY_ZNEG009"]
combat_collection = bpy.data.collections["05_FLOOR_COMBAT_ZNEG018"]

add_outer_ring(
    "Rooftop",
    ROOFTOP_CORE_SIZE,
    ROOF_Z,
    roof_material,
    roof_collection,
)
add_outer_ring(
    "Facility",
    CORE_SIZE,
    FACILITY_Z,
    facility_material,
    facility_collection,
)
add_outer_ring(
    "Combat",
    CORE_SIZE,
    COMBAT_Z,
    combat_material,
    combat_collection,
)

# Leave large, asymmetric fence openings exactly where the two stair volumes
# occupy the east and west sides of the preserved core.
add_core_fence(
    "Facility",
    FACILITY_Z,
    facility_collection,
    structure_material,
    east_open=(-8.0, 26.0),
    west_open=(-26.0, 8.0),
)
add_core_fence(
    "Combat",
    COMBAT_Z,
    combat_collection,
    structure_material,
    east_open=(-8.0, 26.0),
    west_open=None,
)

# Add a map-scale plan camera without replacing the existing core/detail views.
camera_collection = bpy.data.collections["90_LIGHTS_CAMERAS"]
map_camera_data = bpy.data.cameras.new("CAM_MapFootprintPlan_Data")
map_camera_data.type = "ORTHO"
map_camera_data.ortho_scale = MAP_SIZE * 1.08
map_camera = bpy.data.objects.new("CAM_MapFootprintPlan", map_camera_data)
camera_collection.objects.link(map_camera)
map_camera.location = (0.0, 0.0, 420.0)
map_camera.rotation_euler = (0.0, 0.0, 0.0)

scene["asset_id"] = "ENV-TOWER-DESCENT-KIT-3D"
scene["asset_version"] = "v004"
scene["user_edit_snapshot"] = str(INPUT_BLEND)
scene["map_footprint_size_m"] = MAP_SIZE
scene["map_footprint_scale_xy"] = 5.0
scene["functional_core_size_m"] = CORE_SIZE
scene["rooftop_preserved_size_m"] = ROOFTOP_CORE_SIZE
scene["stairwell_variants"] = ["SPECIAL_ROOFTOP", "GENERIC_ROTATABLE"]
scene["godot_integration_status"] = "NOT_IMPORTED_AWAITING_USER_APPROVAL"

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))

print(f"SAVED={OUTPUT_BLEND}")
print(f"MAP_SIZE={MAP_SIZE:.6f}")
print(f"CORE_SIZE={CORE_SIZE:.6f}")
print(
    "SPECIAL_ALIGNMENT_DELTA="
    f"({SPECIAL_ALIGNMENT_DELTA.x:.4f},"
    f"{SPECIAL_ALIGNMENT_DELTA.y:.4f},"
    f"{SPECIAL_ALIGNMENT_DELTA.z:.4f})"
)
