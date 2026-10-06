import bpy
import hashlib
import json
from pathlib import Path

P = Path('I:/工作项目/shellstrom2/ShellStorm2')
OUT = P / 'outputs/base99_radio_v003'
E = OUT / 'optimization_evidence.json'
evidence = json.loads(E.read_text(encoding='utf-8'))
source = Path(evidence['source_path'])
optimized = Path(evidence['optimized_path'])
glb = P / 'assets/art/props/base_world_3d/components/base99_radio/prp_base99_radio_visual_top3d.glb'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(source) == evidence['source_sha256_after_optimization']
assert sha(optimized) == evidence['optimized_sha256']
old_bytes = glb.read_bytes()
bpy.ops.wm.open_mainfile(filepath=str(optimized))
root = bpy.data.objects['ItemRoot']
meshes = [o for o in root.children if o.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for obj in [root] + meshes:
    obj.select_set(True)
next(o for o in meshes if o.get('runtime_interface_name') == 'StatusLight').name = 'StatusLight'
bpy.context.view_layer.objects.active = root
bpy.ops.export_scene.gltf(filepath=str(glb), export_format='GLB', use_selection=True, export_apply=True, export_image_format='NONE', export_materials='EXPORT', export_cameras=False, export_lights=False, export_animations=False)
assert glb.read_bytes() == old_bytes, '源组件修复不应改变游戏输出GLB'
assert sha(source) == evidence['source_sha256_after_optimization']
assert sha(optimized) == evidence['optimized_sha256']
evidence['reexport_after_component_repair'] = {'optimized_reopened': True, 'source_and_optimized_hashes_unchanged_during_export': True, 'glb_byte_identical': True, 'glb_sha256': sha(glb)}
E.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('RADIO_REEXPORT_BYTE_IDENTICAL_OK')
