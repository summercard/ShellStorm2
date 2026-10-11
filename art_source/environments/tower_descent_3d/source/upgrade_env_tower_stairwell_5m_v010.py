"""Build clean v010 stairwell source from v008 without shared-mesh cross-talk.

The v009 migration modified linked mesh datablocks twice: once through the
generic root and once through the rooftop root.  That stretched the four
enclosure walls and left a duplicate far wall in the saved source.  This
migration starts from the last clean source (v008), makes every edited mesh
single-user, then applies the approved 15 x 30 m / 9 m-storey contract.
"""

from pathlib import Path

import bpy


SOURCE_DIR = Path(__file__).resolve().parent
OUTPUT_BLEND = SOURCE_DIR / "env_tower_descent_kit_top3d_v010.blend"
ROOT_NAMES = (
    "Stair_Generic_Rotatable_ROOT",
    "Stair_Special_Rooftop_ROOT",
)
WALL_SUFFIXES = (
    "EnclosureWall_DoorSide",
    "EnclosureWall_Far",
    "EnclosureWall_Inner",
    "EnclosureWall_Outer",
)
FOOTPRINT_MIN_X = 0.0
FOOTPRINT_MAX_X = 15.0
FOOTPRINT_MIN_Y = -2.5
FOOTPRINT_MAX_Y = 27.5
LOWER_SLAB_RAISE_M = 0.1
ENCLOSURE_BOTTOM_Z = -9.0
ENCLOSURE_TOP_Z = -0.1
EPSILON = 1.0e-4


def descendants(root):
    result = []
    stack = list(root.children)
    while stack:
        obj = stack.pop()
        result.append(obj)
        stack.extend(obj.children)
    return result


def unique_child(root, suffix):
    matches = [obj for obj in descendants(root) if obj.name.endswith(suffix)]
    if len(matches) != 1:
        raise RuntimeError(
            f"Expected one {suffix} below {root.name}, got "
            f"{[obj.name for obj in matches]}"
        )
    return matches[0]


def root_points(root, obj):
    to_root = root.matrix_world.inverted() @ obj.matrix_world
    return to_root, [to_root @ vertex.co for vertex in obj.data.vertices]


def remap_axis_bounds(root, obj, axis, target_min, target_max):
    to_root, points = root_points(root, obj)
    from_root = to_root.inverted()
    values = [point[axis] for point in points]
    source_min = min(values)
    source_max = max(values)
    source_span = source_max - source_min
    if source_span <= 1.0e-6:
        raise RuntimeError(f"Degenerate axis {axis} on {obj.name}")
    for vertex, point in zip(obj.data.vertices, points):
        ratio = (point[axis] - source_min) / source_span
        point[axis] = target_min + ratio * (target_max - target_min)
        vertex.co = from_root @ point
    obj.data.update()


def translate_geometry_in_root(root, obj, axis, delta):
    to_root, points = root_points(root, obj)
    from_root = to_root.inverted()
    for vertex, point in zip(obj.data.vertices, points):
        point[axis] += delta
        vertex.co = from_root @ point
    obj.data.update()


def axis_bounds(root, obj, axis):
    _, points = root_points(root, obj)
    values = [point[axis] for point in points]
    return min(values), max(values)


def assert_bounds(root, obj, axis, expected_min, expected_max):
    actual_min, actual_max = axis_bounds(root, obj, axis)
    if abs(actual_min - expected_min) > EPSILON or abs(actual_max - expected_max) > EPSILON:
        raise RuntimeError(
            f"{obj.name} axis {axis} bounds {actual_min:.6f}..{actual_max:.6f} "
            f"!= {expected_min:.6f}..{expected_max:.6f}"
        )


