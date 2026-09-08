import bpy,json
from pathlib import Path
from mathutils import Vector
P=Path('/Users/summercards/ShellStorm2');R=P/'outputs/verification/base_facility_warehouse_v020'
c=bpy.data.collections.new('49_90_固定验收镜头_v020');bpy.data.collections['49_武器工作台与弹药附件_资产包'].children.link(c)
views=json.loads((R/'before_render.json').read_text())['views']
for name,loc,target,scale in views:
 d=bpy.data.cameras.new('仓库验收_'+name);d.type='ORTHO';d.ortho_scale=scale;o=bpy.data.objects.new(d.name,d);c.objects.link(o);o.location=loc;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();o['preview_only']=True
c.hide_viewport=True
for rec in json.loads((R/'catalog.json').read_text()):bpy.data.collections[rec['collection']]['当前状态']='仓库参考深化_结构与UV验收完成'
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
