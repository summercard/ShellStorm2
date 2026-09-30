"""Editable, palette-only SKYLINE eight-storey building from the supplied reference.

Run with Blender 4.5 --background --python this_file. No runtime files are touched.
"""
import bpy, math, random, json, shutil
from pathlib import Path
from collections import defaultdict
from mathutils import Vector
from mathutils.geometry import tessellate_polygon

R = Path(__file__).resolve().parents[2]
OUT = R/'assets/art/environments/open_world/source/skyline_08/v001'
BLEND = OUT/'SKYLINE大楼_8层_精细天台_v001.blend'
ASSET = 'ENV-OPENWORLD-SKYLINE08'
for d in ('previews','qa','references','component_packages'): (OUT/d).mkdir(parents=True,exist_ok=True)
reference = Path('C:/Users/ZHUANG~1/AppData/Local/Temp/codex-clipboard-ed36af7d-b327-4501-be69-596a5129d791.png')
if reference.exists(): shutil.copy2(reference, OUT/'references/用户参考_天台.png')
random.seed(8831)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.unit_settings.system='METRIC'; sc.unit_settings.scale_length=1
sc['asset_id']=ASSET; sc['floor_count']=8; sc['floor_height_m']=4.0
sc['scope']='独立参考图建筑源；8层外立面＋天台；不覆盖现有塔楼或运行时'
sc['block_id']='open_world'; sc['version']='v001'; sc['roof_z_m']=32.0
palette_path=R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
palette=bpy.data.images.load(str(palette_path)); palette.filepath=str(palette_path)
NAMES=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']
MATS=[]
for i,n in enumerate(NAMES):
 m=bpy.data.materials.new(n); m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF')
 p.inputs['Metallic'].default_value=[.82,.02,.16,0][i]
 p.inputs['Roughness'].default_value=[.29,.70,.16,.38][i]
 p.inputs['Coat Weight'].default_value=[.15,0,.65,0][i]
 uv=m.node_tree.nodes.new('ShaderNodeUVMap'); uv.uv_map='PaletteUV'
 tex=m.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=palette; tex.interpolation='Closest'
 m.node_tree.links.new(uv.outputs['UV'],tex.inputs['Vector'])
 m.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
 if i==3:
  m.node_tree.links.new(tex.outputs['Color'],p.inputs['Emission Color']); p.inputs['Emission Strength'].default_value=1.25
 MATS.append(m)

def coll(n,parent):
 c=bpy.data.collections.new(n); parent.children.link(c); return c
root=coll('SKYLINE大楼_8层_中文资产管理',sc.collection)
src=coll('01_制作组件_按独立资产包',root); src.hide_render=True; src.hide_viewport=True
game=coll('02_游戏输出_独立资产包_v001',root)
display=coll('90_展示与验收_固定灯光相机',root)
CATS={k:coll(n,game) for k,n in [('architecture','01_建筑结构'),('floor','02_地面系统'),('facilities','03_天台固定设施'),('signage','04_广告招牌'),('support','05_管线及环境支持')]}
SCATS={k:coll(n+'_制作源',src) for k,n in [('architecture','01_建筑结构'),('floor','02_地面系统'),('facilities','03_天台固定设施'),('signage','04_广告招牌'),('support','05_管线及环境支持')]}
# Only UV cells select colors. Coordinates: column, row from top, zero based.
CREAM=(9,9); LIGHT=(9,8); TILE=(8,9); TILE2=(9,7); DARK=(9,0); STEEL=(9,4)
BLUE=(5,6); BLUE2=(3,6); BLUEHI=(6,6); RED=(5,1); RUST=(5,2); GOLD=(6,3); GOLD2=(7,3)
GREEN=(6,4); TEAL=(6,5); BLACK=(9,1)
catalog=[]

def uv_mesh(mesh,colors,indices,slots):
 for mat in slots: mesh.materials.append(mat)
 uv=mesh.uv_layers.new(name='PaletteUV'); uv.active_render=True; mesh.uv_layers.active=uv
 for p,c,mi in zip(mesh.polygons,colors,indices):
  p.material_index=mi; cx=(c[0]+.5)/10; cy=1-(c[1]+.5)/10
  for j,li in enumerate(p.loop_indices):
   t=math.tau*j/len(p.loop_indices); uv.data[li].uv=(cx+.028*math.cos(t),cy+.028*math.sin(t))

