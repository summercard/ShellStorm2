"""Deterministic art dressing of the supplied room; run in Blender 4.2."""
import bpy, bmesh, math, json, hashlib, random, sys
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path('/Users/summercards/ShellStorm2')
OUT = ROOT/'assets/art/environments/tower_zones/battle/source/main_room_02/v003'
BLEND = OUT/'局内关卡01_主路内容房02_数据机房美术_v003.blend'
PAL = ROOT/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
random.seed(220916)
scene = bpy.context.scene
def log(s): print(s, flush=True)
def dump(p,v): p.parent.mkdir(parents=True,exist_ok=True); p.write_text(json.dumps(v,ensure_ascii=False,indent=2),encoding='utf8')
def bounds(o):
    points=[o.matrix_world@Vector(v) for v in o.bound_box]
    return [[round(fn(p[i] for p in points),6) for i in range(3)] for fn in (min,max)]
def signature(o):
    d={'matrix':[[round(v,6) for v in row] for row in o.matrix_world],
       'verts':[[round(v,6) for v in p.co] for p in o.data.vertices],
       'faces':[list(p.vertices) for p in o.data.polygons],
       'parent':o.parent.name if o.parent else None,'bounds':bounds(o),
       'modifiers':[(m.name,m.type) for m in o.modifiers], 'animated':bool(o.animation_data)}
    return {'sha256':hashlib.sha256(json.dumps(d,sort_keys=True).encode()).hexdigest(),'bounds':d['bounds']}
locked={o.name:signature(o) for o in scene.objects if o.type=='MESH'}
dump(OUT/'qa/whitebox_lock_before.json',locked)
originals=[o for o in scene.objects if o.type=='MESH' and not o.name.startswith('AP_')]
assert len(originals)==39, len(originals)

# One externally linked palette and exactly four material roles.
image=bpy.data.images.load(str(PAL),check_existing=True)
image.filepath=str(PAL)
if image.packed_file: image.unpack(method='REMOVE')
roles=[('01_精工金属_紫色骨架',.86,.28,.16),('02_细腻哑光_青绿大面',.03,.68,0),('03_清漆反光_紫粉点缀',.18,.15,.65),('04_柔和自发光_UI灯光',0,.38,0)]
mats=[]
for i,(name,metal,rough,coat) in enumerate(roles):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes=True; n=m.node_tree.nodes; n.clear(); l=m.node_tree.links
    out=n.new('ShaderNodeOutputMaterial'); bs=n.new('ShaderNodeBsdfPrincipled'); uv=n.new('ShaderNodeUVMap'); tex=n.new('ShaderNodeTexImage')
    uv.uv_map='PaletteUV'; tex.image=image; tex.interpolation='Closest'
    l.new(uv.outputs['UV'],tex.inputs['Vector']); l.new(tex.outputs['Color'],bs.inputs['Base Color']); l.new(bs.outputs[0],out.inputs[0])
    bs.inputs['Metallic'].default_value=metal; bs.inputs['Roughness'].default_value=rough; bs.inputs['Coat Weight'].default_value=coat
    if i==3: l.new(tex.outputs['Color'],bs.inputs['Emission Color']); bs.inputs['Emission Strength'].default_value=1.5
    mats.append(m)
# Palette positions counted from image top-left, matching the shared sheet.
C={'black':(9,0),'dark':(9,1),'panel':(9,2),'steel':(9,4),'silver':(9,6),'white':(9,9),'cyan':(6,5),'blue':(5,6),'amber':(6,2),'rubber':(3,9),'green':(5,4),'paper':(9,8),'rust':(4,2)}
def palette(mesh,key):
    while mesh.uv_layers: mesh.uv_layers.remove(mesh.uv_layers[0])
    uv=mesh.uv_layers.new(name='PaletteUV'); cx,cy=C[key]
    u=(cx+.5)/10; v=1-(cy+.5)/10
    for p in mesh.polygons:
        for j,li in enumerate(p.loop_indices):
            a=2*math.pi*j/len(p.loop_indices)
            uv.data[li].uv=(u+.027*math.cos(a),v+.027*math.sin(a))
    mesh.uv_layers.active=uv; uv.active_render=True
for o in list(scene.objects):
    if o.type=='MESH':
        o.data=o.data.copy(); o.data.materials.clear(); o.data.materials.append(mats[1])
        palette(o.data,'panel' if 'TILE' in o.name else 'dark')
for m in list(bpy.data.materials):
    if m not in mats: bpy.data.materials.remove(m)

top=next(c for c in bpy.data.collections if c.name.endswith('_资产管理'))
top.name='局内关卡01_主路内容房02_数据机房_中文资产管理'
source=bpy.data.collections['01_制作组件_按设施拆分']
output=bpy.data.collections['02_游戏输出_独立资产包_v002']; output.name='02_游戏输出_独立资产包_v003'
display=bpy.data.collections['90_展示与验收_灯光相机']
for o in list(display.objects): bpy.data.objects.remove(o,do_unlink=True)
def coll(name,parent):
    c=bpy.data.collections.new(name); parent.children.link(c); return c
