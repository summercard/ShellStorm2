"""从不变source重新派生优化，消除槽灯重复片并补齐证据。"""
import importlib.util
import json
from pathlib import Path
import bpy

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('key_insert_build', HERE / 'build_key_insert_v001.py')
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)


def main():
    manifest = json.loads(b.MANIFEST.read_text(encoding='utf-8'))
    source_hash = b.sha(b.SOURCE)
    assert source_hash == manifest['source_sha256_before']
    bpy.ops.wm.open_mainfile(filepath=str(b.SOURCE))
    bpy.context.preferences.filepaths.save_version = 0
    editable = bpy.data.collections['01_制作组件_已统一材质']
    for obj in list(editable.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(editable)
    operations = []
    for obj in b.output_meshes():
        obj.data = obj.data.copy()
        operations.append(b.optimize_mesh(obj))
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)
    validity = []
    for obj in b.output_meshes():
        changed = obj.data.validate(verbose=True, clean_customdata=False)
        validity.append({'object':obj.name,'mesh_validate_required_correction':changed})
        assert not changed, obj.name
    bpy.context.scene['role'] = 'optimized'
    bpy.context.scene['source_sha256'] = source_hash
    bpy.ops.wm.save_as_mainfile(filepath=str(b.OPTIMIZED), relative_remap=False)
    optimized_hash = b.sha(b.OPTIMIZED)
    bpy.ops.wm.open_mainfile(filepath=str(b.OPTIMIZED))
    assert Path(bpy.data.filepath).resolve() == b.OPTIMIZED.resolve()
    after = b.audit_native('after')
    openings = b.opening_raycast_audit()
    renders = b.render_set('after')
    for obj in bpy.context.view_layer.objects:
        obj.select_set(False)
    for obj in b.output_meshes():
        obj.select_set(True)
    bpy.context.view_layer.objects.active = b.output_meshes()[0]
    bpy.ops.export_scene.gltf(filepath=str(b.GLB), export_format='GLB', use_selection=True, export_yup=True, export_apply=True, export_image_format='NONE', export_materials='EXPORT', export_texcoords=True, export_normals=True, export_tangents=True, export_animations=False, export_cameras=False, export_lights=False, export_extras=True)
    structure = b.glb_audit()
    composite = b.render_table_reference()
    protected_after = {path:b.sha(path) for path in manifest['protected_hashes_before']}
    assert protected_after == manifest['protected_hashes_before']
    assert b.sha(b.SOURCE) == source_hash and b.sha(b.OPTIMIZED) == optimized_hash
    manifest['source_sha256_after'] = b.sha(b.SOURCE)
    manifest['optimized_sha256'] = optimized_hash
    manifest['glb_sha256'] = b.sha(b.GLB)
    manifest['protected_hashes_after'] = protected_after
    manifest['geometry']['raycast_after'] = openings
    before_tri = manifest['optimization']['triangles_before']
    manifest['optimization'].update({'triangles_after':after['triangles'],'reduction_ratio':(before_tri-after['triangles'])/before_tri,'operations':operations,'zero_reduction_reason':None,'reduction_reason':'四个槽灯各移除2个共面反向四边形，共减少16个三角面；双面材质保留两侧可见性。主体各项安全清理零减面：保留孔口/内壁/暗槽/投影底面及独立UV岛。','mesh_native_validation':validity})
    manifest['materials_and_uv'].update({'after_faces':after['polygon_count'],'valid_uv_faces':after['valid_island_polygon_count'],'after_passed':after['passed'],'glb':structure})
    manifest['fidelity']['after'] = renders
    manifest['fidelity']['fixed_camera_settings_equal'] = all({k:v for k,v in a.items() if k!='image'} == {k:v for k,v in c.items() if k!='image'} for a,c in zip(manifest['fidelity']['before'],renders))
    manifest['table_reference'] = composite
    manifest['godot_import_handoff']['local_gitignore'] = b.rel(b.GLB.parent / '.gitignore')
    manifest['godot_import_handoff']['local_gitignore_content'] = '!*.glb.import\n'
    # 再次由稳定GLB反导入内存核查，不保存，也不启动Godot。
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(b.GLB))
    meshes = [o for o in bpy.context.scene.objects if o.type=='MESH']
    roundtrip = {'mesh_count':len(meshes),'triangles':b.tri_count(meshes),'bbox':b.bbox(meshes),'names':sorted(o.name for o in meshes),'native_mesh_valid':all(not o.data.validate(verbose=True,clean_customdata=False) for o in meshes)}
    assert roundtrip['triangles'] == after['triangles'] and roundtrip['mesh_count'] == 5 and roundtrip['native_mesh_valid']
    manifest['materials_and_uv']['glb_roundtrip'] = roundtrip
    b.dump(b.OUT / 'glb_roundtrip_validation.json', roundtrip)
    b.dump(b.MANIFEST, manifest)
    b.dump(b.OUT / 'asset_manifest.json', manifest)
    print('KEY_INSERT_FINAL_GEOMETRY_COMPLETE', flush=True)


if __name__ == '__main__':
    main()
