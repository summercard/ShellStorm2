"""补充不裁切的严格侧视固定镜头；源保持字节不变。"""
import importlib.util
import json
from pathlib import Path
import bpy

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('key_insert_build', HERE / 'build_key_insert_v001.py')
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)
manifest = json.loads(b.MANIFEST.read_text(encoding='utf-8'))
source_hash = b.sha(b.SOURCE)


def render_side(stage):
    camera = bpy.data.objects['验收镜头_side']
    camera.location = (3,0,.65)
    b.look_at(camera,(0,0,.11))
    camera.data.ortho_scale = 1.35
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.filepath = str(b.OUT / (stage+'_side.png'))
    bpy.ops.render.render(write_still=True)
    return {'view':'side','image':scene.render.filepath,'camera_location_blender':list(camera.location),'camera_rotation':list(camera.rotation_euler),'ortho_scale':camera.data.ortho_scale,'resolution':[1000,700],'engine':'CYCLES','samples':24,'view_transform':'AgX','look':'AgX - Medium High Contrast'}


bpy.ops.wm.open_mainfile(filepath=str(b.SOURCE))
manifest['fidelity']['before'][2] = render_side('before')
# 不回写source，仅持久保存独立优化文件里的修正镜头。
bpy.ops.wm.open_mainfile(filepath=str(b.OPTIMIZED))
bpy.context.preferences.filepaths.save_version = 0
manifest['fidelity']['after'][2] = render_side('after')
bpy.context.scene.camera = bpy.data.objects['验收镜头_game_angle']
bpy.ops.wm.save_as_mainfile(filepath=str(b.OPTIMIZED), relative_remap=False)
bpy.ops.wm.open_mainfile(filepath=str(b.OPTIMIZED))
for obj in bpy.context.view_layer.objects:
    obj.select_set(False)
for obj in b.output_meshes():
    obj.select_set(True)
bpy.context.view_layer.objects.active = b.output_meshes()[0]
bpy.ops.export_scene.gltf(filepath=str(b.GLB), export_format='GLB', use_selection=True, export_yup=True, export_apply=True, export_image_format='NONE', export_materials='EXPORT', export_texcoords=True, export_normals=True, export_tangents=True, export_animations=False, export_cameras=False, export_lights=False, export_extras=True)
manifest['optimized_sha256'] = b.sha(b.OPTIMIZED)
manifest['glb_sha256'] = b.sha(b.GLB)
manifest['materials_and_uv']['glb'] = b.glb_audit()
manifest['fidelity']['side_view_note'] = '首轮侧镜头裁切已纠正为正侧完整构图；前后均使用同一明确设置。source不回写，镜头持久保存在optimized，前后设置逐项写入清单。'
assert b.sha(b.SOURCE) == source_hash == manifest['source_sha256_before']
assert all(b.sha(path)==value for path,value in manifest['protected_hashes_before'].items())
b.dump(b.MANIFEST,manifest)
b.dump(b.OUT/'asset_manifest.json',manifest)
print('KEY_INSERT_SIDE_FULL_FRAME_COMPLETE',flush=True)
