import bpy, bmesh
from mathutils import Matrix, Vector

START = 2.05
def band(me):
    return sorted((round(v.co.x,5), round(v.co.y,5), round(v.co.z,5))
                  for v in me.vertices if abs(v.co.x) >= START)

src = bpy.data.objects["女儿墙直段_水泥结构_制作"]
s0 = band(src.data)
print("S0 source              verts=%d band=%d" % (len(src.data.vertices), len(s0)))

def fresh(tag):
    o = src.copy(); o.data = src.data.copy(); o.name = tag
    bpy.context.scene.collection.objects.link(o)
    return o

# S1: 纯 bmesh 往返
o = fresh("s1")
bm = bmesh.new(); bm.from_mesh(o.data); bm.to_mesh(o.data); bm.free()
s1 = band(o.data)
print("S1 bmesh roundtrip     verts=%d band=%d  lost=%d  added=%d" % (
    len(o.data.vertices), len(s1), len(set(s0)-set(s1)), len(set(s1)-set(s0))))

# S2: + dissolve_degenerate
o = fresh("s2")
bm = bmesh.new(); bm.from_mesh(o.data)
bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges[:])
bm.to_mesh(o.data); bm.free()
s2 = band(o.data)
print("S2 +dissolve_degenerate verts=%d band=%d  lost=%d  added=%d" % (
    len(o.data.vertices), len(s2), len(set(s0)-set(s2)), len(set(s2)-set(s0))))

# S3: + 一个完全在中段的布尔
o = fresh("s3")
me = bpy.data.meshes.new("cut")
bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=2, use_grid_fill=True)
for v in bm.verts:
    v.co.x *= 0.8; v.co.y *= 0.8; v.co.z *= 0.8
bm.to_mesh(me); bm.free()
cut = bpy.data.objects.new("cut", me); cut.location = Vector((0.0, 0.0, 0.9))
bpy.context.scene.collection.objects.link(cut)
m = o.modifiers.new("b", "BOOLEAN"); m.operation="DIFFERENCE"; m.solver="EXACT"; m.object=cut
bpy.context.view_layer.objects.active = o
bpy.ops.object.modifier_apply(modifier=m.name)
bpy.data.objects.remove(cut, do_unlink=True)
s3 = band(o.data)
print("S3 +boolean(mid)       verts=%d band=%d  lost=%d  added=%d" % (
    len(o.data.vertices), len(s3), len(set(s0)-set(s3)), len(set(s3)-set(s0))))

# 打印 S0 端头带的 X 分布，看它到底长什么样
from collections import Counter
print()
print("S0 band X values:", sorted(Counter(round(v.co.x,5) for v in src.data.vertices if abs(v.co.x)>=START).items())[:20])
print("S0 band Y values:", sorted(Counter(round(v.co.y,5) for v in src.data.vertices if abs(v.co.x)>=START).items())[:20])
print()
print("S3 丢失的坐标样本:", sorted(set(s0)-set(s3))[:8])
print("S3 新增的坐标样本:", sorted(set(s3)-set(s0))[:8])
