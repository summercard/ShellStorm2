"""v005 绑定视觉证据：正面 / 侧面 网格渲染 + 骨骼叠加（Rest pose）。

骨骼叠加沿用法：把每根骨的 head/tail 投影到同一深度平面后用曲线画出，
正交相机取正投影 ⇒ 曲线压在网格之上，可直接读"骨落没落在身体对应位置"。
"""
import bpy
from pathlib import Path
from mathutils import Vector

P = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
SRC = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v005.blend'
OUT = P/'_scratch/security_zombie/bound_preview_v005'
OUT.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.open_mainfile(filepath=str(SRC))
s = bpy.context.scene
mesh = next(o for o in s.objects if o.type == 'MESH')
arm = next(o for o in s.objects if o.type == 'ARMATURE')

for o in list(s.objects):
    if o.type in {'LIGHT', 'CAMERA'}:
        bpy.data.objects.remove(o, do_unlink=True)

bpy.ops.object.light_add(type='AREA', location=(3, 4, 4))
l = bpy.context.object; l.data.energy = 900; l.data.size = 5
l.rotation_euler = (Vector((0, 0, 0.8)) - l.location).to_track_quat('-Z', 'Y').to_euler()
bpy.ops.object.light_add(type='AREA', location=(-3, -2, 2))
l = bpy.context.object; l.data.energy = 500; l.data.size = 4
l.rotation_euler = (Vector((0, 0, 0.8)) - l.location).to_track_quat('-Z', 'Y').to_euler()

s.render.engine = 'BLENDER_EEVEE_NEXT'
s.render.resolution_x = 600
s.render.resolution_y = 800
s.render.resolution_percentage = 100

def make_cam(name, loc):
    cd = bpy.data.cameras.new(name)
    cd.type = 'ORTHO'
    cd.ortho_scale = 2.3
    o = bpy.data.objects.new(name, cd)
    s.collection.objects.link(o)
    o.location = Vector(loc)
    o.rotation_euler = (Vector((0, 0, 0.9)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    return o


# --- plain mesh renders (binding reference) ---
for name, loc in (('plusY', (0, 4, 0.9)), ('plusX', (4, 0, 0.9))):
    cam = make_cam('cam_' + name, loc)
    s.camera = cam
    s.render.filepath = str(OUT / (name + '.png'))
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)

# --- bone overlay ---
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')


def flat(vec, mode, depth):
    v = vec.copy()
    if mode == 'front':
        v.y = depth
    else:
        v.x = depth
    return v


made = 0
for mode, depth, camloc in (('front', 0.9, (0, 4, 0.9)), ('side', 0.9, (4, 0, 0.9))):
    for b in arm.data.edit_bones:
        if b.name == 'Root':
            continue
        a = flat(arm.matrix_world @ b.head, mode, depth)
        z = flat(arm.matrix_world @ b.tail, mode, depth)
        c = bpy.data.curves.new('audit_%s_%s' % (mode, b.name), 'CURVE')
        c.dimensions = '3D'; c.bevel_depth = 0.004
        sp = c.splines.new('POLY'); sp.points.add(1)
        sp.points[0].co = (*a, 1); sp.points[1].co = (*z, 1)
        o = bpy.data.objects.new(c.name, c)
        s.collection.objects.link(o)
        m = bpy.data.materials.get('bone_audit') or bpy.data.materials.new('bone_audit')
        m.diffuse_color = (0.05, 1.0, 0.15, 1)
        o.data.materials.append(m)
        made += 1
    cam = make_cam('cam_bone_' + mode, camloc)
    s.camera = cam
    s.render.filepath = str(OUT / ('bone_overlay_%s.png' % mode))
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    for o in list(s.objects):
        if o.type == 'CURVE':
            bpy.data.objects.remove(o, do_unlink=True)

bpy.ops.object.mode_set(mode='OBJECT')
print('BOUND_PREVIEW_OK bones_drawn=%d' % made)
print('BOUND_PREVIEW_DIR', str(OUT))
