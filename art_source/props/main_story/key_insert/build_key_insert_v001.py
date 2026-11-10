"""独立后台制作四孔嵌件；只写本资产与 work_path 指定的工程外证据。"""
from pathlib import Path
import hashlib
import importlib.util
import json
import math
import struct
import sys

import bpy
import bmesh
from mathutils import Vector

PROJECT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(PROJECT / 'scripts'))
from workspace_paths import work_path

ASSET_ID = 'PRP-BASE99-MAIN-STORY-KEY-INSERT'
SLUG = 'prp_base99_main_story_key_insert'
PACKAGE = Path(__file__).resolve().parent
SOURCE = PACKAGE / (SLUG + '_source_v001.blend')
OPTIMIZED = PACKAGE / 'export/v001' / (SLUG + '_optimized_v001.blend')
GLB = PROJECT / 'assets/art/props/main_story/components/key_insert' / (SLUG + '_visual_top3d.glb')
WRAPPER = PROJECT / 'assets/art/props/main_story/runtime/key_insert' / (SLUG + '_root_top3d.tscn')
PALETTE = PROJECT / 'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
TABLE_DIR = PROJECT / 'assets/art/environments/base_facility_3d'
TABLE_GLB = TABLE_DIR / 'components/env_base99_remaining_facilities/main_door_low_storage_cabinet/main_door_low_storage_cabinet_visual_top3d.glb'
TABLE_SCENE = TABLE_DIR / 'runtime/env_base99_remaining_facilities/main_door_low_storage_cabinet/main_door_low_storage_cabinet_root_top3d.tscn'
TABLE_SOURCE = PROJECT / 'art_source/design/blender/base_facility_layout/export/v021/base_facility_runtime_layout_hq-v021-remaining_facilities.blend'
POST_IMPORT = PROJECT / 'tools/asset_pipeline/scene_facility_shared_palette_post_import.gd'
OUT = work_path('outputs/2026-11-10_key_inset/model/.anchor').parent
MANIFEST = PACKAGE / 'asset_manifest.json'
VALIDATOR = Path('C:/Users/zhuangmenghong/.workbuddy/skills/blender-game-prop-standard/scripts/validate_game_prop.py')
SLOPE = math.tan(math.radians(20))
AXIS = Vector((0, math.sin(math.radians(20)), -math.cos(math.radians(20))))
CENTERS = [-0.69, -0.23, 0.23, 0.69]
OUTPUT_COLLECTION = '02_游戏输出_整合模型'


def dump(path, value):
    path = Path(path)
    assert path.parent.is_dir(), str(path.parent)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def rel(path):
    return str(Path(path).relative_to(PROJECT)).replace('\\', '/')


def top(y):
    return 0.24 + (y - 0.29) * SLOPE


def output_meshes():
    return sorted((o for o in bpy.data.collections[OUTPUT_COLLECTION].all_objects if o.type == 'MESH'), key=lambda o: o.name)


def tri_count(objects):
    total = 0
    for obj in objects:
        mesh = obj.to_mesh()
        mesh.calc_loop_triangles()
        total += len(mesh.loop_triangles)
        obj.to_mesh_clear()
    return total


def bbox(objects):
    points = [obj.matrix_world @ Vector(c) for obj in objects for c in obj.bound_box]
    lo = [min(p[i] for p in points) for i in range(3)]
    hi = [max(p[i] for p in points) for i in range(3)]
    return {'blender_min': lo, 'blender_max': hi, 'godot_min': [lo[0], lo[2], -hi[1]], 'godot_max': [hi[0], hi[2], -lo[1]], 'godot_size': [hi[0]-lo[0], hi[2]-lo[2], hi[1]-lo[1]]}


def new_collection(name, parent):
    c = bpy.data.collections.new(name)
    parent.children.link(c)
    return c


def uv_assign(mesh, cells):
    for layer in list(mesh.uv_layers):
        mesh.uv_layers.remove(layer)
    layer = mesh.uv_layers.new(name='PaletteUV')
    for poly, cell in zip(mesh.polygons, cells):
        row, col = cell
        u = (col - 0.5) / 10
        v = (10.5 - row) / 10
        count = len(poly.loop_indices)
        if count == 4:
            coords = [(-1,-1), (1,-1), (1,1), (-1,1)]
        else:
            coords = [(math.cos(2*math.pi*j/count), math.sin(2*math.pi*j/count)) for j in range(count)]
        for li, (a,b) in zip(poly.loop_indices, coords):
            layer.data[li].uv = (u + a*0.025, v + b*0.025)
    mesh.uv_layers.active = layer
    layer.active_render = True


