"""Reference-led bridge room deepening. Blender 4.5. Preserve v001 and gameplay contracts."""
from pathlib import Path
import bpy, math, json, hashlib, random, sys, argparse
from mathutils import Vector
HERE=Path(__file__).resolve(); OUT=HERE.parent; ROOT=HERE.parents[9]
OLD=OUT.parent/'v001'; RENDER=OUT/'renders'; RENDER.mkdir(exist_ok=True)
PALETTE=ROOT/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
WHITEBOX=ROOT/'source/art/whitebox/tower_zones/expedition_01/v001/data/room_templates/bridge_60x50.json'
REF=Path('C:/Users/zhuangmenghong/.workbuddy/clipboard-images/clipboard-2026-09-25T13-40-47-307Z-1c92b0f2.jpg')
BLEND='通道桥房间种类_工字型_30x60m_v002.blend'
args=argparse.ArgumentParser(); args.add_argument('--preview',action='store_true'); args.add_argument('--no-render',action='store_true')
opts=args.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
bpy.ops.wm.read_factory_settings(use_empty=True); scene=bpy.context.scene
scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
scene.render.engine='CYCLES'; scene.cycles.samples=32 if opts.preview else 64; scene.cycles.use_denoising=True
try:
    prefs=bpy.context.preferences.addons['cycles'].preferences; prefs.compute_device_type='OPTIX'; prefs.get_devices()
    for d in prefs.devices: d.use=d.type!='CPU'
    if any(d.use for d in prefs.devices): scene.cycles.device='GPU'
except Exception: pass
scene.render.resolution_x=1400; scene.render.resolution_y=1400; scene.render.resolution_percentage=65 if opts.preview else 100
scene.render.image_settings.file_format='PNG'; scene.render.film_transparent=False
scene.view_settings.view_transform='AgX'; scene.view_settings.look='AgX - Medium High Contrast'; scene.view_settings.exposure=0.0
world=bpy.data.worlds.new('冷灰蓝展示环境'); scene.world=world; world.use_nodes=True
world.node_tree.nodes.clear(); bg=world.node_tree.nodes.new('ShaderNodeBackground'); wo=world.node_tree.nodes.new('ShaderNodeOutputWorld'); world.node_tree.links.new(bg.outputs['Background'],wo.inputs['Surface']); bg.inputs['Color'].default_value=(.12,.18,.27,1); bg.inputs['Strength'].default_value=.45

def collection(name,parent):
    c=bpy.data.collections.new(name); parent.children.link(c); return c
root=collection('通道桥房间_参考图深化_v002',scene.collection)
src=collection('01_制作组件_按设施拆分',root)
game=collection('02_游戏输出_独立资产包_v002',root)
cats={k:collection(v,game) for k,v in [('architecture','01_建筑结构'),('floor','02_地面系统'),('facilities','03_区域固定设施'),('support','04_环境支持')]}
display=collection('90_展示与验收_灯光相机',root)
img=bpy.data.images.load(str(PALETTE),check_existing=True); img.filepath=str(PALETTE)
roles=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']
mats=[]
for i,(name,conf) in enumerate(zip(roles,[(.86,.28,.16),(.03,.70,0),(.18,.14,.66),(0,.36,0)])):
    m=bpy.data.materials.new(name); m.use_nodes=True; n=m.node_tree.nodes; n.clear(); l=m.node_tree.links
    u=n.new('ShaderNodeUVMap'); u.uv_map='PaletteUV'; t=n.new('ShaderNodeTexImage'); t.image=img; t.interpolation='Closest'
    bs=n.new('ShaderNodeBsdfPrincipled'); o=n.new('ShaderNodeOutputMaterial')
    bs.inputs['Metallic'].default_value=conf[0]; bs.inputs['Roughness'].default_value=conf[1]; bs.inputs['Coat Weight'].default_value=conf[2]
    l.new(u.outputs['UV'],t.inputs['Vector']); l.new(t.outputs['Color'],bs.inputs['Base Color'])
    if i==3: l.new(t.outputs['Color'],bs.inputs['Emission Color']); bs.inputs['Emission Strength'].default_value=1.5
    l.new(bs.outputs['BSDF'],o.inputs['Surface']); mats.append(m)
DARK=(9,0); PANEL=(9,1); EDGE=(9,3); STEEL=(9,5); WHITE=(9,9); BLUE=(7,6); CYAN=(8,5); AMBER=(8,3); ORANGE=(6,2); GREEN=(6,4)
packages=[]; current=None

def pack(slug,title,cat='architecture',cut=False):
    global current
    c=collection(title+'_资产包',cats[cat]); current={'slug':slug,'title':title,'category':cat,'col':c,'cutaway':cut,'items':[]}; packages.append(current); return current

def uv_mesh(mesh,cell):
    layer=mesh.uv_layers.new(name='PaletteUV'); mesh.uv_layers.active=layer; layer.active_render=True
    for p in mesh.polygons:
        for j,li in enumerate(p.loop_indices):
            a=2*math.pi*j/len(p.loop_indices); layer.data[li].uv=((cell[0]+.5)/10+.022*math.cos(a),1-(cell[1]+.5)/10+.022*math.sin(a))

def mesh_obj(name,verts,faces,mat=0,cell=PANEL,bevel=0):
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(verts,[],faces); mesh.update(); mesh.materials.append(mats[mat]); uv_mesh(mesh,cell)
    o=bpy.data.objects.new(('自发光_' if mat==3 else '')+name,mesh); current['col'].objects.link(o); current['items'].append(o)
    o['palette_cell']=list(cell); o['material_role']=mat
    if bevel:
        b=o.modifiers.new('机械倒角','BEVEL'); b.width=bevel; b.segments=2
        b=o.modifiers.new('加权法线','WEIGHTED_NORMAL')
    return o
cube_faces=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
def box(name,loc,dims,mat=0,cell=PANEL,bevel=.025):
    dx,dy,dz=[v/2 for v in dims]; v=[(-dx,-dy,-dz),(dx,-dy,-dz),(dx,dy,-dz),(-dx,dy,-dz),(-dx,-dy,dz),(dx,-dy,dz),(dx,dy,dz),(-dx,dy,dz)]
    o=mesh_obj(name,v,cube_faces,mat,cell,min(bevel,min(dims)*.2)); o.location=loc; return o

