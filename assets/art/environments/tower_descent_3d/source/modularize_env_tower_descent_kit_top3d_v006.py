"""Convert the v005 tower review scene to a reusable five-metre module kit.

The script keeps the user's two edited stairwell assemblies and the existing
facility props, but replaces every large floor slab, outer wall, core fence,
facility partition, and combat partition with linked 5 m module instances.
The complete three-floor assembly remains in Blender for review; the module
masters live in a named library for later Godot export and runtime assembly.
"""

from pathlib import Path
import math

import bpy
from mathutils import Matrix, Vector


PROJECT_ROOT = Path("/Users/summercards/ShellStorm2")
SOURCE_DIR = PROJECT_ROOT / "assets/art/environments/tower_descent_3d/source"
INPUT_BLEND = SOURCE_DIR / "env_tower_descent_kit_top3d_v005.blend"
OUTPUT_BLEND = SOURCE_DIR / "env_tower_descent_kit_top3d_v006.blend"

GRID_UNIT = 5.0
MAP_UNITS = 67
MAP_SIZE = GRID_UNIT * MAP_UNITS
MAP_HALF = MAP_SIZE * 0.5
CORE_UNITS = 13
CORE_SIZE = GRID_UNIT * CORE_UNITS
CORE_HALF = CORE_SIZE * 0.5
FLOOR_HEIGHT = 9.0
SLAB_THICKNESS = 0.30
WALL_THICKNESS = 0.30
PARAPET_HEIGHT = 1.50
DOOR_CLEAR_WIDTH = 4.0
DOOR_CLEAR_HEIGHT = 4.5

ROOF_Z = 0.0
FACILITY_Z = -9.0
COMBAT_Z = -18.0

MODULE_FLOOR = "ENV-TOWER-FLOOR-TILE-5M"
MODULE_WALL = "ENV-TOWER-WALL-SOLID-5M"
MODULE_PARAPET = "ENV-TOWER-WALL-PARAPET-5M"
MODULE_DOOR = "ENV-TOWER-WALL-DOOR-5M"

OLD_COLLECTIONS = {
    "01A_EXTERIOR_ROOFTOP_FULL_FOOTPRINT",
    "03A_EXTERIOR_FACILITY_FULL_FOOTPRINT",
    "05A_EXTERIOR_COMBAT_FULL_FOOTPRINT",
}

OLD_PREFIXES = (
    "Rooftop_Slab_",
    "Rooftop_OuterField_",
    "Rooftop_Exterior_Parapet_",
    "Rooftop_StairEntry_",
    "Facility_OuterField_",
    "Facility_Exterior_Wall_",
    "Facility_East_Door_",
    "Facility_West_Door_",
    "Facility_InteriorNorth_",
    "Facility_RightCorridor_",
    "Facility_SouthRoom_",
    "Combat_OuterField_",
    "Combat_Exterior_Wall_",
    "Combat_East_Door_",
    "Combat_EastRooms_",
    "Combat_WestRooms_",
    "Combat_NorthRooms_",
    "Combat_SouthRooms_",
)


def ensure_input_scene():
    if Path(bpy.data.filepath).resolve() != INPUT_BLEND.resolve():
        bpy.ops.wm.open_mainfile(filepath=str(INPUT_BLEND))


def ensure_top_collection(name):
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
    scene_root = bpy.context.scene.collection
    for candidate in bpy.data.collections:
        if collection.name in candidate.children:
            candidate.children.unlink(collection)
    if collection.name not in scene_root.children:
        scene_root.children.link(collection)
    return collection


def ensure_child_collection(parent, name):
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
    scene_root = bpy.context.scene.collection
    if collection.name in scene_root.children:
        scene_root.children.unlink(collection)
    for candidate in bpy.data.collections:
        if candidate is parent:
            continue
        if collection.name in candidate.children:
            candidate.children.unlink(collection)
    if collection.name not in parent.children:
        parent.children.link(collection)
    return collection


def remove_collection(name):
    collection = bpy.data.collections.get(name)
    if collection is None:
        return
    bpy.data.collections.remove(collection)


def remove_object(obj):
    mesh = obj.data if obj.type == "MESH" else None
    bpy.data.objects.remove(obj, do_unlink=True)
    if mesh is not None and mesh.users == 0:
        bpy.data.meshes.remove(mesh)


def move_object_to_collection(obj, target):
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    target.objects.link(obj)


