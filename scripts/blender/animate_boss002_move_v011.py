import bpy,math,json,hashlib
from pathlib import Path
from mathutils import Vector,Quaternion,Matrix
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/move_v011';P.mkdir(exist_ok=True)
# Reuse the authored grip and secondary-motion vocabulary, not the idle action.
source=(R/'scripts/blender/animate_boss002_idle_v010.py').read_text(encoding='utf-8');helpers=source[source.index('def axis('):source.index('animated=[')]
signatures=[]
for kind in ['model','animation']:
 bpy.ops.wm.open_mainfile(filepath=str(B/f'source/enm_boss_monitor002_{kind}_v010.blend'))
 s=bpy.data.scenes['BOSS002_SOURCE_TPOSE'];bpy.context.window.scene=s;rig=bpy.data.objects['Boss002_Rig'];arm=rig.data
 if rig.animation_data:rig.animation_data.action=None
 for pb in rig.pose.bones:pb.location=(0,0,0);pb.rotation_mode='QUATERNION';pb.rotation_quaternion=(1,0,0,0);pb.scale=(1,1,1)
 rig['stretch_L']=rig['stretch_R']=1.;rig['code_scroll']=0
 bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig;bpy.ops.object.mode_set(mode='EDIT')
 b=arm.edit_bones.new('pedestal_motion');b.head=(0,0,0);b.tail=(0,0,.18);b.parent=arm.edit_bones['root'];arm.edit_bones['support_01'].parent=b
 bpy.ops.object.mode_set(mode='OBJECT');arm.bones['pedestal_motion'].inherit_scale='NONE'
 for o in s.objects:
  if o.type=='MESH' and 'root' in o.vertex_groups:o.vertex_groups['root'].name='pedestal_motion'
 rig['skeleton_id']='SKEL-MONITOR002-005';arm.name=rig['skeleton_id'];s['skeleton_id']=rig['skeleton_id'];s['asset_version']='v011'
 sig=hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,list(b.head_local),list(b.tail_local),b.use_deform) for b in arm.bones],sort_keys=True).encode()).hexdigest();signatures.append(sig)
 if kind=='model':
  bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v011.blend'));continue
 # Keep the existing idle available on the upgraded rig.
 exec(helpers)
 idle=bpy.data.actions.get('idle');rig.animation_data.action=idle
 p=rig.pose.bones['pedestal_motion'];p.rotation_mode='QUATERNION'
 for f in [1,97]:
  for path in ['location','rotation_quaternion','scale']:p.keyframe_insert(path,frame=f,group='pedestal_motion')
 rig.animation_data_create();act=bpy.data.actions.new('move');act.use_fake_user=True;rig.animation_data.action=act
 act['duration_seconds']=1.6;act['description']='Heavy alternating pedestal edge steps; in-place root, 30fps, 1..48, closure49'
 base=[o for o in s.objects if o.type=='MESH' and 'pedestal_motion' in o.vertex_groups]
 baseverts=[o.matrix_world@v.co for o in base for v in o.data.vertices]
 for frame in range(1,50):
  t=(frame-1)/48*math.tau;pose(1+(frame-1)*2)
  # Strong support poses with a short settle near the extremes.
  sway=math.sin(t);roll=math.radians(23)*math.tanh(1.8*sway)/math.tanh(1.8)
  pb=rig.pose.bones['pedestal_motion'];pb.rotation_mode='QUATERNION';q=Quaternion((0,0,1),math.radians(11)*math.sin(t-.18))@Quaternion((0,1,0),roll);pb.rotation_quaternion=axis(pb,(0,0,1),math.radians(11)*math.sin(t-.18))@axis(pb,(0,1,0),roll)
  # Correct the exact rigid support geometry to the ground, every authored frame.
  height=.005-min((q@v).z for v in baseverts);world=Vector((.23*sway,.11*math.sin(2*t),height));pb.location=pb.bone.matrix_local.to_3x3().inverted()@world
  for i in range(1,4):
   p=rig.pose.bones['support_%02d'%i];p.rotation_quaternion=axis(p,(0,1,0),-.055*math.sin(t-.3*i))@axis(p,(1,0,0),-.035+.025*math.sin(2*t-.22*i));p.scale.y=1.0+.06*math.sin(2*t-.25*i)
  # Arms lag sideways with the weight transfer but hands counter-rotate to retain
  # the held keyboard and hanging cable's gravity orientation.
  for sign,side in [(1,'L'),(-1,'R')]:
   phase=t+(0 if side=='L' else .45);angles=[-.56,-.12,.22,.34,.31,.18]
   for i,a in enumerate(angles):
    p=rig.pose.bones['arm_%02d.%s'%(i+1,side)];p.rotation_quaternion=axis(p,(0,1,0),sign*(a+.075*math.sin(phase-i*.28)))
   rig['stretch_'+side]=.96+.07*math.sin(phase-.4)
   p=rig.pose.bones['hand_ctrl.'+side];comp=sum(angles)+sum(.075*math.sin(phase-j*.28) for j in range(6))-.06
   p.rotation_quaternion=axis(p,(0,1,0),-sign*comp-roll+.055*sum(math.sin(t-.3*i) for i in range(1,4)))@axis(p,(0,0,1),math.radians(62 if side=='L' else 18))
  rig['code_scroll']=(frame-1)/48
  for p in rig.pose.bones:
   if p.name=='root' or p.name.startswith(('face_','hand.','prop_','monitor_','rear_')) and not p.name.startswith('face_anchor_'):continue
   for path in ['location','rotation_quaternion','scale']:p.keyframe_insert(path,frame=frame,group=p.name)
  for prop in ['stretch_L','stretch_R','code_scroll']:rig.keyframe_insert(data_path='["'+prop+'"]',frame=frame,group='Animated properties')
 for fc in act.fcurves:
  for k in fc.keyframe_points:k.interpolation='LINEAR'
  mod=fc.modifiers.new('CYCLES')
  if 'code_scroll' in fc.data_path:mod.mode_before='REPEAT_OFFSET';mod.mode_after='REPEAT_OFFSET'
 for sc in bpy.data.scenes:sc.render.fps=30;sc.frame_start=1;sc.frame_end=48
 s.frame_set(1);bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v011.blend'))
assert len(set(signatures))==1
c=json.loads((B/'source/rig_contract_v010.json').read_text());c.update(version='v011',skeleton_id=rig['skeleton_id'],skeleton_signature=sig,bone_count=len(arm.bones),formal_animations_authored=['idle','move'],move={'fps':30,'start':1,'end':48,'closure':49,'duration_seconds':1.6,'root_motion':False,'pedestal_roll_degrees':23,'pedestal_lateral_range':.46});(B/'source/rig_contract_v011.json').write_text(json.dumps(c,indent=2),encoding='utf-8')
scene=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=scene;cam=scene.camera;cam.location=(3,12,4.4);cam.rotation_euler=(Vector((0,0,1.9))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=9.4;scene.cycles.samples=12;scene.render.resolution_x=960;scene.render.resolution_y=800
for f in [1,13,25,37]:
 scene.frame_set(f);scene.render.filepath=str(P/('pose_%03d.png'%f));bpy.ops.render.render(write_still=True)
