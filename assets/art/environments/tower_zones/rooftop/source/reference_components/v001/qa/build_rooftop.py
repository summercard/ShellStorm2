"""Versioned rooftop authoring; run using Blender background. No runtime mutations."""
import bpy, bmesh, math, random, json, hashlib, sys
from pathlib import Path
from mathutils import Vector, Matrix
R=Path('/Users/summercards/ShellStorm2')
O=Path(__file__).resolve().parents[1]
random.seed(917)
PAL=R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
ID='ENV-ROOFTOP-REFERENCE-COMPONENT-LIBRARY'
BLEND=O/'天台区块_参考组件库_v001.blend'
LOCKS=[R/'assets/art/environments/rooftop_shelter_3d/source/env_rooftop_shelter_90x80m_top3d_v021.blend', R/'source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v026.blend', R/'assets/art/environments/tower_zones/battle/source/common_components/v003/战局区块_通用组件库_v003.blend']
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
lockfile=O/'qa/scope_before.json'
if not lockfile.exists(): lockfile.write_text(json.dumps({str(p.relative_to(R)):digest(p) for p in LOCKS},indent=2))
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene;scene.name='天台组件库与参考拼装_v001'
scene.unit_settings.system='METRIC'
def coll(name,parent):
    c=bpy.data.collections.new(name);parent.children.link(c);return c
root=coll('天台区块_中文资产管理',scene.collection)
srcroot=coll('01_制作组件_按设施拆分',root)
outroot=coll('02_游戏输出_独立资产包_v001',root)
show=coll('90_展示与验收_灯光相机',root)
demo=coll('91_参考拼装_实例非独立资产',root)
srcroot.hide_render=True;srcroot.hide_viewport=True
image=bpy.data.images.load(str(PAL));image.filepath=str(PAL)
NAMES=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']
mats=[]
for i,n in enumerate(NAMES):
    m=bpy.data.materials.new(n);m.use_nodes=True;nodes=m.node_tree.nodes;p=nodes.get('Principled BSDF')
    p.inputs['Metallic'].default_value=[.86,.025,.18,0][i]
    p.inputs['Roughness'].default_value=[.29,.72,.15,.36][i]
    p.inputs['Coat Weight'].default_value=[.16,0,.65,0][i]
    uv=nodes.new('ShaderNodeUVMap');uv.uv_map='PaletteUV'
    tex=nodes.new('ShaderNodeTexImage');tex.image=image;tex.interpolation='Closest'
    m.node_tree.links.new(uv.outputs['UV'],tex.inputs['Vector']);m.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
    if i==3:
        m.node_tree.links.new(tex.outputs['Color'],p.inputs['Emission Color']);p.inputs['Emission Strength'].default_value=1.3
    mats.append(m)

class Part:
    def __init__(self): self.v=[];self.f=[];self.style=[]
    def add(self,v,f,cell,role):
        k=len(self.v);self.v.extend(v);self.f.extend([tuple(k+i for i in face) for face in f]);self.style.extend([(cell,role)]*len(f))
parts={};cur=None;boxcache={}
def part(name): return parts.setdefault(name,Part())
def geom(v,f,cell=(9,7),role=1,name='水泥结构'): part(name).add(v,f,cell,role)
def box(c,d,cell=(9,7),role=1,name='水泥结构',bev=.025,rot=0):
    key=(tuple(d),min(bev,min(d)*.22))
    if key not in boxcache:
        bm=bmesh.new();bmesh.ops.create_cube(bm,size=1)
        for v in bm.verts: v.co.x*=d[0];v.co.y*=d[1];v.co.z*=d[2]
        if key[1]>0: bmesh.ops.bevel(bm,geom=list(bm.edges),offset=key[1],segments=1,affect='EDGES')
        bm.verts.ensure_lookup_table();bm.verts.index_update()
        boxcache[key]=([tuple(v.co) for v in bm.verts],[tuple(v.index for v in f.verts) for f in bm.faces]);bm.free()
    vv,ff=boxcache[key];co,si=math.cos(rot),math.sin(rot)
    geom([(c[0]+x*co-y*si,c[1]+x*si+y*co,c[2]+z) for x,y,z in vv],ff,cell,role,name)
def rod(a,b,r,cell=(9,5),role=0,name='金属管件',n=12,r2=None):
    a,b=Vector(a),Vector(b);q=(b-a).to_track_quat('Z','Y');r2=r if r2 is None else r2
    v=[tuple(p+q@Vector((rr*math.cos(i*math.tau/n),rr*math.sin(i*math.tau/n),0))) for p,rr in [(a,r),(b,r2)] for i in range(n)]
    f=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    geom(v,f,cell,role,name)
def ring(c,r,t,plane='XY',cell=(9,6),name='护网与管卡',n=24):
    pts=[]
    for i in range(n):
        a=i*math.tau/n;x,y=r*math.cos(a),r*math.sin(a)
        pts.append((c[0]+x,c[1]+y,c[2]) if plane=='XY' else (c[0]+x,c[1],c[2]+y))
    for i in range(n): rod(pts[i],pts[(i+1)%n],t,cell,0,name,n=6)