class MeshBuilder:
    def __init__(self):
        self.vertices = []
        self.lookup = {}
        self.faces = []
        self.roles = []
        self.cells = []

    def face(self, coords, role, cell):
        indices = []
        for point in coords:
            key = tuple(round(float(c), 9) for c in point)
            if key not in self.lookup:
                self.lookup[key] = len(self.vertices)
                self.vertices.append(key)
            indices.append(self.lookup[key])
        self.faces.append(indices)
        self.roles.append(role)
        self.cells.append(cell)

    def finish(self, name, collection, materials):
        mesh = bpy.data.meshes.new(name + '_Mesh')
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        for material in materials:
            mesh.materials.append(material)
        for p, role in zip(mesh.polygons, self.roles):
            p.material_index = role
        uv_assign(mesh, self.cells)
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        collection.objects.link(obj)
        return obj


def materials_create():
    image = bpy.data.images.load(str(PALETTE), check_existing=True)
    image.filepath = str(PALETTE)
    image.use_fake_user = True
    assert tuple(image.size) == (512, 512)
    roles = [
        ('01_精工金属_紫色骨架', 0.86, 0.27, 0.18, 0),
        ('02_细腻哑光_青绿大面', 0.02, 0.70, 0.0, 0),
        ('03_清漆反光_紫粉点缀', 0.18, 0.15, 0.68, 0),
        ('04_柔和自发光_UI灯光', 0.0, 0.38, 0.0, 1.25),
    ]
    materials = []
    for name, metallic, roughness, coat, emission in roles:
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        bsdf = nodes.get('Principled BSDF')
        bsdf.inputs['Metallic'].default_value = metallic
        bsdf.inputs['Roughness'].default_value = roughness
        bsdf.inputs['Coat Weight'].default_value = coat
        bsdf.inputs['Emission Strength'].default_value = emission
        tex = nodes.new('ShaderNodeTexImage')
        tex.image = image
        tex.interpolation = 'Closest'
        tex.extension = 'EXTEND'
        uv = nodes.new('ShaderNodeUVMap')
        uv.uv_map = 'PaletteUV'
        links.new(uv.outputs['UV'], tex.inputs['Vector'])
        links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
        if emission:
            links.new(tex.outputs['Color'], bsdf.inputs['Emission Color'])
        materials.append(mat)
    return materials


