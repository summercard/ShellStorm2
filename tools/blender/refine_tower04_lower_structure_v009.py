"""Rebuild only the lower mall structure from the user's marked scope and reference."""
import ast,bpy,hashlib,json,math,random,shutil,sys
from pathlib import Path
from collections import Counter
from mathutils import Vector
from mathutils.geometry import tessellate_polygon
R=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).parent))
sys.path.insert(0,sys.argv[sys.argv.index('--geometry-libs')+1])
from shapely import wkt,constrained_delaunay_triangles
from shapely.geometry import Polygon,Point,LineString,box
from shapely.ops import nearest_points
from tower04_lower_structure_common import object_signature
import tower04_plan_v002 as P
OLD=R/'assets/art/environments/open_world/source/tower_04/v008';OUT=OLD.parent/'v009'
PREVIOUS=next(OLD.glob('*.blend'));BLEND=OUT/'塔4_架空退台商城下部结构_150x50m_v009.blend'
if BLEND.exists():
 assert '--draft-sha' in sys.argv and hashlib.sha256(BLEND.read_bytes()).hexdigest()==sys.argv[sys.argv.index('--draft-sha')+1],'Draft changed; never overwrite another source'
 backup=R.parent/'_scratch/tower04_v009_before_gallery.blend'
 assert not backup.exists(),'Draft transaction already used'
 shutil.copy2(BLEND,backup)
for d in ('qa','previews','mood','references','component_packages'):(OUT/d).mkdir(parents=True,exist_ok=True)
meta=json.loads((OLD/'catalog.json').read_text(encoding='utf8'))
assert hashlib.sha256(PREVIOUS.read_bytes()).hexdigest()==meta['source_sha256']
plan={'version':'v009','design_revision':'r8','reference':'参考_下部结构真值.png',
 'locked':'v008顶层屋面、平台壳、路线、设施、屋顶植被、原相机灯光和四材质，逐对象完整签名',
 'editable':['oval_level_*','wing_level_*','oval_glazing','wing_glazing','pier_*','facade_growth_*'],
 'reference_facts':['左楼架空大柱','弧形窗墙与突出中间退台','跨层圆角混凝土门形肋','中部通透连廊下大柱','右翼混凝土实墙与内退窗带'],
 'inferred_dimensions':{'roof_z':25,'existing_platform_bottom':23.8,'left_slabs':[9,14.3,19.6],'right_slabs':[0,7.8,15.8,23.8],'left_pilotis_clear_height':8.5},
 'not_inferred_as_reference_fact':['遮挡背面结构','米制楼层尺寸','背景城市'],
 'new_component_definitions':['raised_curved_slab','recessed_window_bay','rounded_concrete_portal','exposed_pilotis','recessed_retail_slab','concrete_facade_bay','lower_link_gallery','retail_interior_structure'],
 'max_definitions':50,'new_lower_package_max_xy':10,'source_only':True}
(OUT/'lower_structure_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf8')
for f in (OLD/'references').glob('*.png'):shutil.copy2(f,OUT/'references'/f.name)
for src,dst in [('C:/Users/ZHUANG~1/AppData/Local/Temp/codex-clipboard-2554123a-e04e-4ac0-b4a2-6ad3c62c593f.png','参考_红线修改范围.png'),('C:/Users/ZHUANG~1/AppData/Local/Temp/codex-clipboard-5fc7a275-424b-4728-8066-6e2bc9987cb8.png','参考_下部结构真值.png')]:shutil.copy2(src,OUT/'references'/dst)
bpy.ops.wm.open_mainfile(filepath=str(PREVIOUS));sc=bpy.data.scenes['Scene'];bpy.context.window.scene=sc
ASSET=meta['asset_id'];NAMES=meta['material_roles'];MATS=[bpy.data.materials[n] for n in NAMES]
DONOR=R/meta['material_source'];PALETTE=R/meta['shared_palette']
CREAM=LIGHT=(9,9);TILE=(9,7);TILE2=(9,6);DARK=(9,1);STEEL=(9,4);RUST=(6,2)
def load(file,names):
 p=R/'tools/blender'/file;n=[n for n in ast.parse(p.read_text(encoding='utf8')).body if isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name in names]
 exec(compile(ast.Module(body=n,type_ignores=[]),str(p),'exec'),globals())
