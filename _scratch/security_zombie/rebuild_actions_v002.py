import bpy,json,math
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion
P=Path('I:/工作项目/shellstrom2/ShellStorm2'); A=P/'assets/art/enemies/normal_enemy_3d/ranged_caster'; M=P/'assets/art/enemies/normal_enemy_3d/melee_chaser'
bpy.ops.wm.open_mainfile(filepath=str(A/'source/model/enm_ranged_sporeshooter01_model_v002.blend'))
bpy.context.preferences.filepaths.save_version=0
for image in bpy.data.images:
 if image.source == 'FILE':
  image.filepath=str(A/'source/model/textures/enm_ranged_sporeshooter01_basecolor_v001.jpeg');image.reload();image.pack()
arm=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH')
with bpy.data.libraries.load(str(M/'source/animation/enm_melee_fungboar01_animation_v003.blend'),link=False) as (src,dst): dst.actions=list(src.actions)
clips={}
for a in list(bpy.data.actions):
 key=a.name.replace('anim_melee_fungboar01_','').rsplit('_v',1)[0];a.name=key;a.use_fake_user=True;clips[key]=a
assert set(clips)=={'idle','walking','running','attack','hurt','dead'},list(clips)
arm.animation_data_create()
def assign(action):
 arm.animation_data.action=action
 if hasattr(action,'slots') and len(action.slots):arm.animation_data.action_slot=action.slots[0]
def aim():
 # Armature-space bone heads are already in rest space: no second matrix transform.
 upper=arm.pose.bones['L_Upperarm']; fore=arm.pose.bones['L_Forearm'];hand=arm.pose.bones['L_Hand']
 S=upper.head.copy(); l1=upper.length;l2=fore.length
 T=S+Vector((-.025,.27,-.015));v=T-S;d=min(v.length,l1+l2-.002);u=v.normalized();pole=Vector((0,0,-1));pole=(pole-u*pole.dot(u)).normalized()
 along=(l1*l1-l2*l2+d*d)/(2*d);height=math.sqrt(max(0,l1*l1-along*along));E=S+u*along+pole*height;T=S+u*d
 for pb,start,end in [(upper,S,E),(fore,E,T),(hand,T,T+Vector((0,hand.length,0)))]:
  direction=(end-start).normalized();q=Vector((0,1,0)).rotation_difference(direction);W=q.to_matrix().to_4x4();W.translation=start
  pb.matrix=W;bpy.context.view_layer.update()
 return (hand.head-T).length
for key in ['idle','walking','running']:
 a=clips[key].copy();a.name='armed_idle' if key=='idle' else key+'_armed';a.use_fake_user=True;clips[a.name]=a;assign(a)
 start,end=map(int,a.frame_range)
 for f in range(start,end+1):
  bpy.context.scene.frame_set(f);aim()
  for name in ['L_Upperarm','L_Forearm','L_Hand']:
   pb=arm.pose.bones[name];pb.keyframe_insert(data_path='rotation_quaternion',frame=f);pb.keyframe_insert(data_path='location',frame=f)
shoot=bpy.data.actions.new('shoot');shoot.use_fake_user=True;clips['shoot']=shoot
# Start from idle pose, then key all bones for an independent complete clip.
assign(clips['idle']);bpy.context.scene.frame_set(1);base={pb.name:pb.matrix_basis.copy() for pb in arm.pose.bones}
assign(shoot)
for f in range(1,26):
 for pb in arm.pose.bones:pb.matrix_basis=base[pb.name]
 bpy.context.view_layer.update();aim()
 phase=(f-1)/24;recoil=max(0,1-abs(phase-.60)/.12) if phase>=.48 else 0
 pb=arm.pose.bones['L_Forearm'];pb.rotation_quaternion=pb.rotation_quaternion@Quaternion((1,0,0),math.radians(-12)*recoil)
 for pb in arm.pose.bones:
  pb.keyframe_insert('location',frame=f);pb.keyframe_insert('rotation_quaternion',frame=f);pb.keyframe_insert('scale',frame=f)
scene=bpy.context.scene;scene.render.fps=30
assign(clips['armed_idle']);scene.frame_set(1)
out=A/'source/animation/enm_ranged_sporeshooter01_animation_v003.blend';bpy.ops.wm.save_as_mainfile(filepath=str(out))
report={'animation':str(out),'status':'authored_pending_visual_validation','clips':{k:{'frames':list(a.frame_range),'seconds':(a.frame_range[1]-a.frame_range[0])/30} for k,a in clips.items()},'bones':len(arm.data.bones)}
(P/'_scratch/security_zombie/rebuild_v002_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('SECURITY_ACTIONS_REBUILT',len(clips),str(out))
