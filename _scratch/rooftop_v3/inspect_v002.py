"""Read-only inspection of the v002 rooftop library: collections, package roots,
and every mesh carrying the parapet geometry (plus its material + UV panel)."""

import bpy
from mathutils import Vector

TAG = "\u5973\u513f\u5899"  # 女儿墙


def aabb_world(obj):
    xs = []
    ys = []
    zs = []
    for v in obj.data.vertices:
        w = obj.matrix_world @ v.co
        xs.append(w.x)
        ys.append(w.y)
        zs.append(w.z)
    if not xs:
        return None
    return (
        round(min(xs), 4), round(max(xs), 4),
        round(min(ys), 4), round(max(ys), 4),
        round(min(zs), 4), round(max(zs), 4),
    )


print("== COLLECTIONS ==")
for c in bpy.data.collections:
    print("COLL %-40s objs=%-3d children=%s" % (c.name, len(c.objects), [x.name for x in c.children]))

print("== MESH OBJECTS (parapet only) ==")
for o in bpy.data.objects:
    if o.type != "MESH":
        continue
    if TAG not in o.name and TAG not in "".join(c.name for c in o.users_collection):
        continue
    me = o.data
    print(
        "MESH %-34s v=%-5d f=%-5d uv=%s mats=%s\n     coll=%s\n     world_aabb=%s"
        % (
            o.name,
            len(me.vertices),
            len(me.polygons),
            [l.name for l in me.uv_layers],
            [(m.name if m else None) for m in me.materials],
            [c.name for c in o.users_collection],
            aabb_world(o),
        )
    )

print("== EMPTY ROOTS ==")
for o in bpy.data.objects:
    if o.type == "EMPTY" and TAG in o.name:
        print(
            "EMPTY %-32s world_loc=%s coll=%s"
            % (
                o.name,
                tuple(round(x, 4) for x in o.matrix_world.translation),
                [c.name for c in o.users_collection],
            )
        )

print("== PALETTE IMAGES ==")
for im in bpy.data.images:
    print("IMAGE %-52s size=%s" % (im.name, tuple(im.size)))

print("== MATERIALS ==")
for m in bpy.data.materials:
    print("MAT %-34s nodes=%s" % (m.name, [n.type for n in m.node_tree.nodes] if m.use_nodes else None))
