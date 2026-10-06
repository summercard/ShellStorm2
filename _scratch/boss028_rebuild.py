import bpy
r=bpy.data.objects['Boss002_Rig'];r.animation_data.action=None
for n in ['special_prepare','special_insert','special_channel','special_recover','hurt','stun_enter','stun_loop','stun_exit','turn_left','turn_right']:
 a=bpy.data.actions.get(n)
 if a:bpy.data.actions.remove(a)
 bpy.data.actions['ARCHIVE_'+n+'_v027'].name=n
import bpy,math,json,hashlib
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion
B=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/bosses/enm_boss_monitor002');P=B/'previews/arms_v028';P.mkdir(exist_ok=True)
r=bpy.data.objects['Boss002_Rig'];s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s
assert 'ARCHIVE_hurt_v027' not in bpy.data.actions,'v028 already applied; restore v027 before rebuild'
if bpy.context.screen.is_animation_playing:bpy.ops.screen.animation_cancel(restore_frame=False)
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_before_arms_v027.blend'),copy=True)
spec={'special_prepare':36,'special_insert':18,'special_channel':24,'special_recover':27,'hurt':15,'stun_enter':42,'stun_loop':48,'stun_exit':30,'turn_left':24,'turn_right':24}
preserve=['idle','move','melee_keyboard','melee_cable','heavy_spin_slam']
def digest(a):return hashlib.sha256(repr([(f.data_path,f.array_index,[tuple(k.co) for k in f.keyframe_points]) for f in a.fcurves]).encode()).hexdigest()
hashes={n:digest(bpy.data.actions[n]) for n in preserve}
def smooth(u):u=max(0,min(1,u));return u*u*(3-2*u)
def sample(keys,t):
 if t<=keys[0][0]:return keys[0][1]
 for (a,x),(b,y) in zip(keys,keys[1:]):
  if t<=b:return x+(y-x)*smooth((t-a)/(b-a))
 return keys[-1][1]
def gesture(kind,t,side,n):
 # Shoulder throws first; each spring segment samples an earlier phase.
 delay=n*1.05+(1.5 if side=='R' else 0);u=max(0,t-delay);end=spec[kind];env=smooth(t/2)*smooth((end-t)/5)
 sign=1 if side=='L' else -1
 if kind=='special_prepare':lift=sample([(0,0),(5,-15),(14,58),(23,25),(29,-12),(36,0)],u);yaw=sample([(0,0),(7,-26),(18,32),(27,-18),(36,0)],u)
 elif kind=='special_insert':lift=sample([(0,0),(5,43),(10,-15),(14,20),(18,0)],u);yaw=sample([(0,0),(5,-30),(11,25),(18,0)],u)
 elif kind=='special_recover':lift=sample([(0,0),(6,18),(13,53),(21,-12),(27,0)],u);yaw=sample([(0,0),(8,-18),(17,35),(27,0)],u)
 elif kind=='hurt':lift=sample([(0,0),(3,-18),(6,62),(10,-12),(15,0)],u);yaw=sample([(0,0),(4,-30),(8,30),(15,0)],u)
 elif kind=='stun_enter':lift=sample([(0,0),(4,-15),(9,65),(15,23),(19,-6),(24,66),(30,20),(36,-7),(42,0)],u);yaw=sample([(0,0),(8,-27),(16,32),(24,-26),(33,25),(42,0)],u)
 elif kind=='stun_exit':lift=sample([(0,0),(6,12),(13,56),(21,12),(26,-10),(30,0)],u);yaw=sample([(0,0),(7,-25),(17,30),(30,0)],u)
 elif kind.startswith('turn'):
  lift=sample([(0,0),(5,-12),(11,52),(17,22),(21,-10),(24,0)],u);yaw=sample([(0,0),(7,-40),(15,38),(24,0)],u)*(1 if kind=='turn_left' else -1)
 else:
  # Periodic loop: return exactly to unmodified boundary pose with zero velocity.
  phase=math.tau*t/end;wave=(1-math.cos(phase))*.5;lift=wave*(35+12*math.sin(phase-n*.32+(0 if side=='L' else .8)));yaw=wave*30*math.sin(phase-n*.35+(0 if side=='L' else .7));env=1
 if side=='R':lift*=.88;yaw*=-.85
 if kind.startswith('special') and side=='R':lift*=.65;yaw*=.65
 # Root-driven traveling curvature: successive tangents curl then unroll,
 # instead of rotating the complete arm as a rigid rod.
 waveenv=math.sin(math.pi*t/end)**2
 phase=math.tau*t/(end*.72)-n*.62+(0 if side=='L' else .65)
 curl=(34 if kind!='hurt' else 42)*math.sin(phase)*waveenv
 return lift*env+curl,yaw*env*sign+20*math.cos(phase+.4)*waveenv*sign

