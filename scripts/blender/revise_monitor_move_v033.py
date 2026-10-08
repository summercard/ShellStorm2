"""MCP: v031 move with reduced pedestal roll only; all other curves retained."""
import bpy,json,math,hashlib,shutil
from pathlib import Path
from mathutils import Vector,Quaternion,Matrix
R=Path('I:/工作项目/shellstrom2/ShellStorm2');B=R/'assets/art/enemies/bosses/enm_boss_monitor002'
Q=B/'previews/move_v033';Q.mkdir(exist_ok=True);D=R/'_scratch/monitor_move_v033';D.mkdir(exist_ok=True)
C=B/'components/enm_boss_monitor002';oldfile=B/'source/enm_boss_monitor002_animation_v031.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(D/'session_before_open.blend'),copy=True)
bpy.ops.wm.open_mainfile(filepath=str(oldfile))
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(D/'session_before.blend'),copy=True)
rig=bpy.data.objects['Boss002_Rig'];s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window_manager.windows[0].scene=s
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def action_hash(a):
 return hashlib.sha256(json.dumps([(c.data_path,c.array_index,[(list(k.co),list(k.handle_left),list(k.handle_right),k.interpolation) for k in c.keyframe_points]) for c in a.fcurves]).encode()).hexdigest()
def signature(r):
 return hashlib.sha256(json.dumps([{'name':b.name,'parent':b.parent.name if b.parent else None,'rest':[round(v,8) for row in b.matrix_local for v in row]} for b in r.data.bones],sort_keys=True).encode()).hexdigest()
def axis(p,v,a):return Quaternion(p.bone.matrix_local.to_3x3().inverted()@Vector(v),a)
old_hashes={a.name:action_hash(a) for a in bpy.data.actions if a.name!='move'}
old_sources={k:sha(B/f'source/enm_boss_monitor002_{k}_v031.blend') for k in ['model','animation']}
sig=signature(rig);act=bpy.data.actions['move'];rig.animation_data.action=act
def untouched_move(a):
 return hashlib.sha256(json.dumps([(c.data_path,c.array_index,[(list(k.co),list(k.handle_left),list(k.handle_right),k.interpolation) for k in c.keyframe_points]) for c in a.fcurves if 'pedestal_motion' not in c.data_path]).encode()).hexdigest()
unchanged_move=untouched_move(act)
base=bpy.data.objects['Crescent pedestal']
baseverts=[base.matrix_world@v.co for v in base.data.vertices]
for f in range(1,50):
 s.frame_set(f);t=(f-1)/48*math.tau
 roll=math.radians(10)*math.tanh(1.8*math.sin(t))/math.tanh(1.8)
 yaw=math.radians(11)*math.sin(t-.18)
 p=rig.pose.bones['pedestal_motion'];q=Quaternion((0,0,1),yaw)@Quaternion((0,1,0),roll)
 p.rotation_quaternion=axis(p,(0,0,1),yaw)@axis(p,(0,1,0),roll)
 height=.005-min((q@v).z for v in baseverts)
 p.location=p.bone.matrix_local.to_3x3().inverted()@Vector((.23*math.sin(t),.11*math.sin(2*t),height))
 for path in ['location','rotation_quaternion']:p.keyframe_insert(path,frame=f,group=p.name)
assert untouched_move(act)==unchanged_move
act['description']='v031 original move; pedestal roll reduced from 23 to 10 degrees; exact ground contact. Other move tracks and 15 actions unchanged.'
for scene in bpy.data.scenes:scene['asset_version']='v033'
s.frame_start=1;s.frame_end=48;s.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v033.blend'))
assert old_hashes=={a.name:action_hash(a) for a in bpy.data.actions if a.name!='move'}
# Independently evaluate rigid pedestal vertices at full and half frames.
ground=[];top=[];xs=[];yaw=[];hands={k:[] for k in ['hand.L','hand.R']};first=None;last=None
for step in range(97):
 f=1+step/2;s.frame_set(int(f),subframe=f%1);dg=bpy.context.evaluated_depsgraph_get()
 e=base.evaluated_get(dg);me=e.to_mesh();vs=[e.matrix_world@v.co for v in me.vertices];e.to_mesh_clear()
 ground.append(min(v.z for v in vs));top.append(max(v.z for v in vs));xs.append(rig.pose.bones['pedestal_motion'].head.x)
 body=rig.pose.bones['monitor_tilt'].matrix@rig.data.bones['monitor_tilt'].matrix_local.inverted();yaw.append(body.to_euler('XYZ').z)
 for name in hands:hands[name].append(list(rig.pose.bones[name].head))
 if step==0:first=vs
 if step==96:last=vs
