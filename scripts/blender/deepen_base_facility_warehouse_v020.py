import bpy,bmesh,math,json,ast,hashlib,importlib.util,random
from pathlib import Path
from mathutils import Vector,Matrix
P=Path('/Users/summercards/ShellStorm2');R=P/'outputs/verification/base_facility_warehouse_v020';OUT=P/'source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v020.blend'
W=bpy.data.collections['50_仓库与辅助设施'];A=bpy.data.collections['49_武器工作台与弹药附件_资产包'];C=[A]+[c for c in W.children if c.get('资产包')];assert len(C)==9
names=[c.name for c in C];allowed=set(o for c in C for o in c.all_objects)
spec=importlib.util.spec_from_file_location('old',P/'scripts/blender/reorganize_base_facility_component_packages_v017.py');old=importlib.util.module_from_spec(spec);spec.loader.exec_module(old)
source=(P/'scripts/blender/deepen_base_facility_loft_v019.py').read_text();tree=ast.parse(source)
for name in ['sig','uv','mesh','move','bevel','box','tube','cyl','paint','text','leaf','potplant']:
 node=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name==name);exec(ast.get_source_segment(source,node))
# Two segments only where silhouette benefits; micro-bevels use one segment.
_bevel=bevel
def bevel(o,width=.03,segments=2):return _bevel(o,width,1 if width<.03 else 2)
locked=json.loads(json.dumps({o.name:sig(o) for o in bpy.data.objects if o not in allowed}));(R/'locked_before.json').write_text(json.dumps(locked,ensure_ascii=False))
M=[bpy.data.materials[n] for n in ['01_精工金属_v018公共色盘','02_细腻哑光_v018公共色盘','03_清漆反光_v018公共色盘','04_柔和自发光_v018公共色盘']]
DARK=(.95,.95);STEEL=(.95,.65);TEAL=(.55,.45);GREEN=(.35,.45);LIGHT=(.95,.05);WALNUT=(.55,.75);TAN=(.85,.75);GOLD=(.85,.65);ORANGE=(.65,.75);RED=(.45,.85)
def triangles(obs):return sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in obs if o.type=='MESH')
before={c.name:{'triangles':triangles(c.all_objects),'bbox':old.bbox(list(c.all_objects))} for c in C}
# Only authorized collection-parent reassignment. Preserve names and stable package IDs.
for parent in bpy.data.collections:
 if A.name in parent.children:parent.children.unlink(A)
W.children.link(A)
S=[]
for c in C:
 for o in list(c.all_objects):bpy.data.objects.remove(o,do_unlink=True)
 for child in list(c.children):bpy.data.collections.remove(child)
 sc=bpy.data.collections.new(c.name[:2]+'_01_制作组件_统一材质_v020');c.children.link(sc);S.append(sc)
def shellcase(c,n,p,dim,cell,front=True):
 x,y,z=p;w,d,h=dim
 box(c,n+'_防冲击箱体',(x,y,z+h*.43),(w,d,h*.86),cell,b=min(.055,h*.10))
 box(c,n+'_箱盖密封缝',(x,y,z+h*.83),(w*1.012,d*1.012,.024),DARK,b=.014)
 box(c,n+'_独立箱盖',(x,y,z+h*.94),(w*1.01,d*1.01,h*.16),cell,b=min(.045,h*.07))
 # Fold-flat top handle and black inset.
 box(c,n+'_提手凹槽',(x,y,z+h*1.025),(w*.42,d*.17,.012),DARK,b=.015)
 tube(c,n+'_折叠提手',[(x-w*.17,y,z+h*1.035),(x-w*.14,y,z+h*1.095),(x+w*.14,y,z+h*1.095),(x+w*.17,y,z+h*1.035)],.022,STEEL,0,sides=6)
 for xx in [x-w*.31,x+w*.31]:
  box(c,n+'_锁扣'+str(xx),(xx,y+d*.51,z+h*.79),(.095,.04,h*.24),STEEL,0,b=.012)
 for xx in [x-w*.43,x+w*.43]:
  for yy in [y-d*.43,y+d*.43]:box(c,n+'_包角%.2f_%.2f'%(xx,yy),(xx,yy,z+.09),(.10,.10,.16),DARK,0,b=.018)
 return z+h*1.1
