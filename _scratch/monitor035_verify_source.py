import bpy,json
from pathlib import Path
from mathutils import Matrix
B=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/bosses/enm_boss_monitor002');d=json.loads((B/'components/enm_boss_monitor002/monitor_motion.json').read_text());r=bpy.data.objects['Boss002_Rig'];s=bpy.data.scenes['BOSS002_STUDIO'];C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)));out={}
for name in ['activate','idle','move','heavy_spin_slam']:
 r.animation_data.action=bpy.data.actions[name];error=0
 for f in [0,len(d['clips'][name]['frames'])//2,len(d['clips'][name]['frames'])-1]:
  s.frame_set(f+1)
  for n in ['monitor_tilt','monitor_spin','face_large_eye','face_round_eye','face_mouth']:
   actual=[v for row in C@r.pose.bones[n].matrix for v in row];ref=d['clips'][name]['frames'][f]['bones'][d['bones'].index(n)];error=max(error,max(abs(a-b) for a,b in zip(actual,ref)))
 out[name]=error
print(json.dumps(out));(B/'previews/screen_v035/source_runtime_check.json').write_text(json.dumps(out,indent=2))