class Part:
 def __init__(self,slug,name,category,origin=(0,0,0),definition=None):
  self.slug=slug; self.name=name; self.category=category; self.origin=Vector(origin)
  self.v=[]; self.f=[]; self.co=[]; self.mi=[]; self.definition=definition or slug
 def poly(self,v,f,c=CREAM,m=1):
  start=len(self.v); self.v.extend(tuple(x) for x in v)
  for face in f:
   self.f.append(tuple(start+j for j in face)); self.co.append(c); self.mi.append(m)
 def box(self,pos,size,c=CREAM,m=1,bevel=.0):
  # Explicit chamfered cuboid, editable with no unapplied modifier.
  x,y,z=pos; a,b,h=[s*.5 for s in size]
  if bevel and min(a,b)>bevel:
   t=min(bevel,h*.45)
   ring=[(-a+t,-b), (a-t,-b),(a,-b+t),(a,b-t),(a-t,b),(-a+t,b),(-a,b-t),(-a,-b+t)]
   vv=[(x+u,y+v,z+q) for q in (-h,h) for u,v in ring]
   self.poly(vv,[tuple(reversed(range(8))),tuple(range(8,16))]+[(j,(j+1)%8,(j+1)%8+8,j+8) for j in range(8)],c,m)
  else:
   self.poly([(x+i*a,y+j*b,z+k*h) for i,j,k in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]],[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],c,m)
 def rod(self,a,b,r=.06,c=STEEL,m=0,n=8):
  a,b=Vector(a),Vector(b); w=(b-a).normalized(); u=w.cross(Vector((0,0,1)))
  if u.length<.01: u=w.cross(Vector((0,1,0)))
  u.normalize(); v=w.cross(u)
  vv=[tuple(p+r*(math.cos(i*math.tau/n)*u+math.sin(i*math.tau/n)*v)) for p in (a,b) for i in range(n)]
  self.poly(vv,[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)],c,m)
 def path(self,pts,r=.06,c=STEEL,m=0,n=8):
  # Continuous mitered tube; fewer joins than overlapping cylinders.
  pts=[Vector(p) for p in pts]; vv=[]
  for i,p in enumerate(pts):
   w=(pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]).normalized()
   u=w.cross(Vector((0,0,1)))
   if u.length<.01: u=w.cross(Vector((0,1,0)))
   u.normalize(); v=w.cross(u)
   vv.extend(tuple(p+r*(math.cos(j*math.tau/n)*u+math.sin(j*math.tau/n)*v)) for j in range(n))
  ff=[tuple(reversed(range(n))),tuple(range((len(pts)-1)*n,len(pts)*n))]
  for i in range(len(pts)-1):
   for j in range(n): ff.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
  self.poly(vv,ff,c,m)
 def panel(self,coords,y,c=CREAM,m=1,thick=.04):
  # Concave irregular silhouettes extruded along Y, including torn billboard edges.
  vv=[Vector((x,0,z)) for x,z in coords]
  triangles=tessellate_polygon([vv]); lookup={tuple(v):i for i,v in enumerate(vv)}
  faces=[tuple(v if isinstance(v,int) else lookup[tuple(v)] for v in tri) for tri in triangles]
  n=len(coords); verts=[(x,y-thick/2,z) for x,z in coords]+[(x,y+thick/2,z) for x,z in coords]
  ff=[tuple(reversed(f)) for f in faces]+[tuple(i+n for i in f) for f in faces]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
  self.poly(verts,ff,c,m)
 def decal(self,center,rx,rz,plane='front',c=RUST,count=7):
  # Large angular paint chips, not noisy photographic texture.
  x,y,z=center; pts=[]
  for i in range(count):
   ang=math.tau*i/count; s=random.uniform(.60,1.0)
   if plane=='top': pts.append((x+rx*s*math.cos(ang),y+rz*s*math.sin(ang),z))
   elif plane=='side': pts.append((x,y+rx*s*math.cos(ang),z+rz*s*math.sin(ang)))
   else: pts.append((x+rx*s*math.cos(ang),y,z+rz*s*math.sin(ang)))
  self.poly(pts,[tuple(range(count))],c,1)
 def finish(self):
  gc=coll(self.name+'_资产包',CATS[self.category]); gc['package_id']='skyline_08/'+self.slug
  source_c=coll(self.name+'_制作组件',SCATS[self.category])
  objects=[]
  for emissive in (False,True):
   selected=[i for i,m in enumerate(self.mi) if (m==3)==emissive]
   if not selected: continue
   use=sorted({j for i in selected for j in self.f[i]}); mapping={old:new for new,old in enumerate(use)}
   verts=[tuple(Vector(self.v[j])-self.origin) for j in use]
   faces=[tuple(mapping[j] for j in self.f[i]) for i in selected]
   mesh=bpy.data.meshes.new(self.name+('_灯光网格' if emissive else '_主体网格'))
   mesh.from_pydata(verts,[],faces); mesh.update()
   uv_mesh(mesh,[self.co[i] for i in selected],[0 if emissive else self.mi[i] for i in selected],[MATS[3]] if emissive else MATS[:3])
   ob=bpy.data.objects.new(self.name+('_柔和自发光' if emissive else '_主体'),mesh); gc.objects.link(ob); ob.location=self.origin
   ob['asset_id']=ASSET; ob['package_id']='skyline_08/'+self.slug; ob['component_definition']=self.definition
   ob['version']='v001'; ob['front_direction']='-Y'; ob['fixed_display_attachment']=True
   so=ob.copy(); so.data=mesh.copy(); so.name=ob.name+'_制作源'; source_c.objects.link(so)
   objects.append(ob)
  mn=[min(v[j] for v in self.v) for j in range(3)]; mx=[max(v[j] for v in self.v) for j in range(3)]
  info=dict(asset_id=ASSET,package_id='skyline_08/'+self.slug,display_name=self.name,slug=self.slug,category=self.category,version='v001',source_blend=str(BLEND.relative_to(R)),collection=gc.name,source_collection=source_c.name,objects=[o.name for o in objects],root_object=objects[0].name,world_position=list(self.origin),local_origin=[0,0,0],front_direction='-Y',bounds_min=mn,bounds_max=mx,dimensions=[mx[j]-mn[j] for j in range(3)],material_roles=NAMES,animation=False,emissive=any(m==3 for m in self.mi),dependencies=[],collision_status='not_authored',exported=False,expected_export=self.slug+'.glb',fixed_display_attachment=True,component_definition=self.definition,block_id='open_world',floor_range='1F–8F＋天台',scene_design_docs=['用户参考图及8层楼要求','docs/v0.1/10.1_3D场景美术生产流程.md'],asset_ledger='scenes::资产主表::'+ASSET)
  path=OUT/'component_packages'/self.category/self.slug; path.mkdir(parents=True,exist_ok=True)
  (path/'asset_manifest.json').write_text(json.dumps(info,ensure_ascii=False,indent=2),encoding='utf8'); catalog.append(info)
  return objects

def bolts(p,points,axis=(0,-1,0),r=.06,c=GOLD):
 for pos in points: p.rod(pos,tuple(Vector(pos)+Vector(axis)*.06),r,c,0,6)

def vent_front(p,x,y,z,w=1,h=1):
 p.box((x,y,z),(w+.16,.10,h+.16),STEEL,0,.02)
 p.box((x,y-.066,z),(w,.025,h),DARK,1)
 for j in range(max(4,int(h/.13))):
  zz=z-h*.43+j*h*.86/(max(4,int(h/.13))-1)
  p.box((x,y-.09,zz),(w,.085,.055),LIGHT,0)

def rail(p,a,b,z):
 a,b=Vector(a),Vector(b); steps=max(1,math.ceil((b-a).length/2.25))
 for h in (.48,1.10): p.rod((*a,z+h),(*b,z+h),.055,GOLD,0)
 for i in range(steps+1):
  q=a+(b-a)*i/steps; p.box((*q,z+.025),(.28,.28,.07),RUST,0)
  p.rod((*q,z),(*q,z+1.17),.075,GOLD,0)
  bolts(p,[(*q,z+.07)],(0,0,1),.045,CREAM)

def fan_top(p,x,y,z,r):
 p.rod((x,y,z-.08),(x,y,z+.04),r,DARK,1,32)
 # Grille rings and sculpted fan blades underneath, all explicit geometry.
 for rr in (r*.32,r*.62,r*.90,r*1.05):
  pts=[(x+rr*math.cos(i*math.tau/32),y+rr*math.sin(i*math.tau/32),z+.09) for i in range(33)]
  p.path(pts,.022,LIGHT,0,6)
 for j in range(4):
  a=j*math.pi/2
  pts=[]
  for rr,aa in [(r*.12,a),(r*.76,a+.22),(r*.84,a+.70),(r*.22,a+.98)]: pts.append((x+rr*math.cos(aa),y+rr*math.sin(aa),z+.03))
  p.poly(pts,[(0,1,2,3)],STEEL,0)
 p.rod((x,y,z),(x,y,z+.13),r*.16,STEEL,0,12)
 for a in [i*math.pi/8 for i in range(8)]:
  p.rod((x-r*.95*math.cos(a),y-r*.95*math.sin(a),z+.1),(x+r*.95*math.cos(a),y+r*.95*math.sin(a),z+.1),.018,STEEL,0,6)

