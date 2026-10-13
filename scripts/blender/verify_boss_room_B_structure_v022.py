"""Independent native geometry, reassembly and package checks for v022."""
import bpy,json,sys,math,hashlib,importlib.util
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(r'I:/工作项目/shellstrom2/ShellStorm2');sys.path.insert(0,str(ROOT/'scripts'))
from workspace_paths import work_path
DEST=ROOT/'art_source/environments/tower_zones/expedition/source/room_types/boss_room_B/v022'
WORK=work_path('outputs/boss_structure_v022/geometry_report.json').parent
spec=importlib.util.spec_from_file_location('validator',r'C:/Users/zhuangmenghong/.agents/skills/blender-game-prop-standard/scripts/validate_game_prop.py');v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
catalog=json.loads((DEST/'component_catalog.json').read_text(encoding='utf-8'))['components']
records=json.loads((DEST/'component_instances.json').read_text(encoding='utf-8'))['instances']
plan=json.loads((DEST/'component_plan.json').read_text(encoding='utf-8'))
def bounds(points):return [[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]]
def points(o):return [o.matrix_world@m.matrix_basis@vert.co for m in o.instance_collection.objects for vert in m.data.vertices]
def near(a,b,t=1e-4):return abs(a-b)<t
inst=[o for o in bpy.context.scene.objects if o.instance_type=='COLLECTION']
decks=[o for o in inst if o.instance_collection.name in ['输出资产包_deck_armor_5m','输出资产包_deck_emblem_5m']]
deck=bounds([p for o in decks for p in points(o)])
bridges=[]
for s in (-1,1):
 obs=[o for o in inst if o.instance_collection.name=='输出资产包_bridge_deck_5m' and o.location.x*s>0]
 bridges.append(bounds([p for o in obs for p in points(o)]))
checks={'component_budget':len(catalog)==len(plan['components'])<=50,'instance_count':len(inst)==len(records),'platform_25x25':near(deck[1][0]-deck[0][0],25) and near(deck[1][1]-deck[0][1],25),'platform_center_xy':near(deck[0][0],-12.5) and near(deck[0][1],-12.5),'platform_walk_top':near(deck[1][2],0,.03),'bridges_each_20x5':all(near(b[1][0]-b[0][0],20) and near(b[1][1]-b[0][1],5) for b in bridges),'bridge_top_zero':all(near(b[1][2],0) for b in bridges),'bridge_interfaces_coincident':near(bridges[0][1][0],deck[0][0]) and near(bridges[1][0][0],deck[1][0]),'unit_instance_scale':all(all(near(k,1) for k in o.scale) for o in inst),'output_instances_only':all(o.type=='EMPTY' and o.instance_type=='COLLECTION' for o in bpy.data.collections['02_游戏输出_组件实例布局'].objects)}
replay=[]
for r in records:
 o=bpy.data.objects[r['instance_id']];m=Matrix.Translation(Vector(r['position_m']))@Matrix.Rotation(math.radians(r['rotation_y_deg']),4,'Z')
 replay.append(max(abs(m[i][j]-o.matrix_world[i][j]) for i in range(4) for j in range(4)))
checks['json_reassembly_transform_match']=max(replay)<1e-5
fam={}
for p in plan['components']:fam[p['component_family']]=fam.get(p['component_family'],0)+1
checks['family_variants_at_most_three']=max(fam.values())<=3
package_checks=[]
for c in catalog:
 col=bpy.data.collections[c['collection']];pts=[o.matrix_basis@vert.co for o in col.objects for vert in o.data.vertices];b=bounds(pts)
 identity=all(max(abs(o.matrix_basis[i][j]-(1 if i==j else 0)) for i in range(4) for j in range(4))<1e-6 for o in col.objects)
 package_checks.append({'slug':c['slug'],'nonempty':len(col.objects)>0,'bottom_center_origin':near(b[0][2],0) and near(b[0][0]+b[1][0],0) and near(b[0][1]+b[1][1],0),'identity_mesh_transform':identity,'zero_collection_offset':col.instance_offset.length<1e-7,'unique_object_ownership':all(len(o.users_collection)==1 for o in col.objects),'actual_bounds':b})
checks['all_package_contracts']=all(all(p[k] for k in ('nonempty','bottom_center_origin','identity_mesh_transform','zero_collection_offset','unique_object_ownership')) for p in package_checks)
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];uv=[v.audit_palette_uv(o) for o in meshes];checks['all_faces_palette_valid']=all(r['valid_island_polygon_count']==r['polygon_count'] for r in uv)
report={'checks':checks,'platform_bounds':deck,'bridge_bounds':bridges,'components':len(catalog),'instances':len(inst),'formal_instances':sum(not r['draft'] for r in records),'draft_instances':sum(r['draft'] for r in records),'valid_uv_faces':sum(r['valid_island_polygon_count'] for r in uv),'total_faces':sum(r['polygon_count'] for r in uv),'package_checks':package_checks,'max_json_replay_matrix_error':max(replay),'runtime_validation':'not performed; Blender source delivery only'}
standalone=[]
for c in catalog:
 bpy.ops.wm.open_mainfile(filepath=c['component_blend']);meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];uv=[v.audit_palette_uv(o) for o in meshes]
 standalone.append({'slug':c['slug'],'loaded':True,'meshes':len(meshes),'has_preview_camera':bpy.context.scene.camera is not None,'uv_valid':all(r['valid_island_polygon_count']==r['polygon_count'] for r in uv),'palette_exists':all(Path(bpy.path.abspath(i.filepath)).is_file() for i in bpy.data.images if i.source=='FILE')})
report['standalone_packages']=standalone;checks['standalone_packages_load_and_uv']=all(p['loaded'] and p['meshes'] and p['has_preview_camera'] and p['uv_valid'] and p['palette_exists'] for p in standalone)
report['passed']=all(checks.values());(WORK/'geometry_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps({'passed':report['passed'],'checks':checks,'instances':len(inst)},ensure_ascii=False))
if not report['passed']:raise RuntimeError('BOSS SOURCE VERIFICATION FAILED')
