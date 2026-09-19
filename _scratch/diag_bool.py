import bpy, bmesh
from mathutils import Vector

src = bpy.data.objects["女儿墙直段_水泥结构_制作"]

def stats(me, label):
    bm = bmesh.new(); bm.from_mesh(me)
    vol = bm.calc_volume(signed=False)
    area = sum(f.calc_area() for f in bm.faces)
    nonmanifold = sum(1 for e in bm.edges if not e.is_manifold)
    shells = 0
    seen = set()
    for f in bm.faces:
        if f.index in seen: continue
        shells += 1
        stack=[f]
        while stack:
            cur = stack.pop()
            if cur.index in seen: continue
            seen.add(cur.index)
            for e in cur.edges:
                for nf in e.link_faces:
                    if nf.index not in seen: stack.append(nf)
    mn=[1e9]*3; mx=[-1e9]*3
    for v in me.vertices:
        for i in range(3):
            mn[i]=min(mn[i],v.co[i]); mx[i]=max(mx[i],v.co[i])
    print("%-24s V=%-4d F=%-4d E=%-5d shells=%-4d nonmanifold_edges=%-4d vol=%.6f area=%.6f bbox=[%.4f,%.4f,%.4f]x[%.4f,%.4f,%.4f]" % (
        label, len(me.vertices), len(me.polygons), len(me.edges), shells, nonmanifold, vol, area, mn[0],mn[1],mn[2],mx[0],mx[1],mx[2]))
    bm.free()
    return vol, area

v0, a0 = stats(src.data, "S0 source")

# 中段布尔（切割体 0.8m 立方 @ (0,0,0.9)）→ 理论体积减少 = 0.8^3 = 0.512
o = src.copy(); o.data = src.data.copy(); o.name="mid"
bpy.context.scene.collection.objects.link(o)
me = bpy.data.meshes.new("cut")
bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
for v in bm.verts:
    v.co.x*=0.8; v.co.y*=0.8; v.co.z*=0.8
bm.to_mesh(me); bm.free()
cut = bpy.data.objects.new("cut", me); cut.location=Vector((0.0,0.0,0.9))
bpy.context.scene.collection.objects.link(cut)
m = o.modifiers.new("b","BOOLEAN"); m.operation="DIFFERENCE"; m.solver="EXACT"; m.object=cut
bpy.context.view_layer.objects.active=o
bpy.ops.object.modifier_apply(modifier=m.name)
bpy.data.objects.remove(cut, do_unlink=True)
v1, a1 = stats(o.data, "S3 mid-boolean(cube .8)")
print("   delta vol=%.6f (理论 -0.512)   delta area=%.6f" % (v1-v0, a1-a0))

# 完全不接触的布尔（切割体在 z=-5 远处）
o2 = src.copy(); o2.data = src.data.copy(); o2.name="far"
bpy.context.scene.collection.objects.link(o2)
me2 = bpy.data.meshes.new("cut2")
bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
bm.to_mesh(me2); bm.free()
cut2 = bpy.data.objects.new("cut2", me2); cut2.location=Vector((0.0,0.0,-5.0))
bpy.context.scene.collection.objects.link(cut2)
m2 = o2.modifiers.new("b","BOOLEAN"); m2.operation="DIFFERENCE"; m2.solver="EXACT"; m2.object=cut2
bpy.context.view_layer.objects.active=o2
bpy.ops.object.modifier_apply(modifier=m2.name)
bpy.data.objects.remove(cut2, do_unlink=True)
v2, a2 = stats(o2.data, "S4 far-boolean(no contact)")
print("   delta vol=%.6f  delta area=%.6f  <- 布尔自身的附带影响" % (v2-v0, a2-a0))