def unit(slug,name,x,y,w,d,h,fans=1):
 p=Part(slug,name,'facilities',(x,y,32),definition='hvac_dualfan' if fans==2 else 'hvac_singlefan')
 p.box((x,y,32.28),(w+.12,d+.12,.28),STEEL,0,.1)
 for dx in (-w*.37,w*.37):
  for dy in (-d*.35,d*.35): p.box((x+dx,y+dy,32.2),(.22,.22,.4),RUST,0)
 p.box((x,y,32.4+h/2),(w,d,h),CREAM,1,.11)
 p.box((x,y,32.45+h),(w+.14,d+.14,.15),LIGHT,1,.09)
 vent_front(p,x,y-d/2-.07,32.4+h/2,w*.80,h*.72)
 for xx in [x-w*.5+.12,x+w*.5-.12]:
  p.rod((xx,y-d*.5-.105,32.52),(xx,y-d*.5-.105,32.28+h),.04,RUST,0)
  bolts(p,[(xx,y-d*.5-.17,32.62),(xx,y-d*.5-.17,32.23+h)],r=.055)
 for i in range(fans): fan_top(p,x+(i-(fans-1)/2)*w*.48,y,32.55+h,min(d*.35,w/(fans*2.6)))
 for j in range(15):
  xx=x+random.uniform(-w*.46,w*.46); zz=32.4+random.uniform(.1,h-.1)
  p.decal((xx,y-d/2-.012,zz),.05+random.random()*.11,.09+random.random()*.2,c=RUST)
 p.box((x+w*.5+.06,y,32.9),(.12,.65,.5),LIGHT,1,.04)
 p.finish()

