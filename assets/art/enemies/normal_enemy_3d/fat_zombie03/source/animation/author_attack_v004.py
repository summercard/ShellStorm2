import bpy, math, json, hashlib, shutil
from pathlib import Path
from mathutils import Vector, Quaternion, Matrix
pkg=Path(__file__).resolve().parents[2]; project=pkg.parents[4]
qa=pkg/'previews/attack_v004';qa.mkdir(parents=True,exist_ok=True)
model=pkg/'source/animation/enm_normal_fat_zombie03_animation_v003.blend'
output=Path(__file__).parent/'enm_normal_fat_zombie03_animation_v004.blend'
glb=pkg/'components/enm_normal_fat_zombie03_visual_top3d.glb'
backup=project/'_scratch/fat_zombie03/attack_v004_backup';backup.mkdir(parents=True,exist_ok=True)
if not (backup/glb.name).exists():shutil.copy2(glb,backup/glb.name)
bpy.ops.wm.open_mainfile(filepath=str(model))
a=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');m=next(o for o in bpy.context.scene.objects if o.type=='MESH');s=bpy.context.scene
rest={b.name:b.matrix_local.copy() for b in a.data.bones};heads={b.name:b.head_local.copy() for b in a.data.bones};tails={b.name:b.tail_local.copy() for b in a.data.bones}
def sig():return hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,[round(x,6) for row in b.matrix_local for x in row]) for b in a.data.bones]).encode()).hexdigest()
original_sig=sig(); original_geo=hashlib.sha256(json.dumps([[list(v.co),[(g.group,g.weight) for g in v.groups]] for v in m.data.vertices]).encode()).hexdigest()
assert set(bpy.data.actions.keys())=={'idle','walking','running'}
for pb in a.pose.bones:pb.matrix_basis=Matrix.Identity(4)
def rx(deg):return Quaternion((1,0,0),math.radians(deg))
def ry(deg):return Quaternion((0,1,0),math.radians(deg))
def aim(n,d):return (tails[n]-heads[n]).normalized().rotation_difference(Vector(d).normalized())
def curve(f,keys):
 f=f%96
 for (fa,va),(fb,vb) in zip(keys,keys[1:]):
  if f<=fb:
   t=(f-fa)/(fb-fa);u=t*t*t*(t*(t*6-15)+10);return va+(vb-va)*u
 return keys[-1][1]
foot_ids={}
for side in ['L','R']:
 ids={g.index for g in m.vertex_groups if g.name in [side+'_Foot',side+'_ToeBase',side+'_Toe_End']}
 foot_ids[side]=[v.index for v in m.data.vertices if v.co.z<.25 and sum(g.weight for g in v.groups if g.group in ids)>.45]
 assert len(foot_ids[side])>10
def eval_points():
 a.update_tag();bpy.context.view_layer.update();ev=m.evaluated_get(bpy.context.evaluated_depsgraph_get());em=ev.to_mesh();pts=[v.co.copy() for v in em.vertices];ev.to_mesh_clear();return pts
def apply(Q,hip):
 for pb in a.pose.bones:
  n=pb.name;par=pb.parent.name if pb.parent else None;pb.rotation_mode='QUATERNION'
  pb.rotation_quaternion=rest[n].to_quaternion().inverted()@(Q[par].inverted() if par else Quaternion())@Q[n]@rest[n].to_quaternion()
  pb.location=(0,0,0);pb.scale=(1,1,1)
 a.pose.bones['Hip'].location=rest['Hip'].to_3x3().inverted()@(hip-heads['Hip']);a.update_tag();bpy.context.view_layer.update()
