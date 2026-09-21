import bpy,math,json
from pathlib import Path
from mathutils import Vector
P=Path('I:/工作项目/shellstrom2/ShellStorm2');A=P/'assets/art/enemies/normal_enemy_3d/ranged_caster'
bpy.ops.wm.open_mainfile(filepath=str(A/'source/animation/enm_ranged_sporeshooter01_animation_v002.blend'))
a=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');s=bpy.context.scene
s.render.engine='BLENDER_EEVEE_NEXT';s.render.resolution_x=700;s.render.resolution_y=700;s.render.resolution_percentage=100
s.world.color=(.3,.3,.3)
for pos,power in [((3,4,5),700),((-3,2,3),500),((0,-3,4),600)]:
 bpy.ops.object.light_add(type='AREA',location=pos);o=bpy.context.object;o.data.energy=power;o.data.shape='DISK';o.data.size=4;o.rotation_euler=(Vector((0,0,1))-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(3,5,2.5));cam=bpy.context.object;cam.rotation_euler=(Vector((0,0,.95))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=2.7;s.camera=cam
out=P/'_scratch/security_zombie/previews_probe';report=[]
for name,f in [('armed_idle',1),('walking_armed',13),('running_armed',7),('shoot',15),('dead',73)]:
 action=bpy.data.actions[name];a.animation_data.action=action;a.animation_data.action_slot=action.slots[0];s.frame_set(f)
 s.render.filepath=str(out/('v002_'+name+'.png'));bpy.ops.render.render(write_still=True)
 report.append({'clip':name,'frame':f,'hand':list(a.pose.bones['L_Hand'].head)})
(P/'_scratch/security_zombie/pose_v002.json').write_text(json.dumps(report,indent=2))