def rod(name,a,b,r=.08,mat=0,cell=EDGE,n=12):
    a,b=Vector(a),Vector(b); d=b-a; length=d.length; verts=[]
    for z in (-length/2,length/2):
        verts.extend([(r*math.cos(j*2*math.pi/n),r*math.sin(j*2*math.pi/n),z) for j in range(n)])
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)]
    o=mesh_obj(name,verts,faces,mat,cell); o.location=(a+b)/2; o.rotation_mode='QUATERNION'; o.rotation_quaternion=d.to_track_quat('Z','Y'); return o

def tube(name,points,r=.12,cell=EDGE,n=10):
    pts=[Vector(p) for p in points]; vs=[]
    for i,p in enumerate(pts):
        t=(pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]).normalized(); ref=Vector((0,0,1)) if abs(t.z)<.9 else Vector((1,0,0)); u=t.cross(ref).normalized(); v=t.cross(u).normalized()
        vs.extend([p+r*(u*math.cos(j*2*math.pi/n)+v*math.sin(j*2*math.pi/n)) for j in range(n)])
    fs=[tuple(reversed(range(n))),tuple(range((len(pts)-1)*n,len(pts)*n))]
    for i in range(len(pts)-1):
        for j in range(n): fs.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
    return mesh_obj(name,vs,fs,0,cell)

def lamp(loc,h=1.7):
    x,y,z=loc; box('立灯底座',(x,y,z+.12),(.42,.42,.24),0,DARK)
    box('立灯铠装',(x,y,z+h/2),(.28,.28,h),0,EDGE)
    box('暖白灯芯',(x,y-.16,z+h*.68),(.13,.05,h*.5),3,AMBER)
    box('灯具遮罩',(x,y,z+h),(.40,.39,.14),0,DARK)

def rail(a,b,z=0,posts=5,warm=True):
    a,b=Vector((a[0],a[1],z)),Vector((b[0],b[1],z)); d=b-a
    for i in range(posts+1):
        p=a+d*i/posts; box('栏杆工字立柱',(p.x,p.y,z+.68),(.14,.18,1.36),0,EDGE)
        box('黄色柱顶',(p.x,p.y,z+1.35),(.2,.22,.11),0,AMBER)
        box('栏杆安装法兰',(p.x,p.y,z+.06),(.33,.32,.12),0,STEEL)
    for h,r in [(1.31,.065),(.72,.045),(.22,.045)]: rod('栏杆连续横梁',a+Vector((0,0,h)),b+Vector((0,0,h)),r,0,EDGE)
    if warm:
        for f in (.05,.50,.95):
            p=a+d*f; lamp((p.x,p.y,z),1.8)

def area(name,loc,power,color,size,target):
    data=bpy.data.lights.new(name,'AREA'); data.energy=power; data.color=color; data.shape='DISK'; data.size=size
    o=bpy.data.objects.new(name,data); display.objects.link(o); o.location=loc; o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler(); return o

def bolts(x,y,z,w,d):
    for sx in (-1,1):
        for sy in (-1,1): rod('固定螺栓',(x+sx*w,y+sy*d,z),(x+sx*w,y+sy*d,z+.035),.045,0,STEEL,6)

# All visual surfaces are rebuilt, while the mathematical whitebox contract is frozen.
rng=random.Random(250925)
floor_bases=[]
def tile(ix,iy,z):
    x=ix*5+2.5; y=iy*5+2.5; lower=z<0
    p=pack(f'tile_{"lower" if lower else "upper"}_{ix}_{iy}',f'地砖_{"下" if lower else "上"}_{ix}_{iy}','floor')
    o=box('结构地砖',(x,y,z-.16),(5,5,.32),0,DARK,0); o['contract_floor_base']=True; floor_bases.append(o)
    for sx in (-1,1):
        for sy in (-1,1):
            box('分块耐磨钢板',(x+sx*1.21,y+sy*1.21,z+.024),(2.36,2.36,.048),0,PANEL,.015)
    for dx in (-2.44,2.44):
        box('拼缝轨道',(x+dx,y,z+.056),(.055,4.9,.028),0,EDGE,.005)
    for dy in (-2.44,2.44): box('拼缝轨道',(x,y+dy,z+.056),(4.9,.055,.028),0,EDGE,.005)
    bolts(x,y,z+.052,2.30,2.30)
    if (ix+iy)%3==0:
        box('凹入检修口',(x+.55,y+.35,z+.056),(1.7,1.18,.025),1,DARK)
        for j in range(9): box('检修格栅叶片',(x-.14+j*.17,y+.35,z+.086),(.075,1.02,.035),0,EDGE,.005)
    if not lower and abs(x)<5:
        for j in range(3):
            o=box('人行虚线标记',(x-.35,y-1.4+j*.72,z+.058),(.34,.40,.013),1,WHITE,.002); o.rotation_euler.z=.2
    # Small irregular wear patches stay attached to this tile; palette only, no private maps.
    for j in range(8 if not lower else 3):
        xx=x+rng.uniform(-2.15,2.15); yy=y+rng.uniform(-2.15,2.15); rr=rng.uniform(.07,.32)
        verts=[]
        for k in range(7):
            a=k*math.pi*2/7; rad=rr*rng.uniform(.55,1.4); verts.append((xx+rad*math.cos(a),yy+rad*math.sin(a),z+.051))
        mesh_obj('局部不规则磨损斑',verts,[tuple(range(7))],1,DARK if j%2 else PANEL)
    # Small physical scuffs are subordinate to large panels, no extra textures.
    for j in range(9 if not lower else 2):
        o=box('边缘磨痕',(x+rng.uniform(-2,2),y+rng.uniform(-2,2),z+.055),(rng.uniform(.09,.25),.015,.004),0,EDGE,0); o.rotation_euler.z=rng.uniform(-1,1)
for iy in range(-6,6):
    for ix in range(-3,3):
        if abs(iy+.5)>=3 or ix in (-1,0): tile(ix,iy,0)
for iy in range(-3,3):
    for ix in range(-3,3): tile(ix,iy,-12)

