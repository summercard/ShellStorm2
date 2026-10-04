import bpy
from pathlib import Path
from mathutils import Vector
pkg=Path(r'I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/normal_enemy_3d/fat_zombie03')
qa=pkg/'previews/locomotion_v003'
bpy.ops.wm.open_mainfile(filepath=str(pkg/'source/animation/enm_normal_fat_zombie03_animation_v003.blend'))
s=bpy.context.scene
a=next(o for o in s.objects if o.type=='ARMATURE')
s.render.engine='BLENDER_EEVEE_NEXT';s.render.resolution_x=480;s.render.resolution_y=480;s.render.resolution_percentage=100
if not s.world:s.world=bpy.data.worlds.new('PreviewWorld')
s.world.color=(.16,)*3
for loc in [(3,4,5),(-3,-1,4)]:
 bpy.ops.object.light_add(type='AREA',location=loc);bpy.context.object.data.energy=500;bpy.context.object.data.size=4
bpy.ops.object.camera_add();cam=bpy.context.object;s.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=4
for name,end in [('walking',60),('running',36)]:
 a.animation_data.action=bpy.data.actions[name]
 for view,pos in [('three_quarter',(4,7,4)),('top',(0,0,8)),('side',(7,0,2))]:
  cam.location=pos;cam.rotation_euler=(Vector((0,0,1.3))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=5.2
  for f in range(0,end,2):
   s.frame_set(f);s.render.filepath=str(qa/f'{name}_{view}_{f:03d}.png');bpy.ops.render.render(write_still=True)
print('FAT_ZOMBIE03_PREVIEWS_OK',flush=True)
