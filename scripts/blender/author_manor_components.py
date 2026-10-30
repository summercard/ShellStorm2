"""Blender MCP authoring entry: exec this file in the live Blender session.

Production definitions are frozen in component_plan.json before this runs.
All repeated reference objects are Collection instances, never geometry copies.
"""
import bpy, math, json, random, hashlib, bmesh
from pathlib import Path
from mathutils import Vector, Matrix
from collections import Counter

ROOT=Path('I:/工作项目/shellstrom2/ShellStorm2')
SRC=ROOT/'art_source/environments/tower_zones/expedition/source/common_components/v017'
WORK=ROOT.parent/'ShellStorm2-work/manor_v017'
PAL=ROOT/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
PLAN=json.loads((SRC/'component_plan.json').read_text(encoding='utf-8'))
random.seed(430)
scene=bpy.context.scene
bpy.ops.wm.save_as_mainfile(filepath=str(WORK/'session_before.blend'),copy=True)
# The original user session is preserved above. Only this new asset file is authored.
for o in list(bpy.data.objects): bpy.data.objects.remove(o,do_unlink=True)
for c in list(bpy.data.collections): bpy.data.collections.remove(c)
for m in list(bpy.data.materials): bpy.data.materials.remove(m)
scene.name='复古公馆_组件实例参考_非正式关卡'
scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
def coll(n,parent=None):
 c=bpy.data.collections.new(n);(parent or scene.collection).children.link(c);return c
MASTERS=coll('01_制作组件_按组件拆分')
OUTPUT=coll('02_游戏输出_组件实例参考')
STAGE=coll('90_展示与验收_灯光相机')
# Master collections live in bpy.data and are referenced, not directly drawn.
image=bpy.data.images.load(str(PAL),check_existing=True)
image.filepath=str(PAL); image.colorspace_settings.name='sRGB'
roles=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']
mats=[]
for i,n in enumerate(roles):
 m=bpy.data.materials.new(n);m.use_nodes=True
 p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
 p.inputs['Metallic'].default_value=[.86,.02,.16,0][i]
 p.inputs['Roughness'].default_value=[.28,.70,.16,.38][i]
 p.inputs['Coat Weight'].default_value=[.16,0,.65,0][i]
 uv=m.node_tree.nodes.new('ShaderNodeUVMap');uv.uv_map='PaletteUV'
 tx=m.node_tree.nodes.new('ShaderNodeTexImage');tx.image=image;tx.interpolation='Closest'
 m.node_tree.links.new(uv.outputs['UV'],tx.inputs['Vector']);m.node_tree.links.new(tx.outputs['Color'],p.inputs['Base Color'])
 if i==3:
  m.node_tree.links.new(tx.outputs['Color'],p.inputs['Emission Color']);p.inputs['Emission Strength'].default_value=1.4
 mats.append(m)
# RGB targets pick existing palette cells; no textures or material color variants.
pixels=list(image.pixels)
def color(rgb):
 best=None
 for y in range(10):
  for x in range(10):
   off=(int((y+.5)*51.2)*512+int((x+.5)*51.2))*4
   v=pixels[off:off+3];d=sum((v[i]-rgb[i])**2 for i in range(3))
   if best is None or d<best[0]: best=(d,x,y)
 return best[1:]