def create_body(collection, materials):
    b = MeshBuilder()
    xs = [-1.14, -1.118, 1.118, 1.14]
    for x in CENTERS:
        xs.extend([round(x-0.10, 4), round(x+0.10, 4)])
    xs.sort()
    ys = [-0.29, -0.268, -0.16, 0.16, 0.268, 0.29]
    for a,c in zip(xs, xs[1:]):
        for d,e in zip(ys, ys[1:]):
            if d == -0.16 and e == 0.16 and any(abs((a+c)/2-x) < 1e-5 and abs(c-a-.2) < 1e-5 for x in CENTERS):
                continue
            border = a < -1.118 or c > 1.118 or d < -.268 or e > .268
            b.face([(a,d,top(d)), (c,d,top(d)), (c,e,top(e)), (a,e,top(e))], 0 if border else 1, (8,6) if border else (6,6))
    # 边界按顶面同一分段封闭，保留底面用于投影与独立复用。
    for a,c in zip(xs, xs[1:]):
        b.face([(a,-.29,0), (c,-.29,0), (c,-.29,top(-.29)), (a,-.29,top(-.29))], 0, (8,6))
        b.face([(c,.29,0), (a,.29,0), (a,.29,top(.29)), (c,.29,top(.29))], 0, (8,6))
        b.face([(a,.29,0), (c,.29,0), (c,-.29,0), (a,-.29,0)], 1, (3,10))
    for d,e in zip(ys, ys[1:]):
        b.face([(-1.14,e,0), (-1.14,d,0), (-1.14,d,top(d)), (-1.14,e,top(e))], 0, (8,6))
        b.face([(1.14,d,0), (1.14,e,0), (1.14,e,top(e)), (1.14,d,top(d))], 0, (8,6))
    sockets = []
    for index, x in enumerate(CENTERS):
        outer = [(x-.10,-.16,top(-.16)), (x+.10,-.16,top(-.16)), (x+.10,.16,top(.16)), (x-.10,.16,top(.16))]
        inner = [Vector((x-.08,-.14,top(-.14)-.006)), Vector((x+.08,-.14,top(-.14)-.006)), Vector((x+.08,.14,top(.14)-.006)), Vector((x-.08,.14,top(.14)-.006))]
        bottom = [v + AXIS * .060 for v in inner]
        for j in range(4):
            k = (j+1)%4
            b.face([outer[j], outer[k], inner[k], inner[j]], 0, (7,8))
            b.face([inner[j], inner[k], bottom[k], bottom[j]], 1, (3,10))
        b.face(list(reversed(bottom)), 1, (1,10))
        sockets.append({'index': index, 'mouth_center_godot': [x, top(0)-.006, 0], 'mouth_width_m': .16, 'mouth_depth_projected_m': .28, 'axial_blind_depth_m': .060, 'entry_lip_m': .006, 'inner_bottom_min_y_godot': min(v.z for v in bottom)})
        # 每孔前方的紫粉识别牌与1至4条刻线，不跨越开口。
        a,c,d,e = x-.085,x+.085,-.245,-.210
        b.face([(a,d,top(d)+.0015), (c,d,top(d)+.0015), (c,e,top(e)+.0015), (a,e,top(e)+.0015)], 2, (9,6))
        for tick in range(index+1):
            tx = x - index*.009 + tick*.018
            b.face([(tx-.003,-.238,top(-.238)+.002), (tx+.003,-.238,top(-.238)+.002), (tx+.003,-.217,top(-.217)+.002), (tx-.003,-.217,top(-.217)+.002)], 0, (10,10))
    obj = b.finish('主线钥匙嵌件_主体_金属哑光反光', collection, materials[:3])
    obj['asset_id'] = ASSET_ID
    obj['semantic'] = '四孔薄型固定嵌件_不含钥匙_不含原台柜'
    return obj, sockets


def create_glow(index, collection, material):
    b = MeshBuilder()
    x = CENTERS[index]
    # 灯片贴内壁，距孔唇沿插入轴下沉18mm；孔中央始终空心。
    for sign in [-1, 1]:
        wall_x = x + sign * .0795
        points = []
        for y, depth in [(-.105,.017), (.105,.017), (.105,.022), (-.105,.022)]:
            p = Vector((wall_x,y,top(y)-.006)) + AXIS*depth
            points.append(p)
        b.face(points, 0, (6,8))
        b.face(list(reversed(points)), 0, (6,8))
    glow = b.finish('SocketGlow_' + str(index), collection, [material])
    glow['socket_index'] = index
    return glow


def look_at(obj, target):
    obj.rotation_euler = (Vector(target)-obj.location).to_track_quat('-Z', 'Y').to_euler()


def presentation_setup(collection):
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
    scene.view_settings.exposure = 0
    world = bpy.data.worlds.new('验收_柔和摄影环境')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs[0].default_value = (.22,.26,.34,1)
    world.node_tree.nodes['Background'].inputs[1].default_value = .7
    scene.world = world
    for name, position, energy, size in [('验收_主光',(0,-2.5,4),650,4), ('验收_侧光',(-3,-.2,2),420,3), ('验收_轮廓光',(1.5,3,3),800,3)]:
        data = bpy.data.lights.new(name, 'AREA')
        data.energy, data.shape, data.size = energy, 'DISK', size
        obj = bpy.data.objects.new(name, data)
        collection.objects.link(obj)
        obj.location = position
        look_at(obj, (0,0,.1))
    cameras = {
        'front': ((0,-3,1.55),(0,0,.10),2.65),
        'back': ((0,3,1.55),(0,0,.10),2.65),
        'side': ((3,-.45,1.30),(0,0,.11),1.3),
        'game_angle': ((2.1,-3.5,4.5),(0,0,.11),2.8),
        'top': ((0,0,4),(0,0,.10),2.65),
        'socket_close': ((.30,-.8,.85),(.23,0,.10),.72),
    }
    for name, (pos, target, scale) in cameras.items():
        data = bpy.data.cameras.new('验收镜头_' + name)
        data.type, data.ortho_scale = 'ORTHO', scale
        obj = bpy.data.objects.new('验收镜头_' + name, data)
        collection.objects.link(obj)
        obj.location = pos
        look_at(obj, target)


