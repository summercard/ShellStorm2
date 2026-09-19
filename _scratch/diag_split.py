import bpy, bmesh, random
from mathutils import Vector, noise

src = bpy.data.objects["女儿墙直段_水泥结构_制作"]

coll = bpy.data.collections.new("work")
bpy.context.scene.collection.children.link(coll)
for owner in list(src.users_collection):
    owner.objects.unlink(src)
coll.objects.link(src)
src.data = src.data.copy()

bpy.ops.object.select_all(action="DESELECT")
src.select_set(True)
bpy.context.view_layer.objects.active = src
print("active=", bpy.context.view_layer.objects.active, "mode=", bpy.context.mode)
bpy.ops.object.mode_set(mode="EDIT")
print("after mode_set EDIT, mode=", bpy.context.mode)
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.separate(type="LOOSE")
bpy.ops.object.mode_set(mode="OBJECT")
print("after separate, mode=", bpy.context.mode)

parts = [o for o in coll.objects if o.type == "MESH"]
print("parts in coll =", len(parts), " scene objects =", len(bpy.context.scene.objects))
for p in parts[:4]:
    mn=[1e9]*3; mx=[-1e9]*3
    for v in p.data.vertices:
        w = p.matrix_world @ v.co
        for i in range(3):
            mn[i]=min(mn[i],w[i]); mx[i]=max(mx[i],w[i])
    print("  part %-28s verts=%-4d aabb=%s..%s  matrix_world_translation=%s bound_box0=%s" % (
        p.name, len(p.data.vertices), tuple(round(x,3) for x in mn), tuple(round(x,3) for x in mx),
        tuple(round(x,3) for x in p.matrix_world.translation), tuple(round(x,3) for x in p.bound_box[0])))

# 造一个生成器
me = bpy.data.meshes.new("er")
bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
for v in bm.verts:
    v.co.x*=1.5; v.co.y*=0.9; v.co.z*=1.1
bm.to_mesh(me); bm.free()
e = bpy.data.objects.new("er", me); e.location=Vector((-0.90,0.0,1.80))
bpy.context.scene.collection.objects.link(e)
bpy.context.view_layer.update()
mn=[1e9]*3; mx=[-1e9]*3
for v in e.data.vertices:
    w = e.matrix_world @ v.co
    for i in range(3):
        mn[i]=min(mn[i],w[i]); mx[i]=max(mx[i],w[i])
print("eroder aabb =", tuple(round(x,3) for x in mn), "..", tuple(round(x,3) for x in mx))

hits = 0
for p in parts:
    pmn=[1e9]*3; pmx=[-1e9]*3
    for v in p.data.vertices:
        w = p.matrix_world @ v.co
        for i in range(3):
            pmn[i]=min(pmn[i],w[i]); pmx[i]=max(pmx[i],w[i])
    ok = all(pmn[i] <= mx[i] and pmx[i] >= mn[i] for i in range(3))
    if ok: hits += 1
print("与生成器相交的积木数 =", hits)