load('build_skyline_08_source_v001.py',{'coll','uv_mesh','Part'});BasePart=Part
load('build_tower04_mall_source.py',{'Part','ellipse'});OriginalPart=Part
load('refine_tower04_routes_v003.py',{'sha','material_signature'})
cats={'architecture':'01_建筑结构','floor':'02_地面系统','garden':'04_曲线景观','support':'05_环境支持','facilities':'03_天台固定设施'}
CATS={k:bpy.data.collections[n] for k,n in cats.items()};SCATS={k:bpy.data.collections[n+'_制作源'] for k,n in cats.items()}
oldmap={p['slug']:p for p in meta['packages']}
editable={s for s in oldmap if s.startswith(('oval_level_','wing_level_','pier_','facade_growth_')) or s in ('oval_glazing','wing_glazing')}
locked={o.name:object_signature(o) for o in bpy.data.objects if o.get('package_id','').split('/')[-1] not in editable}
mat=material_signature();files={p.relative_to(R).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in (PREVIOUS,PALETTE,Path(str(PALETTE)+'.import'),DONOR)}
(OUT/'qa/locked_before.json').write_text(json.dumps({'objects':locked,'materials':mat,'files':files,'editable_packages':sorted(editable)},ensure_ascii=False,indent=2),encoding='utf8')
catalog=[];count=Counter();newpackages=[]
class Part(OriginalPart):
 def finish(self):
  result=super().finish();p=catalog[-1]
  p.update(version='v009',component_revision='v009',lower_structure=True,floor_range='参考图错层架空下部')
  for col in (p['collection'],p['source_collection']):
   for o in bpy.data.collections[col].objects:o['version']='v009'
  newpackages.append(p['slug']);return result
def parts(g):return [g] if g.geom_type=='Polygon' else [x for x in getattr(g,'geoms',[]) if x.geom_type=='Polygon']
layout=json.loads((OLD.parent/'v004/qa/surface_plan.json').read_text(encoding='utf8'))['frozen_layout']
deck=wkt.loads(layout['deck']['wkt']);cx,cy=P.CIRCLE_CENTER;rx,ry=P.CIRCLE_RADII
body=deck.buffer(-2.1,join_style=2).intersection(box(1.5,-50,78,50))
body=max(parts(body),key=lambda x:x.area)
rear=deck.buffer(-1.6).intersection(box(-71,10.7,-51,22))
rear=max(parts(rear),key=lambda x:x.area)
oval=Polygon(ellipse(cx,cy,rx-.6,ry-.6,128))
def remove_package(item):
 for key in ('collection','source_collection'):
  c=bpy.data.collections[item[key]]
  for o in list(c.objects):
   m=o.data;bpy.data.objects.remove(o,do_unlink=True)
   if m.users==0:bpy.data.meshes.remove(m)
  bpy.data.collections.remove(c)
for item in meta['packages']:
 if item['slug'] not in editable:
  q=dict(item);q['source_blend']=BLEND.relative_to(R).as_posix();q['version']='v009';q['component_revision']=item.get('component_revision','v008');catalog.append(q)
 elif not item['slug'].startswith('facade_growth_'):remove_package(item)
print('LOCKED_TOP',len(locked),'REMOVED_OLD_SOLID_SHELL',flush=True)
def prism(p,g,lo,hi,c=CREAM):
 for poly in parts(g):p.prism(list(poly.exterior.coords)[:-1],lo,hi,c,1)
def slabs(slug,g,z,thick,definition):
 b=g.bounds
 for ix in range(math.floor(b[0]/8),math.ceil(b[2]/8)):
  for iy in range(math.floor(b[1]/8),math.ceil(b[3]/8)):
   seg=g.intersection(box(ix*8,iy*8,(ix+1)*8,(iy+1)*8))
   if seg.area<.08:continue
   p=Part(f'{slug}_{ix+20:02d}_{iy+20:02d}',f'{slug}_独立楼板_{ix}_{iy}','architecture',(ix*8+4,iy*8+4,z-thick),definition)
   prism(p,seg,z-thick,z,CREAM);p.finish();count['slab_modules']+=1
def beam(p,a,b,width,height,c=CREAM,m=1):
 a,b=Vector(a),Vector(b);u=(b-a).normalized();s=Vector((-u.y,u.x,0))*width*.5;v=Vector((0,0,height*.5))
 p.poly([q+ss*s+vv*v for q in (a,b) for ss,vv in ((-1,-1),(1,-1),(1,1),(-1,1))],[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],c,m)
