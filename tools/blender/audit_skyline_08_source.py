"""Independent read-only audit of the saved SKYLINE source and package manifests."""
import bpy, json, math, hashlib
from pathlib import Path
from collections import Counter
from mathutils import Vector

R=Path(__file__).resolve().parents[2]
folder=Path(bpy.data.filepath).parent
catalog=json.loads((folder/'catalog.json').read_text(encoding='utf8'))
packages=catalog['packages']; errors=[]; observed=[]
game=next(c for c in bpy.data.collections if c.name.startswith('02_游戏输出'))
source=next(c for c in bpy.data.collections if c.name.startswith('01_制作组件'))
members=Counter()
for item in packages:
 col=bpy.data.collections.get(item['collection'])
 manifest=folder/'component_packages'/item['category']/item['slug']/'asset_manifest.json'
 if not col or not col.objects: errors.append('empty_or_missing_collection:'+item['slug']); continue
 if not manifest.exists(): errors.append('missing_manifest:'+item['slug']); continue
 disk=json.loads(manifest.read_text(encoding='utf8'))
 if disk!=item: errors.append('catalog_manifest_mismatch:'+item['slug'])
 if set(item['objects'])!=set(o.name for o in col.objects): errors.append('object_list_drift:'+item['slug'])
 verts=[]
 for obj in col.objects:
  members[obj.name]+=1
  verts.extend(obj.matrix_world@v.co for v in obj.data.vertices)
  if obj.type!='MESH': errors.append('non_mesh_output:'+obj.name)
  if len(obj.users_collection)!=1: errors.append('multiple_collection_links:'+obj.name)
  if obj.modifiers: errors.append('unevaluated_modifiers:'+obj.name)
  if any(abs(s-1)>1e-5 for s in obj.scale): errors.append('unapplied_scale:'+obj.name)
 mn=[min(v[j] for v in verts) for j in range(3)]; mx=[max(v[j] for v in verts) for j in range(3)]
 if max(abs(a-b) for a,b in zip(mn,item['bounds_min']))>.003: errors.append('bounds_min_drift:'+item['slug'])
 if max(abs(a-b) for a,b in zip(mx,item['bounds_max']))>.003: errors.append('bounds_max_drift:'+item['slug'])
 observed.append(dict(slug=item['slug'],min=mn,max=mx,mesh_count=len(col.objects)))
all_output=list(game.all_objects)
if set(members)!=set(o.name for o in all_output): errors.append('unregistered_output_objects')
if any(v!=1 for v in members.values()): errors.append('multi_package_membership')
manifest_paths=list((folder/'component_packages').rglob('asset_manifest.json'))
if len(manifest_paths)!=len(packages): errors.append('manifest_count_mismatch')
floors=sorted([item for item in observed if item['slug'].startswith('floor_')],key=lambda p:p['slug'])
if len(floors)!=8: errors.append('floor_count_not_eight')
for i,floor in enumerate(floors):
 if abs(floor['min'][2]-i*4)>.003 or abs(floor['max'][2]-(i+1)*4)>.003: errors.append('floor_height_drift:'+floor['slug'])
tiles=[item for item in observed if item['slug'].startswith('tile_')]
if len(tiles)!=192: errors.append('tile_count_not_192')
for tile in tiles:
 if abs(tile['max'][2]-32)>.45 or tile['min'][2]<31.59: errors.append('roof_tile_elevation:'+tile['slug'])
raw=[o.matrix_world@v.co for o in all_output for v in o.data.vertices]
if min(v.z for v in raw)<-.001: errors.append('below_ground')
preview_files=list((folder/'previews').glob('*.png'))
if len(preview_files)!=6: errors.append('preview_count_not_six')
if len(bpy.data.materials)!=4: errors.append('material_count_not_four')
if not source.hide_viewport or not source.hide_render: errors.append('source_not_hidden')
if game.hide_viewport or game.hide_render: errors.append('output_not_visible')
palette=R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
for img in bpy.data.images:
 if img.source=='FILE' and img.filepath:
  if Path(bpy.path.abspath(img.filepath)).resolve()!=palette.resolve(): errors.append('non_palette_image:'+img.name)
  if img.packed_file: errors.append('palette_packed')
report=dict(passed=not errors,errors=errors,asset_id=catalog['asset_id'],version=catalog['version'],scope='new_building_only',locked_existing_assets='not_loaded_not_modified',floor_count=len(floors),floor_height_m=4,roof_z_m=32,package_count=len(packages),manifest_count=len(manifest_paths),category_counts=dict(Counter(p['category'] for p in packages)),floor_tile_count=len(tiles),output_meshes=len(all_output),source_meshes=sum(o.type=='MESH' for o in source.all_objects),output_polygons=sum(len(o.data.polygons) for o in all_output),output_vertices=sum(len(o.data.vertices) for o in all_output),material_count=len(bpy.data.materials),preview_count=len(preview_files),world_bounds_min=[min(v[j] for v in raw) for j in range(3)],world_bounds_max=[max(v[j] for v in raw) for j in range(3)],package_bounds=observed,runtime_status='not_exported_not_integrated',collision_status='not_authored',LOD_status='not_authored')
(folder/'qa/source_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({k:v for k,v in report.items() if k!='package_bounds'},ensure_ascii=False,indent=2))
raise SystemExit(0 if report['passed'] else 1)
