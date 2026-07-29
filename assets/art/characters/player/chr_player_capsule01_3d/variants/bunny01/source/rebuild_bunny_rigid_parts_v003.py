import bpy
import bmesh
from math import radians
from mathutils import Matrix, Vector
from pathlib import Path


PROJECT_ROOT = Path("/Users/summercards/ShellStorm2")
ASSET_ROOT = PROJECT_ROOT / "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01"
COMPONENT_ROOT = ASSET_ROOT / "components"
RUNTIME_ROOT = ASSET_ROOT / "runtime"
SOURCE_PATH = ASSET_ROOT / "source/chr_player_capsule01_bunny01_top3d_v003.blend"

for directory in (COMPONENT_ROOT, RUNTIME_ROOT, SOURCE_PATH.parent):
    directory.mkdir(parents=True, exist_ok=True)

TARGET_HEIGHT = 2.475
RAW_HEIGHT = 2.592014 - 0.138049
UNIFORM_SCALE = TARGET_HEIGHT / RAW_HEIGHT
TURN_TO_GODOT_FORWARD = Matrix.Rotation(radians(-90.0), 4, "Z")
UNIFORM_MATRIX = Matrix.Diagonal((UNIFORM_SCALE, UNIFORM_SCALE, UNIFORM_SCALE, 1.0))
GROUND_OFFSET = Matrix.Translation(Vector((0.0, 0.0, -0.138049 * UNIFORM_SCALE)))
AUTHORING_MATRIX = GROUND_OFFSET @ TURN_TO_GODOT_FORWARD @ UNIFORM_MATRIX

SOURCE_NAMES = {
    "ear": "tripo_node_694681c1",
    "body": "tripo_node_0fa28bd3",
    "head": "tripo_node_0a574e5f",
    "foot": "tripo_node_9dafe42b",
    "hand_primary": "球体.002",
    "hand_secondary": "球体.003",
}


def evaluated_copy(source, name, include_modifiers=True):
    if include_modifiers:
        depsgraph = bpy.context.evaluated_depsgraph_get()
        evaluated = source.evaluated_get(depsgraph)
        mesh = bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)
    else:
        mesh = source.data.copy()
    result = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(result)
    result.matrix_world = source.matrix_world.copy()
    return result


def split_evaluated_world_y(source, negative_name, positive_name):
    evaluated = evaluated_copy(source, "__evaluated_%s" % source.name, True)
    result = []
    for keep_negative, name in ((True, negative_name), (False, positive_name)):
        mesh = evaluated.data.copy()
        part = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(part)
        part.matrix_world = evaluated.matrix_world.copy()
        bm = bmesh.new()
        bm.from_mesh(mesh)
        remove_faces = []
        for face in bm.faces:
            world_center = part.matrix_world @ face.calc_center_median()
            if (world_center.y < 0.0) != keep_negative:
                remove_faces.append(face)
        bmesh.ops.delete(bm, geom=remove_faces, context="FACES")
        loose_vertices = [vertex for vertex in bm.verts if not vertex.link_faces]
        if loose_vertices:
            bmesh.ops.delete(bm, geom=loose_vertices, context="VERTS")
        bm.to_mesh(mesh)
        bm.free()
        result.append(part)
    bpy.data.objects.remove(evaluated, do_unlink=True)
    return result


def world_points(objects):
    return [obj.matrix_world @ vertex.co for obj in objects for vertex in obj.data.vertices]


def bounds(objects):
    points = world_points(objects)
    low = Vector((min(point.x for point in points), min(point.y for point in points), min(point.z for point in points)))
    high = Vector((max(point.x for point in points), max(point.y for point in points), max(point.z for point in points)))
    return low, high


def bottom_center_pivot(objects):
    low, high = bounds(objects)
    return Vector(((low.x + high.x) * 0.5, (low.y + high.y) * 0.5, low.z))


def percentile_pivot(objects, mode):
    points = world_points(objects)
    sample_count = max(8, int(len(points) * 0.08))
    if mode == "bottom":
        selected = sorted(points, key=lambda point: point.z)[:sample_count]
    elif mode == "inner":
        selected = sorted(points, key=lambda point: abs(point.x))[:sample_count]
    else:
        raise ValueError(mode)
    return sum(selected, Vector()) / float(len(selected))


def bake_objects_to_pivot(objects, pivot):
    for obj in objects:
        obj.data.transform(Matrix.Translation(-pivot) @ obj.matrix_world)
        obj.matrix_world = Matrix.Translation(pivot)


def clear_selection():
    bpy.ops.object.select_all(action="DESELECT")


def export_selection(path, objects):
    clear_selection()
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_materials="EXPORT",
    )


def export_local_component(path, source_objects):
    temporary = []
    for index, source in enumerate(source_objects):
        obj = bpy.data.objects.new("EXPORT_%s_%02d" % (path.stem, index), source.data.copy())
        bpy.context.scene.collection.objects.link(obj)
        obj.matrix_world = Matrix.Identity(4)
        temporary.append(obj)
    export_selection(path, temporary)
    for obj in temporary:
        bpy.data.objects.remove(obj, do_unlink=True)


raw = {key: bpy.data.objects[name] for key, name in SOURCE_NAMES.items()}

