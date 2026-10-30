import bpy,json
from pathlib import Path
from mathutils import Vector
R=Path('I:/工作项目/shellstrom2/ShellStorm2');S=R/'art_source/environments/tower_zones/expedition/source/common_components/v017';W=R.parent/'ShellStorm2-work/manor_v017';C=json.loads((S/'component_catalog.json').read_text(encoding='utf-8'))['components'];results=[]
for e in C:
 bpy.ops.wm.open_mainfile(filepath=str(R/e['component_blend']));sc=bpy.context.scene;dg=bpy.context.evaluated_depsgraph_get();vv=[]
 col=bpy.data.collections[e['collection']];assert col.instance_offset.length<1e-8
 for o in sc.objects:
  if o.type=='MESH':
   assert all(abs(o.matrix_local[i][j]-(1 if i==j else 0))<1e-6 for i in range(4) for j in range(4))
   root=o.parent;assert all(abs(root.matrix_local[i][j]-(1 if i==j else 0))<1e-6 for i in range(4) for j in range(4));vv.extend(Vector(v) for v in o.evaluated_get(dg).bound_box)
 low=Vector(tuple(min(v[k] for v in vv) for k in range(3)));high=Vector(tuple(max(v[k] for v in vv) for k in range(3)));assert abs(low.z)<1e-5 and abs((low.x+high.x)/2)<1e-5 and abs((low.y+high.y)/2)<1e-5,(e['slug'],list(low),list(high))
 results.append(dict(slug=e['slug'],three_layer_anchors=True,evaluated_geometry_bottom_center=True))
(W/'anchor_validation.json').write_text(json.dumps(dict(passed=True,components=results),indent=2),encoding='utf-8');print('ANCHORS_PASS',len(results))