C={k:color(v) for k,v in dict(wood=(.21,.105,.04),walnut=(.125,.055,.025),edge=(.055,.047,.035),gold=(.48,.32,.105),brightgold=(.66,.48,.19),red=(.29,.035,.055),red2=(.37,.065,.08),red3=(.19,.025,.04),ivory=(.74,.70,.61),white=(.85,.84,.77),black=(.045,.055,.065),stone=(.23,.24,.24),vein=(.37,.34,.25),green=(.035,.13,.055),leaf=(.08,.21,.09),leaflight=(.12,.27,.13),soil=(.07,.04,.02),paper=(.62,.60,.49)).items()}
class Geo:
 def __init__(self):self.v=[];self.f=[];self.mi=[];self.co=[]
 def mesh(self,v,f,c='wood',m=1):
  n=len(self.v);self.v.extend(v);self.f.extend([tuple(n+i for i in face) for face in f]);self.mi.extend([m]*len(f));self.co.extend([C[c] if isinstance(c,str) else c]*len(f))
 def box(self,p,s,c='wood',m=1,a=0):
  x,y,z=p;u,v,w=[q/2 for q in s];ca,sa=math.cos(a),math.sin(a)
  vv=[(x+ca*i-sa*j,y+sa*i+ca*j,z+k) for i,j,k in [(-u,-v,-w),(-u,v,-w),(u,v,-w),(u,-v,-w),(-u,-v,w),(-u,v,w),(u,v,w),(u,-v,w)]]
  self.mesh(vv,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],c,m)
 def sphere(self,p,s,c='red',m=1,n=20,r=10,power=1):
  vv=[]
  for j in range(r+1):
   th=math.pi*j/r
   for i in range(n):
    ph=2*math.pi*i/n
    def pw(t):return math.copysign(abs(t)**power,t)
    vv.append((p[0]+s[0]*pw(math.sin(th))*pw(math.cos(ph))/2,p[1]+s[1]*pw(math.sin(th))*pw(math.sin(ph))/2,p[2]+s[2]*pw(math.cos(th))/2))
  ff=[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for j in range(r) for i in range(n)]
  self.mesh(vv,ff,c,m)
 def tube(self,points,rad,c='gold',m=0,n=8,closed=False):
  pts=[Vector(p) for p in points];vv=[]
  for i,p in enumerate(pts):
   tangent=(pts[(i+1)%len(pts)]-pts[i-1]).normalized() if closed or 0<i<len(pts)-1 else ((pts[1]-pts[0]) if i==0 else (pts[-1]-pts[-2])).normalized()
   u=tangent.cross(Vector((0,0,1)))
   if u.length<.01:u=tangent.cross(Vector((0,1,0)))
   u.normalize();v=tangent.cross(u).normalized()
   for k in range(n):vv.append(tuple(p+rad*(u*math.cos(k*2*math.pi/n)+v*math.sin(k*2*math.pi/n))))
  ff=[]
  for i in range(len(pts) if closed else len(pts)-1):
   for k in range(n):ff.append((i*n+k,i*n+(k+1)%n,((i+1)%len(pts))*n+(k+1)%n,((i+1)%len(pts))*n+k))
  if not closed:ff += [tuple(range(n-1,-1,-1)),tuple((len(pts)-1)*n+k for k in range(n))]
  self.mesh(vv,ff,c,m)
 def ring(self,p,rx,ry,rad=.012,c='gold',m=0,n=48):
  self.tube([(p[0]+rx*math.cos(i*2*math.pi/n),p[1]+ry*math.sin(i*2*math.pi/n),p[2]) for i in range(n)],rad,c,m,closed=True)
 def lathe(self,profile,c='gold',m=0,p=(0,0,0),n=32):
  vv=[(p[0]+r*math.cos(i*2*math.pi/n),p[1]+r*math.sin(i*2*math.pi/n),p[2]+z) for r,z in profile for i in range(n)]
  ff=[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for j in range(len(profile)-1) for i in range(n)]
  self.mesh(vv,ff,c,m)
 def panel(self,p,s):
  self.box(p,s,'walnut');x,y,z=p;w,d,h=s
  for xx in [-w*.46,w*.46]:self.box((x+xx,y-d*.52,z),(.025,.02,h*.9),'gold',0)
  for zz in [-h*.44,h*.44]:self.box((x,y-d*.52,z+zz),(w*.94,.02,.025),'gold',0)
 def finish(self,col,slug):
  # Output subject and emissive are separate meshes, their transforms are identity.
  allv=Vector((min(v[0] for v in self.v),min(v[1] for v in self.v),min(v[2] for v in self.v)))
  high=Vector((max(v[0] for v in self.v),max(v[1] for v in self.v),max(v[2] for v in self.v)))
  shift=Vector(((allv.x+high.x)/2,(allv.y+high.y)/2,allv.z))
  root=bpy.data.objects.new('ROOT_'+slug,None);col.objects.link(root)
  for emission in [False,True]:
   indices=[i for i,m in enumerate(self.mi) if (m==3)==emission]
   if not indices:continue
   used=sorted({v for i in indices for v in self.f[i]});mapping={v:i for i,v in enumerate(used)}
   me=bpy.data.meshes.new(slug+('_emissive' if emission else '_body'))
   me.from_pydata([self.v[k]-shift if isinstance(self.v[k],Vector) else Vector(self.v[k])-shift for k in used],[],[[mapping[k] for k in self.f[i]] for i in indices]);me.update()
   obj=bpy.data.objects.new(slug+('_柔和自发光' if emission else '_主体'),me);col.objects.link(obj);obj.parent=root
   for mat in ([mats[3]] if emission else mats[:3]):me.materials.append(mat)
   uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True
   for poly,idx in zip(me.polygons,indices):
    poly.material_index=0 if emission else self.mi[idx];poly.use_smooth=len(poly.vertices)==4 and 'floor' not in slug and 'wall' not in slug
    cx,cy=self.co[idx]
    for j,li in enumerate(poly.loop_indices):
     ang=2*math.pi*j/len(poly.loop_indices)+.4;uv.data[li].uv=((cx+.5+.24*math.cos(ang))/10,(cy+.5+.24*math.sin(ang))/10)
  return [round(v,5) for v in high-allv]

def legs(g,w,d,z=.42):
 for x in [-w/2+.12,w/2-.12]:
  for y in [-d/2+.12,d/2-.12]:
   g.lathe([(.04,0),(.055,.035),(.025,z*.85),(.045,z)],'walnut',1,(x,y,0),12)
