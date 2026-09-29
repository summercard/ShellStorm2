"""Localized v002 roof/crane rebuild. Frozen lower building and reference cameras."""
import bpy,math,json,hashlib,ast,random
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2]
BASE=R/'assets/art/environments/open_world/source/tower_02/v001'
OUT=BASE.parent/'v002'; OUT.mkdir(exist_ok=True)
for d in ['qa','previews','component_packages']: (OUT/d).mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'塔2_施工高楼_70x50m_v001.blend'))
scene=bpy.context.scene
old=json.loads((BASE/'catalog.json').read_text(encoding='utf8'))
names=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']
mats=[bpy.data.materials[n] for n in names]
src=bpy.data.collections['01_制作组件_按设施拆分']; game=bpy.data.collections['02_游戏输出_独立资产包_v001']; game.name='02_游戏输出_独立资产包_v002'
display=bpy.data.collections['90_展示与验收_灯光相机']
categories={k:bpy.data.collections[v] for k,v in [('architecture','01_建筑结构'),('scaffold','02_脚手架及围网'),('facilities','03_施工设施'),('roof','04_屋顶施工构件')]}
WHITE=(9,9); CONCRETE=(9,7); GRAY=(9,5); STEEL=(9,4); DARK=(9,1); GOLD=(6,3); GREEN=(5,4); TEAL=(5,5); BLUE=(6,6); RED=(4,1); WOOD=(6,2); RUST=(5,2)
# Reuse audited geometry/UV helpers, without executing the earlier scene builder.
tree=ast.parse((R/'tools/blender/build_openworld_tower02_v001.py').read_text(encoding='utf8'))
nodes=[n for n in tree.body if isinstance(n,(ast.ClassDef,ast.FunctionDef)) and n.name in ['Part','col','rail','camera']]
exec(compile(ast.Module(body=nodes,type_ignores=[]),'<shared_geometry>','exec'))
catalog=[]
def signature(o):
 h=hashlib.sha256(); h.update(str(tuple(tuple(r) for r in o.matrix_world)).encode()); h.update(str(o.parent.name if o.parent else None).encode())
 if o.type=='MESH':
  for v in o.data.vertices: h.update(str(tuple(v.co)).encode())
  for p in o.data.polygons: h.update(str((tuple(p.vertices),p.material_index)).encode())
  for uv in o.data.uv_layers:
   for v in uv.data: h.update(str(tuple(v.uv)).encode())
  h.update(str([m.name for m in o.data.materials]).encode())
 h.update(str([(m.name,m.type) for m in o.modifiers]).encode()); h.update(str(o.animation_data).encode()); return h.hexdigest()
replace=[p for p in old['packages'] if p['category']=='roof' or p['slug'].startswith('crane_')]
replace_objects={n for p in replace for n in p['objects']}
locked={o.name:signature(o) for o in scene.objects if o.type=='MESH' and o.name not in replace_objects and not any(o.name.startswith(p['display_name']) for p in replace)}
(OUT/'qa/locked_before.json').write_text(json.dumps(locked,ensure_ascii=False,indent=2),encoding='utf8')
for p in replace:
 c=bpy.data.collections.get(p['collection'])
 if c:
  for o in list(c.objects): bpy.data.objects.remove(o,do_unlink=True)
  bpy.data.collections.remove(c)
 for o in list(src.objects):
  if o.name.startswith(p['display_name']): bpy.data.objects.remove(o,do_unlink=True)
for p in old['packages']:
 if p not in replace: catalog.append(p)
def finish(p):
 p.finish(); obj=bpy.data.objects[catalog[-1]['objects'][0]]; obj['version']='v002'; return obj
def beam(p,a,b,width=.15,depth=None,c=GOLD,m=0):
 a,b=Vector(a),Vector(b); w=(b-a).normalized(); u=w.cross(Vector((0,0,1)))
 if u.length<.01: u=w.cross(Vector((0,1,0)))
 u.normalize(); v=w.cross(u); depth=depth or width
 verts=[tuple(t+sx*u*width/2+sy*v*depth/2) for t in (a,b) for sx,sy in [(-1,-1),(1,-1),(1,1),(-1,1)]]
 p.poly(verts,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],c,m)
def ring(p,center,axis,radius,tube,c=STEEL,segments=32):
 axis=Vector(axis).normalized(); u=axis.cross(Vector((0,0,1)))
 if u.length<.01: u=axis.cross(Vector((0,1,0)))
 u.normalize(); v=axis.cross(u); center=Vector(center)
 pts=[center+radius*(math.cos(i*2*math.pi/segments)*u+math.sin(i*2*math.pi/segments)*v) for i in range(segments)]
 for a,b in zip(pts,pts[1:]+pts[:1]): p.rod(a,b,tube,c,0,8)
