"""Two explicit levels of detail from one frozen courtyard placement plan."""
import bpy,sys,math,json,random,hashlib,shutil
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent))
import tower04_court_common as H
R=H.R;refined='--refined' in sys.argv;VER='v002' if refined else 'v001';OUT=R/'assets/art/environments/open_world/source/tower_04_2'/VER
low='--far' in sys.argv;lod='far' if low else 'near'
BLEND=OUT/(f'塔4-2_远景组件_{VER}.blend' if low else f'塔4-2_近景庭院_{VER}.blend')
assert not BLEND.exists(),'New version only'
for d in ('qa','previews','references','component_packages'):(OUT/d).mkdir(parents=True,exist_ok=True)
old=R/'assets/art/environments/open_world/source/tower_04/v009';cat=json.loads((old/'catalog.json').read_text(encoding='utf8'))
bpy.ops.wm.read_factory_settings(use_empty=True)
with bpy.data.libraries.load(str(R/cat['source_blend']),link=False) as (a,b):b.materials=list(H.NAMES)
H.setup_materials();sc=bpy.context.scene;sc.name='塔4-2_'+lod;sc.unit_settings.system='METRIC'
ASSET='ENV-OPENWORLD-TOWER04-2';sc['asset_id']=ASSET;sc['version']=VER;sc['block_id']='open_world';sc['lod']=lod
root=H.coll('塔4-2_独立庭院_'+lod,sc.collection);library=H.coll('01_组件定义_隐藏',root);library.hide_render=True;library.hide_viewport=True
layout=H.coll('02_游戏输出_分区实例',root);display=H.coll('90_验收灯光相机',sc.collection)
zones={n:H.coll(n,layout) for n in ['A_圆楼柱下花园','B_中央积水庭院','C_南缘低层连廊','D_东侧林荫步道','E_柱下铺地']}
defs={};instances=[]
def define(slug,name,family,fn):
 p=H.Part(slug,name,'court',definition=family);fn(p);m,origin,dims=H.mesh_of(p)
 assert max(dims[:2])<=8.01,(slug,dims)
 c=H.coll(name+'_定义',library);o=bpy.data.objects.new(name+'_母件',m);c.objects.link(o);o.location=origin
 o['asset_id']=ASSET;o['component_definition']=slug;o['lod']=lod
 defs[slug]=dict(slug=slug,display_name=name,family=family,collection=c.name,mesh=m.name,origin=list(origin),dimensions=dims,triangles=H.tri_count([o]),material_roles=H.NAMES)
 return p
def place(slug,x,y,z=0,angle=0,zone='B_中央积水庭院'):
 d=defs[slug];i=len(instances);o=bpy.data.objects.new(f'{d["display_name"]}_实例{i:04d}',bpy.data.meshes[d['mesh']]);zones[zone].objects.link(o)
 ori=Vector(d['origin']);c,s=math.cos(angle),math.sin(angle);o.location=(x+ori.x*c-ori.y*s,y+ori.x*s+ori.y*c,z+ori.z);o.rotation_euler.z=angle
 o['asset_id']=ASSET;o['component_definition']=slug;o['instance_id']=f'T42-{i:04d}';o['zone']=zone;o['lod']=lod
 instances.append(dict(instance_id=o['instance_id'],definition=slug,object=o.name,position=[x,y,z],rotation_z=angle,zone=zone))

def paving(p,v):
 rng=random.Random(100+v)
 if low:
  p.box((0,0,-.12),(6,6,.24),H.LIGHT if refined else [H.TILE,H.LIGHT,H.TILE2][v],1)
  if v==2:p.poly([(-2,-1,.003),(2,-2,.003),(2.4,1,.003),(-1,2,.003)],[(0,1,2,3)],(9,4),2)
  return
 for ix in range(4):
  for iy in range(4):
   x=-2.25+ix*1.5;y=-2.25+iy*1.5
   if v==2 and (ix,iy) in [(1,2),(2,2)]:
    p.box((x,y,-.15),(1.46,1.46,.10),(3,4),1)
    H.foliage(p,(x,y,-.07),.58,.4,ix*20+iy)
    continue
   p.box((x,y,-.10),(1.465,1.465,.20),rng.choice([H.LIGHT]*9+[H.TILE]) if refined else rng.choice([H.TILE,H.LIGHT,H.TILE2]),1,.018)
   if v and rng.random()<.65:
    a=(x-.60,y-.2,.003);b=(x+.03,y+.16,.003);c=(x+.67,y+.32,.003)
    p.poly([a,b,c,(c[0],c[1]+.025,.003),(b[0],b[1]+.025,.003),(a[0],a[1]+.025,.003)],[(0,1,4,5),(1,2,3,4)],H.DARK,1)
   if v==2 and rng.random()<.35:
    p.poly([(x-.5,y-.4,.005),(x+.48,y-.25,.005),(x+.28,y+.42,.005),(x-.25,y+.35,.005)],[(0,1,2,3)],(9,4),2)
