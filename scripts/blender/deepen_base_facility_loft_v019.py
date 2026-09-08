import bpy, bmesh, math, json, hashlib, random, importlib.util
from pathlib import Path
from mathutils import Vector, Matrix
P=Path('/Users/summercards/ShellStorm2');R=P/'outputs/verification/base_facility_loft_v019';OUT=P/'source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v019.blend';rng=random.Random(1909)
prev=json.loads((P/'outputs/verification/base_facility_loft_v018/catalog.json').read_text());C=[bpy.data.collections[x['collection']] for x in prev]+[bpy.data.collections['116_二楼地板色彩深化_资产包']]
allowed=set(o for c in C for o in c.all_objects)
spec=importlib.util.spec_from_file_location('old',P/'scripts/blender/reorganize_base_facility_component_packages_v017.py');old=importlib.util.module_from_spec(spec);spec.loader.exec_module(old)
def sig(o):
 d=old.signature(o);d['world']=[round(v,6) for row in o.matrix_world for v in row];d['dimensions']=[round(v,6) for v in o.dimensions];d['owners']=sorted(c.name for c in o.users_collection);d['visibility']=[o.hide_render,o.hide_viewport]
 if o.type=='MESH':
  d['topology']=hashlib.sha256(repr([tuple(p.vertices) for p in o.data.polygons]).encode()).hexdigest();d['uv']=hashlib.sha256(repr([(u.name,u.active_render,[(round(v.uv.x,6),round(v.uv.y,6)) for v in u.data]) for u in o.data.uv_layers]).encode()).hexdigest()
 return d
locked={o.name:sig(o) for o in bpy.data.objects if o not in allowed};(R/'locked_before.json').write_text(json.dumps(locked,ensure_ascii=False))
M=[bpy.data.materials[n] for n in ['01_精工金属_v018公共色盘','02_细腻哑光_v018公共色盘','03_清漆反光_v018公共色盘','04_柔和自发光_v018公共色盘']]
# These four material datablocks are used exclusively by the authorized packages.
assert not any(o.type=='MESH' and any(m in M for m in o.data.materials) for o in bpy.data.objects if o not in allowed)
# A subtle physical micro-normal is shared across matte surfaces; base color is still ONLY palette UV.
m=M[1];nodes=m.node_tree.nodes;bs=next(n for n in nodes if n.type=='BSDF_PRINCIPLED');noise=nodes.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=125;noise.inputs['Detail'].default_value=2;bump=nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.12;bump.inputs['Distance'].default_value=.009;m.node_tree.links.new(noise.outputs['Fac'],bump.inputs['Height']);m.node_tree.links.new(bump.outputs['Normal'],bs.inputs['Normal'])
S=[]
for c in C:
 src=next((x for x in c.children if '制作组件' in x.name),None)
 if src:
  for child in list(c.children):
   if child!=src:
    for o in list(child.objects):
     if o.type=='LIGHT':child.objects.unlink(o);src.objects.link(o)
     else:bpy.data.objects.remove(o,do_unlink=True)
    bpy.data.collections.remove(child)
 else:
  src=bpy.data.collections.new(c.name[:3]+'_01_制作组件_已统一材质');c.children.link(src)
  for o in list(c.objects):c.objects.unlink(o);src.objects.link(o)
 src.hide_viewport=False;src.hide_render=False;S.append(src)
 for o in src.objects:
  if o.type=='MESH':o.data=o.data.copy()
# Standard colors in bottom-origin UV cells.
DARK=(.95,.95);STEEL=(.95,.65);TEAL=(.55,.45);GREEN=(.45,.45);LIGHT=(.95,.05);WALNUT=(.55,.75);TAN=(.85,.75);GOLD=(.75,.65);RED=(.45,.85);PLUM=(.65,.25)
def uv(o,cell=None):
 me=o.data
 if me.uv_layers.get('PaletteUV'):u=me.uv_layers['PaletteUV'];cells=[cell or tuple((math.floor(v*10)+.5)/10 for v in u.data[p.loop_start].uv) for p in me.polygons]
 else:u=me.uv_layers.new(name='PaletteUV');cells=[cell or DARK]*len(me.polygons)
 for l in list(me.uv_layers):
  if l.name!='PaletteUV':me.uv_layers.remove(l)
 u=me.uv_layers['PaletteUV'];me.uv_layers.active_index=0;u.active_render=True
 for p,ce in zip(me.polygons,cells):
  for j,li in enumerate(p.loop_indices):a=j*math.tau/len(p.loop_indices)+.3;u.data[li].uv=(ce[0]+.022*math.cos(a),ce[1]+.022*math.sin(a))
