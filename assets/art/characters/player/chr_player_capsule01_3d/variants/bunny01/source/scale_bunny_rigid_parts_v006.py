import bpy
from mathutils import Matrix, Vector
from pathlib import Path


PROJECT_ROOT = Path("/Users/summercards/ShellStorm2")
ASSET_ROOT = PROJECT_ROOT / "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01"
COMPONENT_ROOT = ASSET_ROOT / "components"
RUNTIME_ROOT = ASSET_ROOT / "runtime"
SOURCE_PATH = ASSET_ROOT / "source/chr_player_capsule01_bunny01_top3d_v006.blend"

SOURCE_HEIGHT_M = 1.0
TARGET_HEIGHT_M = 1.5
LINEAR_SCALE_FROM_V005 = TARGET_HEIGHT_M / SOURCE_HEIGHT_M
LINEAR_SCALE_FROM_V004 = TARGET_HEIGHT_M / 2.475

COMPONENT_OBJECTS = {
    "body": ["SRC_Body"],
    "head": ["SRC_Head"],
    "ear": ["SRC_Ear_R"],
    "hand_l": ["SRC_Hand_Main_L", "SRC_Hand_Cuff_L"],
    "hand_r": ["SRC_Hand_Main_R", "SRC_Hand_Cuff_R"],
    "foot_l": ["SRC_Foot_L"],
    "foot_r": ["SRC_Foot_R"],
}


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


def world_bounds(objects):
    points = []
    for obj in objects:
        for corner in obj.bound_box:
            points.append(obj.matrix_world @ Vector(corner))
    low = Vector((
        min(point.x for point in points),
        min(point.y for point in points),
        min(point.z for point in points),
    ))
    high = Vector((
        max(point.x for point in points),
        max(point.y for point in points),
        max(point.z for point in points),
    ))
    return low, high


for directory in (COMPONENT_ROOT, RUNTIME_ROOT, SOURCE_PATH.parent):
    directory.mkdir(parents=True, exist_ok=True)

if (
    str(bpy.context.scene.get("assembly_version", "")) != "v005"
    or abs(float(bpy.context.scene.get("target_height_m", 0.0)) - SOURCE_HEIGHT_M) > 0.000001
):
    raise RuntimeError("The active Blender file is not the approved 1.0 m Bunny v005 source")

required_names = {
    "BunnyAuthoringRoot",
    "PIVOT_BODY",
    "PIVOT_EAR_L",
    "PIVOT_EAR_R",
    "PIVOT_FOOT_L",
    "PIVOT_FOOT_R",
    "PIVOT_HAND_L",
    "PIVOT_HAND_R",
    "PIVOT_HEAD",
}
for names in COMPONENT_OBJECTS.values():
    required_names.update(names)
required_names.add("SRC_Ear_L_Mirror")
missing = sorted(required_names.difference(bpy.data.objects.keys()))
if missing:
    raise RuntimeError("Bunny v005 source is missing objects: %s" % ", ".join(missing))

# v005已经是pivot-local的一米正式源。顶点、网格对象位置和刚性关节Empty位置
# 全部等比放大1.5倍，生成真实1.5米几何，不依赖Godot运行时节点缩放。
scaled_meshes = set()
for obj in bpy.data.objects:
    if obj.type == "MESH":
        if obj.data.name not in scaled_meshes:
            obj.data.transform(Matrix.Scale(LINEAR_SCALE_FROM_V005, 4))
            obj.data.update()
            scaled_meshes.add(obj.data.name)
        obj.location *= LINEAR_SCALE_FROM_V005
    elif obj.type == "EMPTY" and obj.name != "BunnyAuthoringRoot":
        obj.location *= LINEAR_SCALE_FROM_V005

bpy.context.view_layer.update()

authoring_objects = [
    obj for obj in bpy.data.objects
    if obj.type == "MESH" and obj.name.startswith("SRC_")
]
all_low, all_high = world_bounds(authoring_objects)
actual_height = all_high.z - all_low.z
if abs(all_low.z) > 0.0005 or abs(actual_height - TARGET_HEIGHT_M) > 0.001:
    raise RuntimeError(
        "Scaled Bunny bounds failed: low_z=%.9f height=%.9f" % (all_low.z, actual_height)
    )

component_files = {
    "body": COMPONENT_ROOT / "chr_player_capsule01_bunny01_body_top3d_v006.glb",
    "head": COMPONENT_ROOT / "chr_player_capsule01_bunny01_head_top3d_v006.glb",
    "ear": COMPONENT_ROOT / "chr_player_capsule01_bunny01_ear_top3d_v006.glb",
    "hand_l": COMPONENT_ROOT / "chr_player_capsule01_bunny01_hand_l_top3d_v006.glb",
    "hand_r": COMPONENT_ROOT / "chr_player_capsule01_bunny01_hand_r_top3d_v006.glb",
    "foot_l": COMPONENT_ROOT / "chr_player_capsule01_bunny01_foot_l_top3d_v006.glb",
    "foot_r": COMPONENT_ROOT / "chr_player_capsule01_bunny01_foot_r_top3d_v006.glb",
}
for key, path in component_files.items():
    export_local_component(path, [bpy.data.objects[name] for name in COMPONENT_OBJECTS[key]])

export_selection(
    RUNTIME_ROOT / "chr_player_capsule01_bunny01_top3d_v006.glb",
    authoring_objects,
)

bpy.context.scene["source_version"] = "v005"
bpy.context.scene["assembly_version"] = "v006"
bpy.context.scene["source_height_m"] = SOURCE_HEIGHT_M
bpy.context.scene["target_height_m"] = TARGET_HEIGHT_M
bpy.context.scene["linear_scale_from_v005"] = LINEAR_SCALE_FROM_V005
bpy.context.scene["linear_scale_from_v004"] = LINEAR_SCALE_FROM_V004
bpy.context.scene["collision_height_m"] = TARGET_HEIGHT_M
bpy.context.scene["visual_height_includes_ears"] = True
bpy.context.scene["godot_runtime_scale_required"] = False
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_PATH))

print("BUNNY_V006_SCALE_COMPLETE")
print("LINEAR_SCALE_FROM_V005", round(LINEAR_SCALE_FROM_V005, 9))
print("LINEAR_SCALE_FROM_V004", round(LINEAR_SCALE_FROM_V004, 9))
print(
    "AUTHORING_BOUNDS",
    tuple(round(value, 6) for value in all_low),
    tuple(round(value, 6) for value in all_high),
)