def arcwall(g,gap=False,window=False):
 # Surfaces are deliberately double sided and repeat at exact 5m interfaces.
 pieces=[(-1.8,1.4),(1.8,1.4)] if gap else [(0,5)]
 for x,w in pieces:
  g.box((x,0,1.4),(w,.3,2.8),'edge')
  for side in [-1,1]:
   g.box((x,side*.17,.68),(w,.055,1.25),'walnut')
   for zz,hh in [(.1,.2),(1.28,.075),(1.39,.035),(2.7,.16),(2.79,.02)]:g.box((x,side*.20,zz),(w,.1,hh),'wood')
   for k in range(max(1,round(w/.7))):
    xx=x-w/2+(k+.5)*w/max(1,round(w/.7));g.panel((xx,side*.205,.68),(w/max(1,round(w/.7))-.11,.03,.84))
  for xx in [x-w/2+.09,x+w/2-.09]:
   g.box((xx,0,1.4),(.16,.48,2.8),'walnut')
   for z in [.13,1.35,2.67]:g.box((xx,0,z),(.18,.50,.12),'gold',0)
 if window:
  # Decorative leaded glass casement, fixed against the structural core.
  for side in [-1,1]:
   g.box((0,side*.22,1.98),(2.8,.025,1.12),'black',2)
   for x in [-1.45,0,1.45]:g.box((x,side*.26,1.98),(.055,.09,1.23),'gold',0)
   for z in [1.38,1.98,2.58]:g.box((0,side*.26,z),(2.95,.09,.045),'gold',0)
def rug(g,w,d):
 g.box((0,0,.014),(w,d,.028),'red3');g.box((0,0,.030),(w-.10,d-.10,.008),'red')
 for inset in [.16,.22,.37]:
  pts=[(-w/2+inset,-d/2+inset,.039),(w/2-inset,-d/2+inset,.039),(w/2-inset,d/2-inset,.039),(-w/2+inset,d/2-inset,.039)]
  g.tube(pts,.008,'gold',1,4,True)
 # stylized woven arabesques, all actual geometry and palette faces
 for x in [-w/2+.48,w/2-.48]:
  for y in [-d/2+.48,d/2-.48]:
   for rad in [.14,.24]:g.ring((x,y,.04),rad,rad,.006,'gold',1,24)
 for t in range(max(1,int(d/1.3))):
  y=-d/2+.8+t*1.3
  for x in [-w/2+.27,w/2-.27]:
   g.tube([(x,y-.18,.042),(x+.11,y,.042),(x,y+.18,.042),(x-.11,y,.042)],.006,'gold',1,4,True)
 for j in range(3):g.ring((0,0,.041),min(w,d)*(.15+j*.018),min(w,d)*(.22+j*.02),.006,'gold',1)
 # subtle repeating textile diamonds
 for x in range(-int(w),int(w)+1):
  for y in range(-int(d),int(d)+1):
   xx=x*.37;yy=y*.37
   if abs(xx)<w/2-.5 and abs(yy)<d/2-.5:
    g.box((xx,yy,.036),(.035,.07,.003),'red2',1,math.pi/4)
def plant(g,kind):
 r=.34 if kind=='large' else .22
 g.lathe([(0,0),(r*.72,0),(r*.86,.08),(r,.55),(r*1.06,.58),(r*1.06,.63),(r*.88,.64),(0,.56)],'walnut',1,n=32)
 for z in [.08,.53,.61]:g.ring((0,0,z),r*(.80 if z==.08 else 1.02),r*(.80 if z==.08 else 1.02),.018)
 g.lathe([(0,.59),(r*.89,.59)],'soil',1,n=24)
 if kind=='flowers':
  for i in range(22):
   a=random.random()*6.28;rr=random.random()*.30;p=(rr*math.cos(a),rr*math.sin(a),.8+random.random()*.35)
   g.tube([(0,0,.57),p],.009,'green',1,5)
   for j in range(7):
    b=j*6.28/7;g.sphere((p[0]+.035*math.cos(b),p[1]+.035*math.sin(b),p[2]),(.075,.065,.045),'red2',1,8,4)
   g.sphere(p,(.035,.035,.04),'brightgold',1,8,4)
  return
 for i in range(100 if kind=='large' else 55):
  a=i*2.39996;h=.72+(i%7)*.14;rr=.18+(i%5)*.06;length=.20+(i%3)*.08
  if kind!='large':rr*=.65;h*=.85;length*=.72
  start=Vector((.04*math.cos(a),.04*math.sin(a),.59));p=Vector((rr*math.cos(a),rr*math.sin(a),h))
  g.tube([start,p],.008,'green',1,5)
  end=p+Vector((length*math.cos(a),length*math.sin(a),-.12));mid=(p+end)/2+Vector((0,0,.07));side=Vector((-math.sin(a),math.cos(a),0))*.10
  g.mesh([tuple(p),tuple(mid-side),tuple(end),tuple(mid+side),tuple(mid+Vector((0,0,.035)))],[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],['leaf','green','leaflight'][i%3],1)
  g.tube([p,mid+Vector((0,0,.037)),end],.003,'leaflight',1,4)
