import bpy,json,hashlib,math
from pathlib import Path
from mathutils import Matrix,Vector
ROOT=Path(__file__).resolve().parents[1]
LEAVES=['通用墙组件_资产包','通用地板组件_资产包','通用楼梯组件_资产包','墙面装甲与结构框_装饰组件','地面导光与警示_装饰组件','工业管线_装饰组件','灯带与发光几何_装饰组件','楼层标识与海报_装饰组件','控制盒_装饰组件','固定绿植_装饰组件']
ra=bpy.data.objects['楼梯A_100至99层_装配根'];rb=bpy.data.objects['楼梯B_99至98层_装配根'];pairs=json.loads((ROOT/'qa/pair_map.json').read_text());before=json.loads((ROOT/'qa/before_layout.json').read_text())
def sig(o):
    d={'v':[list(v.co) for v in o.data.vertices],'e':[list(e.vertices) for e in o.data.edges],'f':[list(p.vertices) for p in o.data.polygons],'mi':[p.material_index for p in o.data.polygons],'m':[m.name for m in o.data.materials],'uv':[[list(x.uv) for x in l.data] for l in o.data.uv_layers]}
    return hashlib.sha256(json.dumps(d,sort_keys=True).encode()).hexdigest()
def close(a,b,t=1e-5):return all(abs(a[r][c]-b[r][c])<t for r in range(4) for c in range(4))
pair_errors=[];b_world_errors=[];collection_errors=[]
for old,p in pairs.items():
    a,b=bpy.data.objects[p['a']],bpy.data.objects[p['b']]
    if sig(a)!=sig(b) or not close(ra.matrix_world.inverted()@a.matrix_world,rb.matrix_world.inverted()@b.matrix_world):pair_errors.append(old)
    if not close(b.matrix_world,Matrix(before[old]['world'])):b_world_errors.append(old)
    if {c.name for c in a.users_collection}!={p['collection']} or {c.name for c in b.users_collection}!={p['collection']}:collection_errors.append(old)
counts={n:sum(o.type=='MESH' for o in bpy.data.collections[n].objects) for n in LEAVES}
def bounds(tag):
    obs=[o for n in LEAVES for o in bpy.data.collections[n].objects if o.get('stairwell_instance')==tag];pts=[o.matrix_world@v.co for o in obs for v in o.data.vertices]
    return [[min(p[i] for p in pts),max(p[i] for p in pts)] for i in range(3)]
catalog=json.loads((ROOT/'component_packages/catalog.json').read_text());manifest_errors=[]
for p in catalog['packages']:
    m=json.loads((ROOT/'component_packages'/p['path']/'asset_manifest.json').read_text())
    if set(m['objects'])!={o.name for o in bpy.data.collections[p['collection']].objects}:manifest_errors.append(p['collection'])
result={'pair_count':len(pairs),'a_count':sum(o.get('stairwell_instance')=='A_100_to_99' for n in LEAVES for o in bpy.data.collections[n].objects),'b_count':sum(o.get('stairwell_instance')=='B_99_to_98' for n in LEAVES for o in bpy.data.collections[n].objects),'root_a':{'location':list(ra.location),'rotation_z_deg':math.degrees(ra.rotation_euler.z),'scale':list(ra.scale)},'root_b':{'location':list(rb.location),'rotation_z_deg':math.degrees(rb.rotation_euler.z),'scale':list(rb.scale)},'a_bounds':bounds('A_100_to_99'),'b_bounds':bounds('B_99_to_98'),'component_counts':counts,'pair_errors':pair_errors,'b_world_errors':b_world_errors,'collection_errors':collection_errors,'manifest_errors':manifest_errors}
root_ok=all(abs(x-y)<1e-5 for x,y in zip(ra.location,(-32.5,0,0))) and abs(abs(math.degrees(ra.rotation_euler.z))-180)<1e-4 and all(abs(x-1)<1e-6 for x in ra.scale) and all(abs(x-y)<1e-5 for x,y in zip(rb.location,(32.5,0,-9))) and abs(math.degrees(rb.rotation_euler.z))<1e-4 and all(abs(x-1)<1e-6 for x in rb.scale)
result['passed']=root_ok and result['pair_count']==382 and result['a_count']==382 and result['b_count']==382 and not any([pair_errors,b_world_errors,collection_errors,manifest_errors])
(ROOT/'qa/verify_result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
print(json.dumps(result,ensure_ascii=False,indent=2));raise SystemExit(0 if result['passed'] else 1)