categories={k:coll(n,output) for k,n in [('architecture','01_建筑结构_逐墙'),('floor','02_地面系统_逐砖'),('facilities','03_区域固定设施_逐设施'),('support','04_环境支持_跨设施')]}
packages=[]; current=None; origin=Vector((0,0,0)); yaw=0; cache={}; counter=0
def pkg(slug,name,cat,loc=(0,0,0),angle=0,hide=False):
    global current,origin,yaw
    c=coll(name+'_资产包',categories[cat]); c['package_id']='main02_'+slug; c['block_id']='battle'
    current={'slug':slug,'name':name,'cat':cat,'collection':c,'parts':[],'locked':[],'cutaway':hide,'origin':list(loc),'angle':angle}
    packages.append(current); origin=Vector(loc); yaw=math.radians(angle); return current
def world(p): return origin+Matrix.Rotation(yaw,3,'Z')@Vector(p)
def object_mesh(name,me,p=(0,0,0),rot=(0,0,0),role=0,key='dark'):
    global counter
    counter+=1
    o=bpy.data.objects.new(name+('_自发光' if role==3 else '')+'_%05d'%counter,me)
    current['collection'].objects.link(o); o.location=world(p); o.rotation_euler=(rot[0],rot[1],rot[2]+yaw)
    current['parts'].append(o); return o
def box(name,p,d,key='dark',role=0,bevel=.025,rot=(0,0,0)):
    k=(tuple(round(v,5) for v in d),key,role,bevel)
    if k not in cache:
        bm=bmesh.new(); bmesh.ops.create_cube(bm,size=1)
        for v in bm.verts: v.co=Vector((v.co.x*d[0],v.co.y*d[1],v.co.z*d[2]))
        if bevel: bmesh.ops.bevel(bm,geom=list(bm.edges),offset=min(bevel,min(d)*.22),segments=2,affect='EDGES')
        me=bpy.data.meshes.new(name); bm.to_mesh(me); bm.free(); me.materials.append(mats[role]); palette(me,key); cache[k]=me
    return object_mesh(name,cache[k],p,rot,role,key)
def mesh_custom(name,verts,faces,key='dark',role=0):
    me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.materials.append(mats[role]); palette(me,key); return object_mesh(name,me,role=role)
def tube(name,points,r=.05,key='rubber',role=1,segments=8):
    verts=[]; faces=[]
    for i,p in enumerate(points):
        t=Vector(points[min(i+1,len(points)-1)])-Vector(points[max(i-1,0)])
        t.normalize(); a=t.cross(Vector((0,0,1)))
        if a.length<.01: a=t.cross(Vector((0,1,0)))
        a.normalize(); b=t.cross(a)
        for j in range(segments): verts.append(Vector(p)+r*(a*math.cos(j*2*math.pi/segments)+b*math.sin(j*2*math.pi/segments)))
    for i in range(len(points)-1):
        for j in range(segments): faces.append((i*segments+j,i*segments+(j+1)%segments,(i+1)*segments+(j+1)%segments,(i+1)*segments+j))
    faces.extend([tuple(reversed(range(segments))),tuple((len(points)-1)*segments+j for j in range(segments))])
    return mesh_custom(name,verts,faces,key,role)
def text(body,p,size=.24,key='silver',rot=(0,0,0),role=1):
    cu=bpy.data.curves.new('标识','FONT'); cu.body=body; cu.size=size; cu.align_x='CENTER'; cu.extrude=.0008; cu.resolution_u=2
    o=bpy.data.objects.new('文字',cu); current['collection'].objects.link(o)
    dg=bpy.context.evaluated_depsgraph_get(); me=bpy.data.meshes.new_from_object(o.evaluated_get(dg)); bpy.data.objects.remove(o,do_unlink=True); bpy.data.curves.remove(cu)
    me.materials.append(mats[role]); palette(me,key); return object_mesh('标识_'+body,me,p,rot,role,key)
def bolt(p): return box('紧固螺帽',p,(.065,.065,.018),'silver',0,.012)
def route_loop(x,y,w=1):
    for k in range(3):
        pts=[(x+w*math.cos(t*math.pi/12),y+(.65+k*.15)*math.sin(t*math.pi/12),.37+.025*k) for t in range(28)]
        tube('松弛电缆',pts,.035,'blue' if k==1 else 'rubber')