def window_bay(p,a,b,lo,hi,seed):
 a,b=Vector((*a,0)),Vector((*b,0));d=b-a;length=d.length;d.normalize();rng=random.Random(seed)
 cols=max(1,round(length/1.3));rows=max(1,round((hi-lo)/2.1))
 for j in range(cols+1):
  q=a+(b-a)*j/cols;p.rod((q.x,q.y,lo),(q.x,q.y,hi),.047,STEEL,0,6)
 for k in range(rows+1):
  z=lo+(hi-lo)*k/rows;p.rod((a.x,a.y,z),(b.x,b.y,z),.045,STEEL,0,6)
 for j in range(cols):
  for k in range(rows):
   q=a+(b-a)*(j+.06)/cols;r=a+(b-a)*(j+.94)/cols;z=lo+(hi-lo)*(k+.04)/rows;top=lo+(hi-lo)*(k+.96)/rows
   vertices=[(q.x,q.y,z),(r.x,r.y,z),(r.x,r.y,top),(q.x,q.y,top)]
   chance=rng.random()
   if chance<.24:p.poly(vertices,[(0,1,2,3)],rng.choice([(9,3),(8,3),(7,5)]),2);count['retained_panes']+=1
   elif chance<.70:
    v=[Vector(x) for x in vertices];s=rng.randrange(4);p.poly([v[s],v[s].lerp(v[(s+1)%4],rng.uniform(.2,.55)),v[s].lerp(v[(s-1)%4],rng.uniform(.22,.68))],[(0,1,2)],(9,4),2);count['broken_panes']+=1
   else:count['open_panes']+=1
def erosion(p,a,b,z,height,seed):
 rng=random.Random(seed);a,b=Vector((*a,0)),Vector((*b,0));d=b-a
 for j in range(5):
  q=a+d*rng.uniform(.1,.9);width=rng.uniform(.06,.20);h=rng.uniform(.18,height*.55)
  side=d.normalized()*width
  p.poly([(q.x-side.x,q.y-side.y,z),(q.x+side.x,q.y+side.y,z),(q.x+side.x*.2,q.y+side.y*.2,z-h)],[(0,1,2)],rng.choice([(9,6),(8,2),(6,3)]),1)

# Raised circular mall: open undercroft, three occupied storeys and one bold terrace.
for z,radd,thick in [(9,.05,.65),(14.3,.62,.80),(19.6,-.25,.28)]:
 slabs('oval_slab_'+str(int(z*10)),oval.buffer(radd,join_style=2),z,thick,'raised_curved_slab')
ring=list(oval.exterior.coords);edge=LineString(ring);n=math.ceil(edge.length/5.5)
for i in range(n):
 a=edge.interpolate(i*edge.length/n);b=edge.interpolate((i+1)*edge.length/n);a=(a.x,a.y);b=(b.x,b.y)
 for k,(lo,hi) in enumerate([(9.2,13.9),(14.5,24.35)]):
  p=Part(f'oval_window_{i:02d}_{k}',f'左楼内退弧形窗墙_{i:02d}_{k}','architecture',(*a,lo),'recessed_window_bay')
  window_bay(p,a,b,lo,hi,400+i*5+k)
  if k==1:beam(p,(*a,19.65),(*b,19.65),.16,.20,TILE2,0)
  p.finish()
 # Prominent curved concrete balcony fascia and a restrained rail.
 outer=Vector(a)-Vector((cx,cy));outer.normalize();aa=Vector(a)+outer*.52
 outb=Vector(b)-Vector((cx,cy));outb.normalize();bb=Vector(b)+outb*.52
 p=Part(f'oval_terrace_band_{i:02d}',f'左楼突出环形退台栏板_{i:02d}','architecture',(*a,13.5),'raised_curved_slab')
 beam(p,(*aa,13.93),(*bb,13.93),.25,.7);erosion(p,tuple(aa),tuple(bb),14.2,.6,100+i)
 for z in (14.6,15.2):p.rod((*aa,z),(*bb,z),.038,STEEL,0,6)
 p.rod((*aa,14.3),(*aa,15.23),.05,STEEL,0,6);p.finish()

