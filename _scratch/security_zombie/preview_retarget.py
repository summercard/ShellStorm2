import bpy, json, math
from pathlib import Path
from mathutils import Vector
P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
ANIM = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v004.blend'
OUT = P/'_scratch/security_zombie/retarget_preview'
OUT.mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ANIM))
s = bpy.context.scene
arm = next(o for o in s.objects if o.type == 'ARMATURE')
mesh = next(o for o in s.objects if o.type == 'MESH')
for o in list(s.objects):
    if o.type in {'LIGHT', 'CAMERA'}:
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.object.light_add(type='AREA', location=(3, 4, 3)); l = bpy.context.object
l.data.energy = 1500; l.data.size = 6
l.rotation_euler = (Vector((0, 0, 0.9)) - l.location).to_track_quat('-Z', 'Y').to_euler()
bpy.ops.object.light_add(type='AREA', location=(-3, -4, 2)); l = bpy.context.object
l.data.energy = 900; l.data.size = 5
l.rotation_euler = (Vector((0, 0, 0.9)) - l.location).to_track_quat('-Z', 'Y').to_euler()
s.render.engine = 'BLENDER_EEVEE_NEXT'
s.render.resolution_x = 420; s.render.resolution_y = 560; s.render.resolution_percentage = 100

def cam(loc):
    bpy.ops.object.camera_add(location=loc); c = bpy.context.object
    c.data.type = 'ORTHO'; c.data.ortho_scale = 2.4
    c.rotation_euler = (Vector((0, 0, 0.9)) - c.location).to_track_quat('-Z', 'Y').to_euler()
    s.camera = c
    return c

# numeric motion probe: how far do bone tips travel across each clip
motion = {}
arm.animation_data_create()
for clip in ['idle', 'walking', 'running', 'attack', 'hurt', 'dead']:
    act = bpy.data.actions.get(clip)
    if act is None:
        continue
    arm.animation_data.action = act
    if hasattr(act, 'slots') and len(act.slots):
        arm.animation_data.action_slot = act.slots[0]
    start, end = int(act.frame_range[0]), int(act.frame_range[1])
    samples = []
    for f in range(start, end + 1, max(1, (end - start) // 12)):
        s.frame_set(f)
        bpy.context.view_layer.update()
        pts = [arm.pose.bones[n].tail.copy() for n in ('L_Hand', 'R_Hand', 'L_Foot', 'R_Foot', 'Head')]
        samples.append(pts)
    span = 0.0
    for i in range(len(samples[0])):
        xs = [p[i] for p in samples]
        span = max(span, max((a - b).length for a in xs for b in xs))
    motion[clip] = round(span, 4)
print('MOTION_SPAN', json.dumps(motion))

front = cam((0, 4, 0.9))
side = cam((4, 0, 0.9))
for clip, frames in [('idle', [1, 25]), ('walking', [1, 13, 25]), ('running', [1, 7, 13]),
                     ('attack', [1, 20, 26]), ('hurt', [1, 13]), ('dead', [1, 40, 73])]:
    act = bpy.data.actions.get(clip)
    if act is None:
        continue
    arm.animation_data.action = act
    if hasattr(act, 'slots') and len(act.slots):
        arm.animation_data.action_slot = act.slots[0]
    for f in frames:
        s.frame_set(f)
        bpy.context.view_layer.update()
        s.camera = front
        s.render.filepath = str(OUT / ('%s_f%03d_front.png' % (clip, f)))
        bpy.ops.render.render(write_still=True)
        s.camera = side
        s.render.filepath = str(OUT / ('%s_f%03d_side.png' % (clip, f)))
        bpy.ops.render.render(write_still=True)
(P/'_scratch/security_zombie/retarget_motion.json').write_text(json.dumps(motion, indent=2), encoding='utf-8')
print('RETARGET_PREVIEW_OK')
