import bpy, json, hashlib, math
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / 'assets/art/environments/tower_zones/expedition/source/common_components/v001'
BLEND = LIB / 'expedition_boss_room_components_source_v001.blend'
CATALOG = LIB / 'component_catalog.json'
SOURCE = ROOT / 'assets/art/environments/tower_zones/expedition/source/room_types/boss_room/v002/Boss房种类_故障数据库_50x40m_v002.blend'
ROLE_NAMES = {'01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光'}

def all_objects(c):
    result=list(c.objects)
    for child in c.children:
        result += all_objects(child)
    return result

def mesh_objects(c):
    return [o for o in all_objects(c) if o.type=='MESH']

def near(v, target, eps=1e-5):
    return all(abs(float(v[i])-float(target[i])) <= eps for i in range(3))

bpy.ops.wm.open_mainfile(filepath=str(BLEND))
catalog=json.loads(CATALOG.read_text(encoding='utf-8'))
packages=catalog['packages']
output_root=next(c for c in bpy.data.collections if c.name=='02_游戏输出_独立资产包_v001')
editable_root=next(c for c in bpy.data.collections if c.name=='01_制作组件_按组件拆分')
collections={c.name:c for c in output_root.children_recursive if any(obj.name.startswith('ROOT_') for obj in c.objects)}
editable_collections={c.name:c for c in editable_root.children_recursive if any(obj.name.startswith('ROOT_') for obj in c.objects)}
report={'blend_exists':BLEND.exists(),'source_hash_match':hashlib.sha256(SOURCE.read_bytes()).hexdigest()==catalog['source_room_type_sha256'],'package_count':len(packages),'catalog_collection_count':len(collections),'mesh_count':0,'output_instance_offset_violations':[],'root_transform_violations':[],'mesh_transform_violations':[],'palette_uv_violations':[],'material_role_violations':[],'duplicate_output_object_names':False,'room_owned_geometry_violations':[],'missing_package_collections':[]}
seen=set()
for row in packages:
    slug=row['source_package_id']; c=collections.get(row['collection'])
    if c is None:
        report['missing_package_collections'].append(slug); continue
    if not near(c.instance_offset,(0,0,0)):
        report['output_instance_offset_violations'].append((slug,list(c.instance_offset)))
    root=bpy.data.objects.get(row['root_object'])
    if root is None or root.parent is not None or not near(root.location,(0,0,0)) or not near(root.rotation_euler,(0,0,0)) or not near(root.scale,(1,1,1)):
        report['root_transform_violations'].append(slug)
    objs=mesh_objects(c); report['mesh_count'] += len(objs)
    for o in objs:
        if o.name in seen: report['duplicate_output_object_names']=True
        seen.add(o.name)
        if o.parent is not root or not near(o.location,(0,0,0)) or not near(o.rotation_euler,(0,0,0)) or not near(o.scale,(1,1,1)):
            report['mesh_transform_violations'].append(o.name)
        if not o.data.uv_layers.get('PaletteUV'):
            report['palette_uv_violations'].append(o.name)
        for material in o.data.materials:
            if material and material.name not in ROLE_NAMES:
                report['material_role_violations'].append((o.name,material.name))
        if o.get('room_owned_geometry',False): report['room_owned_geometry_violations'].append(o.name)
report['all_instance_offsets_zero']=not report['output_instance_offset_violations']
report['all_roots_identity']=not report['root_transform_violations']
report['all_mesh_transforms_identity']=not report['mesh_transform_violations']
report['all_palette_uv_present']=not report['palette_uv_violations']
report['all_material_roles_shared']=not report['material_role_violations']
report['all_packages_nonempty']=not report['missing_package_collections']
report['all_pass']=all([report['blend_exists'],report['source_hash_match'],report['package_count']==214,report['catalog_collection_count']==214,report['mesh_count']==602,report['all_instance_offsets_zero'],report['all_roots_identity'],report['all_mesh_transforms_identity'],report['all_palette_uv_present'],report['all_material_roles_shared'],not report['duplicate_output_object_names'],not report['room_owned_geometry_violations'],report['all_packages_nonempty']])
(LIB/'component_probe_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,ensure_ascii=False,indent=2))
assert report['all_pass'], report
