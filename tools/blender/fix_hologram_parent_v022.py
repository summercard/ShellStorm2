import bpy, bmesh
from pathlib import Path
from mathutils import Matrix
ROOT=Path('/Users/summercards/ShellStorm2')
source=ROOT/'source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v022.blend'
derived=ROOT/'source/art/blender/base_facility_layout/export/v022/base_facility_runtime_layout_hq-v022-updated_packages.blend'
out=ROOT/'assets/art/environments/base_facility_3d/components/env_base99_remaining_facilities_v021/hologram_terminal_platform/hologram_terminal_platform_visual_top3d_v002.glb'
spinner=bpy.data.objects['51_全息悬浮形状_缓慢旋转']; bpy.context.scene.frame_set(1)
for o in [x for x in bpy.data.objects if x.parent==spinner]:
 current=o.matrix_world.copy(); desired=Matrix.Translation(-spinner.location)@current
 o.parent=None; o.matrix_world=desired; o.parent=spinner; o.matrix_parent_inverse=spinner.matrix_world.inverted(); o.matrix_world=desired
bpy.context.scene.frame_set(1); bpy.ops.wm.save_as_mainfile(filepath=str(source))
# Optimize only a temporary copy of the hologram meshes, then overwrite the current v002 GLB.
c=bpy.data.collections['51_圆形全息设备平台_资产包']
for o in c.objects:
 if o.type!='MESH': continue
 bm=bmesh.new(); bm.from_mesh(o.data); bm.normal_update(); nm=o.matrix_world.to_3x3().inverted().transposed()
 down=[f for f in bm.faces if (nm@f.normal).normalized().z < -0.65]
 if down:bmesh.ops.delete(bm,geom=down,context='FACES')
 bmesh.ops.triangulate(bm,faces=list(bm.faces)); bm.to_mesh(o.data); bm.free()
bpy.ops.wm.save_as_mainfile(filepath=str(derived))
bpy.ops.object.select_all(action='DESELECT')
for o in c.objects:o.select_set(True)
bpy.context.view_layer.objects.active=spinner
bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_yup=True,export_apply=False,export_animations=True,export_materials='EXPORT',export_image_format='NONE',export_lights=True,export_extras=True)
print('HOLOGRAM_V022_PARENT_FIXED')