def apply_bevel(obj, width):
    if width <= 0.0:
        return
    modifier = obj.modifiers.new("EdgeSoftening", "BEVEL")
    modifier.width = width
    modifier.segments = 2
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


def add_master_box(
    name,
    dimensions,
    geometry_offset,
    material,
    collection,
    bevel=0.0,
):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 0.0))
    obj = bpy.context.object
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.transform(Matrix.Translation(Vector(geometry_offset)))
    if material is not None:
        obj.data.materials.append(material)
    apply_bevel(obj, bevel)
    move_object_to_collection(obj, collection)
    obj.hide_viewport = True
    obj.hide_render = True
    obj["asset_role"] = "MODULE_MASTER_MESH"
    obj["grid_unit_m"] = GRID_UNIT
    return obj


def add_socket(name, location, collection, parent=None):
    socket = bpy.data.objects.new(name, None)
    collection.objects.link(socket)
    socket.empty_display_type = "PLAIN_AXES"
    socket.empty_display_size = 0.35
    socket.location = location
    socket.hide_viewport = True
    socket.hide_render = True
    socket["asset_role"] = "MODULE_SOCKET"
    socket["grid_unit_m"] = GRID_UNIT
    if parent is not None:
        socket.parent = parent
        socket.matrix_parent_inverse.identity()
    return socket


def set_module_metadata(target, module_id, component, units=1):
    target["asset_role"] = "MODULE_MASTER"
    target["module_id"] = module_id
    target["component"] = component
    target["grid_unit_m"] = GRID_UNIT
    target["grid_units"] = units
    target["forward_axis_local"] = "+Y"
    target["span_axis_local"] = "+X"
    target["origin_contract"] = "BOTTOM_CENTER"


def clone_linked_mesh(
    master,
    name,
    location,
    rotation_z,
    collection,
    module_id,
    material=None,
):
    obj = master.copy()
    obj.data = master.data
    obj.name = name
    obj.location = location
    obj.rotation_euler = (0.0, 0.0, rotation_z)
    obj.scale = (1.0, 1.0, 1.0)
    obj.hide_viewport = False
    obj.hide_render = False
    collection.objects.link(obj)
    obj["asset_role"] = "MODULE_INSTANCE"
    obj["module_id"] = module_id
    obj["grid_unit_m"] = GRID_UNIT
    obj["instance_kind"] = "LINKED_MESH"
    obj["rotation_step_90"] = int(round(rotation_z / (math.pi * 0.5))) % 4
    if material is not None and obj.material_slots:
        obj.material_slots[0].link = "OBJECT"
        obj.material_slots[0].material = material
    return obj


def clone_array_mesh(
    master,
    name,
    location,
    rotation_z,
    collection,
    module_id,
    count_x,
    count_y=1,
    material=None,
):
    obj = clone_linked_mesh(
        master,
        name,
        location,
        rotation_z,
        collection,
        module_id,
        material=material,
    )
    obj["asset_role"] = "MODULE_ARRAY_ASSEMBLY"
    obj["array_count_x"] = count_x
    obj["array_count_y"] = count_y
    obj["virtual_module_count"] = count_x * count_y
    obj["array_modifiers_applied"] = False

    array_x = obj.modifiers.new("Array_Grid_X_5M", "ARRAY")
    array_x.count = count_x
    array_x.use_relative_offset = False
    array_x.use_constant_offset = True
    array_x.constant_offset_displace = (GRID_UNIT, 0.0, 0.0)

    if count_y > 1:
        array_y = obj.modifiers.new("Array_Grid_Y_5M", "ARRAY")
        array_y.count = count_y
        array_y.use_relative_offset = False
        array_y.use_constant_offset = True
        array_y.constant_offset_displace = (0.0, GRID_UNIT, 0.0)
    return obj


