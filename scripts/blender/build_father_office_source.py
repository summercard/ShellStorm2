"""Blender source production; frozen plan required. No runtime edits or GLB export."""
import bpy, math, json, random, hashlib
from pathlib import Path
from mathutils import Vector
from math import sin, cos, pi
R=Path(__file__).resolve().parents[2]
O=R/'assets/art/environments/master_office_3d/source/env_father_office/v002'
P=json.loads((O/'component_plan.json').read_text(encoding='utf8'))
assert P['component_plan_frozen'] and P['unique_component_count']<=50
random.seed(98109)
bpy.ops.wm.read_factory_settings(use_empty=True)
S=bpy.context.scene; S.name='父亲办公室_参考剖视'
S.unit_settings.system='METRIC'
def coll(n,parent=None):
 c=bpy.data.collections.new(n); (parent or S.collection).children.link(c); return c
root=coll('98F父亲办公室_中文资产管理')
src=coll('01_制作组件',root); out=coll('02_游戏输出_实例布局',root); stage=coll('90_展示与验收',root)
source_layer=bpy.context.view_layer.layer_collection.children[root.name].children[src.name]
palette=bpy.data.images.load(str(R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'),check_existing=True)
names=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']
mats=[]
for k,n in enumerate(names):
 m=bpy.data.materials.new(n); m.use_nodes=True; ns=m.node_tree.nodes; bs=ns.get('Principled BSDF')
 uv=ns.new('ShaderNodeUVMap'); uv.uv_map='PaletteUV'
 tex=ns.new('ShaderNodeTexImage'); tex.image=palette; tex.interpolation='Closest'
 m.node_tree.links.new(uv.outputs['UV'],tex.inputs['Vector']); m.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
 bs.inputs['Metallic'].default_value=[.86,.02,.18,0][k]; bs.inputs['Roughness'].default_value=[.28,.72,.16,.38][k]
 bs.inputs['Coat Weight'].default_value=[.15,0,.65,0][k]
 if k==3:
  m.node_tree.links.new(tex.outputs['Color'],bs.inputs['Emission Color']); bs.inputs['Emission Strength'].default_value=1.35
 mats.append(m)
colors={'steel':(9,3),'dark':(9,1),'slate':(9,4),'concrete':(9,5),'silver':(9,7),'fabric':(9,8),'paper':(9,9),'blue':(6,3),'cyan':(5,7),'gold':(1,5),'leaf':(2,2)}
# Choose chromatic cells against the actual shared palette, not an assumed column hue.
pix=list(palette.pixels)
def nearest(rgb):
 best=None
 for row in range(10):
  for col in range(9):
   x=int((col+.5)*51.2); y=int((9-row+.5)*51.2); a=(y*512+x)*4
   d=sum((pix[a+i]-rgb[i])**2 for i in range(3))
   if best is None or d<best[0]:best=(d,(col,row))
 return best[1]
for key,rgb in {'blue':(.10,.20,.32),'cyan':(.48,.78,.95),'gold':(.46,.33,.14),'leaf':(.25,.35,.11)}.items(): colors[key]=nearest(rgb)
colors['blue']=(9,2)
parts={}; lib={}; current=None
def use(slug):
 global current
 assert slug in [d['slug'] for d in P['components']]
 current=slug; parts[slug]=[]; c=coll(next(d['name_zh'] for d in P['components'] if d['slug']==slug),src); lib[slug]=c
 return c
def uvpaint(mesh,color):
 while mesh.uv_layers:mesh.uv_layers.remove(mesh.uv_layers[0])
 uv=mesh.uv_layers.new(name='PaletteUV'); uv.active_render=True
 col,row=colors[color]; cx=(col+.5)/10; cy=1-(row+.5)/10
 for p in mesh.polygons:
  for j,li in enumerate(p.loop_indices): uv.data[li].uv=(cx+.025*cos(2*pi*j/len(p.loop_indices)),cy+.025*sin(2*pi*j/len(p.loop_indices)))
def objmesh(n,verts,faces,loc=(0,0,0),mat=1,color='slate',bevel=0):
 me=bpy.data.meshes.new(n); me.from_pydata(verts,[],faces); me.update(); ob=bpy.data.objects.new(n,me); lib[current].objects.link(ob)
 ob.location=loc; ob.data.materials.append(mats[mat]); ob['color_key']=color; ob['role']=mat; parts[current].append(ob); uvpaint(me,color)
 if bevel:
  mod=ob.modifiers.new('圆角结构','BEVEL'); mod.width=bevel; mod.segments=7 if color in ['fabric','blue'] else 3
  mod.harden_normals=True
  for polygon in me.polygons:polygon.use_smooth=True
  mod=ob.modifiers.new('加权法线','WEIGHTED_NORMAL')
 return ob
def box(n,loc,size,mat=1,color='slate',bevel=.025,rot=None):
 x,y,z=[v/2 for v in size]; vs=[(-x,-y,-z),(-x,-y,z),(-x,y,-z),(-x,y,z),(x,-y,-z),(x,-y,z),(x,y,-z),(x,y,z)]
 ob=objmesh(n,vs,[(0,4,6,2),(1,3,7,5),(0,1,5,4),(2,6,7,3),(0,2,3,1),(4,5,7,6)],loc,mat,color,bevel)
 if rot:ob.rotation_euler=rot
 return ob
def cyl(n,loc,r,h,mat=0,color='steel',verts=24,r2=None):
 r2=r if r2 is None else r2
 vs=[(rr*cos(2*pi*i/verts),rr*sin(2*pi*i/verts),zz) for zz,rr in [(-h/2,r),(h/2,r2)] for i in range(verts)]
 fs=[tuple(range(verts-1,-1,-1)),tuple(range(verts,2*verts))]+[(i,(i+1)%verts,(i+1)%verts+verts,i+verts) for i in range(verts)]
 return objmesh(n,vs,fs,loc,mat,color,.018)
def tube(n,pts,r=.025,mat=0,color='steel',sides=6):
 vs=[]
 for i,p in enumerate(pts):
  p=Vector(p); d=Vector(pts[min(i+1,len(pts)-1)])-Vector(pts[max(0,i-1)])
  if d.length<1e-7:d=Vector((0,0,1))
  d.normalize(); a=d.cross(Vector((0,0,1)))
  if a.length<.01:a=d.cross(Vector((0,1,0)))
  a.normalize(); b=d.cross(a)
  vs.extend([tuple(p+r*(a*cos(t*2*pi/sides)+b*sin(t*2*pi/sides))) for t in range(sides)])
 fs=[]
 for i in range(len(pts)-1):
  for j in range(sides):fs.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
 fs.extend([tuple(range(sides-1,-1,-1)),tuple((len(pts)-1)*sides+j for j in range(sides))])
 return objmesh(n,vs,fs,mat=mat,color=color)
def rock(n,loc,size,color='concrete'):
 vs=[]; count=7
 for z in [-.5,.5]:
  for i in range(count):
   a=2*pi*i/count; rr=random.uniform(.72,1.12); vs.append((cos(a)*size[0]*.5*rr,sin(a)*size[1]*.5*rr,(z+random.uniform(-.18,.18))*size[2]))
 fs=[tuple(range(count-1,-1,-1)),tuple(range(count,2*count))]+[(i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count)]
 return objmesh(n,vs,fs,loc,1,color,.012)
def seam(n,loc,size):
 x,y,z=loc; sx,sy=size
 pts=[(x+sx*.48*cos(a),y+sy*.48*sin(a),z) for a in [2*pi*j/32 for j in range(33)]]
 return tube(n,pts,.012,1,'silver')

# 5 m modules, with attached trim, fasteners and scars.
for damaged in [False,True]:
 use('floor_fractured' if damaged else 'floor_panel')
 box('地砖承板',(0,0,.02),(5,5,.04),0,'steel',.012)
 box('地砖面板',(0,0,.06),(4.86,4.86,.07),1,'concrete',.035)
 for x in [-2.43,2.43]:box('嵌入边轨',(x,0,.101),(.045,4.90,.015),0,'silver',.006)
 for y in [-2.43,2.43]:box('嵌入边轨',(0,y,.101),(4.90,.045,.015),0,'silver',.006)
 for x in [-2.28,2.28]:
  for y in [-2.28,2.28]:cyl('沉头螺栓',(x,y,.103),.065,.022,0,'dark',8)
 for k in range(22 if damaged else 6):
  x=random.uniform(-2.25,2.25); y=random.uniform(-2.25,2.25)
  if damaged:
   pts=[(x,y,.104)]
   for t in range(random.randint(2,5)): x=max(-2.36,min(2.36,x+random.uniform(-.4,.4)));y=max(-2.36,min(2.36,y+random.uniform(.08,.35)));pts.append((x,y,.104))
   tube('板面龟裂',pts,.013,1,'dark')
  else:box('表面刮痕',(x,y,.103),(.18,.012,.004),0,'silver',0)
use('wall_panel')
box('墙体结构',(0,0,5.95),(5,.30,11.9),1,'slate',.015)
for z,h in [(1.5,2.84),(5.0,3.95),(9.42,4.8)]:
 box('墙面分区',(0,.18,z),(4.84,.12,h),1,'steel',.05)
for x in [-2.42,2.42]:box('竖向框梁',(x,.24,5.95),(.12,.20,11.9),0,'silver',.018)
for z in [.22,11.72]:box('墙沿压边',(0,.24,z),(4.96,.20,.20),0,'silver',.018)
use('wall_door')
# Exact 2.2 m clear width and 2.8 m lintel, retained from common door contract.
for x in [-1.8,1.8]:box('门侧墙',(x,0,5.95),(1.4,.3,11.9),1,'slate')
box('门上墙',(0,0,7.35),(2.2,.3,9.1),1,'slate')
for x in [-1.17,1.17]:
 box('门框',(x,.20,1.4),(.14,.24,2.8),0,'silver')
 box('门框自发光',(x,.33,1.5),(.027,.018,2.15),3,'cyan',.005)
box('门楣',(0,.20,2.86),(2.48,.24,.12),0,'silver')
use('wall_fractured')
# Clipped Voronoi fracture plates retain the exact wall envelope and form branching cracks.
seeds=[(random.uniform(-5,5),random.uniform(.15,11.75)) for _ in range(72)]
def clip(poly,a,b,c):
 result=[]
 for p,q in zip(poly,poly[1:]+poly[:1]):
  fp=a*p[0]+b*p[1]-c;fq=a*q[0]+b*q[1]-c
  if fp<=0:result.append(p)
  if (fp<0)!=(fq<0):
   t=fp/(fp-fq);result.append((p[0]+t*(q[0]-p[0]),p[1]+t*(q[1]-p[1])))
 return result
for x,z in seeds:
 poly=[(-5,0),(5,0),(5,11.9),(-5,11.9)]
 for qx,qz in seeds:
  if (qx,qz)==(x,z):continue
  poly=clip(poly,qx-x,qz-z,(qx*qx+qz*qz-x*x-z*z)/2)
  if not poly:break
 if len(poly)<3 or ((x+1.9)**2/1.25**2+(z-8.3)**2/1.5**2<1) or ((x-3.1)**2/.85**2+(z-9.7)**2/.9**2<1):continue
 cx=sum(p[0] for p in poly)/len(poly);cz=sum(p[1] for p in poly)/len(poly)
 poly=[(cx+(px-cx)*.972,cz+(pz-cz)*.972) for px,pz in poly]
 n=len(poly);depth=random.uniform(.27,.55)
 vs=[(px,yy,pz) for yy in [-.14,depth] for px,pz in poly]
 fs=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 objmesh('不规则裂墙片',vs,fs,mat=1,color=random.choice(['slate','concrete','concrete']),bevel=.018)
for x in [-4.78,4.78]:box('破墙边柱',(x,0,5.95),(.28,.38,11.9),0,'steel')
box('残留上沿',(0,0,11.72),(10,.4,.30),0,'silver')
for x in [-2.8,1.6,3.5]:
 tube('扭曲钢筋',[(x,.30,.4),(x+.15,.32,4),(x-.4,.45,7),(x-.12,.2,10.9)],.055,0,'dark')
use('metal_brace')
box('断梁腹板',(0,0,2.8),(.26,.22,5.6),0,'steel')
for x in [-.21,.21]:box('工字梁翼板',(x,0,2.8),(.09,.5,5.6),0,'dark')
for z in [.3,1.3,2.3,3.3,4.3,5.3]:
 ob=cyl('梁铆钉',(0,.16,z),.065,.07,0,'silver',8);ob.rotation_euler.x=pi/2
use('sofa')
box('底座软包',(0,0,.63),(2.5,11.6,1.06),1,'slate',.28)
for y in [-5.0,5.0]:
 for x in [-.85,.85]:cyl('沙发脚',(x,y,.20),.13,.4,0,'dark')
for i in range(7):
 y=-4.8+i*1.6
 box('独立坐垫',(.25,y,1.30),(2.12,1.56,.72),1,'fabric',.30)
 box('柔软靠背',(-.95,y,2.05),(.86,1.6,2.0),1,'fabric',.35,rot=(0,-.13,0))
 seam('坐垫缝线',(.27,y,1.65),(1.97,1.40))
 for yy in [-.38,.38]:tube('软包褶线',[(-1.34,y+yy,1.2),(-1.39,y+yy+.03,1.9),(-1.31,y+yy,2.7)],.015,1,'silver')
for y in [-5.65,5.65]:box('卷圆扶手',(.02,y,1.5),(2.56,.70,1.94),1,'fabric',.34)
use('pillow')
box('蓬松靠枕',(0,0,.56),(1.13,.44,1.12),1,'blue',.22)
for sx in [-1,1]:tube('靠枕滚边',[(sx*.46,-.21,.15),(sx*.53,-.21,.54),(sx*.46,-.21,1.01)],.014,1,'slate')
use('throw')
vs=[];nx=20;ny=25
for j in range(ny):
 t=j/(ny-1); x=-1.0+t*2.8
 for i in range(nx):
  u=i/(nx-1);y=-.8+u*1.6; z=1.65 if t<.6 else (1.65-(t-.6)/.4*1.52)
  vs.append((x,y,z+.065*sin(u*12*pi)+.02*sin(t*19)))
objmesh('垂落蓝色织毯',vs,[(j*nx+i,j*nx+i+1,(j+1)*nx+i+1,(j+1)*nx+i) for j in range(ny-1) for i in range(nx-1)],mat=1,color='blue')
use('rug')
box('厚织地毯',(0,0,.05),(6.7,12.4,.1),1,'blue',.07)
for x in [-3.17,3.17]:box('地毯包边',(x,0,.108),(.10,12.05,.014),1,'slate',0)
for y in [-6,6]:box('地毯包边',(0,y,.108),(6.4,.10,.014),1,'slate',0)
for ix in range(10):
 for iy in range(19):
  x=-2.85+ix*.63;y=-5.65+iy*.62; a=.26
  objmesh('提花菱纹',[(x-a,y,.11),(x,y+a,.11),(x+a,y,.11),(x,y-a,.11)],[(0,1,2),(0,2,3)],mat=1,color=random.choice(['blue','blue','steel']))
for k in range(130):
 x=random.uniform(-3.1,3.1);y=random.uniform(-5.9,5.9)
 box('地毯斑驳',(x,y,.117),(random.uniform(.025,.18),random.uniform(.025,.22),.006),1,random.choice(['blue','slate']),0)
use('display_case')
for z in [.25,5.5]:box('弧角展柜端盖',(0,0,z),(3.4,1.75,.46),0,'steel',.22)
box('展柜背板',(0,.67,2.85),(3.28,.16,5.1),0,'slate')
for x in [-1.58,0,1.58]:
 box('立柱',(x,0,2.85),(.1,1.44,5.1),0,'silver')
 box('柜灯自发光',(x,-.67,2.85),(.038,.035,4.8),3,'cyan',.01)
for x in [-.8,.8]:
 for z in [.6,2.9]:cyl('陈列底台',(x,-.1,z),.59,.22,0,'silver')
# Open-front glass edges preserve visibility under the four-role material contract.
for x in [-1.43,1.43]:box('玻璃窄侧片',(x,-.69,2.86),(.15,.028,4.85),2,'cyan',.005)
use('display_console')
box('展示台底座',(0,0,.42),(2.25,1.35,.84),0,'steel',.15)
box('展示台背屏',(0,.38,1.55),(2.12,.18,1.5),2,'blue',.08)
for x in [-.91,.91]:box('台灯自发光',(x,-.43,1.55),(.034,.035,1.68),3,'cyan',.009)
for z in [.84,2.38]:box('展示台框',(0,0,z),(2.23,1.32,.12),0,'silver')
use('side_table')
cyl('边桌脚',(0,0,.46),.58,.92,0,'slate')
cyl('圆台面',(0,0,1.0),.82,.16,0,'silver',48)
cyl('台面嵌环',(0,0,1.09),.68,.035,2,'steel',48)
use('shelf_ledge')
box('细长置物架',(0,0,1.35),(.66,10.8,.14),0,'steel')
for y in [-4.8,0,4.8]:box('置物架支脚',(0,y,.65),(.26,.18,1.3),0,'dark')
use('bookcase_fallen')
box('倒柜背板',(0,0,.16),(4.8,1.75,.22),1,'dark')
for x in [-2.3,2.3]:box('柜侧板',(x,0,.61),(.16,1.9,1.12),0,'steel')
for y in [-.86,.86]:box('柜顶底边',(0,y,.6),(4.7,.14,1.03),0,'steel')
for x in [-1.2,0,1.2]:box('散架隔板',(x,0,.57),(.10,1.8,.86),1,'slate',.015,rot=(0,.09,0))
box('破损柜面斜板',(.2,0,1.17),(5.05,.55,.18),0,'steel',.025,rot=(.05,-.12,.16))
for k in range(26):
 x=random.uniform(-2.12,2.12);y=random.uniform(-.60,.60)
 box('柜内固定书册',(x,y,.38+random.uniform(0,.10)),(.16,.55,.32),1,random.choice(['slate','silver','concrete']),.008,rot=(0,random.uniform(-.2,.2),random.uniform(-.2,.2)))
use('plant_withered')
cyl('花盆',(0,0,.52),.46,1.04,0,'steel',24,.62);cyl('盆土',(0,0,1.045),.54,.04,1,'dark')
for k in range(11):
 a=random.uniform(0,2*pi);h=random.uniform(1.6,3.5); dx=cos(a)*random.uniform(.4,1)
 pts=[(0,0,1.05),(dx*.3,sin(a)*.25,1.5),(dx*.6,sin(a)*.65,h*.85),(dx,sin(a),h)]
 tube('枯枝',pts,.023,1,'gold')
 for j in range(4):
  z=1.4+j*(h-1.4)/4;xx=dx*(z-1)/max(h-1,.2);yy=sin(a)*(z-1)/max(h-1,.2)
  for side in [-1,1]:
   ex=xx+side*.45;ey=yy+.15;ez=z-.28
   objmesh('卷曲枯叶',[(xx,yy,z),(ex,ey-.12,z+.05),(ex+side*.15,ey,ez),(ex,ey+.10,z-.12)],[(0,1,2),(0,2,3)],mat=1,color='gold')
use('plant_specimen')
cyl('标本基座',(0,0,.10),.45,.2,0,'silver')
for k in range(4):
 a=k*pi/2;tube('植物茎',[(0,0,.15),(.10*cos(a),.10*sin(a),1.1),(.21*cos(a),.21*sin(a),2.1)],.022,1,'leaf')
 for j in range(5):
  z=.4+j*.32;x=.15*cos(a);y=.15*sin(a);d=.4
  objmesh('标本叶',[(x,y,z),(x+d*cos(a+.5),y+d*sin(a+.5),z+.23),(x+.63*cos(a),y+.63*sin(a),z+.08),(x+d*cos(a-.5),y+d*sin(a-.5),z-.06)],[(0,1,2),(0,2,3)],mat=1,color='leaf')
use('trophy')
cyl('奖杯底座',(0,0,.10),.30,.2,0,'steel');cyl('奖杯底环',(0,0,.25),.21,.10,0,'gold')
for phase in [0,pi]:tube('奖杯螺旋',[(.19*cos(t*.32+phase),.19*sin(t*.32+phase),.3+t*.055) for t in range(25)],.035,0,'gold',8)
cyl('奖杯顶盘',(0,0,1.7),.21,.065,0,'gold')
for slug,sz in [('rubble_large',(1.15,.83,.66)),('rubble_small',(.34,.29,.22))]:
 use(slug);rock('棱角碎块',(0,0,sz[2]*.6),sz)
use('paper')
objmesh('折皱纸页',[(-.25,-.33,.012),(.25,-.33,.04),(.29,.20,.09),(.18,.34,.015),(-.24,.33,.012),(-.1,0,.10)],[(0,1,5),(1,2,5),(2,3,5),(3,4,5),(4,0,5)],mat=1,color='paper')
for y in [-.18,-.12,-.06]:box('纸上印痕',(-.03,y,.075),(.28,.01,.006),1,'silver',0)
use('book_stack')
for k in range(4):box('固定书本',(random.uniform(-.06,.06),0,.10+k*.17),(.62,.85,.14),1,'silver' if k%2 else 'steel',.015,rot=(0,0,random.uniform(-.1,.1)))
use('wall_mural')
box('浮雕底板',(0,0,3.0),(11.3,.10,5.7),1,'steel',.05)
for z in [.13,5.88]:
 box('灯轨',(0,.07,z),(11.45,.18,.10),0,'silver')
 box('长灯带自发光',(0,.17,z),(11.18,.04,.045),3,'cyan',.008)
for j in range(4):
 pts=[]
 for i in range(65):
  t=i/64*2*pi;x=3.0*cos(t)*(1-.12*j);z=3+2.1*sin(t)*(1-.12*j);pts.append((x,.08,z))
 tube('环形抽象徽章',pts,.025,0,'silver')
for i in range(8):
 x=-4.8+i*1.35;tube('壁画几何线',[(x,.085,.6),(x+.65,.085,2.2),(x-.15,.085,3.6),(x+.6,.085,5.4)],.032,1,'silver')
use('monitor_fallen')
box('脱落屏外壳',(0,0,.15),(1.9,1.32,.3),0,'steel',.08)
box('破裂显示面',(0,0,.315),(1.65,1.08,.035),2,'blue',.01)
tube('显示屏裂纹',[(-.5,-.4,.34),(-.1,-.1,.34),(.3,.05,.34),(.5,.4,.34)],.012,1,'silver')

# Bake one output master per definition, keeping editable primitives independently.
masters={};catalog=[]
for d in P['components']:
 slug=d['slug']; objects=parts[slug]; bpy.context.view_layer.update()
 deps=bpy.context.evaluated_depsgraph_get(); groups={False:[],True:[]}; allpoints=[]
 for ob in objects:
  ev=ob.evaluated_get(deps); me=bpy.data.meshes.new_from_object(ev,depsgraph=deps); me.transform(ob.matrix_world); uvpaint(me,ob['color_key'])
  allpoints.extend([v.co.copy() for v in me.vertices]); groups[ob['role']==3].append((me,int(ob['role'])))
 lo=Vector(tuple(min(v[i] for v in allpoints) for i in range(3)));hi=Vector(tuple(max(v[i] for v in allpoints) for i in range(3)))
 anchor=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 mc=bpy.data.collections.new('组件_'+d['name_zh']);mc.use_fake_user=True;masters[slug]=(mc,anchor)
 for emissive,arr in groups.items():
  if not arr:continue
  vs=[];fs=[];uvs=[];roles=[]
  for me,role in arr:
   start=len(vs);vs.extend([tuple(v.co-anchor) for v in me.vertices])
   for p in me.polygons:fs.append(tuple(start+i for i in p.vertices));uvs.append([tuple(me.uv_layers.active.data[i].uv) for i in p.loop_indices]);roles.append(role)
   bpy.data.meshes.remove(me)
  me=bpy.data.meshes.new(d['name_zh']+'输出');me.from_pydata(vs,[],fs);me.update();uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True
  rolelist=[3] if emissive else [0,1,2]
  for role in rolelist:me.materials.append(mats[role])
  for p,pu,role in zip(me.polygons,uvs,roles):
   p.material_index=rolelist.index(role)
   for li,co in zip(p.loop_indices,pu):uv.data[li].uv=co
  ob=bpy.data.objects.new(d['name_zh']+('_自发光输出' if emissive else '_主体输出'),me);mc.objects.link(ob)
 for ob in objects:
  if ob['role']==3 and '自发光' not in ob.name:ob.name+='自发光'
 # Source components are spatially separate only by collection; no layout baked into the output.
 manifest={**d,'version':'v002','source_blend':'env_father_office_source_v002.blend','collection':mc.name,'root_object':None,'objects':[o.name for o in mc.objects],'local_origin':[0,0,0],'authoring_anchor':list(anchor),'bounds_size_m':list(hi-lo),'material_roles':names,'palette_uv_layer':'PaletteUV','exported':False,'block_id':P['block_id'],'floor_range':[98,98]}
 dest=O/'component_packages'/d['category']/slug;dest.mkdir(parents=True,exist_ok=True)
 (dest/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8');catalog.append(manifest)
source_layer.exclude=True
cats={k:coll(n,out) for k,n in [('architecture','01_建筑结构'),('floor','02_地面系统'),('facilities','03_独立设施'),('decoration','04_环境陈设')]}
inst=[]
cutwalls=coll('参考剖视隐藏墙',cats['architecture'])
def place(slug,xyz,rz=0,cut=False,rx=0,ry=0):
 mc,anchor=masters[slug]; ob=bpy.data.objects.new(next(d['name_zh'] for d in P['components'] if d['slug']==slug)+'_实例',None)
 ob.instance_type='COLLECTION';ob.instance_collection=mc;cat=next(d['category'] for d in P['components'] if d['slug']==slug);cats[cat].objects.link(ob)
 ob.location=(xyz[0]-32.5,xyz[1],xyz[2]);ob.rotation_euler=(rx,ry,math.radians(rz));ob['component_id']=next(d['component_id'] for d in P['components'] if d['slug']==slug);ob['cutaway_wall']=cut
 if cut:
  cats[cat].objects.unlink(ob);cutwalls.objects.link(ob)
 inst.append(dict(instance_id=ob.name,component_id=ob['component_id'],slug=slug,position_m=list(xyz),world_position_m=list(ob.location),rotation_z_deg=rz,rotation_euler_rad=list(ob.rotation_euler),scale=[1,1,1],cutaway_hidden=cut));return ob
# Room shell: footprint matches the existing authoritative room, including east entry.
for ix in range(3):
 for iy in range(4):place('floor_fractured' if (ix+iy)%3 else 'floor_panel',(-5+5*ix,-7.5+5*iy,0))
for y in [-7.5,-2.5,2.5,7.5]:place('wall_panel',(-7.5,y,0),-90)
place('wall_panel',(-5,10,0),180);place('wall_fractured',(2.5,10,0),180)
for x in [-5,0,5]:place('wall_panel',(x,-10,0),0,cut=True)
for y in [-7.5,-2.5,2.5,7.5]:place('wall_door' if y==2.5 else 'wall_panel',(7.5,y,0),90,cut=True)
place('sofa',(-4.83,-.70,.105))
place('rug',(-.56,-.5,.108))
place('shelf_ledge',(-6.66,-.4,.105))
# Mural lies against the long left wall, facing inward.
place('wall_mural',(-7.13,-.25,3.65),-90)
for y,rz in [(-4.6,70),(-1.7,85),(2.3,65),(3.4,105)]:place('pillow',(-4.90,y,1.75),rz,rx=.18)
place('throw',(-4.60,-4.75,.40))
place('display_case',(-5.24,8.72,.105))
place('plant_specimen',(-4.45,8.60,.70))
place('trophy',(-6.0,8.58,3.16))
place('trophy',(-6.0,8.58,.69))
place('side_table',(-2.79,-6.15,.105));place('trophy',(-2.79,-6.15,1.21))
place('display_console',(6.14,-1.1,.105),90)
place('plant_specimen',(6.13,-1.1,1.0))
for xyz,rz in [((-5.96,-6.90,.12),12),((-5.75,5.7,.12),140),((5.75,-3.1,.12),-30)]:place('plant_withered',xyz,rz)
for xyz,rz in [((-3.95,-8.05,.12),-12),((4.33,-6.90,.12),68)]:place('bookcase_fallen',xyz,rz)
for y in [-3.7,0.8,2.6]:place('book_stack',(-6.65,y,1.53))
for y in [-4.7,3.9]:place('trophy',(-6.63,y,1.53))
place('monitor_fallen',(5.51,7.59,.49),25,rx=.6)
for x,y,z,tilt in [(-1.4,9.46,4.3,-.42),(2.8,9.45,1.7,.35),(4.3,9.46,4.9,.43)]:place('metal_brace',(x,y,z),0,ry=tilt)
for i in range(100):
 x=random.uniform(-3.6,6.7);y=random.uniform(6.8,9.35)
 place('rubble_large' if i<24 else 'rubble_small',(x,y,.11),random.uniform(0,360))
for i in range(82):
 x=random.uniform(-6.6,6.4);y=random.uniform(-9.3,-6.5)
 place('rubble_small' if i%4 else 'rubble_large',(x,y,.11),random.uniform(0,360))
for i in range(22):
 x=random.uniform(-2.2,3.7);y=random.uniform(-7.0,5.8)
 if abs(x)<1 and abs(y)<1:continue
 place('paper',(x,y,.25),random.uniform(0,360))
for i in range(10):place('rubble_small',(random.uniform(3.5,5.1),random.uniform(-5,6),.11),random.uniform(0,360))
for d in catalog:d['instance_count']=sum(i['slug']==d['slug'] for i in inst)
(O/'component_catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf8')
(O/'component_instances.json').write_text(json.dumps({'room_frame_origin_m':[-32.5,0,0],'coordinate_space':'blender_room_local','instances':inst},ensure_ascii=False,indent=2),encoding='utf8')
(O/'component_tree.txt').write_text('\n'.join(d['category']+'/'+d['slug']+' — '+d['name_zh'] for d in catalog),encoding='utf8')

def camera(n,loc,target,scale):
 data=bpy.data.cameras.new(n);ob=bpy.data.objects.new(n,data);stage.objects.link(ob);ob.location=loc;ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler();data.type='ORTHO';data.ortho_scale=scale;return ob
cam=camera('参考图相机',(-7.5,-36,32),(-32.5,0,3.9),34)
top=camera('俯视验收相机',(-32.5,0,40),(-32.5,0,0),25)
close=camera('沙发展示柜近景',(-20,-20,16),(-36,2,2.6),20)
S.camera=cam
def light(n,loc,power,size,color,target):
 data=bpy.data.lights.new(n,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color;ob=bpy.data.objects.new(n,data);stage.objects.link(ob);ob.location=loc;ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
light('主柔光',(-25,-10,23),6500,15,(.80,.88,1),(-34,0,0))
light('暖色补光',(-46,-5,13),2400,10,(1,.82,.67),(-33,0,3))
light('破墙冷光',(-30,12,7),3400,8,(.32,.64,1),(-32,0,1))
light('展柜柔光',(-37,7.0,4),180,2,(.4,.72,1),(-37,9,2))
S.world=bpy.data.worlds.new('冷灰摄影环境');S.world.use_nodes=True;S.world.node_tree.nodes['Background'].inputs[0].default_value=(.18,.20,.26,1);S.world.node_tree.nodes['Background'].inputs[1].default_value=.45
S.render.engine='CYCLES';S.cycles.samples=48;S.cycles.use_denoising=True
try:
 prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
 for device in prefs.devices:device.use=device.type!='CPU'
 if any(device.use for device in prefs.devices):S.cycles.device='GPU'
except Exception:pass
S.render.resolution_x=1300;S.render.resolution_y=1450;S.render.resolution_percentage=100
S.view_settings.view_transform='AgX';S.render.image_settings.file_format='PNG';S.render.film_transparent=False
S['asset_id']=P['asset_id'];S['block_id']=P['block_id'];S['floor_number']=98;S['wall_logical_height_m']=12;S['whitebox_source']=P['whitebox_source'];S['asset_ledger']=P['asset_ledger'];S['source_only']=True
for area in bpy.context.screen.areas:
 if area.type=='VIEW_3D':area.spaces.active.region_3d.view_perspective='CAMERA'
# Full enclosure view layer retains both camera-facing walls for interface inspection.
full=S.view_layers.new('完整围护_接口核对')
full.layer_collection.children[root.name].children[src.name].exclude=True
full.use=False
bpy.context.view_layer.layer_collection.children[root.name].children[out.name].children[cats['architecture'].name].children[cutwalls.name].exclude=True
# Visibility is per instance for the illustration; complete structure is retained with explicit toggles.
text=bpy.data.texts.new('阅读说明');text.write('98F 最内侧父亲办公室。参考图剖视隐藏南墙与东墙的渲染；完整墙体均保留，按对象 cutaway_wall 属性恢复 hide_render 即可。制作源在01集合，输出为集合实例。仅Blender源，未导入Godot。')
palette.filepath=bpy.path.relpath(str(R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'),start=str(O))
bpy.ops.wm.save_as_mainfile(filepath=str(O/'env_father_office_source_v002.blend'))
print('BUILD_OK',len(catalog),len(inst),flush=True)
S.render.filepath=str(O/'preview_full.png');bpy.ops.render.render(write_still=True)
S.camera=top;S.render.resolution_x=1200;S.render.resolution_y=1400;S.render.filepath=str(O/'preview_top.png');bpy.ops.render.render(write_still=True)
S.camera=close;S.render.resolution_x=1400;S.render.resolution_y=1100;S.render.filepath=str(O/'preview_close.png');bpy.ops.render.render(write_still=True)
print('RENDERS_OK',flush=True)