# Move unaltered whitebox objects into individual packages, then add host details.
for o in originals:
    cat='floor' if o.name.startswith('FLOOR') else 'architecture'
    hide=o.name.startswith(('WALL_SOUTH','WALL_WEST'))
    name=('地砖_'+o.name[11:] if 'FLOOR_TILE_' in o.name else {'FLOOR_BASE':'承重底板','WALL_NORTH_01':'北墙','WALL_SOUTH_01':'南墙'}.get(o.name,o.name.replace('WALL_EAST','东墙').replace('WALL_WEST','西墙')))
    p=pkg(o.name.lower(),name,cat,hide=hide)
    for c in list(o.users_collection): c.objects.unlink(o)
    p['collection'].objects.link(o); p['locked'].append(o)
    if 'FLOOR_TILE' in o.name:
        x,y=o.location.x,o.location.y
        for s in [-1,1]:
            box('地砖压边',(x+s*2.36,y,.301),( .045,4.7,.012),'steel',0,.002)
            box('地砖压边',(x,y+s*2.36,.301),(4.7,.045,.012),'steel',0,.002)
            box('嵌槽蓝色漆线',(x+s*2.26,y,.301),(.025,3.9,.006),'blue',1,.001)
            for t in [-1,1]: bolt((x+s*2.28,y+t*2.28,.307))
        idx=int(o.name[-2:]); row=int(o.name[12:14])
        text('%02d.%02d'%(row,idx),(x+1.78,y-2.1,.308),.17)
        if (row,idx) in [(1,2),(2,3),(4,2),(4,5),(2,5)]:
            box('检修排水框',(x-.7,y+.35,.311),(1.45,1.05,.018),'steel',0,.012)
            box('格栅内凹底',(x-.7,y+.35,.322),(1.3,.9,.012),'black',1,.001)
            for k in range(7): box('检修格栅',(x-.7,y+.02+k*.11,.331),(1.21,.042,.02),'silver',0,.004)
        # Flat authored wear polygons and small scratch marks, local to each tile.
        for k in range(3 if row in (2,3,4) and idx in (2,3,4,5) else 9):
            xx=x+random.uniform(-1.8,1.8); yy=y+random.uniform(-1.8,1.8); rad=random.uniform(.025,.24)
            vs=[(xx+math.cos(a)*rad*random.uniform(.6,1.2),yy+math.sin(a)*rad*.55,.308) for a in [j*math.pi/4 for j in range(8)]]
            mesh_custom('地面油漆磨损',vs,[tuple(range(8))],'black',1)
        for k in range(3):
            xx=x+random.uniform(-1.5,1.5); yy=y+random.uniform(-1.5,1.5)
            for j in range(3): box('细碎刮痕',(xx+j*.035,yy,.309),(.012,random.uniform(.12,.45),.003),'steel',0,.001,rot=(0,0,.6))
        if (row,idx) in [(2,4),(4,3)]:
            text('KEEP CLEAR',(x,y-.9,.311),.24)
            for k in range(7): box('通道斜纹',(x-1.2+k*.37,y-1.35,.31),(.21,.45,.009),'paper',1,.001,rot=(0,0,-.5))
    elif o.name.startswith('WALL'):
        b=bounds(o); lo,hi=b; east='EAST' in o.name; west='WEST' in o.name
        # Insets stay inside the original wall envelope; no shell dimensions change.
        if east or west:
            x=lo[0]+.003 if east else hi[0]-.003
            length=hi[1]-lo[1]; cells=max(1,round(length/2.4))
            for j in range(cells):
                yy=lo[1]+(j+.5)*length/cells
                for z0,z1 in [(lo[2]+.1,5.8),(6.,hi[2]-.1)]:
                    if z1<=z0: continue
                    box('墙体内嵌装甲面板',(x,yy,(z0+z1)/2),(.018,length/cells-.075,z1-z0),'panel',1,.008)
        else:
            y=lo[1]+.003 if 'NORTH' in o.name else hi[1]-.003
            for j in range(12):
                for z0,z1 in [(.38,5.8),(6.,11.75)]:
                    box('墙体内嵌装甲面板',(-13.75+j*2.5,y,(z0+z1)/2),(2.43,.018,z1-z0),'panel',1,.008)

log('Whitebox preserved and surface packages created')
# Per-wall utilities: trans-room conduits get their own support packages.
for side,loc,ang,length,cut in [('north',(0,11.98,0),0,28,False),('east',(14.48,0,0),-90,23,False),('south',(0,-11.98,0),180,28,True),('west',(-14.48,0,0),90,23,True)]:
    pkg(side+'_utilities',{'north':'北','east':'东','south':'南','west':'西'}[side]+'墙电缆桥架与检修灯','support',loc,ang,cut)
    for z in (5.2,5.4,5.62):
        tube('墙面金属管',[(-length/2,0,z),(length/2,0,z)],.05,'steel',0)
    for x in range(-int(length/2)+1,int(length/2),3):
        box('管线固定卡',(x,0,5.4),(.09,.22,.75),'steel',0)
        box('灯条底座',(x,-.10,5.03),(1.8,.21,.18),'black',0)
        box('蓝色检修灯条',(x,-.23,5.03),(1.48,.07,.065),'cyan',3,.015)
        box('检修灯白蓝灯芯',(x,-.272,5.033),(1.37,.016,.023),'paper',3,.005)
    for x in (-length/2+.5,length/2-.5):
        tube('转角下行管',[(x,0,9.7),(x,0,6),(x,-.05,.65)],.065,'steel',0)
    text('AUTHORIZED   /   DATA DIVISION',(0,-.07,8.0),.36,'silver',(math.pi/2,0,0))