# Wall bays face inward on every side. Near walls are hidden only for named cutaway renders.
wall_bases=[]
def wall_bay(side,k):
    long=side in ('east','west'); sign=1 if side in ('east','north') else -1
    pos=k*5+2.5; cut=side in ('west','south'); p=pack(f'wall_{side}_{k}',f'{side}_墙体_{k}','architecture',cut)
    def pt(u,v,z): return (sign*(15-v),pos+u,z) if long else (pos+u,sign*(30-v),z)
    def wb(name,u,v,z,w,d,h,mat=0,cell=PANEL):
        return box(name,pt(u,v,z),(d,w,h) if long else (w,d,h),mat,cell,.025)
    isdoor=not long and k==-1
    if isdoor:
        for u in (-1.8,1.8): wall_bases.append(wb('门洞边柱',u,0,5.95,1.4,.3,11.9))
        wall_bases.append(wb('门洞过梁',0,0,7.35,2.2,.3,9.1))
        wb('门槛',0,0,.15,2.2,.3,.3)
        for u in (-1.22,1.22): wb('门框轨道',u,.22,1.65,.15,.18,2.7,0,EDGE)
        wb('门头灯盒',0,.25,3.15,2.8,.26,.3,0,DARK); wb('门楣蓝灯',0,.4,3.15,2.5,.06,.10,3,BLUE)
    else:
        wall_bases.append(wb('标准结构墙',0,0,5.95,5,.3,11.9,1,PANEL))
        for z,h in [(1.6,2.65),(5.3,4.1),(9.8,3.0)]: wb('内嵌装甲板',0,.19,z,4.65,.15,h,1,PANEL)
    for u in (-2.34,2.34): wb('墙面纵向压筋',u,.34,5.9,.12,.16,11.5,0,EDGE)
    for z in (3.25,8.5): wb('墙面横向管槽',0,.38,z,4.8,.15,.14,0,DARK)
    wb('可维护踢脚梁',0,.28,.20,4.85,.3,.25,0,EDGE)
    for z in (8.75,9.02):
        rod('墙上成束导管',pt(-2.45,.45,z),pt(2.45,.45,z),.07,0,EDGE)
    # Secondary panel seams, fasteners and short conduit runs, never more flat blank walls.
    for u in (-1.8,1.8):
        wb('墙面分区竖脊',u,.31,6.1,.075,.12,8.5,0,DARK)
        for z in (1.0,3.5,6.8,10.9): wb('墙板固定扣',u,.42,z,.15,.12,.21,0,STEEL)
    for z in (4.1,6.5,10.6):
        if not isdoor: wb('钢板横向阴缝',0,.28,z,4.45,.08,.045,0,DARK)
    wb('墙面检修铭牌',1.25,.41,2.9,.52,.05,.27,0,EDGE)
    for zz in (5.0,5.22): rod('壁装支线',pt(-2.3,.42,zz),pt(-.3,.42,zz),.035,0,STEEL,8)
    if k%2==0:
        wb('壁灯底座',1.9,.45,4.45,.4,.22,1.8,0,DARK); wb('暖白壁灯',1.9,.60,4.45,.12,.06,1.55,3,AMBER)
        wb('蓝色识别灯',0,.48,7.85,2.2,.08,.10,3,BLUE)
for side in ('north','south'):
    for k in range(-3,3): wall_bay(side,k)
for side in ('east','west'):
    for k in range(-6,6): wall_bay(side,k)

# Lower envelope, uninterrupted 12m shafts and broad bridge girders.
for s in (-1,1):
    for k in range(-3,3):
        y=k*5+2.5; pack(f'pit_side_{s}_{k}',f'坑壁_{s}_{k}','architecture',s<0)
        box('坑壁下延',(s*15,y,-6),(.3,5,12),1,PANEL,.02)
        for z in (-3.0,-7.0,-10.9):
            box('坑壁装甲分层',(s*14.77,y,z),(.12,4.65,2.45),0,PANEL)
            box('坑壁分层腰梁',(s*14.60,y,z+1.38),(.3,5,.24),0,EDGE)
    for y in (-15,15):
        for x in (s*7.5,s*12.5):
            pack(f'pit_end_{x}_{y}',f'坑端壁_{x}_{y}','architecture',y<0)
            box('坑端壁',(x,y,-6),(5,.3,12),1,PANEL)
    pack(f'bridge_girder_{s}',f'桥侧连续箱梁_{s}')
    box('桥侧承重深梁',(s*4.86,0,-.55),(.45,30,1.1),0,DARK,.045)
    for z in (-.13,-1.02): box('箱梁翼缘',(s*4.93,0,z),(.62,30,.16),0,EDGE)
    for y in range(-14,15,2): box('箱梁竖向加劲板',(s*5.19,y,-.54),(.08,.14,.8),0,STEEL,.005)
    box('桥梁蓝色连续灯',(s*5.20,0,-.23),(.06,28,.07),3,BLUE,.005)
    pack(f'bridge_guardrail_{s}',f'桥面完整护栏_{s}'); rail((s*4.86,-15),(s*4.86,15),0,12)
    for y in (-15,15):
        pack(f'platform_edge_{s}_{y}',f'上层平台坑沿护栏_{s}_{y}')
        rail((s*5.15,y),(s*14.65,y),0,5)
        box('平台断面箱梁',(s*10,y,-.65),(10,.5,1.3),0,DARK)
        box('平台断面翼缘',(s*10,y,-1.27),(10,.65,.12),0,EDGE)

