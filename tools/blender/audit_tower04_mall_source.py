"""Read-only saved-file audit of Tower04 source, materials, bounds and packages."""
import bpy
import hashlib
import json
from collections import Counter
from pathlib import Path

R=Path(__file__).resolve().parents[2]
folder=Path(bpy.data.filepath).parent
catalog=json.loads((folder/'catalog.json').read_text(encoding='utf8'))
errors=[]
game=next(c for c in bpy.data.collections if c.name.startswith('02_游戏输出'))
source=next(c for c in bpy.data.collections if c.name.startswith('01_制作组件'))
members=Counter(); observed=[]
for item in catalog['packages']:
    col=bpy.data.collections.get(item['collection'])
    manifest=folder/'component_packages'/item['category']/item['slug']/'asset_manifest.json'
    if not col or not col.objects: errors.append('empty:'+item['slug']); continue
    if not manifest.exists() or json.loads(manifest.read_text(encoding='utf8'))!=item: errors.append('manifest_drift:'+item['slug'])
    if set(item['objects'])!=set(o.name for o in col.objects): errors.append('object_list:'+item['slug'])
    vertices=[]
    for ob in col.objects:
        members[ob.name]+=1
        if ob.type!='MESH' or len(ob.users_collection)!=1: errors.append('ownership:'+ob.name); continue
        if ob.modifiers or any(abs(s-1)>.00001 for s in ob.scale): errors.append('unfrozen_transform:'+ob.name)
        vertices.extend(ob.matrix_world@v.co for v in ob.data.vertices)
    mn=[min(v[j] for v in vertices) for j in range(3)]; mx=[max(v[j] for v in vertices) for j in range(3)]
    if max(abs(a-b) for a,b in zip(mn,item['bounds_min']))>.003 or max(abs(a-b) for a,b in zip(mx,item['bounds_max']))>.003: errors.append('bounds:'+item['slug'])
    observed.append(dict(slug=item['slug'],bounds_min=mn,bounds_max=mx,polygon_count=sum(len(o.data.polygons) for o in col.objects)))
outputs=list(game.all_objects)
if set(members)!=set(o.name for o in outputs) or any(v!=1 for v in members.values()): errors.append('output_ownership')
if len(list((folder/'component_packages').rglob('asset_manifest.json')))!=len(catalog['packages']): errors.append('manifest_count')
raw=[o.matrix_world@v.co for o in outputs for v in o.data.vertices]
mn=[min(v[j] for v in raw) for j in range(3)]; mx=[max(v[j] for v in raw) for j in range(3)]
if abs(mx[0]-mn[0]-150)>.003 or abs(mx[1]-mn[1]-50)>.003 or abs(mn[2])>.003: errors.append('150x50_ground_envelope')
floors=sorted((p for p in observed if p['slug'].startswith('oval_level_')),key=lambda p:p['slug'])
if len(floors)!=5: errors.append('five_storeys')
for i,item in enumerate(floors):
    if abs(item['bounds_min'][2]-i*5)>.003: errors.append('floor_baseline:'+item['slug'])
if len(bpy.data.materials)!=4 or set(m.name for m in bpy.data.materials)!=set(catalog['material_roles']): errors.append('material_roles')
# Compare shader input/socket values and links to donor without modifying it.
def signature(mat):
    nodes=[]
    for n in mat.node_tree.nodes:
        inputs=[]
        for s in n.inputs:
            if not hasattr(s,'default_value'): continue
            v=s.default_value
            if not isinstance(v,(int,float,str,bool)): v=list(v)
            if isinstance(v,float): v=round(v,7)
            if isinstance(v,list): v=[round(x,7) if isinstance(x,float) else x for x in v]
            inputs.append([s.name,v])
        nodes.append([n.name,n.type,inputs,getattr(n,'interpolation',None),getattr(n,'uv_map',None)])
    links=sorted([l.from_node.name,l.from_socket.name,l.to_node.name,l.to_socket.name] for l in mat.node_tree.links)
    return {'nodes':nodes,'links':links}
current={m.name:signature(m) for m in bpy.data.materials}
with bpy.data.libraries.load(str(R/catalog['material_source']),link=False) as (a,b): b.materials=list(catalog['material_roles'])
donor={name:signature(mat) for name,mat in zip(catalog['material_roles'],b.materials)}
if current!=donor: errors.append('material_shader_not_identical_to_original')
# Donor datablocks are transient audit-only, never saved into the delivered file.
for path,sha in catalog['locked_asset_hashes'].items():
    if hashlib.sha256((R/path).read_bytes()).hexdigest()!=sha: errors.append('locked_asset_changed:'+path)
import_text=(R/(catalog['shared_palette']+'.import')).read_text(encoding='utf8')
if 'mipmaps/generate=false' not in import_text or 'compress/mode=0' not in import_text: errors.append('shared_palette_import_not_lossless_no_mipmap')
if not source.hide_viewport or not source.hide_render or game.hide_viewport or game.hide_render: errors.append('visibility')
for item in catalog['packages']:
    for obname in item['objects']:
        for mat in bpy.data.objects[obname].data.materials:
            for n in mat.node_tree.nodes:
                if n.type=='TEX_IMAGE' and n.image:
                    if n.image.packed_file or Path(bpy.path.abspath(n.image.filepath)).resolve()!=(R/catalog['shared_palette']).resolve(): errors.append('texture_path:'+obname)
                    if n.interpolation!='Closest': errors.append('non_nearest:'+obname)
preview_count=len(list((folder/'previews').glob('*.png')))
if preview_count!=6: errors.append('preview_count')
report=dict(passed=not errors,errors=errors,asset_id=catalog['asset_id'],version=catalog['version'],material_count=4,new_materials_created=0,original_shader_signatures_match=current==donor,locked_assets_unchanged=not any(e.startswith('locked_asset') for e in errors),footprint_m=[mx[0]-mn[0],mx[1]-mn[1]],bounds_min=mn,bounds_max=mx,floor_count=len(floors),package_count=len(catalog['packages']),output_mesh_count=len(outputs),output_polygons=sum(len(o.data.polygons) for o in outputs),category_counts=dict(Counter(p['category'] for p in catalog['packages'])),preview_count=preview_count,runtime_status='not_exported_not_integrated',packages=observed)
(folder/'qa/source_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({k:v for k,v in report.items() if k!='packages'},ensure_ascii=False,indent=2))
raise SystemExit(0 if not errors else 1)
