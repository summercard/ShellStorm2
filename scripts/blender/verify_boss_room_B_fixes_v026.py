import bpy,json
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
R=Path(r'I:/工作项目/shellstrom2/ShellStorm2');W=R.parent/'ShellStorm2-work/outputs/boss_fixes_v026';D=R/'art_source/environments/tower_zones/expedition/source/room_types/boss_room_B/v026'
scene=bpy.context.scene;bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
allowed={o.name for o in scene.objects if o.instance_collection and o.instance_collection.name in ['输出资产包_'+s for s in ('bridge_deck_5m','bridge_threshold','exit_passage')]};verts=[];faces=[]
for ins in dg.object_instances:
 if not ins.is_instance or ins.parent.name not in allowed or ins.object.type!='MESH':continue
 start=len(verts);verts.extend(ins.matrix_world@v.co for v in ins.object.data.vertices);faces.extend(tuple(start+i for i in p.vertices) for p in ins.object.data.polygons)
tree=BVHTree.FromPolygons(verts,faces);samples=[]
for side in (-1,1):
 for k in range(551):
  x=side*(12.5+k*.05)
  for y in (-1.8,0,1.8):
   # Grate openings expose the real backing at -0.1815m, bevel edges at -0.2065m.
   # These are supported surfaces; detect missing support, not just raised grille bars.
   hit=tree.ray_cast(Vector((x,y,.3)),Vector((0,0,-1)),1);samples.append({'x':x,'y':y,'z':hit[0].z if hit[0] else None,'ok':hit[0] is not None and -.23<hit[0].z<.10})
tops=[]
for slug in ('compute_tower_tall','compute_tower_stepped','compute_tower_compact','suspended_server_5m','door_support_pier'):
 c=bpy.data.collections['制作零件_'+slug];core=next(o for o in c.objects if o.get('semantic_part')=='大型方形主壳');coretop=max(v.co.z for v in core.data.vertices);cap=max(max(v.co.z for v in o.data.vertices) for o in c.objects if o.get('semantic_part')=='外凸方形肩座');tops.append({'slug':slug,'top_separation_m':cap-coretop,'ok':cap-coretop>.07})
lamps=[o for o in scene.objects if o.instance_collection and o.instance_collection.name=='输出资产包_stair_pillar_light'];east=[o for o in scene.objects if o.instance_collection and o.instance_collection.name.startswith('输出资产包_exit_leaf_') and 32<o.location.x<35]
checks={'bridge_to_gate_floor_continuous':all(r['ok'] for r in samples),'tower_top_planes_separated':all(r['ok'] for r in tops),'eastern_inner_gate_closed':len(east)==2 and all(abs(o.location.y)<1.24 for o in east),'80_independent_vertical_lights':len(lamps)==80 and all('sequence_index' in o for o in lamps)}
report={'passed':all(checks.values()),'checks':checks,'floor_samples':len(samples),'failed_floor_samples':[r for r in samples if not r['ok']],'tops':tops};(W/'fix_acceptance.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(report,ensure_ascii=False))
if not report['passed']:raise RuntimeError('Task fix acceptance failed')