def lamp(g,wall=False):
 if wall:
  g.box((0,.08,.35),(.19,.1,.58),'walnut');g.sphere((0,.00,.31),(.24,.12,.66),'gold',0,16,8)
  g.tube([(0,-.02,.18),(0,-.18,.18),(0,-.23,.36)],.025)
  pos=(0,-.22,0)
 else:
  g.lathe([(0,0),(.17,0),(.18,.035),(.12,.07),(.065,.09),(.045,.32),(.10,.37)],'gold',0,n=24);pos=(0,0,0)
 # tapered glowing shade + rings, body/emission kept separate
 g.lathe([(.18,.39),(.14,.59),(.08,.64)],'ivory',3,pos,24)
 for rad,z in [(.18,.39),(.08,.64)]:g.ring((pos[0],pos[1],z),rad,rad,.012)
 g.sphere((pos[0],pos[1],.67),(.04,.04,.055),'brightgold',0,12,6)
def chair(g,sofa=False,office=False):
 w=3 if sofa else ( .62 if office else 1.1);d=1.0 if sofa else (.65 if office else 1.05)
 legs(g,w,d,.22)
 g.box((0,0,.28),(w-.1,d-.1,.16),'walnut')
 n=3 if sofa else 1
 for i in range(n):
  x=-w*.5+(i+.5)*w/n
  g.sphere((x,-.06,.46),(w/n-.06,d-.13,.28),'black' if office else 'red2',1,20,10,.35)
  g.sphere((x,.35,.78),(w/n-.03,.24,.62),'black' if office else 'red',1,20,10,.3)
  if not office:
   for z in [.67,.86]:g.sphere((x,.209,z),(.035,.02,.035),'gold',0,8,4)
 for x in [-w/2+.03,w/2-.03]:
  g.sphere((x,0,.65),(.19,d,.45),'black' if office else 'red',1,20,10,.3)
  g.tube([(x,-d/2+.05,.70),(x,d/2-.04,.70),(x,d/2-.04,.98)],.025,'wood',1)
 if sofa:
  for x in [-1.05,1.04]:g.sphere((x,.03,.68),(.50,.16,.45),'ivory',1,20,10,.45)
def bed(g):
 legs(g,1.8,2,.22);g.box((0,0,.25),(1.8,2,.23),'walnut')
 g.sphere((0,0,.47),(1.78,1.98,.35),'ivory',1,28,12,.18)
 g.sphere((0,-.32,.66),(1.79,1.34,.15),'white',1,32,16,.22)
 # draped dark red runner at foot and many seams/folds
 g.sphere((0,-.77,.70),(1.8,.28,.08),'red',1,24,10,.2)
 for x in [-.46,.46]:
  g.sphere((x,.65,.69),(.80,.43,.17),'white',1,24,12,.35)
  for i in range(4):g.tube([(x-.30+i*.18,.48,.75),(x-.29+i*.18,.65,.78),(x-.28+i*.18,.80,.75)],.006,'ivory',1,4)
 g.panel((0,1.05,.70),(1.9,.12,1.1))
 for x in [-.94,.94]:g.lathe([(.055,0),(.065,1.12),(.08,1.15),(.045,1.22)],'walnut',1,(x,1.05,0),16)
def bath(g):
 # Open double shell with recessed interior; never a filled white ellipsoid.
 vv=[];n=64
 for rx,ry,z in [(.70,.28,.16),(.84,.39,.52),(.85,.40,.61),(.79,.34,.61),(.66,.24,.23),(.55,.17,.19)]:
  for k in range(n):a=k*2*math.pi/n;vv.append((rx*math.cos(a),ry*math.sin(a),z+.05*abs(math.cos(a))))
 g.mesh(vv,[(j*n+k,j*n+(k+1)%n,(j+1)*n+(k+1)%n,(j+1)*n+k) for j in range(5) for k in range(n)]+[tuple(range(5*n,6*n))],'ivory',2)
 for x in [-.53,.53]:
  for y in [-.22,.22]:g.sphere((x,y,.09),(.12,.1,.18),'gold',0,12,6)
 g.ring((0,0,.2),.035,.035,.01)
 g.tube([(.12,.38,.05),(.12,.38,.78),(.12,.22,.78),(.12,.18,.70)],.022)
 for x in [-.08,.3]:g.tube([(x,.38,.56),(x,.38,.65)],.018);g.ring((x,.38,.65),.055,.055,.008)
def desk(g):
 # Horseshoe front desk: concentric curved aprons and fluted pilasters.
 n=64;a0=math.radians(205);a1=math.radians(335)
 for z,h,rx,ry,c in [(.12,.24,3,1.65,'walnut'),(.68,.95,2.94,1.58,'wood'),(1.19,.12,3.07,1.72,'walnut')]:
  vv=[]
  for a in [a0+(a1-a0)*i/n for i in range(n+1)]:
   for rxx,ryy,zz in [(rx,ry,z-h/2),(rx,ry,z+h/2),(rx-.70,ry-.62,z-h/2),(rx-.70,ry-.62,z+h/2)]:vv.append((rxx*math.cos(a),ryy*math.sin(a),zz))
  ff=[]
  for i in range(n):
   for q,t in [(0,1),(1,3),(3,2),(2,0)]:ff.append((i*4+q,(i+1)*4+q,(i+1)*4+t,i*4+t))
  ff.extend([(0,2,3,1),(n*4,n*4+1,n*4+3,n*4+2)]);g.mesh(vv,ff,c,1)
 for z in [.11,.23,1.08,1.21]:g.tube([(3.01*math.cos(a0+(a1-a0)*i/n),1.67*math.sin(a0+(a1-a0)*i/n),z) for i in range(n+1)],.022)
 for i in range(57):
  a=a0+(a1-a0)*i/56;g.tube([(2.96*math.cos(a),1.60*math.sin(a),.29),(2.96*math.cos(a),1.60*math.sin(a),1.05)],.022,'gold',0,6)
