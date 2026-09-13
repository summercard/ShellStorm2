"""Build the authored 12 m tower wall and stair assets from kit source v010.

The 5 m X/Z footprint, 2.2 x 2.5 m door contract, tread thickness, guard
height, and 0.1 m top clearance stay unchanged.  Stair flights gain five
treads each instead of vertically scaling the old 9 m object hierarchy.
"""

from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "assets/art/environments/tower_descent_3d/source"
COMPONENT_DIR = ROOT / "assets/art/environments/tower_descent_3d/components"
OUTPUT_BLEND = SOURCE_DIR / "env_tower_descent_kit_top3d_v011.blend"
FLOOR_HEIGHT = 12.0
VISUAL_HEIGHT = 11.9
HALF_HEIGHT = FLOOR_HEIGHT * 0.5
EPSILON = 1.0e-4
STAIR_ROOTS = (
    "Stair_Generic_Rotatable_ROOT",
    "Stair_Special_Rooftop_ROOT",
)


def descendants(root):
    result = []
    pending = list(root.children)
    while pending:
        child = pending.pop()
        result.append(child)
        pending.extend(child.children)
    return result


def points_in_root(root, obj):
    to_root = root.matrix_world.inverted() @ obj.matrix_world
    return to_root, [to_root @ vertex.co for vertex in obj.data.vertices]


def rewrite_root_points(root, obj, mapper):
    to_root, points = points_in_root(root, obj)
    from_root = to_root.inverted()
    for vertex, point in zip(obj.data.vertices, points):
        vertex.co = from_root @ mapper(point.copy())
    obj.data.update()


def root_bounds(root, obj):
    _, points = points_in_root(root, obj)
    return (
        Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points))),
        Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points))),
    )


def move_in_root(root, obj, delta_z):
    rewrite_root_points(root, obj, lambda point: Vector((point.x, point.y, point.z + delta_z)))


def replace_treads(root, prefix, upper):
    old = sorted(
        [obj for obj in descendants(root) if f"{prefix}_Tread_" in obj.name],
        key=lambda obj: obj.name,
    )
    if len(old) != 15:
        raise RuntimeError(f"{root.name} {prefix} expected 15 treads, got {len(old)}")
    prototype = old[0].copy()
    prototype.data = old[0].data.copy()
    # Keep the template detached; an unlinked object with a parent still appears
    # in parent.children and cannot be selected through the active view layer.
    prototype.parent = None
    parent = old[0].parent
    collection = old[0].users_collection[0]
    x = old[0].location.x
    start_y = 3.6203 if upper else 17.6203
    start_z = -0.085 if upper else -6.085
    for obj in old:
        bpy.data.objects.remove(obj, do_unlink=True)
    for index in range(20):
        tread = prototype.copy()
        tread.data = prototype.data.copy()
        tread.name = f"{root.name}_{prefix}_Tread_{index + 1:02d}"
        tread.parent = parent
        tread.matrix_parent_inverse = Matrix.Identity(4)
        tread.location = (
            x,
            start_y + index * 0.75 if upper else start_y - index * 0.75,
            start_z - index * 0.30,
        )
        collection.objects.link(tread)


def update_stair(root):
    meshes = [obj for obj in descendants(root) if obj.type == "MESH"]
    for obj in meshes:
        obj.data = obj.data.copy()

    walls = [obj for obj in meshes if "EnclosureWall_" in obj.name]
    if len(walls) != 4:
        raise RuntimeError(f"{root.name} expected four enclosure walls")
    for wall in walls:
        low, high = root_bounds(root, wall)
        span = high.z - low.z
        rewrite_root_points(
            root,
            wall,
            lambda point, lo=low.z, size=span: Vector(
                (point.x, point.y, -FLOOR_HEIGHT + (point.z - lo) / size * VISUAL_HEIGHT)
            ),
        )
        wall["logical_height_m"] = FLOOR_HEIGHT
        wall["visual_height_m"] = VISUAL_HEIGHT
        wall["visual_top_clearance_m"] = 0.1

    turn = next(obj for obj in meshes if obj.name.endswith("TurnLanding_Walkable"))
    lower_landing = next(obj for obj in meshes if obj.name.endswith("LowerDoorLanding_Walkable"))
    move_in_root(root, turn, -1.5)
    move_in_root(root, lower_landing, -3.0)

    for obj in meshes:
        if "UpperFlight_Walkable" in obj.name or "UpperFlight_Guard_" in obj.name:
            rewrite_root_points(
                root,
                obj,
                lambda point: Vector(
                    (point.x, point.y, point.z - 1.5 * max(0.0, min(1.0, (point.y - 3.0341) / 15.1724)))
                ),
            )
        elif "LowerFlight_Walkable" in obj.name or "LowerFlight_Guard_" in obj.name:
            rewrite_root_points(
                root,
                obj,
                lambda point: Vector(
                    (point.x, point.y, point.z - 1.5 - 1.5 * max(0.0, min(1.0, (18.2065 - point.y) / 15.1724)))
                ),
            )

    replace_treads(root, "UpperFlight", True)
    replace_treads(root, "LowerFlight", False)
    lower_socket = next(obj for obj in descendants(root) if obj.name.endswith("SOCKET_LOWER_DOOR"))
    lower_socket.location.z = -FLOOR_HEIGHT
    root["floor_height_m"] = FLOOR_HEIGHT
    root["lower_floor_z_m"] = -FLOOR_HEIGHT
    root["lower_landing_top_m"] = -VISUAL_HEIGHT
    root["enclosure_visual_z_range_m"] = [-FLOOR_HEIGHT, -0.1]
    root["treads_per_flight"] = 20
    root["tread_rise_m"] = 0.3
    root["tread_run_m"] = 0.75


