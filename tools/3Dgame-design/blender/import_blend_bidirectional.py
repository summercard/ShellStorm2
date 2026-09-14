import json, math, os, sys
import bpy

output_json, model_dir, scene_id, source_name = sys.argv[sys.argv.index('--') + 1:]
os.makedirs(model_dir, exist_ok=True)

native=bpy.data.texts.get('3Dgame-design.scene.json')
if native:
    payload=json.loads(native.as_string())
    payload['name']=scene_id
    for category in ('groups','components'):
        kept=[]
        for record in payload.get(category,[]):
            obj=bpy.data.objects.get(record['name'])
            if obj is None: continue
            record['position']=dict(zip('xyz',obj.location))
            record['rotation']=dict(zip('xyz',[math.degrees(v) for v in obj.rotation_euler]))
            record['scale']=dict(zip('xyz',obj.scale))
            kept.append(record)
        payload[category]=kept
    payload.pop('blenderSource',None)
    payload['editorSettings']={'snapping':False,'grounding':False,'collision':False}
    with open(output_json,'w',encoding='utf-8') as handle: json.dump(payload,handle,ensure_ascii=False,indent=2)
    print('Native component scene restored')
    sys.exit(0)

def has_mesh(root):
    return root.type == 'MESH' or any(child.type == 'MESH' for child in root.children_recursive)

packages = []
for collection in bpy.data.collections:
    if not (collection.get('3dgame_component_package') or collection.name.endswith(('资产包', '组件包'))):
        continue
    component_children = [child for child in collection.children if child.get('3dgame_component')]
    if component_children:
        for child in component_children:
            declared_root = bpy.data.objects.get(child.get('component_root', ''))
            if declared_root and has_mesh(declared_root):
                packages.append((child, declared_root, collection.name))
        continue
    declared_root = bpy.data.objects.get(collection.get('component_root', ''))
    roots = [declared_root] if declared_root and has_mesh(declared_root) else [obj for obj in collection.objects if obj.parent is None and has_mesh(obj)]
    for root in roots:
        packages.append((collection, root, None))

if not packages:
    packages = [(None, obj, None) for obj in bpy.context.scene.objects if obj.parent is None and has_mesh(obj)]
if not packages:
    raise RuntimeError('文件中没有可作为组件根的网格或父级对象')

components = []
for index, (collection, root, group_name) in enumerate(packages, 1):
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
        'name': collection.get('3dgame_component_category', component_name) if collection else component_name,
        'type': 'Blender模型', 'group': group_name,
        'position': dict(zip('xyz', transform[0])),
        'rotation': dict(zip('xyz', [math.degrees(value) for value in transform[1]])),
        'scale': dict(zip('xyz', transform[2])),
        'blenderSettings': {'rootObject': root.name, 'assetCollection': collection.name if collection else None, 'modelFile': filename}
    })

payload = {
    'version': 3, 'coordinateSystem': 'blender-z-up',
    'axes': {'right': 'X', 'forward': '-Y', 'up': 'Z'}, 'units': {'distance': 'm', 'rotation': 'deg'},
    'name': scene_id,
    'groups': [{'name': name, 'position': {'x': 0, 'y': 0, 'z': 0}, 'rotation': {'x': 0, 'y': 0, 'z': 0}, 'scale': {'x': 1, 'y': 1, 'z': 1}} for name in dict.fromkeys(group for _, _, group in packages if group)],
    'components': components,
    'editorSettings': {'snapping': False, 'grounding': False, 'collision': False},
    'blenderSource': {'mode': 'bidirectional', 'sourceFile': source_name, 'managedRootObjects': [item['blenderSettings']['rootObject'] for item in components]}
}
with open(output_json, 'w', encoding='utf-8') as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
