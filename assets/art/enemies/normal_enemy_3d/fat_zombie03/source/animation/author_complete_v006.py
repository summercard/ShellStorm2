import bpy, math, json, hashlib, shutil
from pathlib import Path
from mathutils import Vector, Quaternion, Matrix
pkg=Path(__file__).resolve().parents[2]; project=pkg.parents[4]
qa=pkg/'previews/complete_v006';qa.mkdir(parents=True,exist_ok=True)
model=pkg/'source/animation/enm_normal_fat_zombie03_animation_v005.blend'
output=Path(__file__).parent/'enm_normal_fat_zombie03_animation_v006.blend'
glb=pkg/'components/enm_normal_fat_zombie03_visual_top3d.glb'
backup=project/'_scratch/fat_zombie03/complete_v006_backup';backup.mkdir(parents=True,exist_ok=True)
if not (backup/glb.name).exists():shutil.copy2(glb,backup/glb.name)
bpy.ops.wm.open_mainfile(filepath=str(model))
a=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');m=next(o for o in bpy.context.scene.objects if o.type=='MESH');s=bpy.context.scene
rest={b.name:b.matrix_local.copy() for b in a.data.bones};heads={b.name:b.head_local.copy() for b in a.data.bones};tails={b.name:b.tail_local.copy() for b in a.data.bones}
def sig():return hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,[round(x,6) for row in b.matrix_local for x in row]) for b in a.data.bones]).encode()).hexdigest()
original_sig=sig(); original_geo=hashlib.sha256(json.dumps([[list(v.co),[(g.group,g.weight) for g in v.groups]] for v in m.data.vertices]).encode()).hexdigest()
assert set(bpy.data.actions.keys())=={'idle','walking','running','attack'}
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

def rz(d):return Quaternion((0,0,1),math.radians(d))
def val(f,keys):
 for (fa,va),(fb,vb) in zip(keys,keys[1:]):
  if f<=fb:
   t=max(0,min(1,(f-fa)/(fb-fa)));t=t*t*(3-2*t);return va+(vb-va)*t
 return keys[-1][1]
def snapshot(clip,f):
 a.animation_data.action=bpy.data.actions[clip];s.frame_set(int(f),subframe=f%1);bpy.context.view_layer.update()
 return ({b.name:(b.matrix@rest[b.name].inverted()).to_quaternion() for b in a.pose.bones},a.pose.bones['Hip'].head.copy())