# Broad concrete portals with rounded upper corners, built as real extruded strips.
for i in range(8):
 angle=(i+.35)*math.tau/8;center=Vector((cx+(rx-.20)*math.cos(angle),cy+(ry-.20)*math.sin(angle),0));t=Vector((-rx*math.sin(angle),ry*math.cos(angle),0)).normalized();normal=Vector((math.cos(angle)/rx,math.sin(angle)/ry,0)).normalized()
 p=Part(f'oval_portal_{i:02d}',f'左楼圆角跨层混凝土门形肋_{i:02d}','architecture',tuple(center+Vector((0,0,14.3))),'rounded_concrete_portal')
 w=5.8;r=1.55;points=[(-w/2,14.3),(-w/2,22.55)]
 for j in range(9):
  a=math.pi-j*math.pi/16;points.append((-w/2+r+r*math.cos(a),22.55+r*math.sin(a)))
 points.append((w/2-r,24.10))
 for j in range(9):
  a=math.pi/2-j*math.pi/16;points.append((w/2-r+r*math.cos(a),22.55+r*math.sin(a)))
 points.append((w/2,14.3))
 for a,b in zip(points,points[1:]):
  if math.dist(a,b)<.00001:continue
  va=center+t*a[0]+Vector((0,0,a[1]));vb=center+t*b[0]+Vector((0,0,b[1]));axis=(vb-va).normalized();side=axis.cross(normal)*.32;dep=normal*.30
  p.poly([q+s*side+d*dep for q in (va,vb) for s,d in ((-1,-1),(1,-1),(1,1),(-1,1))],[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],CREAM,1)
 p.finish();count['curved_portals']+=1

def pier(slug,x,y,top,radius):
 p=Part(slug,'架空混凝土大柱_'+slug,'architecture',(x,y,0),'exposed_pilotis')
 p.rod((x,y,.12),(x,y,top),radius,CREAM,1,24)
 p.rod((x,y,.04),(x,y,.26),radius+.13,TILE,1,24)
 for z in range(2,int(top),3):p.rod((x,y,z),(x,y,z+.045),radius+.008,TILE2,1,24)
 p.rod((x,y,top-.48),(x,y,top),radius+.25,CREAM,1,24);p.finish();count['pilotis']+=1
for i in range(5):
 a=(i+.25)*math.tau/5;pier(f'oval_pilotis_{i:02d}',cx+rx*.68*math.cos(a),cy+ry*.67*math.sin(a),8.5,1.02)
for i,(x,y) in enumerate([(-64,16),(-42,13),(-29,7),(-13,-10),(-2,-9)]):pier(f'bridge_pilotis_{i:02d}',x,y,23.8,1.10 if i>1 else .90)

# Lower contact gallery visible below the main deck in the reference.
linkline=LineString([(-41,-3),(-33,2),(-25,2),(-18,-5),(-12,-10),(-3,-10)])
link=linkline.buffer(2.15,cap_style=2,join_style=2).difference(oval.buffer(-.6))
slabs('lower_contact_gallery',link,9,.48,'lower_link_gallery')
edge=LineString(max(parts(link),key=lambda x:x.area).exterior.coords)
for i in range(math.ceil(edge.length/6.5)):
 a=edge.interpolate(i*6.5);b=edge.interpolate(min((i+1)*6.5,edge.length))
 if a.distance(b)<.1:continue
 if a.x>-5 and b.x>-5:continue
 p=Part(f'lower_gallery_rail_{i:02d}',f'下层联系走廊_栏杆与边梁_{i:02d}','architecture',(a.x,a.y,8.5),'lower_link_gallery')
 beam(p,(a.x,a.y,8.65),(b.x,b.y,8.65),.17,.60,CREAM)
 for z in (9.45,10.05):p.rod((a.x,a.y,z),(b.x,b.y,z),.038,STEEL,0,6)
 p.rod((a.x,a.y,9),(a.x,a.y,10.05),.045,STEEL,0,6);p.finish()
p=Part('lower_contact_ramp','下层联系走廊_9m至7米8接口','architecture',(-3,-10,7.8),'lower_link_gallery')
p.poly([(-3,-12.15,9),(-3,-7.85,9),(3,-7.85,7.8),(3,-12.15,7.8),(-3,-12.15,8.52),(-3,-7.85,8.52),(3,-7.85,7.32),(3,-12.15,7.32)],[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],CREAM,1)
for y in (-12.15,-7.85):p.rod((-3,y,10.05),(3,y,8.85),.045,STEEL,0,6)
p.finish();count['lower_gallery_interfaces']=2

