import math
import bpy
from mathutils import Vector

arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
mesh = [o for o in bpy.data.objects if o.type == "MESH"][0]
print("=" * 72)
print("POSE / ORIENTATION DETAIL")
print("=" * 72)
print("mesh = %r   armature = %r" % (mesh.name, arm.name))

print("\n[NON-REST POSE BONES]  (pose vs rest_bone matrix_basis 偏差)")
found = 0
for pb in arm.pose.bones:
    basis = pb.matrix_basis
    t = basis.to_translation()
    q = basis.to_quaternion()
    ang = math.degrees(q.angle)
    s = pb.scale
    if t.length > 1e-6 or abs(ang) > 1e-3 or (Vector(s) - Vector((1,1,1))).length > 1e-6:
        found += 1
        e = basis.to_euler()
        print("  %-14s 平移=%.6f m  旋转=%.3f°  (euler deg: %.2f, %.2f, %.2f)  缩放=%s"
              % (pb.name, t.length, ang,
                 math.degrees(e.x), math.degrees(e.y), math.degrees(e.z),
                 tuple(round(c, 6) for c in s)))
        # 这是哪根骨、原本应该朝哪
        rb = arm.data.bones[pb.name]
        print("         rest head=%s tail=%s" % (
            tuple(round(c,4) for c in rb.head_local), tuple(round(c,4) for c in rb.tail_local)))
if found == 0:
    print("  <全部静置>")

print("\n[骨骼方向抽样]  (rest_bone 的 head->tail 朝向，判断骨架前向)")
for nm in ("Root", "Hip", "Spine01", "Head", "L_Foot", "L_ToeBase", "L_Hand"):
    if nm not in arm.data.bones:
        print("  %-12s <不存在>" % nm); continue
    b = arm.data.bones[nm]
    d = (b.tail_local - b.head_local)
    print("  %-12s head=%s tail=%s  dir=%s" % (
        nm, tuple(round(c,4) for c in b.head_local), tuple(round(c,4) for c in b.tail_local),
        tuple(round(c,4) for c in d.normalized())))

print("\n[网格 UV / 材质绑定]")
print("  uv_layers = %s" % [u.name for u in mesh.data.uv_layers])
uv = mesh.data.uv_layers.active
if uv:
    us = [d.uv[0] for d in uv.data]; vs = [d.uv[1] for d in uv.data]
    print("  UV 范围  u=[%.4f, %.4f]  v=[%.4f, %.4f]   (0..1 = 完整覆盖)" % (min(us), max(us), min(vs), max(vs)))
print("  materials = %s" % [m.name for m in mesh.data.materials])
print("\n[顶点组数量] %d" % len(mesh.vertex_groups))
ng = [g.name for g in mesh.vertex_groups]
print("  前 12 个: %s" % ng[:12])
print("=" * 72)
