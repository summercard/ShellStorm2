"""从已保存并重开的 v003 优化 Blend 导出 217 个 staged GLB。
仅写 source/tower_03/export/v003/staged_components、v003 manifest/catalog/QA；不写 components/runtime、Godot 或账本。
"""
from __future__ import annotations
import bpy
import hashlib
import json
import struct
from pathlib import Path
from mathutils import Vector

ROOT = Path('I:/工作项目/shellstrom2/ShellStorm2')
BASE = ROOT / 'assets/art/environments/open_world'
BLEND = BASE / 'source/tower_03/export/v003/env_tower_03-v003-runtime_optimized.blend'
V001_MANIFEST = BASE / 'source/tower_03/export/v001/export_manifest.json'
V003_QA = BASE / 'source/tower_03/export/v003/qa/optimization_v003.json'
OUT_DIR = BASE / 'source/tower_03/export/v003'
STAGED = OUT_DIR / 'staged_components'
CATALOG_DIR = BASE / 'source/tower_03/v003'


def sha256(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as f:
        for chunk in iter(lambda:f.read(1024*1024),b''): h.update(chunk)
    return h.hexdigest()


def tri(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def bounds(objects):
    points=[obj.matrix_world @ Vector(c) for obj in objects for c in obj.bound_box]
    return [[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]]


def glb_json(path):
    raw=Path(path).read_bytes()
    magic,version,length=struct.unpack_from('<4sII',raw,0)
    assert (magic,version,length)==(b'glTF',2,len(raw)),path
    offset=12; result=None
    while offset < len(raw):
        chunk_len,chunk_type=struct.unpack_from('<II',raw,offset); offset += 8
        data=raw[offset:offset+chunk_len]; offset += chunk_len
        if chunk_type==0x4E4F534A: result=json.loads(data.rstrip(b' \t\r\n\0').decode('utf-8'))
    assert result is not None,path
    return result


def glb_triangles(data):
    accessors=data.get('accessors',[])
    total=0
    for mesh in data.get('meshes',[]):
        for primitive in mesh.get('primitives',[]):
            assert primitive.get('mode',4)==4
            index=primitive.get('indices')
            if index is None:
                position=primitive['attributes']['POSITION']
                total += int(accessors[position]['count']) // 3
            else:
                total += int(accessors[index]['count']) // 3
    return total


def export_one(objects,path):
    path.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.hide_set(False); obj.hide_viewport=False; obj.hide_render=False; obj.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_materials='EXPORT',export_image_format='NONE',export_texcoords=True,export_normals=True,export_tangents=True,export_lights=False,export_cameras=False,export_animations=False,export_extras=False)
    bpy.ops.object.select_all(action='DESELECT')


def main():
    assert Path(bpy.data.filepath).resolve()==BLEND.resolve(),bpy.data.filepath
    assert V001_MANIFEST.is_file() and V003_QA.is_file()
    old=json.loads(V001_MANIFEST.read_text(encoding='utf-8'))
    qa=json.loads(V003_QA.read_text(encoding='utf-8'))
    assert len(old['records'])==217
    assert qa['runtime_integrated'] is False
    assert qa['stable_paths_touched'] is False
    records=[]
    for source_record in old['records']:
        slug=source_record['slug']; objects=[bpy.data.objects.get(n) for n in source_record['objects']]
        assert all(o is not None and o.type=='MESH' for o in objects),slug
        category=source_record['category']
        staged_rel=Path('assets/art/environments/open_world/source/tower_03/export/v003/staged_components')/category/f'{slug}.glb'
        staged=ROOT/staged_rel
        export_one(objects,staged)
        data=glb_json(staged)
        assert not data.get('images') and not data.get('textures') and not data.get('animations') and not data.get('cameras')
        assert not data.get('extensions',{}).get('KHR_lights_punctual')
        assert len(data.get('materials',[]))<=4
        assert all(m['name'].startswith(('01_','02_','03_','04_')) for m in data.get('materials',[]))
        for mesh in data.get('meshes',[]):
            for primitive in mesh.get('primitives',[]):
                assert 'TEXCOORD_0' in primitive.get('attributes',{}),slug
        blender_tri=sum(tri(o) for o in objects); actual_tri=glb_triangles(data)
        assert actual_tri==blender_tri,(slug,blender_tri,actual_tri)
        local=bounds(objects); world=[[local[s][i]+source_record['anchor_blender'][i] for i in range(3)] for s in (0,1)]
        record={
            'asset_id':source_record['asset_id'],'package_id':source_record['package_id'],'slug':slug,'display_name':source_record['display_name'],'category':category,'version':'v003',
            'source_blend':'assets/art/environments/open_world/source/tower_03/export/v003/env_tower_03-v003-runtime_optimized.blend',
            'optimized_blend': 'assets/art/environments/open_world/source/tower_03/export/v003/env_tower_03-v003-runtime_optimized.blend',
            'optimized_blend_sha256':sha256(BLEND),'objects':source_record['objects'],'root_object':source_record['root_object'],'anchor_blender':source_record['anchor_blender'],'local_bounds_blender':local,'bounds_blender':world,'front_direction':source_record['front_direction'],'triangle_count_blender':blender_tri,'triangle_count_glb':actual_tri,'glb':staged_rel.as_posix(),'glb_sha256':sha256(staged),
            'stable_glb':'assets/art/environments/open_world/components/tower_03/'+slug+'/env_tower_03_'+slug+'_visual_top3d.glb','runtime_glb':'assets/art/environments/open_world/components/tower_03/'+slug+'/env_tower_03_'+slug+'_visual_top3d.glb','stable_prefab':'assets/art/environments/open_world/runtime/tower_03/'+slug+'/env_tower_03_'+slug+'_root_top3d.tscn','runtime_integrated':False,
            'material_roles':source_record.get('material_roles',[]),'collision_status':'none_visual_only','formal_layout_rewritten':False,
        }
        records.append(record)
        print('EXPORTED',slug,actual_tri,flush=True)
    assert len(records)==217
    manifest={'schema':'shellstorm2.openworld.tower03.export.v003','asset_id':old['asset_id'],'version':'v003','source':'assets/art/environments/open_world/source/tower_03/export/v001/env_tower_03-v001-runtime.blend','source_sha256':old['source_sha256'],'protected_original_source':'assets/art/environments/open_world/source/tower_03/v001/塔楼03_设备天台办公楼_v001.blend','protected_original_source_sha256':'91b2f8f7d7ccfd483e76799e4b0a7573492b1741021eb3f7b34e5bfc24ec631e','derived':'assets/art/environments/open_world/source/tower_03/export/v003/env_tower_03-v003-runtime_optimized.blend','derived_sha256':sha256(BLEND),'staged_component_root':STAGED.relative_to(ROOT).as_posix(),'coordinate_map':'Blender (x,y,z) -> Godot (x,z,-y)','optimization_qa':V003_QA.relative_to(ROOT).as_posix(),'triangles_blend':sum(r['triangle_count_blender'] for r in records),'triangles_glb':sum(r['triangle_count_glb'] for r in records),'runtime_integrated':False,'stable_paths_touched':False,'records':records}
    (OUT_DIR/'export_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    catalog={'schema':'shellstorm2.openworld.tower03.catalog.trace.v003','asset_id':old['asset_id'],'version':'v003','role':'trace_only','source_blend':manifest['source'],'optimized_blend':manifest['derived'],'optimized_blend_sha256':manifest['derived_sha256'],'runtime_integrated':False,'records':[{'asset_id':r['asset_id'],'slug':r['slug'],'version':'v003','staged_glb':r['glb'],'stable_glb':r['stable_glb'],'runtime_glb':r['runtime_glb'],'stable_prefab':r['stable_prefab'],'runtime_integrated':False,'triangle_count_glb':r['triangle_count_glb'],'bounds_blender':r['bounds_blender'],'glb_sha256':r['glb_sha256']} for r in records]}
    CATALOG_DIR.mkdir(parents=True,exist_ok=True)
    (CATALOG_DIR/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    report={'passed':True,'asset_id':old['asset_id'],'version':'v003','records':217,'triangles_blend':manifest['triangles_blend'],'triangles_glb':manifest['triangles_glb'],'staged_component_root':manifest['staged_component_root'],'optimized_blend_sha256':manifest['derived_sha256'],'glb_sha256s_verified':True,'stable_glb_paths_version_free':True,'runtime_glb_paths_version_free':True,'runtime_prefab_paths_version_free':True,'runtime_integrated':False,'godot_modified':False,'ledger_modified':False}
    (OUT_DIR/'qa/export_v003.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('SUMMARY',json.dumps(report,ensure_ascii=False),flush=True)

if __name__=='__main__': main()
