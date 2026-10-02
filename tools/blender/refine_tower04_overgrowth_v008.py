"""Reference-led dense overgrowth and decay. Existing structure/layout stay fixed."""
import ast, bpy, hashlib, json, math, random, shutil, sys
from pathlib import Path
from collections import defaultdict, Counter
from mathutils import Vector
from mathutils.geometry import tessellate_polygon

R=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(Path(__file__).parent))
sys.path.insert(0,sys.argv[sys.argv.index('--geometry-libs')+1])
from shapely import wkt
from shapely.geometry import Polygon,Point,LineString
from shapely.ops import unary_union
from shapely import constrained_delaunay_triangles
import tower04_plan_v002 as P
OLD=R/'assets/art/environments/open_world/source/tower_04/v006'
OUT=OLD.parent/'v008'
PREVIOUS=next(OLD.glob('*.blend'))
BLEND=OUT/'塔4_植被侵占破损商城_150x50m_v008.blend'
assert not BLEND.exists(), 'Create a new source version, never overwrite an existing one'
for d in ('qa','previews','mood','references','component_packages'):(OUT/d).mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(PREVIOUS))
sc=bpy.data.scenes['Scene']; bpy.context.window.scene=sc
meta=json.loads((OLD/'catalog.json').read_text(encoding='utf8'))
ASSET=meta['asset_id']; NAMES=meta['material_roles']; MATS=[bpy.data.materials[n] for n in NAMES]
DONOR=R/meta['material_source']; PALETTE=R/meta['shared_palette']
CREAM=LIGHT=(9,9); TILE=(9,8); TILE2=(9,7); DARK=(9,1); STEEL=(9,4)
GREEN=(5,4); LEAF=(6,4); LEAFHI=(7,4); SOIL=(4,4); RUST=(5,2)
def load_defs(file,names):
 p=R/'tools/blender'/file
 n=[n for n in ast.parse(p.read_text(encoding='utf8')).body if isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name in names]
 exec(compile(ast.Module(body=n,type_ignores=[]),str(p),'exec'),globals())
load_defs('refine_tower04_routes_v003.py',{'sha','floats','signature','material_signature'})
load_defs('build_skyline_08_source_v001.py',{'coll','uv_mesh','Part'}); BasePart=Part
load_defs('build_tower04_mall_source.py',{'Part','ellipse'}); OriginalPart=Part
cats={'architecture':'01_建筑结构','floor':'02_地面系统','garden':'04_曲线景观','support':'05_环境支持','facilities':'03_天台固定设施'}
CATS={k:bpy.data.collections[n] for k,n in cats.items()}
SCATS={k:bpy.data.collections[n+'_制作源'] for k,n in cats.items()}
game=next(c for c in bpy.data.collections if c.name.startswith('02_游戏输出'))
oldmap={p['slug']:p for p in meta['packages']}
editable={s for s in oldmap if s.startswith(('tile_r','slow_lane_x','glass_pavilion_x','leaf_canopy_x')) or s in ('oval_glazing','wing_glazing')}
oldsource=meta['source_blend']; newsource=BLEND.relative_to(R).as_posix()
def revise(v):
 if isinstance(v,dict):return {k:revise(x) for k,x in v.items()}
 if isinstance(v,list):return [revise(x) for x in v]
 if isinstance(v,str):return v.replace(oldsource,newsource).replace('v006','v008')
 return v
catalog=[]; count=Counter(); foliage=[]
class Part(OriginalPart):
 def finish(self):
  result=super().finish(); info=catalog[-1]
  info.update(version='v008',component_revision='v008',floor_range='1F–5F及25m天台')
  for o in result:o['version']='v008'
  return result