def bolt(p,position,axis=(0,-1,0),r=.09):
 v=Vector(position); a=Vector(axis); p.rod(v-a*.035,v+a*.075,r,STEEL,0,6); p.rod(v+a*.076,v+a*.095,r*.48,DARK,0,6)
def deck(p,x,y,z,w,d,c=GRAY):
 p.box((x,y,z),(w,d,.18),c)
 for yy in [y-d/2,y+d/2]: p.box((x,yy,z-.22),(w,.16,.38),GOLD,0)
 for xx in [x-w/2,x+w/2]: p.box((xx,y,z-.22),(.16,d,.38),GOLD,0)
def perimeter(p,x,y,z,w,d,gap=False):
 for a,b in [((x-w/2,y-d/2),(x+w/2,y-d/2)),((x+w/2,y-d/2),(x+w/2,y+d/2)),((x+w/2,y+d/2),(x-w/2,y+d/2)),((x-w/2,y+d/2),(x-w/2,y-d/2))]:
  if gap and a[1]==b[1] and a[1]<y: continue
  rail(p,a,b,z)
def ladder(p,x,y,z0,z1,w=.65):
 for dx in [-w/2,w/2]: beam(p,(x+dx,y,z0),(x+dx,y,z1),.07,c=STEEL)
 for k in range(int((z1-z0)/.28)+1): p.rod((x-w/2,y,z0+k*.28),(x+w/2,y,z0+k*.28),.028,STEEL)
def gusset(p,x,y,z,size=.4):
 p.box((x,y,z),(size,.065,size),GOLD,0)
 for dx in [-size*.28,size*.28]: bolt(p,(x+dx,y-.05,z),r=.045)
# Diverse exposed rebar columns. Concrete is narrower than cages, bars remain visible.
column_layout=[(-29,-16,3.5,.8),(-29,0,7.5,2.7),(-29,18,11.5,4),(-16,-16,5.5,1.5),(-16,0,8.7,3),(-16,18,10.2,3.8),(-3,-16,8,2),(-3,0,4.2,.7),(-3,18,12.2,4.6),(10,-16,4.5,1.3),(10,0,9.8,3.5),(10,18,7,2),(26,-16,6.5,2),(26,0,5,1.2),(26,18,10.8,4.2)]
for k,(x,y,h,concrete) in enumerate(column_layout):
 p=Part('roof_column_%02d'%k,'屋顶柱_%02d_错层钢筋笼'%k,'roof'); z=84.5; w=2.3 if k%3 else 2.7
 p.box((x,y,z+.12),(w+.7,w+.7,.24),GRAY)
 p.box((x,y,z+concrete/2),(w-.48,w-.48,concrete),CONCRETE)
 for side in [-1,1]:
  for j in range(5):
   t=-w/2+j*w/4; cap=h+[0,.18,-.12,.3,-.2][j]
   p.rod((x+t,y+side*w/2,z+.2),(x+t,y+side*w/2,z+cap),.052,RUST,0,8)
   if j not in [0,4]: p.rod((x+side*w/2,y+t,z+.2),(x+side*w/2,y+t,z+cap-.15),.052,STEEL,0,8)
 for j in range(int((h-.65)/.34)):
  zz=z+.25+j*.34
  for a,b in [((-w/2,-w/2),(w/2,-w/2)),((w/2,-w/2),(w/2,w/2)),((w/2,w/2),(-w/2,w/2)),((-w/2,w/2),(-w/2,-w/2))]: p.rod((x+a[0],y+a[1],zz),(x+b[0],y+b[1],zz),.036,STEEL)
  if j%3==0:
   p.rod((x-w/2,y,z+j*.34+.25),(x+w/2,y,z+j*.34+.25),.028,STEEL)
 if k%3!=0:
  fh=min(h-1,concrete+1.2)
  for side in [-1,1]:
   for j in range(4):
    t=-w/2+(j+.5)*w/4
    p.box((x+t,y+side*(w/2+.12),z+fh/2),(w/4-.035,.14,fh),WOOD if j%2 else DARK)
    p.box((x+side*(w/2+.12),y+t,z+fh/2),(.14,w/4-.035,fh),WOOD if j%2 else DARK)
   for t in [-w/2,-w/4,0,w/4,w/2]:
    beam(p,(x+t,y+side*(w/2+.24),z+.1),(x+t,y+side*(w/2+.24),z+fh),.12)
    beam(p,(x+side*(w/2+.24),y+t,z+.1),(x+side*(w/2+.24),y+t,z+fh),.12)
   for zz in [z+.7,z+fh-.4]:
    p.box((x,y+side*(w/2+.35),zz),(w+.8,.13,.18),GOLD,0)
    for dx in [-w*.35,w*.35]: bolt(p,(x+dx,y+side*(w/2+.45),zz),r=.07)
    p.box((x+side*(w/2+.35),y,zz),(.13,w+.8,.18),GOLD,0)
   p.rod((x+side*(w/2+2.2),y,z+.15),(x+side*(w/2+.25),y,z+fh-.3),.065,STEEL)
 finish(p)
