import bpy
from mathutils import Vector


EXPECTED_COLLECTIONS = {
    "00_BUILDING_GUIDES",
    "01_FLOOR_ROOFTOP_Z000",
    "02_STAIR_ROOF_TO_FACILITY",
    "03_FLOOR_FACILITY_ZNEG009",
    "04_STAIR_FACILITY_TO_COMBAT",
    "05_FLOOR_COMBAT_ZNEG018",
    "90_LIGHTS_CAMERAS",
}
EXPECTED_FLOOR_Z = {0.0, -9.0, -18.0}
EPSILON = 0.001


def require(condition, message):
    if not condition:
        raise AssertionError(message)


scene = bpy.context.scene
actual_collections = {collection.name for collection in bpy.data.collections}
require(actual_collections == EXPECTED_COLLECTIONS, f"Unexpected collections: {sorted(actual_collections)}")
require(scene.get("layout_mode") == "THREE_FLOOR_GAME_STACK", "Scene is not in stacked layout mode")
require(list(scene.get("floor_elevations_m")) == [0.0, -9.0, -18.0], "Floor elevations are incorrect")
require(list(scene.get("stair_side_sequence")) == ["west", "east"], "Stair side sequence is incorrect")

mesh_objects = [obj for obj in bpy.data.objects if obj.type == "MESH"]
require(mesh_objects, "No mesh objects found")
require(
    all((Vector(obj.scale) - Vector((1.0, 1.0, 1.0))).length <= EPSILON for obj in mesh_objects),
    "At least one mesh object has unapplied scale",
)
require(
    not any("MODULE" in collection.name or "ASSEMBLY" in collection.name for collection in bpy.data.collections),
    "Standalone component collection still exists",
)

floor_panels = [obj for obj in mesh_objects if "walkable_surface_z" in obj]
require(floor_panels, "No floor panels carry walkable surface metadata")
actual_floor_z = {round(float(obj["walkable_surface_z"]), 3) for obj in floor_panels}
require(actual_floor_z == EXPECTED_FLOOR_Z, f"Floor surfaces are incorrect: {sorted(actual_floor_z)}")

stair_roots = [obj for obj in bpy.data.objects if obj.type == "EMPTY" and obj.name.endswith("_ROOT")]
require(len(stair_roots) == 2, f"Expected two stair roots, found {len(stair_roots)}")
for root in stair_roots:
    upper = Vector(root["upper_door_world"])
    lower = Vector(root["lower_door_world"])
    require(abs(upper.x - lower.x) <= EPSILON, f"{root.name}: door X is misaligned")
    require(abs(upper.y - lower.y) <= EPSILON, f"{root.name}: door Y is misaligned")
    require(abs((upper.z - lower.z) - 9.0) <= EPSILON, f"{root.name}: floor delta is not 9m")
    require(abs(float(root["passage_width_m"]) - 6.0) <= EPSILON, f"{root.name}: stair width is not 6m")
    points = [Vector(point) for point in root["path_points_world"]]
    require(len(points) == 7, f"{root.name}: expected seven path points")
    require(all((points[index + 1] - points[index]).length > 0.1 for index in range(6)), f"{root.name}: zero-length path")

door_leaves = [obj for obj in mesh_objects if obj.name.endswith("_DoorLeaf_OPEN")]
require(len(door_leaves) >= 10, f"Expected exterior and interior doors, found {len(door_leaves)}")
require(
    all(obj.get("default_preview_state") == "OPEN" for obj in door_leaves),
    "At least one preview door is not open",
)

roof_collection = bpy.data.collections["01_FLOOR_ROOFTOP_Z000"]
roof_panels = [obj for obj in roof_collection.objects if obj.type == "MESH" and obj.name.startswith("Rooftop_Slab")]
require(len(roof_panels) == 3, f"Edge-connected rooftop opening should split the slab into three panels, found {len(roof_panels)}")

for root in stair_roots:
    points = [Vector(point) for point in root["path_points_world"]]
    require(
        all(abs(points[index].z - points[index + 1].z) <= 4.5 + EPSILON for index in range(6)),
        f"{root.name}: a segment exceeds one half-floor drop",
    )

print("TOWER_BLENDER_STACK_QA_OK")
print(f"COLLECTIONS={len(actual_collections)}")
print(f"MESH_OBJECTS={len(mesh_objects)}")
print(f"DOOR_LEAVES={len(door_leaves)}")
print(f"FLOOR_SURFACES={sorted(actual_floor_z, reverse=True)}")
for root in stair_roots:
    print(
        f"{root.name}: upper={tuple(round(value, 3) for value in root['upper_door_world'])} "
        f"lower={tuple(round(value, 3) for value in root['lower_door_world'])}"
    )