for i in range(3):define(f'paving_{i}',f'庭院铺地6米_{["整洁残留","开裂","返野积水"][i]}','paving',lambda p,v=i:paving(p,v))
def soil(p):
 p.box((0,0,-.13),(6,6,.26),(3,4) if refined else (4,2),1)
 if refined:
  for i,(x,y) in enumerate([(-2,-2),(0,-1.7),(2,-1.4),(-1.6,.2),(.5,.4),(2,1.9),(-1.3,2)]):
   H.foliage(p,(x,y,.0),.85,.35,i+490,low)
define('soil','种植土壤6米','soil',soil)
def water(p):
 p.box((0,0,-.28),(6,6,.22),H.DARK,1)
 p.poly([(-3,-3,-.10),(3,-3,-.10),(3,3,-.10),(-3,3,-.10)],[(0,1,2,3)],(9,4),2)
 if not low and not refined:
  for x,y in [(-1.8,.4),(.8,-1.4),(1.5,1.8)]:p.box((x,y,-.085),(.65,.45,.12),H.TILE2,1,.04)
define('water','浅积水池6米','water',water)
def curb(p):
 p.box((0,0,.14),(6,.38,.28),H.LIGHT,1,.025)
 if not low:
  for x in [-2,-1,0,1,2]:p.box((x,0,.285),(.016,.36,.009),H.TILE2,1)
define('curb','池岸压顶6米','curb',curb)
def drain(p):
 p.box((0,0,-.05),(6,.35,.10),H.DARK,1)
 for i in range(10 if low else 40):p.box((-2.9+i*5.8/(9 if low else 39),0,.005),(.06,.32,.035),H.STEEL,0)
define('drain','排水槽6米','drain',drain)
def planter(p):
 for y in (-.47,.47):p.box((0,y,.32),(6,.16,.64),H.LIGHT,1,.025)
 p.box((0,0,.45),(6,.78,.12),(4,2),1)
 for x in [-2.1,0,2.1]:H.foliage(p,(x,0,.49),.75,.8,int(x*30+100),low)
define('planter','带状返野花池6米','planter',planter)
define('wall','低层店铺实墙6米','wall',lambda p:p.box((0,0,1.75),(6,.36,3.5),H.TILE,1,.035))
def window(p):
 for x in (-3,3):p.box((x,0,1.75),(.35,.48,3.5),H.LIGHT,1,.03)
 for z in (.25,3.25):p.box((0,0,z),(6,.48,.5),H.LIGHT,1,.03)
 for x in (-2,-1,0,1,2):p.box((x,0,1.75),(.045,.10,2.5),H.STEEL,0)
 p.box((0,0,1.65),(5.7,.1,.045),H.STEEL,0)
 for i in range(6):
  if i%3==0:continue
  x=-2.9+i
  p.poly([(x,-.005,.55),(x+.88,-.005,.55),(x+.88,-.005,1.5 if i%2 else 2.85)],[(0,1,2)],(9,4),2)
define('window','破损玻璃店面6米','window',window)
def roof(p):
 p.box((0,0,3.62),(6,6,.25),H.TILE,1,.025)
 for y in (-2.85,2.85):p.box((0,y,3.90),(6,.26,.45),H.LIGHT,1,.025)
