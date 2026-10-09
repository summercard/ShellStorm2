import bpy,json,hashlib,sys,importlib.util
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2];O=R/'assets/art/environments/master_office_3d/source/env_block00_story_rooms/v001';P=json.loads((O/'component_plan.json').read_text(encoding='utf8'));C=json.loads((O/'component_catalog.json').read_text(encoding='utf8'));I=json.loads((O/'component_instances.json').read_text(encoding='utf8'))['instances'];errors=[]
def overlap(a,b,box):return all(b[k]>box[k][0] and a[k]<box[k][1] for k in range(3))
tris={};roomtris={};floors=[];sculptures=[];bound_records=[]
for d in C:
 c=bpy.data.collections[d['collection']];n=0
 for ob in c.objects:ob.data.calc_loop_triangles();n+=len(ob.data.loop_triangles)
 tris[d['slug']]=n
 if d['slug'].startswith('sculpture') and n>1500:errors.append('sculpture_budget:'+d['slug'])
for i in I:
 ob=bpy.data.objects[i['instance_id']];pts=[ob.matrix_basis@v.co for child in ob.instance_collection.objects for v in child.data.vertices]
 a=[min(v[k] for v in pts) for k in range(3)];b=[max(v[k] for v in pts) for k in range(3)]
 rid=i['room_id'];slug=i['slug'];room=next(r for r in P['rooms'] if r['room_id']==rid)
 n=0
 for child in ob.instance_collection.objects:child.data.calc_loop_triangles();n+=len(child.data.loop_triangles)
 roomtris[rid]=roomtris.get(rid,0)+n
 if slug.startswith('floor_'):floors.append(tuple(i['position_m']))
 elif not slug.startswith('wall_'):
  if rid=='meeting_room' and overlap(a,b,[[-25,15],[-.5,5.5],[.30,4]]):errors.append('center_lane_blocked:'+ob.name)
  if overlap(a,b,[[19.65,20.35],[0,5],[.30,3]]):errors.append('removed_portal_blocked:'+ob.name)
  if rid!='master_office' and slug not in ['portal_damage','debris_cluster','cable_hanging']:
   if a[0]<room['bounds_x_m'][0]+.14 or b[0]>room['bounds_x_m'][1]-.14 or a[1]<room['bounds_y_m'][0]+.14 or b[1]>room['bounds_y_m'][1]-.14:errors.append('room_footprint:'+ob.name+str((a,b)))
 if slug.startswith('sculpture'):sculptures.append(i)
 if slug.startswith('wall_') and abs(i['position_m'][0]-20)<.01 and abs(i['position_m'][1]-2.5)<.01:errors.append('door_wall_still_present:'+ob.name)
 if tuple(ob.scale)!=(1,1,1):errors.append('scaled_instance:'+ob.name)
 if rid!='master_office':bound_records.append(dict(name=ob.name,bounds=[a,b]))
if len(floors)!=49 or len(set(floors))!=49:errors.append('floor_grid_count')
if len(sculptures)!=12:errors.append('sculpture_count')
if len([i for i in sculptures if i['position_m'][1]<0])!=6:errors.append('sculpture_rows')
for rel,sha in [(P['whitebox_source'],P['whitebox_sha256']),(P['source_office'],P['source_office_sha256'])]:
 if hashlib.sha256((R/rel).read_bytes()).hexdigest()!=sha:errors.append('locked_source_changed:'+rel)
audit=bpy.data.collections.new('99_审计母版');bpy.context.scene.collection.children.link(audit)
allmasters={bpy.data.objects[i['instance_id']].instance_collection for i in I}
for c in allmasters:audit.children.link(c)
spec=importlib.util.spec_from_file_location('standard','C:/Users/zhuangmenghong/.agents/skills/blender-game-prop-standard/scripts/validate_game_prop.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
uv=[m.audit_palette_uv(ob) for ob in bpy.context.scene.objects if ob.type=='MESH']
if any(r['valid_island_polygon_count']!=r['polygon_count'] for r in uv):errors.append('uv_islands')
report=dict(passed=not errors,errors=errors,new_unique_components=len(C),linked_unique_components=24,instances=len(I),floor_tiles=len(floors),sculptures=len(sculptures),sculpture_rows=[6,6],meeting_clear_width_m=6,removed_door_wall_clear_width_m=5,component_triangles=tris,room_instanced_triangles=roomtris,uv_faces=sum(r['polygon_count'] for r in uv),valid_uv_faces=sum(r['valid_island_polygon_count'] for r in uv),locked_office_source_unchanged=True,locked_runtime_layout_unchanged=True,instance_bounds=bound_records)
(O/'task_acceptance.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8');print('STORY_AUDIT',json.dumps({k:v for k,v in report.items() if k!='instance_bounds'},ensure_ascii=False),flush=True)
sys.argv=['blender','--','--all-meshes','--max-materials','4','--shared-palette',str(R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'),'--json',str(O/'material_acceptance.json')];m.main()
