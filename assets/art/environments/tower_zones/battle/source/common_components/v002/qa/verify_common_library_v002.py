import bpy,json
from pathlib import Path

ROOT=Path('/Users/summercards/ShellStorm2')
OUT=ROOT/'assets/art/environments/tower_zones/battle/source/common_components/v002'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'战局区块_通用组件库_v002.blend'))
catalog=json.loads((OUT/'component_packages_v002/catalog.json').read_text())
dedupe=json.loads((OUT/'component_packages_v002/deduplication_report.json').read_text())
bad=[];multi=[];bottom=[];front=[]
for p in catalog:
 col=bpy.data.collections.get(p['blender_collection']);root=bpy.data.objects.get(p['root_object'])
 if not col or sorted(o.name for o in col.objects if o.type=='MESH')!=sorted(p['objects']):bad.append(p['slug'])
 if not root or root.get('front_direction')!='+Y':front.append(p['slug']);continue
 for name in p['objects']:
  o=bpy.data.objects.get(name)
  if not o or o.parent!=root:bad.append(p['slug']);continue
  if len([c for c in o.users_collection if c.name.endswith('_通用包')])!=1:multi.append(name)
  if min(v.co.z for v in o.data.vertices)<-0.0001:bottom.append(name)
 path=OUT/'component_packages_v002'/p['category'][:2]/p['slug']/'asset_manifest.json'
 if not path.exists() or json.loads(path.read_text())!=p:bad.append(p['slug'])
sigs=[p['geometry_signature'] for p in catalog]
report={'passed':not(bad or multi or bottom or front) and len(sigs)==len(set(sigs)) and len(catalog)==dedupe['unique_package_count'],
 'package_count':len(catalog),'category_count':len(set(p['category'] for p in catalog)),'output_mesh_count':sum(len(p['objects']) for p in catalog),
 'wall_package_count':sum(p['category']=='08_墙壁组件' for p in catalog),'floor_package_count':sum(p['category']=='09_地板组件' for p in catalog),
 'deduplicated_count':len(dedupe['removed_duplicates']),'duplicate_signatures':len(sigs)-len(set(sigs)),'manifest_mismatch':sorted(set(bad)),
 'multiple_package_objects':multi,'below_local_ground':bottom,'non_unified_front':front,'excluded_room_specific_packages':dedupe['excluded_room_specific_packages']}
(OUT/'qa/saved_scene_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps(report,ensure_ascii=False));raise SystemExit(0 if report['passed'] else 1)
