import bpy, bmesh, json, hashlib, re
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'source/art/blender/base_facility_layout'
source = max((BASE / 'source').glob('base_facility_runtime_layout_hq_v[0-9]*.blend'), key=lambda p: int(re.search(r'v(\d+)\.blend$', p.name)[1]))
version = re.search(r'v\d+(?=\.blend$)', source.name)[0]
slug = 'base_camp_rollup_main_door'
folder = ROOT / 'assets/art/environments/base_facility_3d/components/env_base99_remaining_facilities_v021' / slug
glb = folder / (slug + '_visual_top3d_v002.glb')
derived = BASE / 'export' / version / ('base_facility_runtime_layout_hq-' + version + '-rollup_main_door.blend')
palette = ROOT / 'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
source_hash = sha(source)
bpy.ops.wm.open_mainfile(filepath=str(source))
package = bpy.data.collections['42_BASE_CAMP大型卷帘主门_资产包']
objects = [o for o in package.all_objects if o.type == 'MESH' and not o.name.startswith('COLLISION_')]
scene = bpy.data.scenes.new('卷帘主门_导出')
bpy.context.window.scene = scene
collection = bpy.data.collections.new('02_游戏输出_整合模型')
scene.collection.children.link(collection)
copies = []
materials = {}
before = after = 0
for original in objects:
    mesh = bpy.data.meshes.new_from_object(original.evaluated_get(bpy.context.evaluated_depsgraph_get()), preserve_all_data_layers=True, depsgraph=bpy.context.evaluated_depsgraph_get())
    mesh.transform(original.matrix_world)
    obj = bpy.data.objects.new(original.name, mesh)
    collection.objects.link(obj)
    copies.append(obj)
    for i, material in enumerate(mesh.materials):
        if material.name not in materials:
            copy = material.copy()
            materials[material.name] = copy
            for node in copy.node_tree.nodes:
                if node.type == 'TEX_IMAGE':
                    node.image = bpy.data.images.load(str(palette), check_existing=True)
                    node.interpolation = 'Closest'
                if node.type == 'UVMAP': node.uv_map = 'PaletteUV'
        mesh.materials[i] = materials[material.name]
    assert mesh.uv_layers.get('PaletteUV'), original.name
    for layer in list(mesh.uv_layers):
        if layer.name != 'PaletteUV': mesh.uv_layers.remove(layer)
    mesh.uv_layers.active = mesh.uv_layers['PaletteUV']
    mesh.uv_layers.active.active_render = True
    bm = bmesh.new(); bm.from_mesh(mesh)
    bmesh.ops.triangulate(bm, faces=list(bm.faces)); bm.normal_update()
    before += len(bm.faces)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.normal.z < -0.65], context='FACES_ONLY')
    after += len(bm.faces)
    bm.to_mesh(mesh); bm.free()
for old in list(bpy.data.scenes):
    if old != scene: bpy.data.scenes.remove(old)
for old in list(bpy.data.objects):
    if old not in copies: bpy.data.objects.remove(old, do_unlink=True)
for old in list(bpy.data.collections):
    if old != collection: bpy.data.collections.remove(old)
bpy.context.view_layer.update()
points = [o.matrix_world @ v.co for o in copies for v in o.data.vertices]
minimum = [min(v[i] for v in points) for i in range(3)]
maximum = [max(v[i] for v in points) for i in range(3)]
derived.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(derived))
bpy.ops.wm.open_mainfile(filepath=str(derived))
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=str(glb), export_format='GLB', use_selection=True, export_image_format='NONE', export_lights=False, export_cameras=False, export_yup=True)
report = dict(package=package.name if False else '42_BASE_CAMP大型卷帘主门_资产包', source=str(source.relative_to(ROOT)), source_sha256=source_hash, derived=str(derived.relative_to(ROOT)), glb=str(glb.relative_to(ROOT)), glb_sha256=sha(glb), triangles_before=before, triangles_after=after, bbox_min=minimum, bbox_max=maximum, mesh_count=len(copies))
(derived.parent / 'rollup_main_door_manifest.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
assert sha(source) == source_hash
print('ROLLUP_REPORT=' + json.dumps(report, ensure_ascii=False))