# flat graphic labels, no extruded high-resolution typography.
def frontlabel(c,n,body,p,size,cell=LIGHT):return text(c,n,body,p,size,cell,(math.pi/2,0,math.pi))
def topmark(c,n,p,size=.18):
 x,y,z=p
 # friendly rabbit outline and two ears, built from short polygonal strokes.
 pts=[(x+size*math.cos(a),y+size*.72*math.sin(a),z) for a in [j*math.tau/16 for j in range(17)]];tube(c,n+'_兔脸',pts,.009,LIGHT,sides=4)
 for xx in [x-size*.45,x+size*.45]:tube(c,n+'_耳'+str(xx),[(xx-size*.13,y+size*.55,z),(xx-size*.13,y+size*1.3,z),(xx+size*.13,y+size*1.3,z),(xx+size*.13,y+size*.55,z)],.009,LIGHT,sides=4)
 for xx in [x-size*.36,x+size*.36]:cyl(c,n+'_眼'+str(xx),(xx,y,z+.002),.016,.003,LIGHT,verts=6)
def mug(c,p):
 x,y,z=p;vs=[];profiles=[(0,.10),(.04,.14),(.33,.16),(.36,.16),(.36,.13),(.08,.11)]
 for zz,r in profiles:
  for j in range(16):a=j*math.tau/16;vs.append((x+r*math.cos(a),y+r*math.sin(a),z+zz))
 fs=[(k*16+j,k*16+(j+1)%16,(k+1)*16+(j+1)%16,(k+1)*16+j) for k in range(5) for j in range(16)];o=mesh(c,'台面_陶瓷杯',vs,fs,LIGHT)
 for f in o.data.polygons:f.use_smooth=True
 tube(c,'杯子_圆环柄',[(x+.15+.09*math.sin(j*math.pi/8),y,z+.18+.12*math.cos(j*math.pi/8)) for j in range(9)],.022,LIGHT,sides=6)
 cyl(c,'杯内咖啡',(x,y,z+.29),.125,.006,(.15,.75),verts=16)
def lantern(c,n,p):
 x,y,z=p;cyl(c,n+'_底座',(x,y,z+.045),.18,.09,DARK,0,verts=16);cyl(c,n+'_柔和自发光灯罩',(x,y,z+.34),.123,.46,GOLD,3,verts=16);cyl(c,n+'_顶盖',(x,y,z+.60),.17,.09,DARK,0,verts=16)
 for j in range(4):
  a=j*math.pi/2;tube(c,n+'_框%d'%j,[(x+.15*math.cos(a),y+.15*math.sin(a),z+.07),(x+.15*math.cos(a),y+.15*math.sin(a),z+.57)],.014,STEEL,0,sides=5)
 d=bpy.data.lights.new(n+'_真实暖光','POINT');d.energy=45;d.color=(1,.51,.18);d.shadow_soft_size=.18;o=bpy.data.objects.new(d.name,d);c.objects.link(o);o.location=(x,y,z+.36)
# 49: all construction is local, front +Y; rotate into west-wall placement once complete.
c=S[0]
box(c,'武器台加固木台面',(0,.55,1.67),(5.50,1.48,.18),ORANGE,b=.05)
box(c,'武器台锁柜主体',(0,.18,.87),(5.1,.78,1.42),DARK,0,b=.045)
for u in [-1.72,0,1.72]:
 box(c,'锁柜_内嵌门'+str(u),(u,.59,.9),(1.54,.035,1.19),GREEN,b=.028)
 box(c,'锁柜_凹槽拉手'+str(u),(u,.619,1.30),(.34,.02,.07),DARK,b=.012)
