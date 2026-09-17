"""Keep bounding-box origins while snapping the structural core of ivy modules."""
import bpy,json,math
from pathlib import Path
from mathutils import Vector,Matrix
O=Path(__file__).resolve().parents[1]
catalog=json.loads((O/'component_packages_v001/catalog.json').read_text())
p=next(p for p in catalog if p['slug']=='parapet_ivy')
c=bpy.data.collections[p['source_collection']]
o=next(o for o in c.objects if '水泥结构' in o.name)
lo=Vector(tuple(min(v.co[i] for v in o.data.vertices) for i in range(3)));hi=Vector(tuple(max(v.co[i] for v in o.data.vertices) for i in range(3)))
center=(lo+hi)/2;center.z=0
p['structural_core_offset']=list(center)
p['sockets']={'left':[float(lo.x),float(center.y),0],'right':[float(hi.x),float(center.y),0]}
p['structural_bounds']=[5,.5,1.8]
assembly=json.loads((O/'reference_assembly.json').read_text())
for i,q in enumerate(assembly['placements']):
    if q['slug']!='parapet_ivy':continue
    nominal=Vector(q.get('structural_position',q['position']))
    shift=Matrix.Rotation(q['rotation_z'],3,'Z') @ center
    position=nominal-shift
    q['structural_position']=list(nominal);q['position']=list(position)
    obj=bpy.data.objects[f'拼装_parapet_ivy_{i:03}'];obj.location=position
mf=O/'component_packages_v001'/p['category'][:2]/p['slug']/'asset_manifest.json'
mf.write_text(json.dumps(p,ensure_ascii=False,indent=2))
(O/'component_packages_v001/catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2))
(O/'reference_assembly.json').write_text(json.dumps(assembly,ensure_ascii=False,indent=2))
# Preserve fixed camera definitions, no geometry scaling.
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath,compress=True)
print('IVY_CORE_SNAP',list(center))
