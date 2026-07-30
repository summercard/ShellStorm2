"""Expand the complete tower floor enclosure from the v004 review source.

v004 already extended every walkable slab to a 335.410 m square, but it kept
the old rooftop parapet and facility/combat exterior walls around the central
core.  This correction keeps the user-edited stairs, rooms, doors, props, core
fences, and floor panels unchanged while moving the true exterior shell to the
same five-times boundary as the floor.
"""

from pathlib import Path
import math

import bpy


PROJECT_ROOT = Path("/Users/summercards/ShellStorm2")
SOURCE_DIR = PROJECT_ROOT / "assets/art/environments/tower_descent_3d/source"
INPUT_BLEND = SOURCE_DIR / "env_tower_descent_kit_top3d_v004.blend"
OUTPUT_BLEND = SOURCE_DIR / "env_tower_descent_kit_top3d_v005.blend"

CORE_SIZE = 30.0 * math.sqrt(5.0)
MAP_SIZE = CORE_SIZE * 5.0
MAP_HALF = MAP_SIZE * 0.5
FLOOR_HEIGHT = 9.0
WALL_THICKNESS = 0.30
PARAPET_HEIGHT = 1.50

ROOF_Z = 0.0
FACILITY_Z = -9.0
COMBAT_Z = -18.0

OLD_ROOFTOP_PARAPETS = {
    "Rooftop_Parapet_East_End",
    "Rooftop_Parapet_North_End",
    "Rooftop_Parapet_South_End",
    "Rooftop_Parapet_West_01",
    "Rooftop_Parapet_West_End",
}

