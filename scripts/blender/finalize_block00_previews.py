import bpy
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2];O=R/'assets/art/environments/master_office_3d/source/env_block00_story_rooms/v001';S=bpy.context.scene
cam=bpy.data.objects['工业雕塑近景'];cam.location=(-10,3,9);cam.rotation_euler=(Vector((-15,-2.95,3))-cam.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.wm.save_as_mainfile(filepath=str(O/'env_block00_story_rooms_source_v001.blend'))
root=bpy.context.view_layer.layer_collection.children['98F剧情房间_中文资产管理'].children['02_游戏输出_实例布局']
for room in root.children:
 room.exclude=not room.name.endswith('meeting_room')
 for child in room.children:child.exclude=True
S.camera=cam;S.render.resolution_x=1500;S.render.resolution_y=1100;S.render.filepath=str(O/'preview_sculpture.png');bpy.ops.render.render(write_still=True)
