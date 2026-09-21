import bpy, json, math
from pathlib import Path
from mathutils import Vector

P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
SRC = P/'assets/art/weapons/weapon_3d/source/security_short_shotgun/wpn_security_short_shotgun_source_v001.blend'

bpy.ops.wm.open_mainfile(filepath=str(SRC))

def world_bbox(objs):
    mins = Vector((1e9,)*3); maxs = Vector((-1e9,)*3)
    any_=False
    for o in objs:
        if o.type != 'MESH': continue
        any_=True
        for c in o.bound_box:
            v = o.matrix_world @ Vector(c)
            mins = Vector(min(a,b) for a,b in zip(mins,v))
            maxs = Vector(max(a,b) for a,b in zip(maxs,v))
    return mins, maxs, any_

root = None
for c in bpy.data.collections:
    if '中文资产管理' in c.name: root=c
print('ROOT_COLLECTION', root.name if root else None)
print('ALL_COLLECTIONS', [c.name for c in bpy.data.collections])

# gather mesh + sockets under WeaponRoot
wr = bpy.data.objects.get('WeaponRoot')
print('WEAPONROOT', wr.name if wr else None, 'parent=', wr.parent.name if (wr and wr.parent) else None)

meshes=[]; sockets=[]
for o in bpy.data.objects:
    if o.type=='MESH': meshes.append(o)
    elif o.type=='EMPTY': sockets.append(o)
print('MESH_NAMES', [m.name for m in meshes])
print('SOCKET_NAMES', [s.name for s in sockets])

mins,maxs,any_ = world_bbox(meshes)
print('WORLD_BBOX_MIN', [round(x,4) for x in mins])
print('WORLD_BBOX_MAX', [round(x,4) for x in maxs])
if any_:
    print('WORLD_DIMS', [round(x,4) for x in (maxs-mins)])

# local bbox relative to WeaponRoot
if wr:
    lmins=Vector((1e9,)*3); lmaxs=Vector((-1e9,)*3)
    for o in meshes:
        for c in o.bound_box:
            v = wr.matrix_world.inverted() @ (o.matrix_world @ Vector(c))
            lmins=Vector(min(a,b) for a,b in zip(lmins,v)); lmaxs=Vector(max(a,b) for a,b in zip(lmaxs,v))
    print('LOCAL_BBOX_MIN', [round(x,4) for x in lmins])
    print('LOCAL_BBOX_MAX', [round(x,4) for x in lmaxs])
    print('LOCAL_DIMS', [round(x,4) for x in (lmaxs-lmins)])

print('MATERIALS', [(m.name, m.use_nodes, getattr(m,'diffuse_color',None)) for m in bpy.data.materials])
# palette image usage
pal=[]
for m in bpy.data.materials:
    if m.use_nodes:
        for n in m.node_tree.nodes:
            if n.type=='TEX_IMAGE':
                pal.append((m.name, n.image.name if n.image else None))
print('TEX_IMAGE_NODES', pal)

# UV layers of each mesh
for m in meshes:
    uv = [l.name for l in m.data.uv_layers]
    print('UV_LAYERS', m.name, uv, 'active=', m.data.uv_layers.active.name if m.data.uv_layers.active else None)

# animation
for o in bpy.data.objects:
    if o.animation_data and o.animation_data.action:
        a=o.animation_data.action
        print('ANIM_OBJ', o.name, 'ACTION', a.name, 'fcurves', [fc.data_path+'.'+str(fc.array_index) for fc in a.fcurves])
print('SCENE_FRAMES', bpy.context.scene.frame_start, bpy.context.scene.frame_end)
print('NODE_GROUPS', [g.name for g in bpy.data.node_groups])