def solve(f, walking=False, running=False):
 attack_frame=f;f=0
 breath=curve(f,[(0,0),(24,1),(48,0),(96,0)])
 sway=curve(f,[(0,0),(24,0),(48,.02/.7),(72,-.02/.7),(96,0)])
 hip=heads['Hip']+Vector((sway,0,-.065+breath*.015/.7))
 Q={n:Quaternion() for n in rest};Q['Hip']=ry(-.6*sway/(.02/.7));Q['Waist']=rx(-3);Q['Spine01']=rx(-5);Q['Spine02']=rx(-8+.45*breath);Q['Neck']=rx(-5);Q['Head']=rx(-5-.35*breath);Q['HeadTop_End']=Q['Head']
 for side,sign in [('L',-1),('R',1)]:
  lag=curve(f-2,[(0,0),(24,0),(48,1),(72,-1),(96,0)])
  Q[side+'_Clavicle']=Q['Spine02']@ry(sign*.55*lag)
  Q[side+'_Upperarm']=aim(side+'_Upperarm',(sign*.32,.03,-.95))@ry(sign*.5*lag)
  Q[side+'_Forearm']=aim(side+'_Forearm',(sign*.22,.30,-.93))
  Q[side+'_Hand']=Q[side+'_Forearm'].copy()
  for b in a.data.bones:
   n=b.name
   if n.startswith(side+'_') and any(z in n for z in ['Thumb','Index','Middle','Pinky','Ring']):
    parent=b.parent.name;Q[n]=Q.get(parent,Q[side+'_Hand'])
 targets={side:heads[side+'_Foot'].copy() for side in ['L','R']}
 lifts={'L':0.,'R':0.}
 def value(keys):
  for (fa,va),(fb,vb) in zip(keys,keys[1:]):
   if attack_frame<=fb:
    t=max(0,min(1,(attack_frame-fa)/(fb-fa)));u=t*t*(3-2*t);return va+(vb-va)*u
  return keys[-1][1]
 opened=value([(0,0),(12,.45),(26,1),(30,1),(36,0),(54,0),(69,0),(75,0)])
 closed=value([(0,0),(30,0),(36,1),(38,1),(44,1),(54,1),(69,.15),(75,0)])
 crouch=value([(0,0),(12,.05),(26,.10),(30,.10),(36,.12),(38,.12),(44,.15),(54,.15),(69,.02),(75,0)])
 forward=value([(0,0),(26,-.015),(30,-.015),(36,.10),(38,.10),(44,.11),(54,.11),(69,.02),(75,0)])
 lean=value([(0,-8),(26,5),(30,5),(36,-30),(38,-30),(44,-34),(54,-34),(69,-11),(75,-8)])
 hip=heads['Hip']+Vector((0,forward/.7,-.065-crouch))
 Q['Hip']=Quaternion();Q['Waist']=rx(-3+(.5*(lean+8)));Q['Spine01']=rx(-5+.75*(lean+8));Q['Spine02']=rx(lean);Q['Neck']=rx(-5+.40*(lean+8));Q['Head']=rx(-5+.25*(lean+8));Q['HeadTop_End']=Q['Head']
 for side,sign in [('L',-1),('R',1)]:
  Q[side+'_Clavicle']=Q['Spine02']
  upper=aim(side+'_Upperarm',(sign*.32,.03,-.95));fore=aim(side+'_Forearm',(sign*.22,.30,-.93))
  upper=upper.slerp(aim(side+'_Upperarm',(sign*1.,-.12,.15)),opened)
  fore=fore.slerp(aim(side+'_Forearm',(sign*.85,.4,.18)),opened)
  upper=upper.slerp(aim(side+'_Upperarm',(sign*.30,.95,-.1)),closed)
  fore=fore.slerp(aim(side+'_Forearm',(-sign*.70,.70,-.12)),closed)
  Q[side+'_Upperarm']=upper;Q[side+'_Forearm']=fore;Q[side+'_Hand']=fore.copy()
  for b in a.data.bones:
   if b.name.startswith(side+'_') and any(z in b.name for z in ['Thumb','Index','Middle','Pinky','Ring']):Q[b.name]=Q[b.parent.name].copy()
 for iteration in range(5):
  apply(Q,hip)
  for side in ['L','R']:
   thigh=side+'_Thigh';calf=side+'_Calf';h=a.pose.bones[thigh].head.copy();delta=targets[side]-h
   l1=(tails[thigh]-heads[thigh]).length;l2=(tails[calf]-heads[calf]).length;dist=max(abs(l1-l2)+1e-5,min(delta.length,l1+l2-1e-5))
   axis=delta.normalized();pole=Vector((0,1,0));pole=(pole-axis*pole.dot(axis)).normalized();along=(l1*l1-l2*l2+dist*dist)/(2*dist)
   knee=h+axis*along+pole*math.sqrt(max(0,l1*l1-along*along));ankle=h+axis*dist
   Q[thigh]=aim(thigh,knee-h);Q[calf]=aim(calf,ankle-knee)
   for n in [side+'_Foot',side+'_ToeBase',side+'_Toe_End']:Q[n]=Quaternion()
  apply(Q,hip);pts=eval_points()
  for side in ['L','R']:targets[side].z+=lifts[side]-min(pts[i].z for i in foot_ids[side])
 return hip