def render_set(stage):
    records = []
    for name in ['front','back','side','game_angle','top','socket_close']:
        camera = bpy.data.objects['验收镜头_' + name]
        bpy.context.scene.camera = camera
        path = OUT / (stage + '_' + name + '.png')
        bpy.context.scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        records.append({'view': name, 'image': str(path), 'camera_location_blender': list(camera.location), 'camera_rotation': list(camera.rotation_euler), 'ortho_scale': camera.data.ortho_scale, 'resolution': [1000,700], 'engine': 'CYCLES', 'samples': 24, 'view_transform': 'AgX', 'look': 'AgX - Medium High Contrast'})
    return records


def audit_native(stage):
    spec = importlib.util.spec_from_file_location('key_insert_standard_validator', VALIDATOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    old = list(sys.argv)
    sys.argv = ['validate_game_prop.py', '--', '--max-materials','4','--shared-palette',str(PALETTE),'--json',str(OUT / (stage + '_standard_validation.json'))]
    try:
        module.main()
    except SystemExit as result:
        assert result.code == 0, '逐面标准验收失败：' + stage
    finally:
        sys.argv = old
    report = json.loads((OUT / (stage + '_standard_validation.json')).read_text(encoding='utf-8'))
    report['triangles'] = tri_count(output_meshes())
    report['bbox'] = bbox(output_meshes())
    report['images'] = [{'name': image.name, 'path': bpy.path.abspath(image.filepath), 'packed': bool(image.packed_file), 'size': list(image.size)} for image in bpy.data.images if image.source == 'FILE']
    dump(OUT / (stage + '_standard_validation.json'), report)
    return report


def optimize_mesh(obj):
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    before = {'verts': len(bm.verts), 'edges': len(bm.edges), 'faces': len(bm.faces)}
    # 同坐标、同材质且UV一致的反向共面片仅保留一片；材质双面显示避免重复几何。
    duplicate_faces = []
    seen_faces = set()
    uv_layer = bm.loops.layers.uv.get('PaletteUV')
    for face in bm.faces:
        uv_cells = tuple(sorted({(int(loop[uv_layer].uv.x * 10), int(loop[uv_layer].uv.y * 10)) for loop in face.loops}))
        signature = (face.material_index, uv_cells, tuple(sorted(tuple(round(c, 7) for c in loop.vert.co) for loop in face.loops)))
        if signature in seen_faces:
            duplicate_faces.append(face)
        else:
            seen_faces.add(signature)
    if duplicate_faces:
        bmesh.ops.delete(bm, geom=duplicate_faces, context='FACES_ONLY')
    duplicate_count = len(duplicate_faces)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-7)
    after_doubles = {'verts': len(bm.verts), 'edges': len(bm.edges), 'faces': len(bm.faces)}
    bmesh.ops.dissolve_degenerate(bm, dist=1e-9, edges=list(bm.edges))
    after_degenerate = {'verts': len(bm.verts), 'edges': len(bm.edges), 'faces': len(bm.faces)}
    loose_edges = [e for e in bm.edges if not e.link_faces]
    if loose_edges:
        bmesh.ops.delete(bm, geom=loose_edges, context='EDGES')
    loose_verts = [v for v in bm.verts if not v.link_edges]
    if loose_verts:
        bmesh.ops.delete(bm, geom=loose_verts, context='VERTS')
    # 每面独立色盘UV岛具有编辑语义，UV/材质/法线边界必须保留。
    before_dissolve = len(bm.faces)
    bmesh.ops.dissolve_limit(bm, angle_limit=1e-6, use_dissolve_boundaries=False, verts=list(bm.verts), edges=list(bm.edges), delimit={'NORMAL','MATERIAL','SEAM','SHARP','UV'})
    after_dissolve = len(bm.faces)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bmesh.ops.triangulate(bm, faces=list(bm.faces), quad_method='BEAUTY', ngon_method='BEAUTY')
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return {'object': obj.name, 'before': before, 'duplicate_coplanar_faces_removed': duplicate_count, 'after_remove_doubles': after_doubles, 'after_degenerate': after_degenerate, 'loose_edges_removed': len(loose_edges), 'loose_vertices_removed': len(loose_verts), 'safe_dissolve_faces_before': before_dissolve, 'safe_dissolve_faces_after': after_dissolve, 'after_triangulation': {'verts':len(mesh.vertices),'edges':len(mesh.edges),'faces':len(mesh.polygons)}, 'operations': {'remove_doubles_distance_m':1e-7,'dissolve_degenerate_distance_m':1e-9,'dissolve_limit_angle_rad':1e-6,'dissolve_delimit':['NORMAL','MATERIAL','SEAM','SHARP','UV'],'triangulate':'BEAUTY'}, 'preserved_reason':'孔唇/内壁/槽底/完整外壳均参与可见性或投影；独立PaletteUV岛禁止跨岛溶解。原始直线轮廓无曲面与冗余倒角段。槽灯共面反向片可由双面材质替代，按同材质同色格清理；不改孔口和灯片可见轮廓。'}


