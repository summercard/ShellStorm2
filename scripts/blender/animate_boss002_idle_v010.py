import bpy,math,json,hashlib
from pathlib import Path
from mathutils import Vector,Quaternion,Matrix
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/idle_v010';P.mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v009.blend'))
s=bpy.data.scenes['BOSS002_SOURCE_TPOSE'];bpy.context.window.scene=s;rig=bpy.data.objects['Boss002_Rig'];arm=rig.data
# Rotate the keyboard's long axis about its center so the hand holds the middle
# of its long side, with the same thickness and opposing finger contact.
key=bpy.data.objects['Keyboard outer shell'];center=sum((key.matrix_world@Vector(c) for c in key.bound_box),Vector())/8
rot=Matrix.Rotation(math.pi/2,4,'X');target=Vector((center.x,center.y,1.515));transform=Matrix.Translation(target)@rot@Matrix.Translation(-center)
for o in s.objects:
 if o.get('asset_role')=='hand_prop_keyboard':o.matrix_world=transform@o.matrix_world
s['asset_version']='v010';bpy.context.view_layer.update()
signature=hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,list(b.head_local),list(b.tail_local),b.use_deform) for b in arm.bones],sort_keys=True).encode()).hexdigest();tri=18684
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v010.blend'))
rig.animation_data_create();act=bpy.data.actions.new('idle');rig.animation_data.action=act;act.use_fake_user=True
def axis(pb,v,a):return Quaternion(pb.bone.matrix_local.to_3x3().inverted()@Vector(v),a)
def pose(frame):
 t=(frame-1)/96*math.tau
 for pb in rig.pose.bones:pb.location=(0,0,0);pb.rotation_mode='QUATERNION';pb.rotation_quaternion=(1,0,0,0)
 for sign,side in [(1,'L'),(-1,'R')]:
  phase=t+(0 if side=='L' else .35);rig['stretch_'+side]=.94+.065*math.sin(phase-.3)
  for i,a in enumerate([-.46,-.10,.20,.32,.30,.18]):
   pb=rig.pose.bones['arm_%02d.%s'%(i+1,side)];pb.rotation_quaternion=axis(pb,(0,1,0),sign*(a+.13*math.sin(phase-i*.24)))
  pb=rig.pose.bones['hand_ctrl.'+side];pb.rotation_quaternion=axis(pb,(0,1,0),-sign*(sum([-.46,-.10,.20,.32,.30,.18]) + sum(.13*math.sin(phase-j*.24) for j in range(6)) - .06 + .04*math.sin(phase-.55)))@axis(pb,(0,0,1),math.radians(62 if side=='L' else 18))
  for d in [1,2,3]:
   for j,angle in [(1,48),(2,32)]:
    pb=rig.pose.bones['digit%d_%02d.%s'%(d,j,side)];pb.rotation_quaternion=axis(pb,(0,1,0),sign*math.radians(angle if side=='L' else (74 if j==1 else 84)))
  for j,angle in [(1,22),(2,30)]:
   pb=rig.pose.bones['digit4_%02d.'%j+side];pb.rotation_quaternion=axis(pb,(0,0,1),-sign*math.radians(46 if j==1 else 15))@axis(pb,(0,1,0),sign*math.radians(angle))
 for i in range(1,4):
  pb=rig.pose.bones['support_%02d'%i];pb.rotation_quaternion=axis(pb,(1,0,0),.035*math.sin(t-(i-1)*.18))
 # Small delayed pendulum, not a self-supporting floating whip. Grip stays firm.
 for i in range(1,17):
  pb=rig.pose.bones['cable_%02d'%i];pb.rotation_quaternion=axis(pb,(1,0,0),.005*math.sin(t-i*.2))
 # Stretch the rear support, lifting the whole display while the base stays planted.
 for i in range(1,4):rig.pose.bones['support_%02d'%i].scale.y=1+.085*math.sin(t-.12*i)
 for i,name in enumerate(['large_eye','round_eye','mouth']):
  pb=rig.pose.bones['face_anchor_'+name];world=Vector((.045*math.sin(t-.4*i),0,.095*math.sin(t-.4*i+.5)));pb.location=pb.bone.matrix_local.to_3x3().inverted()@world
 rig['code_scroll']=(frame-1)/96
 rig.update_tag();bpy.context.view_layer.update()
animated=[pb.name for pb in rig.pose.bones if pb.name.startswith(('arm_','hand_ctrl','digit','support_','cable_'))]
for f in range(1,98,4):
 pose(f)
 for i in range(1,4):rig.pose.bones['support_%02d'%i].keyframe_insert('scale',frame=f,group='Display breathing')
 for name in ['large_eye','round_eye','mouth']:rig.pose.bones['face_anchor_'+name].keyframe_insert('location',frame=f,group='Floating face')
 rig.keyframe_insert(data_path='["code_scroll"]',frame=f,group='Code UV rise')
 for n in animated:rig.pose.bones[n].keyframe_insert('rotation_quaternion',frame=f,group=n)
 for side in ['L','R']:rig.keyframe_insert(data_path='["stretch_'+side+'"]',frame=f,group='Spring length')
for fc in act.fcurves:
 for k in fc.keyframe_points:k.interpolation='BEZIER';k.handle_left_type='AUTO_CLAMPED';k.handle_right_type='AUTO_CLAMPED'
 mod=fc.modifiers.new('CYCLES')
 if 'code_scroll' in fc.data_path:
  mod.mode_before='REPEAT_OFFSET';mod.mode_after='REPEAT_OFFSET'
  for k in fc.keyframe_points:k.interpolation='LINEAR'
s.frame_set(1);bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v010.blend'))
c=json.loads((B/'source/rig_contract_v008.json').read_text());c.update(version='v010',skeleton_id=rig['skeleton_id'],bone_count=len(arm.bones),skeleton_signature=signature,triangles=tri,grip='keyboard center grip; doubled hanging cable with downward plug',cable_bones=16);(B/'source/rig_contract_v010.json').write_text(json.dumps(c,indent=2),encoding='utf-8')

scene=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=scene;cam=scene.camera;scene.cycles.samples=12;scene.render.resolution_x=960;scene.render.resolution_y=800
cam.location=(3,12,4.4);cam.rotation_euler=(Vector((0,0,1.85))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=8.6
for f in [1,25,49,73]:
 scene.frame_set(f);scene.render.filepath=str(P/('pose_%03d.png'%f));bpy.ops.render.render(write_still=True)
