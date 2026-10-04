import bpy, math, json, hashlib, shutil
from pathlib import Path
from mathutils import Vector, Quaternion, Matrix
pkg=Path(__file__).resolve().parents[2]; project=pkg.parents[4]
qa=pkg/'previews/idle_v001';qa.mkdir(parents=True,exist_ok=True)
model=pkg/'source/model/enm_normal_fat_zombie03_model_v002.blend'
output=Path(__file__).parent/'enm_normal_fat_zombie03_animation_v001.blend'
glb=pkg/'components/enm_normal_fat_zombie03_visual_top3d.glb'
backup=project/'_scratch/fat_zombie03/idle_v001_backup';backup.mkdir(parents=True,exist_ok=True)
if not (backup/glb.name).exists():shutil.copy2(glb,backup/glb.name)
bpy.ops.wm.open_mainfile(filepath=str(model))
a=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');m=next(o for o in bpy.context.scene.objects if o.type=='MESH');s=bpy.context.scene
rest={b.name:b.matrix_local.copy() for b in a.data.bones};heads={b.name:b.head_local.copy() for b in a.data.bones};tails={b.name:b.tail_local.copy() for b in a.data.bones}
def sig():return hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,[round(x,6) for row in b.matrix_local for x in row]) for b in a.data.bones]).encode()).hexdigest()
original_sig=sig(); original_geo=hashlib.sha256(json.dumps([[list(v.co),[(g.group,g.weight) for g in v.groups]] for v in m.data.vertices]).encode()).hexdigest()
assert not bpy.data.actions
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
def solve(f):
 breath=curve(f,[(0,0),(24,1),(48,0),(96,0)])
 sway=curve(f,[(0,0),(24,0),(48,.02/.7),(72,-.02/.7),(96,0)])
 hip=heads['Hip']+Vector((sway,0,-.065+breath*.015/.7))
 Q={n:Quaternion() for n in rest};Q['Hip']=ry(-.6*sway/(.02/.7));Q['Waist']=rx(-3);Q['Spine01']=rx(-5);Q['Spine02']=rx(-8+.45*breath);Q['Neck']=rx(-5);Q['Head']=rx(-5-.35*breath);Q['HeadTop_End']=Q['Head']
 for side,sign in [('L',-1),('R',1)]:
  lag=curve(f-2,[(0,0),(24,0),(48,1),(72,-1),(96,0)])
  Q[side+'_Clavicle']=Q['Spine02']@ry(sign*.55*lag)
  Q[side+'_Upperarm']=aim(side+'_Upperarm',(sign*.32,.03,-.95))@ry(sign*.5*lag)
  Q[side+'_Forearm']=aim(side+'_Forearm',(sign*.22,.30,-.93))
  Q[side+'_Hand']=aim(side+'_Hand',(sign*.18,.23,-.96))
  for b in a.data.bones:
   n=b.name
   if n.startswith(side+'_') and any(z in n for z in ['Thumb','Index','Middle','Pinky','Ring']):
    parent=b.parent.name;Q[n]=Q.get(parent,Q[side+'_Hand'])
    if not n.endswith('4'):
     angle=({'1':-30,'2':-25,'3':-5}[n[-1]] if 'Thumb' in n else {'1':-65,'2':-75,'3':-20}[n[-1]])
     basis=rest[n].to_quaternion();Q[n]=Q[n]@basis@rx(angle)@basis.inverted()
 targets={side:heads[side+'_Foot'].copy() for side in ['L','R']}
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
  for side in ['L','R']:targets[side].z-=min(pts[i].z for i in foot_ids[side])
 return hip
s.render.fps=30;s.frame_start=0;s.frame_end=95;s.frame_set(0)
a.animation_data_create();act=bpy.data.actions.new('idle');a.animation_data.action=act;act.use_fake_user=True
act['loop']=True;act['fps']=30;act['duration_seconds']=3.2;act['closing_frame']=96;act['design']='docs/v0.1/design/胖子僵尸03动作设计.md#idle'
for f in range(97):
 s.frame_set(f);solve(f)
 for pb in a.pose.bones:
  pb.keyframe_insert('rotation_quaternion',frame=f,group=pb.name)
  if pb.name=='Hip':pb.keyframe_insert('location',frame=f,group=pb.name)