def line(points,r=.07,cell=(9,5),name='金属管件'):
    for a,b in zip(points,points[1:]):rod(a,b,r,cell,0,name)
def bolts(c,w,h,plane='front'):
    for x in [-w/2,w/2]:
        for z in [-h/2,h/2]:
            a=(c[0]+x,c[1],c[2]+z);b=(a[0],a[1]-.035,a[2]);rod(a,b,.055,(9,8),0,'紧固件',6)
def wear_floor(x,y,w,h,z,n=22):
    for patch_index in range(n):
        cx=x+random.uniform(-w*.37,w*.37);cy=y+random.uniform(-h*.37,h*.37);rr=random.uniform(.12,.48)
        zz=z-.0008*(patch_index/(max(1,n-1)))
        v=[(max(x-w/2+.02,min(x+w/2-.02,cx+math.cos(i*math.tau/7)*rr*random.uniform(.4,1))),max(y-h/2+.02,min(y+h/2-.02,cy+math.sin(i*math.tau/7)*rr*random.uniform(.5,1))),zz) for i in range(7)]
        geom(v,[tuple(range(7))],random.choice([(9,6),(9,7),(9,7)]),1,'表面磨损')
def floor(w=5,h=5,edge=False,corner=False,inner=False,roof=False):
    cells=[(-1.25,-1.25),(1.25,-1.25),(-1.25,1.25)] if inner else None
    if cells:
        for x,y in cells:box((x,y,.1495),(2.5,2.5,.299));wear_floor(x,y,2.5,2.5,.3)
    else:
        nx=max(1,round(w/2.5));ny=max(1,round(h/2.5))
        box((0,0,.115),(w,h,.23),(9,5))
        for i in range(nx):
            for j in range(ny):
                x=-w/2+(i+.5)*w/nx;y=-h/2+(j+.5)*h/ny
                box((x,y,.2645),(w/nx-.025,h/ny-.025,.069),(9,6 if roof else 7))
                wear_floor(x,y,w/nx,h/ny,.3,12)
    if edge or corner:
        box((0,-h/2+.075,.23),(w,.15,.14),(9,8),0,'边缘压条')
        if corner:box((-w/2+.075,0,.23),(.15,h,.14),(9,8),0,'边缘压条')
def parapet(ivy=False,angle=0):
    def segment(cx,cy,length,rot):
        co,si=math.cos(rot),math.sin(rot)
        for i in range(round(length/.5)):
            lx=-length/2+(i+.5)*.5
            box((cx+lx*co,cy+lx*si,.83),(.492,.43,1.56),(9,7),1,rot=rot)
        box((cx,cy,.12),(length,.5,.24),(9,6),1,rot=rot)
        for i in range(round(length/.5)):
            lx=-length/2+(i+.5)*.5;box((cx+lx*co,cy+lx*si,1.68),(.495,.5,.24),(9,8),1,rot=rot)
        box((cx,cy,1.13),(length,.447,.035),(9,5),1,bev=0,rot=rot)
    if not angle:segment(0,0,5,0)
    else:
        segment(0,-1,2.5,0);segment(-1, .25,2,math.pi/2)
        if angle<0:
            for p in parts.values():p.v=[(-x,y,z) for x,y,z in p.v];p.f=[tuple(reversed(f)) for f in p.f]
    if ivy:vine(0,-.29,1.83,4.5,1.6)
def leaf(c,length=.25,angle=0,cell=None,vertical=False):
    x,y,z=c;co,si=math.cos(angle),math.sin(angle);w=length*.38
    pts=[(-length/2,0,0),(0,w,.035),(length/2,0,.08),(0,-w,.035),(0,0,.085)]
    v=[]
    for a,b,h in pts:
        xx=a*co-b*si;yy=a*si+b*co
        v.append((x+xx,y+h,z+yy) if vertical else (x+xx,y+yy,z+h))
    f=[(0,1,4),(1,2,4),(2,3,4),(3,0,4)]
    geom(v,f,cell or random.choice([(5,4),(6,4),(7,4),(7,3),(8,4)]),1,'叶片')
def vine(x,y,z,w,h):
    for k in range(max(4,int(w*6))):
        xx=x+random.uniform(-w/2,w/2);length=random.uniform(h*.35,h)
        pts=[(xx+.1*math.sin(j*1.6+k),y-.02*j,z-j*length/8) for j in range(9)]
        line(pts,.016,(3,4),'藤蔓茎')
        for j,p in enumerate(pts):
            for side in [-1,1]:leaf((p[0]+side*.10,p[1]-.03,p[2]),random.uniform(.21,.38),side*.7+k,vertical=True)
    for _ in range(int(w*17)):leaf((x+random.uniform(-w/2,w/2),y+random.uniform(0,.5),z+.02),.27,random.random()*6.28)