base,basehip=snapshot('idle',0);walk,walkhip=snapshot('walking',0)
ends={'hurt':24,'dead':78,'awaken':36,'alert':18,'turn_l':24,'turn_r':24,'move_start':12,'move_stop':18,'hit_light':9}
preserved={n:[[(fc.data_path,fc.array_index),[(tuple(k.co),k.interpolation) for k in fc.keyframe_points]] for fc in bpy.data.actions[n].fcurves] for n in ['idle','walking','running','attack']}
def makepose(name,f):
 Q={n:q.copy() for n,q in base.items()};hip=basehip.copy();targets={side:heads[side+'_Foot'].copy() for side in ['L','R']};lifts={'L':0.,'R':0.};pitch=0;roll=0;yaw=0;arm=0;head=0
 if name=='hurt':
  v=val(f,[(0,0),(3,1),(7,1),(11,1),(19,.2),(24,0)]);pitch=12*v;head=val(f,[(0,0),(1,0),(4,12),(11,12),(24,0)]);hip.y-=.04/.7*v;hip.z-=.025/.7*v;arm=-10*v
 elif name=='awaken':
  v=val(f,[(0,0),(8,.3),(20,1),(28,1),(36,0)]);pitch=5*v;head=val(f,[(0,0),(8,14),(20,8),(28,8),(36,0)]);hip.z+=.025/.7*v;arm=10*v
 elif name=='alert':
  v=val(f,[(0,0),(3,1),(7,1),(12,1),(18,.5)]);head=12*v;yaw=val(f,[(0,0),(3,0),(7,-8),(12,-8),(18,0)]);hip.z-=val(f,[(0,0),(12,0),(18,.03/.7)]);arm=8*v
 elif name.startswith('turn_'):
  sign=-1 if name=='turn_l' else 1;v=val(f,[(0,0),(6,.3),(12,1),(19,.3),(24,0)]);yaw=sign*14*v;head=sign*8*v;hip.x-=sign*.025/.7*v
  lead='L' if sign==-1 else 'R';other='R' if lead=='L' else 'L'
  lifts[lead]=val(f,[(0,0),(6,0),(9,.045/.7),(12,0),(24,0)]);lifts[other]=val(f,[(0,0),(12,0),(16,.035/.7),(19,0),(24,0)])
  hip.z-=.025/.7*v
 elif name in ['move_start','move_stop']:
  blend=val(f,[(0,0),(4,.25),(8,.7),(12,1)]) if name=='move_start' else 1-val(f,[(0,0),(5,.15),(10,.6),(18,1)])
  Q={n:base[n].slerp(walk[n],blend) for n in base};hip=basehip.lerp(walkhip,blend)
  for side in targets:
   targets[side].y+=((.18/.7) if side=='L' else (-.12/.7))*blend
  if name=='move_start':lifts['L']=val(f,[(0,0),(4,0),(8,.04/.7),(12,0)]);pitch=-5*math.sin(math.pi*f/12)
  else:pitch=-8*math.sin(math.pi*f/18);arm=12*math.sin(math.pi*f/18)
 elif name=='hit_light':
  v=val(f,[(0,0),(2,1),(4,1),(9,0)]);pitch=3*v;head=1*v;roll=2*v
 elif name=='dead':
  collapse=val(f,[(0,0),(6,.10),(18,.40),(30,.70),(36,1),(78,1)])
  pitch=-88*collapse;head=-12*val(f,[(0,0),(6,1),(36,1),(54,1),(78,1)]);hip.z-=.50*collapse;hip.y+=.45*collapse
  arm=30*val(f,[(0,0),(18,.4),(30,1),(42,.9),(54,.8),(78,.8)])
 for n in ['Waist','Spine01','Spine02','Neck','Head','HeadTop_End']:
  mult={'Waist':.4,'Spine01':.7,'Spine02':1,'Neck':.65,'Head':.5,'HeadTop_End':.5}[n]
  Q[n]=rz(yaw*mult)@ry(roll*mult)@rx(pitch*mult+(head if n in ['Head','HeadTop_End'] and not name.startswith('turn_') else 0))@Q[n]
 for side,sign in [('L',-1),('R',1)]:
  for n in [side+'_Clavicle',side+'_Upperarm',side+'_Forearm',side+'_Hand']:
   Q[n]=rz(yaw*.7)@ry(sign*arm*.4)@rx(-arm)@Q[n]
  for b in a.data.bones:
   if b.name.startswith(side+'_') and any(z in b.name for z in ['Thumb','Index','Middle','Pinky','Ring']):Q[b.name]=Q[b.parent.name].copy()
 if name=='dead' and f>=18:
  beforeQ={n:q.copy() for n,q in Q.items()};fall=val(f,[(18,0),(30,.55),(36,1),(78,1)]);whole=rx(-82*fall)
  Q['Hip']=whole
  for n in ['Waist','Spine01','Spine02','Neck','Head','HeadTop_End']:Q[n]=rx(-82*fall)@base[n]
  for side,sign in [('L',-1),('R',1)]:
   Q[side+'_Thigh']=ry(sign*12*fall)@rx(-82*fall);Q[side+'_Calf']=ry(sign*12*fall)@rx(-60*fall);Q[side+'_Foot']=ry(sign*12*fall)@rx(-60*fall);Q[side+'_ToeBase']=Q[side+'_Foot'];Q[side+'_Toe_End']=Q[side+'_Foot']
   Q[side+'_Upperarm']=aim(side+'_Upperarm',(sign*.5,.8,-.25));Q[side+'_Forearm']=aim(side+'_Forearm',(sign*.35,.85,-.18));Q[side+'_Hand']=Q[side+'_Forearm'].copy()
   for b in a.data.bones:
    if b.name.startswith(side+'_') and any(z in b.name for z in ['Thumb','Index','Middle','Pinky','Ring']):Q[b.name]=Q[b.parent.name].copy()
  Q={n:beforeQ[n].slerp(Q[n],fall) for n in Q}
  apply(Q,hip);pts=eval_points();hip.z-=min(v.z for v in pts);apply(Q,hip)
 else:
  for iteration in range(6):
   apply(Q,hip)
   for side in ['L','R']:
    thigh=side+'_Thigh';calf=side+'_Calf';h=a.pose.bones[thigh].head.copy();delta=targets[side]-h;l1=(tails[thigh]-heads[thigh]).length;l2=(tails[calf]-heads[calf]).length;d=max(abs(l1-l2)+1e-5,min(delta.length,l1+l2-1e-5));axis=delta.normalized();pole=Vector((0,1,0));pole=(pole-axis*pole.dot(axis)).normalized();along=(l1*l1-l2*l2+d*d)/(2*d);knee=h+axis*along+pole*math.sqrt(max(0,l1*l1-along*along))
    Q[thigh]=aim(thigh,knee-h);Q[calf]=aim(calf,h+axis*d-knee)
    for n in [side+'_Foot',side+'_ToeBase',side+'_Toe_End']:Q[n]=Quaternion()
   apply(Q,hip);pts=eval_points()
   for side in targets:targets[side].z+=lifts[side]-min(pts[i].z for i in foot_ids[side])
 if name=='dead':
  pts=eval_points();hip.z+=max(0,.002-min(v.z for v in pts))+val(f,[(0,0),(36,0),(40,.025/.7),(54,0),(78,0)]);apply(Q,hip)
 return Q,hip
