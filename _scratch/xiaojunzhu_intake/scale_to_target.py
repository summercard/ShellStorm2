"""把小菌猪源模型归一到目标「游戏内显示高度」。

口径（全部来自代码常量，不是拍的）：
  Enemy3D.DEFAULT_BASE_SIZE_MULTIPLIER = 0.70          (src/enemy3d/Enemy3D.gd:26)
  BODY_SCALE_BY_KIND["melee_chaser"]   = 1.0           (src/enemy3d/Enemy3D.gd:39)
  普通怪 _variant_scale_multiplier      = 1.0
  ⇒ 游戏内显示高度 = 源文件高度 × 0.70

玩家对照：DEFAULT_BASE_SIZE_MULTIPLIER = 0.80，源 1.5m → 游戏内 1.20m
（tests/verification/verify_player3d_avatar_bounds.gd: EXPECTED_STATIC_HEIGHT_M = 1.20）

做法：等比缩放**网格顶点**与**骨架编辑骨**（都绕世界原点），
不写对象级 scale —— 导出后源文件就是真实尺寸，无隐藏缩放。
"""

import bpy
from mathutils import Vector

TARGET_DISPLAY_M = 1.30
DISPLAY_MULTIPLIER = 0.70
TARGET_AUTHORED_M = TARGET_DISPLAY_M / DISPLAY_MULTIPLIER
TOLERANCE_M = 1e-4

print("=" * 72)
print("SCALE: xiaojunzhu -> display %.3f m" % TARGET_DISPLAY_M)
print("=" * 72)
print("blend = %r" % bpy.data.filepath)
print("target authored height = %.3f / %.2f = %.6f m" % (
    TARGET_DISPLAY_M, DISPLAY_MULTIPLIER, TARGET_AUTHORED_M))


def world_bounds() -> tuple:
    lo = Vector((1e18, 1e18, 1e18))
    hi = Vector((-1e18, -1e18, -1e18))
    n = 0
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            w = obj.matrix_world @ Vector(corner)
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
        n += 1
    return lo, hi, n


before_lo, before_hi, mesh_n = world_bounds()
before_size = before_hi - before_lo
before_h = before_size.z
print("\n[BEFORE] meshes=%d  height=%.6f m  size=(%.4f, %.4f, %.4f)"
      % (mesh_n, before_h, before_size.x, before_size.y, before_size.z))

if mesh_n != 1:
    raise SystemExit("SCALE_ABORTED: 期望 1 个 mesh，实际 %d" % mesh_n)

factor = TARGET_AUTHORED_M / before_h
print("factor = %.6f / %.6f = %.8f" % (TARGET_AUTHORED_M, before_h, factor))

# ---- 1) 网格顶点等比缩放（绕原点） ----------------------------------------
mesh_objs = [o for o in bpy.data.objects if o.type == "MESH"]
verts_scaled = 0
for obj in mesh_objs:
    for v in obj.data.vertices:
        v.co *= factor
        verts_scaled += 1
    obj.data.update()
print("\n[SCALE] mesh verts scaled = %d" % verts_scaled)

# ---- 2) 骨架编辑骨等比缩放（绕原点，保持绑定一致） ------------------------
arm_objs = [o for o in bpy.data.objects if o.type == "ARMATURE"]
if len(arm_objs) != 1:
    raise SystemExit("SCALE_ABORTED: 期望 1 个 armature，实际 %d" % len(arm_objs))
arm = arm_objs[0]
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
bones_scaled = 0
for bone in arm.data.edit_bones:
    bone.head *= factor
    bone.tail *= factor
    bones_scaled += 1
bpy.ops.object.mode_set(mode="OBJECT")
print("[SCALE] armature bones scaled = %d" % bones_scaled)

# 对象级变换必须仍是单位阵（无隐藏缩放）
for obj in bpy.data.objects:
    if obj.type in ("MESH", "ARMATURE"):
        print("  object %-34s loc=%s scale=%s" % (
            obj.name,
            tuple(round(c, 6) for c in obj.location),
            tuple(round(c, 6) for c in obj.scale)))
        if any(abs(c - 1.0) > 1e-9 for c in obj.scale):
            raise SystemExit("SCALE_ABORTED: %s 出现对象级缩放" % obj.name)

# ---- 3) 复核 --------------------------------------------------------------
after_lo, after_hi, _ = world_bounds()
after_size = after_hi - after_lo
after_h = after_size.z
print("\n[AFTER ] height=%.6f m  size=(%.4f, %.4f, %.4f)"
      % (after_h, after_size.x, after_size.y, after_size.z))
print("  ground (min Z) = %.6f m   (应 ≈ 0)" % after_lo.z)
print("  in-game display height = %.6f × %.2f = %.4f m"
      % (after_h, DISPLAY_MULTIPLIER, after_h * DISPLAY_MULTIPLIER))

failures = []
if abs(after_h - TARGET_AUTHORED_M) > TOLERANCE_M:
    failures.append("缩放后高度 %.6f != 目标 %.6f" % (after_h, TARGET_AUTHORED_M))
if abs(after_lo.z) > TOLERANCE_M:
    failures.append("脚底不再贴地：min Z = %.6f" % after_lo.z)
if len(mesh_objs[0].data.vertices) != verts_scaled:
    failures.append("顶点数变化")

if failures:
    print("\nSELF-CHECK FAILED:")
    for f in failures:
        print("  - " + f)
    raise SystemExit("SCALE_ABORTED")

bpy.context.preferences.filepaths.save_version = 0  # 不生成 .blend1
print("\nSAVING -> %r" % bpy.data.filepath)
bpy.ops.wm.save_mainfile()
print("SCALE_OK")
print("=" * 72)
