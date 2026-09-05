import bpy,os
out=os.path.dirname(bpy.data.filepath)
s=bpy.context.scene
for cam,fn,res in [('验收_参考轴测','01_参考轴测',(1400,1250)),('验收_正视','02_正视',(1500,1100)),('验收_俯视','03_俯视',(1300,1200)),('验收_家具近景','04_家具近景',(1400,1300))]:
 s.camera=bpy.data.objects[cam];s.render.resolution_x=res[0];s.render.resolution_y=res[1];s.render.filepath=out+'/renders/'+fn+'.png'
 bpy.ops.render.render(write_still=True)