# Three formwork islands with genuine open top wells, stepped platforms and supported catwalks.
for k,(x,y,w,d,h) in enumerate([(-20,7,8,7,6.4),(1,-6,8.5,6,3.4),(23,9,7,8,5)]):
 p=Part('roof_formwork_%d'%k,'屋顶核心模板_%d_多层作业岛'%k,'roof'); z=84.5
 for side in [-1,1]:
  p.box((x+side*(w/2-.25),y,z+h/2),(.5,d,h),DARK)
  p.box((x,y+side*(d/2-.25),z+h/2),(w,.5,h),DARK)
  for j in range(math.ceil(w/.7)):
   xx=x-w/2+(j+.5)*w/math.ceil(w/.7)
   p.box((xx,y+side*(d/2+.05),z+h/2),(.48,.12,h-.15),WOOD)
   beam(p,(xx,y+side*(d/2+.18),z),(xx,y+side*(d/2+.18),z+h),.12)
  for j in range(math.ceil(d/.7)):
   yy=y-d/2+(j+.5)*d/math.ceil(d/.7)
   p.box((x+side*(w/2+.05),yy,z+h/2),(.12,.48,h-.15),WOOD)
   beam(p,(x+side*(w/2+.18),yy,z),(x+side*(w/2+.18),yy,z+h),.12)
  for level in [.6,2,h-.35]:
   p.box((x,y+side*(d/2+.3),z+level),(w+.8,.18,.23),GOLD,0)
   p.box((x+side*(w/2+.3),y,z+level),(.18,d+.8,.23),GOLD,0)
   for j in range(int(w/1.2)+1): bolt(p,(x-w/2+j*1.2,y+side*(d/2+.43),z+level),r=.075)
  for dx in [-w/2,w/2]:
   p.rod((x+dx,y+side*(d/2+2.8),z+.1),(x+dx,y+side*(d/2+.4),z+h-.8),.10,STEEL)
   p.box((x+dx,y+side*(d/2+2.8),z+.07),(.6,.6,.14),GOLD,0)
 # Interior crossed rebar mats and distinct intermediate stair landings.
 for yy in range(int(d)-1): p.rod((x-w/2+.5,y-d/2+yy+.5,z+h-.5),(x+w/2-.5,y-d/2+yy+.5,z+h-.5),.045,STEEL)
 for xx in range(int(w)-1): p.rod((x-w/2+xx+.5,y-d/2+.5,z+h-.45),(x-w/2+xx+.5,y+d/2-.5,z+h-.45),.045,STEEL)
 for zz,extension in [(z+h*.5,1.4),(z+h,1.05)]:
  for side in [-1,1]:
   deck(p,x,y+side*(d/2+extension/2),zz,w+2*extension,extension,GRAY)
   rail(p,(x-w/2-extension,y+side*(d/2+extension)),(x+w/2+extension,y+side*(d/2+extension)),zz+.1)
   for dx in [-w/2-.5,w/2+.5]:
    beam(p,(x+dx,y+side*(d/2+.8),z),(x+dx,y+side*(d/2+.8),zz),.14,c=STEEL)
    beam(p,(x+dx,y+side*(d/2+.8),z+.2),(x+dx+(.9 if dx<0 else -.9),y+side*(d/2+.8),zz-.2),.10,c=STEEL)
 ladder(p,x-w/2-1,y,z,z+h+1)
 # Paired protruding rebar banks over the well lip.
 for side in [-1,1]:
  for j in range(9): p.rod((x-w/2+.5+j*(w-1)/8,y+side*(d/2-.25),z+h-1),(x-w/2+.5+j*(w-1)/8,y+side*(d/2-.25),z+h+1.1+.2*(j%3)),.046,STEEL)
 finish(p)
