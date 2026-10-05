import bpy,math,json,hashlib
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion
R=Path.cwd();B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/remaining_v026';P.mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v025.blend'))
for sc in bpy.data.scenes:sc['asset_version']='v026'
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v026.blend'))
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v025.blend'))
s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s
for c in list(s.collection.children):
 if c.name.startswith('BOSS002_CABLE_PREVIEW'):s.collection.children.unlink(c)
rig=bpy.data.objects['Boss002_Rig'];arm=rig.data;rig.animation_data.action=bpy.data.actions['melee_cable'];s.frame_set(1)
def hashes():return {a.name:hashlib.sha256(repr([(fc.data_path,fc.array_index,[tuple(k.co) for k in fc.keyframe_points]) for fc in a.fcurves]).encode()).hexdigest() for a in bpy.data.actions if a.name in ['idle','move','melee_keyboard','melee_cable','heavy_spin_slam']}
old=hashes()
base={p.name:(p.location.copy(),p.rotation_quaternion.copy(),p.scale.copy()) for p in rig.pose.bones};neutral={side:rig.pose.bones['hand.'+side].matrix.copy() for side in ['L','R']};stretch={side:rig['stretch_'+side] for side in ['L','R']}
support_base=[rig.pose.bones['support_%02d'%i].matrix.copy() for i in range(1,4)];support_points=[rig.pose.bones['support_%02d'%i].head.copy() for i in range(1,4)]+[rig.pose.bones['support_03'].tail.copy()];axle_base=rig.pose.bones['rear_axle'].matrix.copy()
arm_base={side:[rig.pose.bones['arm_%02d.%s'%(i,side)].matrix.copy() for i in range(1,7)] for side in ['L','R']};arm_dirs={side:[(rig.pose.bones['arm_%02d.%s'%(i,side)].tail-rig.pose.bones['arm_%02d.%s'%(i,side)].head).normalized() for i in range(1,7)] for side in ['L','R']};arm_lengths={side:[(rig.pose.bones['arm_%02d.%s'%(i,side)].tail-rig.pose.bones['arm_%02d.%s'%(i,side)].head).length for i in range(1,7)] for side in ['L','R']}
cn=['cable_%02d'%i for i in range(1,17)];lengths=[arm.bones[n].length for n in cn];attach=neutral['R'].inverted()@rig.pose.bones[cn[0]].head;rest_dirs=[neutral['R'].to_3x3().inverted()@(rig.pose.bones[n].tail-rig.pose.bones[n].head).normalized() for n in cn];cable_last=rig.pose.bones['cable_16'].matrix.copy()
plug=bpy.data.objects['Luminous data plug'];ev=plug.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh();vs=[ev.matrix_world@v.co for v in me.vertices];z=min(v.z for v in vs);tip=sum((v for v in vs if v.z<z+.02),Vector())/len([v for v in vs if v.z<z+.02]);ev.to_mesh_clear();tip_local=cable_last.inverted()@tip
base_objects=[o for o in s.objects if o.type=='MESH' and 'pedestal_motion' in o.vertex_groups];baseverts=[o.matrix_world@v.co for o in base_objects for v in o.data.vertices]
helpers=(R/'scripts/blender/animate_boss002_heavy_v017.py').read_text(encoding='utf-8');exec(helpers[helpers.index('def smooth('):helpers.index('def wrist_pose(')])
def stable_support(target):
 delta=target-axle_base.translation;pts=[p+delta*(i/3) for i,p in enumerate(support_points)]
 for i in range(3):
  pb=rig.pose.bones['support_%02d'%(i+1)];m=(support_points[i+1]-support_points[i]).rotation_difference(pts[i+1]-pts[i]).to_matrix().to_4x4()@support_base[i];m.translation=pts[i];pb.matrix=m;bpy.context.view_layer.update()
def mesh_min(name):
 o=bpy.data.objects[name].evaluated_get(bpy.context.evaluated_depsgraph_get());me=o.to_mesh();z=min((o.matrix_world@v.co).z for v in me.vertices);o.to_mesh_clear();return z

