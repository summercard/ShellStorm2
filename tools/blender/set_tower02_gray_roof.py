import bpy,math
from pathlib import Path
out=Path(bpy.data.filepath).parent
changed=0
for obj in bpy.data.objects:
 if obj.type!='MESH' or not (obj.name.startswith('楼层_20_') or obj.name.startswith('屋顶核心模板_')): continue
 uv=obj.data.uv_layers['PaletteUV']
 for p in obj.data.polygons:
  if p.normal.z<.9: continue
  if obj.name.startswith('屋顶核心模板_') and p.center.z<88: continue
  for j,li in enumerate(p.loop_indices):
   t=2*math.pi*j/len(p.loop_indices); uv.data[li].uv=(.95+.026*math.cos(t),.45+.026*math.sin(t))
  changed+=1
scene=bpy.context.scene; scene['roof_color']='cool medium gray, shared palette row 6 column 10'
for name,power in [('主柔光',1900000),('补光',1100000),('轮廓',2100000)]: bpy.data.lights[name].energy=power*.28
scene.view_settings.exposure=.2; scene.cycles.samples=40
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
for i,name in enumerate(['参考镜头_全景','俯视结构','屋顶细节','立面施工细节','背面完整性']):
 scene.camera=bpy.data.objects[name]; scene.render.filepath=str(out/'previews'/('%02d_'%i+name+'.png')); bpy.ops.render.render(write_still=True)
scene.camera=bpy.data.objects['参考镜头_全景']; bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
print('GRAY_ROOF_FACES',changed)
