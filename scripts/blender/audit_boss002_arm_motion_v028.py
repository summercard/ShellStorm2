import bpy,json,math,hashlib
from pathlib import Path
B=Path('assets/art/enemies/bosses/enm_boss_monitor002').resolve();P=B/'previews/arms_v028';bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v028.blend'));r=bpy.data.objects['Boss002_Rig'];s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s;spec=json.loads((P/'clips.json').read_text());report={}
for name,n in spec.items():
 r.animation_data.action=bpy.data.actions[name];pts={side:[] for side in ['L','R']};scales=[]
 for step in range(n*4+1):
  f=1+step/4;s.frame_set(int(f),subframe=f-int(f))
  for side in ['L','R']:
   pts[side].append(r.pose.bones['hand.'+side].matrix.translation.copy());scales.extend(r.pose.bones['hand.'+side].matrix.to_scale())
 report[name]={'max_quarter_frame_hand_step':{side:max((a-b).length for a,b in zip(p,p[1:])) for side,p in pts.items()},'hand_scale_range':[min(scales),max(scales)]}
# Non-arm visual/body/face tracks retain exact old data.
allowed=['arm_','hand_ctrl.','cable_'];unchanged={}
for name in spec:
 a=bpy.data.actions[name];old=bpy.data.actions['ARCHIVE_'+name+'_v027']
 def bodytracks(act):return [(f.data_path,f.array_index,[tuple(k.co) for k in f.keyframe_points]) for f in act.fcurves if not any(x in f.data_path for x in allowed+['stretch_'])]
 unchanged[name]=bodytracks(a)==bodytracks(old)
report['body_face_fx_tracks_unchanged']=unchanged;report['passed']=all(unchanged.values()) and all(max(v['max_quarter_frame_hand_step'].values())<.4 and v['hand_scale_range'][1]<1.01 and v['hand_scale_range'][0]>.99 for k,v in report.items() if k in spec)
(P/'motion_audit.json').write_text(json.dumps(report,indent=2));print(json.dumps(report),flush=True)