def mesh(c,n,vs,fs,cell,role=1):
 me=bpy.data.meshes.new(n);me.from_pydata(vs,[],fs);me.materials.append(M[role]);me.update();o=bpy.data.objects.new(n,me);c.objects.link(o);uv(o,cell);return o
def move(o,c):
 for own in list(o.users_collection):own.objects.unlink(o)
 c.objects.link(o)
def bevel(o,width=.03,segments=2):
 bpy.context.view_layer.objects.active=o
 mod=o.modifiers.new('轮廓倒角_预算受控','BEVEL');mod.width=width;mod.segments=segments
 bpy.ops.object.modifier_apply(modifier=mod.name)
 for p in o.data.polygons:p.use_smooth=True
 mod=o.modifiers.new('加权法线','WEIGHTED_NORMAL');mod.keep_sharp=True;mod.weight=50
 bpy.ops.object.modifier_apply(modifier=mod.name)
 return o
def box(c,n,loc,dim,cell,role=1,b=.0):
 x,y,z=[v*.5 for v in dim];o=mesh(c,n,[(-x,-y,-z),(x,-y,-z),(x,y,-z),(-x,y,-z),(-x,-y,z),(x,-y,z),(x,y,z),(-x,y,z)],[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],cell,role);o.location=loc
 if b:bevel(o,b,3);uv(o,cell)
 return o
def tube(c,n,points,r,cell,role=1,sides=6):
 vs=[];fs=[]
 for j,p in enumerate(points):
  p=Vector(p);t=Vector(points[min(j+1,len(points)-1)])-Vector(points[max(j-1,0)]);t.normalize();ref=Vector((0,0,1)) if abs(t.z)<.9 else Vector((0,1,0));a=t.cross(ref).normalized();b=t.cross(a).normalized()
  for k in range(sides):vs.append(tuple(p+r*(a*math.cos(k*math.tau/sides)+b*math.sin(k*math.tau/sides))))
 for j in range(len(points)-1):
  for k in range(sides):fs.append((j*sides+k,j*sides+(k+1)%sides,(j+1)*sides+(k+1)%sides,(j+1)*sides+k))
 fs.extend([tuple(range(sides-1,-1,-1)),tuple((len(points)-1)*sides+k for k in range(sides))]);o=mesh(c,n,vs,fs,cell,role)
 for p in o.data.polygons:p.use_smooth=True
 return o
def cyl(c,n,p,r,h,cell,role=1,verts=16):
 bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=h,location=p);o=bpy.context.object;o.name=n;move(o,c);o.data.materials.append(M[role]);uv(o,cell);return o
def remove(c,pred):
 for o in list(c.objects):
  if pred(o.name):bpy.data.objects.remove(o,do_unlink=True)
def paint(o,cell,role=1):o.data.materials.clear();o.data.materials.append(M[role]);uv(o,cell)
def text(c,n,body,p,size,cell,rot=(math.pi/2,0,0)):
 cu=bpy.data.curves.new(n,'FONT');cu.body=body;cu.size=size;cu.align_x='CENTER';cu.resolution_u=3;cu.extrude=0;cu.bevel_depth=0;o=bpy.data.objects.new(n,cu);c.objects.link(o);o.location=p;o.rotation_euler=rot
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.convert(target='MESH');uv(o,cell);o.data.materials.append(M[1]);return o
# A true stuffed cushion surface: 6x6 grid per side, rounded boundary and subtle center loft.
def cushion(c,n,loc,dim,cell,rot=(0,0,0),steps=5):
 vs=[];fs=[];h=Vector(dim)*.5;r=min(dim)*.32
 for axis in range(3):
  a=(axis+1)%3;b=(axis+2)%3
  for sign in [-1,1]:
   offset=len(vs)
   for j in range(steps+1):
    for k in range(steps+1):
     q=Vector((0,0,0));q[axis]=sign*h[axis];q[a]=(j/steps*2-1)*h[a];q[b]=(k/steps*2-1)*h[b];core=Vector([max(-h[t]+r,min(h[t]-r,q[t])) for t in range(3)]);delta=q-core;q=core+delta.normalized()*r
     vs.append(tuple(q))
   for j in range(steps):
    for k in range(steps):
     f=(offset+j*(steps+1)+k,offset+(j+1)*(steps+1)+k,offset+(j+1)*(steps+1)+k+1,offset+j*(steps+1)+k+1);fs.append(f if sign>0 else tuple(reversed(f)))
 o=mesh(c,n,vs,fs,cell);bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.0001);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free();uv(o,cell)
 for p in o.data.polygons:p.use_smooth=True
 o.location=loc;o.rotation_euler=rot;return o