def arm_fk(side,yaw,lift,drag=0):
 sign=1 if side=='L' else -1;points=[root_motion@arm_base[side][0].translation]
 for i in range(6):
  rot=Matrix.Rotation(math.radians(yaw+drag*i/5),3,'Z')@Matrix.Rotation(math.radians(-sign*lift),3,'Y');d=root_motion.to_3x3()@rot@arm_dirs[side][i];points.append(points[-1]+d*arm_lengths[side][i])
 rig['stretch_'+side]=stretch[side];rig.update_tag();bpy.context.view_layer.update();chain(['arm_%02d.%s'%(i,side) for i in range(1,7)],points);hm=rig.pose.bones['arm_06.'+side].matrix@arm_base[side][-1].inverted()@neutral[side];hm=hm@Matrix.Rotation(math.radians(drag*.45),4,'Y');rig.pose.bones['hand_ctrl.'+side].matrix=hm;bpy.context.view_layer.update()

def cable_pose(weight,endpoint,wave):
 hand=rig.pose.bones['hand.R'].matrix;start=hand@attach;points=[start.copy()]
 for i,d in enumerate(rest_dirs):
  v=hand.to_3x3()@d
  if points[-1].z+v.z*lengths[i]<.20:v.z=abs(v.z)
  points.append(points[-1]+v.normalized()*lengths[i])
 if weight<=0:chain(cn,points);return
 # End orientation points down; exact tip endpoint, with the first 15 joints solving the slack.
 down=Vector((0,0,-1));q=(cable_last.to_3x3().col[1]).rotation_difference(down);endmat=q.to_matrix().to_4x4()@cable_last;endmat.translation=endpoint-endmat.to_3x3()@tip_local
 neutral_last=(points[-1]-points[-2]).to_track_quat('Y','Z').to_matrix().to_4x4();neutral_last.translation=points[-2]
 targetmat=neutral_last.lerp(endmat,weight);target=targetmat.translation.copy();p=points[:16]
 for i in range(1,15):
  u=i/15;p[i]=start.lerp(target,u)+Vector((wave*math.sin(math.pi*u),.65*math.sin(math.pi*u),1.1*math.sin(math.pi*u)))
 for it in range(250):
  p[-1]=target
  for i in range(14,-1,-1):
   p[i]=p[i+1]+(p[i]-p[i+1]).normalized()*lengths[i];p[i].z=max(.28,p[i].z)
  p[0]=start
  for i in range(15):
   d=p[i+1]-p[i];d.z=max(d.z,.28-p[i].z);p[i+1]=p[i]+d.normalized()*lengths[i]
  if (p[-1]-target).length<1e-5:break
 chain(cn[:15],p);pb=rig.pose.bones['cable_16'];pb.matrix=targetmat;bpy.context.view_layer.update()