# Rack geometry follows a tall recessed server cabinet with exposed rail modules.
def rack(slug,loc,ang=0,damaged=False):
    pkg(slug,('故障服务器柜_' if damaged else '服务器柜_')+slug,'facilities',loc,ang)
    h=3.8; w=1.55; d=1.35
    box('减震底座',(0,0,.16),(w+.18,d+.18,.32),'black',0)
    box('后板',(0,.57,2),(w,.15,h),'panel',1)
    for x in [-.71,.71]:
        box('机柜侧装甲',(x,0,2),(.16,d,h),'panel',1,.05)
        box('铝合金立柱',(x,-.64,2),(.085,.10,h+.02),'steel',0)
        for z in [0.42,1.4,2.5,3.7]: box('安装耳',(x,-.7,z),(.12,.1,.14),'silver',0)
    box('机柜顶盖',(0,0,3.93),(1.58,1.39,.14),'steel',0,.04)
    box('上部铭牌',(0,-.70,3.67),(1.15,.05,.22),'black',1)
    text('NODE '+slug[-2:],(0,-.736,3.59),.12,'paper',(math.pi/2,0,0))
    for z in [0.48+j*.29 for j in range(10)]:
        box('抽屉服务器面板',(0,-.53,z),(1.23,.16,.23),'black',0,.016)
        for x in [-.53,.53]: box('抽屉把手',(x,-.66,z),(.06,.11,.16),'steel',0,.012)
        for j in range(4): box('硬盘散热片',(-.31+j*.12,-.63,z),(.05,.028,.12),'steel',0,.002)
        for j in range(3): box('状态LED',(.23+j*.09,-.646,z),(.04,.018,.038),['paper','cyan','amber'][j],3,.007)
    for x in [-.6,.6]:
        box('纵向蓝灯',(x,-.68,2),(.026,.035,2.65),'cyan',3,.009)
        for z in [.65,1.2,1.75,2.3,2.85,3.25]: box('导轨LED刻度',(x,-.702,z),(.018,.012,.10),'paper',3,.003)
    for j in range(5): box('顶部散热槽',(-.44+j*.22,0,4.005),(.12,.7,.014),'black',1,.004)
    if damaged:
        box('外翻脱落柜门',(.78,-.82,1.93),(1.20,.12,3.15),'steel',0,.04,rot=(0,-.16,-.18))
        for j in range(4): tube('破损线束',[(.3,-.66,2.7),(.4+j*.07,-1.05,1.3),(.8+j*.1,-1.4,.15)],.023,'blue' if j%2 else 'rust')
    for z in [.75,1.8,2.9]:
        for x in [-.79,.79]: box('侧板横向加强筋',(x,0,z),(.07,1.21,.05),'steel',0,.01)
    return current

for i,x in enumerate([-2.8,-.9,1.0,3.0,5.0,7.0,9.0,11.0]): rack('north_%02d'%i,(x,10.7,.3),damaged=i in [3,6])
for i,y in enumerate([8.1,5.95,3.8,-3.9,-6.1,-8.3]): rack('east_%02d'%i,(13.2,y,.3),-90,damaged=i==1)

def console(slug,loc,ang=0,width=3.2):
    pkg(slug,'数据操作终端_'+slug,'facilities',loc,ang)
    for x in [-width/2+.4,width/2-.4]:
        box('终端机座',(x,0,.85),(.72,1.45,1.7),'panel',1,.06)
        for z in [.35,.7,1.05]:
            box('抽屉分缝',(x,-.735,z),(.62,.03,.025),'black',1,.001)
            box('拉手',(x,-.77,z+.16),(.25,.07,.05),'steel',0)
    box('工作台厚边',(0,0,1.77),(width,1.6,.18),'steel',0,.05)
    box('工作台耐磨面',(0,0,1.88),(width-.1,1.5,.08),'dark',1)
    box('屏幕支架',(0,.28,2.1),(.12,.12,.42),'steel',0)
    box('屏幕外壳',(0,.28,2.55),(1.2,.18,.82),'steel',0,.04)
    box('屏幕玻璃',(0,.178,2.55),(1.05,.025,.66),'black',2,.01)
    for j in range(6):
        box('屏幕数据行',(-.14,.156,2.77-j*.085),(.61-j%3*.10,.012,.02),'cyan',3,.002)
    box('侧屏图表',(.37,.153,2.49),(.12,.015,.42),'blue',3,.002)
    box('键盘',(0,-.34,1.96),(.92,.37,.08),'black',1,.02)
    for y in range(3):
        for x in range(11): box('键帽',(-.4+x*.077,-.45+y*.095,2.01),(.05,.058,.022),'steel',0,.003)
    box('UPS柜',(width/2-.5,0,2.21),(.62,.95,.61),'black',0)
    box('UPS电源灯',(width/2-.5,-.49,2.27),(.44,.028,.075),'cyan',3)
    text('DATA // 02',(0,-.819,1.75),.13,'paper',(math.pi/2,0,0))

