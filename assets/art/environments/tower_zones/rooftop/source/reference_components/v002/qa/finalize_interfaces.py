"""Keep bounding-box origins while snapping the structural core of ivy modules."""
import bpy,json,math
from pathlib import Path
from mathutils import Vector,Matrix
O=Path(__file__).resolve().parents[1]
catalog=json.loads((O/'component_packages_v002/catalog.json').read_text())
assembly=json.loads((O/'reference_assembly.json').read_text())
for p in catalog:
    if p['slug']!='door_lamp' and p['slug']!='parapet_ivy' and not p.get('vegetation_variant'):continue
    c=bpy.data.collections[p['source_collection']]
    tag='_门扇_' if p['slug']=='door_lamp' else '水泥结构'
    o=next(o for o in c.objects if tag in o.name)
    lo=Vector(tuple(min(v.co[i] for v in o.data.vertices) for i in range(3)));hi=Vector(tuple(max(v.co[i] for v in o.data.vertices) for i in range(3)))
    center=(lo+hi)/2;center.z=0;p['structural_core_offset']=list(center)
    if p['slug']=='door_lamp':p['sockets']={'wall_plane':list(center)}
    elif p['slug']=='parapet_ivy':
        p['structural_bounds']=[5,.5,1.8];p['sockets']={'left':[lo.x,center.y,0],'right':[hi.x,center.y,0]}
    elif p['slug'].startswith('parapet'):
        sign=-1 if 'inner' in p['slug'] else 1
        p['sockets']={'east':[center.x+sign*1.25,center.y-1,0],'north':[center.x-sign,center.y+1.25,0]}
    for i,q in enumerate(assembly['placements']):
        if q['slug']!=p['slug']:continue
        nominal=Vector(q.get('structural_position',q['position']));position=nominal-Matrix.Rotation(q['rotation_z'],3,'Z')@center
        q['structural_position']=list(nominal);q['position']=list(position)
        bpy.data.objects[f'拼装_{p["slug"]}_{i:03}'].location=position
    (O/'component_packages_v002'/p['category'][:2]/p['slug']/'asset_manifest.json').write_text(json.dumps(p,ensure_ascii=False,indent=2))
(O/'component_packages_v002/catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2))
(O/'reference_assembly.json').write_text(json.dumps(assembly,ensure_ascii=False,indent=2))
# Preserve fixed camera definitions, no geometry scaling.
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath,compress=True)
print('STRUCTURAL_SOCKETS_FINALIZED')