def params(kind,t):
 # dy,dz,pitch,yaw, left yaw/lift, right yaw/lift, special reach, plug height, expression
 v=[0,0,0,0,0,0,0,0,0,1.0,0];phase=0
 if kind.startswith('special'):
  if kind=='special_prepare':u=smooth(t/28);v=[.05*u,-.08*u,-9*u,2*math.sin(t*.32)*math.sin(math.pi*t/36),-12*u,12*u,-50*u,18*u,u,1.05,1]
  elif kind=='special_insert':u=smooth((t-6)/8);v=[.05+.08*u,-.08-.10*u,-9-5*u,0,-12,12,-50,18-8*u,1,1.05*(1-u)+.05*u,2]
  elif kind=='special_channel':u=math.sin(math.tau*t/24);v=[.13,-.18,-14+.7*u,0,-12,12,-50,10+.8*u,1,.05,5];phase=.1*math.sin(math.tau*t/12)
  else:
   lift=smooth((t-8)/6);u=smooth((t-14)/13);v=[.13*(1-u),-.18*(1-u),-14*(1-u),0,-12*(1-u),12*(1-u),-50*(1-u),10*(1-u),1-u,.05+1*lift,5 if t<8 else 0]
 elif kind=='hurt':
  a=sample([(0,0),(3,1),(5,1),(10,-.25),(15,0)],t);lag=sample([(0,0),(5,1),(7,.8),(12,-.2),(15,0)],t);v=[-.12*a,-.035*a,9*a,0,-8*lag,7*lag,10*lag,8*lag,0,1,2 if t<10 else 0]
 elif kind.startswith('stun'):
  if kind=='stun_enter':u=smooth((t-5)/13);w=0
  elif kind=='stun_loop':u=1;w=math.sin(math.tau*t/48)
  else:u=1-smooth((t-8)/19);w=0
  v=[-.85*u,-.95*u,25*u+w,1.5*w,-12*u,-20*u,-8*u,-18*u,0,1,3 if kind!='stun_enter' or t>18 else 5]
 elif kind.startswith('turn'):
  sign=1 if kind=='turn_left' else -1
  angle=sample([(0,0),(6,-5*sign),(12,42*sign),(15,42*sign),(21,90*sign),(24,90*sign)],t)
  v=[0,-.045*math.sin(math.pi*t/24),0,angle,sign*sample([(0,0),(10,12),(18,-8),(24,0)],t),5*math.sin(math.pi*t/24),sign*sample([(0,0),(12,20),(20,-9),(24,0)],t),7*math.sin(math.pi*t/24),0,1,1]
 return v,phase