# Roof formwork beams and horizontal cage bays produce an unfinished storey silhouette.
for k,(x,y,z,w,d) in enumerate([(-22,18,90.0,15,4),(18,-15,87.5,15,4),(25,1,88.6,5,11),(-8,9,86.6,7,4)]):
 p=Part('roof_shoring_%02d'%k,'屋顶支模_%02d_梁笼及顶撑'%k,'roof')
 deck(p,x,y,z,w,d,GRAY)
 for xx in [-w/2+.5,0,w/2-.5]:
  for yy in [-d/2+.4,d/2-.4]:
   p.rod((x+xx,y+yy,84.65),(x+xx,y+yy,z-.4),.085,STEEL)
   p.box((x+xx,y+yy,84.6),(.5,.5,.12),GOLD,0)
   p.rod((x+xx,y+yy,85.5),(x+xx,y+yy,z-.4),.05,GOLD)
   p.box((x+xx,y+yy,z-.28),(.5,.4,.22),GOLD,0)
 for side in [-1,1]:
  rail(p,(x-w/2,y+side*d/2),(x+w/2,y+side*d/2),z+.1)
  beam(p,(x-w/2+.5,y+side*(d/2-.4),84.8),(x+w/2-.5,y+side*(d/2-.4),z-.3),.08,c=STEEL)
 # Beam mould trough, top left open.
 for side in [-1,1]: p.box((x,y+side*.8,z+.6),(w-.4,.13,1.1),WOOD)
 for yy in [-.55,0,.55]:
  for zz in [z+.3,z+1.05]: p.rod((x-w/2,y+yy,zz),(x+w/2,y+yy,zz),.06,STEEL)
 for j in range(int(w/.4)):
  xx=x-w/2+j*.4
  for a,b in [((xx,y-.6,z+.25),(xx,y+.6,z+.25)),((xx,y-.6,z+1.1),(xx,y+.6,z+1.1)),((xx,y-.6,z+.25),(xx,y-.6,z+1.1)),((xx,y+.6,z+.25),(xx,y+.6,z+1.1))]: p.rod(a,b,.035,STEEL)
 ladder(p,x+w/2+.25,y,84.5,z+1)
 finish(p)
# Organized material piles, distribution boxes, pallets, wheelbarrows and hoses.
for k,(x,y,kind) in enumerate([(-27,-8,'rebar'),(-18,-8,'boards'),(-27,10,'panel'),(3,20,'rebar'),(20,-6,'boards'),(29,-8,'plant'),(-4,3,'plant'),(5,-18,'panel')]):
 p=Part('roof_supply_%02d'%k,'屋顶材料_%02d_%s'%(k,kind),'roof'); z=84.5
 for dx in [-1.4,1.4]: p.box((x+dx,y,z+.13),(.3,2.7,.26),WOOD)
 for j in range(7): p.box((x,y-1.2+j*.4,z+.31),(3.6,.32,.12),WOOD)
 if kind=='rebar':
  for row in range(3):
   for j in range(12-row): p.rod((x-3,y-1+j*.18,z+.5+row*.16),(x+3,y-1+j*.18,z+.5+row*.16),.065,RUST)
  for dx in [-1.7,1.7]: ring(p,(x+dx,y,z+.65),(1,0,0),1.1,.035,DARK,16)
 elif kind in ['boards','panel']:
  for j in range(8):
   p.box((x,y,z+.48+j*.16),(4.7,1.8,.13),WOOD if kind=='boards' else DARK)
   if kind=='panel':
    for dx in [-2,-.7,.7,2]: p.box((x+dx,y,z+.55+j*.16),(.08,1.8,.08),GOLD,0)
 else:
  p.box((x,y,z+1.2),(2.7,1.6,1.7),RED)
  p.box((x,y-.84,z+1.3),(1.5,.05,.8),DARK,2)
  for dx in [-1,1]:
   p.rod((x+dx,y-.8,z+.55),(x+dx,y+.8,z+.55),.3,DARK,1,16)
  for j in range(8): p.box((x+1.37,y-.6+j*.17,z+1.15),(.03,.07,.75),STEEL,0)
  ring(p,(x+2.2,y,84.59),(0,0,1),.8,.055,DARK)
 finish(p)