def opening_raycast_audit():
    body = next(o for o in output_meshes() if not o.name.startswith('SocketGlow_'))
    result = []
    for i, x in enumerate(CENTERS):
        mouth = Vector((x,0,top(0)-.006))
        start = mouth - AXIS*.03
        hit, point, normal, face = body.ray_cast(start, AXIS, distance=.12)
        distance_from_mouth = (point-mouth).dot(AXIS) if hit else None
        assert hit and abs(distance_from_mouth-.060) < 1e-5, (i, hit, distance_from_mouth)
        side_hit, side_point, _, _ = body.ray_cast(mouth + AXIS*.03, Vector((1,0,0)), distance=.12)
        assert side_hit and abs(side_point.x-x-.08) < 1e-5
        result.append({'socket':i,'axis_ray_hits_recess_floor':hit,'first_hit_depth_from_mouth_m':distance_from_mouth,'side_wall_hit':side_hit,'half_width_m':side_point.x-x,'no_solid_rectangle_at_mouth':True})
    return result


def glb_audit():
    raw = GLB.read_bytes()
    magic, version, length = struct.unpack_from('<III', raw, 0)
    assert magic == 0x46546C67 and version == 2 and length == len(raw)
    json_length, json_type = struct.unpack_from('<II', raw, 12)
    data = json.loads(raw[20:20+json_length].decode('utf-8'))
    assert not data.get('images') and not data.get('textures')
    assert len(data['materials']) == 4
    triangles = sum(data['accessors'][p['indices']]['count']//3 for m in data['meshes'] for p in m['primitives'])
    assert triangles == tri_count(output_meshes())
    names = [n.get('name') for n in data['nodes']]
    assert all('SocketGlow_'+str(i) in names for i in range(4))
    assert len(data['meshes']) == 5
    assert all('TEXCOORD_0' in p['attributes'] and 'NORMAL' in p['attributes'] for m in data['meshes'] for p in m['primitives'])
    dump(OUT / 'glb_structure.json', data)
    return {'images':len(data.get('images',[])), 'textures':len(data.get('textures',[])), 'materials':[m['name'] for m in data['materials']], 'meshes':len(data['meshes']), 'nodes':names, 'triangles':triangles, 'uv0_and_normals_all_primitives':True, 'tangents_all_primitives':all('TANGENT' in p['attributes'] for m in data['meshes'] for p in m['primitives'])}


def write_wrapper_import():
    res_glb = 'res://' + rel(GLB)
    text = '\n'.join([
        '[gd_scene load_steps=2 format=3]', '',
        '[ext_resource type="PackedScene" path="'+res_glb+'" id="1_visual"]', '',
        '[node name="MainStoryKeyInsert" type="Node3D"]',
        'metadata/asset_id = "'+ASSET_ID+'"',
        'metadata/asset_version = "v001"',
        'metadata/source_blend = "res://'+rel(SOURCE)+'"',
        'metadata/optimized_blend = "res://'+rel(OPTIMIZED)+'"',
        'metadata/collision_policy = "none"',
        'metadata/collision_enabled = false',
        'metadata/units = "m"',
        'metadata/local_origin = "XZ centered; bottom Y=0"',
        'metadata/front_axis = "+Z; rear=-Z"',
        'metadata/socket_insertion_axis = Vector3(0, -0.939692621, -0.342020143)',
        'metadata/socket_pitch_degrees = 20.0',
        'metadata/socket_spacing_m = 0.46',
        'metadata/key_embedded = false',
        'metadata/runtime_integrated = false', '',
        '[node name="Visual" parent="." instance=ExtResource("1_visual")]', '',
    ])
    assert not WRAPPER.exists(), '禁止覆盖已存在包装'
    WRAPPER.write_text(text, encoding='utf-8')
    # 仅预写当前组件契约，不创建/虚报Godot导入缓存或UID。
    cache = GLB.name + '-' + hashlib.md5(res_glb.encode('utf-8')).hexdigest() + '.scn'
    imported = 'res://.godot/imported/' + cache
    config = '\n'.join([
        '[remap]', '', 'importer="scene"', 'importer_version=1', 'type="PackedScene"', 'path="'+imported+'"', '',
        '[deps]', '', 'source_file="'+res_glb+'"', 'dest_files=["'+imported+'"]', '',
        '[params]', '', 'nodes/root_type=""', 'nodes/root_name=""', 'nodes/apply_root_scale=true', 'nodes/root_scale=1.0',
        'nodes/use_name_suffixes=false', 'nodes/use_node_type_suffixes=false', 'meshes/ensure_tangents=true',
        'meshes/generate_lods=false', 'meshes/create_shadow_meshes=true', 'meshes/light_baking=1', 'animation/import=false',
        'import_script/path="res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"',
        'materials/extract=0', '_subresources={}', 'gltf/naming_version=2', 'gltf/embedded_image_handling=0', '',
    ])
    config_path = Path(str(GLB)+'.import')
    assert not config_path.exists(), '禁止覆盖已存在导入配置'
    config_path.write_text(config, encoding='utf-8')
    return {'path':rel(config_path),'content':config,'cache_generated':False,'formal_import_executed':False,'post_import':rel(POST_IMPORT),'post_import_texture_filter':'TEXTURE_FILTER_NEAREST','palette_compression_mode':0,'palette_mipmaps_generate':False,'main_agent_actions':['仅在主agent安全窗口正式导入本GLB；本任务不启动Godot全工程导入。','核对Visual/SocketGlow_0..3可独立访问；共享发光材质若需逐孔换色，运行方需为目标表面复制材质，不改本资产制作脚本。','导入后验证每表面公共色盘、Nearest、不重复、自发光MULTIPLY与影子；独立实例化wrapper并进行真实游戏镜头截图。','本任务不接入房间、不改主线、不登记账本。']}


def render_table_reference():
    objects = output_meshes()
    for obj in objects:
        obj.location = (5, 3.77, 1.38)
    existing = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(TABLE_GLB))
    imported = [obj for obj in bpy.data.objects if obj not in existing]
    palette = next(im for im in bpy.data.images if im.source == 'FILE' and Path(bpy.path.abspath(im.filepath)).resolve() == PALETTE.resolve())
    for obj in imported:
        if obj.type != 'MESH':
            continue
        for mat in obj.data.materials:
            if not mat:
                continue
            if not mat.use_nodes:
                mat.use_nodes = True
            nodes, links = mat.node_tree.nodes, mat.node_tree.links
            bsdf = next((n for n in nodes if n.type == 'BSDF_PRINCIPLED'), None)
            if bsdf is None:
                continue
            tex = nodes.new('ShaderNodeTexImage')
            tex.image, tex.interpolation = palette, 'Closest'
            links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
            if mat.name.startswith('04_'):
                links.new(tex.outputs['Color'], bsdf.inputs['Emission Color'])
    for obj in bpy.data.objects:
        if obj.type == 'LIGHT':
            obj.location += Vector((5,3.77,1.38))
    camera = bpy.data.objects['验收镜头_game_angle']
    camera.location = (8,-1.0,6.4)
    camera.data.ortho_scale = 7.5
    look_at(camera, (5,3.9,1.05))
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.resolution_x, scene.render.resolution_y = 1400, 900
    scene.render.filepath = str(OUT / 'table_composite_placement_reference.png')
    bpy.ops.render.render(write_still=True)
    # 不保存：参考柜体、参考摆位和参考灯光永不进入源、优化文件或稳定GLB。
    return {'image':scene.render.filepath,'temporary_import':str(TABLE_GLB),'reference_only':True,'saved_to_blend':False,'included_in_glb':False,'godot_placement':[5,1.38,-3.77],'insert_world_bbox_godot':{'min':[3.86,1.38,-4.06],'max':[6.14,1.62,-3.48]},'table_top_y':1.38,'table_x_limits':[1.86,8.14],'table_z_limits':[-4.20,-3.34],'left_device_center_x':3,'right_device_center_x':7.1,'circle_modified':False}


