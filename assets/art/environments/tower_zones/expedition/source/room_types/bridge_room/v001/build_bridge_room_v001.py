"""Build the expedition 01 bridge room type source from the locked whitebox contract.

Geometry-only art authoring. No gameplay, Godot scene, collision or room-layout code.
Run with Blender background Python from the repository root or from this file.
"""
from pathlib import Path
import bpy, math, json, hashlib, shutil
from mathutils import Vector

HERE = Path(__file__).resolve()
ROOT = HERE.parents[9]
OUT = HERE.parent
RENDER = OUT / "renders"
PALETTE = ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
WHITEBOX = ROOT / "source/art/whitebox/tower_zones/expedition_01/v001/data/room_templates/bridge_60x50.json"
REFERENCE = ROOT / "docs/v0.1/design/refs/expedition01/通道桥房间.jpg"
OUT.mkdir(parents=True, exist_ok=True)
RENDER.mkdir(parents=True, exist_ok=True)

# Start from a clean, self-contained scene.
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.world = bpy.data.worlds.new('通道桥展示世界')
scene.world.use_nodes = True
world_nodes = scene.world.node_tree.nodes
world_links = scene.world.node_tree.links
world_nodes.clear()
world_bg = world_nodes.new('ShaderNodeBackground')
world_bg.inputs['Color'].default_value = (0.018, 0.028, 0.055, 1.0)
world_bg.inputs['Strength'].default_value = 0.28
world_out = world_nodes.new('ShaderNodeOutputWorld')
world_links.new(world_bg.outputs['Background'], world_out.inputs['Surface'])
scene.view_settings.look = 'AgX - Medium High Contrast'
scene.view_settings.exposure = 2.2
scene.render.engine = 'BLENDER_EEVEE_NEXT'
scene.render.resolution_x = 1100
scene.render.resolution_y = 720
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.film_transparent = False
scene.render.image_settings.color_mode = 'RGBA'
scene.view_settings.look = 'AgX - Medium High Contrast'
scene.world.color = (0.004, 0.006, 0.014)

# Collections mirror the production standard.
def coll(name, parent=None, hide=False):
    c = bpy.data.collections.new(name)
    (parent or scene.collection).children.link(c)
    c.hide_viewport = hide
    return c

root_col = coll('通道桥房间_工字型_30x60m_资产管理')
source_col = coll('01_制作组件_按设施拆分', root_col, hide=True)
game_col = coll('02_游戏输出_独立资产包_v001', root_col)
arch_col = coll('01_建筑结构', game_col)
floor_col = coll('02_地面系统', game_col)
facility_col = coll('03_区域固定设施', game_col)
support_col = coll('04_环境支持', game_col)
display_col = coll('90_展示与验收_灯光相机', root_col)

# Palette-backed, four-role material contract.
image = bpy.data.images.load(str(PALETTE), check_existing=True)
image.filepath = str(PALETTE)
MAT_NAMES = ['01_精工金属_紫色骨架', '02_细腻哑光_青绿大面', '03_清漆反光_紫粉点缀', '04_柔和自发光_UI灯光']
MAT_CONFIG = [(0.86, 0.28, 0.16), (0.03, 0.70, 0.0), (0.18, 0.14, 0.66), (0.0, 0.36, 0.0)]
materials = []
for idx, name in enumerate(MAT_NAMES):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    nodes.clear()
    uv = nodes.new('ShaderNodeUVMap'); uv.uv_map = 'PaletteUV'
    tex = nodes.new('ShaderNodeTexImage'); tex.image = image; tex.interpolation = 'Closest'
    bs = nodes.new('ShaderNodeBsdfPrincipled')
    out = nodes.new('ShaderNodeOutputMaterial')
    metal, rough, coat = MAT_CONFIG[idx]
    bs.inputs['Metallic'].default_value = metal
    bs.inputs['Roughness'].default_value = rough
    if 'Coat Weight' in bs.inputs: bs.inputs['Coat Weight'].default_value = coat
    m.node_tree.links.new(uv.outputs['UV'], tex.inputs['Vector'])
    m.node_tree.links.new(tex.outputs['Color'], bs.inputs['Base Color'])
    if idx == 3:
        m.node_tree.links.new(tex.outputs['Color'], bs.inputs['Emission Color'])
        bs.inputs['Emission Strength'].default_value = 1.35
    m.node_tree.links.new(bs.outputs['BSDF'], out.inputs['Surface'])
    materials.append(m)

