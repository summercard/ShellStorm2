"""Replace bounded floor modules with damage and construction frames at identical budgets."""
import bpy,json,sys,math,hashlib,shutil,random
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2];sys.path.insert(0,str(R/'tools/blender'))
import tower04_court_common as H
from tower04_court_common import Part,coll,camera,render
BASE=R/'assets/art/environments/open_world/source/landscape_tower04/v001'
OUT=BASE.parent/'v002';BLEND=OUT/'景观建筑_塔4周边五组_中段破损与在建骨架_v002.blend'
for d in ['previews','qa','references','component_packages']:(OUT/d).mkdir(parents=True,exist_ok=True)
old=json.loads((BASE/'catalog.json').read_text(encoding='utf8'));source=R/old['source_blend']
source_hash=hashlib.sha256(source.read_bytes()).hexdigest();assert source_hash==old['source_sha256']
bpy.ops.wm.open_mainfile(filepath=str(source));H.setup_materials()
src=bpy.data.collections['01_制作组件_四层楼身与大片藤蔓']
def signature(ob):
 me=ob.data
 data={'vertices':[list(v.co) for v in me.vertices],'faces':[list(f.vertices) for f in me.polygons],'materials':[m.name for m in me.materials],'indices':[p.material_index for p in me.polygons],'uv':[list(x.uv) for x in me.uv_layers.active.data],'location':list(ob.location),'rotation':list(ob.rotation_euler),'scale':list(ob.scale)}
 return hashlib.sha256(json.dumps(data,sort_keys=True).encode()).hexdigest()