# Freeze scope and component definitions before production; instances are separate.
definitions=['repeat_floor_facade','roof_tile','roof_parapet','roof_rail','billboard_frame','torn_billboard_canvas','billboard_city_graphic','billboard_catwalk','billboard_floodlight','billboard_cabling','marquee_letter','marquee_mount','hvac_singlefan','hvac_dualfan','service_hut','hut_door','hut_ladder','hut_antenna','turbine_vent','segmented_duct','conduit_bank','utility_box','tarpaulin','oil_drum','cinder_block','weed_cluster','drain','puddle']
plan=dict(asset_id=ASSET,source_version='v001',scope='8层重复外立面和参考图精细天台',locked_existing_assets='全部现有资产；本任务新建独立目录',component_definition_count=len(definitions),definitions=definitions,dimensions_m=[32,24,32],floor_count=8,floor_height_m=4,roof_z_m=32,scale_basis='参考图美术推定；不套用主塔战斗楼层12m契约',reference_camera='CAM_天台参考',style='Fortnite形体体系：宽倒角、大色块、夸张螺栓、风格化掉漆；不使用写实PBR贴图',reference_relationships=dict(billboard='后方偏左',hut='右后方',hvac='左侧及广告牌下方',marquee='前沿SKYLINE立体字',floor='方砖、拼缝、积水、裂缝、杂草'))
(OUT/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf8')

# Eight identical office levels, including all four facades. Bottom exactly Z=0.
p=Part('floor_01','01层_窗墙楼板重复模块','architecture',(0,0,0),'repeat_floor_facade')
p.box((0,0,.18),(32,24,.36),LIGHT,1,.12)
p.box((0,0,2),(31.3,23.3,3.62),BLUE2,1)
for y in (-12,12):
 p.box((0,y,3.63),(32.2,.62,.74),CREAM,1,.08)
 p.box((0,y,.51),(32.2,.58,.30),CREAM,1,.06)
 for x in (-15.6,-10.4,-5.2,0,5.2,10.4,15.6):
  p.box((x,y,2.08),(.56,.62,3.18),CREAM,1,.055)
 for j in range(6):
  x=-13+j*5.2
  p.box((x,y*1.005,2.12),(4.57,.08,2.92),DARK,0)
  for dx in (-1.12,1.12):
   p.box((x+dx,y*1.01,2.13),(2.16,.065,2.75),BLUE if j%3 else BLUEHI,2)
   # Angular lighter reflection in glass, kept flat and opaque.
   sign=-1 if y<0 else 1
   vv=[(x+dx-1.00,y+sign*.159,.79),(x+dx+1.0,y+sign*.159,2.8),(x+dx+1.0,y+sign*.159,3.45)]
   p.poly(vv,[(0,1,2)],BLUEHI if j%3 else BLUE,2)
  for xx in (x-2.3,x,x+2.3): p.box((xx,y*1.019,2.1),(.085,.10,2.91),STEEL,0)
  for z in (.68,2.0,3.56): p.box((x,y*1.019,z),(4.64,.11,.085),STEEL,0)
  for k in range(3):
   p.decal((x+random.uniform(-2,2),y*1.027,3.6),.15+random.random()*.2,.15,c=RUST)
for x in (-16,16):
 for z,h in ((3.63,.74),(.51,.3)): p.box((x,0,z),(.62,24,h),CREAM,1,.06)
 for y in (-11.6,-5.8,0,5.8,11.6): p.box((x,y,2.08),(.62,.56,3.18),CREAM,1,.04)
 for j in range(4):
  y=-8.7+j*5.8
  p.box((x*1.006,y,2.1),(.08,5.14,2.93),DARK,0)
  for dy in (-1.28,1.28): p.box((x*1.01,y+dy,2.12),(.065,2.46,2.76),BLUE,2)
  for yy in (y-2.57,y,y+2.57): p.box((x*1.014,yy,2.1),(.1,.09,2.94),STEEL,0)
  for z in (.68,2.0,3.56): p.box((x*1.014,y,z),(.1,5.2,.085),STEEL,0)
  for k in range(3): p.decal((x*1.022,y+random.uniform(-2.3,2.3),3.64),.22,.13,'side',RUST)
first=p.finish()
# Linked mesh repetition, not stretched geometry; each level can be independently edited.
first_info=catalog[-1]
for floor in range(2,9):
 slug='floor_%02d'%floor; name='%02d层_窗墙楼板重复模块'%floor
 gc=coll(name+'_资产包',CATS['architecture']); source_c=coll(name+'_制作组件',SCATS['architecture'])
 obs=[]
 for ob in first:
  oo=ob.copy(); oo.name=name+'_主体'; oo.location.z=(floor-1)*4; gc.objects.link(oo); oo['package_id']='skyline_08/'+slug
  so=oo.copy(); so.name=oo.name+'_制作源'; source_c.objects.link(so); obs.append(oo)
 info=dict(first_info); info.update(slug=slug,display_name=name,package_id='skyline_08/'+slug,collection=gc.name,source_collection=source_c.name,objects=[o.name for o in obs],root_object=obs[0].name,world_position=[0,0,(floor-1)*4],bounds_min=[first_info['bounds_min'][0],first_info['bounds_min'][1],(floor-1)*4],bounds_max=[first_info['bounds_max'][0],first_info['bounds_max'][1],floor*4],expected_export=slug+'.glb',linked_mesh_repeat=True)
 d=OUT/'component_packages/architecture'/slug; d.mkdir(parents=True,exist_ok=True); (d/'asset_manifest.json').write_text(json.dumps(info,ensure_ascii=False,indent=2),encoding='utf8'); catalog.append(info)
print('EIGHT_FLOORS_DONE',flush=True)

# Tile system; each tile and all surface details form one package.
for row in range(12):
 for column in range(16):
  x=-15+column*2; y=-11+row*2
  p=Part('tile_%02d_%02d'%(row,column),'天台地砖_R%02d_C%02d'%(row,column),'floor',(x,y,31.8),'roof_tile')
  color=random.choice([CREAM,CREAM,LIGHT,LIGHT,TILE2])
  p.box((x,y,31.8),(1.975,1.975,.4),color,1,.02)
  if random.random()<.18:
   points=[(x-.8,y-.45,32.007),(x-.17,y-.09,32.007),(x+.08,y+.28,32.007),(x+.68,y+.55,32.007)]
   p.path(points,.014,TILE,1,4)
  if random.random()<.20:
   p.decal((x+random.uniform(-.6,.6),y+random.uniform(-.6,.6),32.008),.25,.3,'top',TILE)
  # Three puddle regions use geometry anchored to their host tile.
  water=((-7<x<-1 and -8<y<-3) or (0<x<6 and -3<y<1) or (-11<x<-7 and 0<y<3))
  if water:
   p.decal((x,y,32.019),random.uniform(.7,1.0),random.uniform(.7,.98),'top',BLUEHI,9)
   if random.random()<.65: p.box((x+.3,y-.1,32.025),(.5,.055,.01),LIGHT,2)
  if (row*7+column)%31==0:
   for k in range(5):
    q=x+random.uniform(-.55,.55); t=y+random.uniform(-.55,.55); ht=random.uniform(.17,.40)
    p.poly([(q-.03,t,32.01),(q+.08,t,32.01),(q+random.uniform(-.17,.17),t+.07,32+ht)],[(0,1,2)],GREEN,1)
  p.finish()

# Cream roof edge: large chipped paint patches over blue undercoat and orange drips.
for side in range(4):
 p=Part('parapet_%d'%side,'天台_%s_女儿墙压边'%['前','后','左','右'][side],'architecture',definition='roof_parapet')
 along=32 if side<2 else 24; count=16 if side<2 else 12
 for j in range(count):
  q=-along/2+(j+.5)*2
  x,y=(q,(-12.12 if side==0 else 12.12)) if side<2 else ((-16.12 if side==2 else 16.12),q)
  p.box((x,y,32.03),(1.975,.60,1.18) if side<2 else (.60,1.975,1.18),CREAM,1,.04)
  p.box((x,y,32.68),(2.03,.78,.16) if side<2 else (.78,2.03,.16),LIGHT,1,.04)
  for k in range(4):
   c=BLUE if k==0 else RUST
   if side<2: p.decal((x+random.uniform(-.8,.8),y+(-.305 if side==0 else .305),32.06+random.uniform(-.5,.5)),.20,.26,'front',c)
   else: p.decal((x+(-.305 if side==2 else .305),y+random.uniform(-.8,.8),32.06+random.uniform(-.5,.5)),.21,.28,'side',c)
  p.decal((x,y,32.766),.25,.23,'top',RUST)
 p.finish()
for side,(a,b) in enumerate([((-15.8,-11.8),(15.8,-11.8)),((15.8,-11.8),(15.8,11.8)),((15.8,11.8),(-15.8,11.8)),((-15.8,11.8),(-15.8,-11.8))]):
 p=Part('rail_%d'%side,'天台_%s_黄色安全护栏'%['前','右','后','左'][side],'architecture',definition='roof_rail'); rail(p,a,b,32.78); p.finish()

# Billboard steel frame and exposed holes. Lower edge at 36, top at 44.4.
Y=8.65; X=-4.0; left=-15.4; right=7.4; z0=36.0; z1=44.4
p=Part('billboard_frame','巨型广告牌_橙色钢架与基础','signage',(X,Y,32),'billboard_frame')
for x in (-13.2,-5.0,4.8):
 p.box((x,Y+.3,32.42),(1.6,1.6,.84),CREAM,1,.12)
 p.box((x,Y+.3,32.92),(1.12,1.10,.20),RUST,0)
 bolts(p,[(x+dx,Y+.3+dy,33.04) for dx in (-.42,.42) for dy in (-.4,.4)],(0,0,1),.10,STEEL)
 for xx in (x-.17,x+.17): p.box((xx,Y+.45,36.32),(.13,.48,6.8),RUST,0,.03)
 p.box((x,Y+.18,36.32),(.6,.13,6.8),RUST,0,.03)
 for z in (33.5,35,36.5,38): bolts(p,[(x,Y-.03,z)],r=.1,c=CREAM)
for z in (33.65,35.6,37.5):
 p.box((X,Y+.35,z),(22.8,.34,.27),RUST,0,.04)
for xa,xb in [(-13.2,-5),(-5,4.8)]:
 p.rod((xa,Y+.4,33),(xb,Y+.4,36),.14,RUST,0)
 p.rod((xa,Y+.4,36),(xb,Y+.4,33),.14,RUST,0)
for z in (z0,z1): p.box((X,Y,z),(23.28,.32,.25),RUST,0,.05)
for x in (left,right): p.box((x,Y,40.2),(.27,.34,8.6),RUST,0,.04)
for x in [left+i*3.8 for i in range(7)]:
 p.box((x,Y+.13,40.2),(.16,.15,8.2),STEEL,0)
 for z in (37.1,39.3,41.5,43.7): bolts(p,[(x,Y-.2,z)],r=.07,c=CREAM)
for z in (37.5,40,42.8): p.box((X,Y+.15,z),(22.8,.14,.14),RUST,0)
p.finish()

# Torn sign skin deliberately omits three open holes. No decal pretending to be a hole.
p=Part('billboard_canvas','巨型广告牌_不规则破损画布','signage',(X,Y,36),'torn_billboard_canvas')
# Left torn edge opens toward the side, lower center opens from bottom, upper right opens from side.
outline=[(left,z0),(left,37.0),(left+.7,37.3),(left+1.1,38),(left+2.7,38.6),(left+3.3,39.2),(left+2.4,40.0),(left+1.0,40.6),(left+.7,41.4),(left,41.6),(left,z1),(right,z1),(right,43.0),(right-.75,42.6),(right-1.8,41.9),(right-1.25,41),(right-.6,40.3),(right,40.1),(right,z0),(X+2,z0),(X+1.65,36.7),(X+.9,37.6),(X-.1,37.9),(X-1.3,37.1),(X-1.8,z0)]
p.panel(outline,Y-.17,CREAM,1,.08)
# Back-of-tear darker shadows and cream rims respect silhouette.
for xx,zz in [(left+.8,41.4),(left+2.5,40),(left+3.1,39.15),(X+.6,37.55),(right-1.55,41.9)]:
 p.decal((xx,Y-.222,zz),.18,.35,c=LIGHT)
for x in [left+i*3.8 for i in range(1,6)]:
 p.rod((x,Y-.231,36.1),(x,Y-.231,44.28),.012,TILE,1,4)
for j in range(100):
 x=random.uniform(left+.1,right-.1); z=random.uniform(z0+.15,z1-.15)
 # Ray parity against the torn outline keeps paint wear on the actual canvas.
 def inside(xx,zz):
  hit=False
  for a,b in zip(outline,outline[1:]+outline[:1]):
   if (a[1]>zz)!=(b[1]>zz) and xx<(b[0]-a[0])*(zz-a[1])/(b[1]-a[1])+a[0]: hit=not hit
  return hit
 if inside(x,z) and inside(x+.25,z+.3) and inside(x-.25,z-.3):
  p.decal((x,Y-.228,z),random.uniform(.04,.14),random.uniform(.1,.29),c=RUST,count=5)
for j in range(40):
 x=random.uniform(left+.15,right-.15)
 p.decal((x,Y-.233,44.2),.06,random.uniform(.13,.38),c=RUST,count=5)
p.finish()

p=Part('billboard_graphic','巨型广告牌_城市剪影与落日几何图案','signage',(X,Y,36),'billboard_city_graphic')
# Geometric sun, broken by horizontal cream cutouts.
sunx=1.2; sunz=40.9; radius=2.95
pts=[(sunx+radius*math.cos(i*math.tau/64),sunz+radius*math.sin(i*math.tau/64)) for i in range(64)]
p.panel(pts,Y-.239,RED,1,.012)
for j in range(5): p.box((sunx-.55,Y-.259,sunz-1.7+j*.6),(5.35,.025,.12+.035*(j%2)),CREAM,1)
# Skyline starts above bottom tear; city blocks have stepped rooftops and antennae.
for j in range(26):
 x=left+2+j*.71; h=random.uniform(.65,2.25)
 if j in (9,15): h=4.3 if j==15 else 3.1
 if j==17: h=5.7
 base=36.95 if -6.1<x<-2.1 else 36.2
 if x<left+3.5: base=38.1
 if x>right-1.7: h=min(h,2.2)
 w=random.uniform(.50,.79)
 p.box((x,Y-.276,base+h/2),(w,.018,h),BLUE,1)
 if j in (9,15,17):
  p.box((x,Y-.276,base+h+.24),(w*.57,.018,.48),BLUE,1)
  p.rod((x,Y-.28,base+h+.46),(x,Y-.28,base+h+.95),.026,BLUE,1,4)
 for k in range(int(h/.35)):
  if random.random()<.45: p.box((x+.08,Y-.292,base+.18+k*.35),(.055,.012,.09),CREAM,1)
for j in range(48):
 x=random.uniform(left+4,right-1.6); z=random.uniform(36.8,38.3)
 if not (-6.3<x<-2.0 and z<38): p.decal((x,Y-.303,z),.035,.10,c=CREAM,count=4)
p.finish()

for i,(xa,xb) in enumerate([(left-.4,left+5.6),(right-4.5,right+.8)]):
 p=Part('billboard_catwalk_%d'%i,'广告牌_%s_检修平台'%['左','右'][i],'signage',definition='billboard_catwalk')
 p.box(((xa+xb)/2,Y-1.07,36.08),(xb-xa,1.40,.18),STEEL,0)
 # Visible perforated grating formed by separate bars.
 for j in range(math.ceil((xb-xa)/.14)):
  x=xa+j*.14; p.box((x,Y-1.07,36.2),(.036,1.36,.035),GOLD,0)
 for yy in (Y-1.73,Y-.40): p.box(((xa+xb)/2,yy,36.12),(xb-xa,.10,.20),GOLD,0)
 rail(p,(xa,Y-1.8),(xb,Y-1.8),36.23)
 rail(p,(xa,Y-1.8),(xa,Y-.4),36.23); rail(p,(xb,Y-1.8),(xb,Y-.4),36.23)
 for x in (xa+.35,xb-.35): p.rod((x,Y-.4,35.3),(x,Y-1.7,36),.09,RUST,0)
 p.finish()

for i,x in enumerate((-14.3,-9.2,-4.0,1.1,6.3)):
 p=Part('billboard_light_%d'%i,'广告牌_顶部投光灯_%02d'%i,'signage',(x,Y,44.4),'billboard_floodlight')
 p.box((x,Y,44.63),(.8,.55,.18),RUST,0,.04)
 p.path([(x,Y,44.7),(x,Y-.25,45.45),(x,Y-1.1,45.45)],.08,BLACK,0)
 p.box((x,Y-1.1,45.38),(1.03,.62,.60),STEEL,0,.1)
 p.box((x,Y-1.425,45.34),(.82,.028,.35),CREAM,3)
 bolts(p,[(x-.38,Y-1.46,45.5),(x+.38,Y-1.46,45.5)],r=.06)
 p.finish()
p=Part('billboard_cables','广告牌_垂挂电缆与配电箱','support',definition='billboard_cabling')
for x in (-14,-12.4,4.8,6.5):
 for k in range(2):
  points=[(x+math.sin(t*math.pi)*.2,Y-.6-k*.12,36.1-1.8*math.sin(t*math.pi)) for t in [j/24 for j in range(25)]]
  points=[(xx+(.7*t),yy,zz) for t,(xx,yy,zz) in zip([j/24 for j in range(25)],points)]
  p.path(points,.038,BLACK,1,6)
p.box((-13.0,Y-1.84,36.7),(.78,.24,1.0),CREAM,1,.06)
p.panel([(-13.26,36.55),(-12.73,36.55),(-13,37.03)],Y-1.977,GOLD,1,.02)
p.panel([(-13.02,36.61),(-12.88,36.80),(-13.01,36.80),(-12.98,36.94),(-13.12,36.73),(-13.01,36.73)],Y-1.996,BLACK,1,.01)
p.finish()
print('BILLBOARD_DONE',flush=True)

# Service hut, blue lower paint, panel seams, real door frame and roof details.
hx=9.7; hy=4.0; hw=8.0; hd=7.0; hz=32; hh=4.5
p=Part('hut_shell','天台机房_双色墙壳屋檐','architecture',(hx,hy,32),'service_hut')
p.box((hx,hy,34.25),(hw,hd,hh),CREAM,1,.10)
for y in (hy-hd/2-.012,hy+hd/2+.012):
 p.box((hx,y,32.88),(hw,.025,1.76),BLUE,1)
 for x in (hx-2,hx,hx+2): p.rod((x,y,32.1),(x,y,36.4),.012,TILE,1,4)
 for j in range(35): p.decal((random.uniform(hx-hw/2+.15,hx+hw/2-.15),y-.015 if y<hy else y+.015,random.uniform(32.2,36.4)),.08+random.random()*.18,.12+random.random()*.28,c=RUST)
for x in (hx-hw/2-.012,hx+hw/2+.012):
 p.box((x,hy,32.88),(.025,hd,1.76),BLUE,1)
 for j in range(22): p.decal((x+.017,random.uniform(hy-hd/2+.15,hy+hd/2-.15),random.uniform(32.2,36.4)),.15,.24,'side',RUST)
p.box((hx,hy,36.57),(8.65,7.65,.42),CREAM,1,.1)
for i in range(4):
 for j in range(4):
  p.box((hx-3.21+i*2.14,hy-2.8+j*1.86,36.82),(2.12,1.84,.10),CREAM if (i+j)%3 else LIGHT,1,.015)
for j in range(24):
 x=random.uniform(hx-4.15,hx+4.15); p.decal((x,hy-3.833,36.59),.13,.25,c=RUST)
vent_front(p,hx-2.6,hy-hd/2-.07,34.38,1.25,1.24)
vent_front(p,hx+2.7,hy-hd/2-.07,34.38,1.1,1.24)
p.finish()
p=Part('hut_door','天台机房_蓝色铁门与门灯','facilities',(hx+.2,hy-hd/2,32),'hut_door')
dx=hx+.15; dy=hy-hd/2-.10
p.box((dx,dy,33.62),(1.96,.10,3.24),STEEL,0,.04)
p.box((dx,dy-.065,33.54),(1.65,.07,2.97),BLUE,1,.035)
for z in (32.43,34.73): p.box((dx-.78,dy-.13,z),(.15,.16,.36),LIGHT,0,.02)
p.box((dx+.57,dy-.17,33.51),(.10,.14,.38),STEEL,0,.025)
p.box((dx,dy-.13,34.25),(1.15,.035,.06),LIGHT,1)
for j in range(15): p.decal((random.uniform(dx-.65,dx+.65),dy-.113,random.uniform(32.15,34.85)),.07,.18,c=RUST)
p.box((dx,dy-.05,35.45),(.85,.42,.27),STEEL,0,.07)
p.box((dx,dy-.28,35.41),(.68,.04,.15),CREAM,3)
p.box((dx,dy-.48,32.09),(2.16,.90,.18),LIGHT,1,.04)
p.finish()
p=Part('hut_ladder','天台机房_橙色爬梯与屋顶弯钩','facilities',(hx+hw/2+.34,hy-1.5,32),'hut_ladder')
lx=hx+hw/2+.38; ly=hy-1.5
for yy in (ly-.58,ly+.58):
 p.path([(lx,yy,32.08),(lx,yy,36.65),(lx-.04,yy,37.0),(lx-.27,yy,37.1),(lx-.62,yy,37.1),(lx-.82,yy,36.9)],.075,RUST,0,10)
 for z in (32.3,34,35.7): p.rod((lx,yy,z),(lx-.38,yy,z),.06,STEEL,0)
for j in range(12): p.rod((lx,ly-.58,32.24+j*.375),(lx,ly+.58,32.24+j*.375),.065,GOLD,0)
p.finish()

# Curved profile turbine ventilator with actual flutes.
p=Part('hut_turbine','机房屋顶_涡轮排气帽','facilities',(hx+.2,hy+1.0,36.88),'turbine_vent')
vx=hx+.2; vy=hy+1.0; vz=36.88
p.rod((vx,vy,vz),(vx,vy,vz+.38),.50,STEEL,0,24)
profile=[(.65,.27),(.85,.43),(.87,.72),(.77,.98),(.49,1.13),(.12,1.18)]
verts=[(vx+(r+(.035 if j%2 else 0))*math.cos(j*math.tau/48+k*.09),vy+(r+(.035 if j%2 else 0))*math.sin(j*math.tau/48+k*.09),vz+z) for k,(r,z) in enumerate(profile) for j in range(48)]
for k in range(len(profile)-1):
 for j in range(48):
  p.poly([verts[k*48+j],verts[k*48+(j+1)%48],verts[(k+1)*48+(j+1)%48],verts[(k+1)*48+j]],[(0,1,2,3)],LIGHT if j%2 else STEEL,0)
p.rod((vx,vy,vz+1.10),(vx,vy,vz+1.20),.22,LIGHT,0,24); p.finish()

# Dish is a concave mesh rather than a solid round plate, pole and coax cable attached.
p=Part('hut_antenna','机房屋顶_卫星天线与立杆','facilities',(hx+2.7,hy+1.4,36.88),'hut_antenna')
ax=hx+2.7; ay=hy+1.4; az=36.88
p.box((ax,ay,az+.07),(.95,.95,.14),STEEL,0,.05)
p.rod((ax,ay,az),(ax,ay,az+4.45),.07,STEEL,0)
for x in (-.6,.6): p.rod((ax+x,ay-.4,az+.1),(ax,ay,az+1.8),.045,BLACK,0)
for h in (2.1,3.45,4.0): p.rod((ax-.38,ay,az+h),(ax+.33,ay,az+h),.038,GOLD,0)
cx=ax; cy=ay-.27; cz=az+2.80; rr=.82
verts=[(cx,cy+.20,cz)]
for k in range(1,6):
 r=rr*k/5
 for j in range(40): verts.append((cx+r*math.cos(j*math.tau/40),cy+.20-.32*(r/rr)**2,cz+r*math.sin(j*math.tau/40)))
faces=[(0,1+j,1+(j+1)%40) for j in range(40)]
for k in range(4):
 for j in range(40): faces.append((1+k*40+j,1+k*40+(j+1)%40,1+(k+1)*40+(j+1)%40,1+(k+1)*40+j))
p.poly(verts,faces,CREAM,1)
p.path([(cx+rr*math.cos(j*math.tau/40),cy-.13,cz+rr*math.sin(j*math.tau/40)) for j in range(41)],.026,LIGHT,0,6)
p.rod((cx,cy-.12,cz-rr*.85),(cx,cy-.88,cz),.032,STEEL,0)
p.rod((cx,cy-.88,cz),(cx,cy-.68,cz+.07),.10,BLACK,1)
p.path([(ax,ay,az+2.7),(ax+.18,ay-.05,az+1.7),(ax+.1,ay+.16,az+.16),(hx+hw/2,hy+1,36.85)],.027,BLACK,1)
p.finish()

# Cluster of machines matching the roof reference, clear central walkway.
unit('hvac_main','中央双风扇空调',-3.6,4.1,5.5,2.7,2.7,2)
unit('hvac_left','左侧双风扇机组',-9.0,1.1,3.9,2.4,2.2,2)
unit('hvac_front','左前单风扇冷凝器',-10.0,-5.8,2.4,2.0,2.9,1)
unit('hvac_back','机房左侧冷凝器',3.0,4.0,2.6,2.7,2.65,1)
unit('hvac_small','中央附属空调',-.3,2.65,1.6,1.1,1.15,1)

# Ducts, elbows and segment clamps. Bent duct with octagonal section.
for slug,name,points,width,height in [
 ('duct_front','前侧分节低风管',[(-12,-7,32.6),(-7,-7,32.6),(-7,-8.8,32.6)],1.2,1.1),
 ('duct_center','中央上弯通风管',[(.7,5.1,33.05),(2.4,5.1,33.05),(2.4,5.1,34.7),(.4,5.1,34.7)],1.2,1.0),
 ('duct_back','后侧串联通风管',[(-10,6.2,32.75),(-6.5,6.2,32.75),(-6.5,6.2,33.8)],1.1,1.05)]:
 p=Part(slug,name,'facilities',points[0],'segmented_duct')
 for a,b in zip(points,points[1:]):
  a,b=Vector(a),Vector(b); d=b-a; length=d.length; n=max(1,math.ceil(length/1.2))
  # Axis-aligned bevel segments, actual elbow silhouette retained.
  for i in range(n):
   center=a+d*(i+.5)/n; axis=max(range(3),key=lambda j:abs(d[j]))
   size=[width,width,height]; size[axis]=length/n-.035
   p.box(center,size,LIGHT,0,.12)
   pos=a+d*(i+.07)/n; flange=[width+.08,width+.08,height+.08]; flange[axis]=.065
   p.box(pos,flange,STEEL,0,.08)
 p.finish()

p=Part('conduit_bank','天台_铜管走线与黄色设备护架','support',definition='conduit_bank')
for k in range(3):
 y=-9.45+k*.22
 p.path([(-13.5,y,32.25),(-5,y,32.25),(-4.7,y,32.53),(9.5,y,32.53),(9.9,y+.4,32.53),(9.9,-1.0,32.53)],.05,RUST if k%2 else STEEL,0)
 for x in (-12,-8,-4,0,4,8): p.box((x,y,32.29),(.16,.36,.08),BLACK,1)
for xa,xb,y,z in [(-6.6,-.3,2.4,32.4),(-11.2,-6.8,-.4,32.2)]:
 for h in (.12,.52): p.rod((xa,y,z+h),(xb,y,z+h),.06,GOLD,0)
 for x in (xa,xb): p.rod((x,y,32),(x,y,z+.6),.07,GOLD,0)
for x in (hx-3.4,hx+2.4):
 p.path([(x,hy-3.65,32.1),(x,hy-3.65,36.95),(x,hy-3.4,37.05),(x,hy-2.5,37.05)],.075,RUST,0)
 for z in (32.7,34.2,35.7): p.box((x,hy-3.72,z),(.23,.15,.10),STEEL,0)
p.finish()

for i,(x,y,z) in enumerate([(hx-3.4,hy-3.72,33.2),(hx+3.1,hy-3.75,33.5),(-13.8,-5.7,32.5)]):
 p=Part('utility_box_%d'%i,'天台_电控箱_%02d'%i,'facilities',(x,y,z),'utility_box')
 p.box((x,y,z),(.64,.34,.80),LIGHT,1,.055)
 p.box((x,y-.183,z),(.49,.035,.65),CREAM,1,.02)
 p.rod((x+.19,y-.22,z),(x+.19,y-.29,z),.047,STEEL,0,6)
 p.box((x,y-.213,z+.20),(.13,.014,.09),GOLD,3)
 p.finish()

# Reference drum, folded green cover and blocks are explicitly fixed display props.
p=Part('oil_drum','天台_橙色油桶固定陈设','facilities',(-6.35,.25,32),'oil_drum')
x=-6.35; y=.25
p.rod((x,y,32.03),(x,y,33.70),.56,RUST,1,20)
for z in (32.10,32.60,33.22,33.68):
 pts=[(x+.575*math.cos(i*math.tau/24),y+.575*math.sin(i*math.tau/24),z) for i in range(25)]
 p.path(pts,.04,RED,0)
p.rod((x+.23,y,33.70),(x+.23,y,33.75),.09,STEEL,0,12); p.finish()
p=Part('tarpaulin','天台_绿色折叠篷布覆盖设备','facilities',(-4.8,-.15,32),'tarpaulin')
x=-4.8; y=-.15
# A draped silhouette with peaked corners and large triangular folds.
vv=[(x-1.0,y-.9,32.08),(x+.9,y-.9,32.08),(x+1.1,y+.8,32.08),(x-.9,y+.9,32.08),(x-.65,y-.55,33.25),(x+.6,y-.48,33.0),(x+.7,y+.5,33.18),(x-.6,y+.57,33.32),(x,y,33.38)]
ff=[(0,1,5),(0,5,4),(1,2,6),(1,6,5),(2,3,7),(2,7,6),(3,0,4),(3,4,7),(4,5,8),(5,6,8),(6,7,8),(7,4,8)]
for j,f in enumerate(ff): p.poly([vv[i] for i in f],[tuple(range(len(f)))],GREEN if j%3 else (7,4),1)
for i in range(3): p.box((x-.8+i*.75,y-1.05,32.12),(.69,.27,.24),RUST,1,.02)
p.finish()
for i,(x,y) in enumerate([(-6.0,-1.3),(-4,-1.7),(5.5,.0),(12,-2),(14,-.8)]):
 p=Part('block_%d'%i,'天台_空心砌块_%02d'%i,'facilities',(x,y,32),'cinder_block')
 for xx in (x-.35,x,x+.35): p.box((xx,y,32.16),(.09,.38,.32),LIGHT,1,.018)
 for yy in (y-.19,y+.19): p.box((x,yy,32.16),(.8,.085,.32),CREAM,1,.018)
 p.finish()
# One smaller mushroom exhaust by the front duct.
p=Part('front_vent','天台_前沿蘑菇排风帽','facilities',(-4.8,-8.3,32),'turbine_vent')
x=-4.8; y=-8.3
p.rod((x,y,32.1),(x,y,33.35),.38,STEEL,0,20)
p.rod((x,y,33.18),(x,y,33.63),.60,LIGHT,0,24)
p.decal((x,y,33.64),.42,.39,'top',RUST,9); p.finish()
print('ROOF_EQUIPMENT_DONE',flush=True)

# SKYLINE marquee: seven real extruded glyphs, ivory returns, red face and bulbs.
font=bpy.data.fonts.load('C:/Windows/Fonts/ariblk.ttf')
letters='SKYLINE'; letter_widths=[]; glyphs=[]
for char in letters:
 cu=bpy.data.curves.new('字形_'+char,'FONT'); cu.body=char; cu.font=font; cu.size=3.9; cu.resolution_u=10; cu.extrude=.19; cu.bevel_depth=.025; cu.bevel_resolution=1
 ob=bpy.data.objects.new('文字源_'+char,cu); display.objects.link(ob)
 bpy.context.view_layer.update(); glyphs.append(ob); letter_widths.append(ob.dimensions.x)
total=sum(letter_widths)+.30*6; factor=28/total; current=-14
for i,(char,ob,width) in enumerate(zip(letters,glyphs,letter_widths)):
 p=Part('letter_'+char.lower()+'_%d'%i,'SKYLINE_立体灯泡字_'+char,'signage',(current,-12.7,31.9),'marquee_letter')
 ob.rotation_euler=(math.pi/2,0,0); ob.scale=(factor,factor,factor); ob.location=(current,-12.83,31.78+(0.05 if i%2 else 0))
 bpy.context.view_layer.update()
 evaluated=ob.evaluated_get(bpy.context.evaluated_depsgraph_get()); mesh=bpy.data.meshes.new_from_object(evaluated)
 vertices=[tuple(ob.matrix_world@v.co) for v in mesh.vertices]
 # Front face is nearest viewer (-Y); side wall remains cream, not flat red lettering.
 for face in mesh.polygons:
  vv=[vertices[j] for j in face.vertices]; yy=sum(v[1] for v in vv)/len(vv)
  p.poly(vv,[tuple(range(len(vv)))],RED if yy<-12.94 else CREAM,1)
 # Outline sampling uses face boundary edges on the front plane.
 fronty=min(v[1] for v in vertices)
 edges=[]
 for edge in mesh.edges:
  a,b=[Vector(vertices[j]) for j in edge.vertices]
  if abs(a.y-fronty)<.035 and abs(b.y-fronty)<.035 and (a-b).length>.035: edges.append((a,b))
 # Bulbs at contour vertices, spaced down the glyph outline. Dedup prevents clumps.
 candidates=[]
 for a,b in edges:
  for t in [0,.5]:
   q=a+(b-a)*t
   if all((q-u).length>.40 for u in candidates): candidates.append(q)
 # Move each bulb slightly inward toward the letter center.
 center=Vector((current+width*factor/2,fronty,33.1))
 for q in candidates:
  q=q*.90+center*.10; q.y=fronty-.06
  p.rod((q.x,q.y+.02,q.z),(q.x,q.y-.04,q.z),.112,GOLD,0,12)
  p.rod((q.x,q.y-.04,q.z),(q.x,q.y-.11,q.z),.075,GOLD2,3,12)
 # Stylized paint scratches checked against actual letter front triangle surfaces.
 # The color of select front faces creates broad chipped facets without texture.
 frontfaces=[j for j,mi in enumerate(p.mi) if mi==1 and p.co[j]==RED]
 for j in frontfaces:
  if random.random()<.11: p.co[j]=CREAM
 p.finish()
 # Preserve editable font outlines in the source collection, hidden by default.
 for c in list(ob.users_collection): c.objects.unlink(ob)
 SCATS['signage'].objects.link(ob); ob.name='可编辑字体源_SKYLINE_'+char
 ob['purpose']='字形编辑原件；输出使用显式网格和PaletteUV'
 bpy.data.meshes.remove(mesh)
 current+=width*factor+.30*factor
p=Part('marquee_mount','SKYLINE招牌_钢轨支架与线缆','signage',definition='marquee_mount')
for z in (31.65,33.05,34.48):
 p.box((0,-12.68,z),(29,.12,.12),STEEL,0,.03)
for x in (-13,-9,-5,-1,3,7,11,14):
 p.box((x,-12.53,32.65),(.20,.20,3.10),RUST,0,.02)
 p.rod((x,-11.9,32.2),(x,-12.52,33.15),.07,STEEL,0)
 p.box((x,-12.51,31.22),(.44,.13,.40),RUST,0,.03)
 bolts(p,[(x,-12.61,31.23)],r=.09,c=CREAM)
for x in (10.5,13,14):
 p.path([(x,-12.75,32.0),(x+.15,-12.84,30.4),(x+.65,-12.84,29.8),(x+1.05,-12.84,30.2),(x+1.05,-12.8,32.3)],.035,BLACK,1)
p.finish()
print('MARQUEE_DONE',flush=True)

# All package manifests, catalog and mirrored directory tree.
meta=dict(asset_id=ASSET,version='v001',source_blend=str(BLEND.relative_to(R)),source_status='Blender源已完成',runtime_status='未导出；未接入',floor_count=8,unit='meter',block_id='open_world',floor_range='1F–8F＋天台',design_scope=plan['scope'],scene_design_docs=plan['reference_relationships'],asset_ledger='scenes::资产主表::'+ASSET,packages=catalog,package_count=len(catalog),component_definition_count=len(definitions),shared_palette=str(palette_path.relative_to(R)),color_policy='只用项目公共色盘，4角色材质，PaletteUV逐面有面积UV岛',coordinates='Blender Z-up；正面-Y；地面Z=0；屋顶完成面Z=32',scale_basis=plan['scale_basis'])
(OUT/'catalog.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'component_packages/tree.txt').write_text('\n'.join(c['category']+'/'+c['slug']+' — '+c['display_name'] for c in catalog),encoding='utf8')

# Fixed presentation rigs. Background is a world, no unrelated display geometry.
sc.render.engine='CYCLES'; sc.cycles.samples=32; sc.cycles.use_denoising=True
sc.render.image_settings.file_format='PNG'; sc.render.film_transparent=False
sc.view_settings.view_transform='AgX'; sc.view_settings.look='AgX - Medium High Contrast'; sc.view_settings.exposure=1.2
world=bpy.data.worlds.new('蓝色展示环境'); sc.world=world; world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.18,.30,.48,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.65
def light(n,kind,pos,power,color,size=10):
 data=bpy.data.lights.new(n,kind); data.energy=power; data.color=color
 ob=bpy.data.objects.new(n,data); display.objects.link(ob); ob.location=pos
 ob.rotation_euler=(Vector((0,0,33))-Vector(pos)).to_track_quat('-Z','Y').to_euler()
 if kind=='AREA': data.shape='DISK'; data.size=size
 if kind=='SUN': data.angle=.16
 return ob
light('KEY_暖色大面柔光','SUN',(-40,-30,75),3.3,(1,.86,.69))
light('FILL_正面冷柔光','AREA',(-15,-32,51),4200,(.67,.83,1),22)
light('RIM_顶部暖光','AREA',(15,20,58),5500,(1,.83,.60),18)
def camera(n,pos,target,scale,res):
 data=bpy.data.cameras.new(n); data.type='ORTHO'; data.ortho_scale=scale; data.clip_end=500
 ob=bpy.data.objects.new(n,data); display.objects.link(ob); ob.location=pos
 ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
 ob['resolution_x']=res[0]; ob['resolution_y']=res[1]; return ob
cameras=[
 (camera('CAM_天台参考',(-46,-66,64),(0,1,36),45,(1600,1280)),'01_天台参考镜头.png'),
 (camera('CAM_8层完整楼体',(-65,-85,70),(0,0,21),66,(1400,1700)),'02_8层完整楼体.png'),
 (camera('CAM_天台俯视',(0,-.001,90),(0,0,32),39,(1500,1200)),'03_天台俯视结构.png'),
 (camera('CAM_设备与机房',(34,-36,56),(3,3,34.5),28,(1500,1150)),'04_机房与设备近景.png'),
 (camera('CAM_广告牌细节',(-32,-32,51),(-4,7.5,40),31,(1600,1050)),'05_破损广告牌近景.png'),
 (camera('CAM_背面完整性',(55,70,63),(0,0,22),66,(1300,1550)),'06_背面完整楼体.png')]
sc.camera=cameras[0][0]; sc.render.resolution_x=1600; sc.render.resolution_y=1280; sc.render.resolution_percentage=100
# Open the file at the supplied-image camera; source hidden/output visible.
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D':
   area.spaces.active.region_3d.view_perspective='CAMERA'
   area.spaces.active.shading.type='MATERIAL'
   area.spaces.active.clip_end=500
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print('SOURCE_SAVED',str(BLEND),flush=True)
# Prefer CUDA/OptiX if a supported compute device is exposed; fall back to CPU.
try:
 prefs=bpy.context.preferences.addons['cycles'].preferences
 prefs.compute_device_type='OPTIX'; prefs.get_devices()
 gpu=False
 for device in prefs.devices:
  device.use=device.type!='CPU'; gpu=gpu or device.use
 if gpu: sc.cycles.device='GPU'
 print('RENDER_GPU',gpu,flush=True)
except Exception as exc: print('GPU_FALLBACK',str(exc),flush=True)
for cam,filename in cameras:
 sc.camera=cam; sc.render.resolution_x=cam['resolution_x']; sc.render.resolution_y=cam['resolution_y']; sc.render.filepath=str(OUT/'previews'/filename)
 bpy.ops.render.render(write_still=True); print('RENDER_DONE',filename,flush=True)
sc.camera=cameras[0][0]; sc.render.resolution_x=1600; sc.render.resolution_y=1280
sc.render.filepath=str(OUT/'previews/01_天台参考镜头.png')
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print('SKYLINE_SOURCE_COMPLETE',len(catalog),flush=True)