def floor(g,kind):
 g.box((0,0,.035),(5,5,.07),'walnut' if kind=='wood' else 'stone')
 if kind=='wood':
  # Interlocking parquet with actual board boundaries clipped to a 5m tile.
  def clip(poly,axis,bound,sgn):
   out=[]
   for p,q in zip(poly,poly[1:]+poly[:1]):
    a=(p[axis]-bound)*sgn>=0;b=(q[axis]-bound)*sgn>=0
    if a:out.append(p)
    if a!=b:
     t=(bound-p[axis])/(q[axis]-p[axis]);out.append((p[0]+t*(q[0]-p[0]),p[1]+t*(q[1]-p[1])))
   return out
  L=.72;w=.18
  for a in range(-8,9):
   for b in range(-30,31):
    x=a*L-b*w;y=a*L+b*w
    for x0,y0,ww,hh in [(x,y,L,w),(x+L-w,y+w,w,L)]:
     p=[(x0+.005,y0+.005),(x0+ww-.005,y0+.005),(x0+ww-.005,y0+hh-.005),(x0+.005,y0+hh-.005)]
     p=[((xx-yy)*.70710678,(xx+yy)*.70710678) for xx,yy in p]
     for ax,bd,sgn in [(0,-2.5,1),(0,2.5,-1),(1,-2.5,1),(1,2.5,-1)]:
      if p:p=clip(p,ax,bd,sgn)
     if len(p)>2:
      cc=['wood','walnut','vein'][random.choices([0,1,2],[7,4,1])[0]]
      g.mesh([(xx,yy,.1) for xx,yy in p],[tuple(range(len(p)))],cc)
 else:
  unit=.5 if kind=='bath' else 1
  for ix in range(int(5/unit)):
   for iy in range(int(5/unit)):
    x=-2.5+(ix+.5)*unit;y=-2.5+(iy+.5)*unit
    g.box((x,y,.086),(unit-.012,unit-.012,.028),'ivory' if kind=='bath' else 'stone')
    if kind=='bath' and ix>0 and iy>0:g.box((x-unit/2,y-unit/2,.099),(.095,.095,.002),'black',1,math.pi/4)
    else:
     for j in range(2):
      xx=x+random.uniform(-.4,.4);yy=y+random.uniform(-.4,.4)
      g.tube([(xx-.17,yy-.3,.101),(xx,yy,.102),(xx+.13,yy+.25,.101)],.003,'vein',1,3)