OLD_CORE_EXTERIOR_WALLS = {
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


def ensure_input_scene():
    if Path(bpy.data.filepath).resolve() != INPUT_BLEND.resolve():
        bpy.ops.wm.open_mainfile(filepath=str(INPUT_BLEND))


def ensure_child_collection(parent, name):
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
    for candidate in bpy.data.collections:
        if candidate is parent:
            continue
        if collection.name in candidate.children:
            candidate.children.unlink(collection)
    scene_root = bpy.context.scene.collection
    if collection.name in scene_root.children:
        scene_root.children.unlink(collection)
    if collection.name not in parent.children:
        parent.children.link(collection)
    return collection


def move_object_to_collection(obj, target):
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    target.objects.link(obj)


def remove_object(name):
    obj = bpy.data.objects.get(name)
    if obj is None:
        return
    mesh = obj.data if obj.type == "MESH" else None
    bpy.data.objects.remove(obj, do_unlink=True)
    if mesh is not None and mesh.users == 0:
        bpy.data.meshes.remove(mesh)


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


def add_full_perimeter(prefix, floor_z, height, role, collection, material):
    """Add four joined wall pieces whose outside faces match the slab edge."""

    coordinate = MAP_HALF - WALL_THICKNESS * 0.5
    inner_span = MAP_SIZE - WALL_THICKNESS * 2.0
    center_z = floor_z + height * 0.5
    definitions = (
        (
            "North",
            (0.0, coordinate, center_z),
            (MAP_SIZE, WALL_THICKNESS, height),
        ),
        (
            "South",
            (0.0, -coordinate, center_z),
            (MAP_SIZE, WALL_THICKNESS, height),
        ),
        (
            "East",
            (coordinate, 0.0, center_z),
            (WALL_THICKNESS, inner_span, height),
        ),
        (
            "West",
            (-coordinate, 0.0, center_z),
            (WALL_THICKNESS, inner_span, height),
        ),
    )

    result = []
    for side, location, dimensions in definitions:
        obj = add_box(
            f"{prefix}_{side}",
            location,
            dimensions,
            material,
            collection,
            bevel=0.025,
        )
        obj["asset_role"] = role
        obj["boundary_side"] = side.upper()
        obj["map_size_m"] = MAP_SIZE
        obj["wall_thickness_m"] = WALL_THICKNESS
        obj["floor_z_m"] = floor_z
        obj["top_z_m"] = floor_z + height
        obj["outside_face_on_map_boundary"] = True
        result.append(obj)
    return result


ensure_input_scene()

scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0

roof_collection = bpy.data.collections["01_FLOOR_ROOFTOP_Z000"]
facility_collection = bpy.data.collections["03_FLOOR_FACILITY_ZNEG009"]
combat_collection = bpy.data.collections["05_FLOOR_COMBAT_ZNEG018"]

roof_exterior = ensure_child_collection(
    roof_collection,
    "01A_EXTERIOR_ROOFTOP_FULL_FOOTPRINT",
)
facility_exterior = ensure_child_collection(
    facility_collection,
    "03A_EXTERIOR_FACILITY_FULL_FOOTPRINT",
)
combat_exterior = ensure_child_collection(
    combat_collection,
    "05A_EXTERIOR_COMBAT_FULL_FOOTPRINT",
)

for collection, level, role in (
    (roof_exterior, "ROOFTOP", "FULL_FOOTPRINT_PARAPET_FOLDER"),
    (facility_exterior, "FACILITY", "FULL_FOOTPRINT_EXTERIOR_FOLDER"),
    (combat_exterior, "COMBAT", "FULL_FOOTPRINT_EXTERIOR_FOLDER"),
):
    collection["asset_role"] = role
    collection["level"] = level
    collection["map_size_m"] = MAP_SIZE
    collection["boundary_coordinate_m"] = MAP_HALF

# The old walls described the 67.082/111.803 m inner core.  They must not
# remain as a second building exterior after the floor becomes 335.410 m.
for object_name in sorted(OLD_ROOFTOP_PARAPETS | OLD_CORE_EXTERIOR_WALLS):
    remove_object(object_name)

structure_material = bpy.data.materials["MAT_Structure_DarkSteel"]

roof_parapets = add_full_perimeter(
    "Rooftop_Exterior_Parapet",
    ROOF_Z,
    PARAPET_HEIGHT,
    "FULL_FOOTPRINT_ROOFTOP_PARAPET",
    roof_exterior,
    structure_material,
)
facility_walls = add_full_perimeter(
    "Facility_Exterior_Wall",
    FACILITY_Z,
    FLOOR_HEIGHT,
    "FULL_FOOTPRINT_EXTERIOR_WALL",
    facility_exterior,
    structure_material,
)
combat_walls = add_full_perimeter(
    "Combat_Exterior_Wall",
    COMBAT_Z,
    FLOOR_HEIGHT,
    "FULL_FOOTPRINT_EXTERIOR_WALL",
    combat_exterior,
    structure_material,
)

for obj in facility_walls:
    obj["physical_span"] = "FACILITY_FLOOR_TO_ROOFTOP"
for obj in combat_walls:
    obj["physical_span"] = "COMBAT_FLOOR_TO_FACILITY"
for obj in roof_parapets:
    obj["physical_span"] = "ROOFTOP_EDGE_ABOVE_ROOF"

scene["asset_id"] = "ENV-TOWER-DESCENT-KIT-3D"
scene["asset_version"] = "v005"
scene["derived_from"] = str(INPUT_BLEND)
scene["map_footprint_size_m"] = MAP_SIZE
scene["map_footprint_scale_xy"] = 5.0
scene["functional_core_size_m"] = CORE_SIZE
scene["exterior_boundary_half_extent_m"] = MAP_HALF
scene["exterior_shell_matches_floor_footprint"] = True
scene["old_core_full_height_walls_removed"] = True
scene["stairwell_variants"] = ["SPECIAL_ROOFTOP", "GENERIC_ROTATABLE"]
scene["godot_integration_status"] = "NOT_IMPORTED_AWAITING_USER_APPROVAL"

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))

print(f"SAVED={OUTPUT_BLEND}")
print(f"MAP_SIZE={MAP_SIZE:.6f}")
print(f"BOUNDARY=+/-{MAP_HALF:.6f}")
print(f"ROOFTOP_PARAPETS={len(roof_parapets)}")
print(f"FACILITY_EXTERIOR_WALLS={len(facility_walls)}")
print(f"COMBAT_EXTERIOR_WALLS={len(combat_walls)}")
