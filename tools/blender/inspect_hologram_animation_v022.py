import bpy
from mathutils import Vector
def bounds():
 c=bpy.data.collections['51_圆形全息设备平台_资产包']; pts=[]
 for o in c.objects:
  if o.type=='MESH': pts += [o.matrix_world@Vector(p) for p in o.bound_box]
 return [[round(min(p[i] for p in pts),3) for i in range(3)],[round(max(p[i] for p in pts),3) for i in range(3)]]
for f in [1,48,120,240]: bpy.context.scene.frame_set(f); print('HOLO_FRAME',f,bounds())
