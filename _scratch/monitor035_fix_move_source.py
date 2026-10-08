import bpy,json
from pathlib import Path
from mathutils import Matrix
B=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/bosses/enm_boss_monitor002')
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v035.blend'))
d=json.loads((B/'components/enm_boss_monitor002/monitor_motion.json').read_text());r=bpy.data.objects['Boss002_Rig'];s=bpy.data.scenes['BOSS002_STUDIO'];r.animation_data.action=bpy.data.actions['move'];C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
for i,f in enumerate(d['clips']['move']['frames']):
 s.frame_set(i+1);values=f['bones'][d['bones'].index('monitor_tilt')];m=C.inverted()@Matrix([values[k:k+4] for k in range(0,16,4)])
 p=r.pose.bones['monitor_tilt'];p.matrix=m
 for path in ['location','rotation_quaternion','scale']:p.keyframe_insert(path,frame=i+1,group=p.name)
r.animation_data.action=bpy.data.actions['activate'];s.frame_set(1);bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v035.blend'));print('MOVE_SOURCE_BASELINE_FIXED')
