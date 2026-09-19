import bpy
from mathutils import Vector

def walk(coll, depth=0):
    print("  " * depth + "[C] " + coll.name)
    for o in coll.objects:
        print("  " * (depth+1) + "%-30s type=%-8s loc=%s" % (
            o.name, o.type, tuple(round(v,3) for v in o.matrix_world.translation)))
    for c in coll.children:
        walk(c, depth+1)

print("########## SCENE COLLECTIONS ##########")
for c in bpy.data.collections:
    if c.name.startswith("02") or "女儿墙" in c.name or "parapet" in c.name.lower():
        walk(c)
print()
print("########## ALL COLLECTIONS (top level) ##########")
def top(c, seen):
    pass
parents = set()
for c in bpy.data.collections:
    for ch in c.children:
        parents.add(ch.name)
print("top-level:", [c.name for c in bpy.data.collections if c.name not in parents])
print()
print("########## MESH STATS for parapet-related objects ##########")
for o in bpy.data.objects:
    if o.type == "MESH" and ("女儿墙" in o.name or "parapet" in o.name.lower()):
        me = o.data
        mn = [ 1e9]*3; mx = [-1e9]*3
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            for i in range(3):
                mn[i]=min(mn[i],w[i]); mx[i]=max(mx[i],w[i])
        print("  %-28s verts=%-5d faces=%-5d mats=%s" % (o.name, len(me.vertices), len(me.polygons), [m.name if m else None for m in me.materials]))
        print("       world AABB min=%s max=%s" % (tuple(round(v,3) for v in mn), tuple(round(v,3) for v in mx)))
