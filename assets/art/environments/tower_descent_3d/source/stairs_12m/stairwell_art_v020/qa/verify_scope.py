import bpy,json,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];PREV=ROOT.parent/'stairwell_art_v019'/'env_tower_stairwell_art_source_v019.blend'
catalog=json.loads((ROOT/'component_packages/catalog.json').read_text())
current={o.name:o for p in catalog['packages'] for o in bpy.data.collections[p['collection']].objects}
baseline=json.loads((ROOT/'qa/locked_before.json').read_text())
names=set(baseline['full'])|set(baseline['geometry'])
def value(v):
    if isinstance(v,(str,int,bool)) or v is None:return v
    if isinstance(v,float):return round(v,6)
    if isinstance(v,bpy.types.ID):return v.name
    if isinstance(v,bpy.types.CurveProfile):return {'points':[(value(p.location),p.handle_type_1,p.handle_type_2) for p in v.points]}
    try:return [value(x) for x in v]
    except TypeError:return str(v)
def signature(o,full=True):
    d={'type':o.type,'parent':o.parent.name if o.parent else None,'basis':value(o.matrix_basis),'world':value(o.matrix_world),'dimensions':value(o.dimensions),'vertices':[value(v.co) for v in o.data.vertices],'edges':[list(e.vertices) for e in o.data.edges],'faces':[list(p.vertices) for p in o.data.polygons]}
    if full:
        d.update(materials=[m.name for m in o.data.materials],indices=[p.material_index for p in o.data.polygons],uv=[[value(x.uv) for x in l.data] for l in o.data.uv_layers],modifiers=[{p.identifier:value(getattr(m,p.identifier)) for p in m.bl_rna.properties if p.identifier not in ['rna_type','is_override_data','execution_time'] and p.type not in ['COLLECTION']} for m in o.modifiers])
        d['animation']=[(f.data_path,f.array_index,[(value(k.co),k.interpolation) for k in f.keyframe_points]) for f in o.animation_data.action.fcurves] if o.animation_data and o.animation_data.action else None
    return hashlib.sha256(json.dumps(d,sort_keys=True).encode()).hexdigest()
# Record current values before linking an independent previous-source snapshot.
after={n:signature(current[n]) for n in baseline['full']}
after_geometry={n:signature(current[n],False) for n in baseline['geometry']}
with bpy.data.libraries.load(str(PREV),link=True) as (src,dst):dst.objects=[n for n in src.objects if n in names]
old={o.name:o for o in dst.objects if o}
snapshot=bpy.data.collections.new('QA_PreviousSource_EvaluationOnly')
bpy.context.scene.collection.children.link(snapshot)
for o in old.values():snapshot.objects.link(o)
bpy.context.view_layer.update()
before={n:signature(old[n]) for n in baseline['full']}
before_geometry={n:signature(old[n],False) for n in baseline['geometry']}
members={};manifest_errors=[]
for p in catalog['packages']:
    obs=list(bpy.data.collections[p['collection']].objects)
    data=json.loads((ROOT/'component_packages'/p['path']/'asset_manifest.json').read_text())
    if set(data['objects'])!={o.name for o in obs}:manifest_errors.append(p['collection'])
    for o in obs:members.setdefault(o.name,[]).append(p['collection'])
def bb(o):
    pts=[o.matrix_world@v.co for v in o.data.vertices]
    return [[min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)]]
wallb=[bb(o) for o in bpy.data.collections['通用墙组件_资产包'].objects]
opening_ok=not any(b[1][0]<33 and b[0][1]<2.49 and b[1][1]>-2.49 for b in wallb)
floor_top=bb(current['地板.056_游戏输出_v017输出'])[1][2]
panel_heights=[bb(o) for n,o in current.items() if n.startswith('墙面_right_') and '折边装甲' in n and bb(o)[0][2]>-9.1]
result={'output_mesh_count':len(current),'packages':len(catalog['packages']),'counts':{p['collection']:p['object_count'] for p in catalog['packages']},'locked_count':len(before),'structural_count':len(before_geometry),'locked_match':before==after,'structural_match':before_geometry==after_geometry,'locked_before':before,'locked_after':after,'structural_before':before_geometry,'structural_after':after_geometry,'mismatches':[n for n in before if before[n]!=after[n]],'geometry_mismatches':[n for n in before_geometry if before_geometry[n]!=after_geometry[n]],'manifest_errors':manifest_errors,'multi_package_objects':{n:v for n,v in members.items() if len(v)!=1},'empty_packages':[p['collection'] for p in catalog['packages'] if not p['object_count']],'opening_left_first_span_clear':opening_ok,'upper_floor_top':floor_top,'upper_right_panel_height_range':[[b[0][2],b[1][2]] for b in panel_heights]}
result['passed']=all([result['locked_match'],result['structural_match'],opening_ok,not manifest_errors,not result['multi_package_objects'],not result['empty_packages'],len(catalog['packages'])==10])
(ROOT/'qa/scope_result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
print(json.dumps({k:v for k,v in result.items() if not k.endswith(('_before','_after'))},ensure_ascii=False,indent=2))
raise SystemExit(0 if result['passed'] else 1)
