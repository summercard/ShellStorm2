import bpy,math,json,hashlib
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion
B=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/bosses/enm_boss_monitor002');P=B/'previews/seated_hands_v029';P.mkdir(exist_ok=True);s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s;r=bpy.data.objects['Boss002_Rig']
assert 'ARCHIVE_stun_loop_v028' not in bpy.data.actions,'Already applied; restore v028 before rebuilding'
bpy.ops.wm.save_as_mainfile(filepath='I:/工作项目/shellstrom2/ShellStorm2/_scratch/boss029_before.blend',copy=True)
spec={'stun_enter':42,'stun_loop':48,'stun_exit':30};allnames=['idle','move','melee_keyboard','melee_cable','heavy_spin_slam','special_prepare','special_insert','special_channel','special_recover','hurt','turn_left','turn_right']
def digest(a):return hashlib.sha256(repr([(f.data_path,f.array_index,[tuple(k.co) for k in f.keyframe_points]) for f in a.fcurves]).encode()).hexdigest()
hashes={n:digest(bpy.data.actions[n]) for n in allnames};channels=[p.name for p in r.pose.bones if p.name.startswith(('arm_','hand_ctrl.','digit','cable_','prop_socket.'))];cn=['cable_%02d'%i for i in range(1,17)]
def smooth(u):u=max(0,min(1,u));return u*u*(3-2*u)
def verts(name):
 o=bpy.data.objects[name].evaluated_get(bpy.context.evaluated_depsgraph_get());m=o.to_mesh();v=[o.matrix_world@p.co for p in m.vertices];o.to_mesh_clear();return v

def chain(ns,points,mats):
 for n,a,b in zip(ns,points,points[1:]):
  old=mats[n];q=old.to_3x3().col[1].normalized().rotation_difference((b-a).normalized());m=q.to_matrix().to_4x4()@old;m.translation=a;m=m@Matrix.Diagonal((1,(b-a).length/old.to_3x3().col[1].length/r.data.bones[n].length,1,1));r.pose.bones[n].matrix=m;bpy.context.view_layer.update()
# Flat rest hands with fully relaxed fingers. Determine actual mesh contact height.
r.animation_data.action=None;floorz={};handq={}
for side in ['L','R']:
 sign=1 if side=='L' else -1;rot=Matrix.Rotation(math.radians(-sign*12),4,'Z');handq[side]=(rot@r.data.bones['hand.'+side].matrix_local).to_quaternion()
 for p in r.pose.bones:
  if p.name.startswith('digit') and p.name.endswith('.'+side):p.location=Vector();p.rotation_quaternion=Quaternion();p.scale=Vector((1,1,1))
 hm=handq[side].to_matrix().to_4x4();hm.translation=Vector((sign*2.4,0,0));r.pose.bones['hand_ctrl.'+side].matrix=hm;bpy.context.view_layer.update();floorz[side]=.014-min(v.z for v in verts('Sculpted glove '+side))
