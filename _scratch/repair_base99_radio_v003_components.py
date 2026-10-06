import bpy
import hashlib
import json
import shutil
from pathlib import Path
from mathutils import Vector

P = Path('I:/工作项目/shellstrom2/ShellStorm2')
OUT = P / 'outputs/base99_radio_v003'
S = P / 'assets/art/props/base_world_3d/source/base99_radio'
SOURCE = S / 'prp_base99_radio_source_v003.blend'
OPT = S / 'export/v003/prp_base99_radio_optimized_v003.blend'
GLB = P / 'assets/art/props/base_world_3d/components/base99_radio/prp_base99_radio_visual_top3d.glb'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
protected = [S / 'prp_base99_radio_source_v001.blend', S / 'prp_base99_radio_source_v002.blend', GLB, P / 'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png']
protected_before = {str(p): sha(p) for p in protected}

def matrix(obj):
    return obj.matrix_basis if obj.parent is None else matrix(obj.parent) @ obj.matrix_parent_inverse @ obj.matrix_basis

def output_signature():
    result = {}
    for obj in bpy.data.objects['ItemRoot'].children:
        if obj.type == 'MESH':
            result[obj.name] = {'points': [list(matrix(obj) @ v.co) for v in obj.data.vertices], 'faces': [list(f.vertices) for f in obj.data.polygons], 'uv': [list(v.uv) for v in obj.data.uv_layers['PaletteUV'].data]}
    return result

bpy.ops.wm.open_mainfile(filepath=str(S / 'prp_base99_radio_source_v002.blend'))
old = {obj.name: [matrix(obj) @ v.co for v in obj.data.vertices] for obj in bpy.data.collections['01_制作组件_已统一材质'].all_objects if obj.type == 'MESH'}
points = [v for values in old.values() for v in values]
pivot = Vector(((min(v.x for v in points) + max(v.x for v in points)) / 2, (min(v.y for v in points) + max(v.y for v in points)) / 2, min(v.z for v in points)))
repair = []
for path in [SOURCE, OPT]:
    backup = OUT / (path.stem + '_before_component_repair.blend')
    assert not backup.exists(), '不覆盖既有源修复备份'
    shutil.copy2(path, backup)
    bpy.ops.wm.open_mainfile(filepath=str(path))
    output_before = output_signature()
    for name, values in old.items():
        obj = bpy.data.objects[name]
        assert len(obj.data.vertices) == len(values)
        inverse = matrix(obj).inverted()
        for vertex, point in zip(obj.data.vertices, values, strict=True):
            vertex.co = inverse @ (pivot + 2 * (point - pivot))
        obj.data.update()
    assert output_signature() == output_before
    bpy.context.preferences.filepaths.save_version = 0
    if path == OPT:
        bpy.context.scene['optimized_source_sha256'] = sha(SOURCE)
    bpy.ops.wm.save_as_mainfile(filepath=str(path))
    bpy.ops.wm.open_mainfile(filepath=str(path))
    assert output_signature() == output_before
    repair.append({'path': str(path), 'backup': str(backup), 'output_geometry_topology_uv_unchanged': True, 'sha256': sha(path)})
assert all(sha(path) == protected_before[str(path)] for path in protected)
evidence_path = OUT / 'optimization_evidence.json'
evidence = json.loads(evidence_path.read_text(encoding='utf-8'))
evidence['source_sha256_before_optimization'] = sha(SOURCE)
evidence['source_sha256_after_optimization'] = sha(SOURCE)
evidence['optimized_sha256'] = sha(OPT)
evidence['component_authoring_repair'] = {'reason': '隐藏集合matrix_world未求值导致制作组件错误放大；显式父链修复为v002逐顶点世界坐标2倍。', 'records': repair, 'stable_glb_unchanged': True, 'protected_hashes_unchanged': True}
evidence_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('RADIO_COMPONENT_REPAIR_OK')