for u in [-2.47,2.47]:
 box(c,'工作台_台脚'+str(u),(u,.55,.31),(.13,1.30,.34),DARK,0,b=.02)
 box(c,'工作台_金属收边'+str(u),(u,.55,1.66),(.08,1.49,.18),STEEL,0,b=.018)
box(c,'武器挂墙板',(0,-.51,2.85),(5.75,.14,2.0),DARK,0,b=.035)
for u in [-2.6,-1.56,-.52,.52,1.56,2.6]:
 box(c,'挂板_分区压条'+str(u),(u,-.425,2.87),(.052,.025,1.83),STEEL,0,b=.008)
 box(c,'挂板_青色导向_柔和自发光'+str(u),(u+.10,-.422,2.88),(.018,.016,1.55),TEAL,3)
for i in range(7):box(c,'挂架_橙色快挂%d'%i,(-2.65+i*.32,-.31,3.54),(.18,.12,.20),ORANGE,b=.035)
frontlabel(c,'ARMORY_低面印刷标牌','ARMORY / FIELD SUPPLY',(0,-.405,3.63),.16,LIGHT)
# Large case anchors front left; slimmer cases and device compose the remaining top.
shellcase(c,'主补给箱',(-1.61,.72,1.78),(1.47,1.03,.62),TEAL)
for n in ['主补给箱_提手凹槽','主补给箱_折叠提手']:bpy.data.objects.remove(bpy.data.objects[n],do_unlink=True)
box(c,'主补给箱_正面提手凹槽',(-1.61,1.245,2.09),(.52,.018,.18),DARK,b=.014)
tube(c,'主补给箱_正面折叠提手',[(-1.84,1.28,2.12),(-1.80,1.32,2.04),(-1.42,1.32,2.04),(-1.38,1.28,2.12)],.022,STEEL,0,sides=6)
mark_before=set(c.objects);topmark(c,'主箱标识',(-1.61,.48,2.414),.13);bpy.context.view_layer.update()
markT=Matrix.Translation(Vector((-1.61,.48,0)))@Matrix.Rotation(math.pi,4,'Z')@Matrix.Translation(Vector((1.61,-.48,0)))
for o in set(c.objects)-mark_before:o.matrix_world=markT@o.matrix_world
text(c,'主箱_PROPERTY','PROPERTY',(-1.60,.85,2.419),.115,LIGHT,(0,0,math.pi));text(c,'主箱_TOMORROW','OF A BRIGHTER TOMORROW',(-1.60,1.02,2.419),.060,LIGHT,(0,0,math.pi))
shellcase(c,'细长附件盒',(-.28,.91,1.78),(.62,.81,.28),TEAL)
shellcase(c,'中型弹药盒',(.62,.94,1.78),(.87,.69,.38),GREEN)
shellcase(c,'终端承托盒',(1.66,.22,1.78),(.92,.72,.28),TEAL)
for j in range(3):shellcase(c,'便携弹药匣%d'%j,(1.20,-.02,1.79+j*.14),(.42,.35,.12),(.65,.75))
# Tablet tilted back, glass separated from small emissive diagrams.
parts=[]
parts.append(box(c,'终端_机身',(1.68,.38,2.40),(.69,.09,.64),DARK,0,b=.028))
parts.append(box(c,'终端_反光屏幕',(1.68,.437,2.40),(.59,.012,.53),(.75,.35),2,b=.012))
for j in range(3):parts.append(box(c,'终端_界面线_柔和自发光%d'%j,(1.68,.448,2.27+j*.11),(.40-j*.06,.003,.015),TEAL,3))
parts.append(box(c,'终端_界面侧栏_柔和自发光',(1.44,.448,2.41),(.015,.003,.43),TEAL,3))
T=Matrix.Translation(Vector((1.68,.38,2.09)))@Matrix.Rotation(-.20,4,'X')@Matrix.Translation(Vector((-1.68,-.38,-2.09)))
bpy.context.view_layer.update()
for o in parts:o.matrix_world=T@o.matrix_world
mug(c,(.35,.03,1.78));lantern(c,'工作台便携灯',(2.37,.30,1.78));potplant(c,'台面多肉',(2.38,-.12,1.78),.16)
# Small wear accents are flat host-attached faces, not modeled random chips everywhere.
for j,(x,y) in enumerate([(-2.18,1.25),(.74,1.25),(2.48,.94)]):box(c,'台面边缘磨痕%d'%j,(x,y,1.766),(.15,.01,.002),TAN)
# 51: reference low heavy-duty rail rack and four portable cases (same package name).
c=S[1];box(c,'南仓库重型货架_A_承重底盘',(0,0,.21),(5.20,.92,.18),DARK,0,b=.035)
for y in [-.44,.44]:tube(c,'重型货架_上缘护轨'+str(y),[(-2.68,y,.28),(-2.68,y,.75),(2.68,y,.75),(2.68,y,.28)],.055,STEEL,0,sides=8)
for j,u in enumerate([-1.95,-.65,.65,1.95]):
 shellcase(c,'重型货架补给箱%d'%j,(u,0,.31),(1.03,.67,.54),[GOLD,TEAL,(.95,.55),GOLD][j]);topmark(c,'货架箱标%d'%j,(u,.08,.864),.09)
