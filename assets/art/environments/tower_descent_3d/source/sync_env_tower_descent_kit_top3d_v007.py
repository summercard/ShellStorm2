"""Synchronize the canonical tower Blender source with the PH49 Godot layout.

The v006 five-metre module library and the user's edited stair assets are
preserved. Historical 335 m review assemblies are hidden, while a new PH49
runtime-sync collection records the 250 m envelope, 30 m base, 98--95 room
footprints, wall-edge elevator facilities, corridors, and the 2.2 x 2.5 m
door contract.
"""

from pathlib import Path
import math

import bpy


PROJECT_ROOT = Path("/Users/summercards/ShellStorm2")
SOURCE_DIR = PROJECT_ROOT / "assets/art/environments/tower_descent_3d/source"
INPUT_BLEND = SOURCE_DIR / "env_tower_descent_kit_top3d_v006.blend"
OUTPUT_BLEND = SOURCE_DIR / "env_tower_descent_kit_top3d_v007.blend"

GRID = 5.0
MAP_SIZE = 250.0
CORE_CENTER = (2.5, 2.5)
CORE_SIZE = 65.0
BASE_SIZE = 30.0
FLOOR_HEIGHT = 9.0
DOOR_WIDTH = 2.2
DOOR_HEIGHT = 2.5
WALL_HEIGHT = 9.0
WALL_THICKNESS = 0.30

ROOT_COLLECTION = "20_PH49_RUNTIME_SYNC"
LEVEL_COLLECTION = "20A_LEVEL_GUIDES_250M"
BASE_COLLECTION = "20B_BASE_99_30M"
ROOM_COLLECTION = "20C_ROOMS_98_95"
ELEVATOR_COLLECTION = "20D_STANDALONE_ELEVATORS"
DOOR_COLLECTION = "20E_DOOR_CONTRACT_V002"
DOOR_LIBRARY_COLLECTION = "10D_MOD_WALL_DOOR_5M_U01"
DOOR_ROOT_NAME = "MOD_WALL_DOOR_5M_U01_ROOT"


def ensure_input_scene():
    if Path(bpy.data.filepath).resolve() != INPUT_BLEND.resolve():
        bpy.ops.wm.open_mainfile(filepath=str(INPUT_BLEND))


def remove_collection(name):
    collection = bpy.data.collections.get(name)
    if collection is not None:
        bpy.data.collections.remove(collection)


def ensure_top_collection(name):
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
    root = bpy.context.scene.collection
    for candidate in bpy.data.collections:
        if candidate is not root and collection.name in candidate.children:
            candidate.children.unlink(collection)
    if collection.name not in root.children:
        root.children.link(collection)
    return collection


def ensure_child_collection(parent, name):
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
    root = bpy.context.scene.collection
    if collection.name in root.children:
        root.children.unlink(collection)
    for candidate in bpy.data.collections:
        if candidate is not parent and collection.name in candidate.children:
            candidate.children.unlink(collection)
    if collection.name not in parent.children:
        parent.children.link(collection)
    return collection


def move_to_collection(obj, collection):
    for current in list(obj.users_collection):
        current.objects.unlink(obj)
    collection.objects.link(obj)


def material(name, color, metallic=0.0, roughness=0.7, emission=None):
    result = bpy.data.materials.get(name)
    if result is None:
        result = bpy.data.materials.new(name)
    result.diffuse_color = (*color[:3], color[3] if len(color) > 3 else 1.0)
    result.metallic = metallic
    result.roughness = roughness
    result.use_nodes = True
    principled = result.node_tree.nodes.get("Principled BSDF")
    if principled is not None:
        principled.inputs["Base Color"].default_value = result.diffuse_color
        principled.inputs["Metallic"].default_value = metallic
        principled.inputs["Roughness"].default_value = roughness
        if emission is not None:
            principled.inputs["Emission Color"].default_value = (*emission, 1.0)
            principled.inputs["Emission Strength"].default_value = 1.8
    return result


