"""Build the formal 1.5 m ShellStorm2 player/avatar authoring template."""

import bpy
import json
from pathlib import Path
from mathutils import Vector


PROJECT_ROOT = Path("/Users/summercards/ShellStorm2")
ASSET_ROOT = PROJECT_ROOT / "assets/art/characters/player/chr_player_avatar_template_3d"
OUTPUT_BLEND = ASSET_ROOT / "source/chr_player_avatar_template_source_v001.blend"
OUTPUT_PREVIEW = ASSET_ROOT / "previews/chr_player_avatar_template_overview_v001.png"
OUTPUT_MANIFEST = ASSET_ROOT / "chr_player_avatar_template_manifest_v001.json"


def link_only(obj, collection):
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    collection.objects.link(obj)


def material(name, color, metallic=0.0, roughness=0.55, emission=None):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = next(node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 2.0
    return mat


def add_uv_sphere(name, location, dimensions, collection, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    link_only(obj, collection)
    return obj


def add_box(name, location, dimensions, collection, mat, bevel=0.02, display="TEXTURED"):
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        modifier = obj.modifiers.new("规范倒角", "BEVEL")
        modifier.width = bevel
        modifier.segments = 3
    obj.data.materials.append(mat)
    obj.display_type = display
    link_only(obj, collection)
    return obj


def add_empty(name, location, collection, slot_id, radius=0.075):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "ARROWS"
    obj.empty_display_size = radius
    obj.location = location
    obj["attachment_slot"] = slot_id
    obj["coordinate_mapping"] = "Blender(x,y,z) -> Godot(x,z,-y)"
    collection.objects.link(obj)
    return obj


def add_text(name, body, location, size, collection, color, rotation=(1.5708, 0.0, 0.0)):
    curve = bpy.data.curves.new(name + "_Curve", "FONT")
    curve.body = body
    curve.align_x = "CENTER"
    curve.size = size
    curve.extrude = 0.002
    obj = bpy.data.objects.new(name, curve)
    obj.location = location
    obj.rotation_euler = rotation
    curve.materials.append(color)
    collection.objects.link(obj)
    return obj


def collection(parent, name):
    value = bpy.data.collections.new(name)
    parent.children.link(value)
    return value


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for value in list(bpy.data.collections):
    if value.name != "Collection":
        bpy.data.collections.remove(value)
root_default = bpy.data.collections.get("Collection")
root_default.name = "角色资产规范母版_中文管理"

reference_col = collection(root_default, "01_尺寸方向参照_只读")
editable_col = collection(root_default, "02_制作组件_可编辑")
socket_col = collection(root_default, "03_挂点与导出根")
showcase_col = collection(root_default, "90_展示环境")

slot_collections = {}
for index, label in enumerate([
    "01_身体_Body", "02_头部_Head", "03_手部_Hands", "04_脚部_Feet",
    "05_帽子_Hat", "06_眼镜_Glasses", "07_下身附件_LowerBody",
]):
    slot_collections[label.split("_", 2)[2]] = collection(editable_col, label)

root = bpy.data.objects.new("CHR_PlayerAvatar_Template_Source_v001", None)
root.empty_display_type = "PLAIN_AXES"
root.empty_display_size = 0.22
root["asset_id"] = "CHR-PLAYER-AVATAR-TEMPLATE-001"
root["unit"] = "meter"
root["character_height_m"] = 1.5
root["blender_forward"] = "-Y"
root["godot_forward"] = "-Z"
root["origin_contract"] = "ground_center_z0"
root["runtime_root_scale"] = 1.0
root["collision_contract"] = "presentation_only; gameplay capsule remains in Player3D prefab"
root["slot_contract"] = "body,head,hand,feet,hat,glasses,lower_body"
socket_col.objects.link(root)

mat_body = material("MAT_参照体_钴蓝", (0.10, 0.34, 0.56), 0.25, 0.38)
mat_head = material("MAT_参照头_青蓝", (0.12, 0.56, 0.68), 0.18, 0.34)
mat_slot = material("MAT_组件框_橙", (0.95, 0.32, 0.06), 0.10, 0.32, (0.50, 0.08, 0.01))
mat_guide = material("MAT_规范线_青", (0.12, 0.82, 1.0), 0.18, 0.26, (0.03, 0.34, 0.58))
mat_floor = material("MAT_展示地面", (0.018, 0.032, 0.045), 0.55, 0.34)
mat_text = material("MAT_说明文字", (0.68, 0.94, 1.0), 0.0, 0.45, (0.18, 0.62, 0.82))

body = add_uv_sphere("REF_身体包络_只读", (0.0, 0.0, 0.56), (0.72, 0.52, 0.90), reference_col, mat_body)
head = add_uv_sphere("REF_头部包络_只读", (0.0, -0.02, 1.05), (0.75, 0.62, 0.58), reference_col, mat_head)
ear_l = add_uv_sphere("REF_耳部左_只读", (-0.20, -0.005, 1.33), (0.18, 0.20, 0.34), reference_col, mat_head)
ear_r = add_uv_sphere("REF_耳部右_只读", (0.20, -0.005, 1.33), (0.18, 0.20, 0.34), reference_col, mat_head)
for obj in [body, head, ear_l, ear_r]:
    obj["reference_only"] = True
    obj["do_not_export"] = True

# 可编辑组件只放边界框和导出根，作者把正式网格放入同名集合并保持根缩放1。
slot_boxes = [
    ("Body", (0, 0, 0.58), (0.78, 0.60, 0.95)),
    ("Head", (0, -0.03, 1.08), (0.82, 0.68, 0.66)),
    ("Hands", (0, -0.22, 0.72), (0.98, 0.30, 0.30)),
    ("Feet", (0, -0.08, 0.14), (0.58, 0.50, 0.28)),
    ("Hat", (0, -0.02, 1.38), (0.70, 0.56, 0.22)),
    ("Glasses", (0, -0.34, 1.10), (0.64, 0.12, 0.22)),
    ("LowerBody", (0, 0.0, 0.38), (0.86, 0.68, 0.30)),
]
for slot_id, location, dimensions in slot_boxes:
    target = slot_collections[slot_id]
    guide = add_box("GUIDE_%s_边界" % slot_id, location, dimensions, target, mat_slot, 0.01, "WIRE")
    guide.display_type = "WIRE"
    guide.hide_render = True
    guide["reference_only"] = True
    export_root = add_empty("EXPORT_%s_ROOT" % slot_id.upper(), (0, 0, 0), target, slot_id.lower(), 0.06)
    export_root.parent = root
    export_root["required_scale"] = [1.0, 1.0, 1.0]

sockets = {
    "SOCKET_Weapon": ((0.0, -0.21818, 0.39394), "weapon"),
    "SOCKET_StowedWeaponPrimary": ((-0.36, -0.54, 0.82), "stowed_weapon_primary"),
    "SOCKET_StowedWeaponSecondary": ((0.36, -0.54, 0.82), "stowed_weapon_secondary"),
    "SOCKET_Backpack": ((0.0, -0.30, 0.74), "backpack"),
    "SOCKET_LowerBody": ((0.0, 0.0, 0.30), "lower_body"),
    "SOCKET_Hat": ((0.0, -0.01, 1.36), "hat"),
    "SOCKET_Glasses": ((0.0, -0.35, 1.10), "glasses"),
    "SOCKET_EarL": ((-0.20, -0.01, 1.30), "ear_l"),
    "SOCKET_EarR": ((0.20, -0.01, 1.30), "ear_r"),
}
for name, (location, slot_id) in sockets.items():
    socket = add_empty(name, location, socket_col, slot_id)
    socket.parent = root

# 高度尺、原点、前向箭头。
add_box("GUIDE_1点5米高度尺", (-0.62, 0.0, 0.75), (0.015, 0.015, 1.5), reference_col, mat_guide, 0.0)
for index in range(7):
    z = index * 0.25
    add_box("GUIDE_高度刻度_%02d" % index, (-0.58, 0.0, z), (0.10, 0.015, 0.012), reference_col, mat_guide, 0.0)
bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=0.09, radius2=0.0, depth=0.32, location=(0.0, -0.82, 0.02), rotation=(1.5708, 0, 0))
forward = bpy.context.object
forward.name = "GUIDE_前向_Blender负Y_Godot负Z"
forward.data.materials.append(mat_guide)
link_only(forward, reference_col)
add_text("LABEL_高度", "1.50 m", (-0.62, 0.02, 1.60), 0.11, reference_col, mat_text, (1.5708, 0, 0))
add_text("LABEL_前向", "FRONT  -Y  /  Godot -Z", (0.0, -1.04, 0.02), 0.08, reference_col, mat_text, (0, 0, 0))

add_box("展示地台", (0.0, 0.0, -0.035), (3.4, 3.4, 0.07), showcase_col, mat_floor, 0.04)
for x in [-1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5]:
    add_box("GRID_X_%s" % str(x), (x, 0, 0.002), (0.006, 3.0, 0.006), showcase_col, mat_guide, 0.0)
for y in [-1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5]:
    add_box("GRID_Y_%s" % str(y), (0, y, 0.002), (3.0, 0.006, 0.006), showcase_col, mat_guide, 0.0)

camera_data = bpy.data.cameras.new("规范预览相机")
camera = bpy.data.objects.new("规范预览相机", camera_data)
camera.location = (3.1, -4.2, 2.55)
camera_data.lens = 58
showcase_col.objects.link(camera)
bpy.context.scene.camera = camera

target = Vector((0.0, 0.0, 0.78))
camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
for name, location, energy, size, color in [
    ("主灯", (2.4, -2.8, 4.2), 1050.0, 3.0, (0.72, 0.90, 1.0)),
    ("轮廓灯", (-2.6, 1.8, 3.2), 850.0, 2.4, (0.28, 0.62, 1.0)),
    ("暖补灯", (2.1, 2.4, 2.0), 620.0, 2.0, (1.0, 0.42, 0.16)),
]:
    light_data = bpy.data.lights.new(name, "AREA")
    light_data.energy = energy
    light_data.shape = "DISK"
    light_data.size = size
    light_data.color = color
    light = bpy.data.objects.new(name, light_data)
    light.location = location
    light.rotation_euler = (target - light.location).to_track_quat("-Z", "Y").to_euler()
    showcase_col.objects.link(light)

scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 1024
scene.render.resolution_y = 1024
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.world.color = (0.004, 0.008, 0.014)
scene.view_settings.look = "AgX - Medium High Contrast"
scene.view_settings.exposure = 1.0
scene["template_contract"] = "1.5m; ground origin; Blender -Y; Godot -Z; scale1"
scene["project_skill"] = "skills_drafts/player-avatar-asset-standard"

OUTPUT_BLEND.parent.mkdir(parents=True, exist_ok=True)
OUTPUT_PREVIEW.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND), compress=True)
scene.render.filepath = str(OUTPUT_PREVIEW)
bpy.ops.render.render(write_still=True)

manifest = {
    "asset_id": root["asset_id"],
    "version": "v001",
    "blend": str(OUTPUT_BLEND),
    "preview": str(OUTPUT_PREVIEW),
    "unit": "meter",
    "height_m": 1.5,
    "origin": "ground_center_z0",
    "forward": {"blender": "-Y", "godot": "-Z"},
    "runtime_root_scale": 1.0,
    "slots": ["body", "head", "hand", "feet", "hat", "glasses", "lower_body"],
    "sockets": {name: list(value[0]) for name, value in sockets.items()},
    "gameplay_collision_owner": "res://scenes/Player3D.tscn",
    "source_reference": "chr_player_capsule01_bunny01_top3d_v006.blend audited at exact 1.5m",
}
OUTPUT_MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
print("PLAYER_AVATAR_TEMPLATE_WRITTEN=" + str(OUTPUT_BLEND))
print("PLAYER_AVATAR_TEMPLATE_PREVIEW=" + str(OUTPUT_PREVIEW))
print("PLAYER_AVATAR_TEMPLATE_MANIFEST=" + str(OUTPUT_MANIFEST))
