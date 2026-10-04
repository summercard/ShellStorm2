import bpy
from pathlib import Path
from mathutils import Vector
B=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/bosses/enm_boss_monitor002');bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v009.blend'));s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s;s.frame_set(49);cam=s.camera;rig=bpy.data.objects['Boss002_Rig'];s.cycles.samples=12;s.render.resolution_x=800;s.render.resolution_y=700
for side in ['L','R']:
 p=rig.pose.bones['hand.'+side].head;cam.location=p+Vector((1.5,-3,1));cam.rotation_euler=(p+Vector((.2 if side=='L' else -.2,0,-.15))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=1.8;s.render.filepath=str(B/('previews/idle_v009/grip_back_'+side+'.png'));bpy.ops.render.render(write_still=True)