spec={'special_prepare':36,'special_insert':18,'special_channel':24,'special_recover':27,'hurt':15,'stun_enter':24,'stun_loop':48,'stun_exit':30,'turn_left':24,'turn_right':24}
# Ground contact gets solved in pose space before shoulder FK, so arms follow the corrected body.
for kind,duration in spec.items():
 act=bpy.data.actions.new(kind);act.use_fake_user=True;act['duration_seconds']=duration/30;act['loop']=kind in ['stun_loop','special_channel'];rig.animation_data.action=act;prev={}
 for step in range(duration*4+1):
  t=step/4
  for pb in rig.pose.bones:
   l,q,sc=base[pb.name];pb.location=l;pb.rotation_mode='QUATERNION';pb.rotation_quaternion=q;pb.scale=sc
  v,wave=params(kind,t);dy,dz,pitch,yaw,ly,ll,ry,rl,reach,height,expression=v
  target=axle_base.translation+Vector((0,dy,dz));rotation=Matrix.Rotation(math.radians(yaw),4,'Z')
  turn=kind.startswith('turn');ped=rig.pose.bones['pedestal_motion']
  if turn:
   roll=math.radians(8*math.sin(math.pi*t/12))*(1 if kind=='turn_left' else -1);pm=rotation@Matrix.Rotation(roll,4,'Y');pm.translation.z=.005-min((pm@p).z for p in baseverts);ped.matrix=pm@ped.bone.matrix_local;bpy.context.view_layer.update()
  stable_support(target)
  root_motion=Matrix.Translation(target)@rotation@Matrix.Translation(-axle_base.translation);rig.pose.bones['rear_axle'].matrix=root_motion@axle_base;bpy.context.view_layer.update()
  pb=rig.pose.bones['monitor_tilt'];basis=pb.bone.matrix_local.to_quaternion();pb.rotation_quaternion=basis.inverted()@Quaternion((1,0,0),math.radians(pitch))@basis;bpy.context.view_layer.update()
  if kind.startswith('stun'):
   low=mesh_min('Portrait display');amount=.04-low
   # Only seated states need exact ground placement; enter/exit transition uses the crouch envelope.
   u=smooth((t-5)/13) if kind=='stun_enter' else 1 if kind=='stun_loop' else 1-smooth((t-8)/19)
   if low<.04 or u>.999:
    target.z+=amount;stable_support(target);root_motion=Matrix.Translation(target)@rotation@Matrix.Translation(-axle_base.translation);rig.pose.bones['rear_axle'].matrix=root_motion@axle_base;bpy.context.view_layer.update()
  for name in ['large_eye','round_eye','mouth']:
   pb=rig.pose.bones['face_anchor_'+name];pb.matrix=rig.pose.bones['monitor_tilt'].matrix@arm.bones['monitor_tilt'].matrix_local.inverted()@pb.bone.matrix_local
  # Shoulder-led overlap: broad forward/back swing with distal and wrist delay.
  envelope=math.sin(math.pi*t/duration)**2
  if kind=='special_channel':leftdrag=8*math.sin(math.tau*t/duration);rightdrag=4*math.sin(math.tau*t/duration)
  elif kind=='stun_loop':leftdrag=7*math.sin(math.tau*t/duration);rightdrag=9*math.sin(math.tau*t/duration)
  else:leftdrag=18*envelope*math.sin(math.tau*t/duration);rightdrag=-22*envelope*math.sin(math.tau*t/duration)
  if kind=='hurt':leftdrag*=1.4;rightdrag*=1.4
  ly+=leftdrag*.65;ry+=rightdrag*.65
  arm_fk('L',ly,ll,leftdrag);arm_fk('R',ry,rl,rightdrag)
  for side,obj in [('L','Keyboard outer shell'),('R','Luminous data plug')]:
   if side=='L':
    for it in range(12):
     if mesh_min(obj)>.05:break
     ll+=4;arm_fk(side,ly,ll)
  endpoint=Vector((-1.5,2.2,height))
  if kind.startswith('stun'):
   reach=u;endpoint=Vector((-2.7,-.25,.12))
  cable_pose(reach,endpoint,wave)
  # Rotate the face orientation only for actual heading turns.
  if turn:
   for name in ['large_eye','round_eye','mouth']:
    pb=rig.pose.bones['face_'+name]
    for con in pb.constraints:
     if con.type=='COPY_ROTATION':con.influence=0;con.keyframe_insert('influence',frame=t+1)
    pb.rotation_quaternion=pb.bone.matrix_local.to_quaternion().inverted()@rotation.to_quaternion()@pb.bone.matrix_local.to_quaternion()
  else:
   for pb in rig.pose.bones:
    for con in pb.constraints:
     if con.type=='COPY_ROTATION':con.influence=1;con.keyframe_insert('influence',frame=t+1)
  rig['expression_state']=expression;rig['code_scroll']=t/24
  for pb in rig.pose.bones:
   if pb.name=='root':continue
   if pb.name in prev and prev[pb.name].dot(pb.rotation_quaternion)<0:pb.rotation_quaternion.negate()
   prev[pb.name]=pb.rotation_quaternion.copy()
   for path in ['location','rotation_quaternion','scale']:pb.keyframe_insert(path,frame=t+1,group=pb.name)
  for prop in ['stretch_L','stretch_R','expression_state','code_scroll']:rig.keyframe_insert(data_path='["'+prop+'"]',frame=t+1)
 for fc in act.fcurves:
  for k in fc.keyframe_points:k.interpolation='CONSTANT' if 'expression_state' in fc.data_path or 'influence' in fc.data_path else 'LINEAR'
assert hashes()==old
for sc in bpy.data.scenes:sc['asset_version']='v026'
s.camera.location=(5,12,6);s.camera.rotation_euler=(Vector((0,.4,1.7))-s.camera.location).to_track_quat('-Z','Y').to_euler();s.camera.data.ortho_scale=10.5;s.render.fps=30;s.frame_start=1;s.frame_end=37;rig.animation_data.action=bpy.data.actions['special_prepare'];s.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v026.blend'))
(P/'clips.json').write_text(json.dumps(spec,indent=2));(P/'old_actions.json').write_text(json.dumps({'unchanged':old,'tip_local':list(tip_local)},indent=2))
s.cycles.samples=8;s.render.resolution_x=800;s.render.resolution_y=660
for kind,duration in spec.items():
 rig.animation_data.action=bpy.data.actions[kind];s.frame_set(1+duration//2);s.render.filepath=str(P/(kind+'.png'));bpy.ops.render.render(write_still=True)