console('west_desk',(-12.85,-5.5,.3),90,3.8)
console('west_control',(-12.85,5.0,.3),90,3.0)
console('north_control',(-9.8,10.75,.3),0,3.2)

for i,(x,y,a) in enumerate([(3.2,8.4,-15),(10.8,4.4,65),(9.5,-8.2,12)]):
    pkg('fault_tray_%02d'%i,'脱落服务器模块_%02d'%i,'facilities',(x,y,.3),a)
    box('拆下服务器托架',(0,0,.24),(1.42,1.1,.45),'steel',0,.025)
    box('托架暗色面板',(0,-.56,.25),(1.28,.035,.29),'black',1)
    for j in range(6):
        box('托架插槽',(-.50+j*.2,-.59,.25),(.13,.02,.18),'dark',0,.006)
        box('托架指示',(-.5+j*.2,-.607,.25),(.025,.01,.04),'cyan',3,.002)
    for xx in [-.60,.60]: box('抽拉金属把手',(xx,-.65,.25),(.065,.16,.34),'silver',0,.015)
    for j in range(4): box('托架上盖格栅',(-.42+j*.28,0,.477),(.15,.64,.025),'black',0,.004)
for i,(x,y,a) in enumerate([(-13.5,8.1,90),(-5.1,11.9,0),(14.35,-2.25,-90)]):
    pkg('wall_service_%02d'%i,'墙边电控柜_%02d'%i,'facilities',(x,y,.3),a)
    box('电控柜壳',(0,0,1.28),(1.08,.64,2.56),'panel',1,.045)
    box('电控柜检修门',(0,-.34,1.4),(.94,.045,2.04),'dark',0,.02)
    for z in [.53,.64,.75, .86]: box('柜门散热条',(0,-.37,z),(.68,.025,.045),'black',1,.004)
    box('黄色警戒标签',(.1,-.379,1.54),(.24,.018,.34),'amber',1,.004)
    box('锁柄',(.37,-.40,1.35),(.04,.07,.19),'silver',0,.01)
    box('状态面板',(-.08,-.38,2.15),(.67,.04,.19),'black',2)
    for j in range(4): box('电控状态灯',(-.27+j*.13,-.407,2.15),(.04,.02,.048),'cyan' if j<3 else 'amber',3)

# Three low rugged service islands, with front-facing equipment and support straps.
for i,(x,y,a) in enumerate([(-4,4.0,0),(3,-4.5,0),(-4.5,-7.7,12)]):
    pkg('island_%02d'%i,'中央低矮数据设备岛_%02d'%i,'facilities',(x,y,.3),a)
    width=4.2 if i<2 else 3.4
    box('设备岛主机壳',(0,0,1.05),(width,1.50,2.1),'dark',1,.09)
    box('承重底框',(0,0,.17),(width+.2,1.72,.23),'steel',0,.035)
    box('加强顶盖',(0,0,2.15),(width+.08,1.62,.14),'steel',0,.04)
    for xx in [-width/2+.16,0,width/2-.16]:
        box('装甲防撞立柱',(xx,-.80,1.16),(.16,.18,2.2),'steel',0,.025)
        box('橙色固定带',(xx+.13,0,2.24),(.14,1.65,.035),'amber',1,.01)
    for xx in [-width/4,width/4]:
        box('设备岛黑玻璃窗',(xx,-.768,1.13),(width/2-.36,.045,1.45),'black',2,.04)
        for z in [.63,.94,1.27,1.60]:
            box('硬盘安装梁',(xx,-.81,z),(width/2-.48,.07,.15),'dark',0,.012)
            box('蓝光数据窗',(xx-.17,-.857,z),(width/2-.93,.02,.041),'cyan',3,.004)
            box('插槽指示灯',(xx+.49,-.863,z),(.055,.03,.07),'cyan',3,.008)
    for xx in [-width/2+.1,width/2-.1]:
        for j in range(5): box('侧向格栅',(xx,0,.55+j*.29),(.07,1.15,.07),'black',0,.008)
    for j in range(4): box('顶板锁扣',(-1.1+j*.72,-.5,2.25),(.21,.13,.09),'black',0,.02)
    text('PORTABLE  /  DATA ARRAY',(0,-.846,1.94),.13,'silver',(math.pi/2,0,0))
    if i==0:
        box('设备岛诊断屏底座',(-.7,0,2.3),(1.1,.58,.10),'black',1)
        box('设备岛诊断屏框',(-.7,.24,2.64),(1.0,.08,.64),'steel',0,.03)
        box('设备岛诊断屏',(-.7,.19,2.64),(.87,.02,.51),'black',2)
        for j in range(5): box('诊断信息',(-.76,.174,2.83-j*.08),(.63-j%2*.18,.01,.022),'cyan',3,.002)