# 53 generator: preserve footprint on the east side, shaped rotor, guards and control panel.
c=S[2];box(c,'备用发电机_底座',(0,0,.30),(2.15,3.10,.38),DARK,0,b=.05)
box(c,'发电机_发动机箱',(0,.35,.87),(1.68,1.70,.95),(.95,.65),0,b=.07)
o=cyl(c,'备用发电机_转子罩',(0,-.73,1.00),.62,1.22,GREEN,verts=20);o.rotation_euler.x=math.pi/2
for y in [-1.36,-.12]:
 o=cyl(c,'转子端盖'+str(y),(0,y,1.0),.63,.07,DARK,0,verts=20);o.rotation_euler.x=math.pi/2
for j in range(7):box(c,'发电机_风栅%d'%j,(-.20+j*.07,-1.407,1.0),(.026,.015,.71),STEEL,0)
for x in [-.89,.89]:tube(c,'发电机_防撞框'+str(x),[(x,-1.40,.40),(x,-1.40,1.82),(x,1.4,1.82),(x,1.4,.40)],.045,STEEL,0,sides=8)
box(c,'发电机_控制台',(-1.095,.71,1.16),(.13,.81,.54),DARK,0,b=.035)
box(c,'备用发电机_控制屏_柔和自发光',(-1.17,.72,1.22),(.012,.55,.27),TEAL,3)
for j in range(3):box(c,'发电机_控制键%d'%j,(-1.18,.52+j*.18,.97),(.019,.09,.06),GOLD,b=.01)
box(c,'发电机_维修盖',(0,.42,1.37),(1.26,1.12,.05),GREEN,b=.025)
# 54 modular battery bank with bus bars, terminal guards and isolated emissive status.
c=S[3]
for j,y in enumerate([.82,0,-.82]):
 shellcase(c,'蓄电池模块%d'%j,(0,y,.14),(1.25,.64,.82),[TEAL,(.95,.55),GOLD][j])
 for x in [-.37,.37]:cyl(c,'蓄电池端子%d_%s'%(j,x),(x,y,1.08),.055,.12,RED if x<0 else DARK,0,verts=8)
 box(c,'蓄电池_电量窗%d'%j,(-.637,y,.62),(.02,.32,.14),DARK)
 for k in range(3):box(c,'蓄电池_电量_柔和自发光%d_%d'%(j,k),(-.65,y-.10+k*.1,.62),(.015,.06,.06),TEAL,3)