def wall(kind='plain',external=False):
    # Recesses remain inside the exact 5 x .30 x 11.9 envelope.
    if kind=='door':
        box((-2.2,.0005,5.95),(.6,.299,11.9));box((2.2,.0005,5.95),(.6,.299,11.9));box((0,.0005,9.35),(3.8,.299,5.1))
    else:
        box((0,.055,5.95),(5,.19,11.9),(9,6))
        for row in range(5):
            for col in range(2):
                # window occupies the third/fourth courses
                if kind=='window' and row in (2,3):continue
                box((-1.25+col*2.5,-.054,1.19+row*2.38),(2.47,.19,2.35),(9,7))
        if kind=='window':
            box((0,-.075,7.14),(4.4,.06,4.45),(9,1),2,'窗玻璃',.01)
            for x in [-2.3,0,2.3]:box((x,-.11,7.14),(.1,.08,4.76),(9,5),0,'窗框')
            for z in [4.78,7.14,9.5]:box((0,-.11,z),(4.7,.08,.1),(9,5),0,'窗框')
            box((0,-.10,4.73),(4.75,.1,.16),(9,8),1,'窗台')
    for x in [-2.4,2.4]:box((x,0,5.95),(.2,.3,11.9),(9,6),1,'竖向结构')
    for z in [.18,11.72]:box((0,0,z),(5,.3,.36),(9,8),1,'上下压边')
    for _ in range(40):
        x=random.uniform(-2.1,2.1);z=random.uniform(.5,11.4)
        if kind=='door' and abs(x)<1.95 and z<6.82:continue
        if kind=='window' and abs(x)<2.3 and 4.7<z<9.55:continue
        rr=random.uniform(.05,.18)
        geom([(x-rr,-.15,z),(x+rr*.6,-.15,z+.11),(x+rr,-.15,z+.35),(x-.03,-.15,z+.27)],[(0,1,2,3)],(9,6),1,'表面磨损')
def grille(c,w,h):
    x,y,z=c;box(c,(w,.12,h),(9,1),1,'百叶暗腔')
    for i in range(max(4,int(h/.15))):box((x,y-.09,z-h/2+.07+i*.15),(w-.12,.12,.055),(9,6),0,'百叶片',.009)
    bolts((x,y-.1,z),w-.1,h-.1)
def fan(x,y,z,r):
    rod((x,y,z-.05),(x,y,z),r,(9,1),1,'风扇底腔',32)
    for a in range(5):
        q=a*math.tau/5;cx=x+math.cos(q)*r*.42;cy=y+math.sin(q)*r*.42
        box((cx,cy,z+.06),(r*.8,r*.22,.07),(9,6),0,'风扇叶轮',.02,q+.45)
    rod((x,y,z),(x,y,z+.13),r*.17,(9,7),0,'风扇轴',16)
    for rr in [.35,.65,1]:ring((x,y,z+.17),r*rr,.022)
    for a in range(8):
        q=a*math.tau/8;rod((x-r*math.cos(q),y-r*math.sin(q),z+.18),(x+r*math.cos(q),y+r*math.sin(q),z+.18),.015)
def hvac(kind):
    if kind=='large':w,d,h=4.7,2.4,2.2
    elif kind=='small':w,d,h=2.5,2.2,1.65
    elif kind=='fan':w,d,h=2.2,2.2,.5
    elif kind=='vent':w,d,h=1.4,1,.85
    elif kind=='electric':w,d,h=1.5,.75,2.4
    else:w,d,h=2.4,1.0,2.1
    for x in [-w*.38,w*.38]:box((x,0,.1),(.16,d,.2),(9,4),0,'支脚')
    box((0,0,(h+.04)/2),(w-.04,d-.04,h-.36),(9,6),1,'设备外壳',.04)
    for x in [-w/2+.06,w/2-.06]:box((x,0,(h-.15)/2),(.12,d,h-.15),(9,7),0,'框架')
    box((0,0,h-.07),(w,d,.14),(9,8),0,'顶盖')
    if kind in ('large','small','fan'):
        fan(w*.27 if kind=='large' else 0,0,h+.025,min(d*.39,.84))
    if kind in ('large','small','vent'):
        grille((w*.25 if kind=='large' else 0,-d/2-.015,h*.50),w*.40 if kind=='large' else w*.8,h*.65)
    if kind=='large':
        for x in [-1.72,-.6]:box((x,-d/2-.025,h*.52),(1.06,.06,h*.72),(9,7),1,'检修门');bolts((x,-d/2-.07,h*.52),.9,h*.62)
    if kind in ('electric','cabinet'):
        count=1 if kind=='electric' else 2
        for i in range(count):
            x=(i-(count-1)/2)*w/count
            box((x,-d/2-.04,h*.51),(w/count-.13,.08,h*.78),(9,7),1,'箱门')
            box((x+w/count*.27,-d/2-.11,h*.54),(.065,.1,.25),(9,3),0,'门锁')
            bolts((x,-d/2-.10,h*.51),w/count-.25,h*.67)
        box((0,-d/2-.095,h*.8),(.3,.025,.19),(7,3),1,'警告铭牌')
    for x in [-w*.4,w*.4]:bolts((x,-d/2-.04,h*.5),.12,h*.7)