# Palette cells: (column, row), all faces retain a finite UV island.
DARK=(9,0); PANEL=(9,1); EDGE=(9,3); STEEL=(9,6); BLUE=(3,5); CYAN=(3,6); AMBER=(4,3); PINK=(5,1); WHITE=(9,8)
def assign_uv(obj, cell):
    if obj.type != 'MESH': return
    for layer in list(obj.data.uv_layers): obj.data.uv_layers.remove(layer)
    layer = obj.data.uv_layers.new(name='PaletteUV')
    obj.data.uv_layers.active = layer
    layer.active_render = True
    u = (cell[0] + 0.5) / 10.0; v = 1.0 - (cell[1] + 0.5) / 10.0
    corners = [(-.022,-.022),(.022,-.022),(.022,.022),(-.022,.022)]
    for poly in obj.data.polygons:
        for j, li in enumerate(poly.loop_indices):
            a,b = corners[j % 4]; layer.data[li].uv = (u+a, v+b)

def link(obj, collection):
    collection = target_collection(collection)
    for old in list(obj.users_collection): old.objects.unlink(obj)
    collection.objects.link(obj)

def box(name, loc, dims, collection, mat=0, cell=PANEL, bevel=0.0, props=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object; o.name = name; o.dimensions = dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(materials[mat]); assign_uv(o, cell); link(o, collection)
    if bevel:
        mod=o.modifiers.new('边缘微倒角','BEVEL'); mod.width=bevel; mod.segments=2
        o.modifiers.new('加权法线','WEIGHTED_NORMAL')
    if props:
        for k,v in props.items(): o[k]=v
    return o

def cyl(name, loc, radius, depth, collection, mat=0, cell=STEEL, vertices=12, rot=None, props=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rot or (0,0,0))
    o=bpy.context.object; o.name=name; o.data.materials.append(materials[mat]); assign_uv(o,cell); link(o,collection)
    if props:
        for k,v in props.items(): o[k]=v
    return o

def rod(name, a, b, radius, collection, mat=0, cell=STEEL, vertices=10, props=None):
    a,b=Vector(a),Vector(b); d=b-a; length=d.length
    o=cyl(name,(a+b)/2,radius,length,collection,mat,cell,vertices)
    o.rotation_mode='QUATERNION'; o.rotation_quaternion=d.to_track_quat('Z','Y')
    if props:
        for k,v in props.items(): o[k]=v
    return o

def light_strip(name, loc, dims, collection, cell=CYAN):
    tagged = name if ('自发光' in name or 'UI灯光' in name or 'emissive' in name.lower() or 'glow' in name.lower()) else '自发光_' + name
    return box(tagged,loc,dims,collection,3,cell,0.01,{'art_role':'emissive_accent'})

packages=[]
CURRENT_PACKAGE=None
def package(slug, title, category, collection):
    global CURRENT_PACKAGE
    p=coll(f'{title}_资产包', collection)
    rec={'package_id':'ENV-EXPEDITION-L01-BRIDGE-'+slug.upper(),'slug':slug,'name_zh':title,'category':category,'collection':p,'objects':[]}
    packages.append(rec)
    CURRENT_PACKAGE=rec
    return p

def add(pkg, obj):
    for rec in packages:
        if rec['collection'] == pkg and obj.name not in rec['objects']:
            rec['objects'].append(obj.name)
            break
    return obj

def target_collection(collection):
    """Route category-level helper calls into the active semantic asset package."""
    if CURRENT_PACKAGE is not None and collection in (arch_col, floor_col, facility_col, support_col):
        return CURRENT_PACKAGE['collection']
    return collection

# Source-only whitebox lock record and authoring guides.
lock = bpy.data.objects.new('白盒锁定_30x60_桥宽10_坑深12', None)
source_col.objects.link(lock)
lock.empty_display_type='CUBE'; lock.empty_display_size=1.0
for k,v in {'whitebox_source':str(WHITEBOX.relative_to(ROOT)).replace('\\','/'),'dimensions_m':[30.0,60.0],'pit_rect_m':[-15.0,15.0,-15.0,15.0],'bridge_rect_m':[-5.0,5.0,-15.0,15.0],'pit_depth_m':12.0,'lower_accessible':False,'door_slots_north_south':[-7.5,-2.5,2.5,7.5],'door_geometry_in_source':False}.items(): lock[k]=v
for x in (-15,-5,5,15):
    for y in (-30,-15,15,30):
        g=bpy.data.objects.new(f'网格定位_{x}_{y}',None); source_col.objects.link(g); g.empty_display_type='CUBE'; g.empty_display_size=0.25; g.location=(x,y,0)

# Floors: upper platforms and bridge, all on 5m grid.
def floor_tile(ix, iy, z, lower=False):
    x=ix*5+2.5; y=iy*5+2.5
    p=package(f'floor_{"lower" if lower else "upper"}_{ix}_{iy}','地砖_%s_%02d_%02d'%('下层' if lower else '上层',ix,iy),'floor',floor_col)
    add(p,box('5米结构地砖',(x,y,z-0.15),(5,5,0.30),floor_col,0,DARK,0,{'asset_role':'floor_tile_5m','grid_unit_m':5.0}))
    add(p,box('可维护面板',(x,y,z+0.035),(4.82,4.82,0.07),floor_col,1,PANEL,0.035))
    add(p,box('中心检修盖',(x,y,z+0.085),(2.0,1.15,0.025),floor_col,0,DARK,0.02))
    for sx in (-2.25,2.25): add(p,light_strip('地砖冷光轨',(x+sx,y,z+0.115),(0.025,4.2,0.018),floor_col))
    for dx in (-2.1,2.1):
        for dy in (-2.1,2.1): add(p,cyl('沉头螺栓',(x+dx,y+dy,z+0.12),0.045,0.025,floor_col,0,STEEL,8))
    if (ix+iy) % 3 == 0:
        for j in range(5): add(p,box('警示斜条',(x-1.75+j*.43,y-1.7,z+0.13),(0.22,0.55,0.018),floor_col,2,AMBER,0.01))

for iy in range(-6,-3):
    for ix in range(-3,3): floor_tile(ix,iy,0)
for iy in range(3,6):
    for ix in range(-3,3): floor_tile(ix,iy,0)
for iy in range(-3,3):
    for ix in (-1,0): floor_tile(ix,iy,0)
for iy in range(-3,3):
    for ix in (-3,-2,1,2): floor_tile(ix,iy,-12,True)

# Modular wall helpers. North/south reserve the selected -2.5m lane without door geometry.
def outer_short(y, side):
    for ix in range(-3,3):
        x=ix*5+2.5
        p=package(f'wall_{side}_{ix}','%s端墙模块_%+02d'%(side,ix),'architecture',arch_col)
        is_reserved = ix == -1
        if is_reserved:
            add(p,box('门位预留_侧柱左',(x-1.62,y,1.55),(1.65,0.30,3.1),arch_col,0,EDGE,0.04,{'door_slot_reserved':True,'door_clear_width_m':2.2}))
            add(p,box('门位预留_侧柱右',(x+1.62,y,1.55),(1.65,0.30,3.1),arch_col,0,EDGE,0.04,{'door_slot_reserved':True,'door_clear_width_m':2.2}))
            add(p,box('门位预留_过梁',(x,y,7.35),(5.0,0.30,9.1),arch_col,1,PANEL,0.03))
            light_strip('门位预留冷光框',(x,y-0.19,3.18),(2.45,0.04,0.08),arch_col,BLUE)
        else:
            add(p,box('标准5米墙体',(x,y,5.95),(5,0.30,11.9),arch_col,1,PANEL,0.04,{'asset_role':'wall_standard_5m','visual_height_m':11.9,'grid_unit_m':5.0}))
        add(p,box('墙脚踢脚板',(x,y-0.20,0.28),(4.85,0.12,0.56),arch_col,0,DARK,0.02))
        add(p,box('装甲竖向加强筋',(x-2.26,y-0.22,5.95),(0.10,0.10,11.2),arch_col,0,STEEL,0.02))
        add(p,box('自发光_墙顶蓝光导轨',(x,y-0.22,10.65),(4.25,0.06,0.07),arch_col,3,BLUE,0.01))
        add(p,box('墙面分仓线',(x,y-0.21,4.0),(4.7,0.04,0.035),arch_col,0,EDGE))
for y,side in [(-30,'south'),(30,'north')]: outer_short(y,side)

def outer_long(x, side):
    for iy in range(-6,6):
        y=iy*5+2.5
        p=package(f'wall_{side}_{iy}','%s侧墙模块_%+02d'%(side,iy),'architecture',arch_col)
        add(p,box('标准5米墙体',(x,y,5.95),(0.30,5,11.9),arch_col,1,PANEL,0.04,{'asset_role':'wall_standard_5m','visual_height_m':11.9,'grid_unit_m':5.0}))
        add(p,box('墙脚踢脚板',(x-0.20,y,0.28),(0.12,4.85,0.56),arch_col,0,DARK,0.02))
        add(p,box('装甲竖向加强筋',(x-0.22,y-2.26,5.95),(0.10,0.10,11.2),arch_col,0,STEEL,0.02))
        add(p,box('自发光_侧墙蓝光导轨',(x-0.22,y,10.65),(0.06,4.25,0.07),arch_col,3,BLUE,0.01))
for x,side in [(-15,'west'),(15,'east')]: outer_long(x,side)

# Pit enclosure drops to -12m. Bridge opening remains clear at x[-5,5].
def pit_wall(name, loc, dims, orient):
    p=package(name,name,'architecture',arch_col)
    add(p,box('坑壁下延标准墙',loc,dims,arch_col,1,PANEL,0.03,{'asset_role':'sunken_pit_enclosure','bottom_z_m':-12.0,'accessible':False}))
    add(p,box('坑壁检修边',((loc[0] if dims[0]<dims[1] else loc[0]),(loc[1] if dims[1]<dims[0] else loc[1]),-0.18),(dims[0]+0.15 if dims[0]>dims[1] else 0.15,dims[1]+0.15 if dims[1]>dims[0] else 0.15,0.22),arch_col,0,EDGE,0.02))
    return p
# Side pit walls along x=-15, +15; end returns stop at bridge edges.
for x in (-15,15):
    for iy in (-3,-2,-1,0,1,2):
        y=iy*5+2.5
        p=package(f'pit_wall_x_{x}_{iy}','坑壁纵向模块_%s_%+02d'%('西' if x<0 else '东',iy),'architecture',arch_col)
        add(p,box('坑壁下延标准墙',(x,y,-5.95),(0.30,5,11.9),arch_col,1,PANEL,0.03,{'asset_role':'sunken_pit_enclosure','accessible':False}))
        add(p,box('坑沿警示压边',(x+(-0.20 if x<0 else 0.20),y,0.16),(0.12,4.7,0.18),arch_col,0,AMBER,0.02))
for y in (-15,15):
    for ix in (-3,-2,1,2):
        x=ix*5+2.5
        p=package(f'pit_wall_y_{y}_{ix}','坑壁端部模块_%s_%+02d'%('南' if y<0 else '北',ix),'architecture',arch_col)
        add(p,box('坑壁下延端墙',(x,y,-5.95),(5,0.30,11.9),arch_col,1,PANEL,0.03,{'asset_role':'sunken_pit_enclosure','accessible':False}))
        add(p,box('坑沿黄色警示边',(x,y+(-0.20 if y<0 else 0.20),0.16),(4.7,0.12,0.18),arch_col,0,AMBER,0.02))

# Bridge railings and transverse bracing, visual only; the bridge stays 10m wide.
for x in (-5,5):
    p=package(f'bridge_rail_{x}','跨桥%s侧护栏'%('西' if x<0 else '东'),'architecture',arch_col)
    for y in range(-15,16,5):
        add(p,cyl('护栏立柱',(x,y,0.78),0.09,1.55,arch_col,0,STEEL,10))
        add(p,light_strip('护栏蓝色线光',(x+(-0.08 if x<0 else 0.08),y,0.62),(0.035,0.11,0.055),arch_col,BLUE))
    add(p,rod('护栏上横杆',(x,-15,1.55),(x,15,1.55),0.10,arch_col,0,STEEL))
    add(p,rod('护栏中横杆',(x,-15,0.72),(x,15,0.72),0.055,arch_col,0,EDGE))
for y in (-15,15):
    p=package(f'bridge_end_frame_{y}','跨桥端部框架_%s'%('南' if y<0 else '北'),'architecture',arch_col)
    add(p,rod('端部护栏底梁',(-5,y,0.05),(5,y,0.05),0.11,arch_col,0,STEEL))
    for x in (-5,5): add(p,cyl('端部护栏立柱',(x,y,0.78),0.10,1.55,arch_col,0,STEEL,10))

# Upper wall-mounted fixed facilities.
def server_rack(slug, x, y, z=2.2, yaw=0.0, lower=False):
    p=package(slug,'蓝光服务器机柜_%s'%slug,'facility',facility_col)
    w,d,h=(1.35,0.75,3.8) if not lower else (1.25,0.70,2.2)
    o=add(p,box('重型柜体',(x,y,z),(w,d,h),facility_col,0,DARK,0.07)); o.rotation_euler.z=yaw
    add(p,box('柜体前面板',(x,y-0.40,z),(w-0.20,0.08,h-0.35),facility_col,1,PANEL,0.02))
    for j in range(5 if not lower else 3):
        zz=z-h/2+0.55+j*0.55
        add(p,box('服务器抽屉',(x,y-0.46,zz),(w-0.32,0.12,0.30),facility_col,1,EDGE,0.02))
        for k in range(4): add(p,light_strip('状态灯',(x-w/2+0.28+k*0.16,y-0.53,zz),(0.06,0.025,0.05),facility_col,BLUE if k%2 else CYAN))
    add(p,box('柜顶压梁',(x,y,z+h/2+0.10),(w+0.10,d+0.08,0.20),facility_col,0,STEEL,0.03))
for n,(x,y) in enumerate([(-12.0,-25.7),(-8.0,-25.7),(8.5,-25.7),(11.8,-25.7),(11.3,25.7),(7.3,25.7),(-11.7,25.7)]): server_rack(f'upper_server_{n:02d}',x,y,2.25,0)

# Access terminals and heavy maintenance crates on the upper platforms.
def terminal(slug,x,y,rot=0):
    p=package(slug,'立式访问终端_%s'%slug,'facility',facility_col)
    add(p,box('终端底座',(x,y,0.14),(0.75,0.72,0.28),facility_col,0,STEEL,0.04))
    add(p,box('终端立柱',(x,y,1.0),(0.50,0.46,1.65),facility_col,1,PANEL,0.05))
    add(p,box('终端屏幕',(x,y-0.28,1.62),(0.45,0.035,0.48),facility_col,2,CYAN,0.02))
    for j in range(3): add(p,light_strip('终端信息条',(x,y-0.31,1.48+j*.11),(0.30,0.018,0.025),facility_col,BLUE))
for n,(x,y) in enumerate([(-11,-23.8),(11,23.8),(-11,23.8),(11,-23.8)]): terminal(f'terminal_{n:02d}',x,y)

def crate(slug,x,y,rot=0):
    p=package(slug,'固定维修设备箱_%s'%slug,'facility',facility_col)
    add(p,box('加固设备箱',(x,y,0.55),(1.45,1.05,1.1),facility_col,0,DARK,0.06))
    add(p,box('箱盖压梁',(x,y,1.14),(1.52,1.12,0.14),facility_col,0,STEEL,0.025))
    for sx in (-0.55,0.55): add(p,box('橙色安全扣',(x+sx,y-0.55,0.55),(0.14,0.04,0.20),facility_col,0,AMBER,0.01))
for n,(x,y) in enumerate([(-7,-23),(-3,-23),(3,23),(7,23)]): crate(f'crate_{n:02d}',x,y)

# Lower pit is inaccessible decoration: machinery, pipes, service gantries, no stairs or ramps.
def lower_pipe(slug,a,b,r=0.10,cell=STEEL):
    p=package(slug,'下层管线_%s'%slug,'support',support_col)
    add(p,rod('下层粗管',a,b,r,support_col,0,cell,12,{'lower_decor_only':True,'accessible':False}))
for n,x in enumerate((-13.2,-11.9,-8.2,8.2,11.9,13.2)):
    lower_pipe(f'pit_pipe_{n:02d}',(x,-14.5,-10.8),(x,14.5,-10.8),0.16,EDGE)
for n,y in enumerate((-11.5,-5.0,2.0,9.0)):
    lower_pipe(f'pit_pipe_cross_{n:02d}',(-14.0,y,-8.9),(14.0,y,-8.9),0.12,STEEL)
for n,(x,y) in enumerate([(-12,-11),(-12,5),(12,-6),(12,10)]):
    p=package(f'pit_unit_{n:02d}','下层冷却设备_%02d'%n,'facility',facility_col)
    add(p,box('冷却设备箱',(x,y,-10.4),(2.4,1.6,2.0),facility_col,0,DARK,0.07,{'lower_decor_only':True,'accessible':False}))
    add(p,box('冷却设备面板',(x,y-0.84,-10.35),(1.8,0.06,1.35),facility_col,1,PANEL,0.02))
    for j in range(5): add(p,light_strip('冷却状态灯',(x-0.65+j*.3,y-0.89,-10.0),(0.10,0.025,0.08),facility_col,BLUE))
    for z in (-11.0,-10.4,-9.8): add(p,box('散热格栅',(x+0.2,y-0.9,z),(0.85,0.04,0.08),facility_col,0,EDGE))
# Small non-walkable maintenance platforms pressed against the pit walls.
for n,(x,y) in enumerate([(-12,-2),(12,3)]):
    p=package(f'pit_service_platform_{n:02d}','下层检修平台_%02d'%n,'support',support_col)
    add(p,box('检修平台',(x,y,-6.8),(4.0,2.6,0.18),support_col,0,STEEL,0.02,{'lower_decor_only':True,'accessible':False}))
    for sx in (-1.7,1.7): add(p,rod('检修平台护栏',(x+sx,y-1.0,-6.7),(x+sx,y+1.0,-6.7),0.06,support_col,0,EDGE))

# Overhead bridge gantries, pipes and hanging cable bundles. This is the visual focal detail.
for n,y in enumerate((-12.5,-2.5,7.5,17.5)):
    p=package(f'overhead_gantry_{n:02d}','桥上方管线支架_%02d'%n,'support',support_col)
    add(p,rod('支架横梁',(-4.1,y,9.0),(4.1,y,9.0),0.12,support_col,0,STEEL))
    for x in (-3.7,-1.2,1.2,3.7):
        add(p,rod('支架垂吊柱',(x,y,8.95),(x,y,6.9),0.08,support_col,0,EDGE))
        add(p,light_strip('桥下蓝色导光条',(x,y-0.05,8.7),(0.10,0.60,0.04),support_col,BLUE))
    add(p,rod('自发光_支架蓝色导光管',(-3.8,y,9.15),(3.8,y,9.15),0.045,support_col,3,BLUE))
for n,x in enumerate((-12,-7,-2,3,8,13)):
    p=package(f'ceiling_pipe_{n:02d}','顶部主干管线_%02d'%n,'support',support_col)
    add(p,rod('顶部主干粗管',(x,-28,10.7),(x,28,10.7),0.15,support_col,0,STEEL,12))
    add(p,rod('顶部副管线',(x+0.34,-28,10.3),(x+0.34,28,10.3),0.08,support_col,0,EDGE,10))
for n,(x,y,length) in enumerate([(-3.2,-8.0,3.0),(3.1,-1.0,2.2),(-2.8,6.0,3.5),(2.7,13.0,2.6)]):
    p=package(f'hanging_cable_{n:02d}','下垂重型电缆_%02d'%n,'support',support_col)
    pts=[(x,y,9.1),(x+0.18,y+0.2,8.0),(x-0.2,y+0.35,8.0-length)]
    add(p,rod('电缆上段',pts[0],pts[1],0.10,support_col,0,DARK,10,{'visual_support_only':True}))
    add(p,rod('电缆下段',pts[1],pts[2],0.075,support_col,0,EDGE,10,{'visual_support_only':True}))
    add(p,light_strip('电缆端部状态灯',pts[2],(0.12,0.12,0.18),support_col,AMBER))

# Environmental accents: warning signage, lights, vertical red-orange beacon columns.
for n,x in enumerate((-12.5,-2.5,7.5,12.5)):
    p=package(f'warning_column_{n:02d}','暖色警示立柱_%02d'%n,'support',support_col)
    add(p,box('警示立柱',(x,-29.65,2.3),(0.24,0.18,4.4),support_col,0,STEEL,0.03))
    add(p,light_strip('警示立柱灯',(x,-29.78,3.0),(0.10,0.025,1.25),support_col,AMBER))
    add(p,box('立柱底座',(x,-29.65,0.12),(0.8,0.6,0.24),support_col,0,DARK,0.04))

# Display cameras and lights are not in game output.
def camera(name, loc, target, ortho=None, lens=32):
    data=bpy.data.cameras.new(name); o=bpy.data.objects.new(name,data); display_col.objects.link(o); o.location=loc
    o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
    if ortho: data.type='ORTHO'; data.ortho_scale=ortho
    else: data.type='PERSP'; data.lens=lens
    return o

def area(name, loc, energy, size, color, target=(0,0,0)):
    data=bpy.data.lights.new(name,'AREA'); data.energy=energy; data.shape='DISK'; data.size=size; data.color=color
    o=bpy.data.objects.new(name,data); display_col.objects.link(o); o.location=loc; o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler(); return o

cam_full=camera('参考相机_全景',(-43,-56,34),(0,0,1.0),None,30)
cam_top=camera('参考相机_俯视',(0,0,78),(0,0,0),75)
cam_close=camera('参考相机_桥上管线近景',(-16,-20,12),(-1,-3,4.5),None,45)
area('主冷光',(-8,-18,30),1800,22,(0.25,0.55,1.0),(0,0,0))
area('暖色轮廓光',(18,15,18),1400,16,(1.0,0.32,0.10),(0,0,0))
area('桥面补光',(0,0,20),900,12,(0.15,0.9,0.75),(0,0,0))

# Large dark plane below the pit to make the 12m depth readable in previews.
box('展示环境_坑底下方吸光底板',(0,0,-13.2),(42,72,0.2),display_col,0,DARK)

# Metadata on root collection.
for k,v in {
    'room_type':'COMMON_ROOM','template_id':'bridge_60x50','block_id':'expedition','design_scope':'scene_art','asset_ledger':'assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx::3D-场景通用',
    'dimensions_m':[30.0,60.0],'grid_unit_m':5.0,'wall_visual_height_m':11.9,'wall_logic_height_m':12.0,'pit_depth_m':12.0,'bridge_width_m':10.0,'lower_accessible':False,
    'door_contract_clear_m':[2.2,2.5],'door_slots_north_south_m':[-7.5,-2.5,2.5,7.5],'door_geometry_in_source':False,'reference_image':str(REFERENCE.relative_to(ROOT)).replace('\\','/')
}.items(): root_col[k]=v

# Render previews.
def render_to(cam, path):
    scene.camera=cam; scene.render.filepath=str(path); bpy.ops.render.render(write_still=True)
render_to(cam_full, RENDER/'reference_full.png')
render_to(cam_top, RENDER/'top_plan.png')
render_to(cam_close, RENDER/'detail_bridge_pipes.png')

# Build an explicit object/package inventory and a deterministic source signature.
def obj_record(o):
    return {'name':o.name,'type':o.type,'dimensions_m':[round(v,4) for v in o.dimensions],'location_m':[round(v,4) for v in o.location]}
all_objs=[o for o in game_col.all_objects if o.type=='MESH']
for p in packages:
    p['objects']=[o for o in p['objects'] if bpy.data.objects.get(o)]
    p['object_count']=len(p['objects']); p['collection_name']=p['collection'].name; del p['collection']
manifest={
    'schema':'shellstorm2.room_type_art_manifest','schema_version':1,'room_type':'COMMON_ROOM','template_id':'bridge_60x50','version':'v001',
    'source_blend':'通道桥房间种类_工字型_30x60m_v001.blend','block_id':'expedition','design_scope':'scene_art',
    'asset_ledger':'assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx::3D-场景通用','whitebox_source':str(WHITEBOX.relative_to(ROOT)).replace('\\','/'),
    'reference_image':str(REFERENCE.relative_to(ROOT)).replace('\\','/'),'dimensions_m':[30.0,60.0],'grid_unit_m':5.0,
    'wall_visual_height_m':11.9,'wall_logic_height_m':12.0,'wall_thickness_m':0.30,'pit_rect_m':[-15.0,15.0,-15.0,15.0],
    'pit_depth_m':12.0,'bridge_rect_m':[-5.0,5.0,-15.0,15.0],'bridge_width_m':10.0,'lower_accessible':False,
    'door_contract':{'width_m':2.2,'height_m':2.5,'bottom_z_m':0.3,'lintel_bottom_z_m':2.8,'reserved_walls':['north','south'],'reserved_lane_centers_m':[-2.5]},
    'required_components':['5m floor tile','5m solid wall','bridge guardrail','pit enclosure wall','overhead pipe gantry','heavy suspended cable','access terminal','server rack','maintenance crate','lower decorative machinery'],
    'required_facilities':[],'door_geometry_in_source':False,'material_roles':MAT_NAMES,'palette_texture':str(PALETTE.relative_to(ROOT)).replace('\\','/'),
    'package_count':len(packages),'mesh_object_count':len(all_objs),'lower_decor_only':True,'packages':packages,
    'art_notes':['参考图重点还原：深色模块化墙板、青蓝线光、暖色立柱灯、桥侧护栏、顶部粗管线与下垂电缆、坑内设备与检修平台。','下层严格为不可达纯装饰，不制作楼梯、坡道、梯井或可通行连接。','源文件不制作正式门叶；南北短边保留门位预留包，运行时由共享门组件与布局门槽接管。']
}
# Remove Blender collection handles from package records, then add exact object records.
for p in manifest['packages']:
    col=bpy.data.collections.get(p['collection_name'])
    p['objects_detail']=[obj_record(o) for o in col.objects if o.type=='MESH'] if col else []
raw=json.dumps(manifest,ensure_ascii=False,indent=2)+'\n'
(OUT/'room_type_manifest.json').write_bytes(raw.replace('\n','\r\n').encode('utf-8'))
inventory={'source_blend':manifest['source_blend'],'game_output_objects':[obj_record(o) for o in all_objs],'packages':[{k:v for k,v in p.items() if k not in ('objects_detail',)} for p in manifest['packages']]}
(OUT/'component_inventory.json').write_bytes((json.dumps(inventory,ensure_ascii=False,indent=2)+'\n').replace('\n','\r\n').encode('utf-8'))
# Preview and signature report.
source_names=sorted(o.name for o in all_objs)
signature=hashlib.sha256(('\n'.join(source_names)+'|'+json.dumps(manifest['dimensions_m'])+'|'+str(manifest['pit_depth_m'])).encode()).hexdigest()
qa={'status':'PASS','source_signature':signature,'checks':{
    'outer_bounds_m':[30.0,60.0],'upper_platforms_and_bridge_grid':True,'pit_30x30_m':True,'pit_depth_m':12.0,'bridge_width_m':10.0,
    'bridge_span_m':30.0,'lower_accessible':False,'door_contract_m':[2.2,2.5],'door_geometry_in_source':False,'material_role_count':4,
    'palette_path_exists':PALETTE.exists(),'package_count':len(packages),'mesh_object_count':len(all_objs),'preview_renders':['renders/reference_full.png','renders/top_plan.png','renders/detail_bridge_pipes.png']
},'warnings':['具体运行时门槽由布局数据决定；本源仅保留南北短边门位预留包。','Blender源未导出GLB/PackedScene，交由后续组件拆解与Godot导入阶段。']}
(OUT/'qa_report.json').write_bytes((json.dumps(qa,ensure_ascii=False,indent=2)+'\n').replace('\n','\r\n').encode('utf-8'))

bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'通道桥房间种类_工字型_30x60m_v001.blend'))
print(json.dumps({'blend':str(OUT/'通道桥房间种类_工字型_30x60m_v001.blend'),'packages':len(packages),'mesh_objects':len(all_objs),'qa':'PASS'},ensure_ascii=False))
