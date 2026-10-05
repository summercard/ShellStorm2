import bpy,json,math
from pathlib import Path
from mathutils import Vector
B=Path('assets/art/enemies/bosses/enm_boss_monitor002').resolve();P=B/'previews/cable_v025'
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v025.blend'));s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s;r=bpy.data.objects['Boss002_Rig']
records=[];offsets={x:[] for x in ['L','R']};body=[];maxgap=0;scales=[]
for f in range(1,62):
 s.frame_set(f);body.append(r.pose.bones['rear_axle'].matrix.translation.copy());row={'frame':f}
 for side in ['L','R']:
  last=r.pose.bones['arm_06.'+side];hand=r.pose.bones['hand.'+side];offsets[side].append(last.matrix.inverted()@hand.matrix)
  row[side]={'shoulder':list(r.pose.bones['arm_01.'+side].head),'wrist':list(hand.head)}
  for j in range(2,7):maxgap=max(maxgap,(r.pose.bones['arm_%02d.%s'%(j,side)].head-r.pose.bones['arm_%02d.%s'%(j-1,side)].tail).length)
  scales.append(r['stretch_'+side])
 records.append(row)
# Interior action has exact terminal inheritance; endpoint blends are separately covered by continuity audit.
drift={side:max((m.translation-offsets[side][10].translation).length for m in offsets[side][10:50]) for side in offsets}
span={side:max((Vector(a[side]['wrist'])-Vector(b[side]['wrist'])).length for a in records for b in records) for side in offsets}
report={'terminal_hand_local_translation_drift':drift,'arm_joint_gap':maxgap,'hand_travel_span':span,'body_translation_span':max((a-b).length for a in body for b in body),'method':'shoulder rotation drives fixed-length segments; wrist inherits last segment; no world hand targets','expected_faults':[],'runtime_tests':'not executed; Blender source only'}
report['passed']=max(drift.values())<.001 and maxgap<.001 and report['body_translation_span']<.3 and min(span.values())>.6
(P/'fk_quality_audit.json').write_text(json.dumps(report,indent=2));(P/'arm_trajectories.json').write_text(json.dumps(records,indent=2));print(report,flush=True);assert report['passed']
s.cycles.samples=12;s.render.resolution_x=960;s.render.resolution_y=800
for label,pos in [('front',(0,15,5)),('side',(15,0,5))]:
 s.camera.location=pos;s.camera.rotation_euler=(Vector((0,.5,2))-s.camera.location).to_track_quat('-Z','Y').to_euler()
 for f in [17,28,34]:s.frame_set(f);s.render.filepath=str(P/('%s_%03d.png'%(label,f)));bpy.ops.render.render(write_still=True)