# Three explicit levels: 0 deck / -4.2 service gallery / -7.4 and -8.6 machinery platforms / -12 floor.
platform_tops=[]
def grating(slug,x,y,z,w,d):
    p=pack(slug,'错层钢格栅检修平台_'+slug,'support',slug=='mid_gallery_-1'); p['lower_decor_only']=True
    for yy in (y-d/2,y+d/2): box('平台结构框长边',(x,yy,z-.17),(w,.16,.34),0,DARK)
    for xx in (x-w/2,x+w/2): box('平台结构框短边',(xx,y,z-.17),(.16,d,.34),0,DARK)
    # True crossed open grating; no solid plate sealing the shaft.
    for j in range(int(w/.23)):
        box('密集钢格栅',(x-w/2+.12+j*.23,y,z+.02),(.055,d-.10,.08),0,EDGE,.005)
    for j in range(int(d/.6)):
        box('格栅横拉筋',(x,y-d/2+.12+j*.6,z+.005),(w-.1,.045,.10),0,STEEL,.004)
    for yy in (y-d/2,y+d/2):
        box('平台槽钢边梁',(x,yy,z-.02),(w,.12,.24),0,EDGE)
        rail((x-w/2,yy),(x+w/2,yy),z, max(2,int(w/2)),False)
    for xx in (x-w/2,x+w/2): rail((xx,y-d/2),(xx,y+d/2),z,max(2,int(d/2)),False)
    # Explicit piers from platform frame to pit floor, plus triangulated brackets.
    for xx in (x-w*.4,x+w*.4):
        for yy in (y-d*.36,y+d*.36):
            box('检修平台承重立柱',(xx,yy,(-12+z-.25)/2),(.20,.20,z-.25+12),0,EDGE)
            box('立柱锚固底座',(xx,yy,-11.91),(.48,.48,.18),0,STEEL)
        rod('下托斜撑',(xx,y-d*.36,z-.2),(xx,y+d*.36,z-1.8),.12,0,EDGE)
    lamp((x+w*.4,y-d*.36,z),1.25)
    platform_tops.append(z)
for s in (-1,1):
    grating(f'mid_gallery_{s}',s*13.45,0,-4.2,2.45,27.5)
    for n,(y,z) in enumerate([(-10,-7.4),(1.5,-8.6),(10.5,-7.4)]):
        grating(f'low_platform_{s}_{n}',s*9.65,y,z,5.7,4.0)
    grating(f'cross_gantry_{s}',s*9.5,-3.8,-5.7,8.4,1.65)
    for y in (-14,-5,5,14):
        pack(f'shaft_column_{s}_{y}',f'贯穿层间主柱_{s}_{y}')
        box('通高工字柱腹板',(s*6.0,y,-6),(.46,.7,12),0,DARK)
        for xx in (s*5.68,s*6.32): box('工字柱翼缘',(xx,y,-6),(.18,1.15,12),0,EDGE)
        for z in (-10.3,-6.3,-2.3):
            box('柱节连接套',(s*6,y,z),(1.05,1.4,.4),0,STEEL)
            box('柱侧嵌入蓝灯',(s*6.6,y-.27,z+1.2),(.08,.13,1.7),3,BLUE,.005)
        box('柱脚基础',(s*6,y,-11.68),(1.8,1.8,.64),0,DARK)
    for z in (-4.8,-9.6):
        pack(f'longitudinal_tie_{s}_{z}',f'下层纵向腰梁_{s}_{z}')
        box('纵向结构梁',(s*6.0,0,z),(.45,29,.5),0,EDGE)

# Large segmented elbow pipes: actual curved geometry, flanges, bolted saddles.
def pipe_run(slug,s,y,z):
    pack(slug,'下层粗管弯头_'+slug,'support'); x=s*7.0
    # Rising elbows are outside the grating footprint, avoiding pipe-through-floor intersections.
    y=y-2.2
    pts=[(x,y-2.0,z-2),(x,y-2,z-.65)]
    for j in range(9):
        t=j*math.pi/2/8; pts.append((x,y-1.35-.65*math.cos(t),z-.65+.65*math.sin(t)))
    pts.extend([(x,y+2,z),(x,y+3,z)])
    tube('大口径冷却主管',pts,.36,EDGE,16)
    for yy in (y-1.2,y-.2,y+.8,y+1.8,y+2.8):
        rod('主管分段法兰',(x,yy-.07,z),(x,yy+.07,z),.47,0,STEEL,16)
        for j in range(8):
            a=j*math.pi/4; rod('法兰螺栓',(x+.405*math.cos(a),yy-.10,z+.405*math.sin(a)),(x+.405*math.cos(a),yy+.10,z+.405*math.sin(a)),.036,0,DARK,6)
for s in (-1,1):
    for n,(y,z) in enumerate([(-9,-6.4),(1,-7.6),(9,-6.4)]): pipe_run(f'coolant_{s}_{n}',s,y,z)
    pack(f'deep_trunk_{s}',f'坑底贯穿管束_{s}','support')
    for i in range(3):
        x=s*(8+i*.6); rod('坑底主管',(x,-14,-10.7),(x,14,-10.7),.18 if i else .28,0,EDGE,14)
        for y in (-12,-6,0,6,12): rod('主管管卡',(x,y-.05,-10.7),(x,y+.05,-10.7),.24 if i else .35,0,STEEL)

