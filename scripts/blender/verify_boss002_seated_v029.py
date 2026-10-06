import bpy,json,math,sys
from pathlib import Path
from mathutils import Vector
B=Path('assets/art/enemies/bosses/enm_boss_monitor002').resolve();P=B/'previews/seated_hands_v029';bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v029.blend'));s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s;r=bpy.data.objects['Boss002_Rig'];spec=json.loads((P/'clips.json').read_text());tip_local=Vector(json.loads((B/'previews/remaining_v026/old_actions.json').read_text())['tip_local']);report={};poses={}
for name,n in spec.items():
 r.animation_data.action=bpy.data.actions[name];mins={x:1e6 for x in ['Portrait display','Keyboard outer shell','Long data cable whip','Luminous data plug','Sculpted glove L','Sculpted glove R']};worst={};tip=[];gap=0;armgap=0;handpts={side:[] for side in ['L','R']};lengths={side:[] for side in ['L','R']}
 for i in range(n*2+1):
  f=1+i/2;s.frame_set(int(f),subframe=f-int(f));dg=bpy.context.evaluated_depsgraph_get()
  for obj in mins:
   o=bpy.data.objects[obj].evaluated_get(dg);me=o.to_mesh();z=min((o.matrix_world@v.co).z for v in me.vertices);o.to_mesh_clear()
   if z<mins[obj]:mins[obj]=z;worst[obj]=f
  for j in range(2,17):gap=max(gap,(r.pose.bones['cable_%02d'%j].head-r.pose.bones['cable_%02d'%(j-1)].tail).length)
  for side in ['L','R']:
   handpts[side].append(r.pose.bones['rear_axle'].matrix.inverted()@r.pose.bones['hand.'+side].head);lengths[side].append(sum(r.pose.bones['arm_%02d.%s'%(j,side)].length for j in range(1,7)))
   for j in range(2,7):armgap=max(armgap,(r.pose.bones['arm_%02d.%s'%(j,side)].head-r.pose.bones['arm_%02d.%s'%(j-1,side)].tail).length)
  if name=='special_channel':tip.append(r.pose.bones['cable_16'].matrix@tip_local)
  if i in [0,n*2]:poses[(name,i==0)]={p.name:p.matrix.copy() for p in r.pose.bones}
 report[name]={'min_z':mins,'worst_frames':worst,'max_cable_gap':gap,'max_arm_gap':armgap,'arm_length_range':{side:[min(vals),max(vals)] for side,vals in lengths.items()},'local_hand_travel':{side:max((a-b).length for a in pts for b in pts) for side,pts in handpts.items()},'passed':min(mins.values())>=-.005 and gap<.015 and armgap<.015}
 if tip:report[name]['tip_lock_drift']=max((p-tip[0]).length for p in tip);report[name]['passed'] &= report[name]['tip_lock_drift']<.003
pairs=[('stun_enter','stun_loop'),('stun_loop','stun_exit')]
report['joins']={a+' to '+b:max((poses[(a,False)][p].translation-poses[(b,True)][p].translation).length for p in poses[(a,False)]) for a,b in pairs}
report['loops']={a:max((poses[(a,False)][p].translation-poses[(a,True)][p].translation).length for p in poses[(a,False)]) for a in ['stun_loop']}
report['passed']=all(v['passed'] for k,v in report.items() if k in spec) and max(report['joins'].values())<.03 and max(report['loops'].values())<.003
(P/'audit.json').write_text(json.dumps(report,indent=2));print(json.dumps(report),flush=True)

if '--render' in sys.argv:
 s.cycles.samples=8;s.render.resolution_x=720;s.render.resolution_y=600
 for name,frames in {'stun_enter':[25,31,35,43],'stun_loop':[1,25],'stun_exit':[8,16,25]}.items():
  r.animation_data.action=bpy.data.actions[name]
  for f in frames:s.frame_set(f);s.render.filepath=str(P/(name+'_'+str(f)+'.png'));bpy.ops.render.render(write_still=True)
if '--sequence' in sys.argv:
 assert report['passed']
 s.cycles.samples=8;s.render.resolution_x=720;s.render.resolution_y=600
 for name,n in spec.items():
  r.animation_data.action=bpy.data.actions[name];d=P/name;d.mkdir(exist_ok=True)
  for f in range(1,n+1):s.frame_set(f);s.render.filepath=str(d/('%04d.png'%(f-1)));bpy.ops.render.render(write_still=True)
