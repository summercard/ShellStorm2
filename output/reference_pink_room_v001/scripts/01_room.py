import bpy, math, random, os, json
from mathutils import Vector
from math import sin,cos,pi
random.seed(27)
OUT='/Users/summercards/ShellStorm2/output/reference_pink_room_v001'
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for c in list(bpy.data.collections):
 if c.name!='Collection' and c.users==0: bpy.data.collections.remove(c)
scene=bpy.context.scene
scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=.1; scene.unit_settings.length_unit='MILLIMETERS'
root=bpy.data.collections.new('粉色电竞卧室_参考还原_v001'); scene.collection.children.link(root)
COL=None
packs={}
def group(name):
 global COL
 COL=bpy.data.collections.new(name); root.children.link(COL); packs[name]=COL
 return COL
def put(o,name,color,role='matte'):
 o.name=name
 for c in list(o.users_collection): c.objects.unlink(o)
 COL.objects.link(o)
 o.color=(*color,1); o.data.materials.append(MATS[role])
 return o
MATS={}
for role,rough,metal in [('matte',.48,0),('fabric',.85,0),('gloss',.22,.05),('metal',.27,.8),('glow',.35,0)]:
 m=bpy.data.materials.new('共享_'+role); m.use_nodes=True
 n=m.node_tree.nodes; l=m.node_tree.links; p=next(x for x in n if x.type=='BSDF_PRINCIPLED'); p.inputs['Roughness'].default_value=rough; p.inputs['Metallic'].default_value=metal
 info=n.new('ShaderNodeObjectInfo'); l.new(info.outputs['Color'],p.inputs['Base Color'])
 if role=='glow':
  l.new(info.outputs['Color'],p.inputs['Emission Color']); p.inputs['Emission Strength'].default_value=3.2
 if role=='fabric':
  tex=n.new('ShaderNodeTexNoise'); tex.inputs['Scale'].default_value=195; tex.inputs['Detail'].default_value=2
  bump=n.new('ShaderNodeBump'); bump.inputs['Strength'].default_value=.16; bump.inputs['Distance'].default_value=.006
  l.new(tex.outputs['Fac'],bump.inputs['Height']); l.new(bump.outputs['Normal'],p.inputs['Normal']); p.inputs['Sheen Weight'].default_value=.23
 MATS[role]=m
W=(.84,.81,.80); WHITE=(.93,.89,.89); PINK=(.91,.15,.47); LIGHTP=(.99,.34,.63); DK=(.032,.022,.037); GREY=(.18,.165,.19); CYAN=(.008,.66,.94); MAG=(1,.006,.48); SIL=(.56,.6,.66)
def bevel(o,r=.02,segments=3):
 mod=o.modifiers.new('真实圆角','BEVEL'); mod.width=r; mod.segments=segments
 mod=o.modifiers.new('加权法线','WEIGHTED_NORMAL')
 return o
def box(name,loc,size,color=W,r=.015,role='matte'):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc); o=bpy.context.object; o.dimensions=size; bpy.ops.object.transform_apply(location=False,rotation=False,scale=True); put(o,name,color,role)
 if r: bevel(o,r,4)
 return o
def uv(name,loc,size,color,role='matte',seg=32,rings=20):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=seg,ring_count=rings,location=loc); o=bpy.context.object; o.scale=size; bpy.ops.object.transform_apply(location=False,rotation=False,scale=True); put(o,name,color,role)
 for p in o.data.polygons:p.use_smooth=True
 return o
def mesh(name,verts,faces,color,role='matte',smooth=False):
 me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.update(); o=bpy.data.objects.new(name,me); COL.objects.link(o); o.color=(*color,1); me.materials.append(MATS[role])
 if smooth:
  for f in me.polygons:f.use_smooth=True
 return o
def tube(name,pts,r,color,role='matte',cyclic=False):
 cu=bpy.data.curves.new(name,'CURVE'); cu.dimensions='3D'; cu.resolution_u=12; cu.bevel_depth=r; cu.bevel_resolution=3
 sp=cu.splines.new('BEZIER'); sp.bezier_points.add(len(pts)-1)
 for b,co in zip(sp.bezier_points,pts): b.co=co; b.handle_left_type='AUTO'; b.handle_right_type='AUTO'
 sp.use_cyclic_u=cyclic
 o=bpy.data.objects.new(name,cu); COL.objects.link(o); o.color=(*color,1); cu.materials.append(MATS[role]); return o
