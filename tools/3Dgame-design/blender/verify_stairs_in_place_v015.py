import bpy, json, math
from pathlib import Path
from mathutils import Vector
from mathutils.kdtree import KDTree

ROOT=Path(__file__).resolve().parents[3]
DEST=ROOT/'source/art/whitebox/tower_zones/v015'
payload=json.loads((DEST/'data/whitebox_tower_stairs_v015.json').read_text())
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'source/art/whitebox/tower_zones/v013/blender/whitebox_tower_stairs_v013.blend'))
bpy.context.view_layer.update()
original={o.name:[o.matrix_world@v.co for v in o.data.vertices] for o in bpy.context.scene.objects if o.type=='MESH'}
bpy.ops.wm.open_mainfile(filepath=str(DEST/'blender/whitebox_tower_stairs_v015.blend'))
bpy.context.view_layer.update()
def bounds(points): return [[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]]
def volume(b): return math.prod(b[1][i]-b[0][i] for i in range(3))
def verts(root): return [o.matrix_world@v.co for o in root.children_recursive if o.type=='MESH' for v in o.data.vertices]
surface_errors=[]
for check in json.loads((DEST/'data/original_surface_comparison.json').read_text()):
    roots=[bpy.data.objects[p['name']] for p in check['pieces']]
    before=bounds(original[check['source']]); after=bounds([v for root in roots for v in verts(root)])
    error=max(abs(before[j][i]-after[j][i]) for j in range(2) for i in range(3))
    local_inverse=roots[0].parent.matrix_world.inverted()
    local_before=bounds([local_inverse@v for v in original[check['source']]])
    volume_error=abs(sum(volume(bounds([local_inverse@v for v in verts(root)])) for root in roots)-volume(local_before))
    surface_errors.append({'source':check['source'],'boundsErrorM':error,'volumeErrorM3':volume_error,'pieces':len(roots)})
stairs=[]
for code,prefix in [('A','Stair_Special_Rooftop'),('B','Stair_Generic_Rotatable')]:
    for name,token in [('上跑','UpperFlight'),('下跑','LowerFlight')]:
        before=[v for key,points in original.items() if key.startswith(prefix) and token in key for v in points]
        after=verts(bpy.data.objects[f'{code}_{name}'])
        tree=KDTree(len(before))
        for i,v in enumerate(before): tree.insert(v,i)
        tree.balance()
        error=max(tree.find(v)[2] for v in after)
        stairs.append({'name':f'{code}_{name}','vertexErrorM':error,'vertexCount':[len(before),len(after)]})
scale_errors=[o.name for o in bpy.context.scene.objects if any(abs(v-1)>1e-6 for v in o.scale)]
report={'source':'v013 actual Blender world coordinates','componentCount':len(payload['components']),'surfaceChecks':surface_errors,'flightChecks':stairs,'nonUnitScale':scale_errors,'uniqueStairMeshes':len(set(o.data for r in [bpy.data.objects[f'{c}_{n}'] for c in 'AB' for n in ['上跑','下跑']] for o in r.children))}
report['passed']=not scale_errors and all(c['boundsErrorM']<.0001 and c['volumeErrorM3']<.005 for c in surface_errors) and all(c['vertexErrorM']<.0001 and c['vertexCount'][0]==c['vertexCount'][1] for c in stairs)
(DEST/'data/assembly_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False))
if not report['passed']: raise RuntimeError('Original-coordinate assembly verification failed')