# Detailed crane geometry built in local coordinates; all boxes, windows and fittings rotate together.
for idx,(cx,cy,base,top,angle) in enumerate([(-40,-18,0,112,10),(11,12,84.5,125,165),(39,18,0,108,-35)]):
 theta=math.radians(angle)
 def crane_finish(p):
  p.v=[(cx+x*math.cos(theta)-y*math.sin(theta),cy+x*math.sin(theta)+y*math.cos(theta),z) for x,y,z in p.v]; finish(p)
 def cp(slug,label): return Part('crane_%02d_%s'%(idx,slug),'塔吊%d_%s'%(idx+1,label),'facilities')
 p=cp('mast','标准节塔身_螺栓梯笼')
 p.box((0,0,base+.4),(5.4,5.4,.8),CONCRETE)
 for x in [-1.2,1.2]:
  for y in [-1.2,1.2]:
   beam(p,(x,y,base+.8),(x,y,top-3),.28,c=GOLD)
   p.box((x,y,base+.9),(.7,.7,.22),GOLD,0)
   for dx in [-.22,.22]: bolt(p,(x+dx,y,base+1.03),axis=(0,0,1),r=.09)
 count=math.ceil((top-base-3.8)/3.2)
 for j in range(count):
  z=base+.8+j*(top-base-3.8)/count; zz=base+.8+(j+1)*(top-base-3.8)/count
  for a,b in [((-1.2,-1.2),(1.2,-1.2)),((1.2,-1.2),(1.2,1.2)),((1.2,1.2),(-1.2,1.2)),((-1.2,1.2),(-1.2,-1.2))]:
   beam(p,(*a,z),(*b,z),.16); beam(p,(*a,z+.16),(*b,zz-.16),.14)
  for x in [-1.2,1.2]:
   for y in [-1.2,1.2]:
    p.box((x,y,z),(.4,.4,.38),GOLD,0)
    bolt(p,(x,y-.23,z-.1),r=.075); bolt(p,(x,y-.23,z+.1),r=.075)
 ladder(p,0,.4,base+.8,top-2.5)
 for z in range(int(base+4),int(top-3),12):
  for a in range(8):
   theta2=math.pi*a/7; xx=.8*math.cos(theta2); yy=.4+.8*math.sin(theta2)
   p.rod((xx,yy,z-1),(xx,yy,z+1),.027,STEEL)
  ring(p,(0,.4,z),(0,0,1),.8,.035,STEEL,16)
 if base==0:
  for zz in [25,48,71]:
   deck(p,0,0,zz,4.2,4.2); perimeter(p,0,0,zz+.1,4.2,4.2)
   # Tie back to actual building direction, transformed to crane coordinates.
   wx=max(-34,min(34,cx))-cx; wy=0
   tx=wx*math.cos(theta)+wy*math.sin(theta); ty=-wx*math.sin(theta)+wy*math.cos(theta)
   for dy in [-1.2,1.2]: beam(p,(0,dy,zz),(tx,ty,zz),.23)
 crane_finish(p)
 p=cp('slew_cab','回转总成_折面驾驶室')
 deck(p,0,0,top-3,6.8,5.6); perimeter(p,0,0,top-2.9,6.8,5.6)
 # Solid curved bearing with pinion housings and circumferential bolt heads.
 for zz,rad in [(top-2.6,1.6),(top-2.3,1.75),(top-2,1.6)]: ring(p,(0,0,zz),(0,0,1),rad,.15,STEEL,48)
 # Load-bearing pedestal links the slew bearing to the upper hinge crosshead.
 p.rod((0,.35,top-1.95),(0,.35,top+.3),1.02,GOLD,0,24)
 for x in [-1,1]:
  for y in [-.65,1.35]: beam(p,(x,y,top-1.9),(x,y,top+.35),.2,c=GOLD)
 for j in range(24):
  t=j*math.pi/12; bolt(p,(1.75*math.cos(t),1.75*math.sin(t),top-2.1),axis=(0,0,1),r=.08)
 for x in [-1.7,1.7]:
  p.rod((x,.8,top-2.5),(x,.8,top-1.8),.35,RED,0,16)
  p.box((x,.8,top-2.55),(.9,.9,.2),GOLD,0)
 # Cab side section bulges forward, like reference; opaque tinted windows with structural mullions.
 x0=.8; y0=-1.45; zz=top-2.75
 profile=[(-1.5,.25),(1.25,.25),(1.6,.9),(1.65,2.3),(1.25,3),(-1.5,3)]
 verts=[(x0+x,y0+y,zz+z) for y in [-1.05,1.05] for x,z in profile]
 n=len(profile); p.poly(verts,[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)],WHITE)
 # Two large side windows and bulged three-pane front windshield.
 for side in [-1,1]:
  yy=y0+side*1.065
  for xa,xb in [(-1.32,-.12),(.05,1.22)]:
   p.poly([(x0+xa,yy,zz+.65),(x0+xb,yy,zz+.65),(x0+xb+.12,yy,zz+2.65),(x0+xa,yy,zz+2.65)],[(0,1,2,3)],(3,5),2)
  beam(p,(x0-.02,yy-side*.02,zz+.55),(x0-.02,yy-side*.02,zz+2.8),.08,c=WHITE,m=1)
  p.box((x0-1.22,yy-side*.02,zz+.43),(.22,.12,.07),DARK,0)
 for (xa,za),(xb,zb) in [((1.43,.58),(1.59,.88)),((1.605,.98),(1.644,2.21)),((1.62,2.35),(1.30,2.91))]:
  p.poly([(x0+xa+.03,y0-.91,zz+za),(x0+xa+.03,y0+.91,zz+za),(x0+xb+.03,y0+.91,zz+zb),(x0+xb+.03,y0-.91,zz+zb)],[(0,1,2,3)],(3,5),2)
  beam(p,(x0+xa+.06,y0-.96,zz+za),(x0+xa+.06,y0+.96,zz+za),.05,c=WHITE,m=1)
  beam(p,(x0+xa+.06,y0,zz+za),(x0+xb+.06,y0,zz+zb),.045,c=DARK,m=1)
 beam(p,(x0+1.68,y0,zz+.9),(x0+1.68,y0+.6,zz+1.7),.035,c=DARK)
 p.box((x0,y0,zz+3.12),(3.25,2.35,.22),WHITE)
 for j in range(7): p.box((x0-1.53,y0-.8+j*.25,zz+1.6),(.03,.12,.7),STEEL)
 # Upper hinge crosshead and heavy pivots.
 p.box((0,0,top+.6),(4,3,.6),GOLD,0)
 for x in [-1.4,1.4]:
  p.box((x,0,top+.95),(.55,3.2,.7),GOLD,0)
  for y in [-1.7,1.7]: p.rod((x,y-.12,top+.95),(x,y+.12,top+.95),.26,STEEL,0,16)
 crane_finish(p)
 p=cp('jib','工作臂_双弦桁架检修走道')
 z=top+1
 for yy in [-1.15,1.15]:
  p.box((16,yy,z),(32,.22,.42),GOLD,0); p.box((16,yy,z+1.45),(32,.18,.18),GOLD,0)
  rail(p,(0,yy),(32,yy),z+1.48)
 for x in range(0,32,2):
  for yy in [-1.15,1.15]:
   beam(p,(x,yy,z+.2),(x+1,yy,z+1.45),.16); beam(p,(x+1,yy,z+1.45),(x+2,yy,z+.2),.16)
   gusset(p,x,yy,z+.16,.3)
  beam(p,(x,-1.15,z),(x,1.15,z),.16)
  if x%8==0:
   for yy in [-1.15,1.15]:
    p.box((x,yy,z),(.3,.4,.6),GOLD,0)
    for dz in [-.18,.18]: bolt(p,(x,yy-.23,z+dz),r=.08)
 # Narrow open grating floor rather than a solid slab.
 for j in range(161): p.box((j*.2,0,z+.27),(.045,1.65,.045),STEEL,0)
 for yy in [-.8,-.4,0,.4,.8]: beam(p,(0,yy,z+.27),(32,yy,z+.27),.035,c=STEEL)
 for yy in [-.62,.62]: p.box((16,yy,z-.28),(32,.11,.14),STEEL,0)
 p.box((32,0,z),(.32,2.7,.55),GOLD,0)
 for yy in [-1.3,1.3]:
  p.rod((32,yy,z+2.45),(32,yy,z+2.8),.055,STEEL)
  p.rod((32,yy,z+2.8),(32,yy,z+3.04),.08,RED,1,12)
 crane_finish(p)
 p=cp('counter_jib','平衡臂_配重块卷扬机电柜')
 deck(p,-7.3,0,top+1,14.6,3.2,GRAY); perimeter(p,-7.3,0,top+1.1,14.6,3.2)
 for xx in [-14,-11,-8,-5,-2]:
  for yy in [-1.4,1.4]: beam(p,(xx,yy,top+.8),(xx+2.5,yy,top-.1),.18)
 for x in [-13.7,-12.5,-11.3]:
  for y in [-.82,.82]:
   for level in range(3):
    p.box((x,y,top-.15-level*.8),(1.13,1.56,.74),CONCRETE)
    if level==0: ring(p,(x,y,top+.32),(0,1,0),.16,.035,STEEL,12)
 p.box((-8,0,top+2),(2.8,2.3,1.8),WHITE)
 for y in [-1.17,1.17]:
  for j in range(12): p.box((-8,y,top+1.3+j*.11),(2.15,.03,.035),STEEL)
  for x in [-9.1,-6.9]: bolt(p,(x,y,top+2.6),r=.06)
 p.box((-4.8,0,top+1.5),(2.4,2.2,.28),GOLD,0)
 p.rod((-4.8,-.7,top+2),(-4.8,.7,top+2),.48,RED,0,24)
 for j in range(10): ring(p,(-4.8,-.65+j*.14,top+2),(0,1,0),.49,.033,STEEL,20)
 p.rod((-4.8,.8,top+2),(-4.8,1.5,top+2),.3,RED,0,20)
 crane_finish(p)
 p=cp('apex','塔帽_拉杆铰接销轴')
 for y in [-.95,.95]:
  beam(p,(-1.4,y,top+1.4),(0,y*.5,top+10),.32)
  beam(p,(1.4,y,top+1.4),(0,y*.5,top+10),.32)
  for j in range(4):
   zz=top+2+j*1.7; width=1.2*(1-(zz-top-1.4)/8.6)
   beam(p,(-width,y*(1-(zz-top)*.04),zz),(width,y*(1-(zz-top)*.04),zz+.8),.14)
 p.box((0,0,top+10),(1,1.6,.7),GOLD,0)
 for y in [-.95,.95]:
  p.rod((0,y-.12,top+10),(0,y+.12,top+10),.25,STEEL,0,20)
  for endx,endz in [(-12,top+1.5),(15,top+2.6),(29,top+2.6)]:
   start=Vector((0,y*.6,top+10)); end=Vector((endx,y,endz)); vec=(end-start).normalized()
   p.rod(start,end,.07,GOLD,0,10)
   for a in [.8,(end-start).length-.8]: p.rod(start+vec*a,start+vec*(a+.55),.115,STEEL,0,12)
   ring(p,end,(0,1,0),.18,.07,STEEL,16)
 crane_finish(p)
 p=cp('trolley','变幅小车_行走轮电机')
 tx=23; z=top+.65
 deck(p,tx,0,z-.8,3.4,3.5,GRAY); perimeter(p,tx,0,z-.7,3.4,3.5)
 for x in [tx-1.1,tx+1.1]:
  for y in [-1,1]:
   p.rod((x,y-.12,z+.18),(x,y+.12,z+.18),.28,DARK,1,20)
   p.rod((x,y-.16,z+.18),(x,y+.16,z+.18),.13,STEEL,0,16)
   beam(p,(x,y,z-.7),(x,y,z+.1),.15)
 p.box((tx,0,z+.05),(1.65,1.9,1.2),WHITE)
 for j in range(8): p.box((tx-.85,-.6+j*.17,z+.15),(.03,.07,.7),STEEL)
 p.rod((tx+.8,0,z+.2),(tx+1.6,0,z+.2),.38,RED,0,20)
 for x in [tx-.55,tx+.55]:
  ring(p,(x,0,z-.2),(0,1,0),.34,.06,STEEL,24)
 crane_finish(p)
 p=cp('hook','滑轮组_钢索及锻造吊钩')
 tx=23; hz=top-17
 for x in [tx-.55,tx+.55]:
  for y in [-.28,.28]: p.rod((x,y,top+.2),(x,y,hz+.25),.029,DARK,0,8)
 for y in [-.38,.38]:
  verts=[(tx+x,y+dy,hz+z) for dy in [-.1,.1] for x,z in [(-.85,.55),(.85,.55),(.68,-.35),(0,-1),(-.68,-.35)]]
  p.poly(verts,[(4,3,2,1,0),(5,6,7,8,9)]+[(i,(i+1)%5,(i+1)%5+5,i+5) for i in range(5)],GOLD,0)
  for x in [-.55,.55]: bolt(p,(tx+x,y-.12,hz+.1),r=.16)
 for x in [-.5,.5]:
  ring(p,(tx+x,0,hz+.1),(0,1,0),.48,.09,STEEL,24)
 p.rod((tx,0,hz-.7),(tx,0,hz-1.35),.19,STEEL,0,16)
 # Thick J-shaped hook as a smooth segmented sweep, genuinely open mouth.
 pts=[(tx+.48*math.cos(t),0,hz-1.85+.58*math.sin(t)) for t in [math.radians(90+i*280/24) for i in range(25)]]
 for j,(a,b) in enumerate(zip(pts,pts[1:])): p.rod(a,b,.16 if j<18 else .16*(1-(j-18)*.11),STEEL,0,12)
 p.rod((tx+.09,0,hz-1.35),(tx+.47,0,hz-1.75),.04,GOLD)
 crane_finish(p)
 print('CRANE_COMPLETE',idx,flush=True)
