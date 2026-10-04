import bpy,math,json,hashlib
from pathlib import Path
from mathutils import Vector,Quaternion
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/idle_v008';P.mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v006.blend'))
s=bpy.data.scenes['BOSS002_SOURCE_TPOSE'];bpy.context.window.scene=s;rig=bpy.data.objects['Boss002_Rig'];ctrl=bpy.data.objects['ExpressionController'];s['asset_version']='v008'
for sc in bpy.data.scenes:sc.render.fps=30;sc.frame_start=1;sc.frame_end=96
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v008.blend'))
rig.animation_data_create();act=bpy.data.actions.new('idle');rig.animation_data.action=act;act.use_fake_user=True;act['loop_seconds']=3.2;act['usage']='Formal idle loop; frames 1..96, closure at 97. Root fixed.'
def set_world_axis(pb,axis,angle):
 local=pb.bone.matrix_local.to_3x3().inverted()@Vector(axis);pb.rotation_mode='QUATERNION';pb.rotation_quaternion=Quaternion(local,angle)
def pose(frame):
 t=(frame-1)/96*math.tau
 for p in rig.pose.bones:p.location=(0,0,0);p.rotation_mode='QUATERNION';p.rotation_quaternion=(1,0,0,0)
 for sign,side in [(1,'L'),(-1,'R')]:
  phase=t+(0 if side=='L' else .32);rig['stretch_'+side]=.98+.012*math.sin(phase)
  for i,angle in enumerate([.08,.11,.12,.10,.07,.03]):set_world_axis(rig.pose.bones['arm_%02d.%s'%(i+1,side)],(0,1,0),sign*(angle+.012*math.sin(phase-i*.18)))
  # Counter-rotate the wrist so the keyboard hangs vertically under the palm.
  set_world_axis(rig.pose.bones['hand_ctrl.'+side],(0,1,0),-sign*(.43+.02*math.sin(phase-.4)))
 for i in range(1,4):set_world_axis(rig.pose.bones['support_%02d'%i],(1,0,0),.006*math.sin(t-(i-1)*.08))
 # A loose outward cable loop: lift its lower arc without stretching the cable.
 for i,angle in enumerate([1.30,-.20,-.10,.05,.0]):set_world_axis(rig.pose.bones['cable_%02d'%(i+1)],(0,1,0),angle+.012*math.sin(t-i*.25))
 rig.update_tag();bpy.context.view_layer.update()
animated=['support_%02d'%i for i in range(1,4)]+['arm_%02d.%s'%(i,side) for side in ['L','R'] for i in range(1,7)]+['hand_ctrl.L','hand_ctrl.R']+['cable_%02d'%i for i in range(1,6)]
for f in range(1,98,4):
 pose(f)
 for n in animated:rig.pose.bones[n].keyframe_insert('rotation_quaternion',frame=f,group=n)
 for side in ['L','R']:rig.keyframe_insert(data_path='["stretch_'+side+'"]',frame=f,group='Spring length')
for fc in act.fcurves:
 for k in fc.keyframe_points:k.interpolation='BEZIER';k.handle_left_type='AUTO_CLAMPED';k.handle_right_type='AUTO_CLAMPED'
 fc.modifiers.new('CYCLES')
s.frame_set(1);bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v008.blend'))
c=json.loads((B/'source/rig_contract_v006.json').read_text());c.update(version='v008',formal_animations_authored=['idle'],idle={'fps':30,'start':1,'end':96,'closure':97,'duration_seconds':3.2},face_layout='restored exactly to v006');(B/'source/rig_contract_v008.json').write_text(json.dumps(c,indent=2),encoding='utf-8')
scene=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=scene;cam=scene.camera;cam.location=(3,12,4.5);cam.rotation_euler=(Vector((0,0,1.8))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=9.0;scene.cycles.samples=16;scene.render.resolution_x=960;scene.render.resolution_y=760;scene.frame_set(1);scene.render.filepath=str(P/'idle.png');bpy.ops.render.render(write_still=True)
# Sample actual evaluated geometry, including the held props, through the loop.
mins={};maxloop=0;rest={}
for f in range(1,98,4):
 scene.frame_set(f);dg=bpy.context.evaluated_depsgraph_get()
 for o in s.objects:
  if o.type!='MESH':continue
  e=o.evaluated_get(dg);me=e.to_mesh();vs=[e.matrix_world@v.co for v in me.vertices];e.to_mesh_clear();mins[o.name]=min(mins.get(o.name,999),min(v.z for v in vs))
  if f==1:rest[o.name]=vs
  if f==97:maxloop=max(maxloop,max((a-b).length for a,b in zip(vs,rest[o.name])))
report={'minimum_z':sorted(mins.items(),key=lambda x:x[1]),'loop_error':maxloop,'triangles':c['triangles'],'materials':len(bpy.data.materials)};(P/'pose_audit.json').write_text(json.dumps(report,indent=2));print('IDLE_AUDIT',json.dumps(report))