# BED: lowered dark frame, shaped mattress and a continuous duvet with wrapped front edge.
c=S[0];remove(c,lambda n:any(x in n for x in ['床垫','床面','枕头','缝线','拖鞋']))
for o in c.objects:
 if o.type=='MESH':
  if '床架' in o.name:paint(o,DARK,0)
  if '收纳箱' in o.name:paint(o,(.25,.45))
cushion(c,'床垫_圆润承托边',(.3,11.25,6.82),(4.52,2.30,.34),LIGHT,steps=6)
# sculpted cover top and softly folded vertical front / back overhang
vs=[];fs=[];nx=22;ny=14
for i in range(nx+1):
 x=-.85+3.34*i/nx
 for j in range(ny+1):
  t=j/ny;y=10.10+2.30*t;z=7.047+.02*math.sin(i*.65)*math.sin(t*math.pi)
  if j==0 or j==ny:z=6.88
  elif j==1 or j==ny-1:z=7.005
  z+=.013*math.sin(i*1.6+t*7);vs.append((x,y,z))
for i in range(nx):
 for j in range(ny):a=i*(ny+1)+j;fs.append((a,a+ny+1,a+ny+2,a+1))
o=mesh(c,'床罩_垂边与柔软细褶',vs,fs,GREEN)
for p in o.data.polygons:p.use_smooth=True
for y in [10.16,12.34]:tube(c,'床垫_细滚边'+str(y),[(-1.84,y,6.91),(2.38,y,6.91)],.012,(.95,.15),sides=6)
cushion(c,'枕芯_宽枕',(-1.40,11.23,7.13),(1.04,1.84,.20),LIGHT,rot=(0,.035,-.02),steps=7)
# Bed front storage lids, pull recesses, seam and restrained latch details.
for j,y in enumerate([10.78,11.72]):
 box(c,'床下箱_盖缝%d'%j,(.85,y,6.44),(1.20,.71,.045),DARK,b=.012)
 box(c,'床下箱_织带提手%d'%j,(.85,y-.36,6.30),(.34,.024,.065),(.95,.75),b=.009)
# SOFA: independent softly crowned seats, leaning back cushions and diagonally posed throw pillows.
c=S[5];remove(c,lambda n:any(k in n for k in ['座垫','靠垫','靠枕','针织毯','毯穗','宽扶手']))
for i,x in enumerate([4.94,6.25,7.56]):
 cushion(c,'沙发座垫_软包%d'%i,(x,12.02,6.80),(1.23,1.06,.30),(.45,.45),steps=5)
 cushion(c,'沙发靠背_软包%d'%i,(x,12.75,7.36),(1.23,.36,1.12),(.55,.45),rot=(-.13,0,0),steps=5)
 tube(c,'座垫前细滚边%d'%i,[(x-.53,11.505,6.83),(x+.53,11.505,6.83)],.013,(.65,.45),sides=6)
for x in [4.02,8.48]:cushion(c,'沙发宽扶手_软包'+str(x),(x,12.23,6.98),(.36,1.58,.72),GREEN,steps=5)
for i,(x,cell,ang) in enumerate([(4.87,(.55,.25),-.23),(5.61,(.75,.35),.17),(7.36,(.55,.85),-.18)]):
 cushion(c,'抱枕_蓬松%d'%i,(x,12.22,7.26),(.65,.29,.64),cell,rot=(-.15,ang,0),steps=6)
 # single center button catches light without geometric quilting noise
 o=cyl(c,'抱枕包扣%d'%i,(x,12.056,7.26),.026,.014,cell,verts=8);o.rotation_euler.x=math.pi/2
# Drape with wavy edge, visible woven stripe planes following its contour.
vs=[];fs=[];profile=[(12.45,6.98),(12.12,7.005),(11.77,7.00),(11.56,6.96),(11.46,6.83),(11.43,6.58),(11.41,6.34),(11.30,6.15)]
for i in range(25):
 x=5.40+i*.045
 for j,(y,z) in enumerate(profile):vs.append((x,y+.008*math.cos(i*.9),z+.019*math.sin(i*1.24)+.006*math.cos(i*.4+j)))
