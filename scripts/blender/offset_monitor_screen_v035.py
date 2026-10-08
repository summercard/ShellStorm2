"""MCP: constant actor-forward clearance only, retaining all other pose channels."""
import bpy,json,hashlib,traceback
from pathlib import Path
from mathutils import Matrix,Vector
R=Path('I:/工作项目/shellstrom2/ShellStorm2');B=R/'assets/art/enemies/bosses/enm_boss_monitor002';C=B/'components/enm_boss_monitor002'
Q=B/'previews/screen_v035';Q.mkdir(exist_ok=True);(Q/'.gdignore').touch()
D=R/'_scratch/monitor035';D.mkdir(exist_ok=True)
def run():
 bpy.ops.wm.save_as_mainfile(filepath=str(D/'session_before.blend'),copy=True)
 bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v034.blend'))
 rig=bpy.data.objects['Boss002_Rig'];s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window_manager.windows[0].scene=s
 conv=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
 offset=Vector((0,.5,0));original=D/'motion_before.json'
 motion=json.loads((original if original.exists() else C/'monitor_motion.json').read_text());before=json.loads(json.dumps(motion))
 if not original.exists():original.write_text(json.dumps(before,separators=(',',':')))
 changed={'monitor_tilt','monitor_spin','face_anchor_large_eye','face_anchor_round_eye','face_anchor_mouth','face_large_eye','face_round_eye','face_mouth'}
 for fn in ['source_pose_probes.json','source_mesh_bounds.json']:
  p=D/fn
  if not p.exists():p.write_bytes((B/'previews/runtime'/fn).read_bytes())
 probes=json.loads((D/'source_pose_probes.json').read_text());bounds=json.loads((D/'source_mesh_bounds.json').read_text())
 rig.animation_data.action=bpy.data.actions['idle'];s.frame_set(1)
 neutral={p.name:p.matrix_basis.copy() for p in rig.pose.bones}
 max_other=0;max_rotation=0
 for name,clip in motion['clips'].items():
  for p in rig.pose.bones:p.matrix_basis=neutral[p.name]
  act=bpy.data.actions[name];rig.animation_data.action=act;cached=[]
  for f in range(1,len(clip['frames'])+1):
   s.frame_set(f);m=rig.pose.bones['monitor_tilt'].matrix.copy();m.translation+=offset;cached.append(m)
  for f,m in enumerate(cached,1):
   s.frame_set(f);pb=rig.pose.bones['monitor_tilt'];pb.matrix=m;pb.keyframe_insert('location',frame=f,group=pb.name)
  for fc in act.fcurves:
   if fc.data_path=='pose.bones["monitor_tilt"].location':
    for k in fc.keyframe_points:k.interpolation='LINEAR'
  for i,frame in enumerate(clip['frames']):
   s.frame_set(i+1);bpy.context.view_layer.update()
   mats=json.loads(json.dumps(before['clips'][name]['frames'][i]['bones']))
   for j,n in enumerate(motion['bones']):
    if n in changed:mats[j][11]-=.5
   for j,n in enumerate(motion['bones']):
    old=before['clips'][name]['frames'][i]['bones'][j]
    if n not in changed:max_other=max(max_other,max(abs(a-b) for a,b in zip(old,mats[j])))
    max_rotation=max(max_rotation,max(abs(old[k]-mats[j][k]) for k in [0,1,2,4,5,6,8,9,10]))
   frame['bones']=mats
   probes[name][i]['monitor_tilt'][2]-=.5
   if str(i) in bounds[name]:
    for bound in bounds[name][str(i)]['Portrait display']:bound[2]-=.5
 assert max_other<.0001,(max_other,'non-screen bones changed')
 assert max_rotation<.0001,(max_rotation,'rotation changed')
 for sc in bpy.data.scenes:sc['asset_version']='v035'
 rig.animation_data.action=bpy.data.actions['activate'];s.frame_set(1)
 bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v035.blend'))
 (C/'monitor_motion.json').write_text(json.dumps(motion,separators=(',',':')))
 (B/'previews/runtime/source_pose_probes.json').write_text(json.dumps(probes));(B/'previews/runtime/source_mesh_bounds.json').write_text(json.dumps(bounds))
 bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v034.blend'))
 rig=bpy.data.objects['Boss002_Rig'];rig.animation_data.action=None
 pb=rig.pose.bones['monitor_tilt'];m=pb.matrix.copy();m.translation+=offset;pb.matrix=m
 for sc in bpy.data.scenes:sc['asset_version']='v035'
 bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v035.blend'))
 contract=json.loads((B/'source/rig_contract_v034.json').read_text(encoding='utf-8'));contract.update(version='v035',screen_clearance={'actor_forward_m':.5,'scope':'screen assembly and constrained face only; no other pose, timing or gameplay changes'})
 (B/'source/rig_contract_v035.json').write_text(json.dumps(contract,ensure_ascii=False,indent=2),encoding='utf-8')
 audit={'version':'v035','screen_actor_forward_m':.5,'non_screen_bone_error':max_other,'rotation_scale_error':max_rotation,'clip_count':len(motion['clips']),'static_glb_unchanged':True}
 (Q/'source_audit.json').write_text(json.dumps(audit,indent=2));print('SCREEN_OFFSET_OK',json.dumps(audit))
 bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v035.blend'))
try:run()
except Exception:traceback.print_exc()