planning={
 'version':'v008','reference_priority':'2026-10-02 用户纠正：高覆盖植被和破损的未来末世商城是视觉重点',
 'replaces_prior_restrained_vine_limit':True,
 'allowed':['新增密集屋顶及棚架边缘植被','立面垂挂和柱体攀缘植被','花池溢出生长与砖缝杂草','幕墙/玻璃亭/顶棚非承重面板破损','逐板磨损和碎屑'],
 'locked':['建筑承重结构、层高和原平面轮廓','跑道中心线与主要通路','营地和固定设施摆位','原四材质、公共贴图、MipMap','原固定验收灯光/镜头'],
 'new_component_definitions':['overgrown_canopy_edge','overgrown_roof_edge','climbing_column_ivy','facade_hanging_garden','planter_spill_growth','joint_weed_cluster'],
 'plant_leaf_variants':3,'cluster_max_xy_m':8,'structural_footprint_m':[150,50],
 'foliage_envelope_policy':'叶片及垂挂允许超出结构边缘最多2m；单独报告视觉包络，不改变150×50m建筑尺寸',
 'density_design':{'canopy':'双边连续但起伏变化的叶簇与1–3.5m垂挂；保留格构透空','roof':'屋顶及平台边缘大团块，并向立面垂挂3–9m','columns':'5根Y柱根部、主干及分叉均攀缘','facade':'逐层局部复生与上层连贯垂挂','ground':'花池向外溢出、砖缝生草，保留连续路线'},
 'component_definition_limit':50,'source_only':True}
(OUT/'component_plan.json').write_text(json.dumps(planning,ensure_ascii=False,indent=2),encoding='utf8')
presentation={'末世夕阳','天空冷色柔光','CAM_末世_平台总览'}
planning['presentation_adjustments']=sorted(presentation)
locked={o.name:signature(o) for o in bpy.data.objects if o.get('package_id','').split('/')[-1] not in editable and o.name not in presentation}
mat_signature=material_signature()
files={str(f.relative_to(R)).replace('\\','/'):hashlib.sha256(f.read_bytes()).hexdigest() for f in (PREVIOUS,DONOR,PALETTE,Path(str(PALETTE)+'.import'))}
(OUT/'qa/locked_before.json').write_text(json.dumps({'objects':locked,'materials':mat_signature,'files':files,'editable_packages':sorted(editable)},ensure_ascii=False,indent=2),encoding='utf8')
layout=json.loads((OLD.parent/'v004/qa/surface_plan.json').read_text(encoding='utf8'))['frozen_layout']
deck=wkt.loads(layout['deck']['wkt']); route=wkt.loads(layout['route']['wkt'])
def facecell(o,f):
 u=o.data.uv_layers.active
 return (int(sum(u.data[i].uv.x for i in f.loop_indices)/len(f.loop_indices)*10),int((1-sum(u.data[i].uv.y for i in f.loop_indices)/len(f.loop_indices))*10))
def area(v):return sum((Vector(v[i])-Vector(v[0])).cross(Vector(v[i+1])-Vector(v[0])).length/2 for i in range(1,len(v)-1))
def polygon_parts(g):
 if g.geom_type=='Polygon':return [g]
 return [p for p in getattr(g,'geoms',[]) if p.geom_type=='Polygon']
def patch(p,g,z,c,m=1):
 for poly in polygon_parts(g):
  if poly.area<.0001:continue
  for tri in constrained_delaunay_triangles(poly).geoms:p.poly([(*q,z) for q in list(tri.exterior.coords)[:-1]],[(0,1,2)],c,m)
def leaf(p,root,direction,length,rng,dry=False):
 root=Vector(root); d=Vector(direction).normalized()*length
 n=Vector((rng.uniform(-1,1),rng.uniform(-1,1),rng.uniform(.1,1))).normalized()
 s=d.cross(n)
 if s.length<.0001:s=Vector((1,0,0))
 s.normalize();n=s.cross(d).normalized();width=length*rng.uniform(.78,1.10)
 variant=rng.randrange(3)
 outlines=[[(0,0),(.05,.32),(.23,.5),(.50,.47),(.76,.28),(1,0),(.76,-.28),(.50,-.47),(.23,-.5),(.05,-.32)],
           [(0,0),(-.08,.22),(.12,.5),(.38,.49),(.65,.30),(1,0),(.65,-.30),(.38,-.49),(.12,-.5),(-.08,-.22)],
           [(0,0),(.15,.27),(.27,.48),(.44,.28),(.68,.38),(1,0),(.68,-.38),(.44,-.28),(.27,-.48),(.15,-.27)]]
 v=[root+d*a+s*width*b-n*length*.03*abs(b) for a,b in outlines[variant]]+[root+d*.43+n*length*.045]
 c=rng.choice([(5,3),(6,3)]) if dry else rng.choice([(5,4),(6,4),(6,4),(7,4),(7,4),(6,3)])
 p.poly(v,[(i,(i+1)%10,10) for i in range(10)],c,1);count['leaves']+=1;count['leaf_variant_'+str(variant)]+=1