s.render.fps=30;s.frame_start=0;s.frame_end=75
a.animation_data.action=None;act=bpy.data.actions.new('attack');act.use_fake_user=True;a.animation_data.action=act
act['loop']=False;act['duration_seconds']=2.5;act['hit_frame']=36;act['hit_window']=[36,40]
for f in range(76):
 s.frame_set(f);solve(f)
 for pb in a.pose.bones:
  pb.keyframe_insert('rotation_quaternion',frame=f,group=pb.name)
  if pb.name=='Hip':pb.keyframe_insert('location',frame=f,group=pb.name)
for fc in act.fcurves:
 fc.extrapolation='CONSTANT'
 for k in fc.keyframe_points:k.interpolation='LINEAR'
report={'skeleton_signature':sig(),'geometry_weights_identical':True,'authored_actions':['idle','walking','running','attack'],'attack':{'duration_s':2.5,'fps':30,'loop':False,'hit_frame':36,'hit_window':[36,40]}}
assert sig()==original_sig
assert hashlib.sha256(json.dumps([[list(v.co),[(g.group,g.weight) for g in v.groups]] for v in m.data.vertices]).encode()).hexdigest()==original_geo
minimum=10;rooterror=0;footdrift=0;first=None;poses={};handdata={}
for k in range(151):
 f=k*.5;s.frame_set(k//2,subframe=k%2/2);pts=eval_points()
 minimum=min(minimum,min(pts[i].z*.7 for side in foot_ids for i in foot_ids[side]))
 rooterror=max(rooterror,max(abs(a.pose.bones['Root'].matrix_basis[i][j]-(1 if i==j else 0)) for i in range(4) for j in range(4)))
 feet={side:a.pose.bones[side+'_Foot'].head.copy() for side in ['L','R']}
 if first is None:first=feet
 footdrift=max(footdrift,max((feet[side]-first[side]).length*.7 for side in feet))
 if f in [0,26,30,36,38,44,54,75]:
  poses[int(f)]={pb.name:[x for row in pb.matrix for x in row] for pb in a.pose.bones};handdata[int(f)]={side:list(a.pose.bones[side+'_Hand'].head*.7) for side in ['L','R']}
assert minimum>-.001 and rooterror<1e-6 and footdrift<.005,(minimum,rooterror,footdrift)
seam=max(abs(x-y) for n in poses[0] for x,y in zip(poses[0][n],poses[75][n]));assert seam<1e-5
report['attack'].update(samples=151,min_sole_z_m=minimum,root_error=rooterror,max_foot_drift_m=footdrift,recovery_error=seam,hand_positions_m=handdata)
s.frame_set(26);bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(output))
bpy.ops.object.select_all(action='DESELECT');a.select_set(True);m.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,export_force_sampling=True,export_yup=True)
(qa/'validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print('ATTACK_AUTHOR_OK',json.dumps(report),flush=True)
s.render.engine='BLENDER_EEVEE_NEXT';s.render.resolution_x=480;s.render.resolution_y=480;s.render.resolution_percentage=100
if not s.world:s.world=bpy.data.worlds.new('AttackPreviewWorld')
s.world.color=(.16,)*3
for loc in [(3,4,5),(-3,-1,4)]:
 bpy.ops.object.light_add(type='AREA',location=loc);bpy.context.object.data.energy=500;bpy.context.object.data.size=4
bpy.ops.object.camera_add();cam=bpy.context.object;s.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=5.5
for view,pos in [('three_quarter',(4,7,4)),('top',(0,0,8)),('side',(7,0,2))]:
 cam.location=pos;cam.rotation_euler=(Vector((0,0,1.3))-cam.location).to_track_quat('-Z','Y').to_euler()
 for f in sorted(set(range(0,76,2))|{75}):
  s.frame_set(f);s.render.filepath=str(qa/f'attack_{view}_{f:03d}.png');bpy.ops.render.render(write_still=True)
print('ATTACK_PREVIEWS_OK',flush=True)
