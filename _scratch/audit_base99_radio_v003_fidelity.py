import bpy
import hashlib
import json
import math
from pathlib import Path
from mathutils import Vector

P = Path('I:/工作项目/shellstrom2/ShellStorm2')
OUT = P / 'outputs/base99_radio_v003'
S = P / 'assets/art/props/base_world_3d/source/base99_radio'
PALETTE = P / 'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
paths = {'v002': S / 'prp_base99_radio_source_v002.blend', 'source': S / 'prp_base99_radio_source_v003.blend', 'optimized': S / 'export/v003/prp_base99_radio_optimized_v003.blend'}
protected = list(paths.values()) + [S / 'prp_base99_radio_source_v001.blend', PALETTE]
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
before = {str(p): sha(p) for p in protected}

def snapshot(path):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    bpy.context.view_layer.update()
    root = bpy.data.objects['ItemRoot']
    outputs = [o for o in root.children if o.type == 'MESH']
    components = [o for o in bpy.data.collections['01_制作组件_已统一材质'].all_objects if o.type == 'MESH']
    def world_matrix(obj):
        if obj.parent is None:
            return obj.matrix_basis
        return world_matrix(obj.parent) @ obj.matrix_parent_inverse @ obj.matrix_basis
    def data(objects):
        result = {}
        for o in objects:
            matrix = world_matrix(o)
            result[o.name] = {'points': [list(matrix @ v.co) for v in o.data.vertices], 'polygons': [list(f.vertices) for f in o.data.polygons], 'scale': list(o.scale)}
        return result
    return {'output': data(outputs), 'components': data(components), 'root_scale': list(root.scale)}

snapshots = {key: snapshot(path) for key, path in paths.items()}

def bounds(data):
    points = [v for d in data.values() for v in d['points']]
    lo = [min(p[i] for p in points) for i in range(3)]
    hi = [max(p[i] for p in points) for i in range(3)]
    return {'min': lo, 'max': hi, 'size': [hi[i] - lo[i] for i in range(3)]}

checks = {}
for group in ['output', 'components']:
    old, new = snapshots['v002'][group], snapshots['source'][group]
    b0, b1 = bounds(old), bounds(new)
    pivot = [(b0['min'][0] + b0['max'][0]) / 2, (b0['min'][1] + b0['max'][1]) / 2, b0['min'][2]]
    assert old.keys() == new.keys()
    error = 0.0
    for name in old:
        assert old[name]['polygons'] == new[name]['polygons']
        for a, b in zip(old[name]['points'], new[name]['points'], strict=True):
            error = max(error, max(abs(b[i] - (pivot[i] + 2 * (a[i] - pivot[i]))) for i in range(3)))
    print('SCALE_GROUP', group, 'OLD', b0, 'NEW', b1, 'ERROR', error, flush=True)
    assert error < 1e-6
    checks[group] = {'v002_bounds': b0, 'v003_bounds': b1, 'axis_ratios': [b1['size'][i] / b0['size'][i] for i in range(3)], 'maximum_world_vertex_error_m': error, 'topology_unchanged': True, 'passed': True}
assert snapshots['source'] == snapshots['optimized']
assert snapshots['source']['root_scale'] == [1.0, 1.0, 1.0]
assert all(max(abs(s - 1) for s in o['scale']) < 1e-6 for o in snapshots['source']['output'].values())

# 制作组件与游戏输出沿用v002既有整合归一化，记录真实包络差异，不冒称两者原始坐标相同。
c = bounds(snapshots['source']['components'])
o = bounds(snapshots['source']['output'])
axis_scale = [o['size'][i] / c['size'][i] for i in range(3)]
component_points = [v for d in snapshots['source']['components'].values() for v in d['points']]
output_points = [v for d in snapshots['source']['output'].values() for v in d['points']]
normalized_points = [[o['min'][i] + (v[i] - c['min'][i]) * axis_scale[i] for i in range(3)] for v in component_points]
component_to_output_error = max(min(max(abs(a[i] - b[i]) for i in range(3)) for b in output_points) for a in normalized_points)
output_to_component_error = max(min(max(abs(a[i] - b[i]) for i in range(3)) for b in normalized_points) for a in output_points)
assert max(component_to_output_error, output_to_component_error) < 1e-6
normalization = {'component_bounds': c, 'output_bounds': o, 'axis_scale_component_to_output': axis_scale, 'maximum_bidirectional_vertex_error_m': max(component_to_output_error, output_to_component_error), 'normalized_vertex_sets_match': True, 'note': '制作组件与输出均独立核对v002各轴2倍；保留v002既有整合归一化差异，按已测包络仿射归一化后双向逐顶点吻合；未声明原始世界坐标完全一致。'}

views = {'front': (0, -2.8, .5), 'back': (0, 2.8, .5), 'side': (2.8, 0, .5), 'game': (1.8, -3, 2.1)}
for role in ([] if '--audit-only' in __import__('sys').argv else ['source', 'optimized']):
    bpy.ops.wm.open_mainfile(filepath=str(paths[role]))
    root = bpy.data.objects['ItemRoot']
    meshes = [o for o in root.children if o.type == 'MESH']
    scene = bpy.data.scenes.new('收音机固定保真验收')
    bpy.context.window.scene = scene
    for obj in [root] + meshes:
        scene.collection.objects.link(obj)
        obj.hide_render = False
        obj.hide_set(False)
    for image in bpy.data.images:
        if image.source == 'FILE':
            image.filepath = str(PALETTE)
            image.reload()
    world = bpy.data.worlds.new('固定验收环境')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (.12, .12, .12, 1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = .8
    scene.world = world
    scene.render.engine = 'BLENDER_EEVEE_NEXT'
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.film_transparent = False
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    scene.view_settings.exposure = 0
    scene.view_settings.gamma = 1
    for pos, energy, size in [((-2, -3, 4), 450, 4), ((3, 2, 3), 300, 3)]:
        light = bpy.data.lights.new('固定柔光', 'AREA')
        light.energy = energy
        light.shape = 'DISK'
        light.size = size
        obj = bpy.data.objects.new('固定柔光', light)
        scene.collection.objects.link(obj)
        obj.location = pos
        obj.rotation_euler = (Vector((0, 0, .4)) - obj.location).to_track_quat('-Z', 'Y').to_euler()
    camera_data = bpy.data.cameras.new('固定相机')
    camera_data.type = 'ORTHO'
    camera_data.ortho_scale = 1.25
    camera = bpy.data.objects.new('固定相机', camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    for name, position in views.items():
        camera.location = position
        camera.rotation_euler = (Vector((0, 0, .411)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = str(OUT / f'fidelity_{role}_{name}.png')
        bpy.ops.render.render(write_still=True)

assert all(sha(p) == before[str(p)] for p in protected)
report = {'asset_id': 'PRP-BASE99-RADIO-3D', 'scale_checks': checks, 'root_and_output_scale_one': True, 'source_optimized_geometry_uv_material_snapshot_scope': '几何、拓扑、世界变换快照完全一致；UV材质另由严格验收和固定渲染验证', 'source_optimized_geometry_equal': True, 'component_output_normalization': normalization, 'protected_hashes_unchanged': True, 'protected_hashes': before, 'fixed_views': list(views), 'render_comparison_pending_pixel_audit': True, 'godot_visual_acceptance_replaced': False}
(OUT / 'fidelity_evidence.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('RADIO_FIDELITY_RENDER_OK')
