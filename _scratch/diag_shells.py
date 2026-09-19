import bpy, bmesh
from mathutils import Vector

src = bpy.data.objects["女儿墙直段_水泥结构_制作"]

def shells(me, label):
    bm = bmesh.new(); bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    seen = set(); out = []
    for f in bm.faces:
        if f.index in seen: continue
        comp = []; stack = [f]
        while stack:
            cur = stack.pop()
            if cur.index in seen: continue
            seen.add(cur.index); comp.append(cur)
            for e in cur.edges:
                for nf in e.link_faces:
                    if nf.index not in seen: stack.append(nf)
        vs = set()
        for c in comp: vs.update(c.verts)
        mn=[1e9]*3; mx=[-1e9]*3
        for v in vs:
            for i in range(3):
                mn[i]=min(mn[i],v.co[i]); mx[i]=max(mx[i],v.co[i])
        vol = 0.0
        for c in comp:
            for tri in c.loop_triangles if False else []:
                pass
        # 用面重心 + 面积做散度定理近似
        vv = 0.0
        for c in comp:
            loops = list(c.loops)
            for i in range(1, len(loops)-1):
                a = loops[0].vert.co; b = loops[i].vert.co; d = loops[i+1].vert.co
                vv += a.dot(b.cross(d)) / 6.0
        out.append((len(comp), len(vs), sum(c.calc_area() for c in comp), vv, tuple(round(x,3) for x in mn), tuple(round(x,3) for x in mx)))
    out.sort(key=lambda r: -r[2])
    print("###### %s shells=%d" % (label, len(out)))
    for i,(nf,nv,area,vol,mn,mx) in enumerate(out[:26]):
        print("  shell%02d faces=%-4d verts=%-4d area=%-8.4f signedvol=%+9.5f bbox=%s..%s" % (i,nf,nv,area,vol,mn,mx))
    bm.free()

shells(src.data, "S0 source")

o = src.copy(); o.data = src.data.copy(); o.name="far"
bpy.context.scene.collection.objects.link(o)
me2 = bpy.data.meshes.new("c2")
bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0); bm.to_mesh(me2); bm.free()
cut2 = bpy.data.objects.new("c2", me2); cut2.location=Vector((0,0,-5))
bpy.context.scene.collection.objects.link(cut2)
m2 = o.modifiers.new("b","BOOLEAN"); m2.operation="DIFFERENCE"; m2.solver="EXACT"; m2.object=cut2
bpy.context.view_layer.objects.active=o
bpy.ops.object.modifier_apply(modifier=m2.name)
shells(o.data, "S4 far-boolean")