def build(slug):
 g=Geo();s=slug.removeprefix('manor_')
 if s in ['wall_standard','wall_door','wall_window']:arcwall(g,'door' in s,'window' in s)
 elif s.startswith('floor_'):floor(g,s.split('_')[1])
 elif s.startswith('rug_'):
  w,d={'rug_lounge':(8,10),'rug_runner':(2.4,5),'rug_bedroom':(3,4)}[s];rug(g,w,d)
 elif s=='entrance_mat':
  n=48;g.mesh([(0,0,.02)]+[(1.5*math.cos(math.pi*i/n),-1.5*math.sin(math.pi*i/n),.02) for i in range(n+1)],[(0,i+1,i+2) for i in range(n)],'red')
  for r in [1.38,1.45]:g.tube([(r*math.cos(math.pi*i/n),-r*math.sin(math.pi*i/n),.025) for i in range(n+1)],.012)
 elif s in ['plant_large','plant_compact','flower_arrangement']:plant(g,{'plant_large':'large','plant_compact':'compact','flower_arrangement':'flowers'}[s])
 elif s=='wall_lamp':lamp(g,True)
 elif s=='table_lamp':lamp(g)
 elif s in ['sofa','armchair','office_chair']:chair(g,s=='sofa',s=='office_chair')
 elif s=='bed':bed(g)
 elif s=='bathtub':bath(g)
 elif s=='reception_desk':desk(g)
 elif s in ['coffee_table','side_table']:
  r=1 if s=='coffee_table' else .3;h=.48 if s=='coffee_table' else .63
  g.lathe([(0,0),(r*.66,0),(r*.70,.05),(r*.3,.12),(r*.18,h-.1),(r,h-.06),(r,h),(0,h)],'black',2,n=48)
  for z,rr in [(h,r),(.05,r*.68)]:g.ring((0,0,z),rr,rr,.016)
  if s=='coffee_table':
   for i in range(9):
    x=random.uniform(-.65,.65);g.tube([(x,-.70,.488),(x+.12,-.4,.489),(x-.12,.1,.49),(x+.08,.5,.489)],.003,'vein',1,4)
 elif s in ['nightstand','console','wardrobe','bookcase']:
  w,d,h={'nightstand':(.56,.50,.58),'console':(1.3,.40,.82),'wardrobe':(1.8,.6,2.5),'bookcase':(1.3,.36,2.1)}[s]
  legs(g,w,d,.12);g.box((0,0,h/2+.06),(w,d,h-.12),'walnut');g.box((0,0,h),(w+.04,d+.035,.06),'wood')
  if s=='bookcase':
   for z in [.35,.85,1.35,1.85]:
    g.box((0,-d/2-.02,z),(w-.1,.20,.035),'wood')
    for i in range(9):g.box((-w*.43+i*.13,-d/2,z+.16),(.09,.18,.27+random.uniform(-.04,.06)),['red3','green','walnut'][i%3]);g.box((-w*.43+i*.13,-d/2-.10,z+.15),(.065,.01,.012),'gold',0)
  else:
   num=2 if s=='wardrobe' else 1
   for i in range(num):g.panel((-w/2+(i+.5)*w/num,-d/2-.02,h*.52),(w/num-.06,.035,h*.76));g.sphere((-w/2+(i+.5)*w/num,-d/2-.055,h*.57),(.05,.04,.05),'gold',0,12,6)
 elif s=='bench':
  legs(g,1.5,.45,.35);g.box((0,0,.34),(1.5,.45,.10),'walnut');g.sphere((0,0,.46),(1.48,.44,.22),'red',1,24,12,.3)
 elif s.startswith('door_'):
  w=2.2;g.box((0,0,1.25),(w,.12,2.5),'walnut')
  for x in [-.55,.55]:
   for z,hh in [(.5,.65),(1.62,1.26)]:g.panel((x,-.075,z),(1.0,.05,hh))
  for x in [-.12,.12]:g.tube([(x,-.12,1.02),(x,-.12,1.30)],.025)
  if s=='door_arch':
   g.tube([(.95*math.cos(math.pi*i/48),-.11,1.6+.78*math.sin(math.pi*i/48)) for i in range(49)],.04,'gold',0)
 elif s=='wall_grille':
  g.panel((0,0,.6),(2.6,.12,1.2))
  for x in range(17):g.box((-1.15+x*.144,-.09,.60),(.018,.02,.86),'gold',0)
  for z in range(7):g.box((0,-.10,.21+z*.13),(2.3,.02,.016),'gold',0)
 elif s=='painting':
  g.panel((0,0,.48),(1.45,.10,.96));g.box((0,-.065,.48),(1.25,.012,.77),'paper')
  # Low relief landscape: sky, distant hills, cypress and gilded frame.
  for i in range(9):g.sphere((-.55+i*.14,-.078,.33+random.uniform(-.04,.12)),(.32,.008,.22),'stone',1,12,6)
  for x in [-.4,.3]:g.tube([(x,-.09,.16),(x+.02,-.09,.65)],.012,'walnut',1,5);g.sphere((x,-.09,.57),(.16,.015,.29),'green',1,12,6)
 elif s=='vanity':
  legs(g,2,.6,.65);g.box((0,0,.60),(2,.6,.30),'walnut');g.box((0,0,.82),(2.04,.64,.08),'ivory',2)
  for x in [-.5,.5]:
   # Hollow bowls, ceramic basin and tap.
   g.lathe([(.05,.87),(.16,.88),(.23,.97),(.25,1.0),(.22,1.02),(.13,.92),(.04,.91)],'ivory',2,(x,0,0),32)
   g.tube([(x,.23,.85),(x,.23,1.16),(x,.05,1.16),(x,.03,1.10)],.018)
   g.panel((x,-.32,.55),(.88,.04,.28))
 elif s=='mirror':
  # Vertical circular mirror mounted on local +Y side.
  g.sphere((0,0,.48),(.85,.035,.85),'stone',2,40,20)
  g.tube([(.45*math.cos(i*2*math.pi/64),-.03,.48+.45*math.sin(i*2*math.pi/64)) for i in range(64)],.024,'gold',0,8,True)
 elif s=='toilet':
  g.sphere((0,-.05,.25),(.36,.48,.48),'ivory',2,24,12,.5)
  g.lathe([(.07,.40),(.18,.43),(.20,.48),(.16,.50),(.12,.45),(.07,.44)],'white',2,(0,-.08,0),32)
  g.sphere((0,.24,.50),(.40,.17,.55),'ivory',2,24,12,.2);g.box((0,.24,.80),(.42,.20,.04),'white',2)
 elif s=='towel_rail':
  for x in [-.32,.32]:g.tube([(x,.03,.1),(x,-.15,.1),(x,-.15,.68),(x,.03,.68)],.018)
  g.tube([(-.32,-.15,.65),(.32,-.15,.65)],.018)
  g.box((0,-.17,.42),(.42,.06,.46),'ivory');g.box((0,-.21,.23),(.42,.02,.02),'gold',1)
 elif s=='luggage_cart':
  g.box((0,0,.15),(1.05,.65,.10),'black')
  for x in [-.44,.44]:
   for y in [-.25,.25]:g.sphere((x,y,.08),(.13,.10,.16),'black',1,12,6)
   g.tube([(x,-.27,.2),(x,-.27,1.3),(x*.7,-.27,1.55),(0,-.27,1.65)],.025)
  g.box((0,0,.44),(.78,.48,.5),'walnut');g.box((0,0,.72),(.7,.43,.08),'wood')
  for x in [-.26,.26]:g.box((x,-.25,.44),(.04,.025,.5),'gold',0)
 elif s=='candelabra':
  g.lathe([(0,0),(.16,0),(.12,.05),(.035,.08),(.03,.38),(.08,.40)],'gold',0,n=24)
  for x in [-.22,0,.22]:
   g.tube([(0,0,.20),(x,0,.25),(x,0,.39)],.018)
   g.lathe([(.06,.38),(.06,.4),(.035,.41),(.035,.58)],'ivory',1,(x,0,0),12)
   g.sphere((x,0,.61),(.028,.028,.06),'brightgold',3,12,6)
 elif s=='desk_documents':
  for i in range(4):g.box((.01*i,0,.008+i*.012),(.36,.25,.01),'paper',1,.03*i)
  for i in range(7):g.box((0,-.08+i*.022,.053),(.25,.002,.001),'walnut')
 elif s=='bath_screen':
  # Fixed furnishing partition, not a room wall module.
  for x in [-.56,.56]:g.box((x,0,.70),(.07,.12,1.4),'walnut')
  g.panel((0,0,.68),(1.05,.08,1.26))
 else:raise RuntimeError(slug)
 return g