# Rich electrical cabinets, servers, control desks: proportions grouped rather than evenly scattered.
def cabinet(slug,x,y,w=1.8,h=3.8,kind='server',yaw=0,z=0):
    p=pack(slug,'机房设备_'+slug,'facilities'); start=len(p['items'])
    box('设备基础',(0,0,.12),(w+.18,1.28,.24),0,DARK)
    box('折边钢制机壳',(0,0,h/2+.22),(w,1.08,h),1,GREEN if kind=='power' else PANEL,.07)
    for xx in (-w/2+.07,w/2-.07):
        box('加强立框',(xx,-.62,h/2+.2),(.15,.19,h),0,EDGE)
        box('黄色机械护角',(xx,-.73,h-.05),(.16,.06,.42),0,AMBER)
    box('顶部压盖',(0,0,h+.26),(w+.12,1.20,.18),0,EDGE)
    # Rear and side service panels remain legible from the reference cutaway camera.
    box('背部检修装甲',(0,.58,h*.5),(w-.18,.12,h-.25),0,PANEL)
    for xx in (-w*.35,w*.35): box('背部纵向肋条',(xx,.69,h*.5),(.11,.1,h-.1),0,EDGE)
    for zz in (.6,h*.55,h-.4):
        box('背部横向压条',(0,.7,zz),(w-.2,.08,.12),0,EDGE)
        for j in range(4): box('背部散热叶',(0,.725,zz+.2+j*.09),(w*.55,.06,.035),0,DARK,.005)
    for xx in (-w/2-.03,w/2+.03):
        box('侧面内嵌检修门',(xx,0,h*.5),(.08,.70,h-.6),0,PANEL)
        for zz in (.7,h-.5): box('侧面机械压边',(xx,0,zz),(.12,.8,.11),0,EDGE)
    if kind=='server':
        for j in range(int(h/.42)-1):
            zz=.54+j*.42
            box('热插拔服务器模块',(0,-.585,zz),(w-.3,.14,.32),0,DARK)
            for k in range(5): box('服务器散热狭槽',(-w*.23+k*w*.1,-.67,zz),(.065,.045,.20),0,EDGE,.005)
            for xx in (-w*.36,w*.36): box('抽屉锁扣',(xx,-.70,zz),(.10,.06,.14),0,STEEL)
            box('运行状态蓝灯',(-w*.25,-.72,zz+.09),(.32,.035,.035),3,BLUE,.002)
    else:
        for zz in (.85,h*.65):
            box('配电柜门',(0,-.61,zz),(w-.33,.08,h*.35),1,GREEN)
            box('铰链',(w*.37,-.69,zz),(.11,.09,.32),0,STEEL)
        box('高压标示底牌',(-w*.12,-.675,h*.70),(.47,.03,.46),1,AMBER)
        bolt=box('高压闪电标示',(-w*.12,-.70,h*.70),(.07,.024,.3),1,DARK,.002); bolt.rotation_euler.y=.4
        box('门锁手柄',(w*.25,-.73,h*.49),(.10,.1,.35),0,STEEL)
        for j in range(5): box('下部通风叶',(0,-.685,.47+j*.11),(w-.4,.045,.045),0,DARK,.005)
    for o in p['items'][start:]:
        o.location=Vector((x,y,z))+Vector((math.cos(yaw)*o.location.x-math.sin(yaw)*o.location.y,math.sin(yaw)*o.location.x+math.cos(yaw)*o.location.y,o.location.z)); o.rotation_euler.z+=yaw
    p['fixed_display_attachment']=True

def console(slug,x,y,yaw=0):
    p=pack(slug,'机房操作站_'+slug,'facilities')
    box('操作站底座',(0,0,.1),(1.1,.9,.2),0,DARK)
    box('折线操作柱',(0,0,.75),(.83,.66,1.4),1,PANEL)
    box('操作台托盘',(0,-.23,1.43),(1.12,.95,.14),0,EDGE)
    for j in range(6): box('实体键盘键',(-.35+j*.14,-.57,1.53),(.09,.13,.035),0,STEEL,.008)
    ob=box('后倾显示器',(0,.15,2.02),(1.12,.18,.92),0,DARK); ob.rotation_euler.x=-.15
    ob=box('屏幕玻璃',(0,.028,2.03),(.95,.04,.73),2,BLUE); ob.rotation_euler.x=-.15
    for j in range(5): box('屏幕数据行',(-.13,-.04,1.8+j*.10),(.45 if j%2 else .65,.03,.026),3,WHITE,.002)
    for j in range(4): box('屏幕状态块',(.3,-.04,1.82+j*.12),(.1,.03,.07),3,CYAN,.002)
    for o in p['items']:
        p0=o.location.copy(); o.location=(x+math.cos(yaw)*p0.x-math.sin(yaw)*p0.y,y+math.sin(yaw)*p0.x+math.cos(yaw)*p0.y,p0.z); o.rotation_euler.z+=yaw

def crate(slug,x,y,w=1.8,z=0,yaw=0):
    p=pack(slug,'固定维护箱_'+slug,'facilities'); p['fixed_display_attachment']=True
    box('维护箱主体',(0,0,.70),(w,1.35,1.4),1,PANEL,.08)
    box('维护箱盖',(0,0,1.43),(w+.08,1.43,.18),0,EDGE)
    for xx in (-w*.35,w*.35):
        box('箱体黄色绑带',(xx,0,.73),(.15,1.48,1.53),0,ORANGE)
        box('绑带锁扣',(xx,-.78,.83),(.26,.12,.25),0,STEEL)
    box('箱侧内嵌板',(0,-.72,.70),(w*.48,.10,.79),0,DARK)
    box('箱侧抬手',(0,-.8,1.0),(w*.28,.10,.12),0,STEEL)
    box('维护箱背面嵌板',(0,.71,.7),(w*.63,.09,.88),0,DARK)
    box('维护箱背面提手',(0,.78,1.03),(w*.35,.09,.14),0,STEEL)
    for xx in (-w/2,w/2):
        box('箱体侧护角',(xx,0,.7),(.12,1.1,1.25),0,EDGE)
        box('侧面铭牌',(xx,0,.95),(.15,.42,.19),1,AMBER)
    for o in p['items']:
        q=o.location.copy(); o.location=(x+math.cos(yaw)*q.x-math.sin(yaw)*q.y,y+math.sin(yaw)*q.x+math.cos(yaw)*q.y,z+q.z); o.rotation_euler.z+=yaw

# Rear machine bank at both ends, perpendicular end-wall utility group, pit-edge half partitions.
for s in (-1,1):
    y=s*22
    for j in range(3): cabinet(f'upper_bank_{s}_{j}',12.8,y+j*2.75-2.75,2.45,5.1+(.6 if j==0 else 0),'power' if j==0 else 'server',-math.pi/2)
    console(f'upper_console_{s}',10.5,y-4.7,-math.pi/2)
    for j in range(2): crate(f'bank_crate_{s}_{j}',11.4-j*1.5,y+4,1.45,z=.0 if j==0 else 1.5)
    cabinet(f'end_power_{s}',5.9,s*28.2,2.6,4.9,'power',math.pi if s<0 else 0)
    crate(f'end_crate_{s}',3.0,s*27.5,2.0)
    crate(f'near_crate_{s}',-10,s*25,2.4,yaw=.1*s)
    cabinet(f'near_server_{s}',-12.8,s*19.5,2.5,4.7,'server',math.pi/2)
    pack(f'half_partition_{s}','机房设备隔断_'+str(s))
    box('机房半高分区墙',(-10,s*17.7,1.0),(7.6,.36,2),0,DARK)
    for xx in (-13,-10,-7):
        box('隔断装甲板',(xx,s*17.7,1.1),(2.7,.50,1.45),1,PANEL)
        box('隔断顶槽',(xx,s*17.7,2.1),(2.8,.60,.18),0,EDGE)
    crate(f'partition_box_{s}',-6.8,s*20.2,1.5)
