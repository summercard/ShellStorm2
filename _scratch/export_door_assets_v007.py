import bpy
from pathlib import Path

ROOT = Path(r'I:/工作项目/shellstrom2/ShellStorm2')
SRC = ROOT / 'assets/art/environments/tower_zones/battle/source/common_components/v007/env_battle_common_components_source_v007.blend'
OUT = ROOT / 'assets/art/environments/tower_zones/battle/components/common_components'
bpy.ops.wm.open_mainfile(filepath=str(SRC))
for coll_name, slug in [('wall_door_5m_通用包','wall_door_5m'), ('door_5m_通用包','door_5m')]:
    coll = bpy.data.collections[coll_name]
    objects = [o for o in coll.all_objects if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    target = OUT / slug / f'{slug}_visual_top3d.glb'
    target.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(target), export_format='GLB', use_selection=True, export_apply=True, export_materials='EXPORT', export_cameras=False, export_lights=False)
    print('EXPORTED', target)
print('DOOR_ASSET_EXPORT_V007_OK')
