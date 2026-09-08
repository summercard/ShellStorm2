import bpy
from mathutils import Vector
c=bpy.data.collections['116_二楼地板色彩深化_资产包'];p=bpy.data.collections.new('90_v019固定验收镜头');c.children.link(p)
for name,loc,target,scale in [('全景',(-11,-11,20),(4.6,10,7.2),22.0),('床前',(-7,-4,15),(.3,11.15,7.1),10.2),('沙发',(-1,-2,13),(6.25,11.65,7.4),10.0),('俯视',(5,10,30),(5,10,6),21.2)]:
 d=bpy.data.cameras.new('v019_'+name+'_固定验收');d.type='ORTHO';d.ortho_scale=scale;o=bpy.data.objects.new(d.name,d);p.objects.link(o);o.location=loc;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();o['preview_only']=True;o['preview_render']='Cycles / 48 samples / 1500x880 / no Freestyle / identical temporary warm-cool rig';o['exclude_from_game_export']=True
p.hide_viewport=True;p['用途']='固定参考镜头；原场景灯光和活动相机不变，不导出游戏';bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
