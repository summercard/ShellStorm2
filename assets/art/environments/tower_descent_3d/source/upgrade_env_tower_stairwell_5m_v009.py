"""Normalize both tower stairwell whiteboxes and save source v009.

The upper-door socket, both stair flights, turn landing, upper landing, guards,
and door sockets remain untouched.  Only the enclosure footprint and lower
landing are normalized:

- declared outer footprint: 15 x 30 m on the tower 5 m module grid;
- local footprint bounds: X 0..15 m, Y -2.5..27.5 m;
- the lower landing top moves from -9.0 m to -8.9 m to avoid a coplanar
  overlap with the lower floor; the upper landing remains unchanged.
"""

from pathlib import Path

import bpy


SOURCE_DIR = Path(__file__).resolve().parent
OUTPUT_BLEND = SOURCE_DIR / "env_tower_descent_kit_top3d_v009.blend"
ROOT_NAMES = (
    "Stair_Generic_Rotatable_ROOT",
    "Stair_Special_Rooftop_ROOT",
)
FOOTPRINT_MIN_X = 0.0
FOOTPRINT_MAX_X = 15.0
FOOTPRINT_MIN_Y = -2.5
FOOTPRINT_MAX_Y = 27.5
LOWER_SLAB_RAISE_M = 0.1
ENCLOSURE_BOTTOM_Z = -9.0
ENCLOSURE_TOP_Z = -0.1


def find_child(root, suffix):
    stack = list(root.children)
    while stack:
        obj = stack.pop()
        if obj.name.endswith(suffix):
            return obj
        stack.extend(obj.children)
    raise RuntimeError(f"Missing {suffix} below {root.name}")


def remap_axis_bounds(root, obj, axis, target_min, target_max):
    to_root = root.matrix_world.inverted() @ obj.matrix_world
    from_root = to_root.inverted()
    root_points = [to_root @ vertex.co for vertex in obj.data.vertices]
    source_values = [point[axis] for point in root_points]
    source_min = min(source_values)
    source_max = max(source_values)
    source_span = source_max - source_min
    if source_span <= 1.0e-6:
        raise RuntimeError(f"Degenerate axis {axis} on {obj.name}")
    for vertex, point in zip(obj.data.vertices, root_points):
        ratio = (point[axis] - source_min) / source_span
        point[axis] = target_min + ratio * (target_max - target_min)
        vertex.co = from_root @ point
    obj.data.update()


def translate_geometry_in_root(root, obj, axis, delta):
    to_root = root.matrix_world.inverted() @ obj.matrix_world
    from_root = to_root.inverted()
    for vertex in obj.data.vertices:
        point = to_root @ vertex.co
        point[axis] += delta
        vertex.co = from_root @ point
    obj.data.update()


for root_name in ROOT_NAMES:
    root = bpy.data.objects.get(root_name)
    if root is None:
        raise RuntimeError(f"Missing stairwell root: {root_name}")

    door_wall = find_child(root, "EnclosureWall_DoorSide")
    far_wall = find_child(root, "EnclosureWall_Far")
    inner_wall = find_child(root, "EnclosureWall_Inner")
    outer_wall = find_child(root, "EnclosureWall_Outer")
    lower_slab = find_child(root, "LowerDoorLanding_Walkable")
    upper_slab = find_child(root, "UpperDoorLanding_Walkable")

    # The two cross walls span the exact 15 m width. Their 0.3 m thickness is
    # kept inside the 30 m footprint.
    remap_axis_bounds(root, door_wall, 0, FOOTPRINT_MIN_X, FOOTPRINT_MAX_X)
    remap_axis_bounds(root, door_wall, 1, FOOTPRINT_MIN_Y, FOOTPRINT_MIN_Y + 0.3)
    remap_axis_bounds(root, far_wall, 0, FOOTPRINT_MIN_X, FOOTPRINT_MAX_X)
    remap_axis_bounds(root, far_wall, 1, FOOTPRINT_MAX_Y - 0.3, FOOTPRINT_MAX_Y)

    # Preserve the existing clear opening on the inner/core side, but extend
    # its far end to the normalized footprint. The outer wall retains its
    # original inner face so the unchanged upper landing cannot acquire a
    # narrow fall-through seam; only the exterior face reaches X=15 m.
    inner_to_root = root.matrix_world.inverted() @ inner_wall.matrix_world
    inner_points = [inner_to_root @ vertex.co for vertex in inner_wall.data.vertices]
    inner_start_y = min(point.y for point in inner_points)
    remap_axis_bounds(root, inner_wall, 0, FOOTPRINT_MIN_X, FOOTPRINT_MIN_X + 0.3)
    remap_axis_bounds(root, inner_wall, 1, inner_start_y, FOOTPRINT_MAX_Y)

    outer_to_root = root.matrix_world.inverted() @ outer_wall.matrix_world
    outer_points = [outer_to_root @ vertex.co for vertex in outer_wall.data.vertices]
    outer_inner_x = min(point.x for point in outer_points)
    remap_axis_bounds(root, outer_wall, 0, outer_inner_x, FOOTPRINT_MAX_X)
    remap_axis_bounds(root, outer_wall, 1, FOOTPRINT_MIN_Y, FOOTPRINT_MAX_Y)

    # Stairwell enclosure is one 9 m storey, with the same 0.1 m top visual
    # clearance as every other tower wall. Historical source transforms had
    # stretched these walls above the upper floor, so normalize geometry here.
    for wall in (door_wall, far_wall, inner_wall, outer_wall):
        remap_axis_bounds(root, wall, 2, ENCLOSURE_BOTTOM_Z, ENCLOSURE_TOP_Z)
        wall["logical_height_m"] = 9.0
        wall["visual_height_m"] = 8.9
        wall["visual_top_clearance_m"] = 0.1

    # Lower landing owns the normalized 15 x 30 m base and is the only slab
    # raised. The upper landing is deliberately read-only in this migration.
    remap_axis_bounds(root, lower_slab, 0, FOOTPRINT_MIN_X, FOOTPRINT_MAX_X)
    remap_axis_bounds(root, lower_slab, 1, FOOTPRINT_MIN_Y, FOOTPRINT_MAX_Y)
    translate_geometry_in_root(root, lower_slab, 2, LOWER_SLAB_RAISE_M)

    root["grid_unit_m"] = 5.0
    root["footprint_size_m"] = [15.0, 30.0]
    root["footprint_min_local_xy_m"] = [FOOTPRINT_MIN_X, FOOTPRINT_MIN_Y]
    root["footprint_max_local_xy_m"] = [FOOTPRINT_MAX_X, FOOTPRINT_MAX_Y]
    root["lower_landing_top_m"] = -8.9
    root["lower_landing_floor_clearance_m"] = LOWER_SLAB_RAISE_M
    root["enclosure_visual_z_range_m"] = [ENCLOSURE_BOTTOM_Z, ENCLOSURE_TOP_Z]
    root["upper_landing_unchanged_from_v008"] = True
    upper_slab["source_geometry_unchanged_from_v008"] = True
    lower_slab["lower_floor_visual_clearance_m"] = LOWER_SLAB_RAISE_M

scene = bpy.context.scene
scene["asset_version"] = "v009"
scene["stairwell_grid_unit_m"] = 5.0
scene["stairwell_footprint_size_m"] = [15.0, 30.0]
scene["stairwell_lower_landing_raise_m"] = LOWER_SLAB_RAISE_M
scene["derived_from"] = str(
    SOURCE_DIR / "env_tower_descent_kit_top3d_v008.blend"
)

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
print(f"STAIRWELL_5M_SOURCE_OK output={OUTPUT_BLEND}")