# Lower machinery is attached to staggered platforms, not uniformly dumped at the bottom.
for s in (-1,1):
    for n,(y,z) in enumerate([(-10,-7.4),(1.5,-8.6),(10.5,-7.4)]):
        cabinet(f'lower_control_{s}_{n}',s*9.1,y+.55,1.15,2.25,'server',0,z+.06)
    for y in (-10,0,10):
        pack(f'vertical_service_{s}_{y}',f'竖井服务柜列_{s}_{y}','facilities')
        box('竖井冷却设备',(s*14.1,y,-8.7),(1.3,2.0,5.5),0,DARK)
        box('冷却柜落地承重基座',(s*14.1,y,-11.725),(1.4,2.2,.55),0,EDGE)
        for zz in (-10.9,-6.3): box('设备挂墙托架',(s*14.65,y,zz),(.70,2.1,.18),0,STEEL)
        for j in range(9):
            box('竖井连续状态灯',(s*13.39,y-.3,-11.1+j*.51),(.045,.38,.16),3,BLUE)
            box('冷却百叶',(s*13.38,y+.32,-11.1+j*.51),(.06,.52,.07),0,STEEL)

# Reference focal point: exposed wall header with broken cladding, thick U-shaped sagging bundles.
for s in (-1,1):
    pack(f'wall_service_header_{s}',f'架空墙侧管廊_{s}','support',s<0)
    for z in (8.2,8.55,8.9):
        rod('壁顶主管',(s*14.2,-14,z),(s*14.2,14,z),.14,0,EDGE,16)
    for y in (-12,-5,3,11):
        box('管廊承托架',(s*13.9,y,8.5),(1.6,.25,.25),0,STEEL)
    for n,y in enumerate((-10,-1,8)):
        pack(f'torn_header_{s}_{n}',f'破损管廊护板_{s}_{n}','support',s<0)
        # Jagged suspended sheet, not a uniformly rectangular banner.
        x=s*13.5
        verts=[(x,y-2.3,10.7),(x,y+2.1,10.7),(x,y+2.0,7.6),(x,y+1.2,7.8),(x,y+.7,6.4),(x,y-.1,6.9),(x,y-.8,6.5),(x,y-1.6,7.2),(x,y-2.3,7.0)]
        o=mesh_obj('撕裂装甲护板',verts,[tuple(range(len(verts)))],0,PANEL); so=o.modifiers.new('护板实体厚度','SOLIDIFY'); so.thickness=.08
        pack(f'header_cables_{s}_{n}',f'架空垂落电缆束_{s}_{n}','support',s<0)
        for j in range(7):
            pts=[]
            for k in range(25):
                t=k/24; pts.append((s*(13.0-j*.105),y-3.0+t*6.4,8.7-(3.0+j*.21)*math.sin(math.pi*t)))
            tube('下垂橡胶重电缆',pts,.055 if j%2 else .085,ORANGE if j==2 else DARK,8)
    # Cables continue below upper floor; silhouette seen against lit shaft backplane.
    for n,y in enumerate((-9,3,10)):
        pack(f'deep_cables_{s}_{n}',f'跨层下垂电缆_{s}_{n}','support')
        for j in range(5):
            pts=[]
            for k in range(25):
                t=k/24; pts.append((s*(7.15+j*.14+1.6*math.sin(math.pi*t)),y-2+4*t,-.3-(6+j*.42)*math.sin(math.pi*t)))
            tube('跨层悬垂电缆',pts,.07,DARK if j!=2 else ORANGE,8)

# The reference reads as a machinery shaft, not an empty basement: recessed structural backplanes under bridge.
for s in (-1,1):
    for n,y in enumerate((-10,0,10)):
        pack(f'underbridge_service_bay_{s}_{n}',f'桥下竖井设备背板_{s}_{n}','facilities')
        x=s*4.25
        box('凹进竖井设备背板',(x,y,-6.6),(.35,6.3,9.4),1,DARK)
        for yy in (y-2.6,y+2.6):
            box('设备竖向护轨',(x+s*.25,yy,-6.6),(.20,.15,9.4),0,EDGE)
            for zz in (-10.5,-9.5,-8.5,-7.5,-6.5,-5.5,-4.5):
                box('竖井冷蓝窗格',(x+s*.38,yy,zz),(.045,.13,.36),3,BLUE,.005)
        for zz in (-10.6,-7.4,-4.2): box('背板横向结构梁',(x+s*.28,y,zz),(.22,6.1,.18),0,EDGE)
        # Circular extraction fan assembly facing the side shafts.
        center=Vector((x+s*.4,y,-3.5))
        rod('工业风机壳',center-Vector((s*.14,0,0)),center+Vector((s*.14,0,0)),1.15,0,DARK,32)
        for j in range(8):
            a=j*math.pi/4; a2=a+.35
            p1=center+Vector((s*.22,.2*math.cos(a),.2*math.sin(a)))
            p2=center+Vector((s*.22,.95*math.cos(a2),.95*math.sin(a2)))
            rod('风机斜叶',p1,p2,.16,0,EDGE,6)
        rod('风机中心轴',center,center+Vector((s*.36,0,0)),.21,0,STEEL,16)
        for yy in (y-.8,y-.4,y,y+.4,y+.8): box('风机防护竖栅',(x+s*.8,yy,-3.5),(.035,.035,2.1),0,STEEL,.002)
# Sparse overhead support at ends only: no roof grid hiding the bridge.
for y in (-14,14):
    pack(f'bridge_service_transom_{y}',f'桥端设备支承横梁_{y}','support')
    box('桥端下部横担',(0,y,-1.1),(10,.32,.36),0,EDGE)

# Lighting is presentation-only, game assets keep emissive meshes but no baked lighting assumptions.
area('主光_冷白',(-25,-25,48),26000,(.70,.83,1),32,(0,0,-2))
area('后缘冷蓝',(22,16,26),18000,(.22,.49,1),20,(0,0,-3))
area('前部柔光',(-28,-10,10),9000,(.46,.65,1),24,(0,0,-5))
area('平台暖反射',(4,-27,14),5500,(1,.70,.40),12,(0,-22,0))
for yy in (-22,22):
    area(f'上层机房冷白工作光_{yy}',(4,yy,9),3800,(.65,.8,1),9,(8,yy,1.8))
    area(f'机柜立面补光_{yy}',(6,yy,4.5),1100,(.35,.64,1),5,(13,yy,2))