def pipe(kind):
    if kind=='straight':pts=[(-1.25,0,.18),(1.25,0,.18)]
    elif kind=='elbow':pts=[(-.9,0,1.15),(-.25,0,1.15)]+[(-.25+.65*math.sin(a*math.pi/12),0,.5+.65*math.cos(a*math.pi/12)) for a in range(1,7)]+[(.4,0,.15)]
    elif kind=='tee':pts=[(-1.25,0,1.3),(1.25,0,1.3)];line([(0,0,1.3),(0,0,.15)],.15)
    elif kind=='riser':pts=[(0,0,.18),(0,0,4.65),(.15,0,4.85),(.45,0,4.85)]
    else:
        line([(0,0,.06),(0,0,3.7)],.06)
        for z in [.5,2.8]:box((0,.16,z),(.48,.1,.22),(9,5),0,'挂墙板');line([(0,.15,z),(0,-.65,z-.4),(0,0,z-.4)],.035)
        return
    line(pts,.15)
    for p in [pts[0],pts[-1]]:
        # sleeve aligned to terminal tangent
        tangent=(Vector(pts[1])-Vector(pts[0])).normalized() if p==pts[0] else (Vector(pts[-1])-Vector(pts[-2])).normalized()
        rod(Vector(p)-tangent*.07,Vector(p)+tangent*.07,.205,(9,7),0,'接头法兰',16)
    if kind=='riser':
        for z in [.35,2.1,4.1]:rod((0,0,z-.055),(0,0,z+.055),.21,(9,7),0,'抱箍');box((0,.2,z),(.55,.15,.18),(9,5),0,'管卡底座')
def door():
    box((0,0,3.4),(3.68,.18,6.8),(9,3),0,'门扇',.04)
    for x in [-1.98,1.98]:box((x,0,3.52),(.2,.3,7.04),(9,7),0,'门框')
    box((0,0,6.94),(4.16,.3,.2),(9,7),0,'门框')
    box((0,-.105,2.6),(3.15,.08,4.7),(9,5),1,'门板')
    box((0,-.13,5.3),(1.25,.10,1.15),(9,7),0,'窥窗框')
    box((0,-.19,5.3),(1.02,.025,.92),(9,1),2,'窥窗玻璃')
    box((1.13,-.23,3.1),(.16,.18,.7),(9,8),0,'门把手')
    for z in [1,5.8]:rod((-1.82,-.15,z-.22),(-1.82,-.15,z+.22),.085,(9,6),0,'铰链')
    box((0,-.03,7.34),(1.2,.42,.46),(9,4),0,'门灯罩')
    box((0,-.255,7.32),(.97,.035,.3),(7,3),3,'自发光灯芯')
    box((0,.03,.06),(4.16,.65,.12),(9,7),0,'门槛')
def canopy():
    box((0,0,2.05),(5,2.8,.22),(9,6),1,'雨棚板')
    for x in [-2.37,2.37]:
        box((x,0,1.96),(.16,2.8,.22),(9,7),0,'雨棚压边')
        line([(x,1.25,1.9),(x,1.25,.05),(x,-1.25,1.9)],.06)
    for x in [-1.25,0,1.25]:box((x,0,2.175),(.045,2.7,.025),(9,4),0,'板缝',0)
def planter(big=False,flower=False):
    if flower:
        for z in [.32,.67,1.02]:
            for y in [-.5,.5]:box((0,y,z),(4.5,.12,.28),(7,2),1,'木板',.025)
            for x in [-2.19,2.19]:box((x,0,z),(.12,1,.28),(6,2),1,'木板')
        for x in [-1.8,1.8]:
            box((x,-.575,.68),(.16,.1,1.2),(5,2),0,'箍条');box((x,0,.15),(.24,1.05,.3),(6,2),1,'支脚')
        box((0,0,.96),(4.25,.85,.08),(1,2),1,'土壤')
        for i in range(24):
            x=random.uniform(-2,2);y=random.uniform(-.35,.35);z=random.uniform(1.45,2.05)
            line([(x,y,1),(x+.06,y,z)],.017,(4,4),'花茎')
            for j in range(3):leaf((x+random.uniform(-.2,.2),y,z-.2-j*.14),.35,random.random()*6)
            for a in range(5):
                q=a*math.tau/5;leaf((x+.10*math.cos(q),y+.10*math.sin(q),z),.19,q,random.choice([(9,9),(8,8),(8,3)]))
            rod((x,y,z),(x,y,z+.04),.055,(7,3),1,'花心',8)
    else:
        r=.64 if big else .38;h=1.2 if big else .7
        rod((0,0,.05),(0,0,h),r*.7,(6,2),1,'陶盆',24,r)
        ring((0,0,h-.03),r,.08,'XY',(7,2),'盆沿')
        rod((0,0,h-.07),(0,0,h-.04),r*.87,(0,2),1,'土壤',24)
        for i in range(13):
            q=i*2.4;z=h+.2+random.random()*(1.4 if big else .7);rr=random.uniform(.2,.65)*(1 if big else .65)
            tip=(math.cos(q)*rr,math.sin(q)*rr,z)
            line([(0,0,h),tip],.018,(5,4),'枝茎')
            leaf(tip,.85 if big else .45,q)