for i in range(24):
 for j in range(7):a=i*8+j;fs.append((a,a+8,a+9,a+1))
o=mesh(c,'沙发_有重量的针织垂毯',vs,fs,TAN)
for p in o.data.polygons:p.use_smooth=True
for i in range(12):
 x=5.42+i*.086;tube(c,'针织毯经线%d'%i,[(x,y-.006,z+.018+.019*math.sin((x-5.4)/.045*1.24)) for y,z in profile],.006,(.75,.75),sides=4)
 tube(c,'针织毯穗%d'%i,[(x,11.29,6.155),(x+.02,11.15,6.13)],.008,TAN,sides=4)
# Nightstands: wood front, inset drawers, fine metal knobs and second low nightstand silhouette.
c=S[1]
for o in c.objects:
 if o.type=='MESH' and any(k in o.name for k in ['箱体','顶板','抽屉面']):paint(o,WALNUT)
box(c,'床头柜_抽屉内阴影',(-2.75,10.819,6.65),(.86,.014,.018),DARK)
box(c,'床侧矮柜_木箱体',(-3.80,11.36,6.51),(.84,.88,.78),(.45,.75),b=.035)
box(c,'床侧矮柜_台面',(-3.80,11.36,6.94),(.94,.94,.08),(.65,.75),b=.018)
for z in [6.33,6.63]:
 box(c,'矮柜抽屉'+str(z),(-3.80,10.91,z),(.73,.035,.23),WALNUT,b=.012)
 box(c,'矮柜拉手'+str(z),(-3.80,10.875,z),(.21,.04,.025),STEEL,0,b=.008)
# Rounded terracotta pot and individually oriented bent leaves.
def leaf(c,n,p,angle,length=.25,width=.085,cell=(.65,.55),droop=.10):
 p=Vector(p);d=Vector((math.cos(angle),math.sin(angle),.8));side=Vector((-math.sin(angle),math.cos(angle),0));vs=[]
 for k in range(5):
  t=k/4;center=p+d*length*t;center.z-=droop*t*t;w=width*math.sin(math.pi*t)
  vs.extend([tuple(center-side*w),tuple(center+Vector((0,0,.018*math.sin(math.pi*t)))),tuple(center+side*w)])
 fs=[]
 for k in range(4):
  a=k*3;fs.extend([(a,a+3,a+4,a+1),(a+1,a+4,a+5,a+2)])
 o=mesh(c,n,vs,fs,cell)
 for f in o.data.polygons:f.use_smooth=True
 return o
def potplant(c,n,p,s=.22):
 x,y,z=p;vs=[];profiles=[(0,.64),(.08,.66),(.92,.85),(1.02,.90),(1.12,.90),(1.12,.74),(.99,.73)]
 for h,r in profiles:
  for j in range(16):a=j*math.tau/16;vs.append((x+s*r*math.cos(a),y+s*r*math.sin(a),z+s*h))
 fs=[(k*16+j,k*16+(j+1)%16,(k+1)*16+(j+1)%16,(k+1)*16+j) for k in range(6) for j in range(16)];o=mesh(c,n+'_陶盆',vs,fs,(.55,.75))
 for f in o.data.polygons:f.use_smooth=True
 cyl(c,n+'_盆土',(x,y,z+s),s*.73,.012,(.15,.75),verts=16)
 for j in range(11):leaf(c,n+'_舒展叶%d'%j,(x,y,z+s),j*2.4,s*(1.45+(j%3)*.27),s*.33,(.55+(j%3)*.1,.55),droop=s*.35)
for c,n,p,s in [(S[1],'床头多肉',(-3.8,11.40,6.99),.19),(S[6],'茶几绿植',(7.14,9.53,6.80),.14),(S[10],'小桌绿植',(2.16,9.39,6.70),.11)]:
 remove(c,lambda n:any(k in n for k in ['小植物','小绿植','床头盆栽']))
 potplant(c,n,p,s)
# Lamp softened shade, dark trim and a real warm practical light.
c=S[2]
for o in c.objects:
 if o.type=='LIGHT':o.data=o.data.copy();o.data.energy=100;o.data.color=(1,.45,.12);o.data.shadow_soft_size=.30
 if o.type=='MESH' and '灯罩' in o.name and '自发光' in o.name:paint(o,(.85,.65),3)
