"""Five independent low-poly overgrown skyline groups. Blender 4.5 background."""
import bpy, sys, json, math, random, ast, shutil, hashlib
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(R/'tools/blender'))
import tower04_court_common as H
from tower04_court_common import Part, coll, uv_mesh, camera, render
OUT=R/'assets/art/environments/open_world/source/landscape_tower04/v001'
BLEND=OUT/'景观建筑_塔4周边五组废墟藤蔓_v001.blend'
for d in ['previews','qa','references','component_packages']:(OUT/d).mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc=bpy.context.scene;sc.name='景观建筑_五组总览';sc.unit_settings.system='METRIC'
palette=bpy.data.images.load(str(R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'))
MATS=[]
for i,n in enumerate(H.NAMES[:3]):
 m=bpy.data.materials.new(n);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF')
 p.inputs['Metallic'].default_value=[.82,.02,.16][i];p.inputs['Roughness'].default_value=[.29,.70,.16][i];p.inputs['Coat Weight'].default_value=[.15,0,.65][i]
 uv=m.node_tree.nodes.new('ShaderNodeUVMap');uv.uv_map='PaletteUV';tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=palette;tex.interpolation='Closest'
 m.node_tree.links.new(uv.outputs['UV'],tex.inputs['Vector']);m.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color']);MATS.append(m)
H.MATS=MATS
src=coll('01_制作组件_四层楼身与大片藤蔓',sc.collection);src.hide_render=True;src.hide_viewport=True
game=coll('02_游戏输出_五组景观建筑',sc.collection)
display=coll('90_展示与验收_灯光相机',sc.collection)
defs={};definition_rows=[];instance_rows=[];group_rows=[]
def define(key,name,p):
 mesh,origin,dims=H.mesh_of(p)
 # Keep authored module coordinates, including hanging greenery with its top at Z=0.
 for v in mesh.vertices:v.co+=origin
 o=bpy.data.objects.new(name+'_制作源',mesh);src.objects.link(o)
 o['component_definition']=key;o['front_direction']='-Y'
 defs[key]=mesh
 definition_rows.append({'id':key,'name':name,'dimensions':dims,'triangles':sum(len(f.vertices)-2 for f in mesh.polygons),'mesh':mesh.name})
def floor_module(key,w,d,variant):
 p=Part(key,key,'architecture');rng=random.Random(22+variant)
 # Large continuous wall core and structural members, no bricks, bevels or tiny trim.
 p.box((0,0,8),(w-.8,d-.8,16),(9,5),1)
 for z in [0,4,8,12]:p.box((0,0,z+.30),(w+.45,d+.45,.6),(9,8),1)
 pillars=[(-w/2,-d/2),(w/2,-d/2),(-w/2,d/2),(w/2,d/2)]
 if key!='slim':pillars += [(0,-d/2),(0,d/2),(-w/2,0),(w/2,0)]
 for x,y in pillars:
  p.box((x,y,8),(.62,.62,16),(9,7),1)
 # Flat inset dark window fields provide distant rhythm at two triangles per bay.
 for side in range(4):
  width=w if side%2==0 else d; depth=d if side%2==0 else w
  for f in range(4):
   bays=3 if key=='slim' else 4
   for j in range(bays):
    u=-width/2+(j+.5)*width/bays;hw=width/(2*bays)-.40;z=f*4+.9
    pts=[(u-hw,-depth/2+.34,z),(u+hw,-depth/2+.34,z),(u+hw,-depth/2+.34,z+2.6),(u-hw,-depth/2+.34,z+2.6)]
    a=side*math.pi/2;pts=[(x*math.cos(a)-y*math.sin(a),x*math.sin(a)+y*math.cos(a),zz) for x,y,zz in pts]
    glass=rng.random()>.68
    if rng.random()<.28:
     pts[2]=(pts[2][0],pts[2][1],pts[2][2]-rng.uniform(.5,1.8))
    p.poly(pts,[(0,1,2,3)],(9,2 if glass else 0),2 if glass else 1)
 define(key,'四层楼身_'+key,p)
for key,w,d,v in [('narrow',16,14,0),('wide',25,14,1),('slim',12,12,2)]:floor_module(key,w,d,v)
def crown(key,w,d,seed):
 p=Part(key,key,'architecture');rng=random.Random(seed)
 p.box((0,0,.3),(w+.45,d+.45,.6),(9,7),1)
 # Open, roofless collapsed penthouse. Missing spans and jagged wall tops are actual silhouette.
 for side in range(4):
  width=w if side%2==0 else d;dep=d if side%2==0 else w;a=side*math.pi/2
  q=Part('q','q','architecture')
  coords=[(-width/2,.6),(-width/2,rng.uniform(4.2,5.8)),(-width*.30,4.7),(-width*.24,2.1),(width*.06,rng.uniform(.8,2.5)),(width/2,rng.uniform(3.0,5.7)),(width/2,.6)]
  q.panel(coords,-dep/2,(9,7),1,.42)
  if side%2==0:
   for x in [-width*.45,width*.43]:q.box((x,-dep/2,3.6),(.48,.5,6.0),(9,8),1)
  if side%2==0:q.box((-width*.27,-dep/2,5.4),(width*.40,.42,.36),(9,6),1)
  q.v=[(x*math.cos(a)-y*math.sin(a),x*math.sin(a)+y*math.cos(a),z) for x,y,z in q.v]
  p.poly(q.v,q.f,(9,7),1)
 for i in range(2):
  x=rng.uniform(-w*.35,w*.35);y=rng.uniform(-d*.35,d*.35)
  p.box((x,y,.8),(rng.uniform(1,3),rng.uniform(1,2),.8),(9,5),1)
 for i in range(2):p.rod((-w*.4+i*1.4,-d/2,4.2),(-w*.4+i*1.4+.4,-d/2,7+i*.6),.065,(9,3),0,4)
 define(key,'断顶残墙_'+key,p)
for key,w,d,seed in [('crown_narrow',16,14,30),('crown_wide',25,14,31),('crown_slim',12,12,32)]:crown(key,w,d,seed)
def vine(key,seed,width,length):
 p=Part(key,key,'support');rng=random.Random(seed)
 # Three thick, folded leaf masses, each mesh reusable as a complete climbing/hanging patch.
 for strand in range(3):
  x=(strand-1)*width*.30;lng=length*rng.uniform(.58,1)
  for j in range(5):
   z=-lng*(j+.15)/5;s=width*.24*(1-j/6)*rng.uniform(.7,1.2);xx=x+rng.uniform(-.6,.6)
   h=lng/5*rng.uniform(.7,1.15);yy=-.15-rng.uniform(0,.35)
   # Overlapping faceted leaf masses make scalloped edges rather than a smooth hanging ribbon.
   verts=[(xx-s,yy,z+.1),(xx-s*.4,yy+.12,z+h*.55),(xx+s,yy,z-.15),(xx+s*.25,yy+.15,z-h*.80),(xx,yy-.55,z)]
   p.poly(verts,[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],rng.choice([(4,4),(5,4),(6,4),(7,4)]),1)
 # Crown foliage spreads over parapets, not individual modeled leaves.
 for i in range(3):
  x=(i-1)*width*.30;s=width*.29
  p.poly([(x-s,.1,.1),(x-.3,-.65,.55),(x+s,-.2,.05),(x+s*.6,.65,.4),(x-s*.5,.75,.25),(x,-.05,1.0)],[(0,1,5),(1,2,5),(2,3,5),(3,4,5),(4,0,5)],(5+i%2,4),1)
 define(key,'大片藤蔓_'+key,p)
for args in [('curtain',70,9,13),('cascade',71,7,18),('carpet',72,12,6)]:vine(*args)
plan={'scope':'独立景观建筑，skyline同级；塔4仅参考，不写入塔4母版','group_limit_triangles':3000,'definition_count':len(defs),'definitions':definition_rows,'floor_height':4,'module_floors':4,'material_contract':'existing shared palette and standard roles; no emission required','status':'frozen_before_instancing'}
(OUT/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf8')
CONFIG=[('断顶高塔',[('narrow',0,0,5)]),('错层双楼',[('slim',-8,0,4),('slim',8,3,3)]),('退台楼群',[('narrow',-6,3,4),('slim',10,-3,2)]),('宽体残楼',[('wide',0,0,5)]),('三楼组合',[('slim',-14,3,3),('slim',0,-3,3),('slim',14,4,2)])]
groups=[]
def instance(key,name,pos,parent,gi,rot=0):
 mesh=defs[key];c=coll(name+'_资产包',parent);o=bpy.data.objects.new(name,mesh);c.objects.link(o);o.location=pos;o.rotation_euler.z=rot
 aid=f'ENV-OPENWORLD-LANDSCAPE04-{gi:02d}';slug=f'g{gi:02d}_{len(instance_rows):03d}'
 o['asset_id']=aid;o['component_definition']=key;o['package_id']=slug;o['version']='v001'
 info={'asset_id':aid,'package_id':slug,'slug':slug,'display_name':name,'category':'support' if key in ['curtain','cascade','carpet'] else 'architecture','version':'v001','source_blend':BLEND.relative_to(R).as_posix(),'collection':c.name,'objects':[o.name],'root_object':o.name,'component_definition':key,'local_origin':[0,0,0],'world_position':list(pos),'rotation_z':rot,'front_direction':'-Y','material_roles':H.NAMES[:3],'animation':False,'emissive':False,'dependencies':[],'collision_status':'not_required_background','exported':False,'expected_export':slug+'.glb','block_id':'open_world','asset_ledger':'scenes::资产主表::'+aid}
 instance_rows.append(info);return o
for gi,(name,buildings) in enumerate(CONFIG,1):
 g=coll(f'{gi:02d}_{name}_景观建筑组',game);groups.append(g);g['asset_id']=f'ENV-OPENWORLD-LANDSCAPE04-{gi:02d}'
 for bi,(kind,x,y,n) in enumerate(buildings):
  w,d={'narrow':(16,14),'wide':(25,14),'slim':(12,12)}[kind]
  for k in range(n):instance(kind,f'{gi:02d}组_{bi+1}栋_{k*4+1:02d}至{k*4+4:02d}层',(x,y,k*16),g,gi)
  instance('crown_'+kind,f'{gi:02d}组_{bi+1}栋_断顶',(x,y,n*16),g,gi)
  # All visible front, side and back coverage counted in total budget.
  placements=[('cascade',(x-w*.27,y-d/2-.38,n*16+5),0),('curtain',(x+w*.24,y-d/2-.40,n*16-14),0),('carpet',(x-w/2-.4,y+d*.1,n*16+3),-math.pi/2)]
  if len(buildings)==1:placements += [('curtain',(x+w/2+.4,y-d*.12,n*16-32),math.pi/2),('cascade',(x+w*.15,y+d/2+.4,n*16-1),math.pi),('carpet',(x-w*.2,y-d/2-.4,24),0)]
  for j,(key,pos,rot) in enumerate(placements):instance(key,f'{gi:02d}组_{bi+1}栋_藤蔓{j+1}',pos,g,gi,rot)
 objs=list(g.all_objects);tri=H.tri_count(objs)
 points=[o.location+o.rotation_euler.to_matrix()@v.co for o in objs for v in o.data.vertices]
 lo=[min(v[j] for v in points) for j in range(3)];hi=[max(v[j] for v in points) for j in range(3)]
 shift=Vector((-(lo[0]+hi[0])/2,-(lo[1]+hi[1])/2,-lo[2]))
 for o in objs:o.location+=shift
 group_rows.append({'asset_id':g['asset_id'],'name':name,'collection':g.name,'triangles':tri,'polygons':sum(len(o.data.polygons) for o in objs),'instances':len(objs),'buildings':len(buildings),'height':max(o.location.z+max(v.co.z for v in o.data.vertices) for o in objs)})
 print('GROUP',name,tri,flush=True)
 # Visible arrangement belongs only to overview; export scenes below keep each group at origin.
 game.children.unlink(g)
 ob=bpy.data.objects.new(name+'_总览实例',None);game.objects.link(ob);ob.instance_type='COLLECTION';ob.instance_collection=g;ob.location=((gi-3)*54,0,0)
assert all(g['triangles']<=3000 for g in group_rows),group_rows
for info in instance_rows:
 o=bpy.data.objects[info['root_object']];pts=[o.location+o.rotation_euler.to_matrix()@v.co for v in o.data.vertices]
 info['world_position']=list(o.location)
 info['bounds_min']=[min(v[j] for v in pts) for j in range(3)];info['bounds_max']=[max(v[j] for v in pts) for j in range(3)];info['dimensions']=[info['bounds_max'][j]-info['bounds_min'][j] for j in range(3)]
 folder=OUT/'component_packages'/info['category']/info['slug'];folder.mkdir(parents=True,exist_ok=True);(folder/'asset_manifest.json').write_text(json.dumps(info,ensure_ascii=False,indent=2),encoding='utf8')
sc.world=bpy.data.worlds.new('中性灰蓝天空');sc.world.use_nodes=True;sc.world.node_tree.nodes['Background'].inputs[0].default_value=(.32,.39,.48,1);sc.world.node_tree.nodes['Background'].inputs[1].default_value=.6
sun=bpy.data.lights.new('日光','SUN');sun.energy=3.5;sun.color=(1,.88,.72);sun.angle=.15;so=bpy.data.objects.new('日光',sun);display.objects.link(so);so.rotation_euler=(.45,-.5,-.6)
sc.view_settings.view_transform='AgX';sc.render.film_transparent=False
cam=camera(sc,'五组总览',(115,-250,146),(0,0,39),310,display);sc.camera=cam
for gi,g in enumerate(groups,1):
 s=bpy.data.scenes.new(f'{gi:02d}_{CONFIG[gi-1][0]}_独立原点');s.collection.children.link(g);s.world=sc.world;s.unit_settings.system='METRIC';s.view_settings.view_transform='AgX'
 lights=coll(f'90_第{gi}组验收灯光',s.collection);lights.objects.link(so)
 c=camera(s,f'第{gi}组固定镜头',(105,-180,110),(0,0,group_rows[gi-1]['height']*.48),group_rows[gi-1]['height']*1.35,lights);s.camera=c
 s['asset_id']=g['asset_id'];s['version']='v001';s['triangle_limit']=3000;s['triangles']=group_rows[gi-1]['triangles'];s['status']='Blender源完成，未导入Godot'
sc['scope']='塔4周边景观建筑；独立源文件；5组；每组含植物<=3000三角面'
sc['version']='v001';sc['block_id']='open_world'
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D':
   area.spaces.active.region_3d.view_distance=220;area.spaces.active.region_3d.view_location=(0,0,40);area.spaces.active.shading.type='MATERIAL'
ref=Path('C:/Users/ZHUANG~1/AppData/Local/Temp/codex-clipboard-f832ca31-4776-43af-82e0-3ab8a278a252.png')
if ref.exists():shutil.copy2(ref,OUT/'references/用户参考_破败高楼与藤蔓.png')
bpy.context.view_layer.update();bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
catalog={'version':'v001','source_blend':BLEND.relative_to(R).as_posix(),'source_sha256':hashlib.sha256(BLEND.read_bytes()).hexdigest(),'groups':group_rows,'definitions':definition_rows,'instances':instance_rows,'runtime_imported':False}
(OUT/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'package_tree.txt').write_text('\n'.join(f"{i['category']}/{i['slug']} : {i['display_name']}" for i in instance_rows),encoding='utf8')
top=camera(sc,'俯视结构验收',(0,-.001,300),(0,0,0),290,display)
render(sc,cam,OUT/'previews/五组景观建筑总览.png',(1900,1000),32)
render(sc,top,OUT/'previews/五组俯视结构.png',(1600,550),24)
for gi in range(1,6):
 s=bpy.data.scenes[f'{gi:02d}_{CONFIG[gi-1][0]}_独立原点'];render(s,s.camera,OUT/f'previews/{gi:02d}_{CONFIG[gi-1][0]}.png',(950,1100),24)
print('LANDSCAPE_BUILD_OK',str(BLEND),flush=True)
