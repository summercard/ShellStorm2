import bpy,addon_utils,json
from pathlib import Path
addon_utils.enable('addon',default_set=False,persistent=False)
def boot():
 try:
  bpy.context.scene.blendermcp_port=9876
  if not getattr(bpy.types,'blendermcp_server',None):bpy.ops.blendermcp.start_server()
  s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s
  for area in bpy.context.screen.areas:
   if area.type=='VIEW_3D':
    area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.shading.type='MATERIAL';area.spaces.active.overlay.show_overlays=False
  Path('I:/工作项目/shellstrom2/ShellStorm2/_scratch/boss026_gui_status.json').write_text(json.dumps({'filepath':bpy.data.filepath,'scene':s.name,'port':9876}))
 except Exception as e:print('MCP_BOOT_ERROR',e)
 return None
bpy.app.timers.register(boot,first_interval=2)