# Keep an actual warning light using the fourth shared role, on top of the rear tall cage.
p=Part('roof_warning','屋顶警示灯座','roof'); p.box((-3,18,96.9),(.6,.6,.1),STEEL,0); finish(p)
c=bpy.data.collections[catalog[-1]['collection']]
me=bpy.data.meshes.new('警示灯发光网格'); me.from_pydata([(-3.1,17.9,97),(-2.9,17.9,97),(-2.9,18.1,97),(-3.1,18.1,97)],[],[(0,1,2,3)]); me.materials.append(mats[3]); uv=me.uv_layers.new(name='PaletteUV'); uv.active_render=True
for i,xy in enumerate([(.42,.12),(.48,.12),(.48,.18),(.42,.18)]): uv.data[i].uv=xy
o=bpy.data.objects.new('屋顶警示灯_柔和自发光',me); c.objects.link(o); catalog[-1]['objects'].append(o.name); catalog[-1]['emissive']=True; catalog[-1]['material_roles']=names
# Frozen scene lighting and existing cameras are retained for valid comparisons.
camera('塔吊机械细节',(-12,-54,137),(-32,-17,112),37)
camera('屋顶结构近景',(78,-108,148),(0,0,88),79)
camera('塔吊吊钩近景',(-8,-45,102),(-17.35,-14,96),12)
camera('塔吊完整机械总览',(-6,-82,141),(-31,-16,108),57)
scene['asset_version']='v002'; scene['roof_column_heights_m']=[v[2] for v in column_layout]
locked_after={name:signature(bpy.data.objects[name]) for name in locked}; assert locked_after==locked,'Locked lower structure changed'
(OUT/'qa/scope_lock.json').write_text(json.dumps(dict(passed=True,locked_meshes=len(locked),before=locked,after=locked_after,editable_scope=['roof construction packages','three crane assemblies'],unchanged=['lower floors','70x50 footprint','gray roof slab','facade','elevator','existing reference cameras and lights']),ensure_ascii=False,indent=2),encoding='utf8')
blend=OUT/'塔2_施工高楼_70x50m_v002.blend'
# Refresh exact package bounds, names, paths and version after all edits.
for info in catalog:
 objs=[bpy.data.objects[n] for n in info['objects']]; coords=[o.matrix_world@Vector(corner) for o in objs for corner in o.bound_box]
 mn=[min(v[j] for v in coords) for j in range(3)]; mx=[max(v[j] for v in coords) for j in range(3)]
 info.update(version='v002',source_blend=blend.name,bounds_min=mn,bounds_max=mx,dimensions=[mx[j]-mn[j] for j in range(3)])
 directory=OUT/'component_packages'/info['category']/info['slug']; directory.mkdir(parents=True,exist_ok=True); (directory/'asset_manifest.json').write_text(json.dumps(info,ensure_ascii=False,indent=2),encoding='utf8')
old['packages']=catalog; old['version']='v002'; old['column_heights_m']=[v[2] for v in column_layout]; old['source_blend']=blend.name
(OUT/'catalog.json').write_text(json.dumps(old,ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'package_tree.txt').write_text('\n'.join(i['category']+'/'+i['slug']+' — '+i['display_name'] for i in catalog),encoding='utf8')
for mesh in list(bpy.data.meshes):
 if mesh.users==0: bpy.data.meshes.remove(mesh)
scene.camera=bpy.data.objects['参考镜头_全景']; scene.cycles.samples=40
bpy.ops.wm.save_as_mainfile(filepath=str(blend))
print('V002_SAVED',len(catalog),'PACKAGES',flush=True)
for num,name in enumerate(['参考镜头_全景','屋顶细节','屋顶结构近景','塔吊机械细节','塔吊吊钩近景','俯视结构','背面完整性','塔吊完整机械总览']):
 scene.camera=bpy.data.objects[name]; scene.render.filepath=str(OUT/'previews'/('%02d_'%num+name+'.png')); bpy.ops.render.render(write_still=True); print('RENDERED',name,flush=True)
scene.camera=bpy.data.objects['参考镜头_全景']; bpy.ops.wm.save_as_mainfile(filepath=str(blend))
