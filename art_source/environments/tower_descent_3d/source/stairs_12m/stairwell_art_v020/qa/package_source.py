import bpy,json,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];PREV=ROOT.parent/'stairwell_art_v019'
def write(p,d):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
def bounds(obs):
    pts=[o.matrix_world@v.co for o in obs for v in o.data.vertices]
    return {'min':[round(min(p[i] for p in pts),5) for i in range(3)],'max':[round(max(p[i] for p in pts),5) for i in range(3)]}
catalog=json.loads((PREV/'component_packages/catalog.json').read_text());catalog['version']='v020'
source=str(ROOT/'env_tower_stairwell_art_source_v020.blend')
for pack in catalog['packages']:
    old=json.loads((PREV/'component_packages'/pack['path']/'asset_manifest.json').read_text())
    objs=sorted(bpy.data.collections[pack['collection']].objects,key=lambda o:o.name)
    pack['asset_id']=pack['asset_id'].replace('V019','V020');pack['object_count']=len(objs);pack['bounds']=bounds(objs)
    old.update(asset_id=pack['asset_id'],version='v020',source_blend=source,output_blend=source,objects=[o.name for o in objs],root_object=objs[0].name,world_bounds=pack['bounds'],runtime_imported=False)
    old.update(collision_status='unchanged_runtime_not_exported',export_glb=None,layout_origin=[32.5,0,-9],front_direction='per_object_surface_normal',dependencies=['shared_palette'],animation=False,lights_in_output=False)
    old['object_anchors']={o.name:{'world_matrix':[list(r) for r in o.matrix_world],'host':o.get('host_object'),'emissive':any(m.name.startswith('04_') for m in o.data.materials)} for o in objs}
    write(ROOT/'component_packages'/pack['path']/'asset_manifest.json',old)
write(ROOT/'component_packages/catalog.json',catalog)
(ROOT/'component_packages/tree.txt').write_text('\n'.join(p['path']+' -> '+p['collection']+' ('+str(p['object_count'])+')' for p in catalog['packages'])+'\n')
manifest=json.loads((PREV/'asset_manifest.json').read_text())
manifest.update(version='v020',source_blend=str(Path(source).relative_to('/Users/summercards/ShellStorm2')),previous_source=str(PREV/'env_tower_stairwell_art_source_v019.blend'),output_mesh_count=sum(p['object_count'] for p in catalog['packages']),renders=['renders/'+n+'.png' for n in ['overview','wall_focus','floor_close','top','railing_opening','before_wall_focus','before_overview']],source_sha256=hashlib.sha256(Path(source).read_bytes()).hexdigest())
manifest['qa']={'report':'qa/QA_REPORT.md','scope_verifier':'qa/verify_scope.py','scope_result':'qa/scope_result.json','material_result':'qa/material_result.json'}
manifest['scope']={'editable':['wall_surfaces','floor_surfaces','wall_accessories','floor_attached_details','presentation_lights'],'locked':['stair_meshes','platform_railings','fixed_plant','original_wall_floor_geometry','existing_opening_positions','10_output_collections']}
manifest['asset_ledger']='assets/registry/ShellStorm2_美术资产台账_v001.xlsx#3D-场景通用'
manifest['scene_design_docs']=['docs/v0.1/05_技术施工_关卡生成与爬楼.md','docs/v0.1/05.1_关卡区块设计.md','docs/v0.1/10.1_3D场景美术生产流程.md']
manifest['floor_range']='stairs_12m_existing_assembly';manifest['design_scope']='Existing stairwell wall/floor art detail and wall accessories only'
write(ROOT/'asset_manifest.json',manifest)
print('PACKAGED',manifest['output_mesh_count'],len(catalog['packages']))
