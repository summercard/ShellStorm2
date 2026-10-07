import bpy,json,hashlib
from pathlib import Path
P=Path('I:/工作项目/shellstrom2/ShellStorm2');O=P/'outputs/base99_radio_v004'
m=json.loads((O/'asset_manifest.json').read_text(encoding='utf-8'))
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
for key in ['source_blend','optimized_blend']:
 p=Path(m[key]);tag='source' if key=='source_blend' else 'optimized'
 assert sha(p)==m['hashes_sha256'][tag]
 bpy.ops.wm.open_mainfile(filepath=str(p));bpy.context.preferences.filepaths.save_version=0
 bpy.data.objects['StatusLight'].name='StatusLight_UI灯光_柔和自发光'
 if tag=='optimized':bpy.context.scene['optimized_source_sha256']=sha(m['source_blend'])
 bpy.ops.wm.save_as_mainfile(filepath=str(p));m['hashes_sha256'][tag]=sha(p)
# 仅Blender中文验收名改变，导出接口保持StatusLight。
o=bpy.data.objects['StatusLight_UI灯光_柔和自发光'];o.name='StatusLight'
bpy.ops.object.select_all(action='DESELECT')
for name in ['ItemRoot','Visual','Antenna','StatusLight']:bpy.data.objects[name].select_set(True)
bpy.context.view_layer.objects.active=bpy.data.objects['ItemRoot']
bpy.ops.export_scene.gltf(filepath=m['component_glb'],export_format='GLB',use_selection=True,export_apply=True,export_image_format='NONE',export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False)
assert sha(m['component_glb'])==m['hashes_sha256']['glb']
(O/'asset_manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('BLENDER_NAME_AND_RUNTIME_INTERFACE_OK')