def bush(p,center,radius,height,rng,density=75):
 cx,cy,cz=center
 for j in range(density):
  a=rng.random()*math.tau; rr=radius*math.sqrt(rng.random()); h=height*(1-(rr/radius)**1.5)*rng.uniform(.35,1.0)
  root=(cx+rr*math.cos(a),cy+rr*math.sin(a),cz+h)
  leaf(p,root,(math.cos(a)*.7,math.sin(a)*.7,rng.uniform(-1.0,.6)),rng.uniform(.17,.32),rng)
 for j in range(4):
  a=j*math.tau/4+rng.random();p.rod((cx,cy,cz-.05),(cx+radius*.65*math.cos(a),cy+radius*.65*math.sin(a),cz+height*.7),.015,(4,4),1,5)
def drape(p,anchor,length,width,rng,strands=5):
 x,y,z=anchor
 for strand in range(strands):
  phase=rng.random()*math.tau; dx=rng.uniform(-.5,.5)*width;dy=rng.uniform(-.30,.30)
  ln=length*rng.uniform(.24,1.16); steps=max(5,int(ln/.16)); pts=[]
  bend=rng.uniform(-.65,.65);side=rng.uniform(-.45,.45)
  for i in range(steps+1):
   t=i/steps;pts.append((x+dx+bend*t+.12*math.sin(t*9+phase),y+dy+side*t+.10*math.cos(t*8+phase),z-ln*t))
  p.path(pts,.009,(4,4),1,5)
  for i,q in enumerate(pts[1:]):
   if rng.random()<.10:continue
   for k in range(rng.choice([2,3,4,5])):
    a=phase+i*1.3+k*2.1
    offset=Vector((math.cos(a),math.sin(a),-.15))*rng.uniform(.02,.15)
    leaf(p,Vector(q)+offset,(math.cos(a)*.4,math.sin(a)*.4,-rng.uniform(.4,1.0)),rng.uniform(.15,.28),rng)
  if strand%2==0:
   t=rng.uniform(.12,.55);q=pts[int(t*steps)]
   bush(p,q,rng.uniform(.28,.55),rng.uniform(.22,.45),rng,45)
 count['vine_strands']+=strands
def inherit(item):
 p=Part(item['slug'],item['display_name'],item['category'],item['world_position'],item['component_definition'])
 rng=random.Random('decay7'+item['slug'])
 for name in item['objects']:
  o=bpy.data.objects[name]
  for f in o.data.polygons:
   v=[tuple(o.matrix_world@o.data.vertices[i].co) for i in f.vertices]; c=facecell(o,f);m=MATS.index(o.data.materials[f.material_index]);a=area(v)
   glass=item['slug'] in ('oval_glazing','wing_glazing') or item['slug'].startswith('glass_pavilion_')
   if glass and m==2 and a>.08 and rng.random()<.38:
    count['broken_glazing_faces']+=1
    if rng.random()<.55:continue
    va,vb,vc=map(Vector,v[:3]);p.poly([va,va+(vb-va)*rng.uniform(.2,.55),va+(vc-va)*rng.uniform(.18,.5)],[(0,1,2)],(6,5),2);continue
   if glass and m==0 and rng.random()<.18:c=(5,2)
   p.poly(v,[tuple(range(len(v)))],c,m)
 return p
def surface_polygon(p,z):
 gs=[]
 for f in p.f:
  v=[p.v[i] for i in f]
  if all(abs(q[2]-z)<.0003 for q in v):
   g=Polygon([(q[0],q[1]) for q in v])
   if g.is_valid and g.area>1e-6:gs.append(g)
 return unary_union(gs)
