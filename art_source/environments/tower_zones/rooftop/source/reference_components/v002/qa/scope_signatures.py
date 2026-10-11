import bpy,json,hashlib,sys
from pathlib import Path
O=Path(__file__).resolve().parents[1]
base='baseline' in sys.argv
path=O.parent/'v001' if base else O
cat=json.loads((path/f'component_packages_{path.name}/catalog.json').read_text())
result={}
for p in cat:
    names=[p['root_object']]+p['objects']+[o.name for o in bpy.data.collections[p['source_collection']].objects]
    records=[]
    for name in sorted(names):
        o=bpy.data.objects[name];d={'name':name,'type':o.type,'parent':o.parent.name if o.parent else None,'matrix':[round(v,6) for row in o.matrix_world for v in row],'modifiers':[m.type for m in o.modifiers],'animation':str(o.animation_data)}
        if o.type=='MESH':
            d['v']=[[round(x,6) for x in v.co] for v in o.data.vertices];d['faces']=[list(f.vertices)+[f.material_index] for f in o.data.polygons]
            d['materials']=[m.name for m in o.data.materials];d['uv']=[[round(x,6) for x in loop.uv] for loop in o.data.uv_layers.active.data]
        records.append(d)
    result[p['slug']]=hashlib.sha256(json.dumps(records,sort_keys=True).encode()).hexdigest()
if base:
    (O/'qa/locked_signatures_before.json').write_text(json.dumps(result,indent=2))
else:
    before=json.loads((O/'qa/locked_signatures_before.json').read_text())
    locked=[s for s in before if s!='door_lamp'];diff=[s for s in locked if before[s]!=result.get(s)]
    report={'passed':not diff,'locked_count':len(locked),'changed_allowed':['door_lamp'],'new_packages':sorted(set(result)-set(before)),'unexpected_changes':diff,'before':before,'after':result}
    (O/'qa/scope_validation.json').write_text(json.dumps(report,indent=2));print('SCOPE',len(locked),'DIFFERENCES',diff)
    if diff:raise RuntimeError(str(diff))
