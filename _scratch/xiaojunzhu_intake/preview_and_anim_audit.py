"""小菌猪 Blender 侧核对：动画数据审计 + 多视图预览渲染 + 尺寸参照。

**只读**：渲染产物写到 _scratch，不保存 blend。

运行：
  blender.exe --background --factory-startup "<blend>" --python preview_and_anim_audit.py
"""

import math
from pathlib import Path

import bpy
from mathutils import Vector

OUT_DIR = Path(r"I:\工作项目\shellstrom2\ShellStorm2\_scratch\xiaojunzhu_intake\previews")
OUT_DIR.mkdir(parents=True, exist_ok=True)

DISPLAY_MULTIPLIER = 0.70   # Enemy3D.DEFAULT_BASE_SIZE_MULTIPLIER
PLAYER_DISPLAY_H = 1.20     # verify_player3d_avatar_bounds: EXPECTED_STATIC_HEIGHT_M

print("=" * 72)
print("PREVIEW + ANIM AUDIT")
print("=" * 72)
print("blend = %r" % bpy.data.filepath)

# ============================ 1) 动画数据审计 ============================
print("\n[ACTIONS] total=%d" % len(bpy.data.actions))
if not bpy.data.actions:
    print("  <无 Action —— 该 blend 不含任何动画数据>")
for act in bpy.data.actions:
    fr = act.frame_range
    fcurves = len(act.fcurves) if hasattr(act, "fcurves") else -1
    layers = len(act.layers) if hasattr(act, "layers") else -1
    print("  %-40r frames=%6.1f..%-6.1f users=%d fcurves=%d layers=%d"
          % (act.name, fr[0], fr[1], act.users, fcurves, layers))

print("\n[animation_data per object]")
any_anim = False
for obj in bpy.data.objects:
    ad = obj.animation_data
    if ad is None:
        continue
    any_anim = True
    tracks = [t.name for t in ad.nla_tracks] if ad.nla_tracks else []
    print("  %-34s action=%r nla=%s" % (
        obj.name, ad.action.name if ad.action else None, tracks))
if not any_anim:
    print("  <无任何 animation_data>")

arm_objs = [o for o in bpy.data.objects if o.type == "ARMATURE"]
if arm_objs:
    arm = arm_objs[0]
    pose_bones = arm.pose.bones
    non_identity = []
    for pb in pose_bones:
        loc = pb.location
        quat = pb.rotation_quaternion
        scl = pb.scale
        if (loc.length > 1e-6
                or abs(quat.w - 1.0) > 1e-6
                or (Vector(scl) - Vector((1, 1, 1))).length > 1e-6):
            non_identity.append(pb.name)
    print("\n[POSE] bones=%d  非静置骨=%d %s"
          % (len(pose_bones), len(non_identity), non_identity[:8]))

# ============================ 2) 场景准备 ============================
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 64
scene.cycles.use_denoising = True
scene.render.resolution_x = 720
scene.render.resolution_y = 960
scene.render.resolution_percentage = 100
scene.render.film_transparent = False

world = bpy.data.worlds.new("PreviewWorld")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs[0].default_value = (0.82, 0.84, 0.87, 1.0)
bg.inputs[1].default_value = 1.1


def make_mat(name, color, rough=0.6, metal=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return mat


# 地面
bpy.ops.mesh.primitive_plane_add(size=14.0, location=(0, 0, 0))
ground = bpy.context.active_object
ground.name = "ZZ_PreviewGround"
ground.data.materials.append(make_mat("ZZ_GroundMat", (0.62, 0.64, 0.66, 1.0), 0.85))

# 玩家高度参照柱（蓝）= 游戏内 1.20 m
bar_h = PLAYER_DISPLAY_H
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(-0.78, 0, bar_h * 0.5))
bar = bpy.context.active_object
bar.name = "ZZ_PlayerHeightRef"
bar.scale = (0.07, 0.07, bar_h)
bar.data.materials.append(make_mat("ZZ_RefMat", (0.09, 0.34, 0.86, 1.0), 0.4))

# 灯光
def add_area(name, loc, energy, size, target=Vector((0, 0, 0.7))):
    data = bpy.data.lights.new(name, type="AREA")
    data.energy = energy
    data.size = size
    obj = bpy.data.objects.new(name, data)
    obj.location = loc
    d = target - Vector(loc)
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(obj)
    return obj


add_area("ZZ_Key", (-2.6, -3.2, 3.4), 900, 3.0)
add_area("ZZ_Fill", (3.2, -1.8, 1.6), 320, 3.0)
add_area("ZZ_Rim", (0.6, 3.6, 2.6), 420, 2.5)

sun = bpy.data.lights.new("ZZ_Sun", type="SUN")
sun.energy = 1.6
sun_obj = bpy.data.objects.new("ZZ_Sun", sun)
sun_obj.rotation_euler = (math.radians(52), 0, math.radians(35))
scene.collection.objects.link(sun_obj)

# ============================ 3) 显示倍率（只用于渲染） ============================
arm = arm_objs[0]
mesh_objs = [o for o in bpy.data.objects if o.type == "MESH"
             and not o.name.startswith("ZZ_")]
arm.scale = (DISPLAY_MULTIPLIER,) * 3
print("\n[RENDER SCALE] armature.scale = %s (Enemy3D 展示倍率)"
      % (tuple(arm.scale),))

bpy.context.view_layer.update()


def world_bounds():
    lo = Vector((1e18,) * 3)
    hi = Vector((-1e18,) * 3)
    for obj in mesh_objs:
        for corner in obj.bound_box:
            w = obj.matrix_world @ Vector(corner)
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    return lo, hi


lo, hi = world_bounds()
size = hi - lo
print("[RENDER AABB] 游戏内显示尺寸 = (%.4f, %.4f, %.4f) m" % (size.x, size.y, size.z))
print("              高 %.4f m  vs  玩家参照柱 %.4f m  (+%.1f%%)"
      % (size.z, bar_h, (size.z / bar_h - 1.0) * 100.0))

# ============================ 4) 相机与渲染 ============================
cam_data = bpy.data.cameras.new("ZZ_Cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = 2.35
cam_obj = bpy.data.objects.new("ZZ_Cam", cam_data)
scene.collection.objects.link(cam_obj)
scene.camera = cam_obj

target = Vector((0, 0, size.z * 0.5))

VIEWS = {
    "01_front_from_minusY": Vector((0, -9, size.z * 0.5)),
    "02_back_from_plusY": Vector((0, 9, size.z * 0.5)),
    "03_side_from_plusX": Vector((9, 0, size.z * 0.5)),
    "04_side_from_minusX": Vector((-9, 0, size.z * 0.5)),
    "05_top_from_plusZ": Vector((0, 0.001, 9)),
    "06_three_quarter": Vector((-5.4, -6.0, 3.4)),
}

for name, loc in VIEWS.items():
    cam_obj.location = loc
    cam_obj.rotation_euler = (target - loc).to_track_quat("-Z", "Y").to_euler()
    if name.startswith("05_"):
        cam_data.ortho_scale = 2.35
    scene.render.filepath = str(OUT_DIR / ("%s.png" % name))
    bpy.ops.render.render(write_still=True)
    print("  rendered %s" % scene.render.filepath)

# 恢复（不保存，纯保险）
arm.scale = (1.0, 1.0, 1.0)
print("\nPREVIEW_RENDER_DONE dir=%s" % OUT_DIR)
print("=" * 72)