def weather(p,item):
 z=25.055 if item['slug'].startswith('tile_r') else 25.059
 g=surface_polygon(p,z)
 if g.is_empty:return
 rng=random.Random('surface7'+item['slug']);b=g.bounds
 for j in range(max(3,int(g.area*9.0))):
  q=Point(rng.uniform(b[0],b[2]),rng.uniform(b[1],b[3]))
  if not g.contains(q):continue
  radius=rng.uniform(.018,.085);n=7
  poly=Polygon([(q.x+math.cos(i*math.tau/n)*radius*rng.uniform(.45,1.0),q.y+math.sin(i*math.tau/n)*radius*rng.uniform(.45,1.0)) for i in range(n)]).buffer(0).intersection(g.buffer(-.015))
  patch(p,poly,z+.0007,rng.choice([(9,6),(9,7),(9,8),(6,3)]))
  count['weather_patches']+=1
 for j in range(max(1,int(g.area*.7))):
  edge=LineString(rng.choice(polygon_parts(g)).exterior.coords);q=edge.interpolate(rng.random()*edge.length)
  if route.buffer(-.15).contains(q):continue
  for k in range(rng.randint(7,13)):
   a=rng.random()*math.tau;leaf(p,(q.x,q.y,z+.018),(math.cos(a),math.sin(a),rng.uniform(.6,1.8)),rng.uniform(.08,.20),rng)
  count['joint_weeds']+=1
 if rng.random()<.4 and g.area>1:
  q=g.representative_point()
  for j in range(3):
   p.box((q.x+rng.uniform(-.22,.22),q.y+rng.uniform(-.2,.2),z+.025),(.13+rng.random()*.15,.10,.035),rng.choice([(9,6),(9,7),(5,3)]),1,.015)
  count['rubble_tiles']+=1
for item in meta['packages']:
 if item['slug'] not in editable:
  catalog.append(revise(item));continue
 p=inherit(item)
 if item['slug'].startswith(('tile_r','slow_lane_x')):weather(p,item)
 for key in ('collection','source_collection'):
  col=bpy.data.collections[item[key]]
  for ob in list(col.objects):
   data=ob.data;bpy.data.objects.remove(ob,do_unlink=True)
   if data.users==0:bpy.data.meshes.remove(data)
  bpy.data.collections.remove(col)
 p.finish(); info=catalog[-1]
 for key in ('dependencies','zone_id','zone_name','platform_scope','assembly_grid','cut_bounds_xy','interfaces','tile_row','tile_column','tile_fragment','previous_package_id'):
  if key in item:info[key]=item[key]
 count['weathered_packages']+=1
print('DECAY_BUILT',dict(count),flush=True)

def cluster(slug,name,definition,center,host):
 return Part(slug,name,'garden',center,definition)
def finish_plant(p,host):
 if not p.f:return
 dims=[max(v[k] for v in p.v)-min(v[k] for v in p.v) for k in range(2)]
 if max(dims)>8.0:
  bins={}
  for face,color,material in zip(p.f,p.co,p.mi):
   vv=[p.v[j] for j in face];cx=sum(v[0] for v in vv)/len(vv);cy=sum(v[1] for v in vv)/len(vv)
   key=(math.floor(cx/4),math.floor(cy/4))
   if key not in bins:bins[key]=Part(p.slug+f'_part{len(bins):02d}',p.name+f'_分段{len(bins):02d}',p.category,(key[0]*4+2,key[1]*4+2,p.origin.z),p.definition)
   bins[key].poly(vv,[tuple(range(len(vv)))],color,material)
  for part in bins.values():finish_plant(part,host)
  return
 p.finish();info=catalog[-1]
 info.update(dependencies=[host] if host else [],platform_scope=True,visual_overlay=True,vegetation=True,coverage_role=p.definition)
 assert max(info['dimensions'][:2])<=8.0,(p.slug,info['dimensions'])
 foliage.append({'slug':p.slug,'definition':p.definition,'bounds_min':info['bounds_min'],'bounds_max':info['bounds_max'],'polygons':len(p.f)})
def nearest_host(x,y,prefix):
 choices=[p for p in catalog if p['slug'].startswith(prefix)]
 return min(choices,key=lambda p:math.dist(p['world_position'][:2],(x,y)))['package_id']

