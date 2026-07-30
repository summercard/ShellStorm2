import bpy
import math
from pathlib import Path
from mathutils import Vector


PROJECT_ROOT = Path("/Users/summercards/ShellStorm2")
SOURCE_DIR = PROJECT_ROOT / "assets/art/environments/tower_descent_3d/source"
OUTPUT_DIR = PROJECT_ROOT / "outputs/019facd3-bb17-7462-8504-0210c0919463/previews"
BLEND_PATH = SOURCE_DIR / "env_tower_descent_kit_top3d_v002.blend"
STACK_PREVIEW = OUTPUT_DIR / "tower_blender_three_floor_stack_v002.png"
ROOF_PREVIEW = OUTPUT_DIR / "tower_blender_rooftop_plan_v002.png"
FACILITY_PREVIEW = OUTPUT_DIR / "tower_blender_facility_plan_v002.png"
COMBAT_PREVIEW = OUTPUT_DIR / "tower_blender_combat_plan_v002.png"

AREA_SCALE = 5.0
ROOFTOP_SIZE = 50.0 * math.sqrt(AREA_SCALE)
FLOOR_SIZE = 30.0 * math.sqrt(AREA_SCALE)
FLOOR_HEIGHT = 9.0
ROOF_Z = 0.0
FACILITY_Z = -FLOOR_HEIGHT
COMBAT_Z = -FLOOR_HEIGHT * 2.0

SLAB_THICKNESS = 0.30
WALL_THICKNESS = 0.30
OUTER_WALL_HEIGHT = FLOOR_HEIGHT
INTERIOR_WALL_HEIGHT = 5.4
DOOR_WIDTH = 6.0
DOOR_HEIGHT = 4.8
PASSAGE_WIDTH = 6.0
APPROACH_LENGTH = 6.0
STAIR_RUN = 15.0
STAIR_RISE = FLOOR_HEIGHT * 0.5
LANE_GAP = 2.0
LANE_SPACING = PASSAGE_WIDTH + LANE_GAP
GUARD_HEIGHT = 1.20
GUARD_END_CLEARANCE = 3.0
STAIRWELL_DEPTH = APPROACH_LENGTH + STAIR_RUN + PASSAGE_WIDTH * 0.5
STAIRWELL_MIN_Y = -PASSAGE_WIDTH * 0.5
STAIRWELL_MAX_Y = LANE_SPACING + PASSAGE_WIDTH * 0.5

COLLECTION_NAMES = [
    "00_BUILDING_GUIDES",
    "01_FLOOR_ROOFTOP_Z000",
    "02_STAIR_ROOF_TO_FACILITY",
    "03_FLOOR_FACILITY_ZNEG009",
    "04_STAIR_FACILITY_TO_COMBAT",
    "05_FLOOR_COMBAT_ZNEG018",
    "90_LIGHTS_CAMERAS",
]


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)
    for collection in list(bpy.data.collections):
        bpy.data.collections.remove(collection)


def make_collection(name):
    collection = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)
    return collection


def move_to_collection(obj, collection):
    for old_collection in list(obj.users_collection):
        old_collection.objects.unlink(obj)
    collection.objects.link(obj)