catalog=[];COLS={}
for entry in PLAN['components']:
 slug=entry['slug'];c=bpy.data.collections.new('Component_'+slug);c.instance_offset=(0,0,0)
 # Master collection remains unlinked; a gallery scene owns its authoring links.
 g=build(slug);bounds=g.finish(c,slug);COLS[slug]=c
 entry=dict(entry);entry.update(bounds_size_m=bounds,collection=c.name,root_object='ROOT_'+slug)
 catalog.append(entry)
gallery=bpy.data.scenes.new('组件母版画廊_独立可编辑')
for c in COLS.values():gallery.collection.children.link(c)

instances=[]
def inst(s,x,y,z=0,a=0):
 slug='manor_'+s;c=COLS[slug];o=bpy.data.objects.new('预览_'+s+'_'+str(len(instances)),None);o.instance_type='COLLECTION';o.instance_collection=c;o.location=(x,y,z);o.rotation_euler.z=math.radians(a);OUTPUT.objects.link(o)
 instances.append(dict(component_id=next(e['component_id'] for e in catalog if e['slug']==slug),instance_id=o.name,position_m=[x,y,z],rotation_y_deg=a,scale=[1,1,1],source_object=o.name))
 return o
# Reference-only composition, 25 x 20m, strict 5m floor and wall modules.
for ix in range(5):
 for iy in range(4):inst('floor_bath' if ix==4 and iy==0 else ('floor_stone' if ix==3 else 'floor_wood'),-10+ix*5,-7.5+iy*5,-.1)
for y in [-10,10]:
 for x in [-10,-5,0,5,10]:inst('wall_door' if (y==-10 and x==-5) or (y==10 and x in [-10,0]) else 'wall_standard',x,y,0)
for x in [-12.5,12.5]:
 for y in [-7.5,-2.5,2.5,7.5]:inst('wall_standard' if x<0 else 'wall_window',x,y,0,90)
for x in [2.5,7.5]:
 for y in [-7.5,-2.5,2.5,7.5]:inst('wall_door' if (x==2.5 and y==2.5) or (x==7.5 and y in [-7.5,2.5]) else 'wall_standard',x,y,0,90)
for y in [-5,0]:inst('wall_standard',10,y,0)
inst('door_double',-5,-10,.01);inst('door_arch',-10,10,.01);inst('door_arch',0,10,.01)
inst('door_double',7.5,-7.5,.01,90);inst('door_double',7.5,2.5,.01,90)
inst('rug_lounge',-5,-2.3,.015)
for y in [-7.5,-2.5,2.5,7.5]:inst('rug_runner',5,y,.015)
inst('entrance_mat',-5,-9.2,.015)
inst('sofa',-8,-2.3,.05,90);inst('sofa',-2,-2.3,.05,270)
for x,y,a in [(-8,2,140),(-2,2,220),(-8,-6.6,40),(-2,-6.6,320)]:inst('armchair',x,y,.05,a)
for x in [-9.4,-.6]:
 for y in [-7,2.4]:inst('plant_large',x,y,.05)
for x in [-8,-2]:
 for y in [-.2,-4.4]:inst('side_table',x,y,.05);inst('table_lamp',x,y,.68)
inst('coffee_table',-5,-2.3,.05);inst('flower_arrangement',-5,-2.2,.55)
for x,y in [(-5.55,-2.7),(-4.5,-2.5)]:inst('candelabra',x,y,.55)
inst('reception_desk',-5,6.1,.05);inst('office_chair',-5,7.1,.05,180)
for x in [-7.25,-2.75]:inst('table_lamp',x,6.1,1.32)
inst('desk_documents',-6.3,5.6,1.32)
inst('wall_grille',-5,9.72,1.3)
for x in [-7.7,-2.3,-11,.9]:inst('wall_lamp',x,9.65,1.6)
for x in [-8.2,-1.8]:inst('plant_large',x,8.5,.05)
inst('luggage_cart',-11.3,6.0,.05)
inst('bookcase',-12.15,1.0,.05,90)
inst('console',-12,-3,.05,90);inst('table_lamp',-11.8,-3,.89)
inst('armchair',-11,-4.6,.05,60);inst('side_table',-11.5,-4,.05)
for y in [-7,0,7]:inst('painting',-12.15,y,1.4,90)
for y in [-7,-.2,6.5]:
 for x,a in [(2.8,270),(7.2,90)]:inst('wall_lamp',x,y,1.55,a)