define('roof','低层屋顶6米','roof',roof)
define('column','廊架立柱','column',lambda p:(p.box((0,0,.14),(.75,.75,.28),H.TILE,1,.03),p.box((0,0,1.8),(.32,.32,3.6),H.LIGHT,1,.035)))
def pergola(p):
 for y in (-2.8,2.8):p.box((0,y,3.5),(6,.20,.32),H.LIGHT,1,.02)
 for i in range(7):p.box((-3+i,0,3.70),(.14,6,.16),H.STEEL,0)
 if not low:
  for x in (-2.8,2.8):
   for y in (-2.8,2.8):p.box((x,y,3.48),(.34,.34,.08),H.RUST,0)
define('pergola','透空廊架顶6米','pergola',pergola)
for i in range(3):define(f'tree_{i}',f'庭院乔木_{i+1}','tree',lambda p,v=i:H.tree(p,v,low))
for i in range(3):define(f'bush_{i}',f'地被灌木_{i+1}','bush',lambda p,v=i:H.foliage(p,(0,0,0),[1.2,1.6,2][v],[.8,1.2,1.5][v],800+v,low))
def vine(p,v):
 for i in range(4):
  x=-1.4+i*.9;pts=[(x+math.sin(j+v)*.13,0,3.8-j*.45) for j in range(8)]
  p.path(pts,.023,(4,2),1,5)
  for j,q in enumerate(pts[1:]):H.foliage(p,(q[0],0,q[2]),.32,.3,i*24+j+v,True if low else False)
define('vine_0','廊檐垂挂藤蔓_A','vine',lambda p:vine(p,0))
define('vine_1','廊檐垂挂藤蔓_B','vine',lambda p:vine(p,1))
def bench(p):
 for x in (-1.1,1.1):p.box((x,0,.22),(.25,.68,.44),H.TILE,1,.03)
 for j in range(5):p.box((0,-.3+j*.15,.49),(3,.12,.10),(6,2),1,.015)
define('bench','固定花园木坐凳','bench',bench)
def pot(p):
 p.rod((0,0,.06),(0,0,.60),.42,H.TILE2,1,10 if low else 20);H.foliage(p,(0,0,.6),.65,.8,850,low)
define('pot','固定展示种植盆','pot',pot)

# Frozen architectural grid. The pool and gardens replace paving; no overlapping terrain.
for ix in range(-13,13):
 for iy in range(-11,5):
  x=ix*6+3;y=iy*6+3
  pond=(-18<=x<6 and -48<=y<-30)
  garden=((-72<x<-42 and -54<y<-24) or (24<x<66 and -54<y<-24) or (-72<x<-36 and -18<y<0))
  if refined:garden=garden or (y>6 and x<-30) or (x<-72 or x>72) or (-30<x<18 and -66<y<-57)
  zone='A_圆楼柱下花园' if x<-36 else ('D_东侧林荫步道' if x>24 else ('E_柱下铺地' if y>0 else 'B_中央积水庭院'))
  slug='water' if pond else 'soil' if garden else f'paving_{(ix*7+iy*11)%3}'
  turn=(random.Random(ix*912+iy).randrange(4)*math.pi/2) if refined and slug.startswith('paving') else 0
  place(slug,x,y,angle=turn,zone=zone)
  if refined and garden:
   rng=random.Random(ix*177+iy)
   if (ix+iy)%2==0:place(f'tree_{(ix+iy)%3}',x+rng.uniform(-.6,.6),y+rng.uniform(-.6,.6),angle=rng.random()*math.tau,zone=zone)
   for k in range(2):place(f'bush_{(ix+k)%3}',x+rng.uniform(-1.4,1.4),y+rng.uniform(-1.4,1.4),angle=rng.random()*math.tau,zone=zone)
for y in (-48,-30):
 for x in (-15,-9,-3,3):place('curb',x,y)
for x in (-18,6):
 for y in (-45,-39,-33):place('curb',x,y,angle=math.pi/2)
for x in range(-69,72,6):
 place('drain',x,-24);place('drain',x,-54)
# Two consistent six-metre shop courts frame the foreground; central entrance remains open.
for start in (-66,24):
 for k in range(6):
  x=start+k*6
  place('roof',x,-63,zone='C_南缘低层连廊');place('window',x,-60,zone='C_南缘低层连廊');place('wall',x,-66,zone='C_南缘低层连廊')
  if k in (0,5):place('wall',x+(-3 if k==0 else 3),-63,angle=math.pi/2,zone='C_南缘低层连廊')
  if k%2==0 or refined:place('vine_0',x,-59.7,zone='C_南缘低层连廊')
  if refined:
   place('bush_1',x,-62.8,3.75,zone='C_南缘低层连廊')
   place('vine_1',x,-65.7,zone='C_南缘低层连廊')
 for k in range(5):place('pergola',start+k*6,-54,zone='C_南缘低层连廊')
 for k in range(6):
  for y in (-57,-51):place('column',start-3+k*6,y,zone='C_南缘低层连廊')
