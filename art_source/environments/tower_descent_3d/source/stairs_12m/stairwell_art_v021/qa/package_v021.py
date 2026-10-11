import bpy,json,hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];PREV=ROOT.parent/'stairwell_art_v020';CP=ROOT/'component_packages'
LEAVES=['通用墙组件_资产包','通用地板组件_资产包','通用楼梯组件_资产包','墙面装甲与结构框_装饰组件','地面导光与警示_装饰组件','工业管线_装饰组件','灯带与发光几何_装饰组件','楼层标识与海报_装饰组件','控制盒_装饰组件','固定绿植_装饰组件']
def write(p,d):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
def bounds(obs):
    pts=[o.matrix_world@v.co for o in obs for v in o.data.vertices]
    return {'min':[round(min(p[i] for p in pts),5) for i in range(3)],'max':[round(max(p[i] for p in pts),5) for i in range(3)]}
cat=json.loads((PREV/'component_packages/catalog.json').read_text());cat['version']='v021';source=str(ROOT/'env_tower_stairwell_dual_art_source_v021.blend')
for p in cat['packages']:
    old_path=PREV/'component_packages'/p['path']/'asset_manifest.json';m=json.loads(old_path.read_text());obs=sorted((o for o in bpy.data.collections[p['collection']].objects if o.type=='MESH'),key=lambda o:o.name)
    p['asset_id']=p['asset_id'].replace('V020','V021');p['object_count']=len(obs);p['bounds']=bounds(obs)
    m.update(asset_id=p['asset_id'],version='v021',source_blend=source,output_blend=source,objects=[o.name for o in obs],root_object=obs[0].name,world_bounds=p['bounds'],runtime_imported=False)
    m['assembly_instances']={'A_100_to_99':sum(o.get('stairwell_instance')=='A_100_to_99' for o in obs),'B_99_to_98':sum(o.get('stairwell_instance')=='B_99_to_98' for o in obs)}
    write(CP/p['path']/'asset_manifest.json',m)
cat['assemblies']=[
 {'asset_id':'ENV-TOWER-STAIRWELL-ROOFTOP-12M','display_name':'楼梯A（100→99）','root':'楼梯A_100至99层_装配根','position':[-32.5,0,0],'rotation_z_deg':180,'object_count':382},
 {'asset_id':'ENV-TOWER-STAIRWELL-GENERIC-12M','display_name':'楼梯B（99→98）','root':'楼梯B_99至98层_装配根','position':[32.5,0,-9],'rotation_z_deg':0,'object_count':382},
]
write(CP/'catalog.json',cat);(CP/'tree.txt').write_text('\n'.join(p['path']+' -> '+p['collection']+' ('+str(p['object_count'])+')' for p in cat['packages'])+'\nassemblies/stair_a_100_99 -> 楼梯A_100至99层_装配根 (382)\nassemblies/stair_b_99_98 -> 楼梯B_99至98层_装配根 (382)\n')
for a in cat['assemblies']:
    root=bpy.data.objects[a['root']];tag='A_100_to_99' if 'A_' in root.name else 'B_99_to_98';obs=[o for name in LEAVES for o in bpy.data.collections[name].objects if o.get('stairwell_instance')==tag]
    write(CP/'assemblies'/('stair_a_100_99' if tag.startswith('A') else 'stair_b_99_98')/'asset_manifest.json',{**a,'version':'v021','source_blend':source,'blender_component_collections':LEAVES,'objects':[o.name for o in sorted(obs,key=lambda x:x.name)],'world_bounds':bounds(obs),'scale':[1,1,1],'runtime_imported':False,'export_glb':None,'collision_status':'not_exported_runtime_unchanged'})
manifest=json.loads((PREV/'asset_manifest.json').read_text());manifest.update(version='v021',source_blend=str(Path(source).relative_to('/Users/summercards/ShellStorm2')),previous_source=str((PREV/'env_tower_stairwell_art_source_v020.blend').relative_to('/Users/summercards/ShellStorm2')),output_mesh_count=764,component_package_count=10,assembly_count=2,renders=['renders/dual_overview.png','renders/dual_top.png','renders/stair_a_100_99.png','renders/stair_b_99_98.png'],source_sha256=hashlib.sha256(Path(source).read_bytes()).hexdigest(),runtime_imported=False,design_scope='Duplicate the complete stairwell as an independent 99-to-98 assembly and place both stairwells at the exact block-contract transforms')
manifest['assembly_contract']=cat['assemblies'];manifest['qa']={'report':'qa/QA_REPORT.md','scope_result':'qa/verify_result.json','material_result':'qa/material_result.json'}
write(ROOT/'asset_manifest.json',manifest)
print('V021_PACKAGED',sum(p['object_count'] for p in cat['packages']))
