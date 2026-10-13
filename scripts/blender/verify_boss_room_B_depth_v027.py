import bpy,json
from pathlib import Path
from mathutils import Vector
W=Path(r'I:/工作项目/shellstrom2/ShellStorm2-work/outputs/boss_depth_v027')
c=json.loads((W/'extension_contract.json').read_text(encoding='utf-8'))
def bottom(o):return min((o.matrix_world@m.matrix_basis@v.co).z for m in o.instance_collection.objects for v in m.data.vertices)
r={'tower_bottoms':{n:bottom(bpy.data.objects[n]) for n in c['tower_instances']},'foundation_bottoms':{n:bottom(bpy.data.objects[n]) for n in c['matrix_foundations']},'side_front_dots':{},'position_errors':{}}
for n,old in c['side_matrix_instances'].items():
 o=bpy.data.objects[n];r['side_front_dots'][n]=(o.matrix_world.to_quaternion()@Vector((0,-1,0))).dot(Vector((-o.location.x,0,0)).normalized());r['position_errors'][n]=(o.location-Vector(old['position'])).length
r['checks']={'all_towers_below_floor':max(r['tower_bottoms'].values())<-36,'all_foundations_below_floor':max(r['foundation_bottoms'].values())<-36,'all_side_fronts_inward':min(r['side_front_dots'].values())>.9999,'side_origins_unchanged':max(r['position_errors'].values())<1e-5,'original_details_unchanged':max(c['original_vertex_world_errors'].values())<1e-4,'low_poly_additions':all(x['after_triangles']-x['before_triangles']==36 for x in c['master_triangle_budget'])}
r['passed']=all(r['checks'].values());(W/'depth_acceptance.json').write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf-8');print(r['checks']);assert r['passed']
