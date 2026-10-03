"""Editable, palette-only logistics building from the supplied reference.

Run with Blender 4.5 --background --python this_file. No runtime files are touched.
"""
import bpy, math, random, json, shutil
from pathlib import Path
from collections import defaultdict
from mathutils import Vector
from mathutils.geometry import tessellate_polygon

R = Path(__file__).resolve().parents[2]
OUT = R/'assets/art/environments/open_world/source/logistics_07/v005'
BLEND = OUT/'env_logistics_07_source_v005.blend'
ASSET = 'ENV-OPENWORLD-LOGISTICS07'
for d in ('previews','qa','references','component_packages'): (OUT/d).mkdir(parents=True,exist_ok=True)
reference = OUT.parent/'v004/references/用户参考_物流楼.png'
if reference.exists(): shutil.copy2(reference, OUT/'references/用户参考_物流楼.png')
random.seed(8831)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.unit_settings.system='METRIC'; sc.unit_settings.scale_length=1
sc['asset_id']=ASSET; sc['floor_count']=3; sc['floor_height_m']=6.0
sc['scope']='独立参考图建筑源；物流楼外观＋屋顶＋装卸区；不覆盖现有塔楼或运行时'
sc['block_id']='open_world'; sc['version']='v005'; sc['roof_z_m']=18.0
palette_path=R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
palette=bpy.data.images.load(str(palette_path)); palette.filepath=str(palette_path)
NAMES=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']
MATS=[]
for i,n in enumerate(NAMES):
 m=bpy.data.materials.new(n); m.use_nodes=True
 p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
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
root=coll('SKYLINE物流楼07_中文资产管理',sc.collection)
src=coll('01_制作组件_按独立资产包',root); src.hide_render=True; src.hide_viewport=True
game=coll('02_游戏输出_独立资产包_v005',root)
display=coll('90_展示与验收_固定灯光相机',root)
CATS={k:coll(n,game) for k,n in [('architecture','01_建筑结构'),('floor','02_地面系统'),('facilities','03_天台固定设施'),('signage','04_广告招牌'),('support','05_管线及环境支持')]}
SCATS={k:coll(n+'_制作源',src) for k,n in [('architecture','01_建筑结构'),('floor','02_地面系统'),('facilities','03_天台固定设施'),('signage','04_广告招牌'),('support','05_管线及环境支持')]}
# Only UV cells select colors. Coordinates: column, row from top, zero based.
CREAM=(9,9); LIGHT=(9,8); TILE=(8,9); TILE2=(9,7); DARK=(9,0); STEEL=(9,4)
BLUE=(5,6); BLUE2=(3,6); BLUEHI=(6,6); RED=(5,1); RUST=(5,2); GOLD=(6,0); GOLD2=(8,3)
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
  gc=coll(self.name+'_资产包',CATS[self.category]); gc['package_id']='logistics_07/'+self.slug
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
   ob['asset_id']=ASSET; ob['package_id']='logistics_07/'+self.slug; ob['component_definition']=self.definition
   ob['version']='v005'; ob['front_direction']='-Y'; ob['fixed_display_attachment']=True
   so=ob.copy(); so.data=mesh.copy(); so.name=ob.name+'_制作源'; source_c.objects.link(so)
   objects.append(ob)
  mn=[min(v[j] for v in self.v) for j in range(3)]; mx=[max(v[j] for v in self.v) for j in range(3)]
  info=dict(asset_id=ASSET,package_id='logistics_07/'+self.slug,display_name=self.name,slug=self.slug,category=self.category,version='v005',source_blend=str(BLEND.relative_to(R)),collection=gc.name,source_collection=source_c.name,objects=[o.name for o in objects],root_object=objects[0].name,world_position=list(self.origin),local_origin=[0,0,0],front_direction='-Y',bounds_min=mn,bounds_max=mx,dimensions=[mx[j]-mn[j] for j in range(3)],material_roles=NAMES,animation=False,emissive=any(m==3 for m in self.mi),dependencies=[],collision_status='not_authored',exported=False,expected_export=self.slug+'.glb',fixed_display_attachment=True,component_definition=self.definition,block_id='open_world',floor_range='三段立面＋屋顶',scene_design_docs=['用户参考图；独立外观资产，尺寸为美术尺度，不建立玩法层高','docs/v0.1/10.1_3D场景美术生产流程.md'],asset_ledger='scenes::资产主表::'+ASSET)
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
 for h in (.48,1.10): p.rod((*a,z+h),(*b,z+h),.055,GOLD,1)
 for i in range(steps+1):
  q=a+(b-a)*i/steps; p.box((*q,z+.025),(.28,.28,.07),RUST,0)
  p.rod((*q,z),(*q,z+1.17),.075,GOLD,1)
  bolts(p,[(*q,z+.07)],(0,0,1),.045,CREAM)

def fan_top(p,x,y,z,r):
 # Three rings keep the fan silhouette; 16 angular segments and a four-sided
 # tube avoid dense geometry that is subpixel at the building's game scale.
 p.rod((x,y,z-.08),(x,y,z+.04),r,DARK,1,16)
 for rr in (r*.32,r*.68,r*1.02):
  pts=[(x+rr*math.cos(i*math.tau/16),y+rr*math.sin(i*math.tau/16),z+.09) for i in range(17)]
  p.path(pts,.022,LIGHT,0,4)
 for j in range(4):
  a=j*math.pi/2
  pts=[]
  for rr,aa in [(r*.12,a),(r*.76,a+.22),(r*.84,a+.70),(r*.22,a+.98)]: pts.append((x+rr*math.cos(aa),y+rr*math.sin(aa),z+.03))
  p.poly(pts,[(0,1,2,3)],STEEL,0)
 p.rod((x,y,z),(x,y,z+.13),r*.16,STEEL,0,12)
 for a in [i*math.pi/6 for i in range(6)]:
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

