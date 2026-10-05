import bpy,math,json,sys
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/heavy_v016';P.mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v015.blend'))
for s in bpy.data.scenes:s['asset_version']='v016'
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v016.blend'))
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v015.blend'))
# Keyboard remains preserved in v015 with its preview; retain all three character Actions.
fx=bpy.data.collections.get('BOSS002_IMPACT_PREVIEW')
if fx:
 for ob in list(fx.objects):bpy.data.objects.remove(ob,do_unlink=True)
 bpy.data.collections.remove(fx)
s=bpy.data.scenes['BOSS002_SOURCE_TPOSE'];bpy.context.window.scene=s;rig=bpy.data.objects['Boss002_Rig'];arm=rig.data
rig.animation_data.action=bpy.data.actions['melee_keyboard'];s.frame_set(1)
base={p.name:(p.location.copy(),p.rotation_quaternion.copy(),p.scale.copy()) for p in rig.pose.bones}
neutral={side:rig.pose.bones['hand.'+side].matrix.copy() for side in ['L','R']}
stretch={side:rig['stretch_'+side] for side in ['L','R']}
act=bpy.data.actions.new('heavy_spin_slam');act.use_fake_user=True;act['duration_seconds']=3.2;act['impact_frame']=65;act['spin_turns']=3;act['hold_frames']=[49,55];rig.animation_data.action=act
def smooth(t):t=max(0,min(1,t));return t*t*(3-2*t)
def sample(keys,f):
 for a,b in zip(keys,keys[1:]):
  if f<=b[0]:return a[1]+(b[1]-a[1])*smooth((f-a[0])/(b[0]-a[0]))
 return keys[-1][1]
def chain(names,points):
 for n,a,b in zip(names,points,points[1:]):
  pb=rig.pose.bones[n];m=(b-a).to_track_quat('Y','Z').to_matrix().to_4x4();m.translation=a
  m=m@Matrix.Diagonal(Vector((1,(b-a).length/pb.bone.length,1,1)));pb.matrix=m;bpy.context.view_layer.update()
def support(target):
 start=Vector((0,-.08,.18));mid=Vector((0,-.75,.75));pts=[]
 for i in range(4):
  t=i/3;pts.append((1-t)**2*start+2*(1-t)*t*mid+t*t*target)
 chain(['support_%02d'%i for i in range(1,4)],pts)
 pb=rig.pose.bones['rear_axle'];m=arm.bones['rear_axle'].matrix_local.copy();m.translation=target;pb.matrix=m;bpy.context.view_layer.update()
def arm_curve(side,target):
 sign=1 if side=='L' else -1;root=rig.pose.bones['rear_axle'].matrix@arm.bones['rear_axle'].matrix_local.inverted();start=root@arm.bones['arm_01.'+side].head_local
 c1=start+Vector((sign*.9,-.5,.65));c2=target-neutral[side].to_3x3().col[1].normalized()*.55
 pts=[(1-t)**3*start+3*(1-t)**2*t*c1+3*(1-t)*t*t*c2+t**3*target for t in [i/120 for i in range(121)]];dist=[0]
 for a,b in zip(pts,pts[1:]):dist.append(dist[-1]+(b-a).length)
 nodes=[]
 for j in range(7):
  d=dist[-1]*j/6;i=next((i for i in range(120) if dist[i+1]>=d),119);nodes.append(pts[i].lerp(pts[i+1],(d-dist[i])/(dist[i+1]-dist[i])))
 rig['stretch_'+side]=sum((b-a).length for a,b in zip(nodes,nodes[1:]))/1.32;rig.update_tag();bpy.context.view_layer.update()
 chain(['arm_%02d.%s'%(i,side) for i in range(1,7)],nodes)
 pb=rig.pose.bones['hand_ctrl.'+side];m=neutral[side].copy();m.translation=target;pb.matrix=m;bpy.context.view_layer.update()
def min_z(name):
 ev=bpy.data.objects[name].evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh();z=min((ev.matrix_world@v.co).z for v in me.vertices);ev.to_mesh_clear();return z
