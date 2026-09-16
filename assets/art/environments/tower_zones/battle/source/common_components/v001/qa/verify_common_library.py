import bpy,json
from pathlib import Path
from mathutils import Vector

ROOT=Path('/Users/summercards/ShellStorm2')
OUT=ROOT/'assets/art/environments/tower_zones/battle/source/common_components/v001'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'战局区块_通用组件库_v001.blend'))
catalog=json.loads((OUT/'component_packages_v001/catalog.json').read_text())
bad=[];multi=[];bottom=[];missing_roots=[]
for p in catalog:
    col=bpy.data.collections.get(p['blender_collection'])
    if not col or sorted(o.name for o in col.objects if o.type=='MESH')!=sorted(p['objects']): bad.append(p['slug'])
    root=bpy.data.objects.get(p['root_object'])
    if root is None or root.type!='EMPTY': missing_roots.append(p['slug']);continue
    for name in p['objects']:
        o=bpy.data.objects.get(name)
        if not o or o.parent!=root: bad.append(p['slug']);continue
        if len([c for c in o.users_collection if c.name.endswith('_通用包')])!=1: multi.append(name)
        local_min=min(v.co.z for v in o.data.vertices)
        if local_min < -0.0001: bottom.append((name,local_min))
    m=OUT/'component_packages_v001'/p['category'][:2]/p['slug']/'asset_manifest.json'
    if not m.exists() or json.loads(m.read_text())!=p: bad.append(p['slug'])
report={'passed':len(catalog)==43 and not(bad or multi or bottom or missing_roots),'package_count':len(catalog),
        'output_mesh_count':sum(len(p['objects']) for p in catalog),'category_count':len(set(p['category'] for p in catalog)),
        'manifest_mismatch':sorted(set(bad)),'multiple_package_objects':multi,'below_local_ground':bottom,'missing_roots':missing_roots,
        'material_names':sorted(m.name for m in bpy.data.materials),'palette_images':[i.filepath for i in bpy.data.images if '设施低亮多巴胺色盘' in i.name or '设施低亮多巴胺色盘' in i.filepath]}
(OUT/'qa/saved_scene_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps(report,ensure_ascii=False));raise SystemExit(0 if report['passed'] else 1)