pkg('technician_chair','检修工作椅_独立展示包','facilities',(-11,-5.4,.3),90)
current['fixed_display_attachment']=True
box('坐垫',(0,0,1.05),(.8,.79,.15),'black',1,.06)
box('椅背',(0,.32,1.65),(.84,.15,1.05),'black',1,.06,rot=(.12,0,0))
tube('升降柱',[(0,0,.14),(0,0,1.0)],.07,'steel',0)
for j in range(5):
    a=j*2*math.pi/5
    tube('五星底脚',[(0,0,.27),(.53*math.cos(a),.53*math.sin(a),.15)],.04,'steel',0)
    box('脚轮',(.53*math.cos(a),.53*math.sin(a),.1),(.15,.13,.17),'black',1,.04)
for x in [-.45,.45]:
    tube('扶手支架',[(x,0,1.0),(x,0,1.43)],.032,'steel',0)
    box('扶手垫',(x,-.04,1.45),(.12,.62,.1),'black',1,.03)

# The pictured flag is authored geometry, preserving its torn silhouette.
pkg('data_banner','数据部破损旗帜','facilities',(0,0,0))
verts=[]; nx=22; ny=16
for j in range(ny+1):
    for i in range(nx+1):
        x=-10.1+i*6/nx; z=4.4+j*4.6/ny
        if j==0: z+=random.uniform(-.28,.28)
        verts.append((x,11.93-.09*math.sin(i*.9+j*.3),z))
faces=[(j*(nx+1)+i,j*(nx+1)+i+1,(j+1)*(nx+1)+i+1,(j+1)*(nx+1)+i) for j in range(ny) for i in range(nx)]
mesh_custom('厚布旗帜',verts,faces,'black',1)
tube('旗杆',[(-10.4,11.84,9.15),(-3.7,11.84,9.15)],.055,'steel',0)
text('BASE CAMP',(-7.1,11.68,6.12),.66,'silver',(math.pi/2,0,0))
text('DATA DIVISION',(-7.1,11.67,5.52),.32,'silver',(math.pi/2,0,0))
for pts in [[(-8.5,11.66,8.37),(-5.7,11.66,8.37),(-7.1,11.66,6.8)],[(-8.0,11.66,7.98),(-6.2,11.66,7.98),(-7.1,11.66,6.98)]]:
    tube('部门三角徽记',pts,.075,'silver',1)

# Open jamb armour is outside the exact original 2.2m clear width.
for side,x,ang in [('east',14.51,-90),('west',-14.51,90)]:
    pkg(side+'_portal','东侧门洞装甲' if side=='east' else '西侧门洞装甲','facilities',(x,0,.3),ang,side=='west')
    for u in [-1.20,1.20]:
        box('门框立柱',(u,-.025,1.25),(.17,.24,2.5),'steel',0,.035)
        box('门框信号条',(u,-.16,1.5),(.045,.045,.55),'cyan',3)
    box('门楣护板',(0,0,2.68),(2.7,.25,.27),'steel',0,.045)
    box('门楣顶灯',(0,-.15,2.69),(1.65,.05,.07),'cyan',3)
    box('门禁底板',(1.53,-.1,1.55),(.32,.21,.56),'steel',0)
    box('门禁屏',(1.53,-.22,1.64),(.23,.022,.19),'cyan',3)

# Small independently packaged fixed scene dressing.
for i,(x,y) in enumerate([(-12.9,-9.5),(-11.7,8.4),(11.7,10.7)]):
    pkg('planter_%02d'%i,'固定绿植_%02d'%i,'facilities',(x,y,.3))
    box('盆器',(0,0,.42),(.7,.7,.84),'steel',1,.04)
    box('土面',(0,0,.85),(.61,.61,.04),'black',1)
    for j in range(9):
        a=j*2.4; z=1.05+random.random()*.55
        tube('植株枝茎',[(0,0,.84),(.15*math.cos(a),.15*math.sin(a),z)],.022,'green',1)
        tip=(.58*math.cos(a),.58*math.sin(a),z+.45)
        mesh_custom('叶片',[(0,0,z-.15),(.24*math.cos(a+.8),.24*math.sin(a+.8),z+.14),tip,(.24*math.cos(a-.8),.24*math.sin(a-.8),z+.14)],[(0,1,2,3)],'green',1)
for i,(x,y) in enumerate([(-13,-10.6),(12,-10.4),(9,7.7),(-10.8,-7.4)]):
    pkg('equipment_case_%02d'%i,'固定设备箱_%02d'%i,'facilities',(x,y,.3),i*15)
    box('运输箱壳',(0,0,.5),(1.35,.94,1),'dark',1,.07)
    box('运输箱盖',(0,0,1.06),(1.4,.99,.16),'steel',0,.04)
    for xx in [-.53,.53]: box('金属绑带',(xx,0,.56),(.08,1.02,1.12),'steel',0)
    box('锁扣',(0,-.51,.82),(.2,.09,.19),'amber',0)
    text('D-02',(0,-.49,.35),.17,'paper',(math.pi/2,0,0))

