import bpy
from mathutils import Vector

def aabb(o):
    mn=[1e9]*3; mx=[-1e9]*3
    for c in o.bound_box:
        w=o.matrix_world @ Vector(c)
        for i in range(3):
            mn[i]=min(mn[i],w[i]); mx[i]=max(mx[i],w[i])
    return mn,mx

TARGETS = ["女儿墙直段_主体","女儿墙直段_水泥结构_制作",
           "女儿墙外角_主体","女儿墙外角_水泥结构_制作",
           "女儿墙挂藤_主体","女儿墙外角挂藤_主体"]
for name in TARGETS:
    o = bpy.data.objects.get(name)
    if o is None:
        print("MISSING", name); continue
    me = o.data
    mn,mx = aabb(o)
    print("###### %s" % name)
    print("   verts=%d edges=%d faces=%d  users_of_mesh=%d" % (len(me.vertices), len(me.edges), len(me.polygons), me.users))
    print("   mats=%s" % [ (s.material.name if s.material else None) for s in o.material_slots ])
    print("   modifiers=%s" % [(m.name,m.type) for m in o.modifiers])
    print("   world AABB min=%s max=%s  size=%s" % (
        tuple(round(v,4) for v in mn), tuple(round(v,4) for v in mx),
        tuple(round(mx[i]-mn[i],4) for i in range(3))))
    # face normal buckets -> 判断是不是纯立方体
    from collections import Counter
    c = Counter()
    for p in me.polygons:
        n = p.normal
        c[(round(n.x,2),round(n.y,2),round(n.z,2))] += 1
    print("   face normal buckets (top 8): %s" % c.most_common(8))
    # 顶点 Z 分层
    zs = Counter(round((o.matrix_world @ v.co).z, 3) for v in me.vertices)
    ys = Counter(round((o.matrix_world @ v.co).y, 3) for v in me.vertices)
    xs = Counter(round((o.matrix_world @ v.co).x, 3) for v in me.vertices)
    print("   distinct X=%d Y=%d Z=%d" % (len(xs), len(ys), len(zs)))
    print("   Z levels (top 8): %s" % sorted(zs.items())[:8])
    print("   UV layers=%s  color_attrs=%s" % ([l.name for l in me.uv_layers], [a.name for a in me.color_attributes]))