for x in [-.37,.37]:tube(c,'电池组_汇流电缆'+str(x),[(x,.82,1.15),(x,0,1.15),(x,-.82,1.15)],.026,RED if x<0 else DARK,sides=6)
# 56 water barrel: lid, rolled seams and service fittings; reference compact drum silhouette.
c=S[4];vs=[];profiles=[(.10,.82),(.18,.94),(.32,.96),(2.16,.96),(2.28,.92),(2.34,.87)]
for z,r in profiles:
 for j in range(24):a=j*math.tau/24;vs.append((r*math.cos(a),r*math.sin(a),z))
fs=[(k*24+j,k*24+(j+1)%24,(k+1)*24+(j+1)%24,(k+1)*24+j) for k in range(5) for j in range(24)]+[tuple(range(23,-1,-1)),tuple(range(120,144))];o=mesh(c,'工业水箱',vs,fs,DARK,0)
for f in o.data.polygons:f.use_smooth=len(f.vertices)==4
for z in [.33,1.95,2.29]:
 pts=[(.969*math.cos(j*math.tau/24),.969*math.sin(j*math.tau/24),z) for j in range(25)];tube(c,'水箱卷边'+str(z),pts,.025,STEEL,0,sides=5)
cyl(c,'水箱_密封检修盖',(0,0,2.36),.79,.065,(.95,.75),0,verts=24)
for j in range(6):
 a=j*math.tau/6;box(c,'水箱_盖卡%d'%j,(.69*math.cos(a),.69*math.sin(a),2.40),(.10,.07,.025),ORANGE,0,b=.008)
box(c,'水箱_标签纸',(0,.963,1.0),(.54,.022,.61),TAN,b=.018);frontlabel(c,'水箱_标识','H2O',(0,.981,1.08),.16,DARK);frontlabel(c,'水箱_副标','RECYCLE',(0,.983,.86),.075,DARK)
# 57 relocated purifier, front paired removable filter cans.
c=S[5];box(c,'净水器',(0,0,1.25),(1.50,1.55,2.30),GREEN,b=.07)
box(c,'净水器_前门',(0,.80,1.31),(1.33,.075,2.07),(.95,.65),0,b=.035)
for x in [-.36,.36]:
 cyl(c,'净水器滤芯'+str(x),(x,.96,1.15),.19,1.26,LIGHT,verts=16)
 for z in [.52,1.78]:cyl(c,'滤芯端盖%s_%s'%(x,z),(x,.96,z),.22,.12,DARK,0,verts=16)
 tube(c,'滤芯管路'+str(x),[(x,.96,1.86),(x,.84,2.13),(0,.84,2.13)],.035,TEAL,sides=6)
box(c,'净水器_控制窗',(0,.85,2.09),(.66,.025,.28),DARK,b=.018)
box(c,'净水器_读数_柔和自发光',(0,.870,2.1),(.41,.009,.10),TEAL,3)
# 58 relocated compressor clear of workbench and door: south rack end.
c=S[6];box(c,'空气压缩机_底座',(0,0,.22),(2.05,1.30,.20),DARK,0,b=.04)
o=cyl(c,'空气压缩机储气罐',(0,0,.70),.44,1.65,ORANGE,verts=20);o.rotation_euler.y=math.pi/2
for x in [-.83,.83]:
 o=cyl(c,'压缩机端盖'+str(x),(x,0,.70),.45,.07,DARK,0,verts=20);o.rotation_euler.y=math.pi/2
box(c,'空气压缩机_电机',(0,-.08,1.30),(.74,.66,.48),(.95,.65),0,b=.045)
for j in range(6):box(c,'电机散热翅片%d'%j,(-.32+j*.125,-.08,1.56),(.033,.66,.035),DARK,0)
tube(c,'压缩机_提框',[(-.91,.49,.30),(-.91,.49,1.77),(.91,.49,1.77),(.91,.49,.30)],.038,STEEL,0,sides=8)
o=cyl(c,'压缩机压力表',(0,.45,1.46),.13,.06,LIGHT,verts=16);o.rotation_euler.x=math.pi/2
tube(c,'压力表指针',[(0,.489,1.46),(-.064,.489,1.50)],.009,DARK,sides=4)
# 59 hose reel faces west-wall aisle, shaped spool and six coils without a dense torus.
c=S[7];box(c,'卷盘_安装座',(0,-.12,0),(.30,.10,.83),DARK,0,b=.028)
for y in [-.10,.20]:
 o=cyl(c,'水管卷盘_侧盘'+str(y),(0,y,0),.53,.06,ORANGE,verts=20);o.rotation_euler.x=math.pi/2