def rod(name,a,b,r,color,role='matte',r2=None):
 v=Vector(b)-Vector(a); mid=(Vector(a)+Vector(b))/2
 bpy.ops.mesh.primitive_cone_add(vertices=32,radius1=r,radius2=r if r2 is None else r2,depth=v.length,location=mid); o=bpy.context.object; o.rotation_euler=v.to_track_quat('Z','Y').to_euler(); put(o,name,color,role); bevel(o,min(.006,r/3),2)
 for p in o.data.polygons:p.use_smooth=True
 return o
def polyprism(name,outline,y0,y1,color,r=.01):
 v=[(x,y,z) for y in (y0,y1) for x,z in outline]; n=len(outline); f=[tuple(reversed(range(n))),tuple(range(n,n*2))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 o=mesh(name,v,f,color)
 if r:bevel(o,r)
 return o
def cushion(name,loc,size,color,ex=.45,role='fabric'):
 # Sewn superellipsoid with a shallow puckered crown, not a scaled cube.
 verts=[]; faces=[]; nu=64; nv=32
 def pw(a,e):return (1 if a>=0 else -1)*abs(a)**e
 for j in range(nv+1):
  t=-pi/2+pi*j/nv
  for i in range(nu):
   p=2*pi*i/nu
   x=pw(cos(t),ex)*pw(cos(p),ex); y=pw(cos(t),ex)*pw(sin(p),ex); z=pw(sin(t),.65)
   z+=.013*sin(p*7)*sin(t*9)*(abs(x)*abs(y))
   verts.append((loc[0]+size[0]*x/2,loc[1]+size[1]*y/2,loc[2]+size[2]*z/2))
 for j in range(nv):
  for i in range(nu): a=j*nu+i;b=j*nu+(i+1)%nu;faces.append((a,b,b+nu,a+nu))
 return mesh(name,verts,faces,color,role,True)
def area(name,loc,target,power,color,size):
 d=bpy.data.lights.new(name,'AREA'); d.energy=power; d.color=color; d.shape='DISK'; d.size=size
 o=bpy.data.objects.new(name,d); COL.objects.link(o);o.location=loc;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();return o

group('01_房间外壳')
box('完整地台',(0,0,-.045),(3.62,3.12,.09),(.57,.65,.7),.012)
box('浅灰地面',(0,0,.005),(3.5,3,.025),(.75,.76,.79),.005)
box('背墙',(0,1.53,1.02),(3.62,.06,2.04),(.78,.72,.76),.006)
box('左墙',(-1.78,0,1.02),(.06,3.12,2.04),(.73,.76,.78),.006)
for x in (-1.745,1.745):box('竖向边框',(x,1.475,1.02),(.055,.07,2.04),(.56,.64,.68),.008)
box('背墙上压边',(0,1.48,2.025),(3.56,.1,.07),(.58,.65,.69))
box('左墙上压边',(-1.74,0,2.025),(.1,3.06,.07),(.58,.65,.69))
box('后墙踢脚',(0,1.47,.065),(3.5,.025,.1),W,.004)
for x in (-1.70,1.70):
 box('青色竖灯带',(x,1.422,.46),(.017,.024,.86),CYAN,.007,'glow')
 box('粉色竖灯带',(x,1.422,1.43),(.017,.024,1.05),MAG,.007,'glow')
box('左墙前端粉灯',(-1.698,-1.46,1.48),(.025,.018,.96),MAG,.006,'glow')
box('左墙前端青灯',(-1.698,-1.46,.48),(.025,.018,.95),CYAN,.006,'glow')

group('02_通高衣柜')
box('衣柜壳体',(-1.365,1.09,1.015),(.61,.65,1.91),W,.012)
for x in (-1.513,-1.217):box('独立柜门',(x,.754,1.025),(.291,.027,1.866),WHITE,.008)
box('柜门中缝',(-1.365,.737,1.025),(.008,.008,1.85),(.4,.38,.4),.001)
box('嵌入式灰紫镜边',(-1.526,.729,1.305),(.245,.023,.369),(.64,.59,.65),.035)
box('圆角紫灰镜面',(-1.526,.713,1.305),(.218,.008,.339),(.17,.125,.19),.028,'gloss')
box('竖向门把手',(-1.39,.719,1.0),(.015,.025,.15),SIL,.006,'metal')
box('日历黑色挂头',(-1.56,.714,1.057),(.115,.012,.024),DK,.002)
box('日历纸',(-1.56,.717,.958),(.112,.009,.165),WHITE,.002)
for row in range(6):
 for col in range(5):box('日历日期',( -1.6+col*.02,.71,1.019-row*.023),(.01,.003,.01),(.42,.2,.27) if row==0 else GREY,.001)

group('03_电视柜与电视')
box('电视柜主体',(-.75,1.13,.278),(1.11,.52,.52),(.215,.205,.225),.008)
for j in range(3):
 for i in range(2):box('抽屉面板',(-1.027+i*.554,.861,.119+j*.165),(.543,.023,.153),(.285,.268,.294),.005)
box('电视柜台面',(-.75,1.12,.552),(1.14,.555,.032),GREY,.008)
for i in range(37):box('电视墙竖向格栅',(-1.08+i*.026,1.442,.977),(.011,.025,.75),(.125,.056,.12),.002)
box('电视外框',(-.755,1.233,.969),(.91,.068,.648),(.043,.032,.055),.013,'gloss')
box('电视内屏',(-.755,1.194,.972),(.86,.008,.591),(.022,.015,.034),.004,'gloss')
rod('电视支柱',(-.755,1.229,.558),(-.755,1.229,.692),.025,DK)
box('电视底座',(-.755,1.19,.572),(.3,.18,.025),DK,.018)
box('电视下标',(-.755,1.187,.659),(.058,.002,.004),(.57,.53,.58),.001)
box('电视背景粉灯',(-.73,1.412,1.396),(1.04,.016,.016),MAG,.006,'glow')

group('04_折线置物架')
# One continuous broad black zig-zag ribbon matching the reference.
path=[(-.77,1.817),(.28,1.817),(.45,1.45),(.72,1.45),(.97,1.03),(1.64,1.03)]
for a,b in zip(path,path[1:]):
 dx=b[0]-a[0]; dz=b[1]-a[1]; L=math.hypot(dx,dz); nx=-dz/L*.028;nz=dx/L*.028
 polyprism('连续折线搁板',[(a[0]+nx,a[1]+nz),(b[0]+nx,b[1]+nz),(b[0]-nx,b[1]-nz),(a[0]-nx,a[1]-nz)],1.205,1.457,DK,.005)
box('床头青色环境线',(1.27,1.445,.883),(.86,.014,.015),CYAN,.005,'glow')

group('05_电脑桌')
# custom chamfered desktop in top view
outline=[(-.225,.875),(.09,.71),(.71,.6),(.9,.73),(.71,1.1),(.12,1.27),(-.23,1.19)]
v=[(x,y,z) for z in (.569,.609) for x,y in outline];n=len(outline)
o=mesh('异形转角桌面',v,[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],WHITE);bevel(o,.016)
for x,y in [(-.13,1.08),(.72,.84)]:
 box('黑色桌腿',(x,y,.307),(.047,.047,.52),DK,.006,'metal')
 box('桌脚落地横撑',(x,y,.035),(.15,.25,.045),W,.01)
box('桌下RGB灯柱',(.04,1.23,.32),(.065,.045,.46),CYAN,.008,'glow')
for idx,(x,y,ang) in enumerate([(-.07,1.147,-.19),(.237,1.135,.06),(.524,1.063,.40)]):
 panel=box('三联屏_%d_背壳'%idx,(x,y,.833),(.312,.032,.237),W,.007);panel.rotation_euler.z=ang
 front=box('三联屏_%d_白屏'%idx,(x+sin(ang)*.018,y-cos(ang)*.018,.834),(.296,.006,.219),(.83,.8,.85),.004,'glow');front.rotation_euler.z=ang
 rod('显示器立柱',(x,y,.615),(x,y,.72),.011,GREY,'metal')
 box('显示器脚',(x,y-.015,.62),(.12,.085,.011),GREY,.009)
box('键盘底座',(.225,.837,.627),(.343,.125,.018),(.62,.51,.61),.013)
for row in range(5):
 for col in range(15):
  box('独立键帽',(.07+col*.022,.791+row*.021,.64),(.017,.016,.008),(.89,.72,.84) if col%4 else LIGHTP,.002)
box('空格键',(.222,.792,.645),(.113,.017,.009),WHITE,.003)
box('鼠标垫',(.562,.765,.616),(.142,.15,.007),(.22,.2,.24),.012)
uv('鼠标',(.566,.783,.637),(.029,.041,.022),W,'gloss')
tube('鼠标分缝',[(.567,.758,.65),(.567,.789,.66),(.567,.808,.65)],.0014,GREY)
rod('鼠标滚轮',(.567,.79,.658),(.567,.801,.658),.004,DK)

group('06_床与床品')
box('床箱', (1.1,.15,.181),(.765,1.29,.31),W,.012)
box('床头外框',(1.1,.812,.574),(.78,.079,.613),W,.012)
cushion('床头软包',(1.1,.764,.607),(.7,.055,.42),(.81,.76,.79),.35)
box('床垫支撑沿',(1.1,.153,.348),(.781,1.3,.05),WHITE,.008)
cushion('白色床垫',(1.1,.148,.395),(.752,1.24,.111),WHITE,.3)
cushion('枕头',(1.1,.615,.485),(.605,.264,.11),(.88,.8,.86),.5)
# draped quilt: horizontal crown continues smoothly down both sides and at foot
verts=[];faces=[];nx=60;ny=65
for j in range(ny+1):
 y=-.51+j*.97/ny
 for i in range(nx+1):
  u=-1+2*i/nx; x=1.1+u*.39
  z=.457-.145*max(0,(abs(u)-.89)/.11)**.65
  z-=.10*max(0,(-y-.415)/.095)**.7
  z+=.004*sin(i*.69+j*.39)+.003*sin(j*.53)*abs(u)**4
  verts.append((x,y,z))
for j in range(ny):
 for i in range(nx):a=j*(nx+1)+i;faces.append((a,a+1,a+nx+2,a+nx+1))
o=mesh('粉色垂坠被面_布料褶皱',verts,faces,PINK,'fabric',True);sol=o.modifiers.new('被子厚度','SOLIDIFY');sol.thickness=.012
# piping and folded upper hem
for x in (.755,1.445):tube('被面滚边',[(x,-.44,.45),(x,-.2,.462),(x,.08,.462),(x,.43,.46)],.0035,LIGHTP,'fabric')
cushion('被头折边',(1.1,.419,.472),(.73,.105,.027),LIGHTP,.4)

group('07_矮沙发')
box('沙发下框',(.225,-.963,.135),(1.0,.465,.24),W,.014)
for x in (-.06,.40):cushion('独立座垫',(x,-.981,.281),(.46,.393,.105),WHITE,.32)
for x in (-.08,.37):cushion('分片靠背',(x,-.759,.414),(.45,.105,.317),WHITE,.33)
for x in (-.298,.747):
 box('沙发扶手',(x,-.96,.289),(.105,.474,.294),WHITE,.015)
cushion('粉色抱枕',(.592,-.925,.369),(.269,.262,.089),PINK,.6)
# piping on upholstery back
for x in (-.08,.37):tube('靠背缝线',[(x-.198,-.817,.288),(x-.198,-.817,.539),(x+.198,-.817,.539),(x+.198,-.817,.288)],.0018,(.69,.66,.68))

group('08_茶几')
box('茶几底层',(-.40,-1.0,.065),(.8,.6,.052),(.19,.205,.22),.008)
for x in (-.69,-.11):
 for y in (-1.2,-.8):rod('茶几金属支柱',(x,y,.073),(x,y,.252),.018,SIL,'metal')
box('茶几上层',(-.40,-1.0,.266),(.8,.6,.035),(.77,.75,.76),.008)
box('茶几中层',(-.40,-1.0,.163),(.65,.475,.027),(.44,.4,.44),.008)

group('09_懒人沙发')
# asymmetric sewn beanbag with pinched top, bulging lower body and restrained facets
vs=[];fs=[];N=48;R=24
for j in range(R+1):
 t=pi*j/R
 for i in range(N):
  a=2*pi*i/N;rad=sin(t)*(1+.17*cos(t))
  x=-1.21+.304*rad*cos(a);y=-.96+.283*rad*sin(a);z=.20+.186*cos(t)+.021*sin(a)*sin(t)**2
  x+=.045*max(0,cos(t))**2
  vs.append((x,y,z))
for j in range(R):
 for i in range(N):a=j*N+i;b=j*N+(i+1)%N;fs.append((a,b,b+N,a+N))
mesh('梨形豆袋软包',vs,fs,LIGHTP,'fabric',True)
for a in [0,pi/2,pi,pi*1.5]:
 pts=[]
 for j in range(1,24):
  t=pi*j/24;rad=sin(t)*(1+.17*cos(t));pts.append((-1.21+.305*rad*cos(a)+.045*max(0,cos(t))**2,-.96+.284*rad*sin(a),.2+.187*cos(t)+.021*sin(a)*sin(t)**2))
 tube('豆袋拼片缝线',pts,.0016,(.76,.19,.42),'fabric')

group('10_地毯')
box('淡紫方毯',(-.91,.115,.029),(.99,.83,.012),(.59,.52,.72),.022,'fabric')
print('stage 1 objects',len(bpy.data.objects))