# A continuous overgrown roof silhouette, with explicit gaps rather than uniform hedges.
edges=[('deck',LineString(deck.exterior.coords),25.15,'terrace_shell'),('oval',LineString(ellipse(*P.CIRCLE_CENTER,*P.CIRCLE_RADII,120)+[ellipse(*P.CIRCLE_CENTER,*P.CIRCLE_RADII,120)[0]]),25.18,'oval_roof')]
for label,edge,z,prefix in edges:
 for i in range(int(edge.length/3.3)):
  rng=random.Random(label+str(i)+'7');q=edge.interpolate((i+.4)*3.3)
  if label=='deck' and i%13 in (9,10):continue
  p=cluster(f'overgrown_{label}_edge_{i:03d}',f'{label}_屋顶侵占与垂挂_{i:03d}','overgrown_roof_edge',(q.x,q.y,z),None)
  for j in range(rng.randint(4,7)):
   qq=edge.interpolate(min(edge.length,(i+rng.random())*3.3));bush(p,(qq.x,qq.y,z),rng.uniform(.5,1.15),rng.uniform(.45,1.2),rng,100)
  drape(p,(q.x,q.y,z+.35),rng.uniform(4.0,9.0),2.0,rng,10)
  finish_plant(p,nearest_host(q.x,q.y,prefix));count['roof_clusters']+=1

# Main canopy: dense irregular leaf masses following each real edge, and long hanging tendrils.
for side,pts in [('north',P.TOP),('south',P.BOTTOM)]:
 edge=LineString(pts)
 for i in range(int(edge.length/2.5)):
  rng=random.Random(side+str(i)+'7');q=edge.interpolate((i+.4)*2.5)
  p=cluster(f'overgrown_canopy_{side}_{i:03d}',f'棚架{side}_浓密叶簇垂挂_{i:03d}','overgrown_canopy_edge',(q.x,q.y,29.8),None)
  for j in range(rng.randint(3,6)):
   qq=edge.interpolate(min(edge.length,(i+rng.random())*2.5));bush(p,(qq.x,qq.y,29.84),rng.uniform(.38,.85),rng.uniform(.35,.8),rng,100)
  drape(p,(q.x,q.y,29.8),rng.uniform(.8,3.5),1.6,rng,rng.randint(6,11))
  finish_plant(p,nearest_host(q.x,q.y,'leaf_canopy'));count['canopy_clusters']+=1

# Y columns form major near-camera focal points; vine roots remain attached to the column.
for i,item in enumerate([p for p in meta['packages'] if p['slug'].startswith('canopy_column_')]):
 x,y,z=item['world_position'];rng=random.Random(7700+i)
 p=cluster(f'ivy_column_{i:02d}',f'Y柱攀缘根系与分叉叶簇_{i:02d}','climbing_column_ivy',(x,y,25),item['package_id'])
 for h in range(18):
  a=h*.8;bush(p,(x+.30*math.cos(a),y+.30*math.sin(a),25.1+h*.23),.36,.35,rng,32)
 for point in (P.BOTTOM[[5,14,23,32,40][i]],P.TOP[[5,14,23,32,40][i]]):
  for j in range(7):
   t=j/6; q=Vector((x,y,27.2)).lerp(Vector((*point,29.7)),t);bush(p,q,.4,.45,rng,35)
 for j in range(3):bush(p,(x+(j-1)*.45,y,25.10),.65,.55,rng,55)
 finish_plant(p,item['package_id']);count['column_clusters']+=1

# Repeated floor ledges host further growth; the original load-bearing frame is not deformed.
for label,edge,z,prefix in edges:
 for i in range(int(edge.length/6.0)):
  if i%4==3:continue
  rng=random.Random('facade'+label+str(i));q=edge.interpolate((i+.5)*6.0)
  for level in (5.15,10.15,15.15,20.15):
   if rng.random()<.15:continue
   p=cluster(f'facade_growth_{label}_{i:03d}_{int(level)}',f'{label}_立面楼层生长带_{i:03d}_{int(level)}','facade_hanging_garden',(q.x,q.y,level),None)
   for j in range(3):bush(p,(q.x+rng.uniform(-.5,.5),q.y+rng.uniform(-.4,.4),level),rng.uniform(.6,1.0),rng.uniform(.4,.8),rng,90)
   drape(p,(q.x,q.y,level),rng.uniform(2.5,4.8),1.8,rng,8)
   finish_plant(p,'tower_04/'+('oval_glazing' if label=='oval' else 'wing_glazing'));count['facade_clusters']+=1