for s in (-1,1):
    for y in (-10,0,10):
        area(f'竖井蓝色层光_{s}_{y}',(s*13.5,y,-2.5),1100,(.10,.48,1),3,(s*8,y,-10))
        area(f'下层暖检修灯_{s}_{y}',(s*9,y,-6),160,(1,.66,.27),1,(s*9,y,-9))
        area(f'下层反射补光_{s}_{y}',(s*10,y,-10.8),650,(.10,.50,1),2,(s*13,y,-4))

def camera(name,loc,target,scale):
    d=bpy.data.cameras.new(name); o=bpy.data.objects.new(name,d); display.objects.link(o); o.location=loc
    o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler(); d.type='ORTHO'; d.ortho_scale=scale; d.clip_end=500; return o
cam=camera('参考镜头_剖视全景',(-58,-72,62),(0,0,-1.0),70)
cam_lower=camera('参考镜头_下层结构',(-40,-27,13),(-6,-1,-5.2),36)
cam_upper=camera('参考镜头_上层机房',(-30,-45,27),(5,-22,1.5),30)
cam_top=camera('参考镜头_顶视',(0,0,100),(0,0,0),68)
cam_complete=camera('参考镜头_完整外墙',(-58,-72,72),(0,0,-1),79)

# Measured task QA before packaging, not a literal PASS declaration.
bpy.context.view_layer.update()
def bounds(objects):
    pts=[o.matrix_world@Vector(v) for o in objects for v in o.bound_box]
    return [[round(min(p[i] for p in pts),5) for i in range(3)],[round(max(p[i] for p in pts),5) for i in range(3)]]
upper=[o for o in floor_bases if o.location.z>-1]; lower=[o for o in floor_bases if o.location.z<-1]
bridge=[o for o in upper if abs(o.location.y)<15]
bb=bounds(bridge); ub=bounds(upper); lb=bounds(lower)
wb=json.loads(WHITEBOX.read_text(encoding='utf-8'))
checks={
 'template_dimensions_locked':wb['size_m']==[30.0,60.0],
 'upper_floor_extent_measured':ub[0][:2]==[-15,-30] and ub[1][:2]==[15,30],
 'bridge_extent_measured':bb[0][:2]==[-5,-15] and bb[1][:2]==[5,15],
 'pit_floor_extent_measured':lb[0][:2]==[-15,-15] and lb[1][:2]==[15,15],
 'pit_floor_surface_z_measured':abs(lb[1][2]+12)<.0001,
 'floor_tiles_all_5m':all(abs(o.dimensions.x-5)<.0001 and abs(o.dimensions.y-5)<.0001 for o in floor_bases),
 'upper_tiles_48_lower_tiles_36':len(upper)==48 and len(lower)==36,
 'visible_wall_top_11_9':abs(max(bounds([o])[1][2] for o in wall_bases)-11.9)<.001,
 'layered_platforms_measured':set(platform_tops)=={-4.2,-5.7,-7.4,-8.6},
 'palette_external_unique':img.packed_file is None and Path(bpy.path.abspath(img.filepath)).resolve()==PALETTE.resolve(),
 'four_materials':len(bpy.data.materials)==4,
 'all_packages_nonempty':all(p['items'] for p in packages),
}
assert all(checks.values()),checks

# Evaluate and merge per semantic package; preserve individual editable pieces in hidden source.
# UV islands are rebuilt per face into their original cell after bevel/solidify evaluation.
def merge_package(p,emission):
    objs=[o for o in p['items'] if (o['material_role']==3)==emission]
    if not objs: return None
    dg=bpy.context.evaluated_depsgraph_get(); vs=[]; fs=[]; mi=[]; cells=[]
    used=[3] if emission else [0,1,2]
    for o in objs:
        e=o.evaluated_get(dg); m=e.to_mesh(); off=len(vs)
        vs.extend([o.matrix_world@v.co for v in m.vertices]); fs.extend([tuple(off+i for i in f.vertices) for f in m.polygons])
        mi.extend([used.index(o['material_role'])]*len(m.polygons)); cells.extend([list(o['palette_cell'])]*len(m.polygons)); e.to_mesh_clear()
    mesh=bpy.data.meshes.new(p['title']); mesh.from_pydata(vs,[],fs); mesh.update()
    for i in used: mesh.materials.append(mats[i])
    uv=mesh.uv_layers.new(name='PaletteUV'); mesh.uv_layers.active=uv; uv.active_render=True
    for poly,mat,cell in zip(mesh.polygons,mi,cells):
        poly.material_index=mat
        for j,li in enumerate(poly.loop_indices):
            a=2*math.pi*j/len(poly.loop_indices); uv.data[li].uv=((cell[0]+.5)/10+.022*math.cos(a),1-(cell[1]+.5)/10+.022*math.sin(a))
    obj=bpy.data.objects.new(p['title']+('_自发光' if emission else '_主体'),mesh); p['col'].objects.link(obj)
    obj['package_id']='ENV-EXPEDITION-L01-BRIDGE-'+p['slug'].upper(); obj['version']='v002'; obj['collision_owner']='not_exported'; obj['lower_accessible']=False
    if p.get('lower_decor_only'): obj['lower_decor_only']=True
    return obj
