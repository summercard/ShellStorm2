"""Run through Blender MCP. Add activate only; preserve all sixteen v031 actions."""
import bpy, math, json, hashlib, shutil, traceback, struct
from pathlib import Path
from mathutils import Vector, Matrix, Quaternion
R=Path('I:/工作项目/shellstrom2/ShellStorm2');B=R/'assets/art/enemies/bosses/enm_boss_monitor002'
C=B/'components/enm_boss_monitor002';Q=B/'previews/activate_v034';Q.mkdir(exist_ok=True)
D=R/'_scratch/monitor_activate_v034';D.mkdir(exist_ok=True)
def run():
 bpy.context.preferences.filepaths.save_version=0
 bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v031.blend'))
 s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window_manager.windows[0].scene=s
 rig=bpy.data.objects['Boss002_Rig'];arm=rig.data
 def ah(a):return hashlib.sha256(json.dumps([(c.data_path,c.array_index,[(list(k.co),list(k.handle_left),list(k.handle_right),k.interpolation) for k in c.keyframe_points]) for c in a.fcurves]).encode()).hexdigest()
 def signature():return hashlib.sha256(json.dumps([{'name':b.name,'parent':b.parent.name if b.parent else None,'rest':[round(v,8) for row in b.matrix_local for v in row]} for b in arm.bones],sort_keys=True).encode()).hexdigest()
 originals={a.name:ah(a) for a in bpy.data.actions};sig=signature()
 rig.animation_data.action=bpy.data.actions['idle'];s.frame_set(1)
 base={p.name:(p.location.copy(),p.rotation_quaternion.copy(),p.scale.copy()) for p in rig.pose.bones}
 neutral={p.name:p.matrix.copy() for p in rig.pose.bones}
 stretch={side:rig['stretch_'+side] for side in ['L','R']}
 keyboard=bpy.data.objects['Keyboard outer shell'];old_obj=keyboard.matrix_world.copy()
 held=Matrix.Translation(Vector((2.24,-.15,.52)))@Matrix.Rotation(math.radians(-10),4,'X')@Matrix.Rotation(math.pi/2,4,'Y')
 grip_fix=neutral['prop_socket.L'].inverted()@held@old_obj.inverted()@neutral['prop_socket.L']
 def correct_keyboard(r):
  p=r.pose.bones['prop_socket.L'].matrix
  objects=[o for o in bpy.data.objects if o.parent==r and o.parent_bone=='prop_socket.L']
  worlds={o.name:o.matrix_world.copy() for o in objects}
  for o in objects:o.matrix_world=p@grip_fix@p.inverted()@worlds[o.name]
  bpy.context.view_layer.update()
 correct_keyboard(rig);old_obj=keyboard.matrix_world.copy()
 relative=neutral['hand_ctrl.L'].inverted()@neutral['prop_socket.L']
 desired=Matrix.Translation(Vector((1.22,1.65,.12)))@Matrix.Rotation(math.radians(-12),4,'Z')@Matrix.Rotation(math.pi/2,4,'X')
 ground=desired@old_obj.inverted()@neutral['prop_socket.L']
 dg=bpy.context.evaluated_depsgraph_get();ev=keyboard.evaluated_get(dg);me=ev.to_mesh()
 pts=[desired@old_obj.inverted()@ev.matrix_world@v.co for v in me.vertices];ev.to_mesh_clear()
 ground.translation.z+=.035-min(v.z for v in pts)
 grab=ground@relative.inverted()
 act=bpy.data.actions.new('activate');act.use_fake_user=True;act['duration_seconds']=6.4
 act['description']='Black screen, boot, two restrained pulls, shoulder-led spring emergence, grounded keyboard pickup, face reveal.'
 act['events_json']=json.dumps({'code':[18,45],'pull_peaks':[63,98],'cable_breaks':[44,65,99],'arms':[112,143],'keyboard_grip':150,'face':[171,183],'idle':192})
 rig.animation_data.action=act
 def smooth(t):t=max(0,min(1,t));return t*t*(3-2*t)
 def sample(keys,f):
  for a,b in zip(keys,keys[1:]):
   if f<=b[0]:return a[1]+(b[1]-a[1])*smooth((f-a[0])/(b[0]-a[0]))
  return keys[-1][1]
 def chain(names,points):
  for n,a,b in zip(names,points,points[1:]):
   pb=rig.pose.bones[n];m=(b-a).to_track_quat('Y','Z').to_matrix().to_4x4();m.translation=a
   pb.matrix=m@Matrix.Diagonal(Vector((1,(b-a).length/pb.bone.length,1,1)));bpy.context.view_layer.update()
 def curve(side,dest,orientation,emerge):
  sign=1 if side=='L' else -1
  root=rig.pose.bones['rear_axle'].matrix@arm.bones['rear_axle'].matrix_local.inverted()
  start=root@arm.bones['arm_01.'+side].head_local
  c1=start+Vector((sign*(.22+.8*emerge),-.30,.30+.38*emerge))
  c2=dest+Vector((sign*.14,-.40,.50))
  pts=[(1-t)**3*start+3*(1-t)**2*t*c1+3*(1-t)*t*t*c2+t**3*dest for t in [i/120 for i in range(121)]]
  lengths=[0]
  for a,b in zip(pts,pts[1:]):lengths.append(lengths[-1]+(b-a).length)
  nodes=[]
  for j in range(7):
   distance=lengths[-1]*j/6;i=next((i for i in range(120) if lengths[i+1]>=distance),119)
   nodes.append(pts[i].lerp(pts[i+1],(distance-lengths[i])/(lengths[i+1]-lengths[i])))
  rig['stretch_'+side]=sum((b-a).length for a,b in zip(nodes,nodes[1:]))/1.32;rig.update_tag();bpy.context.view_layer.update()
  chain(['arm_%02d.%s'%(i,side) for i in range(1,7)],nodes)
  m=orientation.copy();m.translation=dest;rig.pose.bones['hand_ctrl.'+side].matrix=m;bpy.context.view_layer.update()
 for frame in range(1,194):
  f=frame-1
  for pb in rig.pose.bones:
   l,q,sc=base[pb.name];pb.location=l;pb.rotation_mode='QUATERNION';pb.rotation_quaternion=q;pb.scale=sc
  for side in ['L','R']:rig['stretch_'+side]=stretch[side]
  # Long hold, compressed anticipation, fast release, tether recoil; second pull is stronger.
  pull=sample([(0,0),(47,0),(56,-.20),(59,-.20),(63,.62),(65,.65),(70,-.23),(77,.03),(82,.03),(91,-.31),(94,-.31),(98,.92),(100,.98),(105,-.18),(111,.12),(121,0),(145,-.12),(154,.05),(164,0),(192,0)],f)
  pitch=sample([(0,0),(48,0),(56,9),(59,9),(63,-21),(65,-23),(70,10),(78,0),(91,14),(94,14),(98,-32),(101,-34),(107,8),(116,-3),(127,0),(145,-9),(152,-7),(162,5),(171,0),(192,0)],f)
  for i in range(1,4):
   pb=rig.pose.bones['support_%02d'%i];pb.rotation_quaternion=base[pb.name][1]@Quaternion((1,0,0),math.radians(pitch*.16))
  bpy.context.view_layer.update()
  pb=rig.pose.bones['rear_axle'];m=pb.matrix.copy();m.translation+=Vector((0,pull,-abs(pull)*.16));pb.matrix=m
  pb=rig.pose.bones['monitor_tilt'];pb.rotation_quaternion=base[pb.name][1]@Quaternion(pb.bone.matrix_local.to_3x3().inverted()@Vector((1,0,0)),math.radians(pitch))
  bpy.context.view_layer.update()
  for side in ['L','R']:
   sign=1 if side=='L' else -1;delay=0 if side=='L' else 5;u=f-delay
   e=smooth((u-112)/24);root=rig.pose.bones['rear_axle'].matrix@arm.bones['rear_axle'].matrix_local.inverted()
   st=root@arm.bones['arm_01.'+side].head_local;folded=st+Vector((sign*.10,-.42,-.10))
   rest=neutral['hand_ctrl.'+side];dest=folded.lerp(rest.translation,e)
   # The root leads a curved unfurl; wrist overshoots, then swings back before pickup.
   flourish=sample([(0,0),(114,0),(121,.35),(130,1),(139,-.24),(145,0),(192,0)],u)
   dest+=Vector((sign*.65*flourish,.42*flourish,.90*flourish))
   orient=rest.copy()
   if side=='L':
    pickup=smooth((f-136)/14)
    if f<=154:dest=dest.lerp(grab.translation,pickup);orient=rest.lerp(grab,pickup)
    else:
     lift=smooth((f-154)/24);dest=grab.translation.lerp(rest.translation,lift)+Vector((.14, .28, .30))*math.sin(math.pi*lift)
     orient=grab.lerp(rest,lift)
   else:
    dest+=Vector((-.22,.32,.30))*math.sin(math.pi*smooth((f-143)/40))
   curve(side,dest,orient,e)
  # Keyboard is a separate bone attachment, stationary until the authored grip frame.
  rig.pose.bones['prop_socket.L'].matrix=ground if f<=150 else rig.pose.bones['hand_ctrl.L'].matrix@relative
  bpy.context.view_layer.update()
  for i in range(1,17):
   pb=rig.pose.bones['cable_%02d'%i];wave=math.sin((f-127)*.20-i*.38)*sample([(0,0),(118,0),(134,.08),(150,.035),(174,0),(192,0)],f)
   pb.rotation_quaternion=base[pb.name][1]@Quaternion((1,0,0),wave)
  # Exact authored neutral endpoint, with a gradual final settle.
  end=smooth((f-176)/16)
  if end>0:
   for pb in rig.pose.bones:
    l,q,sc=base[pb.name];pb.location=pb.location.lerp(l,end);pb.rotation_quaternion=pb.rotation_quaternion.slerp(q,end);pb.scale=pb.scale.lerp(sc,end)
   for side in ['L','R']:rig['stretch_'+side]=rig['stretch_'+side]*(1-end)+stretch[side]*end
  rig['expression_state']=0;rig['code_scroll']=f/96
  for pb in rig.pose.bones:
   if pb.name=='root':continue
   for path in ['location','rotation_quaternion','scale']:pb.keyframe_insert(path,frame=frame,group=pb.name)
  for prop in ['stretch_L','stretch_R','expression_state','code_scroll']:rig.keyframe_insert(data_path='["'+prop+'"]',frame=frame)
 for fc in act.fcurves:
  for k in fc.keyframe_points:k.interpolation='LINEAR'
 assert all(ah(bpy.data.actions[n])==h for n,h in originals.items())
 for sc in bpy.data.scenes:sc['asset_version']='v034';sc.render.fps=30
 s.frame_start=1;s.frame_end=193;s.frame_set(1)
 bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v034.blend'))
 conv=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
 motion=json.loads((C/'monitor_motion.json').read_text());shutil.copy2(C/'monitor_motion.json',D/'monitor_motion_before.json')
 frames=[];probes=[];bounds={};keyboard_samples=[]
 for f in range(1,194):
  s.frame_set(f);bpy.context.view_layer.update()
  frames.append({'bones':[[round(v,7) for row in conv@p.matrix for v in row] for p in rig.pose.bones],'expression':0,'face_scale':{slot:[bpy.data.objects['Texture '+slot].scale.x,bpy.data.objects['Texture '+slot].scale.z] for slot in ['large_eye','round_eye','mouth']}})
  probes.append({n:[round(v,6) for v in conv@rig.pose.bones[n].head] for n in ['hand.L','hand.R','cable_16','monitor_tilt']})
  keyboard_samples.append(list(rig.pose.bones['prop_socket.L'].head))
  if f-1 in [0,96,191,192]:
   dg=bpy.context.evaluated_depsgraph_get();meshes={}
   for obj in ['Portrait display','Sculpted glove L','Sculpted glove R','Keyboard outer shell','Long data cable whip']:
    o=bpy.data.objects[obj].evaluated_get(dg);me=o.to_mesh();pts=[conv@o.matrix_world@v.co for v in me.vertices];o.to_mesh_clear();meshes[obj]=[[min(v[i] for v in pts) for i in range(3)],[max(v[i] for v in pts) for i in range(3)]]
   bounds[str(f-1)]=meshes
 motion['clips']['activate']={'duration':6.4,'loop':False,'frames':frames}
 old=json.loads((D/'monitor_motion_before.json').read_text());assert all(motion['clips'][k]==v for k,v in old['clips'].items() if k!='activate')
 (C/'monitor_motion.json').write_text(json.dumps(motion,separators=(',',':')))
 for name,data in [('source_pose_probes.json',probes),('source_mesh_bounds.json',bounds)]:
  p=B/'previews/runtime'/name;out=json.loads(p.read_text());out['activate']=data;p.write_text(json.dumps(out))
 idle=motion['clips']['idle']['frames'][0]['bones'];endpoint=max(abs(a-b) for mat,ref in zip(frames[-1]['bones'],idle) for a,b in zip(mat,ref))
 assert endpoint<.0001,endpoint
 stationary=max((Vector(p)-Vector(keyboard_samples[0])).length for p in keyboard_samples[:151]);assert stationary<.00001,stationary
 audit={'version':'v034','old_actions_unchanged':originals,'old_runtime_clips_unchanged':True,'idle_endpoint_error':endpoint,'keyboard_stationary_error':stationary,'skeleton_signature':sig,'source_bounds':bounds,'frames':193,'duration':6.4}
 (Q/'source_audit.json').write_text(json.dumps(audit,indent=2))
 # Only the static grip attachment changes; legacy pose matrices remain byte-for-value.
 p=B/'previews/runtime/source_mesh_bounds.json';all_bounds=json.loads(p.read_text())
 for name,clip in motion['clips'].items():
  rig.animation_data.action=bpy.data.actions[name]
  for idx in all_bounds[name]:
   s.frame_set(int(idx)+1);dg=bpy.context.evaluated_depsgraph_get();o=keyboard.evaluated_get(dg);me=o.to_mesh();pts=[conv@o.matrix_world@v.co for v in me.vertices];o.to_mesh_clear()
   all_bounds[name][idx]['Keyboard outer shell']=[[min(v[i] for v in pts) for i in range(3)],[max(v[i] for v in pts) for i in range(3)]]
 p.write_text(json.dumps(all_bounds))
 rig.animation_data.action=act;s.frame_set(1)
 bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v034.blend'))
 bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v031.blend'))
 r=bpy.data.objects['Boss002_Rig'];bpy.context.view_layer.update();correct_keyboard(r)
 for sc in bpy.data.scenes:sc['asset_version']='v034'
 bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v034.blend'))
 # Patch the matching static node transforms without touching geometry, UVs, skins or materials.
 glb=C/'enm_boss_monitor002_visual_top3d.glb';backup=D/'visual_before_grip.glb'
 if not backup.exists():shutil.copy2(glb,backup)
 raw=backup.read_bytes();length=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+length])
 group=next(n for n in doc['nodes'] if n.get('name')=='prop_socket.L' and 'children' in n)
 for idx in group['children']:
  node=doc['nodes'][idx];q=node.get('rotation',[0,0,0,1]);m=Matrix.LocRotScale(Vector(node.get('translation',[0,0,0])),Quaternion((q[3],q[0],q[1],q[2])),Vector(node.get('scale',[1,1,1])))
  m=grip_fix@m
  for key in ['translation','rotation','scale']:node.pop(key,None)
  node['matrix']=[m[row][col] for col in range(4) for row in range(4)]
 encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4);tail=raw[20+length:]
 glb.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
 (Q/'keyboard_grip_correction.json').write_text(json.dumps({'matrix':[list(row) for row in grip_fix],'reason':'Original static keyboard missed glove; corrected attachment only, all legacy bone animations retained.'},indent=2))
 contract=json.loads((B/'source/rig_contract_v031.json').read_text());contract.update(version='v034',export_signature=sig,activate={'fps':30,'start':1,'end':193,'duration_seconds':6.4,'root_motion':False})
 (B/'source/rig_contract_v034.json').write_text(json.dumps(contract,ensure_ascii=False,indent=2),encoding='utf-8')
 bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v034.blend'))
 print('ACTIVATE_SOURCE_OK',json.dumps({k:v for k,v in audit.items() if k not in ['source_bounds','old_actions_unchanged']}))
try:run()
except Exception:traceback.print_exc()