def detail(kind):
    if kind=='mat':
        box((0,0,.035),(3,1.65,.07),(6,2),1,'门垫底')
        for i in range(27):box((-1.4+i*.105,0,.08),(.037,1.44,.04),(8,2),1,'纤维纹',.004)
        for y in [-.77,.77]:box((0,y,.075),(2.92,.065,.04),(4,2),1,'编织边')
    elif kind=='drain':
        box((0,0,.06),(1.2,1.2,.12),(9,3),0,'排水框')
        box((0,0,.127),(1.03,1.03,.015),(9,0),1,'排水暗腔',0)
        for i in range(7):box((-.45+i*.15,0,.16),(.055,.99,.045),(9,7),0,'排水格栅',.006)
        for y in [-.3,.3]:box((0,y,.18),(.99,.045,.04),(9,6),0,'横格栅',.006)
    else:
        box((0,0,.72),(1.8,.72,1.44),(9,6),0,'通风箱壳')
        grille((0,-.38,.72),1.55,1.12)

specs=[
 ('floor_full','完整地砖','01_地面系统',lambda:floor()),('floor_half','半块地砖','01_地面系统',lambda:floor(2.5,5)),
 ('floor_corner','角块地砖','01_地面系统',lambda:floor(2.5,2.5,corner=True)),('floor_edge','边缘地砖','01_地面系统',lambda:floor(edge=True)),('floor_inner','内角地砖','01_地面系统',lambda:floor(inner=True)),
 ('parapet','女儿墙直段','02_女儿墙',lambda:parapet()),('parapet_ivy','女儿墙挂藤','02_女儿墙',lambda:parapet(True)),('parapet_outer','女儿墙外角','02_女儿墙',lambda:parapet(angle=1)),('parapet_inner','女儿墙内角','02_女儿墙',lambda:parapet(angle=-1)),
 ('room_wall','房间标准墙','03_房间墙体',lambda:wall()),('room_window','房间窗墙','03_房间墙体',lambda:wall('window')),('room_doorwall','房间门洞墙','03_房间墙体',lambda:wall('door')),
 ('roof_full','房顶完整板','04_房顶模块',lambda:floor(roof=True)),('roof_edge','房顶边缘板','04_房顶模块',lambda:floor(edge=True,roof=True)),('roof_corner','房顶角板','04_房顶模块',lambda:floor(corner=True,roof=True)),
 *[(f'hvac_{k}',n,'05_空调与设备',lambda k=k:hvac(k)) for k,n in [('large','大型空调机组'),('small','小型空调机组'),('fan','顶置通风扇'),('vent','小通风口'),('cabinet','机电箱'),('electric','配电箱')]],
 *[(f'pipe_{k}',n,'06_管线系统',lambda k=k:pipe(k)) for k,n in [('straight','直管段'),('elbow','转角弯管'),('tee','三通管'),('riser','立管下水管'),('bracket','管道支架')]],
 ('door_lamp','门与暖灯','07_门与雨棚',door),('canopy','支撑雨棚','07_门与雨棚',canopy),
 ('ivy','墙面攀爬藤蔓','08_固定绿化',lambda:vine(0,0,3.6,3.8,3.5)),('flowerbox','长条花箱','08_固定绿化',lambda:planter(flower=True)),('plant_large','大盆栽','08_固定绿化',lambda:planter(big=True)),('plant_small','小盆栽','08_固定绿化',planter),
 *[(f'detail_{k}',n,'09_细节附件',lambda k=k:detail(k)) for k,n in [('mat','编织门垫'),('drain','排水格栅'),('vent','墙面通风箱')]],
 ('facade_solid','标准外墙实墙','10_外墙系统',lambda:wall(external=True)),('facade_window','标准外墙窗墙','10_外墙系统',lambda:wall('window',True))]