for j in range(6):
 pts=[(.40*math.cos(k*math.tau/16),-.055+j*.045,.40*math.sin(k*math.tau/16)) for k in range(17)];tube(c,'水管卷盘_盘管%d'%j,pts,.039,GREEN,sides=5)
tube(c,'卷盘_下垂软管',[(.32,.14,-.22),(.46,.15,-.60),(.40,.16,-.86)],.035,GREEN,sides=6)
box(c,'卷盘_喷嘴',(.40,.16,-.92),(.07,.07,.20),STEEL,0,b=.014)
# 61 reference-style information plates, not structural wall changes.
c=S[8]
def panel(n,p,dim,body,small,cell):
 x,y,z=p;w,h=dim;box(c,n,(x,y,z),(w,.06,h),DARK,0,b=.03);box(c,n+'_纸面',(x,y+.038,z),(w-.10,.008,h-.10),cell)
 frontlabel(c,n+'_标题',body,(x,y+.049,z+h*.20),w*.20,LIGHT if cell==DARK else DARK)
 for j,t in enumerate(small):frontlabel(c,n+'_文字%d'%j,t,(x,y+.05,z+.02-j*h*.14),w*.095,LIGHT if cell==DARK else DARK)
 for xx in [x-w*.41,x+w*.41]:
  for zz in [z-h*.42,z+h*.42]:
   o=cyl(c,n+'_固定螺钉%s_%s'%(xx,zz),(xx,y+.053,zz),.023,.012,STEEL,0,verts=6);o.rotation_euler.x=math.pi/2
panel('南墙资料板_0',(-.9,0,4.73),(1.16,1.62),'A1',['STAY KIND','STAY HUMAN'],DARK)
panel('南墙资料板_1',(3.92,0,3.78),(1.08,1.47),'GOOD',['SUPPLIES','BRIGHTER DAYS'],GOLD)
panel('南墙资料板_2',(-2.22,0,4.71),(.88,1.14),'02',['FIELD','SUPPLY'],TEAL)
# Transform local assemblies into their world placements, preserving facility IDs and names.
placements=[((-13.5,-3.4,0),-math.pi/2),((-10.8,-13.55,0),0),((13.25,-9.1,0),0),((12.9,-12.12,0),0),((-13.15,-7.7,0),-math.pi/2),((-13.10,-10.35,0),-math.pi/2),((-6.65,-13.40,0),0),((-14.16,-11.90,2.44),-math.pi/2),((-14.24,-3.4,0),-math.pi/2)]
for sc,(loc,angle) in zip(S,placements):
 bpy.context.view_layer.update();T=Matrix.Translation(Vector(loc))@Matrix.Rotation(angle,4,'Z')
 for o in sc.objects:o.matrix_world=T@o.matrix_world
