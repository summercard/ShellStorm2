import bpy
from pathlib import Path
scene=bpy.context.scene; out=Path(bpy.data.filepath).parent
for light in bpy.data.lights:
 if light.type=='AREA': light.energy*=3.5
scene.view_settings.exposure=.2
scene.cycles.samples=40
cams=[bpy.data.objects[n] for n in ['参考镜头_全景','俯视结构','屋顶细节','立面施工细节','背面完整性']]
for i,cam in enumerate(cams):
 scene.camera=cam; scene.render.filepath=str(out/'previews'/('%02d_'%i+cam.name+'.png')); bpy.ops.render.render(write_still=True)
scene.camera=cams[0]; bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