# Recessed right wing: slabs, broad concrete piers and deep window reveals, never a solid dark prism.
for label,g in [('wing',body),('rear',rear)]:
 levels=(.45,7.8,15.8,23.8)
 for z in levels:slabs(label+'_slab_'+str(int(z*10)),g,z,.5 if z<23 else .65,'recessed_retail_slab')
 edge=LineString(g.exterior.coords);n=math.ceil(edge.length/7.5)
 for i in range(n):
  qa=edge.interpolate(i*edge.length/n);qb=edge.interpolate((i+1)*edge.length/n);a=Vector((qa.x,qa.y,0));b=Vector((qb.x,qb.y,0));d=(b-a).normalized();mid=(a+b)*.5;inward=Vector((g.representative_point().x-mid.x,g.representative_point().y-mid.y,0)).normalized()
  p=Part(f'{label}_concrete_bay_{i:02d}',f'{label}_内退窗带与宽混凝土实墙_{i:02d}','architecture',(mid.x,mid.y,0),'concrete_facade_bay')
  # Wide vertical concrete zones remain continuous, horizontal strips differ in weight.
  for aa,bb in [(a,a+d*1.65),(b-d*.85,b)]:beam(p,tuple(aa+Vector((0,0,11.9))),tuple(bb+Vector((0,0,11.9))),.82,23.8)
  for k,(lo,hi) in enumerate(zip(levels,levels[1:])):
   aa=a+d*1.65;bb=b-d*.85
   plinth=3.0 if k==0 else 1.45
   beam(p,tuple(aa+Vector((0,0,lo+plinth*.5))),tuple(bb+Vector((0,0,lo+plinth*.5))),.55,plinth,CREAM)
   beam(p,tuple(aa+Vector((0,0,hi-.48))),tuple(bb+Vector((0,0,hi-.48))),.6,.96,CREAM)
   wa=aa+inward*.42;wb=bb+inward*.42
   window_bay(p,tuple(wa[:2]),tuple(wb[:2]),lo+plinth+.08,hi-.98,900+i*8+k)
   erosion(p,tuple(aa[:2]),tuple(bb[:2]),hi-.02,.8,700+i*5+k)
  p.finish();count['concrete_bays']+=1
 # Interior vertical columns and sparse partitions establish real depth behind openings.
 for ix in range(math.ceil(g.bounds[0]/7),math.floor(g.bounds[2]/7)+1):
  for iy in range(math.ceil(g.bounds[1]/7),math.floor(g.bounds[3]/7)+1):
   x,y=ix*7,iy*7
   if not g.buffer(-1.6).contains(Point(x,y)):continue
   p=Part(f'{label}_internal_{ix+20}_{iy+20}',f'{label}_内部楼层柱梁_{ix}_{iy}','architecture',(x,y,0),'retail_interior_structure')
   p.box((x,y,11.9),(.65,.65,23.8),TILE,1,.07)
   for z in (7.8,15.8):p.box((x,y,z-.6),(3.5,.35,.5),TILE2,1,.035)
   p.finish()
# Left curved volume has internal columns, without any filled cylinder hidden behind glass.
for i in range(6):
 a=i*math.tau/6;x=cx+rx*.48*math.cos(a);y=cy+ry*.48*math.sin(a)
 p=Part(f'oval_internal_{i:02d}',f'弧形商场内部贯通柱_{i:02d}','architecture',(x,y,9),'retail_interior_structure')
 p.rod((x,y,9),(x,y,24.62),.25,TILE,1,12);p.finish()

# Rehost existing lower facade growth; roof-origin vegetation is entirely untouched.
for item in meta['packages']:
 s=item['slug']
 if not s.startswith('facade_growth_'):continue
 x,y,z=item['world_position'];keep=False
 if '_oval_' in s and z>=9:
  target=oval.boundary;newz={10:14.3,15:19.6,20:23.8}.get(int(z),z);keep=True
 elif '_deck_' in s and x>=1.5 and int(z) in (5,10,20):
  target=body.boundary;newz={5:7.8,10:15.8,20:23.4}[int(z)];keep=Point(x,y).distance(target)<6
 if not keep:remove_package(item);count['retired_lower_growth']+=1;continue
 q=nearest_points(Point(x,y),target)[1];delta=Vector((q.x-x,q.y-y,newz-z))
 for key in ('collection','source_collection'):
  for o in bpy.data.collections[item[key]].objects:o.location+=delta;o['version']='v009'
 p=dict(item);p.update(version='v009',component_revision='v009',source_blend=BLEND.relative_to(R).as_posix(),world_position=[v+d for v,d in zip(item['world_position'],delta)],bounds_min=[v+d for v,d in zip(item['bounds_min'],delta)],bounds_max=[v+d for v,d in zip(item['bounds_max'],delta)])
 hosts=[c for c in catalog if c['slug'].startswith('oval_terrace_band_' if '_oval_' in s else 'wing_concrete_bay_')]
 host=min(hosts,key=lambda h:math.dist(h['world_position'][:2],(q.x,q.y)));p['dependencies']=[host['package_id']];p['rehosted_lower_vegetation']=True;catalog.append(p);count['rehosted_lower_growth']+=1

