"""Vertex-only ruin deformation: inclined columns, sagging and protruding broken slabs."""
import bpy,json,sys,hashlib,math,random,shutil,ast
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2];sys.path.insert(0,str(R/'tools/blender'))
import tower04_court_common as H
BASE=R/'assets/art/environments/open_world/source/landscape_tower04/v002';OUT=BASE.parent/'v003'
BLEND=OUT/'景观建筑_塔4周边五组_倾斜断柱与塌板_v003.blend'
for d in ['previews','qa','component_packages','references']:(OUT/d).mkdir(parents=True,exist_ok=True)
cat=json.loads((BASE/'catalog.json').read_text(encoding='utf8'));parent_file=R/cat['source_blend'];parent_sha=hashlib.sha256(parent_file.read_bytes()).hexdigest()
assert parent_sha==cat['source_sha256'];bpy.ops.wm.open_mainfile(filepath=str(parent_file))
node=next(n for n in ast.parse((R/'tools/blender/build_tower04_landscape_v002.py').read_text(encoding='utf8')).body if isinstance(n,ast.FunctionDef) and n.name=='signature')
exec(compile(ast.Module(body=[node],type_ignores=[]),'<signature>','exec'),globals())
before={i['root_object']:signature(bpy.data.objects[i['root_object']]) for i in cat['instances']}
src=bpy.data.collections['01_制作组件_四层楼身与大片藤蔓'];changes=[]
plan={'version':'v003','date':'2026-10-03','rule':'vertex-only edits: topology and all group triangle counts unchanged','scope':'eight damaged middle-floor modules and seven ruined crowns; both construction buildings and all vegetation locked','slabs':'anchor rear portion; free edges sag and protrude irregularly','columns':'selected broken column islands lean with fixed foot; remaining columns stay aligned','parent_source':cat['source_blend']}
(OUT/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf8')
def islands(mesh):
 adj=[set() for _ in mesh.vertices]
 for e in mesh.edges:a,b=e.vertices;adj[a].add(b);adj[b].add(a)
 unseen=set(range(len(adj)));result=[]
 while unseen:
  start=unseen.pop();todo=[start];group=[start]
  while todo:
   for j in adj[todo.pop()]:
    if j in unseen:unseen.remove(j);group.append(j);todo.append(j)
  result.append(group)
 return result
for number,info in enumerate(cat['instances']):
 ob=bpy.data.objects[info['root_object']];key=info['component_definition'];is_damage=any(t in key for t in ['corner_loss','floor_collapse','vertical_split']);is_crown=key.startswith('crown_')
 if is_damage or is_crown:
  old_mesh=ob.data;mesh=old_mesh.copy();mesh.name=ob.name+'_倾斜损坏网格';ob.data=mesh
  rng=random.Random(310+number);bounds=[v.co.copy() for v in mesh.vertices];w=max(v.x for v in bounds)-min(v.x for v in bounds);d=max(v.y for v in bounds)-min(v.y for v in bounds)
  actual=[];columns=0
  for ids in islands(mesh):
   verts=[mesh.vertices[j] for j in ids];lo=Vector(tuple(min(v.co[j] for v in verts) for j in range(3)));hi=Vector(tuple(max(v.co[j] for v in verts) for j in range(3)));dims=hi-lo;center=(hi+lo)*.5
   if not is_crown and dims.z<1.6 and dims.x>2 and dims.y>3 and lo.z>1:
    # Tilt a complete closed slab island, preserving thickness and its anchored rear edge.
    sag=rng.uniform(.7,1.7);roll=rng.uniform(-.045,.045);protrude=rng.uniform(.5,1.45);side=1 if rng.random()>.5 else -1
    for v in verts:
     q=v.co.copy();free=max(0,min(1,(hi.y-q.y)/max(dims.y,.1)))
     v.co.z-=sag*free;v.co.z+=roll*(q.x-center.x)*free
     if abs(q.x-center.x)>dims.x*.3:v.co.x+=side*protrude*free
     v.co.y-=rng.uniform(.6,1.1)*free if q.y<lo.y+.1 else 0
    actual.append({'kind':'sagging_protruding_slab','center':list(center),'front_drop_m':sag,'protrusion_m':protrude})
   elif dims.x<.85 and dims.y<.85 and dims.z>1.5 and center.y<0 and columns<2:
    # Leave the bottom anchored; break the top connection by leaning and shortening the pier.
    lean=(1 if center.x>0 else -1)*rng.uniform(1.2,2.25);forward=rng.uniform(.7,1.5)
    for v in verts:
     t=(v.co.z-lo.z)/dims.z;v.co.x+=lean*t;v.co.y-=forward*t;v.co.z=lo.z+(v.co.z-lo.z)*(.83 if not is_crown else .9)
    columns+=1;actual.append({'kind':'leaning_broken_column','center':list(center),'top_shift_m':[lean,-forward]})
   elif is_crown and dims.z>1.2 and (dims.x>2 or dims.y>2):
    # Lean wall remnants outwards and push a torn tip, leaving their lower contact fixed.
    for v in verts:
     t=max(0,(v.co.z-lo.z)/max(dims.z,.01));v.co.x+=math.copysign(.8,center.x or 1)*t;v.co.y+=math.copysign(.65,center.y or 1)*t
     if v.co.z>hi.z-.2:v.co.z-=rng.uniform(.1,.7)
    actual.append({'kind':'leaning_roof_remnant','center':list(center)})
  mesh.update();assert len(mesh.polygons)==len(old_mesh.polygons)
  assert [tuple(p.vertices) for p in mesh.polygons]==[tuple(p.vertices) for p in old_mesh.polygons]
  new=key+f'_deformed_{number:02d}';info['component_definition']=new;ob['component_definition']=new;ob['damage_type']='inclined_fracture'
  so=bpy.data.objects.new(ob.name+'_倾斜损坏制作源',mesh);src.objects.link(so);so['component_definition']=new
  b=[v.co for v in mesh.vertices];dimensions=[max(v[j] for v in b)-min(v[j] for v in b) for j in range(3)]
  cat['definitions'].append({'id':new,'name':ob.name+'_倾斜损坏','mesh':mesh.name,'dimensions':dimensions,'triangles':sum(len(p.vertices)-2 for p in mesh.polygons),'damage_type':'inclined_fracture'})
  changes.append({'object':ob.name,'old_definition':key,'new_definition':new,'topology_identical':True,'deformations':actual})
 ob['version']='v003';info['version']='v003';info['source_blend']=BLEND.relative_to(R).as_posix()
 points=[ob.location+ob.rotation_euler.to_matrix()@v.co for v in ob.data.vertices]
 info['bounds_min']=[min(v[j] for v in points) for j in range(3)];info['bounds_max']=[max(v[j] for v in points) for j in range(3)];info['dimensions']=[info['bounds_max'][j]-info['bounds_min'][j] for j in range(3)]
 path=OUT/'component_packages'/info['category']/info['slug'];path.mkdir(parents=True,exist_ok=True);(path/'asset_manifest.json').write_text(json.dumps(info,ensure_ascii=False,indent=2),encoding='utf8')
changed_names={x['object'] for x in changes};locked={name:sig for name,sig in before.items() if name not in changed_names}
assert all(signature(bpy.data.objects[n])==s for n,s in locked.items())
for g in cat['groups']:
 obs=list(bpy.data.collections[g['collection']].all_objects);assert H.tri_count(obs)==g['triangles']
 points=[ob.location+ob.rotation_euler.to_matrix()@v.co for ob in obs for v in ob.data.vertices]
 g['bounds_min']=[min(v[j] for v in points) for j in range(3)];g['bounds_max']=[max(v[j] for v in points) for j in range(3)];g['height']=g['bounds_max'][2]
 g['origin_policy']='retain v001 local assembly origin; asymmetric damage may extend bounds'
 assert abs(g['bounds_min'][2])<1e-4
for s in bpy.data.scenes:s['version']='v003'
sc=bpy.data.scenes['景观建筑_五组总览'];bpy.context.window.scene=sc;sc.camera=bpy.data.objects['五组总览']
for p in (BASE/'references').glob('*.png'):shutil.copy2(p,OUT/'references'/p.name)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
cat.update(version='v003',source_blend=BLEND.relative_to(R).as_posix(),source_sha256=hashlib.sha256(BLEND.read_bytes()).hexdigest(),parent_source=(parent_file.relative_to(R).as_posix()),source_definition_count=len(cat['definitions']),output_definition_count=len({i['component_definition'] for i in cat['instances']}),deformation_changes=changes)
assert len(cat['definitions'])<=50
(OUT/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'package_tree.txt').write_text('\n'.join(f"{i['category']}/{i['slug']} : {i['display_name']} / {i['component_definition']}" for i in cat['instances']),encoding='utf8')
report={'passed':True,'parent_source':cat['parent_source'],'parent_sha256':parent_sha,'parent_source_unchanged':hashlib.sha256(parent_file.read_bytes()).hexdigest()==parent_sha,'changed_objects':changes,'locked_objects':locked,'locked_objects_unchanged':True,'construction_buildings':cat['construction_buildings'],'exact_group_triangle_counts':[g['triangles'] for g in cat['groups']]}
(OUT/'qa/scope_lock.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
H.render(sc,sc.camera,OUT/'previews/五组景观建筑总览.png',(1900,1000),32)
H.render(sc,bpy.data.objects['俯视结构验收'],OUT/'previews/五组俯视结构.png',(1600,550),24)
for gi,g in enumerate(cat['groups'],1):
 s=next(s for s in bpy.data.scenes if s.get('asset_id')==g['asset_id']);H.render(s,s.camera,OUT/f"previews/{gi:02d}_{g['name']}.png",(950,1100),32)
print('V003_BUILD_OK',[(g['name'],g['triangles']) for g in cat['groups']],flush=True)