for frame in range(1,98):
 f=frame-1
 for pb in rig.pose.bones:
  l,q,sc=base[pb.name];pb.location=l;pb.rotation_mode='QUATERNION';pb.rotation_quaternion=q;pb.scale=sc
 for side in ['L','R']:rig['stretch_'+side]=stretch[side]
 # Windup is low and wide. Spin axis never propagates into the rear axle/arms.
 z=sample([(0,2.02),(12,1.70),(18,2.12),(48,2.12),(54,2.12),(64,1.08),(68,1.02),(80,1.06),(88,2.26),(96,2.02)],f)
 y=sample([(0,-.52),(18,-.70),(48,-.70),(54,-.70),(64,1.65),(68,1.8),(80,1.8),(90,-.3),(96,-.52)],f)
 angle=sample([(0,0),(18,0),(48,0),(54,0),(64,-88),(68,-88),(80,-88),(88,10),(96,0)],f)
 turns=3*smooth((f-18)/30) if f<48 else 3
 if f<18:turns=0.0
 target=Vector((0,y,z));support(target)
 pb=rig.pose.bones['monitor_tilt'];pb.rotation_quaternion=Quaternion(pb.bone.matrix_local.to_3x3().inverted()@Vector((1,0,0)),math.radians(angle))
 rig.pose.bones['monitor_spin'].rotation_quaternion=Quaternion((math.cos(turns*math.pi),0,math.sin(turns*math.pi),0));bpy.context.view_layer.update()
 # Keep the rotating corners off the floor; then place the broad front on the floor.
 desired=.035 if 64<=f<=80 else .10
 for iteration in range(3):
  low=min_z('Portrait display')
  if low<desired or 64<=f<=80:
   target.z+=desired-low;support(target);bpy.context.view_layer.update()
 # The face follows the translating/tilting screen center, counteracting screen roll.
 unspun=rig.pose.bones['monitor_tilt'].matrix@arm.bones['monitor_tilt'].matrix_local.inverted()
 for name in ['large_eye','round_eye','mouth']:
  pb=rig.pose.bones['face_anchor_'+name];m=unspun@pb.bone.matrix_local;m.translation.z=max(m.translation.z,.60 if name=='mouth' else .92);pb.matrix=m;bpy.context.view_layer.update()
 spread=sample([(0,0),(18,1),(54,1),(64,1.15),(72,1),(80,1),(96,0)],f)
 for sign,side in [(1,'L'),(-1,'R')]:
  dest=Vector((sign*(2.35+.8*spread),-.15-.65*spread,1.95+.30*spread+.12*math.sin(f*.16-(0 if side=='L' else .7))*math.sin(math.pi*f/96)))
  if side=='R':dest.z+=.55*spread
  arm_curve(side,dest)
 for i in range(1,17):
  pb=rig.pose.bones['cable_%02d'%i];pb.rotation_quaternion=base[pb.name][1]@Quaternion((1,0,0),.012*math.sin(f*.16-i*.2)*math.sin(math.pi*f/96))
 blend=min(smooth(f/8),smooth((96-f)/10))
 if blend<1:
  for pb in rig.pose.bones:
   l,q,sc=base[pb.name];pb.location=l.lerp(pb.location,blend);pb.rotation_quaternion=q.slerp(pb.rotation_quaternion,blend);pb.scale=sc.lerp(pb.scale,blend)
  for side in ['L','R']:rig['stretch_'+side]=stretch[side]*(1-blend)+rig['stretch_'+side]*blend
 rig['expression_state']=4 if f<48 else 2 if f<80 else 0;rig['code_scroll']=f/48;rig['heavy_spin_turns']=turns
 for pb in rig.pose.bones:
  if pb.name=='root':continue
  for path in ['location','rotation_quaternion','scale']:pb.keyframe_insert(path,frame=frame,group=pb.name)
 for prop in ['stretch_L','stretch_R','expression_state','code_scroll','heavy_spin_turns']:rig.keyframe_insert(data_path='["'+prop+'"]',frame=frame)
for fc in act.fcurves:
 for k in fc.keyframe_points:k.interpolation='CONSTANT' if 'expression_state' in fc.data_path else 'LINEAR'
for sc in bpy.data.scenes:sc.frame_start=1;sc.frame_end=97;sc.render.fps=30;sc['asset_version']='v016'
s.frame_set(1);bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v016.blend'))
scene=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=scene;cam=scene.camera;cam.location=(5,12,6);cam.rotation_euler=(Vector((0,.3,1.8))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=10;scene.cycles.samples=8;scene.render.resolution_x=960;scene.render.resolution_y=800
if '--no-render' not in sys.argv:
 for f in [1,19,29,39,49,55,65,69,81,89,97]:
  scene.frame_set(f);scene.render.filepath=str(P/('pose_%03d.png'%f));bpy.ops.render.render(write_still=True)