# Existing beds overflow onto adjacent paving in separate <=6m foliage packages.
for idx,(slug,record) in enumerate(layout.items()):
 if slug in ('route','deck','lawn_court'):continue
 g=wkt.loads(record['wkt']);g=max(polygon_parts(g),key=lambda p:p.area);edge=LineString(g.exterior.coords)
 for i in range(max(1,int(edge.length/2.6))):
  rng=random.Random(slug+str(i)+'bed7');q=edge.interpolate((i+.3)*2.6)
  if route.buffer(.15).contains(q):continue
  p=cluster(f'bed_spill_{idx:02d}_{i:03d}',f'花池溢生叶丛_{idx:02d}_{i:03d}','planter_spill_growth',(q.x,q.y,25.6),None)
  for j in range(3):bush(p,(q.x+rng.uniform(-.4,.4),q.y+rng.uniform(-.4,.4),25.60),.6,.7,rng,75)
  drape(p,(q.x,q.y,25.65),.55,1.0,rng,4)
  host=nearest_host(q.x,q.y,'island') if any(p['slug'].startswith('island') for p in catalog) else nearest_host(q.x,q.y,'terrace_shell')
  finish_plant(p,host);count['bed_clusters']+=1

# Cover the previously bare circular roof with irregular rooftop gardens, leaving the spiral readable.
cx,cy=P.CIRCLE_CENTER;rx,ry=P.CIRCLE_RADII
for i in range(36):
 rng=random.Random(78800+i);a=rng.random()*math.tau;rr=math.sqrt(rng.uniform(.03,.78));x=cx+rx*rr*math.cos(a);y=cy+ry*rr*math.sin(a)
 p=cluster(f'oval_roof_rewild_{i:02d}',f'圆楼屋顶返野花园_{i:02d}','planter_spill_growth',(x,y,25.08),None)
 for j in range(rng.randint(5,9)):bush(p,(x+rng.uniform(-1.3,1.3),y+rng.uniform(-1.0,1.0),25.08),rng.uniform(.5,.95),rng.uniform(.5,1.4),rng,90)
 finish_plant(p,nearest_host(x,y,'oval_roof'));count['roof_garden_clusters']+=1

assert locked=={name:signature(bpy.data.objects[name]) for name in locked},'Unexpected change outside authorized edit scope'
assert mat_signature==material_signature() and len(bpy.data.materials)==4
assert all(hashlib.sha256((R/f).read_bytes()).hexdigest()==h for f,h in files.items())
game.name='02_游戏输出_独立资产包_v008';sc['version']='v008';sc['scope']='高覆盖植被侵占与非承重表面破损；结构和流线固定'
ids={p['package_id'] for p in catalog}
assert all(d in ids for p in catalog for d in p.get('dependencies',[]))
for info in catalog:
 info['source_blend']=newsource;info['version']='v008'
 for name in info['objects']:bpy.data.objects[name]['version']='v008'
 directory=OUT/'component_packages'/info['category']/info['slug'];directory.mkdir(parents=True,exist_ok=True)
 (directory/'asset_manifest.json').write_text(json.dumps(info,ensure_ascii=False,indent=2),encoding='utf8')