for kind,duration in spec.items():
 old=bpy.data.actions[kind];r.animation_data.action=old;cache={}
 for step in range(duration*4+1):
  f=1+step/4;s.frame_set(int(f),subframe=f-int(f));cache[step]={'local':{p.name:(p.location.copy(),p.rotation_quaternion.copy(),p.scale.copy()) for p in r.pose.bones},'mat':{p.name:p.matrix.copy() for p in r.pose.bones},'tail':{p.name:p.tail.copy() for p in r.pose.bones},'digit':{p.name:p.rotation_quaternion.copy() for p in r.pose.bones if p.name.startswith('digit')},'stretch':{side:r['stretch_'+side] for side in ['L','R']}}
 old.name='ARCHIVE_'+kind+'_v028';act=old.copy();act.name=kind;act.use_fake_user=True;r.animation_data.action=act
 for fc in list(act.fcurves):
  if any(fc.data_path.startswith('pose.bones["'+n+'"]') for n in channels):act.fcurves.remove(fc)
 prev={}
 for step,c in cache.items():
  t=step/4;f=t+1;s.frame_set(int(f),subframe=f-int(f));w=smooth((f-25)/10) if kind=='stun_enter' else 1 if kind=='stun_loop' else 1-smooth((f-8)/17);mats=c['mat']
  for n in channels:
   pb=r.pose.bones[n];pb.location,pb.rotation_quaternion,pb.scale=c['local'][n]
  bpy.context.view_layer.update()
  for side in ['L','R']:
   sign=1 if side=='L' else -1;ns=['arm_%02d.%s'%(i,side) for i in range(1,7)];root=mats[ns[0]].translation.copy();dirs=[]
   for deg in [-56,-62,-46,-23,-7,0]:
    a=math.radians(deg);dirs.append(Vector((sign*math.cos(a),.18,math.sin(a))).normalized())
   lengths=[r.data.bones[n].length for n in ns];targetfactor=(floorz[side]-root.z)/sum(d.z*l for d,l in zip(dirs,lengths));factor=c['stretch'][side]*(1-w)+targetfactor*w;r['stretch_'+side]=factor;r.update_tag();bpy.context.view_layer.update();pts=[root]
   for n,d,l in zip(ns,dirs,lengths):
    olddir=(c['tail'][n]-mats[n].translation).normalized();direction=olddir.lerp(d,w).normalized();pts.append(pts[-1]+direction*l*factor)
   chain(ns,pts,mats)
   q=mats['hand_ctrl.'+side].to_quaternion().slerp(handq[side],w);hm=q.to_matrix().to_4x4();hm.translation=pts[-1];r.pose.bones['hand_ctrl.'+side].matrix=hm
   for n,q0 in c['digit'].items():
    if n.endswith('.'+side):r.pose.bones[n].rotation_quaternion=q0.slerp(Quaternion(),w)
   bpy.context.view_layer.update()
  # Keyboard relaxes flat beside the open left palm, then is picked up on recovery.
  target=Matrix.Rotation(math.pi/2,4,'X')@r.data.bones['prop_socket.L'].matrix_local;target.translation=Vector((0,0,0));r.pose.bones['prop_socket.L'].matrix=target;bpy.context.view_layer.update();vv=verts('Keyboard outer shell');
  import numpy as np
  aa=np.array([list(v) for v in vv]);_,vectors=np.linalg.eigh(np.cov(aa.T));normal=Vector(vectors[:,0]);normal=-normal if normal.z<0 else normal;target=normal.rotation_difference(Vector((0,0,1))).to_matrix().to_4x4()@target;r.pose.bones['prop_socket.L'].matrix=target;bpy.context.view_layer.update();vv=verts('Keyboard outer shell');center=sum(vv,Vector())/len(vv);dest=r.pose.bones['hand.L'].matrix.translation+Vector((.1,.85,0));target.translation+=Vector((dest.x-center.x,dest.y-center.y,.025-min(v.z for v in vv)));r.pose.bones['prop_socket.L'].matrix=mats['prop_socket.L'].lerp(target,w);bpy.context.view_layer.update()
  # Slack data cable settles into a low floor loop attached to the opened right hand.
  start=r.pose.bones['hand.R'].matrix@mats['hand.R'].inverted()@mats['cable_01'].translation;points=[start];flat=[start.copy()]
  for i,n in enumerate(cn):
   angle=math.radians(135+i*16);d=Vector((math.cos(angle),math.sin(angle),0));zgoal=.18
   d.z=max(-.55,min(.55,(zgoal-flat[-1].z)/r.data.bones[n].length));flat.append(flat[-1]+d.normalized()*r.data.bones[n].length)
   oldd=(c['tail'][n]-mats[n].translation).normalized();d=oldd.lerp(d,w).normalized();d.z=max(d.z,(.24-points[-1].z)/r.data.bones[n].length) if i<15 else max(d.z,(.5-points[-1].z)/r.data.bones[n].length);points.append(points[-1]+d.normalized()*r.data.bones[n].length)
  chain(cn,points,mats)
  for n in channels:
   pb=r.pose.bones[n]
   if n in prev and prev[n].dot(pb.rotation_quaternion)<0:pb.rotation_quaternion.negate()
   prev[n]=pb.rotation_quaternion.copy()
   for attr in ['location','rotation_quaternion','scale']:pb.keyframe_insert(attr,frame=f,group=n)
  for side in ['L','R']:r.keyframe_insert(data_path='["stretch_'+side+'"]',frame=f)
 for fc in act.fcurves:
  if any(fc.data_path.startswith('pose.bones["'+n+'"]') for n in channels) or 'stretch_' in fc.data_path:
   for k in fc.keyframe_points:k.interpolation='LINEAR'
 print('Done',kind,flush=True)
assert all(digest(bpy.data.actions[n])==h for n,h in hashes.items())
for sc in bpy.data.scenes:sc['asset_version']='v029'
r.animation_data.action=bpy.data.actions['stun_loop'];s.frame_start=1;s.frame_end=49;s.frame_set(1);bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v029.blend'))
(P/'clips.json').write_text(json.dumps(spec,indent=2));(P/'preservation.json').write_text(json.dumps(hashes,indent=2));(P/'contact_height.json').write_text(json.dumps(floorz));print('V029 COMPLETE')
