import bpy,math
from pathlib import Path
c=bpy.data.collections['36_墨绿三人休闲沙发_资产包']
for o in c.all_objects:
 if o.type!='MESH':continue
 ids=set();u=o.data.uv_layers['PaletteUV']
 for p in o.data.polygons:
  a=u.data[p.loop_start].uv;col=math.floor(a.x*10);row=math.floor(a.y*10)
  if row==7 and col in [7,8]:ids.update(p.vertices)
 for i in ids:
  v=o.data.vertices[i];world=o.matrix_world@v.co
  if 5.3<world.x<6.6 and 11.05<world.y<12.5:
   t=max(0,min(1,(world.z-6.35)/.35));world.y-=.05*t;world.z+=.065*t;v.co=o.matrix_world.inverted()@world
 o.data.update()
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