def clone_door_module(
    master_root,
    name,
    location,
    rotation_z,
    collection,
    connection_role,
):
    root = bpy.data.objects.new(name, None)
    collection.objects.link(root)
    root.empty_display_type = "CUBE"
    root.empty_display_size = 0.6
    root.location = location
    root.rotation_euler = (0.0, 0.0, rotation_z)
    root["asset_role"] = "MODULE_INSTANCE_DOOR"
    root["module_id"] = MODULE_DOOR
    root["grid_unit_m"] = GRID_UNIT
    root["grid_units"] = 1
    root["clear_width_m"] = DOOR_CLEAR_WIDTH
    root["clear_height_m"] = DOOR_CLEAR_HEIGHT
    root["connection_role"] = connection_role
    root["rotation_step_90"] = int(round(rotation_z / (math.pi * 0.5))) % 4

    prefix = "MOD_WALL_DOOR_5M_U01_"
    for source in sorted(master_root.children, key=lambda item: item.name):
        if source.type != "MESH":
            continue
        child = source.copy()
        child.data = source.data
        suffix = source.name.removeprefix(prefix)
        child.name = f"{name}_{suffix}"
        child.hide_viewport = False
        child.hide_render = False
        collection.objects.link(child)
        child.parent = root
        child.matrix_parent_inverse.identity()
        child.matrix_local = source.matrix_local.copy()
        child["asset_role"] = "MODULE_DOOR_COMPONENT_INSTANCE"
        child["module_id"] = MODULE_DOOR
        child["door_component"] = suffix
        child["instance_kind"] = "LINKED_MESH"
    return root


def grid_centers(unit_count):
    start = -(unit_count - 1) * GRID_UNIT * 0.5
    return [start + index * GRID_UNIT for index in range(unit_count)]


def build_floor_grid(level, floor_z, collection, floor_material, roof_opening=False):
    if roof_opening:
        # Four non-overlapping rectangular arrays leave a 5×3 tile stair void:
        # X=-55..-35 and Y=-10..0.
        rectangles = (
            ("WEST", -165.0, -165.0, 22, 67, 0, 0),
            ("EAST", -30.0, -165.0, 40, 67, 27, 0),
            ("OPENING_SOUTH", -55.0, -165.0, 5, 31, 22, 0),
            ("OPENING_NORTH", -55.0, 5.0, 5, 33, 22, 34),
        )
    else:
        rectangles = (("FULL", -165.0, -165.0, 67, 67, 0, 0),)

    count = 0
    for label, start_x, start_y, count_x, count_y, start_col, start_row in rectangles:
        array = clone_array_mesh(
            floor_master,
            f"ASM_{level}_FLOOR_TILE_ARRAY_{label}",
            (start_x, start_y, floor_z),
            0.0,
            collection,
            MODULE_FLOOR,
            count_x,
            count_y,
            material=floor_material,
        )
        array["level"] = level
        array["zone"] = "FLOOR"
        array["grid_start_row"] = start_row
        array["grid_start_col"] = start_col
        count += count_x * count_y

    collection["tile_count"] = count
    collection["array_object_count"] = len(rectangles)
    collection["grid_rows"] = MAP_UNITS
    collection["grid_cols"] = MAP_UNITS
    return count


def build_outer_wall_grid(level, floor_z, collection, master, module_id):
    wall_center = MAP_HALF - WALL_THICKNESS * 0.5
    definitions = (
        ("NORTH", (-165.0, wall_center, floor_z), 0.0),
        ("SOUTH", (165.0, -wall_center, floor_z), math.pi),
        ("EAST", (wall_center, -165.0, floor_z), math.pi * 0.5),
        ("WEST", (-wall_center, 165.0, floor_z), -math.pi * 0.5),
    )
    for side, location, rotation in definitions:
        wall = clone_array_mesh(
            master,
            f"ASM_{level}_OUTER_{'PARAPET' if module_id == MODULE_PARAPET else 'WALL'}_{side}_ARRAY",
            location,
            rotation,
            collection,
            module_id,
            MAP_UNITS,
        )
        wall["level"] = level
        wall["zone"] = "OUTER"
        wall["boundary_side"] = side
        wall["grid_start_index"] = 0
        wall["grid_end_index"] = MAP_UNITS - 1
    count = MAP_UNITS * 4
    collection["module_count"] = count
    collection["modules_per_side"] = MAP_UNITS
    collection["array_object_count"] = 4
    return count


def side_transform(side, tangent, floor_z, half_extent):
    wall_center = half_extent - WALL_THICKNESS * 0.5
    if side == "NORTH":
        return (tangent, wall_center, floor_z), 0.0
    if side == "SOUTH":
        return (tangent, -wall_center, floor_z), math.pi
    if side == "EAST":
        return (wall_center, tangent, floor_z), math.pi * 0.5
    return (-wall_center, tangent, floor_z), -math.pi * 0.5