def main():
    for path in [SOURCE, OPTIMIZED, GLB, WRAPPER, MANIFEST]:
        assert not path.exists(), '已有资产不可覆盖：' + str(path)
    assert PACKAGE.is_dir() and GLB.parent.is_dir() and WRAPPER.parent.is_dir() and OUT.is_dir()
    protected_paths = [PALETTE, Path(str(PALETTE)+'.import'), TABLE_GLB, Path(str(TABLE_GLB)+'.import'), TABLE_SCENE, POST_IMPORT]
    if TABLE_SOURCE.exists():
        protected_paths.append(TABLE_SOURCE)
    # 全部基地母版与外链库只读指纹，防止临时参考导入污染制作来源。
    source_root = PROJECT / 'art_source/design/blender/base_facility_layout'
    protected_paths.extend(p for p in source_root.rglob('*.blend') if p not in protected_paths)
    protected = {str(p):sha(p) for p in protected_paths}
    dump(OUT / 'protected_hashes_before.json', protected)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.scene.unit_settings.scale_length = 1
    bpy.context.preferences.filepaths.save_version = 0
    root = new_collection('主线四孔薄型嵌件_中文资产管理', bpy.context.scene.collection)
    editable = new_collection('01_制作组件_已统一材质', root)
    output = new_collection(OUTPUT_COLLECTION, root)
    presentation = new_collection('90_展示与验收_灯光相机', root)
    materials = materials_create()
    body, sockets = create_body(output, materials)
    for i in range(4):
        create_glow(i, output, materials[3])
    for obj in output_meshes():
        copy = obj.copy()
        copy.data = obj.data.copy()
        copy.name = '制作_' + obj.name
        editable.objects.link(copy)
    editable.hide_render = True
    editable.hide_viewport = True
    presentation_setup(presentation)
    bpy.context.scene.camera = bpy.data.objects['验收镜头_game_angle']
    bpy.context.scene['asset_id'] = ASSET_ID
    bpy.context.scene['version'] = 'v001'
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE), relative_remap=False)
    source_hash = sha(SOURCE)
    before_audit = audit_native('before')
    before_openings = opening_raycast_audit()
    before_renders = render_set('before')
    # 从已保存制作源重新读取后另存派生文件，源不再写入。
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    bpy.context.preferences.filepaths.save_version = 0
    editable = bpy.data.collections['01_制作组件_已统一材质']
    for obj in list(editable.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(editable)
    operations = []
    for obj in output_meshes():
        obj.data = obj.data.copy()
        operations.append(optimize_mesh(obj))
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)
    OPTIMIZED.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene['role'] = 'optimized'
    bpy.context.scene['source_sha256'] = source_hash
    bpy.ops.wm.save_as_mainfile(filepath=str(OPTIMIZED), relative_remap=False)
    optimized_hash = sha(OPTIMIZED)
    bpy.ops.wm.open_mainfile(filepath=str(OPTIMIZED))
    assert Path(bpy.data.filepath).resolve() == OPTIMIZED.resolve()
    assert sha(SOURCE) == source_hash
    after_audit = audit_native('after')
    after_openings = opening_raycast_audit()
    after_renders = render_set('after')
    assert before_audit['bbox'] == after_audit['bbox']
    for obj in bpy.context.view_layer.objects:
        obj.select_set(False)
    for obj in output_meshes():
        obj.select_set(True)
    bpy.context.view_layer.objects.active = output_meshes()[0]
    bpy.ops.export_scene.gltf(filepath=str(GLB), export_format='GLB', use_selection=True, export_yup=True, export_apply=True, export_image_format='NONE', export_materials='EXPORT', export_texcoords=True, export_normals=True, export_tangents=True, export_animations=False, export_cameras=False, export_lights=False, export_extras=True)
    structure = glb_audit()
    import_handoff = write_wrapper_import()
    composite = render_table_reference()
    after_protected = {str(p):sha(p) for p in protected_paths}
    assert protected == after_protected
    assert source_hash == sha(SOURCE)
    assert optimized_hash == sha(OPTIMIZED)
    count_before, count_after = before_audit['triangles'], after_audit['triangles']
    report = {
        'asset_id':ASSET_ID,'display_name':'主门低柜中央四孔主线钥匙薄型嵌件','version':'v001','role':'fixed_attachment','source':rel(SOURCE),'optimized':rel(OPTIMIZED),'stable_glb':rel(GLB),'wrapper':rel(WRAPPER),'source_sha256_before':source_hash,'source_sha256_after':sha(SOURCE),'optimized_sha256':optimized_hash,'glb_sha256':sha(GLB),'wrapper_sha256':sha(WRAPPER),'source_path_not_optimized_path':SOURCE != OPTIMIZED,'optimized_saved_then_reopened_before_export':True,'protected_hashes_before':protected,'protected_hashes_after':after_protected,'protected_all_unchanged':True,
        'coordinates':{'units':'m','blender_to_godot':'(x,y,z) -> (x,z,-y)','origin':'Godot XZ中心，底面Y=0','front_axis_godot':'+Z','rear_axis_godot':'-Z','top_slope_degrees':20,'socket_insertion_axis_godot':[0,-math.cos(math.radians(20)),-math.sin(math.radians(20))],'bbox':after_audit['bbox'],'recommended_godot_placement':[5,1.38,-3.77],'socket_spacing_m':.46,'socket_centers_x':CENTERS,'sockets':sockets},
        'geometry':{'body_meshes':1,'glow_meshes':4,'glow_node_names':['SocketGlow_'+str(i) for i in range(4)],'key_embedded':False,'table_embedded':False,'standalone_ring':False,'pedestal_or_feet':False,'socket_geometry':'真实倒角矩形孔唇、轴向内壁、60mm下沉暗槽；非实心矩形贴片','raycast_before':before_openings,'raycast_after':after_openings},
        'optimization':{'triangles_before':count_before,'triangles_after':count_after,'reduction_ratio':(count_before-count_after)/count_before,'budget':None,'budget_source':'用户未给出面数预算','operations':operations,'zero_reduction_reason':'完整执行重复点/退化/孤立/安全共面清理；每面UV岛、材质和孔口轮廓边界必须保留；没有可安全减少的曲面/倒角段，不使用全局Decimate，不将三角化冒充减面。','bottom_faces_retained':True},
        'materials_and_uv':{'before_report':str(OUT/'before_standard_validation.json'),'after_report':str(OUT/'after_standard_validation.json'),'before_passed':before_audit['passed'],'after_passed':after_audit['passed'],'after_faces':after_audit['polygon_count'],'valid_uv_faces':after_audit['valid_island_polygon_count'],'materials':after_audit['material_audit'],'images':after_audit['images'],'palette_sha256_unchanged':protected[str(PALETTE)] == after_protected[str(PALETTE)],'glb':structure},
        'fidelity':{'before':before_renders,'after':after_renders,'fixed_camera_settings_equal':before_renders[0]['camera_location_blender']==after_renders[0]['camera_location_blender'],'bbox_exactly_equal':before_audit['bbox']==after_audit['bbox'],'human_visual_review':'pending','pixel_comparison':'pending'},
        'table_reference':composite,'godot_import_handoff':import_handoff,
        'status':{'blender_source_complete':True,'stable_glb_exported':True,'wrapper_authored':True,'godot_formal_import_verified':False,'runtime_integrated':False,'ledger_updated':False,'docs_updated':False,'active_blender_session_touched':False,'full_project_import_run':False},
        'not_verified':['Godot正式导入、独立PackedScene实例化、导入后材质与实际游戏截图：按用户要求交接主agent执行。','未提供红框原图，本次按明确台柜坐标和尺寸制作与合成摆位。'],
        'evidence_directory':str(OUT),'build_script':rel(Path(__file__)),
    }
    dump(MANIFEST, report)
    dump(OUT / 'asset_manifest.json', report)
    print('KEY_INSERT_COMPLETE ' + str(MANIFEST), flush=True)


if __name__ == '__main__':
    main()
