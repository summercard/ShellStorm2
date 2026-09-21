import bpy,json,hashlib
from pathlib import Path
P=Path('I:/工作项目/shellstrom2/ShellStorm2');A=P/'assets/art/enemies/normal_enemy_3d/ranged_caster';OUT=A/'components/enm_ranged_sporeshooter01_visual_top3d.glb'
bpy.ops.wm.open_mainfile(filepath=str(A/'source/animation/enm_ranged_sporeshooter01_animation_v003.blend'))
scene=bpy.context.scene
arm=next(o for o in scene.objects if o.type=='ARMATURE');mesh=next(o for o in scene.objects if o.type=='MESH' and o.name.startswith('enm_ranged'))
# remove preview gun from export copy, and all non-character objects
for o in list(bpy.data.objects):
 if o not in (arm,mesh): bpy.data.objects.remove(o,do_unlink=True)
# remove scene extras
for s in list(bpy.data.scenes):
 if s != scene: bpy.data.scenes.remove(s)
arm.animation_data_clear();arm.animation_data_create()
# Export each action as a named NLA track. Blender 4 actions use slots.
order=['idle','armed_idle','walking','walking_armed','running','running_armed','attack','hurt','dead','shoot']
for name in order:
 act=bpy.data.actions.get(name); assert act is not None,name
 act.name='anim_ranged_sporeshooter01_'+name
 track=arm.animation_data.nla_tracks.new();track.name=name
 strip=track.strips.new(name,1,act);strip.action_frame_start=act.frame_range[0];strip.action_frame_end=act.frame_range[1];strip.frame_start=1;strip.frame_end=1+(act.frame_range[1]-act.frame_range[0]);strip.extrapolation='NOTHING';track.mute=False
# Disable all but one? NLA tracks are exported separately by name; keep strips with unique blend.
scene.render.fps=30;scene.frame_start=1;scene.frame_end=97;scene.frame_set(1)
bpy.ops.object.select_all(action='DESELECT');arm.select_set(True);mesh.select_set(True);bpy.context.view_layer.objects.active=arm
bpy.ops.export_scene.gltf(filepath=str(OUT),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_frame_range=False,export_yup=True)
report={'output':str(OUT),'sha256':hashlib.sha256(OUT.read_bytes()).hexdigest(),'bytes':OUT.stat().st_size,'bones':len(arm.data.bones),'actions':order}
(P/'_scratch/security_zombie/export_ranged_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('RANGED_GLB_EXPORT_OK',OUT,report)