def extension(kind,t,side):
 end=spec[kind];u=t/end;env=math.sin(math.pi*u)**2
 phase=math.tau*u-(0 if side=='L' else .45)
 # Compression before the throw, then lengthening during uncoiling.
 return 1+env*(.25-.42*math.sin(phase+.35))
names={side:['arm_%02d.%s'%(i,side) for i in range(1,7)] for side in ['L','R']};cn=['cable_%02d'%i for i in range(1,17)];channels=sum(names.values(),[])+['hand_ctrl.L','hand_ctrl.R']+cn

def meshmin(name):
 o=bpy.data.objects[name].evaluated_get(bpy.context.evaluated_depsgraph_get());m=o.to_mesh();v=min((o.matrix_world@p.co).z for p in m.vertices);o.to_mesh_clear();return v

def place_chain(bones,points,mats):
 for n,a,b in zip(bones,points,points[1:]):
  old=mats[n];q=old.to_3x3().col[1].normalized().rotation_difference((b-a).normalized());m=q.to_matrix().to_4x4()@old;m.translation=a;m=m@Matrix.Diagonal((1,(b-a).length/old.to_3x3().col[1].length/r.data.bones[n].length,1,1));r.pose.bones[n].matrix=m;bpy.context.view_layer.update()

for kind,duration in spec.items():
 old=bpy.data.actions[kind];r.animation_data.action=old;cache={}
 for step in range(duration*4+1):
  f=1+step/4;s.frame_set(int(f),subframe=f-int(f));cache[step]={'mat':{p.name:p.matrix.copy() for p in r.pose.bones},'stretch':{side:r['stretch_'+side] for side in ['L','R']},'tail':{n:r.pose.bones[n].tail.copy() for n in sum(names.values(),[])+cn}}
 old.name='ARCHIVE_'+kind+'_v027';act=old.copy();act.name=kind;act.use_fake_user=True;act['arm_animation_revision']='root driven whip, traveling C/S curvature, 1.05f/segment lag, elastic length and wrist followthrough';r.animation_data.action=act
 for fc in list(act.fcurves):
  if any(fc.data_path.startswith('pose.bones["'+n+'"]') for n in channels):act.fcurves.remove(fc)
 previous={}
 for step,cachepose in cache.items():
  t=step/4;f=t+1;s.frame_set(int(f),subframe=f-int(f));mats=cachepose['mat'];tails=cachepose['tail'];axis=(mats['rear_axle']@r.data.bones['rear_axle'].matrix_local.inverted()).to_quaternion().to_matrix();axis_inv=axis.inverted()
  for side in ['L','R']:
   ns=names[side];extra=0;strength=1;factor=extension(kind,t,side)
   for attempt in range(24):
    r['stretch_'+side]=cachepose['stretch'][side]*factor;r.update_tag();bpy.context.view_layer.update()
    pts=[mats[ns[0]].translation.copy()]
    for i,n in enumerate(ns):
     lift,yaw=gesture(kind,t,side,i);lift=lift*strength+extra;yaw*=strength;sgn=1 if side=='L' else -1
     rot=axis@Matrix.Rotation(math.radians(yaw),3,'Z')@Matrix.Rotation(math.radians(-sgn*lift),3,'Y')@axis_inv
     d=tails[n]-mats[n].translation;pts.append(pts[-1]+(rot@d)*factor)
    place_chain(ns,pts,mats)
    dq=r.pose.bones[ns[-1]].matrix.to_quaternion()@mats[ns[-1]].to_quaternion().inverted();hm=dq.to_matrix().to_4x4()@mats['hand_ctrl.'+side];hm.translation=pts[-1]+dq@(mats['hand_ctrl.'+side].translation-tails[ns[-1]])
    wrist=gesture(kind,t,side,7)[0]-gesture(kind,t,side,3)[0];hm=hm@Matrix.Rotation(math.radians(wrist*.65),4,'Y');r.pose.bones['hand_ctrl.'+side].matrix=hm;bpy.context.view_layer.update()
    low=meshmin('Keyboard outer shell') if side=='L' else min(v.z for v in [r.pose.bones['hand.R'].head,r.pose.bones['hand.R'].tail])-.18
    start=r.pose.bones['hand.R'].matrix@mats['hand.R'].inverted()@mats[cn[0]].translation if side=='R' else Vector()
    reach=(start-mats[cn[-1]].translation).length if side=='R' else 0
    capacity=sum((tails[n]-mats[n].translation).length for n in cn[:15])
    if low>=.071 and reach<capacity*.995:break
    if low<.071:extra+=max(.025,math.degrees((.075-low)/max(.5,sum((tails[n]-mats[n].translation).length for n in ns)*factor))*.7)
    if reach>=capacity*.995:
     attenuation=max(.8,min(.999,capacity*.99/reach));strength*=attenuation;factor=1+(factor-1)*attenuation
   if side=='R':
    delta=r.pose.bones['hand.R'].matrix@mats['hand.R'].inverted();p=[delta@mats[n].translation for n in cn];target=mats[cn[-1]].translation.copy();start=p[0].copy();lens=[(tails[n]-mats[n].translation).length for n in cn[:15]]
    for i in range(1,15):p[i]+=(target-p[-1])*i/15;p[i].z=max(.22,p[i].z)
    for it in range(180):
     p[-1]=target
     for i in range(14,-1,-1):p[i]=p[i+1]+(p[i]-p[i+1]).normalized()*lens[i];p[i].z=max(.18,p[i].z)
     p[0]=start
     for i in range(15):
      d=p[i+1]-p[i];d.z=max(d.z,.18-p[i].z);p[i+1]=p[i]+d.normalized()*lens[i]
     if (p[-1]-target).length<1e-5:break
    place_chain(cn[:15],p,mats);r.pose.bones[cn[-1]].matrix=mats[cn[-1]];bpy.context.view_layer.update()
  for side in ['L','R']:r.keyframe_insert(data_path='["stretch_'+side+'"]',frame=f)
  for n in channels:
   pb=r.pose.bones[n]
   if n in previous and previous[n].dot(pb.rotation_quaternion)<0:pb.rotation_quaternion.negate()
   previous[n]=pb.rotation_quaternion.copy()
   for attr in ['location','rotation_quaternion','scale']:pb.keyframe_insert(attr,frame=f,group=n)
 for fc in act.fcurves:
  if any(fc.data_path.startswith('pose.bones["'+n+'"]') for n in channels):
   for k in fc.keyframe_points:k.interpolation='LINEAR'
 print('Finished arms',kind,flush=True)
assert all(digest(bpy.data.actions[n])==h for n,h in hashes.items())
for sc in bpy.data.scenes:sc['asset_version']='v028'
r.animation_data.action=bpy.data.actions['hurt'];s.frame_start=1;s.frame_end=16;s.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v028.blend'))
(P/'clips.json').write_text(json.dumps(spec,indent=2));(P/'preservation.json').write_text(json.dumps(hashes,indent=2));print('V028 COMPLETE')
