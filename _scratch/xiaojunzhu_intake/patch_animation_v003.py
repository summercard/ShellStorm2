import bpy,json,math,hashlib
from pathlib import Path
from mathutils import Vector,Quaternion
P=Path(__file__).parent
# Load definitions only; operate on actual v002 scene data, not regenerate unrelated Actions.
base=(P/'animate_zombie.py').read_text(encoding='utf-8').split('meta=[]')[0]
exec(base.replace("animation_v001.blend","animation_v003.blend"))
ref=(P/'refine_motion_v002.py').read_text(encoding='utf-8')
ref=ref.replace('chest=-21 if run else -14;stride=.25 if run else .15','chest=-32 if run else -14;stride=.36 if run else .15').replace('(.07 if run else', '(.105 if run else')
ref=ref.replace(" elif clip=='attack':", "  if run:\n   nod=-3+2*math.sin(phase-.8)\n   arm['L']=[(-.20,.72,-.50),(-.06,1,.02)]\n   arm['R']=[(.20,.70,-.50),(.06,1,-.03)]\n elif clip=='attack':")
exec(ref)
previous_solve=solve
# In this imported rig labels are reversed anatomically: +X is the character's left when facing +Y.
# User's marked character-right hand is negative X -> L_Hand in imported names.
attack_side='L'
def solve(clip,t):
 previous_solve(clip,t)
 if clip!='attack':return
 # Replace the entire attack body timing and attacking arm with a reachable 3D wrist arc.
 drive=track(t,[(0,0),(.18,-.45),(.32,-.6),(.43,.8),(.52,1),(.62,.7),(.80,.25),(1,0)])
 Q={}
 for pb in a.pose.bones:Q[pb.name]=pb.matrix.to_quaternion()@rest[pb.name].to_quaternion().inverted()
 Q['Waist']=rx(-8-8*max(0,drive))@rz(-12*drive);Q['Spine02']=rx(-13-11*max(0,drive))@rz(-25*drive);Q['Neck']=Q['Spine02']@rx(4);Q['Head']=Q['Neck']@rx(3)
 # Restore a quiet left arm rather than retaining the previous opposite-arm swipe.
 Q['R_Clavicle']=Q['Spine02'];Q['R_Upperarm']=Q['Spine02']@aim('R_Upperarm',(.25,.3,-.9));Q['R_Forearm']=Q['Spine02']@aim('R_Forearm',(.1,.95,-.2));Q['R_Hand']=Q['R_Forearm']@rx(18)
 Q['L_Clavicle']=Q['Spine02']
 hip=heads['Hip']+rest['Hip'].to_3x3()@a.pose.bones['Hip'].location
 apply_q(Q,hip)
 shoulder=a.pose.bones['L_Upperarm'].head.copy()
 # wind-up wrist rises beside shoulder; then projects forward and crosses through an arc.
 knots=[(0,(-.10,.19,-.17)),(.20,(-.20,.07,.15)),(.32,(-.17,.12,.20)),(.40,(-.13,.27,.10)),(.48,(.02,.31,-.015)),(.56,(.15,.22,-.12)),(.67,(.09,.16,-.19)),(.82,(-.04,.16,-.21)),(1,(-.10,.19,-.17))]
 delta=Vector(tuple(track(t,[(u,v[k]) for u,v in knots]) for k in range(3)));target=shoulder+delta
 n='L_Upperarm';k='L_Forearm';l1=(tails[n]-heads[n]).length;l2=(tails[k]-heads[k]).length;dist=min(delta.length,l1+l2-.002);axis=delta.normalized();pole=Vector((-.8,-.4,.35));pole=(pole-axis*pole.dot(axis)).normalized();d=(l1*l1-l2*l2+dist*dist)/(2*dist);elbow=shoulder+axis*d+pole*math.sqrt(max(0,l1*l1-d*d));target=shoulder+axis*dist
 Q[n]=aim(n,elbow-shoulder);Q[k]=aim(k,target-elbow);Q['L_Hand']=Q[k]@rx(track(t,[(0,15),(.3,-8),(.48,8),(.6,30),(1,15)]))
 for side in ['L','R']:
  for fi,finger in enumerate(['Thumb','Index','Middle','Pinky']):
   for j in [1,2]:Q[side+'_'+finger+str(j)]=Q[side+'_Hand']@rx((1 if side=='R' else -1)*(12+fi*3+j*9))
 apply_q(Q,hip)
 ev=m.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh();low=min((m.matrix_world@v.co).z for v in me.vertices);ev.to_mesh_clear()
 hip.z+=.002-low;apply_q(Q,hip)
meta=json.loads((P/'animation_meta_v002.json').read_text());fingerprints={}
def fingerprint(act):return hashlib.sha256(json.dumps([(fc.data_path,fc.array_index,[(list(k.co),k.interpolation) for k in fc.keyframe_points]) for fc in act.fcurves]).encode()).hexdigest()
for entry in meta['clips']:
 scene=bpy.data.scenes[entry['scene']];bpy.context.window.scene=scene;a=next(o for o in scene.objects if o.type=='ARMATURE');m=next(o for o in scene.objects if o.type=='MESH');act=a.animation_data.action
 if entry['id'] not in ['attack','running']:fingerprints[entry['id']]=fingerprint(act);continue
 new=bpy.data.actions.new(act.name.replace('_v002','_v003'));a.animation_data.action=new;new.use_fake_user=True
 previous_quaternions={}
 for f in range(entry['frames']+1):
  solve(entry['id'],f/entry['frames'])
  for pb in a.pose.bones:
   q=pb.rotation_quaternion.copy();q.normalize()
   if pb.name in previous_quaternions and q.dot(previous_quaternions[pb.name])<0:q.negate()
   pb.rotation_quaternion=q;previous_quaternions[pb.name]=q.copy()
  for pb in a.pose.bones:
   if pb.name=='Root':continue
   pb.keyframe_insert('rotation_quaternion',frame=f+1,group=pb.name)
   if pb.name=='Hip':pb.keyframe_insert('location',frame=f+1,group=pb.name)
 new.use_frame_range=True;new.frame_start=1;new.frame_end=entry['frames']+1;new.use_cyclic=entry['loop']
 for fc in new.fcurves:
  fc.extrapolation='CONSTANT'
  for key in fc.keyframe_points:key.interpolation='LINEAR'
  if entry['loop']:fc.modifiers.new('CYCLES')
 entry['action']=new.name;scene.frame_set(1)
# No extraneous superseded Actions in the new bundle.
used={e['action'] for e in meta['clips']}
for act in list(bpy.data.actions):
 if act.name not in used:bpy.data.actions.remove(act)
for entry in meta['clips']:
 if entry['id'] in fingerprints:assert fingerprint(bpy.data.actions[entry['action']])==fingerprints[entry['id']]
meta['animation']=str(out);meta['unchanged_action_hashes']=fingerprints;meta['anatomical_right_bone']='L_Hand (negative X; imported label reversed)'
bpy.context.window.scene=bpy.data.scenes[meta['clips'][3]['scene']];bpy.context.scene.frame_set(1);bpy.ops.wm.save_as_mainfile(filepath=str(out));(P/'animation_meta_v003.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2));print('V003_PATCH_OK unchanged_actions',len(fingerprints))