def build_core_wall_grid(level, floor_z, collection, door_sides):
    centers = grid_centers(CORE_UNITS)
    module_count = 0
    door_count = 0
    for side in ("NORTH", "SOUTH", "EAST", "WEST"):
        for index, tangent in enumerate(centers):
            location, rotation = side_transform(side, tangent, floor_z, CORE_HALF)
            is_door = side in door_sides and index == CORE_UNITS // 2
            base_name = f"ASM_{level}_CORE_{side}_I{index:02d}"
            if is_door:
                root = clone_door_module(
                    door_master_root,
                    f"{base_name}_DOOR",
                    location,
                    rotation,
                    collection,
                    door_sides[side],
                )
                root["level"] = level
                root["zone"] = "CORE"
                root["boundary_side"] = side
                root["grid_index"] = index
                door_count += 1
            else:
                wall = clone_linked_mesh(
                    wall_master,
                    f"{base_name}_WALL",
                    location,
                    rotation,
                    collection,
                    MODULE_WALL,
                )
                wall["level"] = level
                wall["zone"] = "CORE"
                wall["boundary_side"] = side
                wall["grid_index"] = index
            module_count += 1
    collection["module_count"] = module_count
    collection["door_module_count"] = door_count
    collection["core_size_m"] = CORE_SIZE
    return module_count, door_count


def build_partition_line(
    level,
    line_id,
    floor_z,
    collection,
    orientation,
    constant,
    centers,
    door_centers,
):
    rotation = 0.0 if orientation == "HORIZONTAL" else math.pi * 0.5
    module_count = 0
    door_count = 0
    for index, tangent in enumerate(centers):
        location = (
            (tangent, constant, floor_z)
            if orientation == "HORIZONTAL"
            else (constant, tangent, floor_z)
        )
        base_name = f"ASM_{level}_INTERIOR_{line_id}_I{index:02d}"
        if tangent in door_centers:
            root = clone_door_module(
                door_master_root,
                f"{base_name}_DOOR",
                location,
                rotation,
                collection,
                "INTERIOR_ROGUE_DOOR",
            )
            root["level"] = level
            root["zone"] = "INTERIOR"
            root["line_id"] = line_id
            root["grid_index"] = index
            door_count += 1
        else:
            wall = clone_linked_mesh(
                wall_master,
                f"{base_name}_WALL",
                location,
                rotation,
                collection,
                MODULE_WALL,
            )
            wall["level"] = level
            wall["zone"] = "INTERIOR"
            wall["line_id"] = line_id
            wall["grid_index"] = index
        module_count += 1
    return module_count, door_count


ensure_input_scene()

scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0

# Remove only the v005 large floor/wall representation and the non-grid room
# walls/doors. User-edited stairwell children and facility props remain.
for obj in list(bpy.data.objects):
    if (
        obj.name in {"Facility_Slab", "Combat_Slab"}
        or obj.get("asset_role") == "CORE_BOUNDARY_FENCE"
        or any(obj.name.startswith(prefix) for prefix in OLD_PREFIXES)
    ):
        remove_object(obj)

for collection_name in OLD_COLLECTIONS:
    remove_collection(collection_name)

roof_collection = bpy.data.collections["01_FLOOR_ROOFTOP_Z000"]
facility_collection = bpy.data.collections["03_FLOOR_FACILITY_ZNEG009"]
combat_collection = bpy.data.collections["05_FLOOR_COMBAT_ZNEG018"]

roof_tiles = ensure_child_collection(roof_collection, "01B_TILE_GRID_5M")
roof_outer = ensure_child_collection(roof_collection, "01C_OUTER_PARAPET_GRID_5M")
roof_entry = ensure_child_collection(roof_collection, "01D_STAIR_ENTRY_WALL_GRID_5M")
facility_tiles = ensure_child_collection(facility_collection, "03B_TILE_GRID_5M")
facility_outer = ensure_child_collection(facility_collection, "03C_OUTER_WALL_GRID_5M")
facility_core = ensure_child_collection(facility_collection, "03D_CORE_WALL_GRID_5M")
facility_interior = ensure_child_collection(facility_collection, "03E_INTERIOR_WALL_GRID_5M")
combat_tiles = ensure_child_collection(combat_collection, "05B_TILE_GRID_5M")
combat_outer = ensure_child_collection(combat_collection, "05C_OUTER_WALL_GRID_5M")
combat_core = ensure_child_collection(combat_collection, "05D_CORE_WALL_GRID_5M")
combat_interior = ensure_child_collection(combat_collection, "05E_INTERIOR_WALL_GRID_5M")

