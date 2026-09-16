import bpy,json
from pathlib import Path
ROOT=Path('/Users/summercards/ShellStorm2');OUT=ROOT/'assets/art/environments/tower_zones/battle/source/common_components/v003'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'战局区块_通用组件库_v003.blend'))
cat=json.loads((OUT/'component_packages_v003/catalog.json').read_text());task=json.loads((OUT/'qa/task_validation.json').read_text())
bad=[];bottom=[];front=[]
for p in cat:
 col=bpy.data.collections.get(p['blender_collection']);root=bpy.data.objects.get(p['root_object'])
 if not col or sorted(o.name for o in col.objects if o.type=='MESH')!=sorted(p['objects']):bad.append(p['slug'])
 if not root or root.get('front_direction')!='+Y':front.append(p['slug']);continue
 for n in p['objects']:
  o=bpy.data.objects.get(n)
  if not o or o.parent!=root or len([c for c in o.users_collection if c.name.endswith('_通用包')])!=1:bad.append(p['slug']);continue
  if min(v.co.z for v in o.data.vertices)<-.0001:bottom.append(n)
 path=OUT/'component_packages_v003'/p['category'][:2]/p['slug']/'asset_manifest.json'
 if not path.exists() or json.loads(path.read_text())!=p:bad.append(p['slug'])
wall=next(p for p in cat if p['slug']=='wall_standard_5m');dims=wall['bounds_size']
report={'passed':len(cat)==23 and not(bad or bottom or front) and all(abs(a-b)<.001 for a,b in zip(dims,[5,.3,11.9])),
 'package_count':len(cat),'category_count':len(set(p['category'] for p in cat)),'output_mesh_count':sum(len(p['objects']) for p in cat),
 'wall_package_count':sum(p['category']=='08_墙壁组件' for p in cat),'floor_package_count':sum(p['category']=='09_地板组件' for p in cat),
 'wall_dimensions_m':dims,'kept_by_group':task['kept_by_group'],'manifest_mismatch':sorted(set(bad)),'below_local_ground':bottom,'non_unified_front':front}
(OUT/'qa/saved_scene_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False));raise SystemExit(0 if report['passed'] else 1)