pkg('floor_cabling','跨设备地面电缆','support')
for x,y,w in [(0,9.3,1.8),(6.2,9.2,2),(11.4,5,1.3),(11.5,-6.3,1.5),(-3,3,2.2),(3,-5.7,2),(-12,-4,1.4)]: route_loop(x,y,w)
for j in range(4): tube('沿墙供电干线',[(-11+j*.08,9.6,.4),(-4,9.55-j*.08,.4),(3,9.5-j*.08,.4),(11,9.4-j*.08,.4),(11.7+j*.08,5,.4)],.032,'blue' if j%2 else 'rubber')
pkg('fixed_papers','固定展示散落文件','support')
current['fixed_display_attachment']=True
for i in range(48):
    x,y=random.choice([(-11,-6),(-9,10),(4,9),(12,-6),(1,-5)])
    x+=random.uniform(-1.4,1.4); y+=random.uniform(-.9,.9)
    box('废弃文件',(x,y,.32),(.28,.39,.007),'paper',1,.001,rot=(0,0,random.random()*6.28))

log('Facilities assembled; building editable/output mirrors')
# Evaluate source pieces into body and emission output, separately per package.
def combine(parts,name,collection):
    verts=[]; faces=[]; uvvals=[]; indices=[]; matlist=[]
    for o in parts:
        me=o.data; off=len(verts); verts.extend([o.matrix_world@v.co for v in me.vertices]); uv=me.uv_layers['PaletteUV']
        for p in me.polygons:
            faces.append(tuple(off+i for i in p.vertices)); uvvals.extend([tuple(uv.data[i].uv) for i in p.loop_indices])
            m=me.materials[p.material_index]
            if m not in matlist: matlist.append(m)
            indices.append(matlist.index(m))
    me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces)
    for m in matlist: me.materials.append(m)
    uv=me.uv_layers.new(name='PaletteUV'); uv.active_render=True
    for i,v in enumerate(uvvals): uv.data[i].uv=v
    for p,idx in zip(me.polygons,indices): p.material_index=idx
    o=bpy.data.objects.new(name,me); collection.objects.link(o); return o
bpy.context.view_layer.update()
for p in packages:
    c=p['collection']; src=coll('制作_'+p['name'],source)
    for emit in [False,True]:
        parts=[o for o in p['parts'] if (o.data.materials[0]==mats[3])==emit]
        if parts: combine(parts,p['name']+('_UI灯光_柔和自发光' if emit else '_附着细节_主体'),c)
    for o in p['parts']:
        c.objects.unlink(o); src.objects.link(o)
    objects=list(c.objects)
    for o in objects: o['package_id']=c['package_id']; o['block_id']='battle'; o['asset_id']='ENV-BATTLE-L01-ROOM-MAIN-02'
    bpy.context.view_layer.update()
    bs=[bounds(o) for o in objects]
    lower=[min(b[0][i] for b in bs) for i in range(3)]; upper=[max(b[1][i] for b in bs) for i in range(3)]
    manifest={'package_id':c['package_id'],'asset_id':'ENV-BATTLE-L01-ROOM-MAIN-02','name':p['name'],'slug':p['slug'],'category':p['cat'],'version':'v003','block_id':'battle','floor_range':'98–95F','design_scope':'主路内容房02','scene_design_docs':['docs/v0.1/05.1_关卡区块设计.md','docs/v0.1/10.1_3D场景美术生产流程.md'],'asset_ledger':'assets/registry/ShellStorm2_美术资产台账_v001.xlsx#3D-场景通用','source_blend':str(BLEND.relative_to(ROOT)),'blender_collection':c.name,'objects':[o.name for o in objects],'root_objects':[o.name for o in objects],'world_position':p['origin'],'local_origin':p['origin'],'forward':'Blender -Y / Godot -Z','bounds':[lower,upper],'dimensions':[upper[i]-lower[i] for i in range(3)],'material_roles':[m.name for m in mats],'emission':any('UI灯光' in o.name for o in objects),'animation':False,'dependencies':[],'fixed_display_attachment':p.get('fixed_display_attachment',False),'exported':False,'expected_export':p['slug']+'_v003.glb','collision_status':'未制作','cutaway_preview_only':p['cutaway']}
    dump(OUT/'component_packages_v003'/p['cat']/p['slug']/'asset_manifest.json',manifest)
    p['manifest']=manifest
source.hide_viewport=True; source.hide_render=True
for c in list(output.children):
    if not c.objects and not c.children: bpy.data.collections.remove(c)
dump(OUT/'component_packages_v003/catalog.json',[p['manifest'] for p in packages])
(OUT/'component_packages_v003/tree.txt').write_text('\n'.join(p['cat']+'/'+p['slug']+' / '+p['collection'].name for p in packages),encoding='utf8')