body = evaluated_copy(raw["body"], "SRC_Body", True)
head = evaluated_copy(raw["head"], "SRC_Head", True)
ear = evaluated_copy(raw["ear"], "SRC_Ear_L", False)
foot_negative, foot_positive = split_evaluated_world_y(raw["foot"], "SRC_Foot_L", "SRC_Foot_R")
hand_primary_negative, hand_primary_positive = split_evaluated_world_y(
    raw["hand_primary"], "SRC_Hand_L_Main", "SRC_Hand_R_Main"
)
hand_secondary_negative, hand_secondary_positive = split_evaluated_world_y(
    raw["hand_secondary"], "SRC_Hand_L_Cuff", "SRC_Hand_R_Cuff"
)

logical_parts = {
    "body": [body],
    "head": [head],
    "ear": [ear],
    "hand_l": [hand_primary_negative, hand_secondary_negative],
    "hand_r": [hand_primary_positive, hand_secondary_positive],
    "foot_l": [foot_negative],
    "foot_r": [foot_positive],
}

for objects in logical_parts.values():
    for obj in objects:
        obj.matrix_world = AUTHORING_MATRIX @ obj.matrix_world

pivots = {
    "body": bottom_center_pivot(logical_parts["body"]),
    "head": bottom_center_pivot(logical_parts["head"]),
    "ear_l": percentile_pivot(logical_parts["ear"], "bottom"),
    "hand_l": percentile_pivot(logical_parts["hand_l"], "inner"),
    "hand_r": percentile_pivot(logical_parts["hand_r"], "inner"),
    "foot_l": bottom_center_pivot(logical_parts["foot_l"]),
    "foot_r": bottom_center_pivot(logical_parts["foot_r"]),
}
pivots["ear_r"] = Vector((-pivots["ear_l"].x, pivots["ear_l"].y, pivots["ear_l"].z))

for key, objects in logical_parts.items():
    pivot_key = "ear_l" if key == "ear" else key
    bake_objects_to_pivot(objects, pivots[pivot_key])

ear_r_preview = bpy.data.objects.new("SRC_Ear_R_Mirror", ear.data.copy())
bpy.context.scene.collection.objects.link(ear_r_preview)
ear_r_preview.matrix_world = Matrix.Translation(pivots["ear_r"]) @ Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0))

authoring_objects = [obj for objects in logical_parts.values() for obj in objects] + [ear_r_preview]
keep_objects = set(authoring_objects)
for obj in list(bpy.data.objects):
    if obj not in keep_objects:
        bpy.data.objects.remove(obj, do_unlink=True)

rig_reference = bpy.data.objects.new("BunnyAuthoringRoot", None)
bpy.context.scene.collection.objects.link(rig_reference)
rig_reference.empty_display_type = "PLAIN_AXES"
rig_reference.empty_display_size = 0.18
for obj in keep_objects:
    obj.parent = rig_reference
    obj.matrix_parent_inverse = Matrix.Identity(4)

for pivot_name, pivot in pivots.items():
    guide = bpy.data.objects.new("PIVOT_%s" % pivot_name.upper(), None)
    bpy.context.scene.collection.objects.link(guide)
    guide.location = pivot
    guide.empty_display_type = "SPHERE"
    guide.empty_display_size = 0.045
    guide.show_in_front = True
    guide.parent = rig_reference

component_files = {
    "body": COMPONENT_ROOT / "chr_player_capsule01_bunny01_body_top3d_v003.glb",
    "head": COMPONENT_ROOT / "chr_player_capsule01_bunny01_head_top3d_v003.glb",
    "ear": COMPONENT_ROOT / "chr_player_capsule01_bunny01_ear_top3d_v003.glb",
    "hand_l": COMPONENT_ROOT / "chr_player_capsule01_bunny01_hand_l_top3d_v003.glb",
    "hand_r": COMPONENT_ROOT / "chr_player_capsule01_bunny01_hand_r_top3d_v003.glb",
    "foot_l": COMPONENT_ROOT / "chr_player_capsule01_bunny01_foot_l_top3d_v003.glb",
    "foot_r": COMPONENT_ROOT / "chr_player_capsule01_bunny01_foot_r_top3d_v003.glb",
}
for key, path in component_files.items():
    export_local_component(path, logical_parts[key])

export_selection(RUNTIME_ROOT / "chr_player_capsule01_bunny01_top3d_v003.glb", authoring_objects)

bpy.context.scene["godot_forward"] = "-Z"
bpy.context.scene["uniform_scale_from_raw"] = UNIFORM_SCALE
bpy.context.scene["target_height_m"] = TARGET_HEIGHT
for key, pivot in pivots.items():
    bpy.context.scene["pivot_%s_blender" % key] = tuple(pivot)
    bpy.context.scene["pivot_%s_godot" % key] = (pivot.x, pivot.z, -pivot.y)

bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_PATH))

all_objects = authoring_objects
all_low, all_high = bounds(all_objects)
print("BUNNY_V003_BUILD_COMPLETE")
print("UNIFORM_SCALE", round(UNIFORM_SCALE, 9))
print("AUTHORING_BOUNDS", tuple(round(v, 6) for v in all_low), tuple(round(v, 6) for v in all_high))
for key, pivot in pivots.items():
    godot = Vector((pivot.x, pivot.z, -pivot.y))
    print("PIVOT", key, "BLENDER", tuple(round(v, 6) for v in pivot), "GODOT", tuple(round(v, 6) for v in godot))
for key, objects in logical_parts.items():
    print("PART", key, [(obj.name, len(obj.data.vertices), len(obj.data.polygons)) for obj in objects])
