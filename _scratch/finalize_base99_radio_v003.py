import bpy
import bmesh
import hashlib
import json
import math
from pathlib import Path
from mathutils import Vector

P = Path('I:/工作项目/shellstrom2/ShellStorm2')
S = P / 'assets/art/props/base_world_3d/source/base99_radio'
OUT = P / 'outputs/base99_radio_v003'
SOURCE = S / 'prp_base99_radio_source_v003.blend'
OPT = S / 'export/v003/prp_base99_radio_optimized_v003.blend'
GLB = P / 'assets/art/props/base_world_3d/components/base99_radio/prp_base99_radio_visual_top3d.glb'
PALETTE = P / 'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def signature(objects):
    result = {}
    for obj in objects:
        obj.data.calc_loop_triangles()
        result[obj.name] = {'vertices': [[round(x, 7) for x in v.co] for v in obj.data.vertices], 'polygons': [list(p.vertices) for p in obj.data.polygons], 'matrix': [list(row) for row in obj.matrix_world], 'triangles': len(obj.data.loop_triangles)}
    return result

protected = [S / 'prp_base99_radio_source_v001.blend', S / 'prp_base99_radio_source_v002.blend', PALETTE]
before = {str(p): sha(p) for p in protected}
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
# 修正本资产铜棕采样；公共色盘和历史源不变。
for obj in bpy.data.objects:
    if obj.type != 'MESH' or obj.data.uv_layers.get('PaletteUV') is None:
        continue
    uv = obj.data.uv_layers['PaletteUV']
    for poly in obj.data.polygons:
        mat = obj.data.materials[poly.material_index]
        if mat.name.startswith('01_'):
            cell = (1, 6)
        elif mat.name.startswith('03_'):
            cell = (2, 7)
        else:
            continue
        center = Vector(((cell[0] + 0.5) / 10, (cell[1] + 0.5) / 10))
        for i, loop in enumerate(poly.loop_indices):
            angle = 2 * math.pi * i / len(poly.loop_indices) + .17
            uv.data[loop].uv = center + Vector((math.cos(angle), math.sin(angle))) * .018
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
source_hash = sha(SOURCE)
root = bpy.data.objects['ItemRoot']
meshes = [o for o in root.children if o.type == 'MESH']
original_signature = signature(meshes)
tri_before = sum(v['triangles'] for v in original_signature.values())
operations = []
for obj in meshes:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    duplicate_faces = []
    keys = set()
    for face in bm.faces:
        key = tuple(sorted(tuple(round(c, 7) for c in v.co) for v in face.verts))
        if key in keys:
            duplicate_faces.append(face)
        keys.add(key)
    zero = [f for f in bm.faces if f.calc_area() <= 1e-12 and f not in duplicate_faces]
    if duplicate_faces or zero:
        bmesh.ops.delete(bm, geom=duplicate_faces + zero, context='FACES')
    loose_edges = [e for e in bm.edges if not e.link_faces]
    if loose_edges:
        bmesh.ops.delete(bm, geom=loose_edges, context='EDGES')
    loose_vertices = [v for v in bm.verts if not v.link_edges]
    if loose_vertices:
        bmesh.ops.delete(bm, geom=loose_vertices, context='VERTS')
    if duplicate_faces or zero or loose_edges or loose_vertices:
        bm.to_mesh(obj.data)
    bm.free()
    operations.append({'mesh': obj.name, 'duplicate_faces_removed': len(duplicate_faces), 'zero_area_faces_removed': len(zero), 'loose_edges_removed': len(loose_edges), 'loose_vertices_removed': len(loose_vertices), 'simplification': '保留598面复古轮廓、底面、文字与按钮，不对焦点细节作非零减面'})
OPT.parent.mkdir(parents=True, exist_ok=True)
bpy.context.scene['optimized_source_sha256'] = source_hash
bpy.context.scene['optimized_role'] = 'optimized'
bpy.ops.wm.save_as_mainfile(filepath=str(OPT))
bpy.ops.wm.open_mainfile(filepath=str(OPT))
root = bpy.data.objects['ItemRoot']
meshes = [o for o in root.children if o.type == 'MESH']
actual_signature = signature(meshes)
assert actual_signature == original_signature, '优化前后几何保真失败'
assert sha(SOURCE) == source_hash
assert all(sha(p) == before[str(p)] for p in protected)
bpy.ops.object.select_all(action='DESELECT')
root.select_set(True)
for obj in meshes:
    obj.select_set(True)
status = next(o for o in meshes if o.get('runtime_interface_name') == 'StatusLight')
status.name = 'StatusLight'
bpy.context.view_layer.objects.active = root
bpy.ops.export_scene.gltf(filepath=str(GLB), export_format='GLB', use_selection=True, export_apply=True, export_image_format='NONE', export_materials='EXPORT', export_cameras=False, export_lights=False, export_animations=False)
report = {'asset_id': 'PRP-BASE99-RADIO-3D', 'source_path': str(SOURCE), 'optimized_path': str(OPT), 'source_sha256_before_optimization': source_hash, 'source_sha256_after_optimization': sha(SOURCE), 'optimized_sha256': sha(OPT), 'protected_hashes_before': before, 'protected_hashes_after': {str(p): sha(p) for p in protected}, 'operations': operations, 'triangles_before': tri_before, 'triangles_after': sum(v['triangles'] for v in actual_signature.values()), 'reduction_ratio': 0.0, 'budget_faces': 800, 'geometry_signature_equal': True, 'saved_reopened_before_export': True, 'glb_sha256': sha(GLB), 'palette_uv_cells_bottom_origin': {'body': [1, 4], 'metal': [1, 6], 'accent': [2, 7], 'status': [5, 5]}}
(OUT / 'optimization_evidence.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('RADIO_V003_OPTIMIZED_EXPORT_OK', json.dumps(report, ensure_ascii=False))