records=[]
for p in packages:
    merged=[o for o in (merge_package(p,False),merge_package(p,True)) if o]
    sc=collection(p['title']+'_制作组件',src)
    for o in p['items']: p['col'].objects.unlink(o); sc.objects.link(o)
    b=bounds(merged); origin=[(b[0][i]+b[1][i])/2 for i in range(2)]+[b[0][2]]
    for o in merged:
        for v in o.data.vertices: v.co-=Vector(origin)
        o.location=origin
    rec={'package_id':'ENV-EXPEDITION-L01-BRIDGE-'+p['slug'].upper(),'slug':p['slug'],'name_zh':p['title'],'category':p['category'],'version':'v002','source_blend':BLEND,'collection':p['col'].name,'objects':[o.name for o in merged],'world_origin_m':origin,'local_origin':'bottom_center','forward_axis':'-Y in Blender; +Z after conventional glTF transform','world_bounds_m':b,'dimensions_m':[round(b[1][i]-b[0][i],5) for i in range(3)],'materials':roles,'source_piece_count':len(p['items']),'reference_cutaway_hidden':p['cutaway'],'lower_decor_only':p.get('lower_decor_only',False),'fixed_display_attachment':p.get('fixed_display_attachment',False),'collision_status':'not_exported','exported':False,'dependencies':[]}
    directory=OUT/'component_packages_v002'/p['category']/p['slug']; directory.mkdir(parents=True,exist_ok=True)
    (directory/'asset_manifest.json').write_text(json.dumps(rec,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\r\n'); records.append(rec)
    p['output']=merged
src.hide_render=True; src.hide_viewport=True
for layer in bpy.context.view_layer.layer_collection.children[root.name].children:
    if layer.name==src.name: layer.exclude=True
# Actual door opening is bounded by mesh pieces, not inferred from metadata.
door_measures=[]
for p in packages:
    if p['slug'] in ('wall_north_-1','wall_south_-1'):
        jambs=[o for o in p['items'] if o.name.startswith('门洞边柱')]
        lintel=next(o for o in p['items'] if o.name.startswith('门洞过梁'))
        sill=next(o for o in p['items'] if o.name.startswith('门槛'))
        js=sorted([bounds([o]) for o in jambs],key=lambda b:b[0][0])
        door_measures.append({'width':round(js[1][0][0]-js[0][1][0],4),'bottom':bounds([sill])[1][2],'lintel':bounds([lintel])[0][2]})
checks['door_openings_measured']=len(door_measures)==2 and all(abs(m['width']-2.2)<.001 and abs(m['bottom']-.3)<.001 and abs(m['lintel']-2.8)<.001 for m in door_measures)
checks['output_uv_and_material_slots']=all('PaletteUV' in o.data.uv_layers and all(f.material_index<len(o.data.materials) for f in o.data.polygons) for p in packages for o in p['output'])
checks['one_package_per_output']=all(len(o.users_collection)==1 for p in packages for o in p['output'])
checks['disk_collection_count']=len(records)==len(list((OUT/'component_packages_v002').glob('*/*/asset_manifest.json')))
output_meshes=[o for p in packages for o in p['output']]
manifest={'schema':'shellstorm2.room_type_art_manifest','schema_version':1,'version':'v002','template_id':'bridge_60x50','room_type':'COMMON_ROOM','block_id':'expedition','design_scope':'scene_art','asset_ledger':'assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx::3D-场景通用','source_blend':BLEND,'whitebox_source':str(WHITEBOX.relative_to(ROOT)),'dimensions_m':[30,60],'pit_depth_m':12,'bridge_width_m':10,'wall_visual_height_m':11.9,'wall_logic_height_m':12,'lower_accessible':False,'door_contract':wb['door_contract'],'required_components':['segmented floors','walls and empty door frames','bridge box girders','shaft columns','staggered maintenance galleries','flanged curved pipes','sagging cables','server groups','power cabinets','control consoles'],'required_facilities':[],'door_geometry_in_source':False,'reference_image':str(REF),'reference_sha256':hashlib.sha256(REF.read_bytes()).hexdigest(),'scope':{'modifiable':'all scene-art geometry and presentation','locked':'whitebox dimensions, floor planes, bridge footprint, pit footprint and depth, doors, gameplay','v001_preserved':True},'package_count':len(records),'output_mesh_count':len(output_meshes),'material_roles':roles,'palette_texture':str(PALETTE),'packages':records,'preview_note':'Cutaway images hide only named near-wall packages; complete source retains all walls. No gameplay changes, GLB or engine integration.'}
oldfile=OLD/'通道桥房间种类_工字型_30x60m_v001.blend'
qa={'status':'PASS' if all(checks.values()) else 'FAIL','checks':checks,'measured':{'upper_floor_bounds':ub,'bridge_bounds':bb,'pit_floor_bounds':lb,'lower_service_levels_m':sorted(set(platform_tops)),'source_piece_count':sum(len(p['items']) for p in packages),'output_meshes':len(output_meshes),'output_faces':sum(len(o.data.polygons) for o in output_meshes)},'scope_lock':{'whitebox_sha256':hashlib.sha256(WHITEBOX.read_bytes()).hexdigest(),'v001_sha256':hashlib.sha256(oldfile.read_bytes()).hexdigest(),'method':'all art geometry authorized for reconstruction; preserve input files by hash; measure structural contract'},'visual_review':'pending rendered review; technical PASS is not reference fidelity approval','runtime_integration':False}
for name,data in [('room_type_manifest.json',manifest),('component_inventory.json',records),('qa_report.json',qa)]: (OUT/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\r\n')
(OUT/'component_tree.txt').write_text('\n'.join(p['category']+'/'+p['slug']+' -> '+p['col'].name for p in packages),encoding='utf-8')
# Save full structural source, with all game packages visible and editable source hidden.
scene.camera=cam
for area_ in bpy.context.screen.areas if bpy.context.screen else []:
    if area_.type=='VIEW_3D':
        area_.spaces.active.region_3d.view_perspective='CAMERA'; area_.spaces.active.clip_end=500
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/BLEND))
print('SOURCE_SAVED',str(OUT/BLEND),len(records),len(output_meshes),flush=True)
def render(camera_,name,cutaway):
    for p in packages: p['col'].hide_render=cutaway and p['cutaway']
    scene.camera=camera_; scene.render.filepath=str(RENDER/name); bpy.ops.render.render(write_still=True)
if not opts.no_render:
    render(cam,'reference_cutaway.png',True)
    if not opts.preview:
        render(cam_lower,'lower_layers_detail.png',True); render(cam_upper,'upper_machine_room_detail.png',True)
        render(cam_top,'top_plan.png',True); render(cam_complete,'complete_structure.png',False)
for p in packages: p['col'].hide_render=False
scene.camera=cam
print('BUILD_COMPLETE',json.dumps(qa['measured']),flush=True)
