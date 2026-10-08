import bpy
from pathlib import Path
from mathutils import Vector
s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window_manager.windows[0].scene=s
s.camera.location=(3,12,4.4);s.camera.rotation_euler=(Vector((0,0,1.9))-s.camera.location).to_track_quat('-Z','Y').to_euler();s.camera.data.ortho_scale=9.4
p=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/bosses/enm_boss_monitor002/previews/move_v033/studio_frames');p.mkdir(exist_ok=True)
for f in range(1,49):
 s.frame_set(f);s.render.filepath=str(p/('%04d.png'%(f-1)));bpy.ops.render.render(write_still=True)
s.frame_set(13)
print('STUDIO_SEQUENCE_OK_48')