meta=revise(meta);meta.update(packages=catalog,package_count=len(catalog),version='v008',source_blend=newsource,source_status='dense_overgrowth_pending_visual_review',component_definition_count=len({p['component_definition'] for p in catalog}),reference_atmosphere_status='dense_reference_foliage_priority',locked_asset_hashes=files,scope=planning['allowed'])
assert meta['component_definition_count']<=50
(OUT/'catalog.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'component_packages/tree.txt').write_text('\n'.join(p['category']+'/'+p['slug']+' — '+p['display_name'] for p in catalog),encoding='utf8')
shutil.copy2(OLD/'route_centerlines.json',OUT/'route_centerlines.json')
for f in (OLD/'references').glob('*.png'):shutil.copy2(f,OUT/'references'/f.name)
# Presentation changes expose the actual foliage geometry, without changing original materials.
mood=bpy.data.scenes['塔4_黄昏末世氛围'];mood['version']='v008'
sun=bpy.data.objects['末世夕阳'];az=math.radians(200);el=math.radians(22)
sun.rotation_euler=Vector((-math.cos(el)*math.cos(az),-math.cos(el)*math.sin(az),-math.sin(el))).to_track_quat('-Z','Y').to_euler()
sun.data.energy=3.0;sun.data.color=(1.0,.81,.57)
fill=bpy.data.objects['天空冷色柔光'];fill.data.energy=18000;fill.data.color=(.8,.88,1.0)
world=mood.world;nt=world.node_tree;sky=nt.nodes.get('末世展示_黄昏天空');sky.sun_elevation=el;sky.sun_rotation=az;sky.dust_density=.6
bg=nt.nodes.get('Background');bg.inputs['Strength'].default_value=.40
# A camera-only sky gradient removes the flat brown below-horizon Nishita background.
out=next(n for n in nt.nodes if n.type=='OUTPUT_WORLD');mix=nt.nodes.new('ShaderNodeMixShader');lp=nt.nodes.new('ShaderNodeLightPath')
camera_bg=nt.nodes.new('ShaderNodeBackground');tc=nt.nodes.new('ShaderNodeTexCoord');sep=nt.nodes.new('ShaderNodeSeparateXYZ');ramp=nt.nodes.new('ShaderNodeValToRGB')
ramp.color_ramp.elements[0].position=.05;ramp.color_ramp.elements[0].color=(.23,.32,.40,1)
ramp.color_ramp.elements[1].position=.8;ramp.color_ramp.elements[1].color=(.62,.65,.64,1)
nt.links.new(tc.outputs['Normal'],sep.inputs[0]);nt.links.new(sep.outputs['Z'],ramp.inputs[0]);nt.links.new(ramp.outputs['Color'],camera_bg.inputs['Color'])
nt.links.new(lp.outputs['Is Camera Ray'],mix.inputs[0]);nt.links.new(bg.outputs[0],mix.inputs[1]);nt.links.new(camera_bg.outputs[0],mix.inputs[2]);nt.links.new(mix.outputs[0],out.inputs['Surface'])
for n in mood.node_tree.nodes:
 if n.type=='MATH' and n.operation=='MULTIPLY':n.inputs[1].default_value=.025
cam=bpy.data.objects['CAM_末世_平台总览'];cam.data.lens*=.85
planning['presentation_adjustments']=sorted(presentation)
(OUT/'component_plan.json').write_text(json.dumps(planning,ensure_ascii=False,indent=2),encoding='utf8')
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
report={'passed':True,'counts':dict(count),'new_foliage_packages':foliage,'locked_object_count':len(locked),'locked_match':True,'materials_unchanged':True,'source_sha256':hashlib.sha256(BLEND.read_bytes()).hexdigest(),'package_count':len(catalog),'definitions':meta['component_definition_count'],'visual_acceptance':'pending'}
(OUT/'qa/overgrowth_build.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('OVERGROWTH_BUILT',dict(count),len(catalog),flush=True)
prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
for d in prefs.devices:d.use=d.type!='CPU'
mood=bpy.data.scenes['塔4_黄昏末世氛围'];bpy.context.window.scene=mood;mood.cycles.device='GPU';mood.cycles.samples=32
for name in ['CAM_末世_平台总览','CAM_末世_棚下主街','CAM_末世_营地设施近景']:
 mood.camera=bpy.data.objects[name];mood.render.resolution_x=1400;mood.render.resolution_y=875;mood.render.resolution_percentage=100
 mood.render.filepath=str(OUT/'mood'/(name[4:]+'.png'));bpy.ops.render.render(write_still=True,scene=mood.name);print('RENDERED',name,flush=True)
