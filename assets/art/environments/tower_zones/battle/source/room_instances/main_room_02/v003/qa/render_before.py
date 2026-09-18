import bpy
from pathlib import Path
ROOT=Path('/Users/summercards/ShellStorm2'); OUT=ROOT/'assets/art/environments/tower_zones/battle/source/room_instances/main_room_02/v003'
final=OUT/'env_battle_l01_main_02_data_room_layout_source_v003.blend'
bpy.ops.wm.open_mainfile(filepath=str(final))
scene=bpy.context.scene
# Same saved camera, lights, world, color transform, resolution and sampling.
for c in bpy.data.collections:
    if c.name.startswith(('01_制作组件','02_游戏输出')): c.hide_render=True
with bpy.data.libraries.load(str(OUT/'qa/制作前工作区备份.blend'),link=False) as (src,dst):
    dst.objects=[n for n in src.objects if n.startswith(('WALL_','FLOOR_'))]
for o in dst.objects:
    scene.collection.objects.link(o)
    o.hide_render=o.name.startswith(('WALL_SOUTH','WALL_WEST'))
scene.camera=bpy.data.objects['01_参考构图_剖切全景']
scene.render.filepath=str(OUT/'renders/00_同镜头制作前.png')
bpy.ops.render.render(write_still=True)