def add_box(name, location, dimensions, mat, collection, role, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if mat is not None:
        obj.data.materials.append(mat)
    if bevel > 0.0:
        modifier = obj.modifiers.new("EdgeSoftening", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    move_to_collection(obj, collection)
    obj["asset_role"] = role
    obj["grid_unit_m"] = GRID
    obj["runtime_sync_version"] = "PH49"
    return obj


def add_empty(name, location, collection, role, **metadata):
    obj = bpy.data.objects.new(name, None)
    collection.objects.link(obj)
    obj.location = location
    obj.empty_display_type = "CUBE"
    obj.empty_display_size = 1.0
    obj["asset_role"] = role
    obj["runtime_sync_version"] = "PH49"
    for key, value in metadata.items():
        obj[key] = value
    return obj


def rebuild_door_master():
    collection = bpy.data.collections.get(DOOR_LIBRARY_COLLECTION)
    root = bpy.data.objects.get(DOOR_ROOT_NAME)
    if collection is None or root is None:
        raise RuntimeError("v006 door module library is missing")

    preserved_materials = {}
    for child in list(root.children):
        if child.type == "MESH" and child.data.materials:
            preserved_materials[child.name.split("_")[-1]] = child.data.materials[0]
        mesh = child.data if child.type == "MESH" else None
        bpy.data.objects.remove(child, do_unlink=True)
        if mesh is not None and mesh.users == 0:
            bpy.data.meshes.remove(mesh)

    root["asset_role"] = "MODULE_MASTER"
    root["module_id"] = "ENV-TOWER-WALL-DOOR-5M"
    root["asset_version"] = "v002"
    root["clear_width_m"] = DOOR_WIDTH
    root["clear_height_m"] = DOOR_HEIGHT
    root["grid_unit_m"] = GRID
    root["origin_contract"] = "BOTTOM_CENTER"

    wall_mat = next(iter(preserved_materials.values()), None)
    frame_mat = material(
        "MAT_PH49_DoorFrame",
        (0.12, 0.17, 0.18, 1.0),
        metallic=0.78,
        roughness=0.28,
    )
    leaf_mat = material(
        "MAT_PH49_DoorLeaf",
        (0.055, 0.08, 0.09, 1.0),
        metallic=0.86,
        roughness=0.24,
        emission=(0.02, 0.36, 0.40),
    )

    pier_width = (GRID - DOOR_WIDTH) * 0.5
    pier_center = DOOR_WIDTH * 0.5 + pier_width * 0.5
    lintel_height = WALL_HEIGHT - DOOR_HEIGHT
    components = [
        (
            "Pier_L",
            (-pier_center, 0.0, WALL_HEIGHT * 0.5),
            (pier_width, WALL_THICKNESS, WALL_HEIGHT),
            wall_mat or frame_mat,
            "MODULE_MASTER_DOOR_COMPONENT",
        ),
        (
            "Pier_R",
            (pier_center, 0.0, WALL_HEIGHT * 0.5),
            (pier_width, WALL_THICKNESS, WALL_HEIGHT),
            wall_mat or frame_mat,
            "MODULE_MASTER_DOOR_COMPONENT",
        ),
        (
            "Lintel",
            (0.0, 0.0, DOOR_HEIGHT + lintel_height * 0.5),
            (DOOR_WIDTH, WALL_THICKNESS, lintel_height),
            wall_mat or frame_mat,
            "MODULE_MASTER_DOOR_COMPONENT",
        ),
        (
            "Frame_L",
            (-(DOOR_WIDTH * 0.5 + 0.07), -0.07, DOOR_HEIGHT * 0.5),
            (0.14, 0.42, DOOR_HEIGHT + 0.28),
            frame_mat,
            "MODULE_MASTER_DOOR_COMPONENT",
        ),
        (
            "Frame_R",
            (DOOR_WIDTH * 0.5 + 0.07, -0.07, DOOR_HEIGHT * 0.5),
            (0.14, 0.42, DOOR_HEIGHT + 0.28),
            frame_mat,
            "MODULE_MASTER_DOOR_COMPONENT",
        ),
        (
            "Frame_Top",
            (0.0, -0.07, DOOR_HEIGHT + 0.14),
            (DOOR_WIDTH + 0.28, 0.42, 0.28),
            frame_mat,
            "MODULE_MASTER_DOOR_COMPONENT",
        ),
        (
            "DoorLeaf_OPEN",
            (-(DOOR_WIDTH + 0.18), -0.20, DOOR_HEIGHT * 0.5),
            (DOOR_WIDTH - 0.12, 0.18, DOOR_HEIGHT - 0.12),
            leaf_mat,
            "MODULE_MASTER_DOOR_LEAF",
        ),
    ]
    for suffix, location, dimensions, mat, role in components:
        child = add_box(
            f"MOD_WALL_DOOR_5M_U01_{suffix}",
            location,
            dimensions,
            mat,
            collection,
            role,
            bevel=0.025 if "Frame" in suffix or "DoorLeaf" in suffix else 0.0,
        )
        child.parent = root
        child.matrix_parent_inverse.identity()
        child["module_id"] = "ENV-TOWER-WALL-DOOR-5M"
        child["door_component"] = suffix
        child["clear_width_m"] = DOOR_WIDTH
        child["clear_height_m"] = DOOR_HEIGHT

    for socket_name, location in (
        ("SOCKET_L", (-2.5, 0.0, 0.0)),
        ("SOCKET_R", (2.5, 0.0, 0.0)),
        ("SOCKET_INTERACT", (0.0, -1.0, 1.2)),
    ):
        socket = add_empty(
            f"MOD_WALL_DOOR_5M_U01_{socket_name}",
            location,
            collection,
            "MODULE_SOCKET",
            grid_unit_m=GRID,
        )
        socket.parent = root
        socket.matrix_parent_inverse.identity()


def add_centered_wall(direction, center, dimensions, collection, mat):
    horizontal = direction in {"north", "south"}
    length = dimensions[0] if horizontal else dimensions[1]
    wall_x, wall_y = center
    if direction == "north":
        wall_y -= dimensions[1] * 0.5
    elif direction == "south":
        wall_y += dimensions[1] * 0.5
    elif direction == "west":
        wall_x -= dimensions[0] * 0.5
    else:
        wall_x += dimensions[0] * 0.5
    segment_length = (length - DOOR_WIDTH) * 0.5
    for side_index, side in enumerate((-1.0, 1.0)):
        along = side * (DOOR_WIDTH * 0.5 + segment_length * 0.5)
        x = wall_x + (along if horizontal else 0.0)
        y = wall_y + (0.0 if horizontal else along)
        add_box(
            f"Base99_{direction}_Wall_{side_index + 1}",
            (x, y, -FLOOR_HEIGHT + WALL_HEIGHT * 0.5),
            (
                segment_length if horizontal else WALL_THICKNESS,
                WALL_THICKNESS if horizontal else segment_length,
                WALL_HEIGHT,
            ),
            mat,
            collection,
            "BASE_WALL_SEGMENT",
        )
    lintel_height = WALL_HEIGHT - DOOR_HEIGHT
    add_box(
        f"Base99_{direction}_DoorLintel",
        (
            wall_x,
            wall_y,
            -FLOOR_HEIGHT + DOOR_HEIGHT + lintel_height * 0.5,
        ),
        (
            DOOR_WIDTH if horizontal else WALL_THICKNESS,
            WALL_THICKNESS if horizontal else DOOR_WIDTH,
            lintel_height,
        ),
        mat,
        collection,
        "BASE_DOOR_LINTEL",
    )


def rotate_about_core(point, steps):
    x = point[0] - CORE_CENTER[0]
    y = point[1] - CORE_CENTER[1]
    for _ in range(steps % 4):
        x, y = -y, x
    return (x + CORE_CENTER[0], y + CORE_CENTER[1])


def normal_floor_positions():
    return {
        "entry": ((27.5, 2.5), (15.0, 15.0), "stair_entry"),
        "hub": ((27.5, -32.5), (45.0, 45.0), "hub"),
        "main_02": ((77.5, -32.5), (45.0, 45.0), "main"),
        "main_03": ((77.5, -82.5), (45.0, 45.0), "main"),
        "main_04": ((27.5, -82.5), (45.0, 45.0), "main"),
        "main_05": ((-22.5, -82.5), (45.0, 45.0), "main"),
        "main_06": ((-22.5, -32.5), (45.0, 45.0), "main"),
        "exit": ((-22.5, 2.5), (15.0, 15.0), "stair_exit"),
        "branch_01": ((77.5, 17.5), (45.0, 45.0), "branch"),
        "branch_02": ((77.5, 67.5), (45.0, 45.0), "branch"),
        "branch_03": ((27.5, 67.5), (45.0, 45.0), "search"),
        "elevator": ((-22.5, 67.5), (45.0, 45.0), "elevator_access"),
    }


def boss_floor_positions():
    return {
        "entry": ((-22.5, 2.5), (15.0, 15.0), "stair_entry"),
        "hub": ((-22.5, -32.5), (45.0, 45.0), "hub"),
        "main_02": ((-72.5, -32.5), (45.0, 45.0), "main"),
        "prep": ((-72.5, 52.5), (45.0, 45.0), "boss_prep"),
        "boss": ((27.5, 52.5), (90.0, 90.0), "boss"),
        "branch_01": ((27.5, -32.5), (45.0, 45.0), "branch"),
        "branch_02": ((77.5, -32.5), (45.0, 45.0), "branch"),
        "branch_03": ((77.5, -82.5), (45.0, 45.0), "search"),
        "branch_04": ((27.5, -82.5), (45.0, 45.0), "branch"),
        "elevator": ((-22.5, -82.5), (45.0, 45.0), "elevator_access"),
    }


def add_runtime_sync():
    remove_collection(ROOT_COLLECTION)
    root = ensure_top_collection(ROOT_COLLECTION)
    levels = ensure_child_collection(root, LEVEL_COLLECTION)
    base = ensure_child_collection(root, BASE_COLLECTION)
    rooms = ensure_child_collection(root, ROOM_COLLECTION)
    elevators = ensure_child_collection(root, ELEVATOR_COLLECTION)
    door_contract = ensure_child_collection(root, DOOR_COLLECTION)

    floor_mat = material(
        "MAT_PH49_RuntimeFloor",
        (0.035, 0.055, 0.060, 0.36),
        metallic=0.34,
        roughness=0.78,
    )
    base_tile_mat = material(
        "MAT_PH49_BaseTile",
        (0.10, 0.15, 0.16, 1.0),
        metallic=0.46,
        roughness=0.62,
    )
    wall_mat = material(
        "MAT_PH49_BaseWall",
        (0.12, 0.14, 0.14, 1.0),
        metallic=0.58,
        roughness=0.58,
    )
    room_mat = material(
        "MAT_PH49_RoomFootprint",
        (0.04, 0.36, 0.42, 0.82),
        metallic=0.28,
        roughness=0.58,
        emission=(0.02, 0.22, 0.26),
    )
    search_mat = material(
        "MAT_PH49_SearchFootprint",
        (0.42, 0.28, 0.04, 0.88),
        metallic=0.22,
        roughness=0.62,
        emission=(0.38, 0.18, 0.02),
    )
    boss_mat = material(
        "MAT_PH49_BossFootprint",
        (0.46, 0.04, 0.03, 0.88),
        metallic=0.18,
        roughness=0.56,
        emission=(0.42, 0.02, 0.01),
    )
    elevator_mat = material(
        "MAT_PH49_Elevator",
        (0.03, 0.34, 0.38, 1.0),
        metallic=0.82,
        roughness=0.26,
        emission=(0.02, 0.52, 0.60),
    )
    corridor_mat = material(
        "MAT_PH49_Corridor",
        (0.06, 0.20, 0.22, 1.0),
        metallic=0.50,
        roughness=0.50,
        emission=(0.02, 0.28, 0.30),
    )

    for floor_number in range(100, 94, -1):
        z = -FLOOR_HEIGHT * (100 - floor_number)
        stage = add_box(
            f"RuntimeStage_{floor_number}F_250M",
            (CORE_CENTER[0], CORE_CENTER[1], z - 0.12),
            (MAP_SIZE, MAP_SIZE, 0.12),
            floor_mat,
            levels,
            "RUNTIME_FLOOR_STAGE",
        )
        stage["floor_number"] = floor_number
        stage["map_size_m"] = MAP_SIZE

    for side, x in (("West", -32.5), ("East", 32.5)):
        marker = add_empty(
            f"StairFacility_{side}_UNCHANGED",
            (x, CORE_CENTER[1], 0.0),
            levels,
            "STAIR_POSITION_REFERENCE",
            stair_side=side.lower(),
            position_unchanged=True,
        )
        marker.empty_display_size = 3.0

    for tile_y in range(6):
        for tile_x in range(6):
            tile = add_box(
                f"Base99_Tile_X{tile_x + 1:02d}_Y{tile_y + 1:02d}",
                (
                    CORE_CENTER[0] - 12.5 + tile_x * GRID,
                    CORE_CENTER[1] - 12.5 + tile_y * GRID,
                    -FLOOR_HEIGHT + 0.03,
                ),
                (GRID - 0.04, GRID - 0.04, 0.10),
                base_tile_mat,
                base,
                "BASE_GRID_TILE",
            )
            tile["grid_x"] = tile_x
            tile["grid_y"] = tile_y
            tile["floor_number"] = 99

    for direction in ("north", "south", "west", "east"):
        add_centered_wall(
            direction,
            CORE_CENTER,
            (BASE_SIZE, BASE_SIZE),
            base,
            wall_mat,
        )

    for side, x_start, x_end in (
        ("West", CORE_CENTER[0] - BASE_SIZE * 0.5, -30.0),
        ("East", CORE_CENTER[0] + BASE_SIZE * 0.5, 35.0),
    ):
        corridor = add_box(
            f"Base99_{side}_StairCorridor",
            ((x_start + x_end) * 0.5, CORE_CENTER[1], -FLOOR_HEIGHT + 0.04),
            (abs(x_end - x_start), 6.0, 0.12),
            corridor_mat,
            base,
            "BASE_TO_STAIR_CORRIDOR",
        )
        corridor["corridor_length_m"] = abs(x_end - x_start)
        corridor["stair_position_unchanged"] = True

    normal_positions = normal_floor_positions()
    elevator_world_positions = {}
    for floor_number in (98, 97, 96):
        rotation_steps = 0 if floor_number in (98, 96) else 2
        z = -FLOOR_HEIGHT * (100 - floor_number)
        for key, (point, dimensions, role) in normal_positions.items():
            rotated = rotate_about_core(point, rotation_steps)
            footprint_mat = search_mat if role in {"search", "elevator_access"} else room_mat
            footprint = add_box(
                f"Floor{floor_number}_{key}_Footprint",
                (rotated[0], rotated[1], z + 0.05),
                (dimensions[0] - 0.18, dimensions[1] - 0.18, 0.10),
                footprint_mat,
                rooms,
                "RUNTIME_ROOM_FOOTPRINT",
            )
            footprint["floor_number"] = floor_number
            footprint["tower_role"] = role
            footprint["room_dimensions_m"] = dimensions
            if role == "elevator_access":
                direction = "south" if rotated[1] > CORE_CENTER[1] else "north"
                offset = dimensions[1] * 0.5 - 3.2
                elevator_world_positions[floor_number] = (
                    rotated[0],
                    rotated[1] + (offset if direction == "south" else -offset),
                    z,
                    direction,
                )

    z = -FLOOR_HEIGHT * 5
    for key, (point, dimensions, role) in boss_floor_positions().items():
        footprint_mat = (
            boss_mat
            if role == "boss"
            else search_mat
            if role in {"search", "elevator_access"}
            else room_mat
        )
        footprint = add_box(
            f"Floor95_{key}_Footprint",
            (point[0], point[1], z + 0.05),
            (dimensions[0] - 0.18, dimensions[1] - 0.18, 0.10),
            footprint_mat,
            rooms,
            "RUNTIME_ROOM_FOOTPRINT",
        )
        footprint["floor_number"] = 95
        footprint["tower_role"] = role
        footprint["room_dimensions_m"] = dimensions
        if role == "elevator_access":
            elevator_world_positions[95] = (
                point[0],
                point[1] - (dimensions[1] * 0.5 - 3.2),
                z,
                "north",
            )

    elevator_world_positions[99] = (
        CORE_CENTER[0] + 9.0,
        CORE_CENTER[1] + 11.6,
        -FLOOR_HEIGHT,
        "south",
    )
    for floor_number, (x, y, z, side) in elevator_world_positions.items():
        elevator = add_box(
            f"StandaloneElevator_{floor_number}F",
            (x, y, z + 1.55),
            (4.5, 3.0, 3.1),
            elevator_mat,
            elevators,
            "STANDALONE_ELEVATOR_FACILITY",
            bevel=0.08,
        )
        elevator["floor_number"] = floor_number
        elevator["wall_side"] = side
        elevator["is_room_content"] = False

    for floor_number, side, x in (
        (99, "west", CORE_CENTER[0] - BASE_SIZE * 0.5),
        (99, "east", CORE_CENTER[0] + BASE_SIZE * 0.5),
        (98, "east", 35.0),
        (97, "west", -30.0),
        (96, "east", 35.0),
        (95, "west", -30.0),
    ):
        marker = add_box(
            f"DoorContract_{floor_number}F_{side}",
            (
                x,
                CORE_CENTER[1],
                -FLOOR_HEIGHT * (100 - floor_number) + DOOR_HEIGHT * 0.5,
            ),
            (
                0.18 if side in {"west", "east"} else DOOR_WIDTH,
                DOOR_WIDTH if side in {"west", "east"} else 0.18,
                DOOR_HEIGHT,
            ),
            elevator_mat,
            door_contract,
            "RUNTIME_DOOR_CONTRACT",
        )
        marker["floor_number"] = floor_number
        marker["door_side"] = side
        marker["clear_width_m"] = DOOR_WIDTH
        marker["clear_height_m"] = DOOR_HEIGHT


def hide_historical_reviews():
    for collection in bpy.context.scene.collection.children:
        if collection.name.startswith(("00_", "01_", "03_", "05_", "90_")):
            collection.hide_viewport = True
            collection.hide_render = True
            collection["historical_reference"] = True
        elif collection.name == "02_STAIRWELLS":
            collection.hide_viewport = False
            collection.hide_render = False
            collection["position_unchanged_ph49"] = True


def update_scene_metadata():
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.length_unit = "METERS"
    scene["asset_id"] = "ENV-TOWER-DESCENT-KIT-3D"
    scene["asset_version"] = "v007"
    scene["runtime_sync_phase"] = "PH49"
    scene["map_footprint_size_m"] = MAP_SIZE
    scene["functional_core_size_m"] = CORE_SIZE
    scene["base_room_size_m"] = BASE_SIZE
    scene["base_grid_tiles"] = "6x6"
    scene["combat_floors"] = "98,97,96,95"
    scene["door_clear_width_m"] = DOOR_WIDTH
    scene["door_clear_height_m"] = DOOR_HEIGHT
    scene["elevator_placement"] = "standalone_wall_edge"
    scene["lighting_contract"] = "global_fixed_environment_plus_switchable_room_lights"
    scene["source_migration_status"] = "project_local"


ensure_input_scene()
rebuild_door_master()
add_runtime_sync()
hide_historical_reviews()
update_scene_metadata()
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
print(
    "SYNC_V007_OK "
    f"output={OUTPUT_BLEND} map={MAP_SIZE} base={BASE_SIZE} "
    f"door={DOOR_WIDTH}x{DOOR_HEIGHT}"
)
