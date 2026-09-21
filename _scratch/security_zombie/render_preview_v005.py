import bpy, math
from pathlib import Path
from mathutils import Vector
P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
ANIM = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v005.blend'
OUTDIR = P/'_scratch/security_zombie/retarget_preview'
OUTDIR.mkdir(parents=True, exist_ok=True)
SHOTS = {
    'idle':    [1, 49, 97],
    'walking': [1, 13, 25, 37, 49],
    'running': [1, 7, 13, 19, 25],
    'attack':  [1, 13, 26, 39, 52],
    'hurt':    [1, 13, 25],
    'dead':    [1, 19, 37, 55, 73],
    'armed_idle': [25, 73],
    'walking_armed': [13, 37],
    'running_armed': [13],
    'shoot':   [1, 9, 17, 25],
}

bpy.ops.wm.open_mainfile(filepath=str(ANIM))
sc = bpy.context.scene
arm = next(o for o in sc.objects if o.type == 'ARMATURE')
mesh = next(o for o in sc.objects if o.type == 'MESH')

sc.render.engine = 'BLENDER_WORKBENCH'
sh = sc.display.shading
sh.light = 'STUDIO'
sh.color_type = 'TEXTURE'
sh.show_shadows = True
sh.show_cavity = True
sc.render.resolution_x = 420
sc.render.resolution_y = 560
sc.render.resolution_percentage = 100
sc.render.image_settings.file_format = 'PNG'
sc.render.film_transparent = False

cam_data = bpy.data.cameras.new('cam')
cam_data.type = 'ORTHO'
cam_data.ortho_scale = 2.3
cam = bpy.data.objects.new('cam', cam_data)
sc.collection.objects.link(cam)
sc.camera = cam
# raw FBX front was -Y; after the 180 deg fix the character faces Blender +Y
target = Vector((0.0, 0.0, 0.93))
cam.location = Vector((1.5, 1.9, 1.05))
d = (target - cam.location).normalized()
cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()

made = []
for clip, frames in SHOTS.items():
    act = bpy.data.actions.get(clip)
    if act is None:
        print('MISSING_CLIP', clip); continue
    arm.animation_data_create()
    arm.animation_data.action = act
    if hasattr(arm.animation_data, 'action_slot') and hasattr(act, 'slots') and len(act.slots):
        arm.animation_data.action_slot = act.slots[0]
    for f in frames:
        sc.frame_set(f)
        bpy.context.view_layer.update()
        p = OUTDIR/('%s_f%03d.png' % (clip, f))
        sc.render.filepath = str(p)
        bpy.ops.render.render(write_still=True)
        made.append(p.name)
print('PREVIEW_RENDERED', len(made))
print('PREVIEW_DIR', str(OUTDIR))