bpy.context.view_layer.update()
# Preserve semantic accessories as output objects; merge construction pieces by facility/material role.
catalog=[]
for c,sc in zip(C,S):
 out=bpy.data.collections.new(c.name[:2]+'_02_游戏输出_整合模型_v020');c.children.link(out);groups={}
 for o in list(sc.objects):
  if o.type!='MESH':sc.objects.unlink(o);out.objects.link(o);continue
  uv(o)
  if any(m==M[3] for m in o.data.materials):key='柔和自发光'
  elif c==A and any(k in o.name for k in ['主补给箱','主箱','中型弹药盒','细长附件盒','终端','便携弹药匣','台面多肉','杯','咖啡','工作台便携灯']):
   key=next((k for k in ['主补给箱','中型弹药盒','细长附件盒','终端','便携弹药匣','台面多肉','工作台便携灯'] if k in o.name),'台面生活附件')
  elif c==C[1] and ('补给箱' in o.name or '货架箱标' in o.name):key='补给箱'+next((str(j) for j in range(4) if str(j) in o.name),'0')
  else:key='主体'
  groups.setdefault(key,[]).append(o)
 for key,obs in groups.items():
  vs=[];fs=[];mi=[];us=[];sm=[];ns=[];mats=[]
  for o in obs:
   o.data.update();off=len(vs);vs.extend(tuple(o.matrix_world@v.co) for v in o.data.vertices);u=o.data.uv_layers[0];nt=o.matrix_world.to_3x3().inverted().transposed()
   for p in o.data.polygons:
    fs.append(tuple(off+i for i in p.vertices));m=o.data.materials[p.material_index]
    if m not in mats:mats.append(m)
    mi.append(mats.index(m));us.append([tuple(u.data[i].uv) for i in p.loop_indices]);sm.append(p.use_smooth);ns.extend(tuple((nt@o.data.corner_normals[i].vector).normalized()) for i in p.loop_indices)
  me=bpy.data.meshes.new(key+'_v020');me.from_pydata(vs,[],fs)
  for m in mats:me.materials.append(m)
  u=me.uv_layers.new(name='PaletteUV');me.uv_layers.active_index=0;u.active_render=True
  for p,idx,uu,smooth in zip(me.polygons,mi,us,sm):
   p.material_index=idx;p.use_smooth=smooth
   for li,t in zip(p.loop_indices,uu):u.data[li].uv=t
  me.normals_split_custom_set(ns);o=bpy.data.objects.new(c.name[:2]+'_'+key+'_v020',me);out.objects.link(o);o['fixed_display_attachment']=key not in ['主体','柔和自发光']
 sc.hide_viewport=True;sc.hide_render=True;c['资产类别']='warehouse';c['组织版本']='v020';c['当前状态']='仓库参考深化_待验收';slug=c['资产包键'];folder=P/'source/art/blender/base_facility_layout/component_packages/v020/warehouse'/slug;folder.mkdir(parents=True,exist_ok=True);c['未来导出目录']=str(folder.relative_to(P));center,dims=old.bbox([o for o in out.objects if o.type=='MESH'])
 rec={'package_id':slug,'collection':c.name,'parent_collection':W.name,'source_collection':sc.name,'output_collection':out.name,'source_blend':str(OUT.relative_to(P)),'version':'v020','objects':[o.name for o in out.objects],'triangles_before':before[c.name]['triangles'],'triangles_after':triangles(out.objects),'center':center,'dimensions':dims,'local_origin':[center[0],center[1],center[2]-dims[2]/2],'world_placement':placements[C.index(c)],'material_roles':[m.name for m in M],'exported':False,'runtime_integrated':False,'collision':'not_modified','fixed_display_attachments':True}
 (folder/'asset_manifest.json').write_text(json.dumps(rec,ensure_ascii=False,indent=2));catalog.append(rec)
bpy.context.view_layer.update();after=json.loads(json.dumps({n:sig(bpy.data.objects[n]) for n in locked}));diff=[n for n in locked if locked[n]!=after[n]];assert not diff,diff[:20];assert [c.name for c in C]==names;assert A.name in W.children
(R/'locked_after.json').write_text(json.dumps(after,ensure_ascii=False));(R/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2));report={'locked_match':True,'locked_count':len(locked),'package_count':len(C),'names_unchanged':True,'moved_49_under_50':True,'triangles_before':sum(x['triangles_before'] for x in catalog),'triangles_after':sum(x['triangles_after'] for x in catalog),'material_count':len(bpy.data.materials),'status':'scope_pass_visual_pending'};(R/'acceptance.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));bpy.ops.wm.save_as_mainfile(filepath=str(OUT));print('RESULT',report)
