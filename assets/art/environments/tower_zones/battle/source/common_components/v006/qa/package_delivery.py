import bpy,json,shutil
from pathlib import Path
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view
ROOT=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/environments/tower_zones/battle/source/common_components/v006')
OUT=Path('I:/工作项目/shellstrom2/outputs/door_anchor_v006')
master=bpy.context.scene
sc=bpy.data.scenes['101_门扇正立面_底部中心'];bpy.context.window.scene=sc;bpy.context.view_layer.update()
assert sc.camera.parent is None and not sc.camera.constraints
sc.camera.matrix_world=sc.camera.matrix_basis.copy()
p=world_to_camera_view(sc,sc.camera,Vector((0,0,0)))
bpy.context.window.scene=master;bpy.context.view_layer.update()
(OUT/'anchor_projection.json').write_text(json.dumps({'x':p.x*1400,'y':(1-p.y)*1400,'origin_world':[0,0,0],'camera':sc.camera.name},ensure_ascii=False,indent=2),encoding='utf-8')
for name in ['anchor_and_door_validation.json','door_scope_validation.json','full_library_validation.json']:shutil.copy2(ROOT/'qa'/name,OUT/name)
# save_as remaps external paths for the delivery folder; raw copy would break relative palette references.
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'战局区块_通用组件库_v006.blend'),copy=True,relative_remap=True,check_existing=False)
print('DELIVERY_COPY_OK')
