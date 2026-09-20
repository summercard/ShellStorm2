"""把小菌猪源模型的朝向从 Blender +X 归正到契约要求的 +Y。

契约（docs/v0.1/16.1_角色美术制作与动作导入流程.md:147）：
  「面罩朝 Blender +Y，Z 向上 … 前向为 Godot -Z，不额外加偏航补偿」

实测：模型朝 +X（从 +X 看是正脸，从 -X 看是后脑勺）
  ⇒ 绕世界 Z 轴转 +90°（Rz(+90°) 把 +X 映射到 +Y）

做法与缩放一致：在**数据层**旋转（网格顶点 + 骨架编辑骨），
不写对象级旋转 —— 不留隐藏补偿。

bone roll 一并处理：先快照所有编辑骨的 matrix，再整体左乘 Rz(+90°)。
（本 blend 无任何 Action，不存在需要重定向的既有动画。）
"""

import math
import bpy
from mathutils import Matrix, Vector

ROT_DEG = 90.0
R = Matrix.Rotation(math.radians(ROT_DEG), 4, "Z")
TOL = 1e-4

print("=" * 72)
print("ORIENTATION: +X -> +Y  (rotate %.1f deg about Z)" % ROT_DEG)
print("=" * 72)
print("blend = %r" % bpy.data.filepath)


def bounds():
    lo = Vector((1e18,) * 3)
    hi = Vector((-1e18,) * 3)
    for obj in bpy.data.objects:
        if obj.type != "MESH" or obj.name.startswith("ZZ_"):
            continue
        for c in obj.bound_box:
            w = obj.matrix_world @ Vector(c)
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    return lo, hi


lo0, hi0 = bounds()
s0 = hi0 - lo0
print("\n[BEFORE] size = (%.4f, %.4f, %.4f)  center=(%.4f, %.4f)"
      % (s0.x, s0.y, s0.z, (lo0.x + hi0.x) / 2, (lo0.y + hi0.y) / 2))

mesh_objs = [o for o in bpy.data.objects
             if o.type == "MESH" and not o.name.startswith("ZZ_")]
arm_objs = [o for o in bpy.data.objects if o.type == "ARMATURE"]
if len(mesh_objs) != 1 or len(arm_objs) != 1:
    raise SystemExit("ORIENT_ABORTED: mesh=%d arm=%d" % (len(mesh_objs), len(arm_objs)))

# ---- 1) 网格顶点绕世界原点旋转 -------------------------------------------
vert_count = 0
for obj in mesh_objs:
    for v in obj.data.vertices:
        v.co = R @ v.co
        vert_count += 1
    obj.data.update()
print("\n[ROTATE] mesh verts = %d" % vert_count)

# ---- 2) 骨架编辑骨：先快照 matrix，再整体左乘 R ----------------------------
arm = arm_objs[0]
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")

snapshot = {eb.name: eb.matrix.copy() for eb in arm.data.edit_bones}
for eb in arm.data.edit_bones:
    eb.matrix = R @ snapshot[eb.name]
bpy.ops.object.mode_set(mode="OBJECT")
print("[ROTATE] armature bones = %d (matrix 左乘 Rz(+%.0f°)，roll 随之更正)"
      % (len(snapshot), ROT_DEG))

for obj in bpy.data.objects:
    if obj.type in ("MESH", "ARMATURE"):
        rot = tuple(round(math.degrees(a), 4) for a in obj.rotation_euler)
        print("  %-34s rot_deg=%s scale=%s" % (
            obj.name, rot, tuple(round(c, 6) for c in obj.scale)))
        if any(abs(a) > 1e-6 for a in rot):
            raise SystemExit("ORIENT_ABORTED: %s 出现对象级旋转" % obj.name)

# ---- 3) 复核：X/Y 应互换 --------------------------------------------------
lo1, hi1 = bounds()
s1 = hi1 - lo1
print("\n[AFTER ] size = (%.4f, %.4f, %.4f)  center=(%.4f, %.4f)"
      % (s1.x, s1.y, s1.z, (lo1.x + hi1.x) / 2, (lo1.y + hi1.y) / 2))

failures = []
if abs(s1.x - s0.y) > TOL:
    failures.append("X 跨度 %.4f 应等于原 Y 跨度 %.4f" % (s1.x, s0.y))
if abs(s1.y - s0.x) > TOL:
    failures.append("Y 跨度 %.4f 应等于原 X 跨度 %.4f" % (s1.y, s0.x))
if abs(s1.z - s0.z) > TOL:
    failures.append("Z 高度 %.4f 变了（应 %.4f）" % (s1.z, s0.z))
if abs(lo1.z) > TOL:
    failures.append("脚底离地: min Z = %.6f" % lo1.z)

print("\n  高度 Z = %.4f m  (不变，游戏内 %.4f m)" % (s1.z, s1.z * 0.70))
print("  左右 X = %.4f m  (原来在 Y 上)" % s1.x)
print("  前后 Y = %.4f m  (原来在 X 上)" % s1.y)

if failures:
    print("\nSELF-CHECK FAILED:")
    for f in failures:
        print("  - " + f)
    raise SystemExit("ORIENT_ABORTED")

bpy.context.preferences.filepaths.save_version = 0
print("\nSAVING -> %r" % bpy.data.filepath)
bpy.ops.wm.save_mainfile()
print("ORIENT_OK")
print("=" * 72)