for collection, role, level in (
    (roof_tiles, "FLOOR_TILE_ASSEMBLY", "ROOFTOP"),
    (roof_outer, "OUTER_PARAPET_ASSEMBLY", "ROOFTOP"),
    (roof_entry, "STAIR_ENTRY_ASSEMBLY", "ROOFTOP"),
    (facility_tiles, "FLOOR_TILE_ASSEMBLY", "FACILITY"),
    (facility_outer, "OUTER_WALL_ASSEMBLY", "FACILITY"),
    (facility_core, "CORE_WALL_ASSEMBLY", "FACILITY"),
    (facility_interior, "INTERIOR_WALL_ASSEMBLY", "FACILITY"),
    (combat_tiles, "FLOOR_TILE_ASSEMBLY", "COMBAT"),
    (combat_outer, "OUTER_WALL_ASSEMBLY", "COMBAT"),
    (combat_core, "CORE_WALL_ASSEMBLY", "COMBAT"),
    (combat_interior, "INTERIOR_WALL_ASSEMBLY", "COMBAT"),
):
    collection["asset_role"] = role
    collection["level"] = level
    collection["grid_unit_m"] = GRID_UNIT

# Module library and four stable component collections.
module_library = ensure_top_collection("10_MODULE_LIBRARY_5M")
floor_module_collection = ensure_child_collection(
    module_library,
    "10A_MOD_FLOOR_TILE_5M_U01",
)
wall_module_collection = ensure_child_collection(
    module_library,
    "10B_MOD_WALL_SOLID_5M_U01",
)
parapet_module_collection = ensure_child_collection(
    module_library,
    "10C_MOD_WALL_PARAPET_5M_U01",
)
door_module_collection = ensure_child_collection(
    module_library,
    "10D_MOD_WALL_DOOR_5M_U01",
)
module_library["asset_role"] = "MODULE_LIBRARY"
module_library["parent_asset_id"] = "ENV-TOWER-DESCENT-KIT-3D"
module_library["grid_unit_m"] = GRID_UNIT

roof_material = bpy.data.materials["MAT_Rooftop"]
facility_material = bpy.data.materials["MAT_FacilityFloor"]
combat_material = bpy.data.materials["MAT_CombatFloor"]
wall_material = bpy.data.materials["MAT_Structure_DarkSteel"]
door_material = bpy.data.materials["MAT_Door_CyanSteel"]

floor_master = add_master_box(
    "MOD_FLOOR_TILE_5M_U01",
    (GRID_UNIT, GRID_UNIT, SLAB_THICKNESS),
    (0.0, 0.0, -SLAB_THICKNESS * 0.5),
    roof_material,
    floor_module_collection,
    bevel=0.015,
)
set_module_metadata(floor_master, MODULE_FLOOR, "floor_tile")
floor_master["dimensions_m"] = (GRID_UNIT, GRID_UNIT, SLAB_THICKNESS)
for suffix, location in (
    ("N", (0.0, GRID_UNIT * 0.5, 0.0)),
    ("S", (0.0, -GRID_UNIT * 0.5, 0.0)),
    ("E", (GRID_UNIT * 0.5, 0.0, 0.0)),
    ("W", (-GRID_UNIT * 0.5, 0.0, 0.0)),
):
    add_socket(
        f"MOD_FLOOR_TILE_5M_U01_SOCKET_{suffix}",
        location,
        floor_module_collection,
    )

wall_master = add_master_box(
    "MOD_WALL_SOLID_5M_U01",
    (GRID_UNIT, WALL_THICKNESS, FLOOR_HEIGHT),
    (0.0, 0.0, FLOOR_HEIGHT * 0.5),
    wall_material,
    wall_module_collection,
    bevel=0.025,
)
set_module_metadata(wall_master, MODULE_WALL, "wall_solid")
wall_master["dimensions_m"] = (GRID_UNIT, WALL_THICKNESS, FLOOR_HEIGHT)
add_socket(
    "MOD_WALL_SOLID_5M_U01_SOCKET_L",
    (-GRID_UNIT * 0.5, 0.0, 0.0),
    wall_module_collection,
)
add_socket(
    "MOD_WALL_SOLID_5M_U01_SOCKET_R",
    (GRID_UNIT * 0.5, 0.0, 0.0),
    wall_module_collection,
)