audit={'version':'v033','samples':97,'pedestal_bottom_z':[min(ground),max(ground)],'pedestal_top_z':[min(top),max(top)],'lateral_range':max(xs)-min(xs),'body_yaw_range_degrees':math.degrees(max(yaw)-min(yaw)),'closure_error':max((a-b).length for a,b in zip(first,last)),'other_actions_unchanged':True,'other_move_tracks_unchanged':True,'pedestal_roll_degrees':10,'baseline_version':'v031','hand_ranges':{k:[max(v[i] for v in pts)-min(v[i] for v in pts) for i in range(3)] for k,pts in hands.items()},'old_sources':old_sources,'skeleton_signature':sig}
assert min(ground)>0 and max(ground)<.008
assert audit['lateral_range']>.45 and audit['closure_error']<1e-5,audit
# Export only revised evaluated move clip; retain every other clip byte-for-value.
CONV=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
motion=json.loads((C/'monitor_motion.json').read_text());original=json.loads(json.dumps(motion));frames=[];probes=[];bounds={}
for name in ['monitor_motion.json']:
 shutil.copy2(C/name,D/name)
for f in range(1,50):
 s.frame_set(f)
 frames.append({'bones':[[round(v,7) for row in CONV@p.matrix for v in row] for p in rig.pose.bones],'expression':int(round(rig.get('expression_state',0))),'face_scale':{slot:[bpy.data.objects['Texture '+slot].scale.x,bpy.data.objects['Texture '+slot].scale.z] for slot in ['large_eye','round_eye','mouth']}})
 probes.append({o:[round(v,6) for v in CONV@rig.pose.bones[o].head] for o in ['hand.L','hand.R','cable_16','monitor_tilt']})
 if f-1 in [0,24,47]:
  dg=bpy.context.evaluated_depsgraph_get();meshes={}
  for obj in ['Portrait display','Sculpted glove L','Sculpted glove R','Keyboard outer shell','Long data cable whip']:
   o=bpy.data.objects[obj].evaluated_get(dg);me=o.to_mesh();pts=[CONV@o.matrix_world@v.co for v in me.vertices];o.to_mesh_clear();meshes[obj]=[[min(v[i] for v in pts) for i in range(3)],[max(v[i] for v in pts) for i in range(3)]]
  bounds[str(f-1)]=meshes
motion['clips']['move']['frames']=frames
assert all(motion['clips'][k]==original['clips'][k] for k in motion['clips'] if k!='move')
(C/'monitor_motion.json').write_text(json.dumps(motion,separators=(',',':')))
for name,data in [('source_pose_probes.json',probes),('source_mesh_bounds.json',bounds)]:
 p=B/'previews/runtime'/name;shutil.copy2(p,D/name);out=json.loads(p.read_text());out['move']=data;p.write_text(json.dumps(out))
# New model master is the same geometry/rest/rig; no static GLB rebuild is needed.
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v031.blend'))
assert signature(bpy.data.objects['Boss002_Rig'])==sig
for scene in bpy.data.scenes:scene['asset_version']='v033'
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v033.blend'))
assert all(sha(B/f'source/enm_boss_monitor002_{k}_v031.blend')==v for k,v in old_sources.items())
contract=json.loads((B/'source/rig_contract_v031.json').read_text());contract.update(version='v033',export_signature=sig,move={'fps':30,'start':1,'end':48,'closure':49,'duration_seconds':1.6,'root_motion':False,'pedestal_roll_degrees':10,'pedestal_lateral_range':.46,'pedestal_bottom_z':.005,'revision':'r27 v031 reduced pedestal roll only'})
(B/'source/rig_contract_v033.json').write_text(json.dumps(contract,ensure_ascii=False,indent=2),encoding='utf-8')
audit['dual_signature_equal']=True;audit['static_glb_reused']=sha(C/'enm_boss_monitor002_visual_top3d.glb')
(Q/'source_audit.json').write_text(json.dumps(audit,indent=2));print(json.dumps(audit))
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v033.blend'))
bpy.context.window_manager.windows[0].scene=bpy.data.scenes['BOSS002_STUDIO'];bpy.data.scenes['BOSS002_STUDIO'].frame_set(13)

s=bpy.data.scenes['BOSS002_STUDIO'];rig=bpy.data.objects['Boss002_Rig'];rig.animation_data.action=bpy.data.actions['move']
s.render.resolution_x=960;s.render.resolution_y=800;s.render.resolution_percentage=75;s.cycles.samples=12
for f in [1,13,25,37]:
 s.frame_set(f);s.render.filepath=str(Q/('pose_%03d.png'%f));bpy.ops.render.render(write_still=True)
print('V033_RENDER_COMPLETE')