def select_tree(root):
    bpy.ops.object.select_all(action="DESELECT")
    selected = [root, *descendants(root)]
    for obj in selected:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    return selected


def export_tree(root, output, asset_id):
    original = root.matrix_world.copy()
    root.matrix_world = Matrix.Identity(4)
    root["asset_id"] = asset_id
    root["asset_version"] = "v001"
    root["blender_source_version"] = "v011"
    root["origin_contract"] = "UPPER_DOOR_SOCKET"
    root["upper_floor_z_m"] = 0.0
    root["lower_floor_z_m"] = -FLOOR_HEIGHT
    select_tree(root)
    bpy.ops.export_scene.gltf(
        filepath=str(output), export_format="GLB", use_selection=True,
        export_apply=True, export_yup=True, export_extras=True,
        export_materials="EXPORT", export_image_format="NONE",
        export_cameras=False, export_lights=False, export_animations=False,
    )
    root.matrix_world = original


wall = bpy.data.objects.get("MOD_WALL_SOLID_5M_U01")
if wall is None:
    raise RuntimeError("Missing MOD_WALL_SOLID_5M_U01")
wall.data = wall.data.copy()
for vertex in wall.data.vertices:
    if vertex.co.z > 4.0:
        vertex.co.z += 3.0
wall.data.update()
wall["dimensions_m"] = [5.0, 0.3, VISUAL_HEIGHT]
wall["logical_height_m"] = FLOOR_HEIGHT
wall["visual_height_m"] = VISUAL_HEIGHT
wall["visual_top_clearance_m"] = 0.1

for root_name in STAIR_ROOTS:
    update_stair(bpy.data.objects[root_name])

scene = bpy.context.scene
scene["asset_version"] = "v011"
scene["tower_floor_height_m"] = FLOOR_HEIGHT
scene["tower_wall_visual_height_m"] = VISUAL_HEIGHT
scene["derived_from"] = str(SOURCE_DIR / "env_tower_descent_kit_top3d_v010.blend")
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))

bpy.ops.object.select_all(action="DESELECT")
wall_export = wall.copy()
wall_export.data = wall.data.copy()
wall_export.name = "ENV_TOWER_WALL_SOLID_5M_V003"
wall_export.parent = None
wall_export.matrix_world = Matrix.Identity(4)
wall_export.hide_viewport = False
wall_export.hide_render = False
bpy.context.scene.collection.objects.link(wall_export)
wall_export.select_set(True)
bpy.context.view_layer.objects.active = wall_export
bpy.ops.export_scene.gltf(
    filepath=str(COMPONENT_DIR / "env_tower_wall_solid_5m_top3d_v003.glb"),
    export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
    export_extras=True, export_materials="EXPORT", export_image_format="NONE",
    export_cameras=False, export_lights=False, export_animations=False,
)
bpy.data.objects.remove(wall_export, do_unlink=True)

export_tree(
    bpy.data.objects[STAIR_ROOTS[0]],
    COMPONENT_DIR / "env_tower_stairwell_generic_12m_top3d_v001.glb",
    "ENV-TOWER-STAIRWELL-GENERIC-12M",
)
export_tree(
    bpy.data.objects[STAIR_ROOTS[1]],
    COMPONENT_DIR / "env_tower_stairwell_rooftop_12m_top3d_v001.glb",
    "ENV-TOWER-STAIRWELL-ROOFTOP-12M",
)
print(f"TOWER_HEIGHT12_ASSETS_OK blend={OUTPUT_BLEND}")