reports={};s.render.fps=30
for name,end in ends.items():
 a.animation_data.action=None;act=bpy.data.actions.new(name);act.use_fake_user=True;a.animation_data.action=act;act['loop']=False;act['duration_seconds']=end/30
 for step in range(end*4+1):
  f=step/4;s.frame_set(int(f),subframe=f%1);makepose(name,f)
  for pb in a.pose.bones:
   if name=='hit_light' and pb.name not in ['Waist','Spine01','Spine02','Neck','Head','HeadTop_End']:continue
   pb.keyframe_insert('rotation_quaternion',frame=f,group=pb.name)
   if pb.name=='Hip':pb.keyframe_insert('location',frame=f,group=pb.name)
 for fc in act.fcurves:
  fc.extrapolation='CONSTANT'
  for k in fc.keyframe_points:k.interpolation='LINEAR'
 minimum=10;rooterr=0;last=None;motion=0
 for k in range(end*2+1):
  s.frame_set(k//2,subframe=k%2/2);pts=eval_points();minimum=min(minimum,min(v.z*.7 for v in pts));rooterr=max(rooterr,max(abs(a.pose.bones['Root'].matrix_basis[i][j]-(1 if i==j else 0)) for i in range(4) for j in range(4)))
  pose=[x for b in a.pose.bones for row in b.matrix for x in row]
  if last:motion=max(motion,max(abs(x-y) for x,y in zip(pose,last)))
  last=pose
 assert rooterr<1e-6 and minimum>-.005,(name,minimum,rooterr)
 reports[name]={'duration_s':end/30,'loop':False,'samples':end*2+1,'min_mesh_z_m':minimum,'root_error':rooterr,'max_half_frame_change':motion}
for n,before in preserved.items():assert before==[[(fc.data_path,fc.array_index),[(tuple(k.co),k.interpolation) for k in fc.keyframe_points]] for fc in bpy.data.actions[n].fcurves]
assert sig()==original_sig
report={'skeleton_signature':sig(),'clips':reports,'original_four_actions_unchanged':True,'bone_scale_one':all(abs(v-1)<1e-6 for b in a.pose.bones for v in b.scale),'hit_light_upper_body_only':True}
a.animation_data.action=bpy.data.actions['dead'];s.frame_start=0;s.frame_end=78;s.frame_set(54);bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(output))
bpy.ops.object.select_all(action='DESELECT');a.select_set(True);m.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,export_force_sampling=True,export_yup=True)
# Keep the exported light-hit clip upper-body-only, including on importers
# which unify sampled armature tracks across actions.
import struct
raw=glb.read_bytes();jn=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+jn]);body=raw[20+jn:]
light=next(c for c in doc['animations'] if c['name']=='hit_light');allowed={'Waist','Spine01','Spine02','Neck','Head','HeadTop_End'}
light['channels']=[c for c in light['channels'] if doc['nodes'][c['target']['node']].get('name') in allowed]
blob=json.dumps(doc,separators=(',',':')).encode();blob+=b' '*((-len(blob))%4)
glb.write_bytes(struct.pack('<III',0x46546c67,2,20+len(blob)+len(body))+struct.pack('<I4s',len(blob),b'JSON')+blob+body)
(qa/'validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print('COMPLETE_SOURCE_OK',json.dumps(report),flush=True)
s.render.engine='BLENDER_EEVEE_NEXT';s.render.resolution_x=480;s.render.resolution_y=480;s.render.resolution_percentage=100
if not s.world:s.world=bpy.data.worlds.new('PreviewWorld')
s.world.color=(.16,)*3
for loc in [(3,4,5),(-3,-1,4)]:
 bpy.ops.object.light_add(type='AREA',location=loc);bpy.context.object.data.energy=500;bpy.context.object.data.size=4
bpy.ops.object.camera_add();cam=bpy.context.object;s.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=6.4
for name,end in ends.items():
 a.animation_data.action=bpy.data.actions[name]
 for view,pos in [('three_quarter',(4,7,4)),('side',(7,0,2))]:
  cam.location=pos;cam.rotation_euler=(Vector((0,.7,1))-cam.location).to_track_quat('-Z','Y').to_euler()
  for f in sorted(set(range(0,end+1,3))|{end}):
   s.frame_set(f);s.render.filepath=str(qa/f'{name}_{view}_{f:03d}.png');bpy.ops.render.render(write_still=True)
print('COMPLETE_PREVIEWS_OK',flush=True)
