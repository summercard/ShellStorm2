import bpy, math, json, hashlib, shutil
from pathlib import Path
from mathutils import Vector, Quaternion, Matrix
pkg=Path(__file__).resolve().parents[2]; project=pkg.parents[4]
qa=pkg/'previews/idle_walk_v002';qa.mkdir(parents=True,exist_ok=True)
model=pkg/'source/model/enm_normal_fat_zombie03_model_v002.blend'
output=Path(__file__).parent/'enm_normal_fat_zombie03_animation_v002.blend'
glb=pkg/'components/enm_normal_fat_zombie03_visual_top3d.glb'
backup=project/'_scratch/fat_zombie03/idle_walk_v002_backup';backup.mkdir(parents=True,exist_ok=True)
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
def solve(f, walking=False):
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
 if walking:
  phase=(f%60)/60;hip=heads['Hip']+Vector((-.018/.7*math.cos(2*math.pi*phase),0,-.14-.025/.7*(.5+.5*math.cos(4*math.pi*phase))))
  Q['Hip']=ry(0);Q['Waist']=rx(-3);Q['Spine01']=rx(-5);Q['Spine02']=rx(-8);Q['Neck']=rx(-5);Q['Head']=rx(-5);Q['HeadTop_End']=Q['Head']
  for side,sign,offset in [('L',-1,0),('R',1,.5)]:
   t=(phase+offset)%1
   # Constant support velocity: 0.30 m/s at display scale .70.
   if t<=.6:y=.18/.7-.6/.7*t
   else:
    u=(t-.6)/.4;sm=u*u*(3-2*u);y=-.18/.7+.36/.7*sm;lifts[side]=.06/.7*math.sin(math.pi*u)**2
   targets[side].y+=y
   swing=math.sin(2*math.pi*t)
   Q[side+'_Clavicle']=Q['Spine02']
   Q[side+'_Upperarm']=rx(8*swing)@aim(side+'_Upperarm',(sign*.32,.03,-.95))
   Q[side+'_Forearm']=rx(8*swing)@aim(side+'_Forearm',(sign*.22,.30,-.93))
   Q[side+'_Hand']=Q[side+'_Forearm'].copy()
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

s.render.fps=30;a.animation_data_create();reports={}
for name,end in [('idle',96),('walking',60)]:
 s.frame_start=0;s.frame_end=end-1;s.frame_set(0)
 act=bpy.data.actions.new(name);a.animation_data.action=act;act.use_fake_user=True
 act['loop']=True;act['duration_seconds']=end/30;act['closing_frame']=end
 for f in range(end+1):
  s.frame_set(f);solve(f,name=='walking')
  for pb in a.pose.bones:
   pb.keyframe_insert('rotation_quaternion',frame=f,group=pb.name)
   if pb.name=='Hip':pb.keyframe_insert('location',frame=f,group=pb.name)
 for fc in act.fcurves:
  for k in fc.keyframe_points:k.interpolation='LINEAR'
  fc.modifiers.new('CYCLES')
 ground=10;flight=0;rooterror=0;fingererror=0;seam=0;maxlift=0;first=None;support_error=0
 for step in range(end*4+1):
  f=step*.5;s.frame_set(int(f),subframe=f%1);pts=eval_points()
  soles={side:min(pts[i].z*.7 for i in foot_ids[side]) for side in foot_ids};ground=min(ground,*soles.values());flight=max(flight,min(soles.values()));maxlift=max(maxlift,*soles.values())
  rooterror=max(rooterror,max(abs(a.pose.bones['Root'].matrix_basis[i][j]-(1 if i==j else 0)) for i in range(4) for j in range(4)))
  for pb in a.pose.bones:
   if any(z in pb.name for z in ['Thumb','Index','Middle','Pinky','Ring']):fingererror=max(fingererror,abs(pb.rotation_quaternion.angle))
  if first is None:first={pb.name:pb.matrix.copy() for pb in a.pose.bones}
  if f in [end,end*2]:seam=max(seam,max(abs(pb.matrix[i][j]-first[pb.name][i][j]) for pb in a.pose.bones for i in range(4) for j in range(4)))
  if name=='walking':
   for side,offset in [('L',0),('R',.5)]:
    phase=(f/60+offset)%1
    if phase<=.6:support_error=max(support_error,abs((a.pose.bones[side+'_Foot'].head.y-heads[side+'_Foot'].y)*.7-(.18-.6*phase)))
 assert ground>-.001 and flight<.001 and seam<1e-5 and rooterror<1e-6 and fingererror<.001,(name,ground,flight,seam,fingererror)
 assert support_error<.005,(name,support_error)
 reports[name]={'duration_s':end/30,'fps':30,'frame_range':[0,end],'loop':True,'two_cycle_samples':end*4+1,'min_sole_z_m':ground,'max_both_feet_clearance_m':flight,'max_foot_lift_m':maxlift,'support_trajectory_error_m':support_error,'root_error':rooterror,'loop_error':seam,'finger_local_rotation_error':fingererror}
assert sig()==original_sig
assert hashlib.sha256(json.dumps([[list(v.co),[(g.group,g.weight) for g in v.groups]] for v in m.data.vertices]).encode()).hexdigest()==original_geo
report={'clips':reports,'skeleton_signature':sig(),'geometry_weights_identical':True,'model_skeleton_identical':True,'walking_reference_speed_m_s':.30,'authored_actions':['idle','walking']}
a.animation_data.action=bpy.data.actions['walking'];s.frame_start=0;s.frame_end=59;s.frame_set(0)
bpy.context.preferences.filepaths.save_version=0
for im in bpy.data.images:
 if im.users and im.has_data:im.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(output))
bpy.ops.object.select_all(action='DESELECT');a.select_set(True);m.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,export_force_sampling=True,export_yup=True)
(qa/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('FAT_ZOMBIE03_IDLE_WALK_AUTHORED_OK',json.dumps(report),flush=True)
s.render.engine='BLENDER_EEVEE_NEXT';s.render.resolution_x=480;s.render.resolution_y=480;s.render.resolution_percentage=100
if not s.world:s.world=bpy.data.worlds.new('PreviewWorld')
s.world.color=(.16,)*3
for loc in [(3,4,5),(-3,-1,4)]:
 bpy.ops.object.light_add(type='AREA',location=loc);bpy.context.object.data.energy=500;bpy.context.object.data.size=4
bpy.ops.object.camera_add();cam=bpy.context.object;s.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=4
for name,end in [('idle',96),('walking',60)]:
 a.animation_data.action=bpy.data.actions[name]
 cam.location=(4,7,3);cam.rotation_euler=(Vector((0,0,1.5))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=4
 for f in range(0,end,4 if name=='idle' else 2):
  s.frame_set(f);s.render.filepath=str(qa/f'{name}_{f:03d}.png');bpy.ops.render.render(write_still=True)
 for side in ['L','R']:
  s.frame_set(0);target=a.pose.bones[side+'_Hand'].head.copy();cam.location=target+Vector((0,3,1));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=1.3;s.render.filepath=str(qa/f'{name}_{side}_hand.png');bpy.ops.render.render(write_still=True)
print('FAT_ZOMBIE03_PREVIEWS_OK',flush=True)