for fc in act.fcurves:
 for k in fc.keyframe_points:k.interpolation='LINEAR'
 fc.modifiers.new('CYCLES')
samples=[];first=None;seam=0;ground=10;drift=0;rooterror=0;scaleerror=0;baseline_feet=None
for step in range(385):
 f=step*.5;s.frame_set(int(f),subframe=f%1);pts=eval_points()
 feet={side:a.pose.bones[side+'_Foot'].head.copy() for side in ['L','R']}
 if baseline_feet is None:baseline_feet=feet
 drift=max(drift,max((feet[side]-baseline_feet[side]).length*.7 for side in feet))
 ground=min(ground,min(pts[i].z*.7 for side in foot_ids for i in foot_ids[side]))
 rooterror=max(rooterror,max(abs(a.pose.bones['Root'].matrix_basis[i][j]-(1 if i==j else 0)) for i in range(4) for j in range(4)))
 scaleerror=max(scaleerror,max(abs(x-1) for pb in a.pose.bones for x in pb.scale))
 if step==0:first={pb.name:pb.matrix.copy() for pb in a.pose.bones}
 if f in [96,192]:seam=max(seam,max(abs(pb.matrix[i][j]-first[pb.name][i][j]) for pb in a.pose.bones for i in range(4) for j in range(4)))
 if f in [0,24,48,72,96]:samples.append({'frame':f,'hip_world_m':[x*.7 for x in a.pose.bones['Hip'].head],'foot_min_world_m':{side:min(pts[i].z*.7 for i in ids) for side,ids in foot_ids.items()}})
assert sig()==original_sig
assert hashlib.sha256(json.dumps([[list(v.co),[(g.group,g.weight) for g in v.groups]] for v in m.data.vertices]).encode()).hexdigest()==original_geo
assert seam<1e-5 and rooterror<1e-6 and scaleerror<1e-6 and ground>-.001 and drift<.01,(seam,ground,drift)
report={'clip':'idle','fps':30,'duration_s':3.2,'frame_range':[0,96],'preview_range':[0,95],'loop':True,'skeleton_signature':sig(),'model_skeleton_identical':True,'geometry_weights_identical':True,'two_cycle_samples':385,'loop_error':seam,'root_error':rooterror,'bone_scale_error':scaleerror,'min_foot_world_z':ground,'max_foot_drift_world_m':drift,'samples':samples,'authored_actions':['idle'],'other_actions_authored':False}
s.frame_set(0);bpy.context.preferences.filepaths.save_version=0
# Packed textures make the animation source independent of relative image paths.
for im in bpy.data.images:
 if im.users and im.has_data:im.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(output))
bpy.ops.object.select_all(action='DESELECT');a.select_set(True);m.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,export_force_sampling=True,export_yup=True)
(qa/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
# Preview scene is saved separately; the authoring source contains only skin+rig.
s.render.engine='BLENDER_EEVEE_NEXT';s.render.resolution_x=640;s.render.resolution_y=640;s.render.resolution_percentage=100
if not s.world:s.world=bpy.data.worlds.new('IdleWorld')
s.world.color=(.16,)*3
for loc in [(3,4,5),(-3,-1,4)]:
 bpy.ops.object.light_add(type='AREA',location=loc);bpy.context.object.data.energy=500;bpy.context.object.data.size=4
bpy.ops.object.camera_add();cam=bpy.context.object;s.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=4
for view,pos in [('front',(0,7,1.7)),('side',(7,0,1.7)),('three_quarter',(5,7,3))]:
 cam.location=pos;cam.rotation_euler=(Vector((0,0,1.5))-cam.location).to_track_quat('-Z','Y').to_euler()
 for f in [0,24,48,72]:s.frame_set(f);s.render.filepath=str(qa/f'{view}_{f:03d}.png');bpy.ops.render.render(write_still=True)
cam.location=(4,7,3);cam.rotation_euler=(Vector((0,0,1.5))-cam.location).to_track_quat('-Z','Y').to_euler()
s.render.resolution_x=480;s.render.resolution_y=480
for f in range(0,96,4):s.frame_set(f);s.render.filepath=str(qa/f'frame_{f:03d}.png');bpy.ops.render.render(write_still=True)
print('FAT_ZOMBIE03_IDLE_AUTHORED_OK',json.dumps(report))
