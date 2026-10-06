import bpy,json,hashlib
from pathlib import Path
B=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/bosses/enm_boss_monitor002');P=B/'previews/seated_hands_v029';r=bpy.data.objects['Boss002_Rig'];s=bpy.data.scenes['BOSS002_STUDIO'];r.animation_data.action=bpy.data.actions['stun_loop'];rows=[]
for f in [1,13,25,37,49]:
 s.frame_set(f);item={'frame':f}
 for side in ['L','R']:
  o=bpy.data.objects['Sculpted glove '+side].evaluated_get(bpy.context.evaluated_depsgraph_get());me=o.to_mesh();item[side]=min((o.matrix_world@v.co).z for v in me.vertices);o.to_mesh_clear()
 rows.append(item)
def digest(a):return hashlib.sha256(repr([(f.data_path,f.array_index,[tuple(k.co) for k in f.keyframe_points]) for f in a.fcurves]).encode()).hexdigest()
old=json.loads((P/'preservation.json').read_text());unchanged=all(digest(bpy.data.actions[n])==h for n,h in old.items());report={'loop_palm_min_z':rows,'twelve_other_actions_unchanged':unchanged,'passed':unchanged and all(0<=v[side]<.025 for v in rows for side in ['L','R'])};(P/'palm_contact_audit.json').write_text(json.dumps(report,indent=2));s.frame_set(25);print(report)
