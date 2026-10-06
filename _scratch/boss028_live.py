import bpy
from pathlib import Path
r=bpy.data.objects['Boss002_Rig'];s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s;r.animation_data.action=bpy.data.actions['special_prepare'];s.frame_start=1;s.frame_end=37;s.frame_set(1)
for area in bpy.context.screen.areas:
 if area.type=='VIEW_3D':area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.overlay.show_overlays=False
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
print('v028 open; preview selected: special_prepare; MCP responding')