catalog=[];packages={};groups={};sourcegroups={}
def meshobj(name,p,c,selected_role=None):
    faces=[];style=[]
    for f,s in zip(p.f,p.style):
        if selected_role is None or (s[1]==3)==selected_role:faces.append(f);style.append(s)
    if not faces:return None
    used=sorted(set(i for f in faces for i in f));mapping={old:i for i,old in enumerate(used)}
    mesh=bpy.data.meshes.new(name);mesh.from_pydata([p.v[i] for i in used],[],[tuple(mapping[i] for i in f) for f in faces]);mesh.update()
    roles=sorted({s[1] for s in style})
    for r in roles:mesh.materials.append(mats[r])
    uv=mesh.uv_layers.new(name='PaletteUV');uv.active_render=True;mesh.uv_layers.active=uv
    for poly,((col,row),role) in zip(mesh.polygons,style):
        poly.material_index=roles.index(role)
        for j,li in enumerate(poly.loop_indices):
            a=j*math.tau/poly.loop_total;uv.data[li].uv=((col+.5)/10+.027*math.cos(a),(9-row+.5)/10+.027*math.sin(a))
    ob=bpy.data.objects.new(name,mesh);c.objects.link(ob);return ob
groupcounts={}
for slug,zh,cat,fn in specs:
    parts={};fn()
    vs=[Vector(v) for p in parts.values() for v in p.v]
    lo=Vector(tuple(min(v[i] for v in vs) for i in range(3)));hi=Vector(tuple(max(v[i] for v in vs) for i in range(3)))
    anchor=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
    for p in parts.values():p.v=[tuple(Vector(v)-anchor) for v in p.v]
    if cat not in groups:groups[cat]=coll(cat,outroot);sourcegroups[cat]=coll(cat+'_制作',srcroot)
    pkg=coll(zh+'_资产包',groups[cat]);spkg=coll(zh+'_制作组件',sourcegroups[cat])
    rootob=bpy.data.objects.new('根_'+zh,None);pkg.objects.link(rootob)
    idx=groupcounts.get(cat,0);groupcounts[cat]=idx+1
    pos=(idx*8,int(cat[:2])*-17,0);rootob.location=pos;pkg.instance_offset=pos
    allp=Part()
    for pn,p in parts.items():
        ob=meshobj(zh+'_'+pn+'_制作',p,spkg);ob.location=pos
        k=len(allp.v);allp.v.extend(p.v);allp.f.extend([tuple(k+i for i in f) for f in p.f]);allp.style.extend(p.style)
    obs=[]
    for emissive,suffix in [(False,'主体'),(True,'UI灯光_柔和自发光')]:
        ob=meshobj(zh+'_'+suffix,allp,pkg,emissive)
        if ob:ob.parent=rootob;obs.append(ob)
    pid='ENV-ROOFTOP-REF-'+slug.upper().replace('_','-');rootob['asset_id']=pid;rootob['block_id']='rooftop';rootob['version']='v001'
    size=hi-lo
    sockets={}
    if 'wall' in slug or slug.startswith('facade') or slug=='room_window':
        sockets={'left':[-2.5,0,0],'right':[2.5,0,0],'base':[0,0,0],'upper_floor':[0,0,12]}
    elif slug.startswith(('floor','roof')):sockets={'left':[-size.x/2,0,.3],'right':[size.x/2,0,.3],'front':[0,-size.y/2,.3],'back':[0,size.y/2,.3]}
    elif slug=='parapet':sockets={'left':[-2.5,0,0],'right':[2.5,0,0]}
    item={'schema':1,'asset_id':ID,'package_id':pid,'name_zh':zh,'slug':slug,'category':cat,'version':'v001','block_id':'rooftop','floor_range':'100F','design_scope':'参考图独立组件，非正式布局替换','source_blend':str(BLEND.relative_to(R)),'blender_collection':pkg.name,'root_object':rootob.name,'objects':[o.name for o in obs],'source_collection':spkg.name,'local_origin':[0,0,0],'world_position':list(pos),'front_direction':'-Y','bounds_size':[round(v,6) for v in size],'bounds_min':[-size.x/2,-size.y/2,0],'bounds_max':[size.x/2,size.y/2,size.z],'material_roles':NAMES,'sockets':sockets,'dependencies':['shared_facility_palette'],'attachment':'fixed_display_attachment' if cat[:2] in ('08','09') else 'independent_module','exported':False,'expected_export':f'env_rooftop_ref_{slug}_v001.glb','collision':'not_created','logical_wall_height':12 if sockets.get('upper_floor') else None,'collision_bounds':[5,.3,12] if sockets.get('upper_floor') else None,'camera_clearance':12 if slug.startswith('roof') else None,'animation':False,'emission':any(o.name.endswith('柔光灯') for o in obs),'scene_design_docs':['docs/v0.1/design/rooftop_component_library.md','docs/v0.1/05.1_关卡区块设计.md'],'asset_ledger':'assets/registry/ShellStorm2_美术资产台账_v001.xlsx#3D-场景通用'}
    item['emission']=any('自发光' in o.name for o in obs)
    item['parent_asset_id']='ENV-ROOFTOP-SHELTER-90X80'
    item['dedupe_classification']='child_variant'
    item['variant_of']='ENV-TOWER-ROOFTOP-FACADE' if slug.startswith('facade') else 'ENV-TOWER-FLOOR-TILE-5M' if slug.startswith('floor') else 'ENV-ROOFTOP-SHELTER-90X80'
    if slug.startswith('parapet'):
        if slug in ('parapet','parapet_ivy'):item['sockets']={'left':[-2.5,0,0],'right':[2.5,0,0]}
        else:
            s=-1 if slug=='parapet_inner' else 1
            item['sockets']={'east':[s*1.25,-1,0],'north':[-s*1,1.25,0]}
    if slug.startswith('pipe_'):
        ports={'pipe_straight':[[-1.25,0,.18],[1.25,0,.18]],'pipe_elbow':[[-.9,0,1.15],[.4,0,.15]],'pipe_tee':[[-1.25,0,1.3],[1.25,0,1.3],[0,0,.15]],'pipe_riser':[[0,0,.18],[.45,0,4.85]]}.get(slug,[])
        item['sockets']={f'port_{i}':[round(v,6) for v in Vector(p)-anchor] for i,p in enumerate(ports)}
        item['pipe_diameter']=.3 if ports else None
    path=O/'component_packages_v001'/cat[:2]/slug;path.mkdir(parents=True,exist_ok=True)
    (path/'asset_manifest.json').write_text(json.dumps(item,ensure_ascii=False,indent=2))
    catalog.append(item);packages[slug]=(pkg,rootob,obs)
    print('BUILT',slug,len(allp.f),flush=True)