# Lighting/cameras are kept exclusively in the inspection collection.
def light(name,loc,energy,color,size):
    d=bpy.data.lights.new(name,'AREA'); d.energy=energy; d.color=color; d.shape='DISK'; d.size=size
    o=bpy.data.objects.new(name,d); display.objects.link(o); o.location=loc; o.rotation_euler=(Vector((0,0,1))-o.location).to_track_quat('-Z','Y').to_euler(); return o
light('冷白主光',(-8,-7,26),4200,(.63,.78,1),13)
light('机房顶反射',(7,8,21),2900,(.4,.66,1),10)
light('柔和前侧补光',(-15,-20,12),2300,(.72,.82,1),13)
light('微暖边缘光',(18,-7,14),750,(1,.74,.48),8)
for x,y in [(0,10),(10,9),(13,-5),(-12,-5)]: light('蓝色设备反射',(x,y,5.8),95,(.08,.48,1),3)
worlddata=bpy.data.worlds.new('机房冷灰展示环境'); scene.world=worlddata; worlddata.use_nodes=True
bg=next(n for n in worlddata.node_tree.nodes if n.type=='BACKGROUND'); bg.inputs[0].default_value=(.18,.24,.34,1); bg.inputs[1].default_value=.18
def camera(name,pos,target,ortho):
    d=bpy.data.cameras.new(name); d.type='ORTHO'; d.ortho_scale=ortho; d.clip_end=300
    o=bpy.data.objects.new(name,d); display.objects.link(o); o.location=pos; o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler(); return o
cam=camera('01_参考构图_剖切全景',(-37,-46,49),(0,0,3),46)
topcam=camera('02_顶视_完整墙体',(0,0,65),(0,0,0),34)
close=camera('03_机柜与旗帜近景',(-13,-12,17),(0,8,3.2),24)
scene.camera=cam; scene.render.engine='CYCLES'; scene.cycles.samples=32; scene.cycles.use_denoising=True
scene.render.resolution_x=1400; scene.render.resolution_y=1400; scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'; scene.view_settings.look='AgX - Medium High Contrast'; scene.view_settings.exposure=.60
scene.render.image_settings.file_format='PNG'; scene.render.film_transparent=False
scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
scene['block_id']='battle'; scene['asset_id']='ENV-BATTLE-L01-ROOM-MAIN-02'; scene['geometry_source']='v002 白盒：39个输出结构保持原几何与变换'
scene['review_note']='剖切展示层隐藏南墙/西墙，完整结构层保留全部11.9m墙体；切换图层查看。'
full=bpy.context.view_layer; full.name='01_完整结构_交付'
cut=scene.view_layers.new('02_剖切展示_仅隐藏近侧墙')
def locate(lc,name):
    if lc.name==name:return lc
    for child in lc.children:
        r=locate(child,name)
        if r:return r
for p in packages:
    if p['cutaway']: locate(cut.layer_collection,p['collection'].name).exclude=True
full.use=False; cut.use=True
for area in bpy.context.screen.areas if bpy.context.screen else []:
    if area.type=='VIEW_3D':
        area.spaces.active.region_3d.view_rotation=cam.rotation_euler.to_quaternion(); area.spaces.active.region_3d.view_distance=48; area.spaces.active.region_3d.view_location=(0,0,3)
        area.spaces.active.shading.type='MATERIAL'
bpy.context.view_layer.update()
after={n:signature(bpy.data.objects[n]) for n in locked}
changed=[n for n in locked if locked[n]!=after[n]]
checks={'locked_geometry_and_transforms':not changed,'original_output_count':len(originals)==39,'floor_tile_count':sum(p['slug'].startswith('floor_tile') for p in packages)==30,'packages_nonempty':all(len(p['collection'].objects)>0 for p in packages),'one_output_package_per_object':all(len(o.users_collection)==1 for p in packages for o in p['collection'].objects),'four_materials':len(bpy.data.materials)==4}
dump(OUT/'qa/task_validation.json',{'passed':all(checks.values()),'checks':checks,'changed_locked_objects':changed,'locked_count':len(locked),'after_signatures':after,'package_count':len(packages),'floor_tile_packages':30,'materials':[m.name for m in mats],'output_objects':sum(len(p['collection'].objects) for p in packages),'notes':'Materials/UV and authorized collection regrouping excluded from geometry lock; original backup preserves complete original materials.'})
assert all(checks.values()),checks
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND),compress=True)
log('SAVED '+str(BLEND))
def render(name,camera_obj,complete=False):
    scene.camera=camera_obj; full.use=complete; cut.use=not complete; scene.render.filepath=str(OUT/'renders'/name)
    bpy.ops.render.render(write_still=True); log('RENDERED '+name)
render('01_参考全景.png',cam)
render('02_完整结构顶视.png',topcam,True)
render('03_机柜旗帜近景.png',close)
scene.camera=cam; full.use=False; cut.use=True
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND),compress=True)
log('FINISHED')