for root_name in ROOT_NAMES:
    root = bpy.data.objects.get(root_name)
    if root is None:
        raise RuntimeError(f"Missing stairwell root: {root_name}")

    walls = {suffix: unique_child(root, suffix) for suffix in WALL_SUFFIXES}
    lower_slab = unique_child(root, "LowerDoorLanding_Walkable")
    upper_slab = unique_child(root, "UpperDoorLanding_Walkable")

    # The v008 generic and rooftop variants share mesh datablocks.  Every
    # edited object must own its data before either variant is modified.
    for obj in [*walls.values(), lower_slab]:
        obj.data = obj.data.copy()

    door_wall = walls["EnclosureWall_DoorSide"]
    far_wall = walls["EnclosureWall_Far"]
    inner_wall = walls["EnclosureWall_Inner"]
    outer_wall = walls["EnclosureWall_Outer"]

    remap_axis_bounds(root, door_wall, 0, FOOTPRINT_MIN_X, FOOTPRINT_MAX_X)
    remap_axis_bounds(root, door_wall, 1, FOOTPRINT_MIN_Y, FOOTPRINT_MIN_Y + 0.3)
    remap_axis_bounds(root, far_wall, 0, FOOTPRINT_MIN_X, FOOTPRINT_MAX_X)
    remap_axis_bounds(root, far_wall, 1, FOOTPRINT_MAX_Y - 0.3, FOOTPRINT_MAX_Y)

    inner_start_y, _ = axis_bounds(root, inner_wall, 1)
    remap_axis_bounds(root, inner_wall, 0, FOOTPRINT_MIN_X, FOOTPRINT_MIN_X + 0.3)
    remap_axis_bounds(root, inner_wall, 1, inner_start_y, FOOTPRINT_MAX_Y)

    outer_inner_x, _ = axis_bounds(root, outer_wall, 0)
    remap_axis_bounds(root, outer_wall, 0, outer_inner_x, FOOTPRINT_MAX_X)
    remap_axis_bounds(root, outer_wall, 1, FOOTPRINT_MIN_Y, FOOTPRINT_MAX_Y)

    for wall in walls.values():
        remap_axis_bounds(root, wall, 2, ENCLOSURE_BOTTOM_Z, ENCLOSURE_TOP_Z)
        wall["logical_height_m"] = 9.0
        wall["visual_height_m"] = 8.9
        wall["visual_top_clearance_m"] = 0.1
        assert_bounds(root, wall, 2, ENCLOSURE_BOTTOM_Z, ENCLOSURE_TOP_Z)

    remap_axis_bounds(root, lower_slab, 0, FOOTPRINT_MIN_X, FOOTPRINT_MAX_X)
    remap_axis_bounds(root, lower_slab, 1, FOOTPRINT_MIN_Y, FOOTPRINT_MAX_Y)
    translate_geometry_in_root(root, lower_slab, 2, LOWER_SLAB_RAISE_M)
    assert_bounds(root, lower_slab, 0, FOOTPRINT_MIN_X, FOOTPRINT_MAX_X)
    assert_bounds(root, lower_slab, 1, FOOTPRINT_MIN_Y, FOOTPRINT_MAX_Y)
    _, lower_top = axis_bounds(root, lower_slab, 2)
    if abs(lower_top + 8.9) > EPSILON:
        raise RuntimeError(f"{lower_slab.name} top is {lower_top:.6f}, expected -8.9")
    _, upper_top = axis_bounds(root, upper_slab, 2)
    if abs(upper_top) > EPSILON:
        raise RuntimeError(f"{upper_slab.name} changed, top is {upper_top:.6f}")

    root["grid_unit_m"] = 5.0
    root["footprint_size_m"] = [15.0, 30.0]
    root["footprint_min_local_xy_m"] = [FOOTPRINT_MIN_X, FOOTPRINT_MIN_Y]
    root["footprint_max_local_xy_m"] = [FOOTPRINT_MAX_X, FOOTPRINT_MAX_Y]
    root["lower_landing_top_m"] = -8.9
    root["lower_landing_floor_clearance_m"] = LOWER_SLAB_RAISE_M
    root["enclosure_visual_z_range_m"] = [ENCLOSURE_BOTTOM_Z, ENCLOSURE_TOP_Z]
    root["upper_landing_unchanged_from_v008"] = True
    root["linked_mesh_cross_talk_fixed"] = True
    upper_slab["source_geometry_unchanged_from_v008"] = True
    lower_slab["lower_floor_visual_clearance_m"] = LOWER_SLAB_RAISE_M

scene = bpy.context.scene
scene["asset_version"] = "v010"
scene["stairwell_grid_unit_m"] = 5.0
scene["stairwell_footprint_size_m"] = [15.0, 30.0]
scene["stairwell_lower_landing_raise_m"] = LOWER_SLAB_RAISE_M
scene["derived_from"] = str(SOURCE_DIR / "env_tower_descent_kit_top3d_v008.blend")
scene["repair_note"] = "single-user stair meshes; exactly four 8.9m enclosure walls"

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
print(f"STAIRWELL_V010_SOURCE_OK output={OUTPUT_BLEND}")