# Frozen authoring scope: a new exterior asset, without gameplay/storey contracts.
definitions=['wall_panel','corner_pier','floor_band','roof_tile','paving_tile','roof_rail','service_catwalk','rollup_dock','office_entry','entry_stairs','billboard','brand_sign','roof_hvac','wall_ac','utility_cabinet','duct','ladder','telecom_mast','conduit','bollard','planter','cargo_stack','truck_display','forklift_display','roof_hatch']
plan=dict(asset_id=ASSET,version='v005',block_id='open_world',floor_range='三段立面及屋顶',design_scope='参考图07号物流楼的完整外观、屋顶、广告及装卸展示区',dimensions_m=[28,20,18],scale_basis='独立外观资产美术尺度；参考图无尺寸，28×20×18m为明确制作假设，非可进入关卡或12m墙体模块',component_definition_count=len(definitions),definitions=definitions,locked_existing_assets='所有已有资产与运行时场景保持不动',reference_camera='CAM_参考全景',scene_design_docs=['docs/v0.1/10_资产与内容规范.md','docs/v0.1/10.1_3D场景美术生产流程.md'],asset_ledger='scenes::资产主表::'+ASSET,reference_relationships={'front':'左侧办公室和竖幅海报；右侧01/02/03三联装卸门','roof':'六台空调、服务柜、通信塔、橙色栏杆、方形风道','attachments':'货车、叉车、托盘箱、花池独立包，均为静态展示'})
(OUT/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf8')

def text_geo(p,body,pos,size,c=DARK,m=1,rot=(math.pi/2,0,0),align='CENTER'):
 curve=bpy.data.curves.new('可编辑标识_'+body,'FONT'); curve.body=body; curve.size=size; curve.align_x=align; curve.extrude=.004; curve.resolution_u=3
 font=Path('C:/Windows/Fonts/arialbd.ttf')
 if font.exists(): curve.font=bpy.data.fonts.load(str(font),check_existing=True)
 ob=bpy.data.objects.new('可编辑字形_'+body,curve); display.objects.link(ob); ob.location=pos; ob.rotation_euler=rot
 bpy.context.view_layer.update(); mesh=bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
 p.poly([tuple(ob.matrix_world@v.co) for v in mesh.vertices],[tuple(f.vertices) for f in mesh.polygons],c,m)
 bpy.data.meshes.remove(mesh)
 display.objects.unlink(ob); SCATS['signage'].objects.link(ob)

def rotate_part(p,angle):
 ca,sa=math.cos(angle),math.sin(angle)
 p.v=[(ca*x-sa*y,sa*x+ca*y,z) for x,y,z in p.v]
 p.origin=Vector((ca*p.origin.x-sa*p.origin.y,sa*p.origin.x+ca*p.origin.y,p.origin.z))

def lamp(p,x,y,z,w=1.2):
 p.box((x,y,z),(w+.24,.36,.23),DARK,0,.05)
 p.box((x,y-.20,z-.075),(w,.09,.075),GOLD2,3,.025)
 p.rod((x,y+.2,z+.22),(x,y-.05,z),.06,STEEL,0)

# Wall panels retain joints, corner trims, fasteners and sparse weathering.
for side in ('front','back','left','right'):
 width=28 if side in ('front','back') else 20
 for level in range(3):
  for col in range(7 if width==28 else 5):
   x=-width/2+2+col*4; z=3+level*6
   if side=='front' and level==0: continue  # Actual entry and loading door apertures.
   y=-10 if width==28 else -14
   p=Part(f'wall_{side}_{level}_{col}',f'墙板_{side}_{level}_{col}','architecture',(x,y,z-3),'wall_panel')
   p.box((x,y,z),(3.96,.32,5.94),CREAM,1,.035)
   for zz in (z-2,z,z+2): p.box((x,y-.167,zz),(3.9,.018,.025),LIGHT,0)
   bolts(p,[(xx,y-.19,zz) for xx in (x-1.78,x+1.78) for zz in (z-2.75,z-.05,z+2.75)],r=.042,c=STEEL)
   for k in range(12):
    xx=x+random.uniform(-1.8,1.8); zz=z+random.uniform(-2.5,2.5)
    p.decal((xx,y-.169,zz),random.uniform(.015,.075),random.uniform(.07,.4),c=TILE2)
   for k in range(3):
    xx=x+random.uniform(-1.8,1.8); zz=z+random.uniform(-2.8,2.8)
    p.decal((xx,y-.175,zz),.028,.15,c=RUST)
   if side=='back': rotate_part(p,math.pi)
   if side=='left': rotate_part(p,-math.pi/2)
   if side=='right': rotate_part(p,math.pi/2)
   p.finish()
for z in (.28,6.2,17.85):
 p=Part('band_'+str(z).replace('.','_'),'楼层钢檐带_'+str(z),'architecture',(0,0,z-.2),'floor_band')
 for y in (-10.15,10.15):
  p.box((0,y,z),(28.7,.48,.4),LIGHT,0,.045); p.box((0,y+(-.25 if y<0 else .25),z-.02),(28.6,.045,.12),GOLD,0)
  for x in range(-14,15,2): bolts(p,[(x,y+(-.27 if y<0 else .27),z+.1)],r=.055,c=STEEL)
 for x in (-14.15,14.15):
  p.box((x,0,z),(.48,20.4,.4),LIGHT,0,.045); p.box((x+(-.25 if x<0 else .25),0,z-.02),(.045,20.3,.12),GOLD,0)
 p.finish()
for x in (-14,14):
 for y in (-10,10):
  p=Part(f'pier_{x}_{y}','转角铆接立柱','architecture',(x,y,0),'corner_pier')
  p.box((x,y,9),(.52,.52,18),LIGHT,0,.04)
  for z in range(1,18):
   bolts(p,[(x,y-.28,z)],r=.07,c=STEEL)
  p.finish()

# Roof surface: independent host tile packages, no common floor-detail mesh.
for row in range(10):
 for col in range(14):
  x=-13+col*2; y=-9+row*2
  p=Part(f'roof_tile_{row:02}_{col:02}',f'屋顶地砖_R{row:02}_C{col:02}','floor',(x,y,17.68),'roof_tile')
  p.box((x,y,17.83),(1.978,1.978,.30),TILE if (row+col)%5 else (9,7),1,.025)
  for xx in (x-.85,x+.85): bolts(p,[(xx,y-.85,17.99)],axis=(0,0,1),r=.022,c=STEEL)
  if row in (1,7): p.box((x,y,17.987),(1.90,.075,.012),GOLD,1)
  if col in (3,10): p.box((x,y,17.988),(.075,1.90,.012),GOLD,1)
  if random.random()<.22: p.decal((x+.3,y+.2,17.99),.33,.11,'top',TILE2)
  p.finish()
for i,(a,b) in enumerate([((-14,-10),(14,-10)),((14,-10),(14,10)),((14,10),(-14,10)),((-14,10),(-14,-10))]):
 p=Part(f'roof_rail_{i}','屋顶橙色安全栏杆_'+str(i),'architecture',(*a,18),'roof_rail'); rail(p,a,b,18); p.finish()

# Front door wall is built around true apertures, not a solid wall behind doors.
for x,w in [(-13.6,.8),(-6.7,.7),(-.25,.65),(6.65,.65),(13.65,.7)]:
 p=Part('dock_pier_'+str(x),'装卸口承重门柱','architecture',(x,-10,0),'corner_pier'); p.box((x,-10,3),(w,.65,6),CREAM,1,.04); p.finish()
for j,x in enumerate((-3.5,3.25,10)):
 p=Part(f'dock_{j+1:02}',f'{j+1:02}号装卸卷帘门','facilities',(x,-10,0),'rollup_dock')
 p.box((x,-10,5.3),(6.1,.45,1.8),CREAM,1,.05)
 p.box((x,-9.90,2.25),(5.35,.18,4.45),DARK,1)
 # First shutter raised to reveal dark loading aperture, remaining two shut.
 lower=3.5 if j==0 else .4
 for zz in [lower+i*.19 for i in range(int((4.4-lower)/.19)+1)]: p.box((x,-10.11,zz),(4.95,.14,.16),STEEL,0,.02)
 for dx in (-2.66,2.66):
  p.box((x+dx,-10.3,2.5),(.28,.38,4.8),DARK,0,.05)
  p.box((x+dx,-10.52,2.3),(.12,.12,4.1),GOLD,0,.03)
  p.box((x+dx,-10.67,.95),(.33,.26,1.6),GOLD,0,.065)
 p.box((x,-10.38,4.62),(5.8,.6,.44),STEEL,0,.06)
 lamp(p,x,-10.69,4.48,2.1)
 text_geo(p,f'{j+1:02}',(x,-10.245,5.03),1.0,DARK)
 if j:
  for dx in (-1.3,0,1.3):
   p.box((x+dx,-10.22,2.2),(.78,.11,.42),DARK,0,.07); p.box((x+dx,-10.29,2.2),(.62,.035,.29),GOLD2,2,.05)
  p.box((x,-10.25,.57),(4.95,.09,.30),GOLD,1)
  for dx in [i*.43-2.3 for i in range(11)]: p.panel([(x+dx-.11,.43),(x+dx+.05,.43),(x+dx+.30,.71),(x+dx+.14,.71)],-10.31,DARK,1,.008)
 lamp(p,x,-10.5,6.05,1.15)
 p.finish()

# Recessed office entry, transom logo and stair landing.
p=Part('office_entry','办公入口_玻璃双门与招牌','facilities',(-10.4,-10,0),'office_entry')
p.box((-10.4,-9.9,2.85),(6.2,.35,5.6),CREAM,1,.08)
p.box((-10.4,-10.12,2.5),(4.7,.18,3.5),DARK,0,.03)
for x in (-11.55,-9.25):
 p.box((x,-10.235,2.45),(2.14,.08,3.24),BLUE,2,.04)
 p.box((x,-10.29,1.45),(2.10,.07,.55),GOLD,0)
 for dx in (-1.08,1.08): p.box((x+dx,-10.31,2.45),(.07,.10,3.35),GOLD,0)
 for zz in (.78,3.4,4.12): p.box((x,-10.32,zz),(2.2,.11,.08),GOLD,0)
 p.rod((x+(.9 if x<-10.4 else -.9),-10.45,2),(x+(.9 if x<-10.4 else -.9),-10.45,2.75),.045,CREAM,0)
text_geo(p,'SKYLINE',(-10.4,-10.13,4.85),.61,DARK)
text_geo(p,'LOGISTICS',(-10.4,-10.13,4.50),.27,DARK)
for x in (-13.1,-7.65): lamp(p,x,-10.5,4.1,.55)
p.finish()
p=Part('entry_stairs','办公室入口_四级踏步平台','architecture',(-10.4,-11.75,0),'entry_stairs')
for i in range(4): p.box((-10.4,-12.65+i*.45,.15+i*.17),(5.3,.90,.30+i*.34),LIGHT,1,.035)
for x in (-13.13,-7.67): rail(p,(x,-13),(x,-10.55),.64)
p.finish()

# Large illustrated poster, all geometry and palette colors (no private texture).
p=Part('billboard','BUILT TO DELIVER_完整竖幅广告','signage',(-10.3,-10.5,6.4),'billboard')
p.box((-10.3,-10.51,11.9),(6.7,.28,10.65),DARK,0,.045)
p.box((-10.3,-10.68,11.9),(6.35,.04,10.3),GOLD,1)
p.box((-10.3,-10.72,9.55),(6.29,.035,5.58),DARK,1)
# sun disc parallel to front facade
p.rod((-10.6,-10.74,14.18),(-10.6,-10.77,14.18),2.05,GOLD2,1,64)
for k in range(9):
 x=-13.3+k*.72; h=[1.4,2.1,1.7,3.4,2.5,3.0,1.6,2.0,1.3][k]
 p.box((x,-10.80,12.2+h/2),(.65,.015,h),(9,2) if k%3 else DARK,1)
 if k in (3,5): p.rod((x,-10.81,12.2+h),(x,-10.81,12.6+h),.027,DARK,1)
p.panel([(-13.44,11.63),(-7.15,13),(-7.15,12.72),(-13.44,11.37)],-10.84,RED,1,.008)
text_geo(p,'BUILT',(-13.12,-10.88,10.25),1.62,CREAM,align='LEFT')
text_geo(p,'TO DELIVER',(-13.12,-10.88,8.88),1.01,CREAM,align='LEFT')
p.panel([(-13.44,7.68),(-7.16,8.68),(-7.16,8.49),(-13.44,7.49)],-10.90,GOLD,1,.008)
text_geo(p,'SKYLINE LOGISTICS',(-10.3,-10.89,7.21),.31,CREAM)
for x in (-13.65,-6.95): p.box((x,-10.83,11.9),(.13,.16,10.9),STEEL,0,.035)
for z in (6.52,17.25): p.box((-10.3,-10.83,z),(6.88,.16,.14),STEEL,0,.035)
for x in (-12.55,-10.3,-8.05): lamp(p,x,-10.98,17.18,.9)
for z in range(7,17): bolts(p,[(-13.65,-10.94,z),(-6.95,-10.94,z)],r=.055)
p.finish()

p=Part('brand_sign','SKYLINE物流品牌_立面几何字标','signage',(4,-10.2,8),'brand_sign')
for dx,h in [(-1.5,1.6),(-.5,2.6),(.5,3.6),(1.5,1.7)]:
 p.panel([(4+dx-.43,11.15),(4+dx+.43,11.15),(4+dx+.43,11.15+h-.5),(4+dx-.43,11.15+h)],-10.19,DARK,1,.018)
text_geo(p,'SKYLINE',(4,-10.21,9.83),1.2,DARK)
text_geo(p,'LOGISTICS',(4,-10.21,8.84),.78,DARK)
p.finish()
p=Part('side_number','侧墙07库区编号','signage',(-14.2,-6,14),'brand_sign')
text_geo(p,'07',(-8,-14.2,14.4),1.75,DARK); rotate_part(p,-math.pi/2); p.finish()

# HVAC appliances, visibly equipped with top fans, front fans, louvers and conduit.
def hvac(slug,x,y,z,w=3,d=2.6,h=2.8):
 p=Part(slug,'空调机组_'+slug,'facilities',(x,y,z),'roof_hvac' if z>17 else 'wall_ac')
 for dx in (-w*.36,w*.36): p.box((x+dx,y,z+.19),(.18,d+.12,.37),DARK,0,.025)
 p.box((x,y,z+.38+h/2),(w,d,h),CREAM,1,.11)
 p.box((x,y,z+.44+h),(w+.12,d+.12,.12),LIGHT,0,.045)
 fan_top(p,x,y,z+.55+h,min(w,d)*.34)
 # Front circular fan in XZ plane, reused and rotated from the top fan geometry.
 start=len(p.v); fan_top(p,0,0,0,min(w,h)*.32)
 for i in range(start,len(p.v)):
  xx,yy,zz=p.v[i]; p.v[i]=(x+xx,y-d/2-.03-zz,z+.4+h*.54+yy)
 for xx in (x-w*.5+.14,x+w*.5-.14):
  p.box((xx,y-d*.5-.055,z+.4+h*.5),(.07,.04,h-.14),STEEL,0)
  bolts(p,[(xx,y-d*.5-.10,z+.57),(xx,y-d*.5-.10,z+h+.16)],r=.042)
 for zz in [z+.5+j*.14 for j in range(int(h/.14)-1)]: p.box((x-w*.5-.01,y,zz),(.025,d*.63,.06),DARK,0)
 p.box((x+w*.29,y-d*.5-.07,z+.6),(.38,.06,.24),DARK,2,.025)
 for k in range(9): p.decal((x+random.uniform(-w*.4,w*.4),y-d*.5-.012,z+.5+random.random()*h*.8),.035,.11,c=RUST)
 p.finish()
for i,(x,y) in enumerate([(-10,4.9),(-10,8),(-.9,-4.8),(6,-5.3),(9.6,-5.3),(8.8,7.1)]): hvac(f'roof_hvac_{i:02}',x,y,18,2.8,2.65,2.7)
for i,(x,z) in enumerate([(-5.55,7.8),(-3.65,7.8),(13.1,12.0),(13.1,7.65),(-6.0,1.25)]): hvac(f'wall_ac_{i:02}',x,-10.6,z,1.25,.70,1.1)

for k,(x,y,z,w,d,h) in enumerate([(-3.4,6.7,18,4.2,2.5,2.7),(13.2,-11,0,1.3,.9,2.2),(-6.4,-12,0,1.25,1,1.3)]):
 p=Part(f'utility_{k}','维修配电箱_'+str(k),'facilities',(x,y,z),'utility_cabinet')
 p.box((x,y,z+h/2),(w,d,h),LIGHT,1,.07)
 for dx in (-w/4,w/4):
  p.box((x+dx,y-d/2-.025,z+h/2),(w/2-.075,.05,h-.18),CREAM,1,.025)
  p.box((x+dx+.18,y-d/2-.065,z+h*.46),(.05,.075,.33),DARK,0)
  bolts(p,[(x+dx-.25,y-d/2-.07,z+h-.17),(x+dx+.25,y-d/2-.07,z+.17)],r=.045)
 lamp(p,x,y-d/2-.08,z+h-.23,.24); p.finish()

# Segmented ducts with diagonal folded sheet seams, ladders and cable trays.
for n,(x,y,bottom,top) in enumerate([(-6.0,-10.45,8.8,18.65),(11.8,-9.65,8.2,21.3)]):
 p=Part(f'duct_{n}','方形通风管_立面转屋顶_'+str(n),'support',(x,y,bottom),'duct')
 for i in range(math.ceil((top-bottom)/1.1)):
  z=bottom+.55+i*1.1
  p.box((x,y,z),(1.20,1.18,1.07),LIGHT,0,.07)
  for dx in (-.60,.60): p.rod((x+dx,y-.60,z-.51),(x+dx,y-.60,z+.51),.025,GOLD,0,6)
  p.rod((x-.56,y-.61,z-.5),(x+.56,y-.61,z+.5),.016,STEEL,0,6)
 for i in range(6):
  yy=y+1.1+i*1.1; zz=top-.38
  p.box((x,yy,zz),(1.2,1.07,1.18),LIGHT,0,.06)
  p.rod((x-.55,yy-.51,zz+.6),(x+.55,yy+.51,zz+.6),.018,GOLD,0,6)
 p.finish()
for n,x in enumerate((-13.85,10.7)):
 p=Part('ladder_'+str(n),'橙色检修直梯_'+str(n),'support',(x,-10.65,6.4),'ladder')
 for dx in (-.37,.37): p.path([(x+dx,-10.6,6.4),(x+dx,-10.6,18.8),(x+dx,-10.5,19.05),(x+dx,-10.15,19.05),(x+dx,-10.05,18.1)],.057,GOLD,1)
 for j in range(34): p.rod((x-.38,-10.65,6.6+j*.36),(x+.38,-10.65,6.6+j*.36),.047,GOLD,1)
 for z in (7,10,13,16,18):
  for dx in (-.37,.37): p.rod((x+dx,-10.1,z),(x+dx,-10.6,z),.048,STEEL,0)
 p.finish()
for k,x in enumerate((-5.0,-1.8,12.95)):
 p=Part('conduit_'+str(k),'外露管线束_'+str(k),'support',(x,-10.35,.2),'conduit')
 for j in range(3):
  xx=x+j*.2
  p.path([(xx,-10.37,.2),(xx,-10.37,7.1),(xx-.3,-10.37,7.4),(xx-.3,-10.37,14.6),(xx-.1,-10.37,14.9),(xx+.12,-10.37,14.9)],.045,STEEL,0)
 for z in range(1,15): p.box((x+.18,-10.46,z),(.76,.08,.075),GOLD,0)
 p.finish()
for k,pts in enumerate([[(-10,5,18.13),(-7,5,18.13),(-7,-2,18.13),(-1,-2,18.13),(-1,-4.5,18.13)],[(8,7,18.14),(5,7,18.14),(5,1,18.14),(7,1,18.14),(7,-4,18.14)]]):
 p=Part('roof_conduit_'+str(k),'屋顶钢管布线_'+str(k),'support',pts[0],'conduit')
 for j in range(3): p.path([(x+j*.22,y,z) for x,y,z in pts],.08,DARK,0)
 p.finish()

p=Part('telecom_mast','屋顶通信塔_桁架与三向天线','facilities',(2,2,18),'telecom_mast')
for dx in (-.85,.85):
 for dy in (-.85,.85):
  p.box((2+dx,2+dy,18.13),(.7,.7,.23),LIGHT,1,.04)
  p.rod((2+dx,2+dy,18.2),(2+dx*.25,2+dy*.25,24.7),.11,DARK,0)
for z in (18.7,20.0,21.3,22.6,23.9):
 t=(z-18.2)/6.5; a=.85*(1-.75*t); b=.85*(1-.75*(t+1.3/6.5))
 for sign in (-1,1):
  p.rod((2-a,2+sign*a,z),(2+a,2+sign*a,z),.06,STEEL,0)
  p.rod((2-a,2+sign*a,z),(2+b,2+sign*b,z+1.3),.045,DARK,0)
  p.rod((2+sign*a,2-a,z),(2+sign*b,2+b,z+1.3),.045,DARK,0)
for dx,dy in [(-.95,0),(.95,0),(0,.95)]:
 p.box((2+dx,2+dy,23.45),(.25,.38,2.0),CREAM,1,.09)
 p.rod((2,2,23),(2+dx,2+dy,23),.045,STEEL,0)
p.rod((2,2,24.3),(2,2,25.6),.065,GOLD,0)
p.rod((2,2,25.5),(2,2,25.78),.13,RED,3,12)
p.finish()

for i,(x,y) in enumerate([(-7,-6),(4,7)]):
 p=Part('roof_hatch_'+str(i),'屋顶检修盖_'+str(i),'facilities',(x,y,18),'roof_hatch')
 p.box((x,y,18.10),(1.7,1.2,.2),DARK,0,.05); p.box((x,y,18.23),(1.55,1.05,.12),LIGHT,0,.04)
 p.box((x,y,18.31),(1.32,.84,.045),TILE2,2,.03); p.finish()

# Building apron and loading-bay marks belong to their individual tiles.
for row in range(3):
 for col in range(15):
  x=-14+col*2; y=-11-row*2
  p=Part(f'apron_{row}_{col}',f'装卸地坪_R{row}_C{col}','floor',(x,y,0),'paving_tile')
  p.box((x,y,.09),(1.98,1.98,.18),LIGHT if (row+col)%3 else CREAM,1,.025)
  if col in (5,8,12,14):
   p.box((x-.6,y,.185),(.09,1.96,.012),GOLD,1)
   if row>0:
    for yy in (y-.65,y,y+.65): p.poly([(x-.55,yy-.22,.194),(x-.55,yy-.06,.194),(x+.1,yy+.44,.194),(x+.1,yy+.28,.194)],[(0,1,2,3)],GOLD,1)
  p.finish()
for row in range(10):
 p=Part(f'side_paving_{row}','侧墙基础地坪_'+str(row),'floor',(-15,-9+2*row,0),'paving_tile'); p.box((-15,-9+2*row,.1),(1.98,1.98,.2),LIGHT,1,.02); p.finish()
for i,x in enumerate((-13.6,-7.0,-.7,6.55,13.5)):
 for j,y in enumerate((-10.95,-15.6)):
  p=Part(f'bollard_{i}_{j}','黄色防撞柱_'+str(i)+'_'+str(j),'facilities',(x,y,.2),'bollard')
  p.box((x,y,.25),(.6,.6,.13),LIGHT,0,.05); p.rod((x,y,.30),(x,y,1.42),.14,GOLD,0,12); p.rod((x,y,1.14),(x,y,1.30),.145,CREAM,1,12)
  bolts(p,[(x-.2,y-.2,.33),(x+.2,y+.2,.33)],axis=(0,0,1),r=.04); p.finish()

for i,(x,y) in enumerate([(-13.85,-11.8),(-7.25,-11.8)]):
 p=Part('planter_'+str(i),'入口绿植花池_'+str(i),'facilities',(x,y,.2),'planter')
 p.box((x,y,.74),(1.1,1.8,1.08),CREAM,1,.07); p.box((x,y,1.29),(1.18,1.9,.12),LIGHT,0,.03); p.box((x,y,1.35),(.9,1.60,.025),DARK,1)
 for k in range(26):
  xx=x+random.uniform(-.4,.4); yy=y+random.uniform(-.7,.7); zz=random.uniform(1.5,2.15)
  p.rod((xx,yy,1.33),(xx,yy,zz),.018,GREEN,1,5)
  for a in (0,2.1,4.2):
   q=(xx+math.cos(a)*.24,yy+math.sin(a)*.24,zz+.1)
   p.poly([(xx,yy,zz-.18),(q[0]-.12,q[1],q[2]-.08),q,(q[0]+.12,q[1],q[2]-.08)],[(0,1,2),(0,2,3)],GREEN if k%2 else (7,4),1)
 p.finish()

# Separate non-interactive display cargo, truck and forklift packages.
p=Part('cargo_stack','装卸区_托盘纸箱堆','facilities',(7,-11.5,.2),'cargo_stack')
for xx in (6.45,7,7.55): p.box((xx,-11.5,.29),(.14,1.2,.18),RUST,1)
for yy in (-11.95,-11.65,-11.35,-11.05): p.box((7,yy,.4),(1.4,.21,.13),GOLD,1)
for z in (.87,1.72,2.57):
 for x in (6.65,7.35):
  p.box((x,-11.5,z),(.66,1.0,.80),(7,2),1,.025)
  p.box((x,-12.006,z),(.07,.012,.79),GOLD2,1); p.box((x-.13,-12.014,z+.1),(.23,.01,.13),CREAM,1)
p.finish()

p=Part('delivery_truck','01号泊位_厢式货车静态展示','facilities',(-3.5,-12.1,.2),'truck_display')
p.box((-3.5,-12.4,1.03),(2.5,4.9,.35),DARK,0,.1)
for yy in (-13.8,-10.75):
 for xx in (-4.80,-2.2):
  p.rod((xx-.13,yy,.80),(xx+.13,yy,.80),.62,DARK,1,20); p.rod((xx-.15,yy,.80),(xx+.15,yy,.80),.30,STEEL,0,12)
p.box((-3.5,-12.6,2.57),(2.75,4.05,2.65),CREAM,1,.07)
p.box((-3.5,-10.18,1.90),(2.58,.95,1.90),LIGHT,1,.12)
for xx in (-4.82,-2.18): p.box((xx,-10.2,2.23),(.035,.69,.7),BLUE,2,.02)
for xx in (-4.84,-3.5,-2.16):
 p.box((xx,-14.65,2.56),(.07,.06,2.64),STEEL,0)
 if xx!=-3.5:
  p.rod((xx+(.17 if xx<-3.5 else -.17),-14.72,1.42),(xx+(.17 if xx<-3.5 else -.17),-14.72,3.68),.037,STEEL,0)
for zz in (1.26,3.89): p.box((-3.5,-14.65,zz),(2.8,.08,.10),STEEL,0)
for yy in (-14.4,-13.1,-11.8): p.box((-3.5,yy,3.91),(2.79,.06,.045),STEEL,0)
p.box((-3.5,-14.77,.88),(2.9,.14,.13),LIGHT,0)
for xx in (-4.5,-2.5): p.box((xx,-14.83,1.04),(.24,.035,.15),RED,3)
p.box((-3.5,-14.86,.95),(.56,.02,.18),CREAM,1)
for xx in (-4.69,-2.31):
 for zz in (1.50,2.55,3.61):
  p.box((xx,-14.75,zz),(.27,.11,.12),STEEL,0,.02)
  bolts(p,[(xx-.075,-14.815,zz),(xx+.075,-14.815,zz)],r=.024,c=CREAM)
 p.box((xx,-14.77,1.40),(.31,.04,.09),RED,1)
for xx in (-3.82,-3.18): p.rod((xx,-14.78,2.15),(xx+.19,-14.78,2.15),.043,STEEL,0)
for xx in (-4.89,-2.11):
 p.box((xx,-12.55,1.32),(.035,3.6,.12),RED,1)
for yy in (-13.8,-10.75):
 for xx in (-4.97,-2.03):
  for j in range(6):
   a=j*math.tau/6
   p.rod((xx,yy+math.sin(a)*.20,.80+math.cos(a)*.20),(xx+.025,yy+math.sin(a)*.20,.80+math.cos(a)*.20),.035,CREAM,0,6)
p.finish()

p=Part('forklift','03号泊位_叉车静态展示','facilities',(11.3,-12.1,.2),'forklift_display')
p.box((11.3,-12.7,.93),(1.8,2.4,.65),GOLD,0,.18)
p.box((11.3,-13.6,1.45),(1.75,.65,.8),GOLD,1,.16)
for xx in (10.39,12.21):
 for yy in (-13.25,-11.83):
  p.rod((xx-.10,yy,.62),(xx+.10,yy,.62),.43,DARK,1,16); p.rod((xx-.12,yy,.62),(xx+.12,yy,.62),.22,STEEL,0,12)
p.box((11.3,-12.7,1.53),(.70,.63,.17),DARK,1,.07); p.box((11.3,-13.0,1.85),(.70,.18,.65),DARK,1,.07)
for xx in (10.55,12.05):
 for yy in (-13.22,-11.82): p.rod((xx,yy,1.18),(xx,yy,3.03),.054,DARK,0)
p.box((11.3,-12.5,3.08),(1.74,1.72,.13),DARK,0,.09)
for xx in (10.80,11.8):
 p.box((xx,-11.5,1.91),(.16,.2,3.0),DARK,0)
 p.box((xx,-10.86,.34),(.18,1.40,.12),STEEL,0)
 p.box((xx,-11.4,.82),(.15,.13,1.05),STEEL,0)
for zz in (.7,1.9,3.15): p.box((11.3,-11.47,zz),(1.17,.16,.13),STEEL,0)
p.rod((11.3,-12.35,1.55),(11.3,-12,2.0),.055,DARK,0)
p.path([(11.3+.24*math.cos(j*math.tau/20),-12+.24*math.sin(j*math.tau/20),2.0) for j in range(21)],.028,DARK,0,6)
for xx in (10.75,11.85):
 p.box((xx,-13.97,1.52),(.23,.045,.18),CREAM,3,.03)
 p.box((xx,-13.97,1.12),(.23,.045,.11),RED,1,.02)
for yy in (-13.75,-13.6,-13.45): p.box((11.3,yy,1.89),(.8,.045,.02),DARK,0)
p.finish()
p=Part('blue_crate','装卸区_蓝色周转箱','facilities',(5.8,-12.45,.2),'cargo_stack')
p.box((5.8,-12.45,.69),(.67,.8,.94),BLUE,1,.045)
for xx in (5.51,6.09):
 for yy in (-12.8,-12.1): p.box((xx,yy,.71),(.06,.07,1.02),STEEL,0,.02)
for zz in (.35,.85,1.17):
 p.box((5.8,-12.87,zz),(.72,.05,.045),LIGHT,0)
p.box((5.8,-12.88,1.01),(.25,.018,.12),DARK,1)
p.finish()

# Additional reference-visible side maintenance access and front louvers.
for n,z in enumerate((6.15,12.05)):
 p=Part('side_catwalk_'+str(n),'侧立面检修平台_'+str(n),'architecture',(-14.5,0,z),'service_catwalk')
 p.box((-14.55,0,z),(.95,20,.16),STEEL,0,.02)
 rail(p,(-15.03,-9.9),(-15.03,9.9),z+.08)
 for yy in range(-9,10,3): p.rod((-14.06,yy,z-.9),(-15.0,yy,z-.1),.055,STEEL,0)
 p.finish()
for n,(x,z) in enumerate([(-3.8,14.6),(1,14.6)]):
 p=Part('facade_vent_'+str(n),'立面百叶风口_'+str(n),'facilities',(x,-10.2,z-1),'wall_ac')
 vent_front(p,x,-10.25,z,1.6,1.65); p.finish()
for n,(y,z) in enumerate([(-5,8.0),(3,13.8),(7,2.5)]):
 p=Part('side_service_'+str(n),'侧墙机电检修箱_'+str(n),'facilities',(y,-14.4,z),'utility_cabinet')
 p.box((y,-14.35,z+1.0),(2.0,.72,2.0),LIGHT,1,.07)
 vent_front(p,y,-14.74,z+1.0,1.55,1.6)
 for xx in (y-.6,y+.6): p.path([(xx,-14.5,z),(xx,-14.5,z-1.3),(xx+.4,-14.5,z-1.3)],.055,STEEL,0)
 rotate_part(p,-math.pi/2); p.finish()
p=Part('side_pipes','侧墙连续管线','support',(-14.3,0,.2),'conduit')
for y in (-7.5,-7.2,5.8):
 p.path([(-14.35,y,.2),(-14.35,y,17.5),(-13.8,y,18.15)],.07,STEEL,0)
 for z in range(1,17): p.box((-14.42,y,z),(.06,.36,.07),GOLD,1)
p.finish()

# Manifests and authoring boundaries.
meta=dict(asset_id=ASSET,version='v005',source_blend=str(BLEND.relative_to(R)),source_status='待验收',runtime_status='未导出；未接入',unit='meter',block_id='open_world',floor_range=plan['floor_range'],design_scope=plan['design_scope'],scene_design_docs=plan['scene_design_docs'],asset_ledger=plan['asset_ledger'],packages=catalog,package_count=len(catalog),component_definition_count=len(definitions),shared_palette=str(palette_path.relative_to(R)),coordinates='Blender Z-up；正面-Y；地面Z=0；屋顶18m',scale_basis=plan['scale_basis'])
(OUT/'catalog.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'component_packages/tree.txt').write_text('\n'.join(c['category']+'/'+c['slug']+' — '+c['display_name'] for c in catalog),encoding='utf8')
sc.render.engine='CYCLES'; sc.cycles.samples=32; sc.cycles.use_denoising=True
sc.render.image_settings.file_format='PNG'; sc.render.film_transparent=False
sc.view_settings.view_transform='AgX'; sc.view_settings.look='AgX - Medium High Contrast'; sc.view_settings.exposure=1.25
world=bpy.data.worlds.new('蓝色展示环境'); sc.world=world; world.use_nodes=True
next(n for n in world.node_tree.nodes if n.type=='BACKGROUND').inputs[0].default_value=(.045,.19,.48,1); next(n for n in world.node_tree.nodes if n.type=='BACKGROUND').inputs[1].default_value=.5
wn=world.node_tree.nodes; wl=world.node_tree.links
bg=next(n for n in wn if n.type=='BACKGROUND')
ambient=wn.new('ShaderNodeBackground'); ambient.inputs[0].default_value=(.40,.43,.48,1); ambient.inputs[1].default_value=.55
lp=wn.new('ShaderNodeLightPath'); mix=wn.new('ShaderNodeMixShader')
wl.new(lp.outputs['Is Camera Ray'],mix.inputs[0]); wl.new(ambient.outputs[0],mix.inputs[1]); wl.new(bg.outputs[0],mix.inputs[2]); wl.new(mix.outputs[0],next(n for n in wn if n.type=='OUTPUT_WORLD').inputs[0])
def light(n,kind,pos,power,color,size=10):
 data=bpy.data.lights.new(n,kind); data.energy=power; data.color=color
 ob=bpy.data.objects.new(n,data); display.objects.link(ob); ob.location=pos
 ob.rotation_euler=(Vector((0,0,12))-Vector(pos)).to_track_quat('-Z','Y').to_euler()
 if kind=='AREA': data.shape='DISK'; data.size=size
 if kind=='SUN': data.angle=.12
 return ob
light('KEY_暖光','SUN',(-35,-45,65),4.3,(1,.89,.75))
light('FILL_柔光','AREA',(-18,-40,38),3500,(.78,.88,1),20)
light('RIM_屋顶轮廓','AREA',(18,22,42),4200,(1,.90,.75),17)
for x,z in [(-12.5,17),(-10.3,17),(-8,17),(-3.5,6),(3.25,6),(10,6),(-12,4),(-8.5,4)]:
 ob=light('建筑暖光_'+str(x)+'_'+str(z),'AREA',(x,-10.95,z-.1),30,(1,.52,.12),1.2)
 ob.rotation_euler=(Vector((x,-10.1,z-1.3))-ob.location).to_track_quat('-Z','Y').to_euler()
def camera(n,pos,target,scale,res):
 data=bpy.data.cameras.new(n); data.type='ORTHO'; data.ortho_scale=scale; data.clip_end=500
 ob=bpy.data.objects.new(n,data); display.objects.link(ob); ob.location=pos; ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
 ob['resolution_x']=res[0]; ob['resolution_y']=res[1]; return ob
cameras=[(camera('CAM_参考全景',(-32,-58,38),(0,-1.8,11),43,(1600,1500)),'01_参考全景.png'),(camera('CAM_屋顶俯视',(0,-.01,65),(0,0,18),34,(1500,1200)),'02_屋顶俯视.png'),(camera('CAM_入口广告',(-24,-40,24),(-9.8,-10.2,9),22,(1200,1500)),'03_入口与广告.png'),(camera('CAM_装卸细节',(17,-40,18),(4,-11.5,3.2),24,(1600,1100)),'04_装卸区.png'),(camera('CAM_屋顶设备',(-26,-30,40),(1,1,20),32,(1500,1200)),'05_屋顶设备.png'),(camera('CAM_背面完整性',(37,50,35),(0,0,10),42,(1400,1400)),'06_背面完整性.png')]
sc.camera=cameras[0][0]; sc.render.resolution_x=1600; sc.render.resolution_y=1500; sc.render.resolution_percentage=100
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D': area.spaces.active.region_3d.view_perspective='CAMERA'; area.spaces.active.shading.type='MATERIAL'; area.spaces.active.clip_end=500
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND)); print('SOURCE_SAVED',str(BLEND),len(catalog),flush=True)
try:
 prefs=bpy.context.preferences.addons['cycles'].preferences; prefs.compute_device_type='OPTIX'; prefs.get_devices()
 gpu=False
 for device in prefs.devices: device.use=device.type!='CPU'; gpu=gpu or device.use
 if gpu: sc.cycles.device='GPU'
except Exception as exc: print('GPU_FALLBACK',str(exc),flush=True)
for cam,filename in cameras:
 sc.camera=cam; sc.render.resolution_x=cam['resolution_x']; sc.render.resolution_y=cam['resolution_y']; sc.render.filepath=str(OUT/'previews'/filename)
 bpy.ops.render.render(write_still=True); print('RENDER_DONE',filename,flush=True)
sc.camera=cameras[0][0]; sc.render.resolution_x=1600; sc.render.resolution_y=1500; sc.render.filepath=str(OUT/'previews/01_参考全景.png')
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND)); print('LOGISTICS_SOURCE_COMPLETE',len(catalog),flush=True)

