"""BOSS_ROOM art authoring. Geometry-only reference interpretation; no gameplay edits."""
import bpy, math, json, hashlib, random, importlib.util, sys
from pathlib import Path
from mathutils import Vector
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/art/environments/tower_zones/expedition/source/room_types/boss_room/v001'
WHITE = ROOT / 'source/art/whitebox/tower_zones/expedition_01/v001/blender/远征关卡01_白模_Boss竞技场_50x40m_v001.blend'
PAL = ROOT / 'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
BLEND = OUT / 'Boss房种类_故障数据库_50x40m_v001.blend'
random.seed(90222)
spec = importlib.util.spec_from_file_location('wb', ROOT / 'scripts/blender/build_expedition01_whitebox_v001.py')
wb = importlib.util.module_from_spec(spec); spec.loader.exec_module(wb)

def dump(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes((json.dumps(data, ensure_ascii=False, indent=2)+'\n').replace('\n','\r\n').encode('utf-8'))

def signature(o):
    data = {'name':o.name,'matrix':[list(r) for r in o.matrix_world], 'vertices':[list(v.co) for v in o.data.vertices], 'faces':[list(p.vertices) for p in o.data.polygons]}
    return hashlib.sha256(json.dumps(data,sort_keys=True).encode()).hexdigest()

def coll(name, parent):
    c=bpy.data.collections.new(name); parent.children.link(c); return c

bpy.ops.wm.open_mainfile(filepath=str(WHITE))
source_hash=hashlib.sha256(WHITE.read_bytes()).hexdigest()
old_output=next(c for c in bpy.data.collections if c.name.startswith('02_游戏输出'))
kept=list(old_output.all_objects)
snapshot={o.name:signature(o) for o in kept}
for o in list(bpy.data.objects):
    if o not in kept: bpy.data.objects.remove(o,do_unlink=True)
for c in list(bpy.data.collections): bpy.data.collections.remove(c)
scene=bpy.context.scene
root=coll('BOSS房_故障数据库_资产管理',scene.collection)
src=coll('01_制作组件_可编辑包',root)
output=coll('02_游戏输出_独立资产包_v001',root)
preview=coll('90_展示与验收_灯光相机',root)
categories={k:coll(n,output) for k,n in [('architecture','01_建筑结构'),('floor','02_地面系统'),('facilities','03_固定设施'),('support','04_环境支持')]}
for m in list(bpy.data.materials): bpy.data.materials.remove(m,do_unlink=True)
names=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']
mats=[]
for i,(metal,rough) in enumerate([(0.86,0.29),(0.03,0.70),(0.18,0.15),(0,0.38)]):
    m=wb.make_material(names[i],metal,rough,(9,1)); p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Coat Weight'].default_value=[0.16,0,0.65,0][i]
    if i==3:
        t=next(n for n in m.node_tree.nodes if n.type=='TEX_IMAGE')
        m.node_tree.links.new(t.outputs['Color'],p.inputs['Emission Color']); p.inputs['Emission Strength'].default_value=1.6
    mats.append(m)
# Per-face palette colors, never private textures.
DARK=(9,0); GRAY=(9,1); EDGE=(9,3); SILVER=(9,6); RED=(4,1); REDLIGHT=(5,1); PAPER=(9,8); GREEN=(7,4); GOLD=(6,3)
packages={}; current=None; batches={}; cut=[]
def package(slug,zh,category,side=None):
    global current
    c=coll(zh+'_资产包',categories[category]); packages[slug]={'c':c,'category':category,'side':side,'zh':zh}; current=slug
    return c

def meshpart(verts,faces,mat=0,color=GRAY):
    key=(current,mat); b=batches.setdefault(key,[[],[],[]]); off=len(b[0]); b[0].extend(verts); b[1].extend([tuple(off+i for i in f) for f in faces]); b[2].extend([color]*len(faces))

def box(name,pos,size,mat=0,color=GRAY,angle=0):
    x,y,z=pos; a,b,c=[v/2 for v in size]; co=math.cos(angle); si=math.sin(angle)
    verts=[(x+u*co-v*si,y+u*si+v*co,z+w) for u,v,w in [(-a,-b,-c),(a,-b,-c),(a,b,-c),(-a,b,-c),(-a,-b,c),(a,-b,c),(a,b,c),(-a,b,c)]]
    meshpart(verts,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat,color)

def rod(a,b,r,mat=0,color=GRAY,n=8,r2=None):
    a,b=Vector(a),Vector(b); d=(b-a).normalized(); u=d.cross(Vector((0,0,1)))
    if u.length<0.1: u=d.cross(Vector((0,1,0)))
    u.normalize(); v=d.cross(u); r2=r if r2 is None else r2
    pts=[tuple(p+(u*math.cos(i*math.tau/n)+v*math.sin(i*math.tau/n))*rad) for p,rad in [(a,r),(b,r2)] for i in range(n)]
    fs=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    meshpart(pts,fs,mat,color)

def wire(points,r=0.035,mat=1,color=DARK):
    for a,b in zip(points,points[1:]): rod(a,b,r,mat,color)

def text(body,pos,size=0.5,mat=1,color=SILVER,rot=(math.pi/2,0,0)):
    curve=bpy.data.curves.new('标识文字','FONT'); curve.body=body; curve.size=size; curve.align_x='CENTER'; curve.extrude=0.001; curve.resolution_u=2
    # Emissive text is a separate mesh package and must carry the validator's explicit name marker.
    o=bpy.data.objects.new('自发光铭牌_'+body,curve); packages[current]['c'].objects.link(o); o.location=pos; o.rotation_euler=rot
    bpy.context.view_layer.objects.active=o; o.select_set(True); bpy.ops.object.convert(target='MESH'); o.select_set(False)
    o.data.materials.append(mats[mat]); wb.assign_palette_uv(o,color); return o

# Preserve exact base whitebox meshes and interfaces; art only adds inward overlays.
for o in kept:
    name=o.name; category='floor' if 'FLOOR' in name else 'architecture'
    slug='base_'+name.lower().replace(' ','_'); side=next((s for s in ['NORTH','SOUTH','EAST','WEST'] if s in name),None)
    c=package(slug,('地板' if category=='floor' else '结构')+'_'+name,category,side)
    c.objects.link(o); o.data.materials.clear(); o.data.materials.append(mats[1]); wb.assign_palette_uv(o,GRAY if category=='floor' else DARK)
    o['locked_whitebox_geometry']=True
    if category=='floor' and 'BASE' not in name:
        p=(o.matrix_world @ Vector(o.bound_box[0])+o.matrix_world @ Vector(o.bound_box[6]))/2
        x,y=p.x,p.y
        for dx in [-2.35,2.35]: box('纵向压边',(x+dx,y,0.312),(0.07,4.67,0.022),0,DARK)
        for dy in [-2.35,2.35]: box('横向压边',(x,y+dy,0.314),(4.67,0.07,0.024),0,EDGE)
        for dx in [-2.19,2.19]:
            for dy in [-2.19,2.19]:
                box('锁扣',(x+dx,y+dy,0.325),(0.12,0.12,0.025),0,SILVER)
        box('红色定位灯',(x-1.85,y-2.27,0.335),(0.35,0.08,0.025),3,RED)
        # Inset service grille and thin, non-interactive scuffs belong to their tile.
        if random.random()<0.19:
            box('格栅暗槽',(x+0.8,y,0.316),(1.65,0.94,0.022),1,DARK)
            for q in range(11): box('格栅叶片',(x+0.08+q*0.145,y,0.343),(0.058,0.86,0.03),0,EDGE)
        for q in range(5):
            xx=x+random.uniform(-2,2); yy=y+random.uniform(-2,2)
            box('磨损划痕',(xx,yy,0.327),(random.uniform(.09,.48),.012,.004),1,EDGE,random.random()*6.28)

# Full modular wall skin; door slots leave exact 2.2m x 2.5m clear.
for side,count in [('NORTH',10),('SOUTH',10),('EAST',8),('WEST',8)]:
    for i in range(count):
        u=-count*2.5+2.5+i*5; door=(side=='SOUTH' and abs(u-2.5)<.01) or (side=='WEST' and abs(u+2.5)<.01)
        package('wall_skin_'+side.lower()+'_%02d'%i,'装甲墙_'+side+'_%02d'%i,'architecture',side)
        def wallbox(uu,z,w,h,depth=.09,mat=1,color=GRAY):
            if side in ['NORTH','SOUTH']:
                y=(19.65 if side=='NORTH' else -19.65)
                box('墙板',(uu,y,z),(w,depth,h),mat,color)
            else: box('墙板',((24.65 if side=='EAST' else -24.65),uu,z),(depth,w,h),mat,color)
        for z,h in [(1.48,2.25),(4.55,3.5),(8.04,3.34),(10.68,1.84)]:
            if door and z<2.8:
                wallbox(u-1.83,z,1.3,h);wallbox(u+1.83,z,1.3,h)
            else: wallbox(u,z,4.87,h,color=GRAY if i%3 else (9,2))
        for edge in [-2.42,2.42]:
            wallbox(u+edge,5.95,.085,11.8,.15,0,EDGE)
        if i%2==0:
            wallbox(u-2.12,5.95,.44,11.5,.32,0,DARK)
            for z in [2.0,8.2]: wallbox(u-2.12,z,.13,1.95,.36,3,RED)
            wallbox(u-2.12,10.9,.31,.14,.36,3,RED)
        if door:
            wallbox(u,3.06,2.7,.17,.25,0,EDGE)
            wallbox(u,3.42,1.6,.15,.25,3,RED)
            wallbox(u-1.19,1.55,.12,2.5,.23,0,SILVER);wallbox(u+1.19,1.55,.12,2.5,.23,0,SILVER)
        elif i%3==1:
            wallbox(u,7.7,2.0,.85,.16,0,DARK)
            for j in range(7): wallbox(u,7.38+j*.1,1.84,.033,.20,0,EDGE)

# North-wall focal installation, strong framing and low under-screen racks.
package('main_fault_screen','主屏_破损数据库','facilities')
box('主屏箱体',(1,18.97,7.35),(21.5,1.15,6.9),0,DARK)
box('屏幕玻璃',(1,18.32,7.35),(20.5,.11,5.95),2,(0,1))
for x in [-9.65,11.65]: box('屏框竖梁',(x,18.18,7.35),(.22,.36,6.92),0,EDGE)
for z in [3.9,10.8]: box('屏框横梁',(1,18.18,z),(21.5,.42,.19),0,EDGE)
# Glitch code bands, scanline details. Center remains legible.
for j in range(40):
    z=4.35+j*.145
    for x0 in [-8.9,7.5]:
        for k in range(random.randint(1,4)):
            box('故障代码',(x0+random.random()*1.7,18.245,z),(random.uniform(.12,1.0),.015,.023),3,RED if j%3 else REDLIGHT)
text('DATABASE OFFLINE',(1,18.19,5.70),.81,3,REDLIGHT)
text('CRITICAL FAILURE  /  ARCHIVE CONNECTION LOST',(1,18.19,4.85),.24,3,RED)
tri=[(-.8,18.18,7),(1,18.18,9.75),(2.8,18.18,7),(-.8,18.18,7)]
wire(tri,.057,3,REDLIGHT); text('!',(1,18.15,7.43),1.37,3,REDLIGHT)
# Asymmetric glass fracture; explicit jagged facets and branching crack paths.
impact=Vector((8.7,18.1,7.2))
for k in range(11):
    ang=k*math.tau/11; end=Vector((max(4.1,min(11,8.7+math.cos(ang)*3.5)),18.08,max(4.5,min(10.3,7.2+math.sin(ang)*3.4))))
    mid=impact.lerp(end,.5)+Vector((random.uniform(-.3,.3),0,random.uniform(-.3,.3)))
    wire([impact,mid,end],.013,0,SILVER)
    if k%2==0: wire([mid,mid+Vector((.65,0,.6))],.009,0,EDGE)
for k in range(5):
    x=10.0+random.random();z=5+random.random()*3
    meshpart([(x,18.065,z),(x+.55,18.065,z+.75),(x+.65,18.065,z-.55)],[(0,1,2)],1,DARK)

# Rack local geometry; front faces -Y; rotate entire packet by yaw.
def rack(slug,x,y,height=4.7,yaw=0,mini=False):
    package(slug,'服务器_'+slug,'facilities')
    start={k:(len(v[0]),len(v[1])) for k,v in batches.items()}
    w=1.65 if mini else 2.0; dep=1.65
    box('柜体',(0,0,height/2+.3),(w,dep,height),0,GRAY)
    box('前凹槽',(0,-.855,height/2+.3),(w-.18,.12,height-.22),1,DARK)
    for sx in [-w/2+.07,w/2-.07]: box('立柱',(sx,-.95,height/2+.3),(.10,.18,height),0,EDGE)
    for j in range(int(height/.43)):
        z=.62+j*.43;box('抽屉',(0,-.96,z),(w-.32,.17,.33),0,GRAY)
        box('抽屉拉手',(.12,-1.065,z+.05),(.64,.055,.04),0,SILVER)
        for k in range(3): box('状态灯',(-w/2+.25+k*.16,-1.072,z),(.07,.022,.045),3,REDLIGHT if k==0 else RED)
        for k in range(5): box('散热槽',(.42+k*.1,-1.055,z-.07),(.055,.028,.06),1,DARK)
    box('灯牌',(0,-.97,height+.03),(1.05,.18,.10),3,RED)
    for key,b in batches.items():
        if key[0]!=current: continue
        co,si=math.cos(yaw),math.sin(yaw)
        b[0]=[(x+u*co-v*si,y+u*si+v*co,z) for u,v,z in b[0]]

for i,x in enumerate([-19.8,-17.4,-14.9,14.2,16.8,19.4,22]): rack('north_%02d'%i,x,18.3,4.2+(i%3)*.35)
for i,x in enumerate([-7.8,-5.25,-2.7,0,2.7,5.4,8.1,10.8]): rack('under_screen_%02d'%i,x,18.0,2.9,mini=True)
for i,y in enumerate([-15,-10,-5,0,5,10]): rack('east_%02d'%i,23.3,y,4.7+(i%2)*.5,-math.pi/2)
for i,y in enumerate([-14,3.5,12.5]): rack('west_%02d'%i,-23.2,y,4.2,math.pi/2)

# Workstation islands, separate stools and fixed decorative desk accessories.
def desk(i,x,y):
    package('workstation_%02d'%i,'工作站_%02d'%i,'facilities')
    box('台面',(x,y,1.7),(4.2,2.05,.16),1,EDGE)
    for dx in [-1.7,1.7]:
        box('柜脚',(x+dx,y,1),(0.65,1.6,1.4),0,GRAY)
        for j in range(3):
            box('抽屉面',(x+dx,y-.84,.56+j*.4),(.57,.07,.31),1,GRAY)
            box('把手',(x+dx,y-.90,.63+j*.4),(.25,.055,.035),0,SILVER)
    box('隔断',(x,y+.96,2.37),(4.25,.14,1.2),1,DARK)
    for dx in [-.82,.85]:
        box('显示器立柱',(x+dx,y+.25,2.03),(.12,.13,.6),0,GRAY)
        box('显示器框',(x+dx,y+.3,2.64),(1.49,.18,.88),0,DARK)
        box('红色屏面',(x+dx,y+.19,2.64),(1.30,.04,.70),2,(2,1))
        for j in range(7): box('屏幕代码',(x+dx-.20,y+.16,2.36+j*.08),(random.uniform(.25,.85),.014,.023),3,RED)
        box('键盘',(x+dx,y-.45,1.83),(1.18,.44,.08),0,DARK)
        for j in range(3):
            for k in range(10): box('按键',(x+dx-.5+k*.108,y-.58+j*.115,1.88),(.075,.075,.027),1,EDGE)
    for q in range(3): box('桌面文档',(x+random.uniform(-1.7,1.7),y-.1,1.806+q*.003),(.36,.48,.004),1,PAPER,random.uniform(-.4,.4))
    rod((x+1.7,y-.48,1.80),(x+1.7,y-.48,2.05),.12,1,PAPER,n=12)
    package('chair_%02d'%i,'独立座椅_%02d'%i,'facilities')
    box('坐垫',(x,y-1.73,1.04),(.94,.90,.20),1,DARK)
    box('靠背',(x,y-2.07,1.65),(.94,.20,1.05),1,GRAY)
    rod((x,y-1.73,.39),(x,y-1.73,1.03),.10,0,SILVER)
    for k in range(5):
        a=k*math.tau/5;rod((x,y-1.73,.43),(x+.65*math.cos(a),y-1.73+.65*math.sin(a),.39),.045,0,EDGE)

for i,(x,y) in enumerate([(-18,15),(-18,9),(-18,-8),(-18,-15),(-12,15)]): desk(i,x,y)
# Fixed-display plants, kept separately instead of welded into desks.
for i,(x,y) in enumerate([(-21,17),(-20,7),(-20,-12),(-15,-17),(20,13)]):
    package('plant_%02d'%i,'固定绿植_%02d'%i,'facilities')
    rod((x,y,.3),(x,y,1.12),.34,1,GRAY,n=10,r2=.5)
    for j in range(9):
        a=j*math.tau/9; p=(x+math.cos(a)*.85,y+math.sin(a)*.85,1.5+random.random()*.6)
        meshpart([(x,y,1), (x+math.cos(a+.45)*.42,y+math.sin(a+.45)*.42,1.75),p,(x+math.cos(a-.45)*.42,y+math.sin(a-.45)*.42,1.75)],[(0,1,2,3)],1,GREEN)

# Side shelf loaded with archive containers, independent rack packet.
for i,y in enumerate([-13,-6,2,10]):
    package('archive_shelf_%02d'%i,'档案货架_%02d'%i,'facilities')
    x=21.0
    for sx in [-1.1,1.1]:
        for sy in [-.72,.72]: box('货架立柱',(x+sx,y+sy,2.7),(.12,.12,4.8),0,EDGE)
    for z in [.5,1.9,3.3,4.7]:
        box('货架层板',(x,y,z),(2.45,1.6,.13),0,GRAY)
        for q in range(2):
            xx=x-.58+q*1.14
            box('封存箱',(xx,y,z+.51),(.96,1.30,.88),1,(9,2))
            box('封存带',(xx,y-.66,z+.51),(.19,.023,.88),0,DARK)
            box('档案标签',(xx-.2,y-.68,z+.61),(.3,.02,.18),1,PAPER)

package('floor_cables','跨设施电缆束','support')
for i in range(12):
    x=-11+i*1.9
    points=[(x,18.0,2.9),(x+.25,16.8,1.1),(x+.8,15.9,.39),(x+1.5,14.7,.39),(x+.1,13.8,.39),(x-1.5,14.4,.39),(x-2,16,.39)]
    wire(points,.045+(i%2)*.018)
# Debris and paper are fixed, non-interactive display components outside central rectangle.
for i in range(10):
    package('debris_%02d'%i,'固定碎屑_%02d'%i,'support')
    x=-11+i*2.5;y=16.0
    for k in range(9):
        xx=x+random.uniform(-1.1,1.1);yy=y+random.uniform(-1.3,.5)
        if k%2: box('散落纸页',(xx,yy,.335),(.35,.46,.009),1,PAPER,random.random()*6.28)
        else:
            meshpart([(xx,yy,.34),(xx+.4,yy-.2,.34),(xx+.2,yy+.3,.34),(xx+.1,yy+.02,.55)],[(0,2,1),(0,1,3),(1,2,3),(2,0,3)],0,EDGE)
package('north_wall_typography','数据库墙面标识','architecture','NORTH')
text('SECTOR',(16.5,19.47,9.4),.53,1,SILVER)
text('A3',(16.5,19.46,8.05),1.35,1,SILVER)
text('DATA CORE',(16.5,19.46,7.45),.43,1,SILVER)
text('KNOWLEDGE / PRESERVES / HUMANITY',(-16,19.43,9.4),.25,1,SILVER)
package('south_floor_marking','入口地砖_标识附件','support')
text('A3 - DB',(2.5,-16.4,.338),.85,1,EDGE,rot=(0,0,0))
for dx in [-1.4,1.4]:
    box('入口箭头',(2.5+dx,-17.7,.34),(.13,1.8,.012),1,EDGE,angle=dx*.32)

# Realize batched editable meshes. Every face has its own nonzero-area safe-cell island.
for (slug,mat),(vs,fs,colors) in batches.items():
    me=bpy.data.meshes.new(slug+'_'+str(mat)); me.from_pydata(vs,[],fs);me.update()
    o=bpy.data.objects.new(packages[slug]['zh']+('_自发光' if mat==3 else '_部件'+str(mat)),me);packages[slug]['c'].objects.link(o);me.materials.append(mats[mat])
    uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True;me.uv_layers.active=uv
    for p,color in zip(me.polygons,colors):
        for j,l in enumerate(p.loop_indices):
            a=j*math.tau/len(p.loop_indices);uv.data[l].uv=((color[0]+.5)/10+.022*math.cos(a),1-(color[1]+.5)/10+.022*math.sin(a))
    # Faceted small bevels only in editable source are not required for silhouettes;
    # mesh geometry is already directly evaluated and ready to decompose.

bpy.context.view_layer.update()
locked_after={o.name:signature(o) for o in kept}
assert locked_after==snapshot,'Whitebox geometry changed'
# Capture real envelopes and independent editable sources; no duplicated output membership.
manifest=[]
for slug,info in packages.items():
    obs=list(info['c'].objects);assert obs,slug
    bounds=[o.matrix_world@Vector(p) for o in obs for p in o.bound_box]
    low=[min(p[i] for p in bounds) for i in range(3)];high=[max(p[i] for p in bounds) for i in range(3)]
    origin=[(low[0]+high[0])/2,(low[1]+high[1])/2,low[2]]
    sc=coll(info['zh']+'_制作',src)
    for o in obs:
        o['package_id']=slug;o['fixed_display_attachment']=info['category'] in ['facilities','support'];o['local_origin_m']=origin
        so=o.copy();so.data=o.data.copy();so.name='制作_'+o.name;sc.objects.link(so)
        if info['side'] in ['SOUTH','EAST']: cut.append(o)
    row={'package_id':slug,'name_zh':info['zh'],'category':info['category'],'version':'v001','source_blend':str(BLEND.relative_to(ROOT)).replace('\\','/'),'collection':info['c'].name,'objects':[o.name for o in obs],'root_object':None,'world_origin_m':origin,'local_origin_contract':'bottom_center_recorded; room-world geometry retained','bounds':{'min':low,'max':high},'dimensions_m':[high[i]-low[i] for i in range(3)],'front':'-Y Blender / +Z Godot; per placement','materials':sorted({m.name for o in obs for m in o.data.materials}),'collision':'not_authored','exported':False,'dependencies':[],'interaction':'none; fixed display'}
    manifest.append(row);dump(OUT/'component_packages'/info['category']/slug/'asset_manifest.json',row)
src.hide_render=True;src.hide_viewport=True
# Reference cameras & lighting. Walls remain complete in saved source.
scene.world=bpy.data.worlds.new('展示环境');scene.world.use_nodes=True
wn=scene.world.node_tree.nodes; wl=scene.world.node_tree.links
wn.clear(); wbgn=wn.new('ShaderNodeBackground'); wout=wn.new('ShaderNodeOutputWorld'); wbgn.inputs['Color'].default_value=(.22,.24,.28,1); wbgn.inputs['Strength'].default_value=.35; wl.new(wbgn.outputs['Background'],wout.inputs['Surface'])

def light(name,pos,power,color,size,target=(0,0,0)):
    d=bpy.data.lights.new(name,'AREA');d.energy=power;d.color=color;d.shape='DISK';d.size=size;o=bpy.data.objects.new(name,d);preview.objects.link(o);o.location=pos;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
light('大面积柔光',(0,-8,31),17000,(.75,.83,1),30)
light('侧向轮廓',(-28,6,22),11000,(.66,.76,1),22)
light('暖色填光',(24,-22,18),9000,(1,.77,.66),25)
for x in [-20,-10,0,10,20]: light('红色警报洗墙',(x,16,6),450,(1,.018,.009),4,(x,14,0))
for y in [-15,-5,5,15]:light('西侧警报',(-22,y,5),220,(1,.02,.01),3,(-18,y,0))

def camera(name,pos,target,scale):
    d=bpy.data.cameras.new(name);d.type='ORTHO';d.ortho_scale=scale;o=bpy.data.objects.new(name,d);preview.objects.link(o);o.location=pos;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();return o
cams=[camera('参考全景',(64,-78,82),(0,0,2),74),camera('正交俯视',(0,0,90),(0,0,0),55),camera('主屏破损近景',(30,-30,27),(1,17,6),31),camera('工作站近景',(-6,-17,16),(-18,8,1.7),23)]
scene.render.engine='CYCLES';scene.cycles.samples=8;scene.cycles.use_denoising=False
# Keep reference renders below the local OpenImageDenoise memory ceiling; geometry/material fidelity is unchanged.
scene.render.resolution_x=1000;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=.65
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
scene.use_nodes=True;nt=scene.node_tree;nt.nodes.clear();rl=nt.nodes.new('CompositorNodeRLayers');gl=nt.nodes.new('CompositorNodeGlare');gl.glare_type='FOG_GLOW';gl.quality='HIGH';gl.threshold=.9;co=nt.nodes.new('CompositorNodeComposite');nt.links.new(rl.outputs['Image'],gl.inputs['Image']);nt.links.new(gl.outputs['Image'],co.inputs['Image'])
scene['room_type']='BOSS_ROOM';scene['block_id']='expedition';scene['design_scope']='scene_art';scene['whitebox_source']=str(WHITE.relative_to(ROOT));scene['art_stage']='source_only'
scene.camera=cams[0]
bpy.context.preferences.filepaths.save_version=0
OUT.mkdir(parents=True,exist_ok=True)
# Store unclipped model, reference preset says which walls to hide only for inspection.
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_distance=65;area.spaces.active.region_3d.view_location=Vector((0,0,3))
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
index=json.loads((ROOT/'assets/registry/ledger_index.json').read_text('utf-8'))
ledger=next(d['file'] for d in index['domains'] if '场景' in d['categories'])
dump(OUT/'room_type_manifest.json',{'room_type':'BOSS_ROOM','package_id':'BOSS_ROOM_DATACORE_50X40','version':'v001','whitebox_source':str(WHITE.relative_to(ROOT)).replace('\\','/'),'whitebox_sha256':source_hash,'dimensions_m':[50,40,11.9],'logical_height_m':12,'ports':wb.ARENA_PORTS,'door_clearance_m':[2.2,2.5],'floor_top_m':.3,'block_id':'expedition','block_id_note':'Explicit expedition whitebox takes precedence over skill battle example.','design_scope':'scene_art','asset_ledger':index['ledger_dir']+'/'+ledger+'::3D-场景通用','required_components':['5m_floor','5m_wall','door_wall'],'required_facilities':['fault_screen','server_racks','workstations'],'source_blend':BLEND.name,'runtime_connected':False,'ledger_registration':'pending; whitebox asset identity preserved','reference':'user clipboard-2026-09-22T09-18-18-591Z-463a7c81.jpg','reference_interpretation':'Geometry-only damage/UI; no new texture; complete four-wall room with south/east hidden ONLY during cutaway preview','package_count':len(manifest),'output_mesh_count':sum(len(v['c'].objects) for v in packages.values()),'packages':manifest,'preview_cutaway_objects':[o.name for o in cut]})
dump(OUT/'scope_lock.json',{'whitebox_before':snapshot,'whitebox_after':locked_after,'locked_match':locked_after==snapshot,'source_file_sha256':source_hash,'scope':'wall/floor base geometry and transforms locked; material and inward decoration allowed; no gameplay edits'})
dump(OUT/'component_packages/catalog.json',{'packages':manifest})
(OUT/'component_packages/tree.txt').write_text('\n'.join(r['category']+'/'+r['package_id'] for r in manifest),encoding='utf-8')
print('BOSS_DATACORE_SOURCE_SAVED',str(BLEND),len(manifest),flush=True)
for i,cam in enumerate(cams):
    for o in cut:o.hide_render=(i!=1)
    scene.camera=cam;scene.render.filepath=str(OUT/'renders'/['01_参考全景.png','02_完整俯视.png','03_主屏破损近景.png','04_工作站近景.png'][i]);Path(scene.render.filepath).parent.mkdir(exist_ok=True)
    bpy.ops.render.render(write_still=True)
    print('BOSS_DATACORE_RENDER_OK',i,flush=True)
for o in cut:o.hide_render=False
scene.camera=cams[0];bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print('BOSS_DATACORE_BUILD_OK',flush=True)
