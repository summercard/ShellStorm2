import bpy,json,math,sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
R=Path(r'I:/工作项目/shellstrom2/ShellStorm2');W=R.parent/'ShellStorm2-work/outputs/boss_enclosure_v025';D=R/'art_source/environments/tower_zones/expedition/source/room_types/boss_room_B/v025'
scene=bpy.context.scene;bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
contract=json.loads((D/'enclosure_contract.json').read_text(encoding='utf-8'));allowed=set(contract['shell_instances']);allowed.update(o.name for o in scene.objects if o.name.startswith(('外壳门框_','外壳门扇_','外壳密封边_')))
verts=[];faces=[]
for ins in dg.object_instances:
 if not ins.is_instance or ins.parent.name not in allowed or ins.object.type!='MESH':continue
 mesh=ins.object.data;start=len(verts);verts.extend(ins.matrix_world@v.co for v in mesh.vertices);faces.extend(tuple(start+i for i in p.vertices) for p in mesh.polygons)
bvh=BVHTree.FromPolygons(verts,faces);miss=[];rays=0
for x in (-32,-15,0,15,32):
 for y in (-65,-40,-15,0,20):
  for z in [k+.5 for k in range(-35,35)]:
   for direction in [(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)]:
    rays+=1;hit=bvh.ray_cast(Vector((x,y,z)),Vector(direction),200)
    if hit[0] is None:miss.append({'origin':[x,y,z],'direction':direction})
door_miss=[]
for side in (-1,1):
 for yy in (-2,-1,0,1,2):
  for zz in (.1,1,2,3,4,5,5.9):
   if bvh.ray_cast(Vector((side*37,yy,zz)),Vector((side,0,0)),8)[0] is None:door_miss.append([side,yy,zz])
for xx in (-2,-1,0,1,2):
 for zz in (12.1,13,14,15,16,17,17.9):
  if bvh.ray_cast(Vector((xx,-70,zz)),Vector((0,-1,0)),8)[0] is None:door_miss.append(['entrance',xx,zz])
stair=[]
for k in range(100):
 y=-12.75-k*.5;hit=scene.ray_cast(dg,Vector((.05,y,20)),Vector((0,0,-1)),distance=25);expected=(k+1)*.12+.036
 stair.append({'step':k,'height':hit[1].z if hit[0] else None,'expected':expected,'ok':bool(hit[0]) and abs(hit[1].z-expected)<.04})
lights=[o for o in scene.objects if o.instance_collection and o.instance_collection.name=='输出资产包_stair_chase_light'];indices=sorted(o['sequence_index'] for o in lights)
doorwall_positions=sorted(round(o.location.z,3) for o in scene.objects if o.instance_collection and o.instance_collection.name=='输出资产包_enclosure_doorwall_5m')
checks={'sealed_shell_grid_rays':not miss,'outer_doors_seal':not door_miss,'doorwall_above_actual_opening':doorwall_positions==[6,6,18],'100_tread_heights':all(x['ok'] for x in stair),'independent_100_step_lights':len(lights)==100 and indices==list(range(100)),'no_remaining_draft_masters':not any(c.name.startswith('输出资产包_draft_') for c in bpy.data.collections)}
result={'checks':checks,'passed':all(checks.values()),'shell_ray_count':rays,'shell_misses':miss,'door_misses':door_miss,'steps':stair,'note':'Art envelope ray sampling, not manifold topology or gameplay collision validation'}
(W/'enclosure_acceptance.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps({'passed':result['passed'],'checks':checks,'misses':len(miss),'door_misses':len(door_miss)},ensure_ascii=False))
if not result['passed']:raise RuntimeError('Enclosure or stair verification failed')