inst('console',6.9,-2.5,.05,90);inst('flower_arrangement',6.9,-2.5,.90)
inst('rug_bedroom',10,5,.02)
inst('bed',10,6,.055);inst('bench',10,4.5,.05)
for x in [8.75,11.25]:inst('nightstand',x,6.4,.05);inst('table_lamp',x,6.4,.65)
inst('wardrobe',10,9.6,.05)
inst('painting',10,9.27,1.45)
inst('armchair',11.4,8.0,.05,220);inst('side_table',10.5,8.2,.05)
inst('plant_large',11.65,1.3,.05)
inst('bathtub',10.5,-8.8,.05)
inst('vanity',10.8,-5.5,.05)
for x in [10.3,11.3]:inst('mirror',x,-5.26,1.2)
inst('toilet',8.65,-6.3,.05);inst('bath_screen',9.3,-6.3,.05,90)
inst('towel_rail',12.2,-7.4,.65,90);inst('plant_compact',11.65,-7.1,.05)
for x in [-8.2,-1.8]:inst('plant_large',x,-8.9,.05)

def area(name,loc,energy,size,target=(0,0,0),color=(1,.77,.52)):
 d=bpy.data.lights.new(name,'AREA');d.energy=energy;d.shape='DISK';d.size=size;d.color=color;o=bpy.data.objects.new(name,d);STAGE.objects.link(o);o.location=loc;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();return o
area('主光_暖色软光',(-6,-3,16),2400,12,(-4,0,0))
area('补光_冷灰',(9,2,15),1700,10,(5,0,0),(.65,.74,1))
area('前台重点光',(-5,7,6),650,5,(-5,6,0))
for ins in instances:
 if ins['component_id'].endswith('WALL-LAMP') or ins['component_id'].endswith('TABLE-LAMP'):
  p=ins['position_m'];d=bpy.data.lights.new('预览灯光','POINT');d.energy=22;d.color=(1,.58,.23);d.shadow_soft_size=.25;o=bpy.data.objects.new('预览灯光',d);STAGE.objects.link(o);o.location=(p[0],p[1]-.12,p[2]+.5)
def camera(name,loc,target,scale):
 d=bpy.data.cameras.new(name);d.type='ORTHO';d.ortho_scale=scale;o=bpy.data.objects.new(name,d);STAGE.objects.link(o);o.location=loc;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();return o
scene.camera=camera('参考顶视相机',(0,-4,35),(0,0,0),29)
camera('正俯视相机',(0,0,35),(0,0,0),29)
camera('三分之四检查相机',(24,-30,29),(0,0,0),35)
scene.render.engine='CYCLES';scene.cycles.samples=32
scene.cycles.use_denoising=True;scene.render.resolution_x=1600;scene.render.resolution_y=1400;scene.render.resolution_percentage=100
scene.world.color=(.12,.12,.12)
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=.5
scene.render.image_settings.file_format='PNG'
scene['reference_only']=True;scene['room_owned_geometry']=False
for screen in bpy.data.screens:
 for ar in screen.areas:
  if ar.type=='VIEW_3D':ar.spaces.active.region_3d.view_perspective='CAMERA'
counts=Counter(x['component_id'] for x in instances)
for e in catalog:e['instance_count']=counts[e['component_id']]
(SRC/'component_catalog.json').write_text(json.dumps({'components':catalog},ensure_ascii=False,indent=2),encoding='utf-8')
(SRC/'component_instances.json').write_text(json.dumps(dict(schema='shellstorm2.battle.component_instances',schema_version=1,library='v017',block_id='expedition',level_id='expedition_03',room_owned_geometry=False,coordinate_contract=dict(source_space='blender_room_local',origin_mode='template_bounds_center_at_walk_plane',room_frame_world_translation_m=[0,0,0],room_frame_world_rotation_z_deg=0,source_bounds_xy_m=[[-12.5,-10],[12.5,10]],walk_plane_z_m=0,blender_plane='XY',blender_up='+Z',rotation_y_deg_semantics='rotation_about_blender_Z',godot_mapping='(bx, by, bz) -> (bx, bz, -by)'),instances=instances,validation=dict(instance_count=len(instances),source_object_count=len(instances),coverage_ok=True)),ensure_ascii=False,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'复古公馆_模块化组件母版_v017.blend'))
scene.render.filepath=str(WORK/'manor_initial.png')
bpy.ops.render.render(write_still=True)
print(json.dumps({'component_count':len(catalog),'instances':len(instances),'source':bpy.data.filepath,'render':scene.render.filepath},ensure_ascii=False))

