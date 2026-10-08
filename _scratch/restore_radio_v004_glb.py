import bpy
from pathlib import Path
P=Path('I:/工作项目/shellstrom2/ShellStorm2')
bpy.ops.wm.open_mainfile(filepath=str(P/'assets/art/props/base_world_3d/source/base99_radio/export/v004/prp_base99_radio_optimized_v004.blend'))
root=bpy.data.objects['ItemRoot']; bpy.ops.object.select_all(action='DESELECT')
selected=[root]+[o for o in root.children if o.type=='MESH']
assert len(selected)==4,[o.name for o in selected]
for o in selected:
    o.hide_set(False);o.select_set(True)
    if o.name.startswith('StatusLight'):o.name='StatusLight'
bpy.context.view_layer.objects.active=root
bpy.ops.export_scene.gltf(filepath=str(P/'outputs/base99_radio_v005/before_v004_visual.glb'),export_format='GLB',use_selection=True,export_apply=True,export_image_format='NONE',export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False)
print('V004_ROLLBACK_GLB_OK')
