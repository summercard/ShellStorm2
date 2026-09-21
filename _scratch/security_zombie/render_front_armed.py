import bpy, math
from pathlib import Path
from mathutils import Vector
P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
ANIM = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v005.blend'
OUTDIR = P/'_scratch/security_zombie/retarget_preview'
OUTDIR.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ANIM))
sc = bpy.context.scene
arm = next(o for o in sc.objects if o.type == 'ARMATURE')
sc.render.engine = 'BLENDER_WORKBENCH'
sh = sc.display.shading
sh.light = 'STUDIO'; sh.color_type = 'TEXTURE'; sh.show_shadows = True; sh.show_cavity = True
sc.render.resolution_x = 420; sc.render.resolution_y = 560
sc.render.image_settings.file_format = 'PNG'
cam_data = bpy.data.cameras.new('cam'); cam_data.type = 'ORTHO'; cam_data.ortho_scale = 2.3
cam = bpy.data.objects.new('cam', cam_data); sc.collection.objects.link(cam); sc.camera = cam
aim = Vector((0.0, 0.0, 0.95))
# front = looking from +Y (character faces +Y)
cam.location = Vector((0.0, 2.6, 0.95))
cam.rotation_euler = (aim - cam.location).normalized().to_track_quat('-Z', 'Y').to_euler()
SHOTS = {'armed_idle': [1, 25, 49], 'walking_armed': [25], 'running_armed': [13], 'shoot': [1, 5, 9, 13, 17, 21]}
made = 0
for clip, frames in SHOTS.items():
    act = bpy.data.actions.get(clip)
    if act is None:
        continue
    arm.animation_data_create(); arm.animation_data.action = act
    if hasattr(arm.animation_data, 'action_slot') and hasattr(act, 'slots') and len(act.slots):
        arm.animation_data.action_slot = act.slots[0]
    for f in frames:
        sc.frame_set(f); bpy.context.view_layer.update()
        sc.render.filepath = str(OUTDIR/('%s_f%03d_front.png' % (clip, f)))
        bpy.ops.render.render(write_still=True)
        made += 1
print('FRONT_PREVIEW_RENDERED', made)