# Reference assembly: object-linked instances retain every package boundary.
placements=[]
def place(slug,x,y,z=0,angle=0):
    pkg,rootob,obs=packages[slug]
    ob=bpy.data.objects.new('拼装_'+slug+f'_{len(placements):03}',None);ob.instance_type='COLLECTION';ob.instance_collection=pkg
    # Collection objects are laid out on the library sheet, offset back to local origin.
    pkg.instance_offset=rootob.location.copy();ob.location=(x,y,z);ob.rotation_euler.z=angle;demo.objects.link(ob)
    placements.append({'slug':slug,'position':[x,y,z],'rotation_z':angle})
for r in range(10):
    for c in range(10):place('floor_full',-22.5+c*5,-22.5+r*5,-.3)
for i in range(10):
    p=-22.5+i*5
    for side in range(4):
        x,y,ang=[(p,-24.75,0),(24.75,p,math.pi/2),(-p,24.75,math.pi),(-24.75,-p,-math.pi/2)][side]
        place('parapet_ivy' if i in (1,4,8) else 'parapet',x,y,0,ang)
        place('facade_window' if i%3!=0 else 'facade_solid',x,y,-12,ang)
# room front at y=-8, back +12, X +/-10 (shared corner trim covers junction).
for i in range(4):
    x=-7.5+i*5
    place('room_doorwall' if i==3 else ('room_window' if i==1 else 'room_wall'),x,-8,0)
    place('room_window' if i in (1,2) else 'room_wall',-x,12,0,math.pi)
    for side in [-1,1]:place('room_window' if i==2 else 'room_wall',side*10,-5.5+i*5,0,side*math.pi/2)
for r in range(4):
    for c in range(4):
        angle=0
        if r in (0,3) and c in (0,3):
            slug='roof_corner';angle={(0,0):0,(0,3):math.pi/2,(3,3):math.pi,(3,0):-math.pi/2}[(r,c)]
        elif r in (0,3) or c in (0,3):
            slug='roof_edge';angle=0 if r==0 else math.pi if r==3 else math.pi/2 if c==3 else -math.pi/2
        else:slug='roof_full'
        place(slug,-7.5+c*5,-5.5+r*5,12,angle)