# Curtain finer alternating warm red/plum folds and a readable hem, no flat slab rhythm.
c=S[4];remove(c,lambda n:'连续垂落' in n)
vs=[];fs=[]
for i in range(81):
 y=10.86+i*2.86/80
 for j in range(7):
  t=j/6;x=3.55+.10*math.cos(i*math.pi/4)*(1-.12*t);vs.append((x,y,6.18+2.48*t+.018*math.sin(i*.5)*(1-t)))
for i in range(80):
 for j in range(6):a=i*7+j;fs.append((a,a+7,a+8,a+1))
o=mesh(c,'隔断帘_缎纹红紫褶面',vs,fs,RED)
for f in o.data.polygons:
 f.use_smooth=True;ce=RED if (f.index//6)//8%2==0 else (.65,.85)
 for j,li in enumerate(f.loop_indices):a=j*math.pi/2+.3;o.data.uv_layers[0].data[li].uv=(ce[0]+.022*math.cos(a),ce[1]+.022*math.sin(a))
tube(c,'帘底缝边',[(3.55+.1*math.cos(i*math.pi/4),10.86+i*2.86/80,6.23+.018*math.sin(i*.5)) for i in range(81)],.009,(.35,.85),sides=4)
# Hanging greenery: curved stems with alternate paired leaves, visible stems and crown.
c=S[14];remove(c,lambda n:True);potplant(c,'吊盆',(2.72,14.10,8.08),.23)
for j in range(6):
 a=j*math.tau/6;pts=[]
 for k in range(9):
  t=k/8;p=(2.72+.18*math.cos(a)+.08*math.sin(t*4+j),14.06+.16*math.sin(a)-.08*t,8.33-.97*t);pts.append(p)
  if k>0:leaf(c,'垂藤%d_叶%d'%(j,k),p,a+(k%2)*2.4,.17,.052,(.55+.1*(k%3),.55),droop=.25)
 tube(c,'垂藤主茎%d'%j,pts,.008,(.45,.55),sides=4)
for dx in [-.18,.18]:tube(c,'吊篮支绳'+str(dx),[(2.72+dx,14.1,8.30),(2.72,14.1,8.92)],.012,DARK,0,sides=5)
# Sofa upper wall gallery: detailed flat graphic posters in existing workstation package.
c=S[11];remove(c,lambda n:'二楼后墙v013b_海报' in n or '二楼后墙v013b_工位竖海报' in n)
def poster(c,n,cx,cz,w,h,variant=0):
 y=14.28
 box(c,n+'_深色框',(cx,y,cz),(w,.05,h),DARK,0,b=.012)
 box(c,n+'_纸面',(cx,y-.032,cz),(w-.07,.012,h-.07),TAN)
 # Art is planar color geometry. No additional bitmap or per-color materials.
 left=cx-w*.43;right=cx+w*.43;bottom=cz-h*.39;top=cz+h*.25
 mesh(c,n+'_远山',[(left,y-.042,bottom),(left,y-.042,cz-.06),(cx-w*.2,y-.042,cz+h*.16),(cx,y-.042,cz),(cx+w*.23,y-.042,cz+h*.22),(right,y-.042,cz+.01),(right,y-.042,bottom)],[tuple(range(7))],(.55,.75))
 mesh(c,n+'_近山',[(left,y-.047,bottom),(left,y-.047,cz-h*.12),(cx-w*.08,y-.047,cz+h*.10),(cx+w*.14,y-.047,cz-h*.12),(right,y-.047,cz+.03),(right,y-.047,bottom)],[tuple(range(6))],(.25,.45) if variant else (.95,.85))
 # winding trail
 for k in range(5):
  z=bottom+.025+k*h*.042;x=cx+math.sin(k*.9)*w*.1
  box(c,n+'_小径%d'%k,(x,y-.052,z),(w*(.27-k*.035),.002,.017),GOLD)
 text(c,n+'_标题','ROAM' if variant else 'WILD', (cx,y-.052,cz+h*.32),w*.16,(.35,.75))
 text(c,n+'_脚注','NORTH  /  07' if variant else 'FIELD NOTES',(cx,y-.052,bottom-.035),w*.057,(.35,.75))
for i,x in enumerate([6.72,7.72]):poster(c,'沙发上方旅行海报%d'%i,x,8.47,.70,1.22,i)
# Reference-style wall lantern belongs to the existing workstation upper-wall display group.
box(c,'沙发上方壁灯_安装板',(5.05,14.27,8.60),(.19,.07,.48),DARK,0,b=.025)
tube(c,'沙发上方壁灯_弯臂',[(5.05,14.23,8.79),(5.05,13.97,8.91),(5.05,13.79,8.75)],.032,DARK,0,sides=8)
cyl(c,'壁灯_上帽',(5.05,13.78,8.67),.20,.075,DARK,0,verts=12)
cyl(c,'壁灯_柔和自发光罩',(5.05,13.78,8.40),.135,.43,(.85,.65),3,verts=12)
cyl(c,'壁灯_下托',(5.05,13.78,8.15),.18,.065,DARK,0,verts=12)
for j in range(4):
 a=j*math.pi/2;tube(c,'壁灯_护框%d'%j,[(5.05+.16*math.cos(a),13.78+.16*math.sin(a),8.17),(5.05+.16*math.cos(a),13.78+.16*math.sin(a),8.64)],.014,DARK,0,sides=5)
d=bpy.data.lights.new('沙发壁灯_暖橙实光','POINT');d.energy=115;d.color=(1,.47,.15);d.shadow_soft_size=.28;o=bpy.data.objects.new(d.name,d);c.objects.link(o);o.location=(5.05,13.60,8.4)
# EXPLORE: correct filled landscape, sun and off-road vehicle silhouette.
c=S[15];remove(c,lambda n:True);poster(c,'EXPLORE旅行画',-2.12,8.05,1.38,1.66,0)
remove(c,lambda n:'_标题' in n or '_脚注' in n)
text(c,'EXPLORE_金色标题','EXPLORE',(-2.12,14.225,8.57),.175,GOLD)
# wheels and roof-rack vehicle at bottom
for x in [-2.38,-1.94]:
 o=cyl(c,'海报越野车轮'+str(x),(x,14.218,7.55),.067,.004,DARK,verts=12);o.rotation_euler.x=math.pi/2
mesh(c,'海报_越野车侧影',[(-2.52,14.212,7.56),(-2.52,14.212,7.68),(-2.35,14.212,7.72),(-2.24,14.212,7.82),(-2.0,14.212,7.82),(-1.9,14.212,7.68),(-1.77,14.212,7.65),(-1.77,14.212,7.56)],[tuple(range(8))],GOLD)
box(c,'海报_车窗',(-2.15,14.208,7.746),(.23,.003,.065),DARK)
text(c,'海报_脚注','FIND YOUR OWN WAY',(-2.12,14.205,7.36),.064,GOLD)
# Pegboard varied fixed tools, tiny hooks and horizontal wrench instead of five identical hammers.
c=S[16];remove(c,lambda n:'固定工具' in n or '固定锤头' in n or '扳手' in n)
for i,x in enumerate([-.98,-.55,-.08,.37,.81]):
 z=8.10+(i%2)*.14
 box(c,'工具挂钩%d'%i,(x,14.28,z+.13),(.085,.10,.035),GOLD,0,b=.01)
 if i in [0,3]:
  tube(c,'工具_螺丝刀轴%d'%i,[(x,14.27,z-.32),(x,14.27,z+.01)],.018,STEEL,0,sides=6)
  o=cyl(c,'工具_橙色防滑握把%d'%i,(x,14.27,z+.055),.047,.17,(.55,.75),verts=10)
 elif i==1:
  tube(c,'工具_钳柄A',[(x-.09,14.27,z-.30),(x,14.27,z-.10),(x-.065,14.27,z+.06)],.025,RED,sides=6)
  tube(c,'工具_钳柄B',[(x+.09,14.27,z-.30),(x,14.27,z-.10),(x+.065,14.27,z+.06)],.025,STEEL,0,sides=6)
 else:
  box(c,'工具_扳手柄%d'%i,(x,14.27,z-.10),(.055,.045,.37),STEEL,0,b=.012)
  for dx in [-.052,.052]:box(c,'工具_开口爪%d_%s'%(i,dx),(x+dx,14.27,z+.10),(.038,.045,.105),STEEL,0,b=.008)
box(c,'洞洞板_下沿浅托盘',(-.15,14.245,7.43),(2.37,.16,.04),(.95,.75),0,b=.009)
# Table fronts: rounded wood edges; lenses, cup openings and restrained open book.
for c in [S[6],S[10]]:
 for o in list(c.objects):
  if o.type=='MESH' and '台面' in o.name:
   p=o.location.copy();dim=o.dimensions.copy();n=o.name;bpy.data.objects.remove(o,do_unlink=True);box(c,n,p,dim,WALNUT,b=.04)
c=S[10];remove(c,lambda n:'书页' in n)
for side in [-1,1]:
 o=box(c,'小桌_打开书页'+str(side),(1.75+side*.09,9.12,6.755),(.18,.25,.022),LIGHT,b=.004);o.rotation_euler.y=side*.10
 for j in range(4):box(c,'书页印刷%d_%d'%(side,j),(1.75+side*.09,9.045+j*.044,6.776),(.125,.004,.002),(.95,.45))
# Move the complete small-table vignette into the bed-front focal area.
for o in S[10].objects:
 o.location.y-=.80
 # World-authored display plants and flat text also follow the same package translation.
# Wooden floor. Keep surface at original 6.09m: no changed floor/stair interface or height.
c=S[17];remove(c,lambda n:True)
box(c,'木地板_原标高深色底层',(5,10,6.039),(19.6,9.6,.100),(.15,.75))
woodcells=[(.35,.75),(.45,.75),(.55,.75),(.65,.75)]
for row in range(36):
 y0=5.205+row*9.59/36;y1=5.205+(row+1)*9.59/36;x=-4.795;idx=0
 lengths=[1.1+(row%3)*.59]+[2.00+rng.random()*.80 for _ in range(15)]
 for length in lengths:
  if x>=14.795:break
  end=min(14.795,x+length);gap=.010;a=x+gap;b=end-gap;lo=y0+.007;hi=y1-.007;z=6.0905;inset=.006
  vs=[(a,lo,z-.006),(b,lo,z-.006),(b,hi,z-.006),(a,hi,z-.006),(a+inset,lo+inset,z),(b-inset,lo+inset,z),(b-inset,hi-inset,z),(a+inset,hi-inset,z)]
  fs=[(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
  cell=woodcells[rng.choices(range(4),[2,5,5,1])[0]];o=mesh(c,'木板_R%02d_C%02d'%(row,idx),vs,fs,cell)
  # Every plank keeps its own editable/output identity; surface grain is integrated with its host.
  for k in range(2):
   yy=lo+(hi-lo)*(.25+k*.45)+rng.uniform(-.02,.02);start=a+.08;finish=b-.08
   if finish>start:
    vv=[]
    for j in range(5):
     xx=start+(finish-start)*j/4;cy=yy+.008*math.sin(j*1.3+row);w=.0025*math.sin(math.pi*(j+.2)/4.4);vv.extend([(xx,cy-w,z+.0004),(xx,cy+w,z+.0004)])
    # Inline grain faces in same plank mesh, not separate objects/draw calls.
    oldvs=[tuple(v.co) for v in o.data.vertices];oldfs=[tuple(p.vertices) for p in o.data.polygons];off=len(oldvs);oldfs.extend([(off+j*2,off+j*2+2,off+j*2+3,off+j*2+1) for j in range(4)]);me=bpy.data.meshes.new(o.name+'_木纹');me.from_pydata(oldvs+vv,[],oldfs);me.materials.append(M[1]);o.data=me;uv(o,cell)
  # Alternate subtle fiber tone in the final eight grain faces.
  u=o.data.uv_layers[0]
  for f in list(o.data.polygons)[5:]:
   ce=(max(.25,cell[0]-.10),.75)
   for j,li in enumerate(f.loop_indices):ang=j*math.pi/2+.3;u.data[li].uv=(ce[0]+.022*math.cos(ang),ce[1]+.022*math.sin(ang))
  x=end;idx+=1
# Foreground auxiliary-table textile occupies visible empty floor without raising furniture.
c=S[3]
box(c,'床前小桌_织物毯底',(1.80,8.18,6.106),(3.10,1.75,.028),(.85,.85),b=.007)
for inset,cell in [(.10,(.75,.75)),(.18,(.95,.75)),(.25,(.75,.75))]:
 for y in [7.305+inset,9.055-inset]:box(c,'小毯横边'+str(y),(1.80,y,6.123),(3.1-2*inset,.018,.003),cell)
 for x in [.25+inset,3.35-inset]:box(c,'小毯竖边'+str(x),(x,8.18,6.123),(.018,1.75-2*inset,.003),cell)
# Existing rugs: reduce high contrast ornamental geometry; use nested framed motifs.
c=S[7]
for o in c.objects:
 if o.type=='MESH':
  if '菱花' in o.name:paint(o,(.65,.75))
  if '酒红底' in o.name:paint(o,(.45,.85))
# Pouf lid center button and a few stitched seams; retain 16-sided silhouette budget.
for c,cell in [(S[8],TEAL),(S[9],(.25,.45))]:
 o=next(o for o in c.objects if '分层软包' in o.name);center=old.bbox([o])[0]
 cyl(c,'坐墩_中心包扣',(center[0],center[1],6.777),.022,.008,cell,verts=8)
# Build clean outputs while retaining normals and UV face colors. Fixed props remain replaceable.
bpy.context.view_layer.update()
def count(obs):return sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in obs if o.type=='MESH')
catalog=[]
for c,src in zip(C,S):
 for o in src.objects:
  if o.type=='MESH':
   uv(o);o.data.uv_layers.active_index=0;o.data.uv_layers[0].active_render=True
 out=bpy.data.collections.new(c.name[:3]+'_02_游戏输出_整合模型');c.children.link(out);groups={}
 for o in list(src.objects):
  if o.type!='MESH':src.objects.unlink(o);out.objects.link(o);continue
  if c==C[17]:key=o.name # boards are separately replaceable modules
  elif any(k in o.name for k in ['陶盆','盆土','叶','垂藤','吊篮']):key='植物组件'
  elif any(k in o.name for k in ['杯','相机','遥控','杂志','书页','书本','个人终端']):key=o.name
  else:key='柔和自发光' if any(m==M[3] for m in o.data.materials) else '主体'
  groups.setdefault(key,[]).append(o)
 for key,obs in groups.items():
  vs=[];fs=[];idx=[];us=[];normals=[];smooth=[];mats=[]
  for o in obs:
   o.data.update();offset=len(vs);vs.extend([tuple(o.matrix_world@v.co) for v in o.data.vertices]);nt=o.matrix_world.to_3x3().inverted().transposed();u=o.data.uv_layers[0]
   for p in o.data.polygons:
    fs.append(tuple(offset+v for v in p.vertices));m=o.data.materials[p.material_index]
    if m not in mats:mats.append(m)
    idx.append(mats.index(m));us.append([tuple(u.data[i].uv) for i in p.loop_indices]);smooth.append(p.use_smooth)
    normals.extend([tuple((nt@o.data.corner_normals[i].vector).normalized()) for i in p.loop_indices])
  me=bpy.data.meshes.new(key+'_v019');me.from_pydata(vs,[],fs)
  for m in mats:me.materials.append(m)
  u=me.uv_layers.new(name='PaletteUV');me.uv_layers.active_index=0;u.active_render=True
  for p,mi,uu,sm in zip(me.polygons,idx,us,smooth):
   p.material_index=mi;p.use_smooth=sm
   for li,t in zip(p.loop_indices,uu):u.data[li].uv=t
  if normals:me.normals_split_custom_set(normals)
  o=bpy.data.objects.new(c.name.split('_')[0]+'_'+key+'_v019',me);out.objects.link(o)
  o['fixed_display_attachment']=key not in ['主体','柔和自发光'] and c!=C[17]
 src.hide_render=True;src.hide_viewport=True
 c['组织版本']='v019';c['当前状态']='参考重点深化_待验收';c['正面方向']='-Y';c['楼面标高']=6.09
 center,dims=old.bbox([o for o in out.objects if o.type=='MESH']);slug=c['资产包键'];folder=P/'source/art/blender/base_facility_layout/component_packages/v019'/slug;folder.mkdir(parents=True,exist_ok=True)
 rec={'package_id':slug,'collection':c.name,'version':'v019','source_blend':str(OUT.relative_to(P)),'source_collection':src.name,'output_collection':out.name,'objects':[o.name for o in out.objects],'triangles':count(out.objects),'center':center,'dimensions':dims,'local_origin':[center[0],center[1],center[2]-dims[2]/2],'front':'-Y','exported':False,'runtime_integrated':False,'collision':'unchanged','floor_height':6.09,'material_roles':[m.name for m in M]}
 (folder/'asset_manifest.json').write_text(json.dumps(rec,ensure_ascii=False,indent=2));catalog.append(rec)
bpy.context.view_layer.update();after={n:sig(bpy.data.objects[n]) for n in locked};diff=[n for n in locked if locked[n]!=after[n]];(R/'locked_after.json').write_text(json.dumps(after,ensure_ascii=False));assert not diff,diff[:20]
report={'locked_match':True,'locked_count':len(locked),'package_count':len(C),'triangles':sum(r['triangles'] for r in catalog),'floor_triangles':catalog[-1]['triangles'],'material_count':len(bpy.data.materials),'status':'scope_pass_visual_pending'}
(R/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2));(R/'acceptance.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));bpy.ops.wm.save_as_mainfile(filepath=str(OUT));print('RESULT',report)