def make_material(name, base_color, metallic=0.0, roughness=0.55, emission=None, alpha=1.0):
    material = bpy.data.materials.new(name)
    material.diffuse_color = (*base_color, alpha)
    material.use_nodes = True
    bsdf = next(
        (node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"),
        None,
    )
    if bsdf is None:
        raise RuntimeError(f"Missing Principled BSDF node for material {name}")
    bsdf.inputs["Base Color"].default_value = (*base_color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None:
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
            bsdf.inputs["Emission Strength"].default_value = 2.2
        else:
            bsdf.inputs["Emission"].default_value = (*emission, 1.0)
            bsdf.inputs["Emission Strength"].default_value = 2.2
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        material.surface_render_method = "DITHERED"
    return material


def add_box(name, location, dimensions, material, collection, bevel=0.04, rotation_z=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    obj.rotation_euler[2] = rotation_z
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    move_to_collection(obj, collection)
    if material is not None:
        obj.data.materials.append(material)
    if bevel > 0.0:
        modifier = obj.modifiers.new(name="Bevel_0p04m", type="BEVEL")
        modifier.width = bevel
        modifier.segments = 2
    return obj


def add_empty(name, location, collection, display_size=0.8):
    obj = bpy.data.objects.new(name, None)
    obj.location = location
    obj.empty_display_type = "ARROWS"
    obj.empty_display_size = display_size
    collection.objects.link(obj)
    return obj


def add_text(name, body, location, collection, size=1.8, material=None, align="CENTER"):
    curve = bpy.data.curves.new(name=f"{name}_Curve", type="FONT")
    curve.body = body
    curve.align_x = align
    curve.align_y = "CENTER"
    curve.size = size
    curve.extrude = 0.025
    curve.bevel_depth = 0.008
    obj = bpy.data.objects.new(name, curve)
    obj.location = location
    collection.objects.link(obj)
    if material is not None:
        curve.materials.append(material)
    return obj


def add_floor_panel(name, x0, x1, y0, y1, elevation, material, collection):
    if x1 - x0 <= 0.01 or y1 - y0 <= 0.01:
        return None
    panel = add_box(
        name,
        ((x0 + x1) * 0.5, (y0 + y1) * 0.5, elevation - SLAB_THICKNESS * 0.5),
        (x1 - x0, y1 - y0, SLAB_THICKNESS),
        material,
        collection,
        bevel=0.05,
    )
    panel["walkable_surface_z"] = elevation
    panel["supports_physics_when_hidden"] = True
    return panel


def add_floor_slab(name, size, elevation, material, collection, cutout=None):
    half = size * 0.5
    panels = []
    if cutout is None:
        panels.append(
            add_floor_panel(
                f"{name}_Slab",
                -half,
                half,
                -half,
                half,
                elevation,
                material,
                collection,
            )
        )
    else:
        cut_x0 = max(-half, cutout[0])
        cut_x1 = min(half, cutout[1])
        cut_y0 = max(-half, cutout[2])
        cut_y1 = min(half, cutout[3])
        panels.extend(
            [
                add_floor_panel(
                    f"{name}_Slab_West",
                    -half,
                    cut_x0,
                    -half,
                    half,
                    elevation,
                    material,
                    collection,
                ),
                add_floor_panel(
                    f"{name}_Slab_East",
                    cut_x1,
                    half,
                    -half,
                    half,
                    elevation,
                    material,
                    collection,
                ),
                add_floor_panel(
                    f"{name}_Slab_South",
                    cut_x0,
                    cut_x1,
                    -half,
                    cut_y0,
                    elevation,
                    material,
                    collection,
                ),
                add_floor_panel(
                    f"{name}_Slab_North",
                    cut_x0,
                    cut_x1,
                    cut_y1,
                    half,
                    elevation,
                    material,
                    collection,
                ),
            ]
        )
    for panel in [item for item in panels if item is not None]:
        panel["footprint_m"] = (size, size)
        panel["area_scale"] = AREA_SCALE
        panel["floor_height_m"] = FLOOR_HEIGHT
    return panels


def add_wall_line_with_openings(
    prefix,
    start,
    end,
    elevation,
    height,
    openings,
    material,
    collection,
    door_material=None,
):
    start = Vector(start)
    end = Vector(end)
    direction = end - start
    length = direction.length
    if length <= 0.01:
        return
    unit = direction.normalized()
    yaw = math.atan2(unit.y, unit.x)
    sorted_openings = sorted(openings, key=lambda item: item[0])
    cursor = 0.0
    for index, (center_distance, opening_width, opening_height, door_name) in enumerate(sorted_openings):
        opening_start = max(cursor, center_distance - opening_width * 0.5)
        opening_end = min(length, center_distance + opening_width * 0.5)
        if opening_start > cursor + 0.01:
            segment_start = start + unit * cursor
            segment_end = start + unit * opening_start
            add_box(
                f"{prefix}_Wall_{index:02d}A",
                ((segment_start.x + segment_end.x) * 0.5, (segment_start.y + segment_end.y) * 0.5, elevation + height * 0.5),
                ((segment_end - segment_start).length, WALL_THICKNESS, height),
                material,
                collection,
                rotation_z=yaw,
            )
        lintel_height = max(0.0, height - opening_height)
        if lintel_height > 0.01 and opening_end > opening_start:
            opening_center = start + unit * ((opening_start + opening_end) * 0.5)
            add_box(
                f"{prefix}_{door_name}_Lintel",
                (opening_center.x, opening_center.y, elevation + opening_height + lintel_height * 0.5),
                (opening_end - opening_start, WALL_THICKNESS, lintel_height),
                material,
                collection,
                rotation_z=yaw,
            )
        if door_material is not None:
            opening_center = start + unit * center_distance
            add_door(
                f"{prefix}_{door_name}",
                (opening_center.x, opening_center.y, elevation),
                yaw - math.pi * 0.5,
                collection,
                material,
                door_material,
            )
        cursor = opening_end
    if cursor < length - 0.01:
        segment_start = start + unit * cursor
        segment_end = end
        add_box(
            f"{prefix}_Wall_End",
            ((segment_start.x + segment_end.x) * 0.5, (segment_start.y + segment_end.y) * 0.5, elevation + height * 0.5),
            ((segment_end - segment_start).length, WALL_THICKNESS, height),
            material,
            collection,
            rotation_z=yaw,
        )


def add_door(prefix, origin, normal_yaw, collection, frame_material, leaf_material, open_degrees=68.0):
    origin = Vector(origin)
    normal = Vector((math.cos(normal_yaw), math.sin(normal_yaw), 0.0))
    side = Vector((-normal.y, normal.x, 0.0))
    for side_sign in (-1.0, 1.0):
        add_box(
            f"{prefix}_Frame_{'L' if side_sign < 0 else 'R'}",
            origin + side * side_sign * (DOOR_WIDTH * 0.5 + 0.18) + Vector((0.0, 0.0, DOOR_HEIGHT * 0.5)),
            (0.42, 0.42, DOOR_HEIGHT),
            frame_material,
            collection,
            bevel=0.05,
        )
    lintel = add_box(
        f"{prefix}_Frame_Top",
        origin + Vector((0.0, 0.0, DOOR_HEIGHT + 0.18)),
        (0.42, DOOR_WIDTH + 0.78, 0.36),
        frame_material,
        collection,
        bevel=0.05,
        rotation_z=normal_yaw,
    )
    lintel["door_clear_width_m"] = DOOR_WIDTH
    lintel["door_clear_height_m"] = DOOR_HEIGHT
    hinge = origin - side * (DOOR_WIDTH * 0.5 - 0.16)
    leaf_yaw = normal_yaw + math.radians(open_degrees)
    leaf_side = Vector((-math.sin(leaf_yaw), math.cos(leaf_yaw), 0.0))
    leaf_center = hinge + leaf_side * (DOOR_WIDTH * 0.5 - 0.16) + Vector((0.0, 0.0, (DOOR_HEIGHT - 0.24) * 0.5))
    leaf = add_box(
        f"{prefix}_DoorLeaf_OPEN",
        leaf_center,
        (0.18, DOOR_WIDTH - 0.32, DOOR_HEIGHT - 0.24),
        leaf_material,
        collection,
        bevel=0.07,
        rotation_z=leaf_yaw,
    )
    leaf["default_preview_state"] = "OPEN"
    leaf["gameplay_door_should_block_vision_when_closed"] = True
    return leaf


def add_outer_room_shell(prefix, size, elevation, door_sides, collection):
    half = size * 0.5
    sides = {
        "south": ((-half, -half), (half, -half)),
        "east": ((half, -half), (half, half)),
        "north": ((half, half), (-half, half)),
        "west": ((-half, half), (-half, -half)),
    }
    for side, (start, end) in sides.items():
        openings = []
        if side in door_sides:
            wall_length = (Vector(end) - Vector(start)).length
            openings.append((wall_length * 0.5 + door_sides[side], DOOR_WIDTH, DOOR_HEIGHT, f"Door_{side.title()}"))
        add_wall_line_with_openings(
            f"{prefix}_{side.title()}",
            start,
            end,
            elevation,
            OUTER_WALL_HEIGHT,
            openings,
            MAT_STRUCTURE,
            collection,
            MAT_DOOR,
        )


def transform_local(point, anchor, yaw):
    point = Vector(point)
    anchor = Vector(anchor)
    cos_yaw = math.cos(yaw)
    sin_yaw = math.sin(yaw)
    return Vector(
        (
            anchor.x + point.x * cos_yaw - point.y * sin_yaw,
            anchor.y + point.x * sin_yaw + point.y * cos_yaw,
            anchor.z + point.z,
        )
    )


def add_path_segment(prefix, start, end, collection, material, add_guards=False):
    start = Vector(start)
    end = Vector(end)
    direction = end - start
    length = direction.length
    rotation = direction.to_track_quat("X", "Z")
    surface_normal = rotation @ Vector((0.0, 0.0, 1.0))
    center = (start + end) * 0.5 - surface_normal * (SLAB_THICKNESS * 0.5)
    slab = add_box(
        f"{prefix}_Walkable",
        center,
        (length, PASSAGE_WIDTH, SLAB_THICKNESS),
        material,
        collection,
        bevel=0.025,
    )
    slab.rotation_mode = "QUATERNION"
    slab.rotation_quaternion = rotation
    slab["walkable_surface_start"] = tuple(start)
    slab["walkable_surface_end"] = tuple(end)
    slab["clear_width_m"] = PASSAGE_WIDTH
    slab["height_delta_m"] = end.z - start.z
    if abs(direction.z) > 0.05:
        planar = Vector((direction.x, direction.y, 0.0))
        planar_length = planar.length
        step_count = max(12, int(round(planar_length)))
        step_yaw = math.atan2(planar.y, planar.x)
        for index in range(step_count):
            ratio = (index + 0.5) / step_count
            position = start.lerp(end, ratio)
            add_box(
                f"{prefix}_Tread_{index + 1:02d}",
                position + Vector((0.0, 0.0, 0.065)),
                (planar_length / step_count * 0.72, PASSAGE_WIDTH - 0.42, 0.07),
                MAT_STAIR_TREAD,
                collection,
                bevel=0.012,
                rotation_z=step_yaw,
            )
        if add_guards:
            guard_planar_length = max(1.0, planar_length - GUARD_END_CLEARANCE * 2.0)
            guard_length = length * guard_planar_length / planar_length
            side_axis = rotation @ Vector((0.0, 1.0, 0.0))
            for side_index, side_sign in enumerate((-1.0, 1.0), start=1):
                guard_center = (
                    (start + end) * 0.5
                    + side_axis * side_sign * (PASSAGE_WIDTH * 0.5 + 0.10)
                    + surface_normal * (GUARD_HEIGHT * 0.5)
                )
                guard = add_box(
                    f"{prefix}_Guard_{side_index:02d}",
                    guard_center,
                    (guard_length, WALL_THICKNESS, GUARD_HEIGHT),
                    MAT_STRUCTURE,
                    collection,
                    bevel=0.025,
                )
                guard.rotation_mode = "QUATERNION"
                guard.rotation_quaternion = rotation
                guard["end_clearance_m"] = GUARD_END_CLEARANCE
    return slab


def build_stairwell(collection, prefix, anchor, yaw, upper_name, lower_name):
    local_points = [
        (0.0, 0.0, 0.0),
        (APPROACH_LENGTH, 0.0, 0.0),
        (APPROACH_LENGTH + STAIR_RUN, 0.0, -STAIR_RISE),
        (APPROACH_LENGTH + STAIR_RUN, LANE_SPACING, -STAIR_RISE),
        (APPROACH_LENGTH, LANE_SPACING, -FLOOR_HEIGHT),
        (APPROACH_LENGTH, 0.0, -FLOOR_HEIGHT),
        (0.0, 0.0, -FLOOR_HEIGHT),
    ]
    points = [transform_local(point, anchor, yaw) for point in local_points]
    segment_names = [
        "UpperDoorLanding",
        "UpperFlight",
        "TurnLanding",
        "LowerFlight",
        "LowerReturnLanding",
        "LowerDoorLanding",
    ]
    for index, segment_name in enumerate(segment_names):
        add_path_segment(
            f"{prefix}_{segment_name}",
            points[index],
            points[index + 1],
            collection,
            MAT_STAIR if "Flight" in segment_name else MAT_LANDING,
            add_guards="Flight" in segment_name,
        )

    # Full-height enclosure is outside the 6m path envelope. No wall crosses a landing or bend.
    wall_height = FLOOR_HEIGHT
    local_wall_lines = [
        ((0.0, STAIRWELL_MIN_Y), (STAIRWELL_DEPTH, STAIRWELL_MIN_Y)),
        ((STAIRWELL_DEPTH, STAIRWELL_MIN_Y), (STAIRWELL_DEPTH, STAIRWELL_MAX_Y)),
        ((STAIRWELL_DEPTH, STAIRWELL_MAX_Y), (0.0, STAIRWELL_MAX_Y)),
    ]
    for wall_index, (local_start, local_end) in enumerate(local_wall_lines, start=1):
        world_start = transform_local((local_start[0], local_start[1], -FLOOR_HEIGHT), anchor, yaw)
        world_end = transform_local((local_end[0], local_end[1], -FLOOR_HEIGHT), anchor, yaw)
        delta = world_end - world_start
        add_box(
            f"{prefix}_EnclosureWall_{wall_index:02d}",
            (
                (world_start.x + world_end.x) * 0.5,
                (world_start.y + world_end.y) * 0.5,
                anchor[2] - FLOOR_HEIGHT * 0.5,
            ),
            (delta.length, WALL_THICKNESS, wall_height),
            MAT_STAIRWELL_WALL,
            collection,
            bevel=0.03,
            rotation_z=math.atan2(delta.y, delta.x),
        )

    root = add_empty(f"{prefix}_ROOT", anchor, collection, 1.2)
    root["upper_floor"] = upper_name
    root["lower_floor"] = lower_name
    root["upper_door_world"] = tuple(points[0])
    root["lower_door_world"] = tuple(points[-1])
    root["path_points_world"] = [tuple(point) for point in points]
    root["passage_width_m"] = PASSAGE_WIDTH
    root["floor_delta_m"] = FLOOR_HEIGHT
    root["stair_run_m"] = STAIR_RUN
    root["stair_rise_each_m"] = STAIR_RISE
    root["lane_center_spacing_m"] = LANE_SPACING
    root["collision_contract"] = "walkable surfaces are continuous; walls never cross path segments"
    add_empty(f"{prefix}_SOCKET_UPPER_DOOR", points[0], collection, 0.7)
    add_empty(f"{prefix}_SOCKET_LOWER_DOOR", points[-1], collection, 0.7)
    return points


def add_segmented_parapet(prefix, side, coordinate, axis_min, axis_max, elevation, openings, collection):
    cursor = axis_min
    horizontal = side in ("north", "south")
    for index, (opening_center, opening_width) in enumerate(sorted(openings), start=1):
        opening_start = max(axis_min, opening_center - opening_width * 0.5)
        opening_end = min(axis_max, opening_center + opening_width * 0.5)
        if opening_start > cursor:
            center_axis = (cursor + opening_start) * 0.5
            dims = (
                (opening_start - cursor, WALL_THICKNESS, 1.5)
                if horizontal
                else (WALL_THICKNESS, opening_start - cursor, 1.5)
            )
            location = (
                (center_axis, coordinate, elevation + 0.75)
                if horizontal
                else (coordinate, center_axis, elevation + 0.75)
            )
            add_box(f"{prefix}_{index:02d}", location, dims, MAT_STRUCTURE, collection)
        cursor = opening_end
    if cursor < axis_max:
        center_axis = (cursor + axis_max) * 0.5
        dims = (
            (axis_max - cursor, WALL_THICKNESS, 1.5)
            if horizontal
            else (WALL_THICKNESS, axis_max - cursor, 1.5)
        )
        location = (
            (center_axis, coordinate, elevation + 0.75)
            if horizontal
            else (coordinate, center_axis, elevation + 0.75)
        )
        add_box(f"{prefix}_End", location, dims, MAT_STRUCTURE, collection)


def build_rooftop(collection):
    half_roof = ROOFTOP_SIZE * 0.5
    half_floor = FLOOR_SIZE * 0.5
    # The west stair rotates local +Y to world -Y, so its 14m envelope is [-11m, +3m].
    west_stair_y_min = -STAIRWELL_MAX_Y
    west_stair_y_max = -STAIRWELL_MIN_Y
    stair_cutout = (
        -half_roof,
        -half_floor + 0.4,
        west_stair_y_min - 0.5,
        west_stair_y_max + 0.5,
    )
    panels = add_floor_slab("Rooftop", ROOFTOP_SIZE, ROOF_Z, MAT_ROOF, collection, stair_cutout)
    for panel in panels:
        if panel is not None:
            panel["module_type"] = "stacked_rooftop"
            panel["stair_cutout_bounds"] = stair_cutout

    add_segmented_parapet(
        "Rooftop_Parapet_North",
        "north",
        half_roof,
        -half_roof,
        half_roof,
        ROOF_Z,
        [],
        collection,
    )
    add_segmented_parapet(
        "Rooftop_Parapet_South",
        "south",
        -half_roof,
        -half_roof,
        half_roof,
        ROOF_Z,
        [],
        collection,
    )
    add_segmented_parapet(
        "Rooftop_Parapet_West",
        "west",
        -half_roof,
        -half_roof,
        half_roof,
        ROOF_Z,
        [(LANE_SPACING * -0.5, PASSAGE_WIDTH * 2.0 + LANE_GAP + 1.0)],
        collection,
    )
    add_segmented_parapet(
        "Rooftop_Parapet_East",
        "east",
        half_roof,
        -half_roof,
        half_roof,
        ROOF_Z,
        [],
        collection,
    )

    roof_entry_x = -half_floor
    add_wall_line_with_openings(
        "Rooftop_StairEntry",
        (roof_entry_x, west_stair_y_max),
        (roof_entry_x, west_stair_y_min),
        ROOF_Z,
        5.4,
        [((west_stair_y_max - west_stair_y_min) * 0.5 - LANE_SPACING * 0.5, DOOR_WIDTH, DOOR_HEIGHT, "WestStair")],
        MAT_STAIRWELL_WALL,
        collection,
        MAT_DOOR,
    )
    # The south and north walls make the roof opening read as an enclosed stair head-house.
    for name, y in (("South", west_stair_y_min), ("North", west_stair_y_max)):
        add_box(
            f"Rooftop_StairHeadHouse_{name}",
            ((-half_roof + roof_entry_x) * 0.5, y, ROOF_Z + 2.7),
            (roof_entry_x + half_roof, WALL_THICKNESS, 5.4),
            MAT_STAIRWELL_WALL,
            collection,
        )
    add_text(
        "Rooftop_Label",
        "ROOFTOP  Z 0 m",
        (18.0, -44.0, ROOF_Z + 0.18),
        collection,
        3.0,
        MAT_LABEL,
    )


def build_facility_floor(collection):
    slabs = add_floor_slab("Facility", FLOOR_SIZE, FACILITY_Z, MAT_FACILITY, collection)
    for slab in slabs:
        slab["module_type"] = "stacked_facility_floor"
    add_outer_room_shell(
        "Facility",
        FLOOR_SIZE,
        FACILITY_Z,
        {"west": 0.0, "east": 0.0},
        collection,
    )
    half = FLOOR_SIZE * 0.5

    # North equipment wall: seven existing-base facility placeholders, kept out of both stair axes.
    bay_width = 5.2
    for index in range(7):
        x = -18.6 + index * 6.2
        bay = add_box(
            f"Facility_ExistingFacility_{index + 1:02d}",
            (x, half - 3.4, FACILITY_Z + 1.35),
            (bay_width, 4.8, 2.7),
            MAT_FACILITY_ACCENT if index % 2 == 0 else MAT_STRUCTURE,
            collection,
            bevel=0.15,
        )
        bay["facility_placeholder"] = index + 1

    # Interior service wall and east corridor wall use real door openings.
    add_wall_line_with_openings(
        "Facility_InteriorNorth",
        (-half + 7.0, 18.0),
        (half - 7.0, 18.0),
        FACILITY_Z,
        INTERIOR_WALL_HEIGHT,
        [
            (10.0, 5.0, 4.2, "Door_A"),
            (26.5, 5.0, 4.2, "Door_B"),
            (43.0, 5.0, 4.2, "Door_C"),
        ],
        MAT_INTERIOR_WALL,
        collection,
        MAT_DOOR,
    )
    add_wall_line_with_openings(
        "Facility_RightCorridor",
        (18.0, -18.0),
        (18.0, 18.0),
        FACILITY_Z,
        INTERIOR_WALL_HEIGHT,
        [(18.0, 5.0, 4.2, "Door_ToEastHall")],
        MAT_INTERIOR_WALL,
        collection,
        MAT_DOOR,
    )
    add_wall_line_with_openings(
        "Facility_SouthRoom",
        (-18.0, -18.0),
        (18.0, -18.0),
        FACILITY_Z,
        INTERIOR_WALL_HEIGHT,
        [(18.0, 5.0, 4.2, "Door_ToSouthRoom")],
        MAT_INTERIOR_WALL,
        collection,
        MAT_DOOR,
    )
    add_box(
        "Facility_ClearMainLane",
        (0.0, 0.0, FACILITY_Z + 0.035),
        (FLOOR_SIZE - 12.0, 12.0, 0.07),
        MAT_CLEARANCE,
        collection,
        bevel=0.0,
    )


def build_combat_floor(collection):
    slabs = add_floor_slab("Combat", FLOOR_SIZE, COMBAT_Z, MAT_COMBAT, collection)
    for slab in slabs:
        slab["module_type"] = "stacked_combat_floor"
    add_outer_room_shell(
        "Combat",
        FLOOR_SIZE,
        COMBAT_Z,
        {"east": 0.0},
        collection,
    )
    half = FLOOR_SIZE * 0.5

    # Four rooms around a 14m cross-shaped combat lane. Every partition terminates cleanly at a grid line.
    for row_name, y, door_x in (
        ("NorthRooms", 16.0, -10.0),
        ("SouthRooms", -16.0, 10.0),
    ):
        add_wall_line_with_openings(
            f"Combat_{row_name}",
            (-half + 5.0, y),
            (half - 5.0, y),
            COMBAT_Z,
            INTERIOR_WALL_HEIGHT,
            [
                (half - 5.0 + door_x - 2.5, 5.0, 4.2, "Door_Left"),
                (half - 5.0 + door_x + 20.0, 5.0, 4.2, "Door_Right"),
            ],
            MAT_INTERIOR_WALL,
            collection,
            MAT_DOOR,
        )
    add_wall_line_with_openings(
        "Combat_WestRooms",
        (-16.0, -16.0),
        (-16.0, 16.0),
        COMBAT_Z,
        INTERIOR_WALL_HEIGHT,
        [(16.0, 5.0, 4.2, "Door_Center")],
        MAT_INTERIOR_WALL,
        collection,
        MAT_DOOR,
    )
    add_wall_line_with_openings(
        "Combat_EastRooms",
        (16.0, -16.0),
        (16.0, 16.0),
        COMBAT_Z,
        INTERIOR_WALL_HEIGHT,
        [(16.0, 5.0, 4.2, "Door_Center")],
        MAT_INTERIOR_WALL,
        collection,
        MAT_DOOR,
    )
    for index, (x, y) in enumerate(((-24, 24), (24, 24), (-24, -24), (24, -24)), start=1):
        add_box(
            f"Combat_Cover_{index:02d}",
            (x, y, COMBAT_Z + 1.05),
            (4.2, 3.2, 2.1),
            MAT_STRUCTURE,
            collection,
            bevel=0.12,
        )
    add_box(
        "Combat_ClearMainLane",
        (0.0, 0.0, COMBAT_Z + 0.035),
        (FLOOR_SIZE - 12.0, 14.0, 0.07),
        MAT_CLEARANCE,
        collection,
        bevel=0.0,
    )


def look_at(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def add_camera(name, location, target, ortho_scale, collection):
    camera_data = bpy.data.cameras.new(name)
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = ortho_scale
    camera = bpy.data.objects.new(name, camera_data)
    camera.location = location
    look_at(camera, target)
    collection.objects.link(camera)
    return camera


def add_lighting(collection):
    sun_data = bpy.data.lights.new(name="Review_Sun", type="SUN")
    sun_data.energy = 2.0
    sun_data.angle = math.radians(16.0)
    sun = bpy.data.objects.new("Review_Sun", sun_data)
    sun.rotation_euler = (math.radians(28), math.radians(-22), math.radians(-32))
    collection.objects.link(sun)
    for name, location, energy, size, color in (
        ("Review_Key", (-95.0, -105.0, 95.0), 5200.0, 60.0, (0.54, 0.77, 1.0)),
        ("Review_Fill", (105.0, -35.0, 55.0), 3800.0, 52.0, (1.0, 0.55, 0.26)),
    ):
        light_data = bpy.data.lights.new(name=name, type="AREA")
        light_data.energy = energy
        light_data.shape = "DISK"
        light_data.size = size
        light_data.color = color
        light = bpy.data.objects.new(name, light_data)
        light.location = location
        look_at(light, (0.0, 0.0, FACILITY_Z))
        collection.objects.link(light)


def set_collection_visibility(visible_names):
    visible = set(visible_names)
    for name, collection in COLLECTIONS.items():
        collection.hide_render = name not in visible


def render_preview(path, camera, visible_collections, resolution):
    set_collection_visibility(visible_collections)
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.resolution_x = resolution[0]
    scene.render.resolution_y = resolution[1]
    scene.render.resolution_percentage = 100
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


clear_scene()
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

scene = bpy.context.scene
scene.name = "ENV_TOWER_DESCENT_THREE_FLOOR_STACK_3D"
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.film_transparent = False
scene.view_settings.look = "AgX - Medium High Contrast"
scene.world.color = (0.008, 0.012, 0.018)
scene["asset_id"] = "ENV-TOWER-DESCENT-KIT-3D"
scene["version"] = "v002"
scene["unit_contract"] = "1 Blender unit = 1 meter"
scene["layout_mode"] = "THREE_FLOOR_GAME_STACK"
scene["floor_elevations_m"] = [ROOF_Z, FACILITY_Z, COMBAT_Z]
scene["floor_height_m"] = FLOOR_HEIGHT
scene["rooftop_size_m"] = ROOFTOP_SIZE
scene["interior_floor_size_m"] = FLOOR_SIZE
scene["stair_side_sequence"] = ["west", "east"]
scene["godot_integration_status"] = "NOT_IMPORTED_AWAITING_USER_APPROVAL"

COLLECTIONS = {name: make_collection(name) for name in COLLECTION_NAMES}

MAT_STRUCTURE = make_material("MAT_Structure_DarkSteel", (0.075, 0.095, 0.12), metallic=0.55, roughness=0.48)
MAT_STAIRWELL_WALL = make_material("MAT_Stairwell_Wall", (0.045, 0.065, 0.086), metallic=0.22, roughness=0.68)
MAT_INTERIOR_WALL = make_material("MAT_Interior_Wall", (0.13, 0.16, 0.19), metallic=0.08, roughness=0.74)
MAT_DOOR = make_material("MAT_Door_CyanSteel", (0.06, 0.34, 0.39), metallic=0.48, roughness=0.38)
MAT_LANDING = make_material("MAT_Stair_Landing", (0.08, 0.38, 0.44), metallic=0.28, roughness=0.44)
MAT_STAIR = make_material("MAT_Stair_Slope", (0.09, 0.27, 0.56), metallic=0.22, roughness=0.47)
MAT_STAIR_TREAD = make_material("MAT_Stair_Tread", (0.16, 0.19, 0.23), metallic=0.50, roughness=0.42)
MAT_CLEARANCE = make_material("MAT_ClearanceZone", (0.08, 0.42, 0.30), metallic=0.04, roughness=0.64)
MAT_ROOF = make_material("MAT_Rooftop", (0.10, 0.13, 0.17), metallic=0.18, roughness=0.72)
MAT_FACILITY = make_material("MAT_FacilityFloor", (0.075, 0.18, 0.17), metallic=0.14, roughness=0.66)
MAT_FACILITY_ACCENT = make_material("MAT_FacilityAccent", (0.10, 0.56, 0.43), metallic=0.20, roughness=0.48)
MAT_COMBAT = make_material("MAT_CombatFloor", (0.17, 0.085, 0.09), metallic=0.12, roughness=0.68)
MAT_LABEL = make_material("MAT_Label", (0.86, 0.94, 1.0), metallic=0.0, roughness=0.32, emission=(0.55, 0.78, 1.0))

build_rooftop(COLLECTIONS["01_FLOOR_ROOFTOP_Z000"])
build_facility_floor(COLLECTIONS["03_FLOOR_FACILITY_ZNEG009"])
build_combat_floor(COLLECTIONS["05_FLOOR_COMBAT_ZNEG018"])

half_floor = FLOOR_SIZE * 0.5
west_points = build_stairwell(
    COLLECTIONS["02_STAIR_ROOF_TO_FACILITY"],
    "Stair_West_Roof_Facility",
    (-half_floor, 0.0, ROOF_Z),
    math.pi,
    "ROOFTOP",
    "FACILITY",
)
east_points = build_stairwell(
    COLLECTIONS["04_STAIR_FACILITY_TO_COMBAT"],
    "Stair_East_Facility_Combat",
    (half_floor, 0.0, FACILITY_Z),
    0.0,
    "FACILITY",
    "COMBAT",
)

for name, body, location in (
    ("Guide_Roof", "ROOFTOP  Z=0m", (-76.0, -57.0, 3.0)),
    ("Guide_Facility", "FACILITY  Z=-9m", (-76.0, -57.0, -6.0)),
    ("Guide_Combat", "COMBAT  Z=-18m", (-76.0, -57.0, -15.0)),
):
    add_text(name, body, location, COLLECTIONS["00_BUILDING_GUIDES"], 2.8, MAT_LABEL, align="LEFT")

add_lighting(COLLECTIONS["90_LIGHTS_CAMERAS"])
camera_stack = add_camera(
    "CAM_ThreeFloorStack",
    (150.0, -205.0, 24.0),
    (0.0, 0.0, FACILITY_Z - 1.0),
    154.0,
    COLLECTIONS["90_LIGHTS_CAMERAS"],
)
camera_roof = add_camera(
    "CAM_RooftopPlan",
    (0.0, 0.0, 145.0),
    (0.0, 0.0, ROOF_Z),
    126.0,
    COLLECTIONS["90_LIGHTS_CAMERAS"],
)
camera_facility = add_camera(
    "CAM_FacilityPlan",
    (0.0, 0.0, 75.0),
    (0.0, 0.0, FACILITY_Z),
    82.0,
    COLLECTIONS["90_LIGHTS_CAMERAS"],
)
camera_combat = add_camera(
    "CAM_CombatPlan",
    (0.0, 0.0, 66.0),
    (0.0, 0.0, COMBAT_Z),
    82.0,
    COLLECTIONS["90_LIGHTS_CAMERAS"],
)

render_preview(
    STACK_PREVIEW,
    camera_stack,
    COLLECTION_NAMES,
    (1800, 1200),
)
render_preview(
    ROOF_PREVIEW,
    camera_roof,
    [
        "00_BUILDING_GUIDES",
        "01_FLOOR_ROOFTOP_Z000",
        "02_STAIR_ROOF_TO_FACILITY",
        "90_LIGHTS_CAMERAS",
    ],
    (1600, 1600),
)
render_preview(
    FACILITY_PREVIEW,
    camera_facility,
    [
        "03_FLOOR_FACILITY_ZNEG009",
        "02_STAIR_ROOF_TO_FACILITY",
        "04_STAIR_FACILITY_TO_COMBAT",
        "90_LIGHTS_CAMERAS",
    ],
    (1600, 1600),
)
render_preview(
    COMBAT_PREVIEW,
    camera_combat,
    [
        "05_FLOOR_COMBAT_ZNEG018",
        "04_STAIR_FACILITY_TO_COMBAT",
        "90_LIGHTS_CAMERAS",
    ],
    (1600, 1600),
)

for collection in COLLECTIONS.values():
    collection.hide_render = False
    collection.hide_viewport = False
scene.camera = camera_stack
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

print("TOWER_BLENDER_STACK_OK")
print(f"BLEND={BLEND_PATH}")
print(f"ROOF_Z={ROOF_Z:.3f} FACILITY_Z={FACILITY_Z:.3f} COMBAT_Z={COMBAT_Z:.3f}")
print(f"ROOFTOP={ROOFTOP_SIZE:.6f}m AREA={ROOFTOP_SIZE * ROOFTOP_SIZE:.3f}m2")
print(f"FLOOR={FLOOR_SIZE:.6f}m AREA={FLOOR_SIZE * FLOOR_SIZE:.3f}m2")
print(f"WEST_UPPER={tuple(round(value, 4) for value in west_points[0])}")
print(f"WEST_LOWER={tuple(round(value, 4) for value in west_points[-1])}")
print(f"EAST_UPPER={tuple(round(value, 4) for value in east_points[0])}")
print(f"EAST_LOWER={tuple(round(value, 4) for value in east_points[-1])}")
print(f"PASSAGE_WIDTH={PASSAGE_WIDTH:.3f}m FLOOR_HEIGHT={FLOOR_HEIGHT:.3f}m")