bpy.context.view_layer.update()
assert locked=={n:object_signature(bpy.data.objects[n]) for n in locked},'Protected top changed'
assert mat==material_signature() and len(bpy.data.materials)==4
assert all(hashlib.sha256((R/p).read_bytes()).hexdigest()==s for p,s in files.items())
ids={p['package_id'] for p in catalog}
assert all(d in ids for p in catalog for d in p.get('dependencies',[]))
for p in catalog:
 p['source_blend']=BLEND.relative_to(R).as_posix();p['version']='v009'
 if p.get('lower_structure'):assert max(p['dimensions'][:2])<=10.01,(p['slug'],p['dimensions'])
 path=OUT/'component_packages'/p['category']/p['slug'];path.mkdir(parents=True,exist_ok=True);(path/'asset_manifest.json').write_text(json.dumps(p,ensure_ascii=False,indent=2),encoding='utf8')
meta.update(version='v009',source_blend=BLEND.relative_to(R).as_posix(),packages=catalog,package_count=len(catalog),component_definition_count=len({p['component_definition'] for p in catalog}),floor_count=3,floor_height_m=None,vertical_structure=plan['inferred_dimensions'],source_status='lower_structure_pending_visual_review',reference='references/参考_下部结构真值.png',geometry_parent_source=PREVIOUS.relative_to(R).as_posix(),geometry_parent_sha256=files[PREVIOUS.relative_to(R).as_posix()],scope=plan['editable'],locked_asset_hashes=files)
meta.pop('source_sha256',None);meta.pop('visual_review',None)
assert meta['component_definition_count']<=50
(OUT/'catalog.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'component_packages/tree.txt').write_text('\n'.join(p['category']+'/'+p['slug']+' — '+p['display_name'] for p in catalog),encoding='utf8')
shutil.copy2(OLD/'route_centerlines.json',OUT/'route_centerlines.json')
for n,loc,target,lens in [('CAM_下部_左楼架空与退台',(-18,-62,34),(cx,cy,14),40),('CAM_下部_右翼窗墙',(95,-98,40),(31,-6,12),48),('CAM_下部_中央架空',(-28,-57,15),(-28,8,16),32)]:
 data=bpy.data.cameras.new(n);o=bpy.data.objects.new(n,data);sc.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();data.lens=lens;data.clip_end=600
sc['version']='v009';sc['scope']='顶层锁定；按参考重建架空退台商城下部'
for scene in bpy.data.scenes:
 scene['floor_count']=3;scene['floor_height_m']='variable';scene['left_floor_levels_m']=[9.,14.3,19.6,25.];scene['right_floor_levels_m']=[.45,7.8,15.8,23.8]
game=next(c for c in bpy.data.collections if c.name.startswith('02_游戏输出'));game.name='02_游戏输出_独立资产包_v009'
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
report={'passed':True,'source_sha256':hashlib.sha256(BLEND.read_bytes()).hexdigest(),'locked_match':True,'locked_objects':len(locked),'original_materials_unchanged':True,'modified_scope':sorted(editable),'removed_packages':sorted(editable-{p['slug'] for p in catalog}),'new_structure_packages':newpackages,'counts':dict(count),'package_count':len(catalog),'component_definitions':meta['component_definition_count'],'body_footprints':{'oval':oval.wkt,'right':body.wkt,'rear':rear.wkt},'visual_acceptance':'pending'}
(OUT/'qa/lower_structure_build.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('LOWER_STRUCTURE_BUILT',len(catalog),dict(count),flush=True)
prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
for d in prefs.devices:d.use=d.type!='CPU'
sc.cycles.device='GPU';sc.cycles.samples=48
for name in ['CAM_参考全景','CAM_俯视轮廓','CAM_下部_左楼架空与退台','CAM_下部_右翼窗墙','CAM_下部_中央架空']:
 sc.camera=bpy.data.objects[name];sc.render.resolution_x=1600;sc.render.resolution_y=1000;sc.render.resolution_percentage=100;sc.render.filepath=str(OUT/'previews'/(name[4:]+'.png'));bpy.ops.render.render(write_still=True,scene=sc.name);print('RENDERED',name,flush=True)
