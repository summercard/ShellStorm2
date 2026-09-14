import json, math, os, sys
import bpy

output_json, model_dir, scene_id, source_name = sys.argv[sys.argv.index('--') + 1:]
os.makedirs(model_dir, exist_ok=True)

def has_mesh(root):
    return root.type == 'MESH' or any(child.type == 'MESH' for child in root.children_recursive)

packages = []
for collection in bpy.data.collections:
    if not collection.name.endswith('资产包'):
        continue
    roots = [obj for obj in collection.objects if obj.parent is None and has_mesh(obj)]
    for root in roots:
        packages.append((collection, root))

if not packages:
    packages = [(None, obj) for obj in bpy.context.scene.objects if obj.parent is None and has_mesh(obj)]
if not packages:
    raise RuntimeError('文件中没有可作为组件根的网格或父级对象')

components = []
for index, (collection, root) in enumerate(packages, 1):
    if collection and collection.name.startswith('楼梯A_'):
        component_name = 'Stair_A'
    elif collection and collection.name.startswith('楼梯B_'):
        component_name = 'Stair_B'
    else:
        component_name = root.name
    filename = f'model_{index:03d}.glb'
    transform = (root.location.copy(), root.rotation_euler.copy(), root.scale.copy())
    root.location = (0, 0, 0); root.rotation_euler = (0, 0, 0); root.scale = (1, 1, 1)
    bpy.ops.object.select_all(action='DESELECT')
    hierarchy = [root] + list(root.children_recursive)
    for obj in hierarchy: obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=os.path.join(model_dir, filename), export_format='GLB', use_selection=True, export_yup=True, export_image_format='NONE')
    root.location, root.rotation_euler, root.scale = transform
    components.append({
        'name': component_name, 'type': 'Blender模型', 'group': None,
        'position': dict(zip('xyz', transform[0])),
        'rotation': dict(zip('xyz', [math.degrees(value) for value in transform[1]])),
        'scale': dict(zip('xyz', transform[2])),
        'blenderSettings': {'rootObject': root.name, 'assetCollection': collection.name if collection else None, 'modelFile': filename}
    })

payload = {
    'version': 3, 'coordinateSystem': 'blender-z-up',
    'axes': {'right': 'X', 'forward': '-Y', 'up': 'Z'}, 'units': {'distance': 'm', 'rotation': 'deg'},
    'name': scene_id, 'groups': [], 'components': components,
    'blenderSource': {'mode': 'bidirectional', 'sourceFile': source_name, 'managedRootObjects': [item['blenderSettings']['rootObject'] for item in components]}
}
with open(output_json, 'w', encoding='utf-8') as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
