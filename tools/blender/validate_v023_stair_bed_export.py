import bpy
import json
from pathlib import Path

TARGETS = {
    'northwest_l_stair': '14_西北贴墙L型楼梯_资产包',
    'loft_bed_and_bedding': '31__02_游戏输出_整合模型',
}

def is_visual_mesh(obj):
    return obj.type == 'MESH' and not obj.name.startswith('COLLISION_')

report = {'file': bpy.data.filepath, 'packages': {}}
for slug, collection_name in TARGETS.items():
    collection = bpy.data.collections[collection_name]
    meshes = [obj for obj in collection.all_objects if is_visual_mesh(obj)]
    assert meshes, f'{slug} has no exported visual mesh'
    details = []
    for obj in meshes:
        mesh = obj.data
        assert [layer.name for layer in mesh.uv_layers] == ['PaletteUV'], f'{obj.name} has legacy UV layers'
        assert mesh.uv_layers.active.name == 'PaletteUV' and mesh.uv_layers['PaletteUV'].active_render, f'{obj.name} PaletteUV inactive'
        for polygon in mesh.polygons:
            uv = [mesh.uv_layers['PaletteUV'].data[index].uv for index in polygon.loop_indices]
            area = abs(sum(uv[i].x * uv[(i + 1) % len(uv)].y - uv[(i + 1) % len(uv)].x * uv[i].y for i in range(len(uv)))) * 0.5
            assert area > 0.0000001, f'{obj.name} contains a point PaletteUV island'
            cell_x, cell_y = int(uv[0].x * 10), int(uv[0].y * 10)
            assert all(int(item.x * 10) == cell_x and int(item.y * 10) == cell_y for item in uv), f'{obj.name} PaletteUV crosses color cells'
        details.append({'name': obj.name, 'triangles': len(mesh.polygons), 'materials': len(mesh.materials)})
    report['packages'][slug] = {'collection': collection_name, 'visual_meshes': details}
print('BASE99_V023_STAIR_BED_VALID=' + json.dumps(report, ensure_ascii=False))