locked_before={i['root_object']:signature(bpy.data.objects[i['root_object']]) for i in old['instances']}
defs={d['id']:bpy.data.meshes[d['mesh']] for d in old['definitions']};definitions=list(old['definitions']);changes=[]
plan={'version':'v002','source_reference':old['source_blend'],'budget_rule':'Each group triangle count equals v001, including every repeated instance and vines.','construction_buildings':['02组_2栋','04组_1栋'],'damage_types':['corner_loss','floor_collapse','vertical_split'],'frozen_before_modeling':True,'replacement_module_budgets':{'narrow':284,'wide':284,'slim':204,'crown':228},'unchanged_scope':'all vegetation, intact modules, group layout, materials, cameras'}
(OUT/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf8')
def tris(p):return sum(len(f)-2 for f in p.f)
def add_visible_fractures(p,target,w,d,seed):
 """Use reclaimed triangles for exposed bent reinforcement and faceted concrete chunks."""
 rng=random.Random(seed);remaining=target-tris(p);assert remaining>=0,(p.name,tris(p),target)
 n=remaining//12
 for i in range(n):
  sign=1 if i%2 else -1;z=[4.5,8.5,12.5][i%3]
  x=sign*w*.29 if 'floor_collapse' in p.slug or 'vertical_split' in p.slug else -w*.05+i%3*w*.07
  y=d*.08+(i//3)*.4
  p.rod((x,y,z),(x-sign*rng.uniform(.4,1.2),y-.55,z+rng.uniform(.8,2.2)),.075,(9,3),0,4)
 remaining=target-tris(p)
 for j in range(remaining//4):
  x=w*.33+j*.65;y=d*.13;z=4.6
  p.poly([(x-.6,y-.5,z),(x+.65,y-.4,z),(x,y+.7,z),(x-.15,y, z+.75)],[(0,2,1),(0,1,3),(1,2,3),(2,0,3)],(9,7),1)
 if target-tris(p)==2:
  p.poly([(-w*.15,-d*.30,8.6),(w*.1,-d*.3,8.6),(w*.1,-d*.48,7.7),(-w*.15,-d*.48,7.7)],[(0,1,2,3)],(9,5),1)
 assert tris(p)==target,(p.name,tris(p),target)
def define(key,p,target,tag):
 assert tris(p)==target
 mesh,origin,dimensions=H.mesh_of(p)
 for v in mesh.vertices:v.co+=origin
 ob=bpy.data.objects.new(p.name+'_制作源',mesh);src.objects.link(ob);ob['component_definition']=key;ob['damage_type']=tag
 defs[key]=mesh
 definitions.append({'id':key,'name':p.name,'dimensions':dimensions,'triangles':target,'mesh':mesh.name,'damage_type':tag})
def windows(p,w,d,bays,sides,mode):
 for side in sides:
  width=w if side%2==0 else d;depth=d if side%2==0 else w;a=side*math.pi/2
  for f in range(4):
   for j in range(bays):
    x=-width*.5+(j+.5)*width/bays;h=width/(bays*2)-.5;z=f*4+.9
    v=[(x-h,-depth/2+.34,z),(x+h,-depth/2+.34,z),(x+h,-depth/2+.34,z+2.5),(x-h,-depth/2+.34,z+2.5)]
    if (j+f)%3==0:v[2]=(v[2][0]-.4,v[2][1],v[2][2]-1.1)
    p.poly([(xx*math.cos(a)-yy*math.sin(a),xx*math.sin(a)+yy*math.cos(a),zz) for xx,yy,zz in v],[(0,1,2,3)],(9,1 if (f+j)%3 else 3),1)
def damage(kind,style,w,d,target):
 key=kind+'_'+style;p=Part(key,'四层破损_'+key,'architecture')
 corners=[(-w/2,-d/2),(w/2,-d/2),(-w/2,d/2),(w/2,d/2)]
 if style=='corner_loss':
  # Right-front corner is absent through multiple floors; slab edges form the visible diagonal bite.
  p.box((-w*.27,0,8),(w*.44,d-.8,16),(9,5),1)
  for f in range(4):
   points=[(-w/2-.225,-d/2-.225),(w*.05,-d/2-.225),(w/2+.225,d*.12),(w/2+.225,d/2+.225),(-w/2-.225,d/2+.225)]
   p.prism(points,f*4,f*4+.6,(9,8),1)
  for j,(x,y) in enumerate(corners):
   h=2.4 if j==1 else 16;p.box((x,y,h/2),(.62,.62,h),(9,7),1)
  if kind=='narrow':
   for x,y in [(-w/2,0),(0,d/2)]:p.box((x,y,8),(.62,.62,16),(9,7),1)
  windows(p,w,d,3 if kind=='slim' else 4,[2,3],style)
 elif style=='floor_collapse':
  # Rear wall and side piers remain; two central floors are gone, exposing a double-height cavity.
  p.box((0,d*.38,8),(w-.8,d*.17,16),(9,5),1)
  for x in [-w*.43,w*.43]:p.box((x,0,8),(w*.10,d-.8,16),(9,6),1)
  for z in [0,12]:p.box((0,0,z+.3),(w+.45,d+.45,.6),(9,8),1)
  for z in [4,8]:
   for sign in [-1,1]:
    start=len(p.v);p.box((sign*w*.38,0,z+.3),(w*.24,d+.45,.6),(9,8),1)
    for vi in range(start,len(p.v)):
     x,y,zz=p.v[vi]
     if abs(x)<w*.3 and y<0:p.v[vi]=(x+sign*.45,y,zz-.7)
  for x,y in corners:p.box((x,y,8),(.62,.62,16),(9,7),1)
  windows(p,w,d,3 if kind=='slim' else 4,[2],style)
 elif style=='vertical_split':
  # Full-depth central split: paired wall masses and discontinuous slabs, not a dark facade decal.
  for sign in [-1,1]:p.box((sign*w*.33,0,8),(w*.32,d-.8,16),(9,5),1)
  for f in range(4):
   for sign in [-1,1]:
    start=len(p.v);p.box((sign*w*.34,0,f*4+.3),(w*.32+.45,d+.45,.6),(9,8),1)
    for vi in range(start,len(p.v)):
     x,y,z=p.v[vi]
     if abs(x)<w*.3:p.v[vi]=(x+sign*(.25 if f%2 else -.25),y,z-(.35 if y<0 and f>0 else 0))
  for x,y in corners:p.box((x,y,8),(.62,.62,16),(9,7),1)
  for f in range(4):
   for sign in [-1,1]:
    x=sign*w*.33;z=f*4+1
    p.poly([(x-w*.10,-d/2+.34,z),(x+w*.10,-d/2+.34,z),(x+w*.10,-d/2+.34,z+2.4),(x-w*.10,-d/2+.34,z+1.8)],[(0,1,2,3)],(9,1),1)
 add_visible_fractures(p,target,w,d,50+len(definitions));define(key,p,target,style)
for kind,w,d,target in [('narrow',16,14,284),('slim',12,12,204)]:
 for style in ['corner_loss','floor_collapse','vertical_split']:damage(kind,style,w,d,target)
def skeleton(kind,w,d,target):
 key='frame_'+kind;p=Part(key,'四层在建梁柱骨架_'+kind,'architecture')
 for z in [0,4,8,12]:p.box((0,0,z+.3),(w+.45,d+.45,.6),(9,8),1)
 corners=[(-w/2,-d/2),(w/2,-d/2),(-w/2,d/2),(w/2,d/2)]
 if kind=='wide':corners += [(0,-d/2),(0,d/2),(-w/2,0),(w/2,0)]
 for x,y in corners:p.box((x,y,8),(.62,.62,16),(9,7),1)
 for z in [3.65,7.65,11.65,15.65]:
  for y in [-d/2,d/2]:p.box((0,y,z),(w,.62,.7),(9,7),1)
 # Diagonal temporary braces are visible through the empty envelope.
 p.rod((-w/2,-d/2,.6),(w/2,-d/2,3.25),.10,(9,3),0,4)
 if kind=='wide':
  for z in [4.6,8.6]:p.rod((-w/2,d/2,z),(0,d/2,z+2.6),.1,(9,3),0,4)
  for j in range(4):
   x=-w*.35+j*w*.23;p.poly([(x,-d/2-.05,11.3),(x+.8,-d/2-.05,11.3),(x+.8,-d/2-.05,11.7),(x,-d/2-.05,11.7)],[(0,1,2,3)],(6,2),0)
 define(key,p,target,'under_construction')
 key='frame_crown_'+kind;p=Part(key,'在建顶层_未封顶梁柱_'+kind,'architecture');p.box((0,0,.3),(w+.45,d+.45,.6),(9,8),1)
 for x,y in corners:p.box((x,y,2.3),(.62,.62,4.6),(9,7),1)
 # Incomplete roof beam framework; no walls, glazing or hidden wall core.
 if kind=='wide':
  for x in [-w/2,0,w/2]:p.box((x,0,4.3),(.62,d,.6),(9,7),1)
  for y in [-d/2,0,d/2]:p.box((0,y,4.3),(w,.62,.6),(9,7),1)
 else:
  for y in [-d/2,0,d/2]:p.box((0,y,4.3),(w,.62,.6),(9,7),1)
  for x in [-w/2,0,w/2]:p.box((x,0,4.3),(.62,d,.6),(9,7),1)
 remaining=228-tris(p);assert remaining%12==0
 for i in range(remaining//12):
  x,y=corners[i%len(corners)]
  offset=.13 if i>=len(corners) else -.13
  p.rod((x+offset,y,4.5),(x+offset+.12,y,5.8+(i%2)*.4),.055,(9,3),0,4)
 define(key,p,228,'under_construction')
skeleton('slim',12,12,204);skeleton('wide',25,14,284)
# Mapping is deliberately different between buildings and uses middle floors, not just the roof.
damage_map={
 '01组_1栋_05至08层':'narrow_corner_loss','01组_1栋_13至16层':'narrow_floor_collapse',
 '02组_1栋_05至08层':'slim_vertical_split',
 '03组_1栋_09至12层':'narrow_vertical_split','03组_2栋_01至04层':'slim_corner_loss',
 '05组_1栋_05至08层':'slim_floor_collapse','05组_2栋_05至08层':'slim_corner_loss','05组_3栋_01至04层':'slim_vertical_split'}
construction=['02组_2栋','04组_1栋']
for info in old['instances']:
 ob=bpy.data.objects[info['root_object']];key=info['component_definition'];new=damage_map.get(ob.name)
 if any(ob.name.startswith(prefix) for prefix in construction) and info['category']=='architecture':new='frame_'+key if not key.startswith('crown_') else 'frame_crown_'+key[6:]
 if new:
  previous=sum(len(p.vertices)-2 for p in ob.data.polygons);ob.data=defs[new]
  assert sum(len(p.vertices)-2 for p in ob.data.polygons)==previous
  info['component_definition']=new;ob['component_definition']=new
  ob['damage_type']='under_construction' if new.startswith('frame') else new.split('_',1)[1]
  changes.append({'object':ob.name,'old_definition':key,'new_definition':new,'triangles_unchanged':previous})
 ob['version']='v002';info['version']='v002';info['source_blend']=BLEND.relative_to(R).as_posix()
 pts=[ob.location+ob.rotation_euler.to_matrix()@v.co for v in ob.data.vertices]
 info['bounds_min']=[min(v[j] for v in pts) for j in range(3)];info['bounds_max']=[max(v[j] for v in pts) for j in range(3)];info['dimensions']=[info['bounds_max'][j]-info['bounds_min'][j] for j in range(3)]
 folder=OUT/'component_packages'/info['category']/info['slug'];folder.mkdir(parents=True,exist_ok=True);(folder/'asset_manifest.json').write_text(json.dumps(info,ensure_ascii=False,indent=2),encoding='utf8')
changed_names={x['object'] for x in changes};locked={name:sig for name,sig in locked_before.items() if name not in changed_names}
assert all(signature(bpy.data.objects[name])==sig for name,sig in locked.items())
groups=old['groups'];names={2:'破损与在建双楼',4:'宽体在建骨架楼'}
for gi,g in enumerate(groups,1):
 col=bpy.data.collections[g['collection']];obs=list(col.all_objects)
 assert H.tri_count(obs)==g['triangles']<=3000
 g['name']=names.get(gi,g['name']);g['polygons']=sum(len(o.data.polygons) for o in obs);g['construction_buildings']=1 if gi in [2,4] else 0
 g['height']=max((o.location+o.rotation_euler.to_matrix()@v.co).z for o in obs for v in o.data.vertices)
 scene=next(s for s in bpy.data.scenes if s.get('asset_id')==g['asset_id']);scene['version']='v002';scene['construction_buildings']=g['construction_buildings']
 scene.name=f"{gi:02d}_{g['name']}_独立原点"
sc=bpy.data.scenes['景观建筑_五组总览'];sc['version']='v002';sc['construction_buildings']=2
bpy.context.window.scene=sc
display=bpy.data.collections['90_展示与验收_灯光相机'];top=camera(sc,'俯视结构验收',(0,-.001,300),(0,0,0),290,display)
for p in (BASE/'references').glob('*'):
 if p.is_file() and p.suffix=='.png':shutil.copy2(p,OUT/'references'/p.name)
sc.camera=bpy.data.objects['五组总览'];bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
cat={**old,'version':'v002','source_blend':BLEND.relative_to(R).as_posix(),'source_sha256':hashlib.sha256(BLEND.read_bytes()).hexdigest(),'definitions':definitions,'groups':groups,'source_definition_count':len(definitions),'output_definition_count':len({i['component_definition'] for i in old['instances']}),'construction_buildings':construction,'damage_changes':changes}
(OUT/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'package_tree.txt').write_text('\n'.join(f"{i['category']}/{i['slug']} : {i['display_name']} / {i['component_definition']}" for i in old['instances']),encoding='utf8')
report={'passed':True,'parent_sha256':source_hash,'parent_source_unchanged':hashlib.sha256(source.read_bytes()).hexdigest()==source_hash,'exact_group_triangle_counts':[g['triangles'] for g in groups],'changed_objects':changes,'locked_objects':locked,'locked_objects_unchanged':True,'construction_buildings':construction}
(OUT/'qa/scope_lock.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
render(sc,sc.camera,OUT/'previews/五组景观建筑总览.png',(1900,1000),32)
render(sc,top,OUT/'previews/五组俯视结构.png',(1600,550),24)
for gi,g in enumerate(groups,1):
 s=next(s for s in bpy.data.scenes if s.get('asset_id')==g['asset_id']);render(s,s.camera,OUT/f"previews/{gi:02d}_{g['name']}.png",(950,1100),32)
print('V002_BUILD_OK',cat['source_sha256'],[(g['name'],g['triangles']) for g in groups],flush=True)
