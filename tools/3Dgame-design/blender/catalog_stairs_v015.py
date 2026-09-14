"""Generate per-component source manifests and verify Collection ownership."""
import json
from pathlib import Path
import bpy
from mathutils import Vector

project = Path(__file__).resolve().parents[3]
target = project / 'source/art/whitebox/tower_zones/v015/data'
payload = json.loads((target / 'whitebox_tower_stairs_v015.json').read_text())
catalog = []
for index, record in enumerate(payload['components'], 1):
    slug = f'component_{index:03d}'
    collection = bpy.data.collections[record['name']]
    root = bpy.data.objects[record['name']]
    objects = list(collection.objects)
    meshes = [obj for obj in objects if obj.type == 'MESH']
    assert meshes and all(len(obj.users_collection) == 1 for obj in objects)
    points = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
    bounds = {'min': [min(p[i] for p in points) for i in range(3)],
              'max': [max(p[i] for p in points) for i in range(3)]}
    path = target / 'component_packages' / slug
    path.mkdir(parents=True, exist_ok=True)
    manifest = {
        'package_id': slug, 'asset_id': record['assetId'], 'name': record['name'],
        'category': record['group'], 'version': 'v015',
        'source_blend': str(Path(bpy.data.filepath).relative_to(project)),
        'collection': collection.name, 'root': root.name,
        'objects': [obj.name for obj in objects],
        'world_position': list(root.matrix_world.translation),
        'local_origin': [0, 0, 0], 'forward': '-Y', 'world_bounds': bounds,
        'local_transform': {key: record[key] for key in ('position', 'rotation', 'scale')},
        'settings': record.get('surfaceSettings', record.get('stairwellSettings')),
        'materials': sorted({mat.name for obj in meshes for mat in obj.data.materials}),
        'animation': False, 'lights': False, 'emission': False,
        'dependencies': ['assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'],
        'attachments': [], 'expected_export': None, 'collision': 'not_generated',
        'exported_to_godot': False,
    }
    (path / 'asset_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    catalog.append({'package': slug, 'name': record['name'], 'asset_id': record['assetId']})
assert len(catalog) == 130
(target / 'component_packages/catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
(target / 'component_packages/tree.txt').write_text('\n'.join(f"{item['package']}/asset_manifest.json  {item['name']}" for item in catalog) + '\n')
(target / 'package_verification.json').write_text(json.dumps({'passed': True, 'packages': 130, 'empty_packages': 0, 'multiple_ownership': 0}, indent=2) + '\n')
print('130 source component packages verified')