# Garden aisles are deliberately aligned; trees stay within planting parcels.
for x in (-66,-54,30,42,54):
 for j,y in enumerate((-45,-33)):
  zone='A_圆楼柱下花园' if x<0 else 'D_东侧林荫步道'
  place(f'tree_{(int(x)+j)%3}',x,y,zone=zone)
  for dx,dy in [(-2.4,1.7),(2.1,-1.9),(.3,2.8)]:place(f'bush_{(int(x)+j)%3}',x+dx,y+dy,zone=zone)
for x,y in [(-69,-12),(-57,-12),(-45,-12),(-69,0),(-45,0),(15,-39),(15,-51),(69,-39),(69,-15)]:
 place('tree_0',x,y,zone='A_圆楼柱下花园' if x<0 else 'D_东侧林荫步道')
for x in (-66,-54,-42,24,36,48,60):
 place('planter',x,-21);place('bench',x,-19.3)
for x in (-30,18):
 for y in (-51,-39,-27):place('bench',x,y,angle=math.pi/2);place('pot',x,y+2.2)

assert len(defs)<=40
manifest=dict(asset_id=ASSET,version=VER,lod=lod,source_blend=BLEND.relative_to(R).as_posix(),definitions=list(defs.values()),instances=instances,definition_count=len(defs),instance_count=len(instances),visible_triangles=H.tri_count(layout.all_objects),bounds=[[-78,-66,-.5],[78,30,10]],scene_design_docs=['docs/v0.1/design/tower04_ground_court.md'],asset_ledger='scenes::资产主表::'+ASSET,block_id='open_world',floor_range='地面庭院Z=0',runtime_verified=False)
for d in defs.values():
 f=OUT/'component_packages'/d['slug'];f.mkdir(parents=True,exist_ok=True)
 (f/f'{lod}_manifest.json').write_text(json.dumps(dict(d,asset_id=ASSET,version=VER,lod=lod,source_blend=manifest['source_blend'],collision_status='not_authored',exported=False),ensure_ascii=False,indent=2),encoding='utf8')
# Golden late-afternoon display lighting; four asset materials remain unchanged.
world=bpy.data.worlds.new('庭院暮色天空');world.use_nodes=True;world.node_tree.nodes['Background'].inputs['Color'].default_value=(.44,.53,.67,1);world.node_tree.nodes['Background'].inputs['Strength'].default_value=.45;sc.world=world
ld=bpy.data.lights.new('暮光暖阳','SUN');ld.energy=2.5;ld.color=(1,.75,.46);ld.angle=.13;sun=bpy.data.objects.new(ld.name,ld);display.objects.link(sun);sun.rotation_euler=(.52,-.63,-.65)
ld=bpy.data.lights.new('天空柔光','AREA');ld.energy=2400;ld.shape='DISK';ld.size=80;obj=bpy.data.objects.new(ld.name,ld);display.objects.link(obj);obj.location=(-10,-30,65)
sc.view_settings.view_transform='AgX'
cameras=[H.camera(sc,'CAM_庭院全景',(113,-138,109),(-5,-22,0),190,display),H.camera(sc,'CAM_庭院俯视',(-1,-18,150),(0,-18,0),166,display),H.camera(sc,'CAM_积水与廊架',(-24,-7,17),(-2,-45,1.5),57,display),H.camera(sc,'CAM_柱下花园',(-35,-12,17),(-55,-37,2),48,display)]
sc.camera=cameras[0];bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
manifest['source_sha256']=hashlib.sha256(BLEND.read_bytes()).hexdigest();(OUT/f'{lod}_catalog.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
print('COURT_SAVED',lod,len(defs),len(instances),manifest['visible_triangles'],flush=True)
if not low:
 for cam in cameras:H.render(sc,cam,OUT/'previews'/(cam.name[4:]+'.png'))