parapet_master = add_master_box(
    "MOD_WALL_PARAPET_5M_U01",
    (GRID_UNIT, WALL_THICKNESS, PARAPET_HEIGHT),
    (0.0, 0.0, PARAPET_HEIGHT * 0.5),
    wall_material,
    parapet_module_collection,
    bevel=0.025,
)
set_module_metadata(parapet_master, MODULE_PARAPET, "wall_parapet")
parapet_master["dimensions_m"] = (GRID_UNIT, WALL_THICKNESS, PARAPET_HEIGHT)
add_socket(
    "MOD_WALL_PARAPET_5M_U01_SOCKET_L",
    (-GRID_UNIT * 0.5, 0.0, 0.0),
    parapet_module_collection,
)
add_socket(
    "MOD_WALL_PARAPET_5M_U01_SOCKET_R",
    (GRID_UNIT * 0.5, 0.0, 0.0),
    parapet_module_collection,
)

door_master_root = bpy.data.objects.new("MOD_WALL_DOOR_5M_U01_ROOT", None)
door_module_collection.objects.link(door_master_root)
door_master_root.empty_display_type = "CUBE"
door_master_root.empty_display_size = 0.7
door_master_root.hide_viewport = True
door_master_root.hide_render = True
set_module_metadata(door_master_root, MODULE_DOOR, "wall_door")
door_master_root["clear_width_m"] = DOOR_CLEAR_WIDTH
door_master_root["clear_height_m"] = DOOR_CLEAR_HEIGHT
door_master_root["door_leaf_independent"] = True

door_piece_specs = (
    (
        "Pier_L",
        (0.50, WALL_THICKNESS, FLOOR_HEIGHT),
        (-2.25, 0.0, FLOOR_HEIGHT * 0.5),
        wall_material,
    ),
    (
        "Pier_R",
        (0.50, WALL_THICKNESS, FLOOR_HEIGHT),
        (2.25, 0.0, FLOOR_HEIGHT * 0.5),
        wall_material,
    ),
    (
        "Lintel",
        (DOOR_CLEAR_WIDTH, WALL_THICKNESS, FLOOR_HEIGHT - DOOR_CLEAR_HEIGHT),
        (0.0, 0.0, DOOR_CLEAR_HEIGHT + (FLOOR_HEIGHT - DOOR_CLEAR_HEIGHT) * 0.5),
        wall_material,
    ),
    ("Frame_L", (0.14, 0.42, 4.80), (-2.0, 0.0, 2.40), door_material),
    ("Frame_R", (0.14, 0.42, 4.80), (2.0, 0.0, 2.40), door_material),
    ("Frame_Top", (4.14, 0.42, 0.30), (0.0, 0.0, 4.65), door_material),
)
for suffix, dimensions, offset, material in door_piece_specs:
    piece = add_master_box(
        f"MOD_WALL_DOOR_5M_U01_{suffix}",
        dimensions,
        offset,
        material,
        door_module_collection,
        bevel=0.02,
    )
    piece.parent = door_master_root
    piece.matrix_parent_inverse.identity()
    piece["asset_role"] = "MODULE_MASTER_DOOR_COMPONENT"
    piece["module_id"] = MODULE_DOOR
    piece["door_component"] = suffix

door_leaf = add_master_box(
    "MOD_WALL_DOOR_5M_U01_DoorLeaf_OPEN",
    (3.80, 0.18, 4.40),
    (1.90, 0.0, 2.20),
    door_material,
    door_module_collection,
    bevel=0.035,
)
door_leaf.parent = door_master_root
door_leaf.matrix_parent_inverse.identity()
door_leaf.location = (-2.0, 0.0, 0.0)
door_leaf.rotation_euler.z = math.radians(-72.0)
door_leaf["asset_role"] = "MODULE_MASTER_DOOR_LEAF"
door_leaf["module_id"] = MODULE_DOOR
door_leaf["door_component"] = "DoorLeaf_OPEN"
door_leaf["interaction_child"] = True

add_socket(
    "MOD_WALL_DOOR_5M_U01_SOCKET_L",
    (-GRID_UNIT * 0.5, 0.0, 0.0),
    door_module_collection,
    parent=door_master_root,
)
add_socket(
    "MOD_WALL_DOOR_5M_U01_SOCKET_R",
    (GRID_UNIT * 0.5, 0.0, 0.0),
    door_module_collection,
    parent=door_master_root,
)
add_socket(
    "MOD_WALL_DOOR_5M_U01_SOCKET_INTERACT",
    (0.0, -1.0, 1.2),
    door_module_collection,
    parent=door_master_root,
)