place('door_lamp',7.5,-8.25,0)
place('canopy',10.9,-8.5,5.3)
place('detail_mat',7.5,-9.45,.02)
place('flowerbox',-4,-8.85,0)
place('plant_large',5,-8.8,0);place('plant_small',-8.6,-8.9,0);place('plant_small',10,-8.8,0)
place('hvac_cabinet',1,-8.9,0);place('hvac_electric',11,-8.85,0);place('detail_vent',-8,-8.5,.2)
for x,z in [(-9,7.8),(-6,5.3),(3.5,8),(9,8.1)]:place('ivy',x,-8.24,z)
for x,y,k in [(-5,5,'small'),(2,8,'small'),(3,-4,'large')]:place('hvac_'+k,x,y,12.3)
place('hvac_vent',-6,-4,12.3);place('hvac_fan',6,4,12.3)
for x in [-5,-2.5,0,2.5,5]:place('pipe_straight',x,-6.2,12.35)
for z in [0,4.8,7]:place('pipe_riser',-3,-8.4,z)
for x,y in [(-20,-20),(20,-20),(20,20),(-20,20)]:place('detail_drain',x,y,.005)
for x in [-17.5,-2.5,17.5]:place('ivy',x,-25.03,-3.5)
for y in [-17.5,2.5,17.5]:place('ivy',25.03,y,-3.5,math.pi/2)
(O/'component_packages_v001/catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2))
(O/'component_packages_v001/tree.txt').write_text('\n'.join([f'{cat}\n'+ '\n'.join('  '+p['slug']+' / '+p['name_zh'] for p in catalog if p['category']==cat) for cat in groups]))
(O/'reference_assembly.json').write_text(json.dumps({'schema':1,'purpose':'50m参考拼装演示，不是90x80m正式天台','block_id':'rooftop','placements':placements},ensure_ascii=False,indent=2))

def track(ob,p):ob.rotation_euler=(Vector(p)-ob.location).to_track_quat('-Z','Y').to_euler()
def camera(name,loc,target,scale):
    cd=bpy.data.cameras.new(name);co=bpy.data.objects.new(name,cd);show.objects.link(co);cd.type='ORTHO';cd.ortho_scale=scale;co.location=loc;track(co,target);return co
cameras={
 '01_参考镜头全景':camera('01_参考镜头全景',(19,-94,85),(0,0,0),76),
 '02_俯视结构':camera('02_俯视结构',(0,0,110),(0,0,0),59),
 '03_房间设备近景':camera('03_房间设备近景',(31,-48,38),(0,0,6),44),
 '04_外墙接口':camera('04_外墙接口',(41,-54,21),(0,-23,-4),59)}
world=bpy.data.worlds.new('中性日光世界');world.use_nodes=True;scene.world=world
bg=world.node_tree.nodes.get('Background');bg.inputs['Color'].default_value=(.32,.38,.46,1);bg.inputs['Strength'].default_value=.65
for n,loc,power,size,color in [('大柔光',(-20,-30,65),42000,35,(1,.91,.78)),('补光',(45,-5,40),18000,30,(.77,.85,1))]:
    ld=bpy.data.lights.new(n,'AREA');ld.energy=power;ld.shape='DISK';ld.size=size;ld.color=color
    ob=bpy.data.objects.new(n,ld);show.objects.link(ob);ob.location=loc;track(ob,(0,0,0))
ld=bpy.data.lights.new('日光','SUN');ld.energy=2.2;ld.angle=.25
sun=bpy.data.objects.new('日光',ld);show.objects.link(sun);sun.rotation_euler=(.35,-.5,-.35)
ld=bpy.data.lights.new('门灯照明_展示专用','POINT');ld.energy=65;ld.color=(1,.55,.16);ld.shadow_soft_size=.5
lamp=bpy.data.objects.new('门灯照明_展示专用',ld);show.objects.link(lamp);lamp.location=(7.5,-8.8,7.3)
scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
scene.render.resolution_x=1600;scene.render.resolution_y=1200;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=.65
scene['asset_id']=ID;scene['block_id']='rooftop';scene['floor_range']='100F';scene['package_count']=len(catalog)
scene['scene_design_docs']='docs/v0.1/design/rooftop_component_library.md'
scene['asset_ledger']='assets/registry/ShellStorm2_美术资产台账_v001.xlsx#3D-场景通用'
root.children.unlink(demo)
assembly=bpy.data.scenes.new('天台_参考拼装展示')
assembly.collection.children.link(demo);assembly.collection.children.link(show)
assembly.world=world;assembly.render.engine='CYCLES';assembly.cycles.samples=24;assembly.cycles.use_denoising=True
assembly.render.resolution_x=1600;assembly.render.resolution_y=1200;assembly.render.resolution_percentage=100
assembly.render.image_settings.file_format='PNG';assembly.view_settings.view_transform='AgX';assembly.view_settings.look='AgX - Medium High Contrast';assembly.view_settings.exposure=.65
assembly.camera=cameras['01_参考镜头全景']
scene.camera=camera('05_组件库总览',(60,-160,180),(12,-90,3),210)
# Library default is arranged by category; assembly is a separately selectable scene view.
for area in bpy.context.screen.areas if bpy.context.screen else []:
    if area.type=='VIEW_3D':
        area.spaces.active.region_3d.view_distance=105;area.spaces.active.region_3d.view_location=(0,-70,0)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND),compress=True)
import runpy
runpy.run_path(str(O/'qa/finalize_interfaces.py'),run_name='__main__')
(O/'qa/build_summary.json').write_text(json.dumps({'packages':len(catalog),'source_meshes':sum(o.type=='MESH' for o in srcroot.all_objects),'output_meshes':sum(o.type=='MESH' for o in outroot.all_objects),'materials':len(mats),'assembly_instances':len(placements)},indent=2))
print('SAVED',BLEND,flush=True)
if '--render' in sys.argv:
    for name,cam in cameras.items():
        assembly.camera=cam;assembly.render.filepath=str(O/'renders'/f'{name}.png');bpy.ops.render.render(write_still=True,scene=assembly.name)
