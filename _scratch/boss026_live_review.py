import bpy,json
from pathlib import Path
B=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/bosses/enm_boss_monitor002');P=B/'previews/remaining_v026';s=bpy.context.scene;r=bpy.data.objects['Boss002_Rig']
bpy.ops.wm.save_as_mainfile(filepath='I:/工作项目/shellstrom2/ShellStorm2/_scratch/boss026_before_live_review.blend',copy=True)
spec=json.loads((P/'clips.json').read_text());checked=[]
for name,n in spec.items():
 r.animation_data.action=bpy.data.actions[name];s.frame_set(1);s.frame_set(n//2+1);s.frame_set(n+1);checked.append(name)
r.animation_data.action=bpy.data.actions['special_channel'];s.frame_start=1;s.frame_end=24;s.frame_set(7)
report={'connection':'BlenderMCP TCP 9876','file':bpy.data.filepath,'live_scene':s.name,'switched_and_evaluated':checked,'selected_action':'special_channel','frame':7}
(P/'live_mcp_review.json').write_text(json.dumps(report,indent=2));print(json.dumps(report))