for collection, module_id, component in (
    (floor_module_collection, MODULE_FLOOR, "floor_tile"),
    (wall_module_collection, MODULE_WALL, "wall_solid"),
    (parapet_module_collection, MODULE_PARAPET, "wall_parapet"),
    (door_module_collection, MODULE_DOOR, "wall_door"),
):
    collection["asset_role"] = "MODULE_DEFINITION"
    collection["module_id"] = module_id
    collection["component"] = component
    collection["grid_unit_m"] = GRID_UNIT
    collection["source_asset_id"] = "ENV-TOWER-DESCENT-KIT-3D"

# Move both stair assemblies to the nearest 5 m core boundary. Their child
# geometry and hand-edited special wall heights stay untouched.
generic_root = bpy.data.objects["Stair_Generic_Rotatable_ROOT"]
special_root = bpy.data.objects["Stair_Special_Rooftop_ROOT"]
generic_root.location.x = CORE_HALF
special_root.location.x = -CORE_HALF
generic_root["grid_anchor_x_m"] = CORE_HALF
special_root["grid_anchor_x_m"] = -CORE_HALF
generic_root["interface_grid_unit_m"] = GRID_UNIT
special_root["interface_grid_unit_m"] = GRID_UNIT

# Roof opening occupies exactly 5 columns by 3 rows on the five-metre grid.
map_centers = grid_centers(MAP_UNITS)
roof_open_x = {-55.0, -50.0, -45.0, -40.0, -35.0}
roof_open_y = {-10.0, -5.0, 0.0}
roof_skipped = {
    (row, col)
    for row, y in enumerate(map_centers)
    for col, x in enumerate(map_centers)
    if x in roof_open_x and y in roof_open_y
}

roof_tile_count = build_floor_grid(
    "ROOFTOP",
    ROOF_Z,
    roof_tiles,
    roof_material,
    roof_opening=True,
)
facility_tile_count = build_floor_grid(
    "FACILITY",
    FACILITY_Z,
    facility_tiles,
    facility_material,
)
combat_tile_count = build_floor_grid(
    "COMBAT",
    COMBAT_Z,
    combat_tiles,
    combat_material,
)

roof_wall_count = build_outer_wall_grid(
    "ROOFTOP",
    ROOF_Z,
    roof_outer,
    parapet_master,
    MODULE_PARAPET,
)
facility_outer_count = build_outer_wall_grid(
    "FACILITY",
    FACILITY_Z,
    facility_outer,
    wall_master,
    MODULE_WALL,
)
combat_outer_count = build_outer_wall_grid(
    "COMBAT",
    COMBAT_Z,
    combat_outer,
    wall_master,
    MODULE_WALL,
)

roof_entry_door = clone_door_module(
    door_master_root,
    "ASM_ROOFTOP_STAIR_ENTRY_WEST_I06_DOOR",
    (-CORE_HALF + WALL_THICKNESS * 0.5, 0.0, ROOF_Z),
    -math.pi * 0.5,
    roof_entry,
    "STAIR_DOWN_TO_FACILITY",
)
roof_entry_door["level"] = "ROOFTOP"
roof_entry_door["zone"] = "STAIR_ENTRY"
roof_entry["module_count"] = 1
roof_entry["door_module_count"] = 1

facility_core_count, facility_core_doors = build_core_wall_grid(
    "FACILITY",
    FACILITY_Z,
    facility_core,
    {
        "WEST": "STAIR_UP_TO_ROOFTOP",
        "EAST": "STAIR_DOWN_TO_COMBAT",
    },
)
combat_core_count, combat_core_doors = build_core_wall_grid(
    "COMBAT",
    COMBAT_Z,
    combat_core,
    {
        "EAST": "STAIR_UP_TO_FACILITY",
        "WEST": "RESERVED_RANDOM_STAIR_DOWN",
    },
)

facility_module_count = 0
facility_door_count = 0
for args in (
    (
        "NORTH_SERVICE",
        "HORIZONTAL",
        15.0,
        grid_centers(11),
        {-20.0, 0.0, 20.0},
    ),
    (
        "EAST_CORRIDOR",
        "VERTICAL",
        15.0,
        grid_centers(5),
        {0.0},
    ),
    (
        "SOUTH_ROOM",
        "HORIZONTAL",
        -15.0,
        grid_centers(5),
        {0.0},
    ),
):
    modules, doors = build_partition_line(
        "FACILITY",
        args[0],
        FACILITY_Z,
        facility_interior,
        args[1],
        args[2],
        args[3],
        args[4],
    )
    facility_module_count += modules
    facility_door_count += doors
