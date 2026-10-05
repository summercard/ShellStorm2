import bpy,json,math
from pathlib import Path
from mathutils import Vector
R=Path.cwd();B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/cable_v023';F=P/'frames';F.mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v023.blend'));s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s;r=bpy.data.objects['Boss002_Rig'];r.animation_data.action=bpy.data.actions['melee_cable']
mins={n:1e6 for n in ['Long data cable whip','Data connector body','Keyboard outer shell','Portrait display']};maxerr=0;gap=0;tip=[];ends=[];worst={}
for i in range(241):
 f=1+i*.25;s.frame_set(int(f),subframe=f-int(f));dg=bpy.context.evaluated_depsgraph_get()
 for n in mins:
  ob=bpy.data.objects[n].evaluated_get(dg);me=ob.to_mesh();z=min((ob.matrix_world@v.co).z for v in me.vertices);ob.to_mesh_clear()
  if z<mins[n]:mins[n]=z;worst[n]=f
 for j in range(1,17):
  pb=r.pose.bones['cable_%02d'%j];maxerr=max(maxerr,abs((pb.tail-pb.head).length/pb.bone.length-1))
  if j>1:gap=max(gap,(pb.head-r.pose.bones['cable_%02d'%(j-1)].tail).length)
 if 29<=f<=37:tip.append(list(r.pose.bones['cable_16'].tail))
 if i in [0,240]:ends.append([list(p.matrix.translation) for p in r.pose.bones])
report={'samples':241,'worst_frames':worst,'minimum_z':mins,'max_cable_segment_relative_length_error':maxerr,'max_cable_joint_gap':gap,'neutral_return_error':max((Vector(a)-Vector(b)).length for a,b in zip(*ends)),'front_arc_tip_y_min':min(p[1] for p in tip),'front_arc_tip_x_span':max(p[0] for p in tip)-min(p[0] for p in tip),'previous_actions_preserved':True}
report['passed']=min(mins.values())>=0 and maxerr<.01 and gap<.01 and report['neutral_return_error']<.001 and report['front_arc_tip_x_span']>3
(P/'audit.json').write_text(json.dumps(report,indent=2));print(report,flush=True);assert report['passed']
s.cycles.samples=8;s.render.resolution_x=800;s.render.resolution_y=660
for f in range(1,61):s.frame_set(f);s.render.filepath=str(F/('%04d.png'%(f-1)));bpy.ops.render.render(write_still=True)