facility_interior["module_count"] = facility_module_count
facility_interior["door_module_count"] = facility_door_count

combat_module_count = 0
combat_door_count = 0
for args in (
    (
        "NORTH_ROOMS",
        "HORIZONTAL",
        15.0,
        grid_centers(11),
        {-15.0, 15.0},
    ),
    (
        "SOUTH_ROOMS",
        "HORIZONTAL",
        -15.0,
        grid_centers(11),
        {-15.0, 15.0},
    ),
    (
        "EAST_ROOMS",
        "VERTICAL",
        15.0,
        grid_centers(5),
        {0.0},
    ),
    (
        "WEST_ROOMS",
        "VERTICAL",
        -15.0,
        grid_centers(5),
        {0.0},
    ),
):
    modules, doors = build_partition_line(
        "COMBAT",
        args[0],
        COMBAT_Z,
        combat_interior,
        args[1],
        args[2],
        args[3],
        args[4],
    )
    combat_module_count += modules
    combat_door_count += doors
combat_interior["module_count"] = combat_module_count
combat_interior["door_module_count"] = combat_door_count

map_camera = bpy.data.objects.get("CAM_MapFootprintPlan")
if map_camera is not None and map_camera.type == "CAMERA":
    map_camera.data.ortho_scale = MAP_SIZE * 1.08

scene["asset_id"] = "ENV-TOWER-DESCENT-KIT-3D"
scene["asset_version"] = "v006"
scene["derived_from"] = str(INPUT_BLEND)
scene["grid_unit_m"] = GRID_UNIT
scene["map_grid_units"] = MAP_UNITS
scene["map_footprint_size_m"] = MAP_SIZE
scene["map_footprint_scale_xy"] = 5.0
scene["functional_core_grid_units"] = CORE_UNITS
scene["functional_core_size_m"] = CORE_SIZE
scene["exterior_boundary_half_extent_m"] = MAP_HALF
scene["floor_module_id"] = MODULE_FLOOR
scene["wall_module_id"] = MODULE_WALL
scene["parapet_module_id"] = MODULE_PARAPET
scene["door_module_id"] = MODULE_DOOR
scene["roof_floor_tile_count"] = roof_tile_count
scene["facility_floor_tile_count"] = facility_tile_count
scene["combat_floor_tile_count"] = combat_tile_count
scene["roof_open_tile_count"] = len(roof_skipped)
scene["outer_modules_per_level"] = roof_wall_count
scene["facility_core_module_count"] = facility_core_count
scene["facility_core_door_count"] = facility_core_doors
scene["combat_core_module_count"] = combat_core_count
scene["combat_core_door_count"] = combat_core_doors
scene["facility_interior_module_count"] = facility_module_count
scene["facility_interior_door_count"] = facility_door_count
scene["combat_interior_module_count"] = combat_module_count
scene["combat_interior_door_count"] = combat_door_count
scene["assembly_strategy"] = "LINKED_5M_MODULES; EXPORT_MASTERS_FOR_GODOT"
scene["godot_integration_status"] = "NOT_IMPORTED_AWAITING_USER_APPROVAL"

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))

print(f"SAVED={OUTPUT_BLEND}")
print(f"GRID_UNIT={GRID_UNIT:.3f}")
print(f"MAP_SIZE={MAP_SIZE:.3f}")
print(f"CORE_SIZE={CORE_SIZE:.3f}")
print(
    "FLOOR_TILES="
    f"{roof_tile_count}+{facility_tile_count}+{combat_tile_count}"
)
print(
    "OUTER_MODULES="
    f"{roof_wall_count}+{facility_outer_count}+{combat_outer_count}"
)
print(
    "FACILITY_MODULES="
    f"core:{facility_core_count}/doors:{facility_core_doors},"
    f"interior:{facility_module_count}/doors:{facility_door_count}"
)
print(
    "COMBAT_MODULES="
    f"core:{combat_core_count}/doors:{combat_core_doors},"
    f"interior:{combat_module_count}/doors:{combat_door_count}"
)
