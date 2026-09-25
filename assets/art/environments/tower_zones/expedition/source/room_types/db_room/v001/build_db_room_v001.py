"""数据库房间种类（不规则 40x30m · db_01 布局）美术源 v001。参考图导向深化，Blender 4.5。

冻结契约：40x30m 包围盒 / 墙高 11.9m / 5m 模数 / 门洞 2.2x2.5 底 0.3m 过梁底 2.8m。
轮廓（db_01，非矩形）：主体 40x25 + 南侧中段外凸 10x5（面积 1050 m²）。

🔴 本房型的**墙件与地砖全部 Library Link 引用 office_room/v001**（业主指令
「墙和地砖使用办公室的墙和地砖组件。其它组件重新制作」）。本房型源**自持几何 = 0 墙 0 砖**，
只自产「数据库机房专属」的新组件：地面标识 / 格栅 / 地面设备坑 / 吊顶与顶部管线 / 机柜 /
工作台 / 工具车 / 货箱 / 电缆盘 / 花箱 / 壁挂屏 / 墙面灯柱与走管 等。
公共唯一色盘 + 四共享材质角色 + PaletteUV；每末级语义包一 Collection + asset_manifest.json。
"""
from pathlib import Path
import bpy, math, json, hashlib, random, sys, argparse
from mathutils import Vector, Matrix

HERE = Path(__file__).resolve(); OUT = HERE.parent; ROOT = HERE.parents[9]
RENDER = OUT/'renders'; RENDER.mkdir(exist_ok=True)
PKGDIR = OUT/'component_packages_v001'
PALETTE = ROOT/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
WHITEBOX = ROOT/'source/art/whitebox/tower_zones/expedition_01/v001/data/room_templates/db_70x50.json'
REF = ROOT/'docs/v0.1/design/refs/expedition01/数据库房间01.jpg'
BLEND = '数据库房间种类_数据机房_40x30m_v001.blend'
OFFICE_BLEND = ROOT/'assets/art/environments/tower_zones/expedition/source/room_types/office_room/v001/办公室房间种类_开放办公_30x40m_v001.blend'
OFFICE_PKGDIR = ROOT/'assets/art/environments/tower_zones/expedition/source/room_types/office_room/v001/component_packages_v001'

args = argparse.ArgumentParser()
args.add_argument('--preview', action='store_true')
args.add_argument('--no-render', action='store_true')
opts = args.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'; scene.unit_settings.scale_length = 1
scene.render.engine = 'CYCLES'; scene.cycles.samples = 32 if opts.preview else 96
scene.cycles.use_denoising = True
try:
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'OPTIX'; prefs.get_devices()
    for d in prefs.devices: d.use = d.type != 'CPU'
    if any(d.use for d in prefs.devices): scene.cycles.device = 'GPU'
except Exception: pass
scene.render.resolution_x = 1400; scene.render.resolution_y = 1400
scene.render.resolution_percentage = 65 if opts.preview else 100
scene.render.image_settings.file_format = 'PNG'; scene.render.film_transparent = False
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'; scene.view_settings.exposure = 0.10
world = bpy.data.worlds.new('冷蓝灰展示环境'); scene.world = world; world.use_nodes = True
world.node_tree.nodes.clear()
bg = world.node_tree.nodes.new('ShaderNodeBackground'); wo = world.node_tree.nodes.new('ShaderNodeOutputWorld')
world.node_tree.links.new(bg.outputs['Background'], wo.inputs['Surface'])
bg.inputs['Color'].default_value = (.085, .125, .20, 1); bg.inputs['Strength'].default_value = .55

# ---------------------------------------------------------------- collections
def collection(name, parent):
    c = bpy.data.collections.new(name); parent.children.link(c); return c

root = collection('数据库房间_数据机房_v001', scene.collection)
src = collection('01_制作组件_按设施拆分', root)
game = collection('02_游戏输出_独立资产包_v001', root)
cats = {k: collection(v, game) for k, v in [('floor', '01_地面系统'), ('facilities', '02_区域固定设施'),
                                            ('support', '03_环境支持')]}
link_host = collection('05_链接引用_办公室墙地_v001', root)
display = collection('90_展示与验收_灯光相机', root)

# ---------------------------------------------------------------- materials
img = bpy.data.images.load(str(PALETTE), check_existing=True); img.filepath = str(PALETTE)
roles = ['01_精工金属_紫色骨架', '02_细腻哑光_青绿大面', '03_清漆反光_紫粉点缀', '04_柔和自发光_UI灯光']
conf = [(.86, .26, .18), (.04, .72, 0.0), (.20, .13, .70), (0, .34, 0)]
mats = []
for i, (name, c) in enumerate(zip(roles, conf)):
    m = bpy.data.materials.new(name); m.use_nodes = True
    n = m.node_tree.nodes; n.clear(); l = m.node_tree.links
    u = n.new('ShaderNodeUVMap'); u.uv_map = 'PaletteUV'
    t = n.new('ShaderNodeTexImage'); t.image = img; t.interpolation = 'Closest'
    bs = n.new('ShaderNodeBsdfPrincipled'); o = n.new('ShaderNodeOutputMaterial')
    bs.inputs['Metallic'].default_value = c[0]; bs.inputs['Roughness'].default_value = c[1]
    bs.inputs['Coat Weight'].default_value = c[2]
    l.new(u.outputs['UV'], t.inputs['Vector']); l.new(t.outputs['Color'], bs.inputs['Base Color'])
    if i == 3:
        l.new(t.outputs['Color'], bs.inputs['Emission Color']); bs.inputs['Emission Strength'].default_value = 16.0
    l.new(bs.outputs['BSDF'], o.inputs['Surface']); mats.append(m)

# 色盘取样实测值（设施低亮多巴胺色盘_10x10_512.png，10x10 纯色格；元组为 (列,行)）
VOID = (0, 9); DARK = (9, 0); PANEL = (9, 1); HULL = (9, 2); EDGE = (9, 3)
MID = (9, 4); STEEL = (9, 5); PALE = (9, 6); HI = (9, 7); HI2 = (9, 8); WHITE = (9, 9)
BLUE = (8, 0); BLUEB = (4, 6); INDIGO = (2, 9); CYAN = (3, 0); ICE = (6, 5); TEAL = (5, 5)
GREEN = (6, 4); GREEN_D = (1, 4); AMBER = (6, 3); RUST = (4, 2); RED = (5, 1)
TAN = (8, 2); CARD = (6, 9); PURPLE = (7, 7)

# ---------------------------------------------------------------- room contract
W, D = 40.0, 30.0
HX, HY = W/2, D/2                      # 20 / 15
WALL_T, WALL_H, GRID = 0.30, 11.9, 5.0
MAIN = (-HX, -10.0, HX, HY)            # 主体 40 x 25：X∈[-20,20] Y∈[-10,15]
TAB = (-5.0, -HY, 5.0, -10.0)          # 南侧中段外凸 10 x 5：X∈[-5,5] Y∈[-15,-10]
EPS = 1e-6

def inside(x, y):
    """点是否落在 db_01 轮廓内（主体 ∪ 外凸；两者都是轴对齐矩形 ⇒ 并集判定即精确）。"""
    return (MAIN[0]-EPS <= x <= MAIN[2]+EPS and MAIN[1]-EPS <= y <= MAIN[3]+EPS) or \
           (TAB[0]-EPS <= x <= TAB[2]+EPS and TAB[1]-EPS <= y <= TAB[3]+EPS)

MAIN_ENV = (MAIN[0]-WALL_T/2-.01, MAIN[1]-WALL_T/2-.01, MAIN[2]+WALL_T/2+.01, MAIN[3]+WALL_T/2+.01)
TAB_ENV = (TAB[0]-WALL_T/2-.01, TAB[1]-WALL_T/2-.01, TAB[2]+WALL_T/2+.01, TAB[3]+WALL_T/2+.01)
def inside_env(x, y):
    return (MAIN_ENV[0] <= x <= MAIN_ENV[2] and MAIN_ENV[1] <= y <= MAIN_ENV[3]) or \
           (TAB_ENV[0] <= x <= TAB_ENV[2] and TAB_ENV[1] <= y <= TAB_ENV[3])

# 墙体定义：plane = 墙中心面基准点，inward = 指向房内，along = 墙走向，center = 该段墙中点
WALLDEF = {
    'north': dict(plane=Vector((0, HY, 0)), inward=Vector((0, -1, 0)), along=Vector((1, 0, 0)), center=0.0),
    'south_w': dict(plane=Vector((0, -10, 0)), inward=Vector((0, 1, 0)), along=Vector((1, 0, 0)), center=-12.5),
    'south_e': dict(plane=Vector((0, -10, 0)), inward=Vector((0, 1, 0)), along=Vector((1, 0, 0)), center=12.5),
    'tab_s': dict(plane=Vector((0, -HY, 0)), inward=Vector((0, 1, 0)), along=Vector((1, 0, 0)), center=0.0),
    'tab_w': dict(plane=Vector((-5, 0, 0)), inward=Vector((1, 0, 0)), along=Vector((0, 1, 0)), center=-12.5),
    'tab_e': dict(plane=Vector((5, 0, 0)), inward=Vector((-1, 0, 0)), along=Vector((0, 1, 0)), center=-12.5),
    'east': dict(plane=Vector((HX, 0, 0)), inward=Vector((-1, 0, 0)), along=Vector((0, 1, 0)), center=2.5),
    'west': dict(plane=Vector((-HX, 0, 0)), inward=Vector((1, 0, 0)), along=Vector((0, 1, 0)), center=2.5),
}
WALL_ORDER = ('north', 'tab_s', 'tab_w', 'tab_e', 'east', 'west', 'south_w', 'south_e')

# ---------------------------------------------------------------- packaging
packages = []; current = None

def pack(slug, title, cat, cut=False, coll='self', visual_only=False, wall=None):
    global current
    c = collection(title+'_资产包', cats[cat])
    current = {'slug': slug, 'title': title, 'category': cat, 'col': c, 'cutaway': cut,
               'collision_owner': coll, 'visual_only': visual_only, 'items': [], 'wall': wall}
    packages.append(current); return current

def uv_mesh(mesh, cell):
    layer = mesh.uv_layers.new(name='PaletteUV'); mesh.uv_layers.active = layer; layer.active_render = True
    for p in mesh.polygons:
        for j, li in enumerate(p.loop_indices):
            a = 2*math.pi*j/len(p.loop_indices)
            layer.data[li].uv = ((cell[0]+.5)/10+.022*math.cos(a), 1-(cell[1]+.5)/10+.022*math.sin(a))

def mesh_obj(name, verts, faces, mat=0, cell=PANEL, bevel=0):
    mesh = bpy.data.meshes.new(name); mesh.from_pydata(verts, [], faces); mesh.update()
    mesh.materials.append(mats[mat]); uv_mesh(mesh, cell)
    o = bpy.data.objects.new(('自发光_' if mat == 3 else '')+name, mesh)
    current['col'].objects.link(o); current['items'].append(o)
    o['palette_cell'] = list(cell); o['material_role'] = mat
    if bevel:
        b = o.modifiers.new('机械倒角', 'BEVEL'); b.width = bevel; b.segments = 2
        o.modifiers.new('加权法线', 'WEIGHTED_NORMAL')
    return o

cube_faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]

def box(name, loc, dims, mat=0, cell=PANEL, bevel=.025, rot=0.0):
    dx, dy, dz = [v/2 for v in dims]
    v = [(-dx, -dy, -dz), (dx, -dy, -dz), (dx, dy, -dz), (-dx, dy, -dz),
         (-dx, -dy, dz), (dx, -dy, dz), (dx, dy, dz), (-dx, dy, dz)]
    o = mesh_obj(name, v, cube_faces, mat, cell, min(bevel, min(dims)*.25))
    o.location = loc; o.rotation_euler.z = rot; return o

def cyl(name, a, b, r=.08, mat=0, cell=EDGE, n=12):
    a, b = Vector(a), Vector(b); d = b-a; L = d.length; verts = []
    for z in (-L/2, L/2):
        verts.extend([(r*math.cos(j*2*math.pi/n), r*math.sin(j*2*math.pi/n), z) for j in range(n)])
    faces = [tuple(reversed(range(n))), tuple(range(n, 2*n))] + [(j, (j+1) % n, (j+1) % n+n, j+n) for j in range(n)]
    o = mesh_obj(name, verts, faces, mat, cell)
    o.location = (a+b)/2; o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = d.to_track_quat('Z', 'Y'); return o

SEG = {'a': ((.10, 1.00), (.90, 1.00)), 'b': ((.95, .95), (.95, .55)), 'c': ((.95, .45), (.95, .05)),
       'd': ((.10, .00), (.90, .00)), 'e': ((.05, .05), (.05, .45)), 'f': ((.05, .55), (.05, .95)),
       'g': ((.10, .50), (.90, .50))}
DIG = {'0': 'abcdef', '1': 'bc', '2': 'abged', '3': 'abgcd', '4': 'fgbc',
       '5': 'afgcd', '6': 'afgedc', '7': 'abc', '8': 'abcdefg', '9': 'abcdfg'}

def glyph(name, ch, loc, h=.62, cell=WHITE, w=.024, mat=1, rot=0.0):
    """七段笔画字模（数字 + A/B），供地面分区编号用。"""
    ca, sa = math.cos(rot), math.sin(rot)
    def P(u, v):
        return (loc[0]+u*ca-v*sa, loc[1]+u*sa+v*ca, loc[2])
    for s in DIG[ch]:
        (u1, v1), (u2, v2) = SEG[s]
        cyl(name, P(u1*h, v1*h), P(u2*h, v2*h), w, mat, cell, 8)

def bolts(x, y, z, w, d):
    for sx in (-1, 1):
        for sy in (-1, 1):
            cyl('固定螺栓', (x+sx*w, y+sy*d, z), (x+sx*w, y+sy*d, z+.035), .045, 0, STEEL, 6)

def casters(name, x, y, z, w, d, r=.055):
    for sx in (-1, 1):
        for sy in (-1, 1):
            cyl(name, (x+sx*w, y+sy*d, z), (x+sx*w, y+sy*d, z+2*r), r, 0, VOID, 10)
            cyl(name, (x+sx*w-.02, y+sy*d, z+r), (x+sx*w+.02, y+sy*d, z+r), r*1.25, 0, STEEL, 10)

def wp(side, u, v, z):
    """墙坐标系 -> 世界：u 沿墙走向（相对该段中点），v 自墙中心面指向房内。"""
    d = WALLDEF[side]
    p = d['plane'] + d['along']*(d['center']+u) + d['inward']*v
    return (p.x, p.y, z)

def wbox(side, name, u, v, z, w_along, d_in, h, mat=0, cell=PANEL, bev=.02, rot=0.0):
    d = WALLDEF[side]; p = wp(side, u, v, z)
    if abs(d['along'].y) > .5:
        return box(name, p, (d_in, w_along, h), mat, cell, bev, rot)
    return box(name, p, (w_along, d_in, h), mat, cell, bev, rot)

def wcyl(side, name, u1, v1, z1, u2, v2, z2, r=.06, mat=0, cell=EDGE, n=10):
    return cyl(name, wp(side, u1, v1, z1), wp(side, u2, v2, z2), r, mat, cell, n)

# ================================================================ 00 链接引用
# 🔴 业主指令：墙件与地砖复用 office_room/v001 的已验收组件。Library Link（不 Append、不复制网格）。
#    被链接集合只有挂进「集合实例空物体」后才算落位；组件根原点带源房间世界坐标
#    ⇒ 空物体 L = P_dst − R·origin_src（绕组件自身原点旋转）。
OFF_WALL_PLAIN = {
    'north': [-2, -1, 1],            # north_墙体_-3 挂旗幡、-2 空、-1 走管、1 走管（k=0 是门洞件）
    'south': [-2, -1, 0, 1],         # -3 配电、2 货架标 ⇒ 只用 4 个素件
    'east': [-3, -2, -1, 0, 1, 2],   # -4 / 3 挂窗带 ⇒ 只用 6 个素件
    'west': [-3, -2, -1, 0, 1, 2],   # -4 监视屏 / 3 通告板 ⇒ 只用 6 个素件
}
DOOR_WALL_SLUG = ('door_wall',)

# 28 樘墙件：(目标段, 沿墙坐标, 目标 inward, 源 slug)
WALL_PLAN = []
for x in (-17.5, -12.5, -7.5, -2.5, 2.5, 7.5, 12.5, 17.5):
    WALL_PLAN.append(('north', x, (0, -1, 0)))
for x in (-17.5, -12.5, -7.5):
    WALL_PLAN.append(('south_w', x, (0, 1, 0)))
for x in (7.5, 12.5, 17.5):
    WALL_PLAN.append(('south_e', x, (0, 1, 0)))
WALL_PLAN.append(('tab_s', -2.5, (0, 1, 0)))
WALL_PLAN.append(('tab_s', 2.5, (0, 1, 0)))          # ← 门洞墙件（可复用）
WALL_PLAN.append(('tab_w', -12.5, (1, 0, 0)))
WALL_PLAN.append(('tab_e', -12.5, (-1, 0, 0)))
for y in (-7.5, -2.5, 2.5, 7.5, 12.5):
    WALL_PLAN.append(('east', y, (-1, 0, 0)))
for y in (-7.5, -2.5, 2.5, 7.5, 12.5):
    WALL_PLAN.append(('west', y, (1, 0, 0)))

# 源指派：只用「素件」（不带办公室专属装饰），按朝向池顺序取，保证每樘源 slug 互不重复
SRC_POOL = {
    (0, -1, 0): [('north', -2), ('south', -2), ('north', -1), ('south', -1),
                 ('north', 1), ('south', 0), ('east', -2), ('south', 1)],
    (0, 1, 0): [('south', -2), ('north', -2), ('south', -1), ('south', 0),
                ('north', -1), ('south', 1), ('north', 1)],
    (-1, 0, 0): [('east', -3), ('east', -2), ('east', -1), ('east', 0), ('east', 1), ('east', 2)],
    (1, 0, 0): [('west', -3), ('west', -2), ('west', -1), ('west', 0), ('west', 1), ('west', 2)],
}
_cursor = {}
FORWARD_DEG = {(-1, 0): 0.0, (0, 1): 90.0, (1, 0): 180.0, (0, -1): 270.0}
def inward_deg(v):
    for (a, b), deg in FORWARD_DEG.items():
        if (a, b) == (v[0], v[1]): return deg
    raise AssertionError(v)

def ru(side, u_abs):
    """把「沿墙绝对坐标」换算为 wp()/wbox()/wcyl() 需要的「相对该段中点」坐标。"""
    return u_abs - WALLDEF[side]['center']

WALL_SRC = []           # (side, u, inward, source_slug, rotation_deg)
for side, u, inward in WALL_PLAN:
    if side == 'tab_s' and u == 2.5:
        WALL_SRC.append((side, u, inward, DOOR_WALL_SLUG[0], 180.0)); continue
    pool = SRC_POOL[inward]
    i = _cursor.get(inward, 0); _cursor[inward] = i+1
    src_side, src_k = pool[i % len(pool)]
    WALL_SRC.append((side, u, inward, '%s_墙体_%d' % (src_side, src_k), None))

# 地砖：db 8x6 网格（ix∈[-4,3], iy∈[-3,2]）取落在轮廓内的 42 格
TILE_PLAN = []
for iy in range(-3, 3):
    for ix in range(-4, 4):
        x, y = ix*GRID+GRID/2, iy*GRID+GRID/2
        if inside(x, y, ) or inside(x+2.4, y) or inside(x-2.4, y) or inside(x, y+2.4) or inside(x, y-2.4):
            if inside(x-2.49, y-2.49) and inside(x+2.49, y-2.49) and inside(x-2.49, y+2.49) and inside(x+2.49, y+2.49):
                ox = ix if -3 <= ix <= 2 else (2 if ix == -4 else -3)
                TILE_PLAN.append((ix, iy, ox, iy))

wall_instances = []; tile_instances = []
if not OFFICE_BLEND.is_file():
    raise SystemExit('MISSING OFFICE LIBRARY: %s' % OFFICE_BLEND)

# 由 slug 反推 office 集合名（office 集合名 = '<side>_墙体_<k>_资产包'）
def office_coll_of(slug):
    if slug == DOOR_WALL_SLUG[0]: return '门洞墙件_可复用_资产包'
    side, k = slug.split('_墙体_')
    return '%s_墙体_%s_资产包' % (side, k)
need = {office_coll_of(s) for _s, _u, _i, s, _r in WALL_SRC}
need |= {'地砖_%d_%d_资产包' % (ox, oy) for _ix, _iy, ox, oy in TILE_PLAN}

with bpy.data.libraries.load(str(OFFICE_BLEND), link=True) as (lib_from, lib_to):
    lib_to.collections = [n for n in lib_from.collections if n in need]
LINKED = {c.name: c for c in bpy.data.collections if c.library is not None}
missing_link = sorted(need - set(LINKED))
if missing_link:
    raise SystemExit('MISSING LINKED COLLECTIONS: %s' % missing_link)

def src_origin(coll):
    """被链接组件的源原点（= 组件自身坐标系原点）。matrix_world 必为单位阵，只有 matrix_basis 可信。"""
    o = sorted(coll.objects, key=lambda x: x.name)[0]
    mb = o.matrix_basis
    assert abs(mb.to_scale().x-1) < 1e-6 and abs(mb.to_euler().z) < 1e-6, o.name
    return Vector(mb.translation)

def link_instance(tag, coll, dst, rot_deg, side_tag):
    R = Matrix.Rotation(math.radians(rot_deg), 3, 'Z')
    org = src_origin(coll)
    e = bpy.data.objects.new('LINK_%s' % tag, None)
    e.instance_type = 'COLLECTION'; e.instance_collection = coll
    e.location = Vector(dst) - (R @ org)
    e.rotation_euler = (0.0, 0.0, math.radians(rot_deg))
    e['link_source_library'] = OFFICE_BLEND.name
    e['link_source_collection'] = coll.name
    e['link_src_origin_m'] = list(org); e['link_dst_origin_m'] = list(dst)
    e['link_rotation_deg'] = rot_deg; e['link_wall_side'] = side_tag
    link_host.objects.link(e)
    return e

WALL_OFFSETS = {}
for side, u, inward, slug, rotd in WALL_SRC:
    cname = office_coll_of(slug)
    coll = LINKED[cname]
    org = src_origin(coll)
    # 源 inward：由 office 集合名反推
    s_side = 'door' if slug == DOOR_WALL_SLUG[0] else slug.split('_墙体_')[0]
    src_inward = Vector({'north': (0, -1, 0), 'south': (0, 1, 0),
                         'east': (-1, 0, 0), 'west': (1, 0, 0), 'door': (0, -1, 0)}[s_side])
    # offset = 沿 inward 方向「office 外墙边线 -> 组件包 origin」的有符号距离。
    # office 房界：x 半宽 HX=15（西/东墙边线 x=∓15）、y 半深 HY=20（南/北墙边线 y=∓20）。
    # origin = 整樘 bbox 中心（含朝房内前凸装饰）⇒ offset ≈ -0.1675（内缩），门洞件 -0.1575。
    if src_inward.y < 0:   offset = 20.0 - org.y
    elif src_inward.y > 0: offset = org.y + 20.0
    elif src_inward.x < 0: offset = 15.0 - org.x
    else:                  offset = org.x + 15.0
    WALL_OFFSETS[slug] = round(offset, 5)
    d = WALLDEF[side]
    dst = d['plane'] + d['along']*u + d['inward']*offset
    if rotd is None:
        rotd = (inward_deg(inward) - inward_deg(src_inward)) % 360.0
    wall_instances.append(dict(side=side, u=u, slug=slug, coll=cname, offset_m=offset,
                               rotation_deg=rotd, dst_origin_m=[round(v, 5) for v in dst],
                               inward=inward, is_door=(slug == DOOR_WALL_SLUG[0])))
    link_instance('WALL_%s_%s' % (side, str(u).replace('-', 'm').replace('.', 'p')), coll, dst, rotd, side)

for ix, iy, ox, oy in TILE_PLAN:
    cname = '地砖_%d_%d_资产包' % (ox, oy)
    dst = Vector((ix*GRID+GRID/2, iy*GRID+GRID/2, -0.32))
    tile_instances.append(dict(grid=[ix, iy], slug='tile_%d_%d' % (ox, oy), coll=cname,
                               dst_origin_m=[round(v, 5) for v in dst], rotation_deg=0.0))
    link_instance('TILE_%d_%d' % (ix, iy), LINKED[cname], dst, 0.0, 'floor')

# ================================================================ 01 地面系统
pack('floor_hazard_edging', '沿墙黄黑警示边带', 'floor', coll='visual_only', visual_only=True)
HZ_EDGES = [('north', 39.2, 0.0, 0.0), ('east', 24.2, 0.0, 0.0), ('south_e', 14.2, 0.0, 0.0),
            ('south_w', 14.2, 0.0, 0.0), ('west', 24.2, 0.0, 0.0)]
for side, ln, _a, _b in HZ_EDGES:
    wbox(side, '警示带基底', 0.0, 0.66, .030, ln, .34, .045, 0, VOID, .004)
    wbox(side, '警示带黄面', 0.0, 0.615, .060, ln, .26, .028, 1, AMBER, .003)
    n = int(ln//0.62)
    for j in range(n):
        u = -ln/2 + .42 + j*.62
        wbox(side, '警示斜条', u, .615, .078, .34, .275, .012, 0, VOID, .002, math.radians(32))
# 外凸段（10m）单独一条
for side, ln in (('tab_s', 9.2),):
    wbox(side, '警示带基底', 0.0, .66, .030, ln, .34, .045, 0, VOID, .004)
    wbox(side, '警示带黄面', 0.0, .615, .060, ln, .26, .028, 1, AMBER, .003)
    for j in range(int(ln//0.62)):
        u = -ln/2 + .42 + j*.62
        wbox(side, '警示斜条', u, .615, .078, .34, .275, .012, 0, VOID, .002, math.radians(32))

pack('floor_zone_mark', '地面分区标识', 'floor', coll='visual_only', visual_only=True)
for num, px, py, rot in (('01', 0.0, 7.5, 0.0), ('02', -10.0, 2.5, math.pi/4),
                         ('03', 10.0, -2.5, math.pi/4), ('04', 0.0, -7.5, 0.0),
                         ('05', -15.0, -6.0, math.pi/4), ('06', 15.0, -6.0, math.pi/4)):
    box('标识底板', (px, py, .058), (2.30, 2.30, .014), 1, HULL, .004, rot)
    box('标识内框', (px, py, .068), (1.86, 1.86, .010), 0, EDGE, .003, rot)
    glyph('地面编号', num[0], (px-.34, py-.05, .080), .96, WHITE, .050, 1, rot)
    glyph('地面编号', num[1], (px+.34, py-.05, .080), .96, WHITE, .050, 1, rot)
# 白色人字通行导向（参考图：板块边缘成对箭头）
for px, py, rot in ((-6.0, 4.0, 0.0), (6.0, 4.0, 0.0), (-6.0, -3.5, math.pi),
                    (6.0, -3.5, math.pi), (0.0, 11.0, 0.0)):
    for s in (-1, 1):
        o = box('地面导向箭头', (px+s*.46, py, .062), (.86, .20, .012), 1, WHITE, .003, rot)
        o.rotation_euler.z = rot + s*.72
# 菱形警示标（黄）
for px, py in ((-13.0, 6.5), (13.0, 6.5), (-3.5, -12.6), (3.5, -12.6), (17.0, -8.0), (-17.0, -8.0)):
    box('菱形警示底板', (px, py, .058), (1.34, 1.34, .012), 1, AMBER, .003, math.pi/4)
    box('菱形警示内板', (px, py, .068), (1.02, 1.02, .010), 0, VOID, .003, math.pi/4)

pack('floor_grate_grid', '地面格栅与检修口', 'floor', coll='visual_only', visual_only=True)
GRATES = [(-9.0, 5.5, 0.0), (3.0, 4.0, 0.0), (-6.5, -7.0, math.pi/2),
          (11.0, -6.0, 0.0), (-13.5, 1.0, math.pi/2), (16.5, 4.0, 0.0)]
for px, py, rot in GRATES:
    box('格栅口框', (px, py, .066), (2.10, 1.42, .034), 0, VOID, .006, rot)
    box('格栅口压边', (px, py, .088), (2.22, 1.54, .016), 0, EDGE, .004, rot)
    for j in range(11):
        box('格栅叶片', (px-1.04+j*.208*math.cos(rot), py-1.04*math.sin(rot) if rot else py, .104),
            (.075, 1.24, .038), 0, STEEL, .005, rot) if rot == 0 else \
        box('格栅叶片', (px, py-1.04+j*.208, .104), (1.24, .075, .038), 0, STEEL, .005, 0)
    bolts(px, py, .096, .96, .62)

pack('floor_conduit_run', '地面线槽与检修盖板', 'floor', coll='visual_only', visual_only=True)
for xx in (-10.0, 10.0):
    box('地面纵向线槽', (xx, 2.5, .058), (.28, 24.0, .026), 0, EDGE, .005)
    for yy in range(-8, 15, 4):
        box('线槽检修盖板', (xx, yy, .066), (.38, .62, .020), 1, DARK, .004)
for yy in (-4.0, 8.0):
    box('地面横向线槽', (0.0, yy, .056), (38.0, .24, .022), 0, EDGE, .004)
    for xx in range(-18, 19, 6):
        box('线槽检修盖板', (xx, yy, .064), (.62, .34, .018), 1, DARK, .004)

pack('floor_service_pit', '地面设备坑与抬升平台', 'floor', coll='visual_only', visual_only=True)
PX, PY = 12.6, 3.2
box('抬升平台底板', (PX, PY, .010), (3.90, 2.90, .020), 0, VOID, .005)
box('抬升平台台面', (PX, PY, .185), (3.62, 2.62, .330), 1, DARK, .010)
box('平台黄黑边框', (PX, PY, .360), (3.90, 2.90, .020), 1, AMBER, .004)
for j in range(11):
    box('平台边框斜纹', (PX-1.70+j*.34, PY+1.30, .378), (.22, .11, .012), 0, VOID, .002, math.radians(40))
    box('平台边框斜纹', (PX-1.70+j*.34, PY-1.30, .378), (.22, .11, .012), 0, VOID, .002, math.radians(40))
box('平台内凹槽', (PX, PY, .356), (3.10, 2.10, .040), 0, EDGE, .008)
for xx in (-.75, .75):
    box('平台内设备格', (PX+xx, PY, .382), (1.30, 1.80, .028), 1, PANEL, .006)
box('平台标识牌', (PX, PY-1.60, .392), (1.60, .34, .028), 0, VOID, .005)
glyph('平台警示字模', '0', (PX-.30, PY-1.60, .405), .42, AMBER, .034, 1)
glyph('平台警示字模', '3', (PX+.30, PY-1.60, .405), .42, AMBER, .034, 1)

# ================================================================ 02 区域固定设施
def server_rack(tag, c, rot=0.0, hs=2.15, u_slots=14, side_light=True):
    """机柜：底墩 + 柜体 + 前门框 + U 位层 + LED 点阵 + 顶部理线 + 侧向灯柱。"""
    cx, cy, cz = c
    ca, sa = math.cos(rot), math.sin(rot)
    def P(u, v, z): return (cx+u*ca-v*sa, cy+u*sa+v*ca, cz+z)
    box(tag+'_底墩', P(0, .04, .07), (1.42, 1.10, .14), 0, VOID, .008, rot)
    box(tag+'_柜体', P(0, .02, 1.16), (1.38, 1.03, 2.06), 1, PANEL, .016, rot)
    for sx in (-1, 1):
        box(tag+'_侧板压条', P(sx*.70, .02, 1.16), (.05, 1.05, 2.02), 0, EDGE, .005, rot)
    box(tag+'_顶盖', P(0, .02, 2.22), (1.46, 1.11, .10), 0, DARK, .010, rot)
    box(tag+'_顶部理线槽', P(0, -.30, 2.32), (1.20, .44, .20), 0, VOID, .008, rot)
    for j in range(4):
        cyl(tag+'_顶部出线', P(-.48+j*.32, -.30, 2.42), P(-.48+j*.32, -.30, 2.72), .042, 0, DARK, 8)
    # 前门（朝向 +Y）
    box(tag+'_门框', P(0, .545, 1.14), (1.24, .045, 1.92), 0, VOID, .008, rot)
    box(tag+'_门内格网', P(0, .562, 1.14), (1.14, .020, 1.82), 0, DARK, .004, rot)
    for j in range(u_slots):
        z = .34+j*.132
        box(tag+'_U位层板', P(0, .574, z), (1.10, .016, .104), 1, HULL, .003, rot)
        for s in (-1, 1):
            box(tag+'_U位灯点', P(s*.42, .588, z+.030), (.05, .014, .030), 3, BLUE, .002, rot)
        if j % 3 == 0:
            box(tag+'_U位面板条', P(-.20, .588, z), (.52, .012, .052), 0, STEEL, .002, rot)
    box(tag+'_门锁', P(.50, .585, 1.14), (.10, .030, .26), 0, STEEL, .004, rot)
    for z in (.32, 1.14, 1.96):
        cyl(tag+'_门铰链', P(-.60, .575, z), P(-.60, .610, z), .028, 0, EDGE, 6)
    # 前门两侧竖向冷蓝灯条（参考图：机柜正面成对纵向蓝光带，是全场最强识别特征）
    for sx in (-1, 1):
        box(tag+'_门侧灯条槽', P(sx*.565, .588, 1.14), (.055, .018, 1.86), 0, VOID, .002, rot)
        box(tag+'_门侧冷蓝灯条', P(sx*.565, .600, 1.14), (.032, .012, 1.70), 3, BLUE, .002, rot)
    if side_light:
        box(tag+'_侧灯槽', P(.735, -.05, 1.30), (.055, .62, 2.30), 0, VOID, .006, rot)
        box(tag+'_侧向冷光灯柱', P(.760, -.05, 1.30), (.030, .52, 2.14), 3, BLUE, .004, rot)

def screen(name, c, rot, wide=True, glow=CYAN):
    x, y, z = c
    ca, sa = math.cos(rot), math.sin(rot)
    def P(u, v, w): return (x+u*ca-v*sa, y+u*sa+v*ca, z+w)
    box(name+'_底座', P(0, 0, .018), (.34, .26, .036), 0, VOID, .008, rot)
    cyl(name+'_立杆', P(0, 0, .036), P(0, 0, .30), .032, 0, DARK, 8)
    sw, sh = (.84, .48) if wide else (.38, .64)
    box(name+'_屏壳', P(0, -.10, .56), (sw, .055, sh), 0, VOID, .010, rot)
    box(name+'_屏框', P(0, -.072, .56), (sw-.05, .020, sh-.05), 0, DARK, .004, rot)
    box(name+'_发光面', P(0, -.058, .56), (sw-.11, .018, sh-.11), 3, glow, .003, rot)
    for r in range(6 if wide else 8):
        w = (sw-.22)*(1-.06*r) if wide else (sw-.16)
        box(name+'_界面条', P(0, -.044, .56+sh*.30-r*.062), (w, .012, .024), 3, BLUE, .001, rot)

def stool(name, c):
    x, y, z = c
    box(name+'_座面', (x, y, z+.62), (.42, .42, .07), 1, HULL, .014)
    box(name+'_座沿', (x, y, z+.585), (.48, .48, .05), 0, DARK, .008)
    cyl(name+'_气缸', (x, y, z+.20), (x, y, z+.585), .055, 0, STEEL, 10)
    for j in range(5):
        a = j*math.pi*2/5
        ex, ey = x+.30*math.cos(a), y+.30*math.sin(a)
        box(name+'_五星脚', ((x+ex)/2, (y+ey)/2, z+.085), (.34, .075, .06), 0, DARK, .006, a)
        cyl(name+'_滚轮', (ex, ey, z+.03), (ex, ey, z+.095), .042, 0, VOID, 8)
    cyl(name+'_脚踏圈', (x, y, z+.16), (x, y, z+.20), .27, 0, EDGE, 16)

# ---- 西侧机柜列（7 台，自由站立成列，面朝 +X；离墙 2.5m 保留冷通道）
pack('server_rack_row', '西侧机柜列', 'facilities')
for i, yy in enumerate((9.2, 7.65, 6.10, 4.55, 3.00, 1.45, -0.10)):
    server_rack('西列机柜%d' % (i+1), (-17.45, yy, 0.0), rot=-math.pi/2, side_light=(i % 2 == 0))
box('机柜列顶部汇流槽', (-17.45, 4.55, 2.62), (1.30, 11.6, .22), 0, EDGE, .010)
for yy in (-0.6, 3.0, 6.6, 10.2):
    box('汇流槽吊架', (-17.45, yy, 3.10), (.90, .10, .86), 0, DARK, .006)
box('机柜列地面走线槽', (-17.45, 4.55, .075), (1.05, 12.4, .13), 0, VOID, .008)
box('机柜列警示边界', (-16.06, 4.55, .048), (.10, 12.6, .016), 1, AMBER, .003)

# ---- 中部机柜组 + 移动推车
pack('rack_cluster_center', '中部机柜组与推车', 'facilities')
for i, (xx, yy, rt) in enumerate(((-13.6, -7.4, 0.0), (-12.1, -7.4, 0.0), (-10.6, -7.4, 0.0))):
    server_rack('中部机柜%d' % (i+1), (xx, yy, 0.0), rot=rt, hs=2.15, u_slots=12, side_light=(i == 1))
box('机柜组顶部理线架', (-12.1, -7.4, 2.40), (4.10, .70, .20), 0, EDGE, .008)
for j in range(6):
    cyl('理线架出线', (-13.9+j*.72, -7.72, 2.50), (-13.9+j*.72, -7.72, 2.86), .036, 0,
        [DARK, BLUE, RED, DARK, BLUE, AMBER][j], 8)
box('移动推车台面', (-8.9, -6.2, .62), (1.30, .78, .06), 1, PANEL, .010)
box('移动推车下层板', (-8.9, -6.2, .30), (1.22, .70, .05), 1, HULL, .008)
for j in range(2):
    box('推车立柱', (-8.9, -6.55+j*.66, .48), (.07, .07, .96), 0, DARK, .006)
    cyl('推车推把', (-9.60, -6.55+j*.66, 1.02), (-9.20, -6.55+j*.66, 1.02), .028, 0, EDGE, 8)
casters('推车脚轮', -8.9, -6.2, 0.0, .54, .30)
box('推车上机柜', (-9.10, -6.20, .93), (.66, .64, .56), 1, PANEL, .012)
for j in range(4):
    box('推车机柜灯点', (-8.77, -6.20, .70+j*.14), (.014, .40, .036), 3, BLUE, .002)

# ---- 西墙检修工作台（放在西墙无门段 Y∈[10,15]）
pack('workbench_west', '西墙检修工作台', 'facilities')
wbx = wp('west', 10.4, .50, 0.0)[0]
box('检修台台面', (wbx+.0, 12.5, .92), (.86, 4.30, .07), 1, MID, .010)
box('检修台前缘', (-18.60, 12.5, .875), (.06, 4.30, .10), 1, HULL, .008)
box('检修台背板', (-19.44, 12.5, 1.34), (.09, 4.30, .80), 0, VOID, .008)
for dy in (-1.85, 0.0, 1.85):
    box('检修台支腿', (wbx-.28, 12.5+dy, .44), (.09, .11, .88), 0, DARK, .008)
box('检修台下横撑', (wbx-.10, 12.5, .18), (.62, 4.10, .08), 0, EDGE, .005)
for dy in (-1.55, 0.0, 1.55):
    box('检修台背挂板', (-19.36, 12.5+dy, 1.68), (.05, 1.30, .62), 1, HULL, .003)
    for j in range(4):
        box('背挂工具', (-19.32, 12.5+dy-.44+j*.30, 1.68), (.04, .09, .34), 0, STEEL, .003)
box('台上示波器', (-18.85, 11.30, 1.16), (.66, .60, .40), 0, HULL, .010)
box('示波器显示面', (-19.20, 11.30, 1.24), (.03, .46, .24), 3, CYAN, .003)
box('台上电源箱', (-18.90, 12.30, 1.10), (.52, .48, .28), 1, PANEL, .008)
for j in range(3):
    box('电源箱指示', (-18.63, 12.30, .99+j*.09), (.014, .30, .030), 3, BLUE, .002)
box('台上料盒', (-18.95, 13.55, 1.06), (.52, .50, .20), 1, TAN, .006)
box('台上零件盘', (-18.90, 14.25, 1.02), (.56, .40, .12), 0, EDGE, .006)
screen('台上检修屏', (-18.72, 13.00, .955), math.radians(90), False, HI2)

# ---- 东墙 L 形长工作台（东墙无门段 + 北墙东北角）
pack('workbench_l_east', '东墙L形工作台', 'facilities')
box('东台台面', (18.95, 12.35, .93), (.98, 4.60, .07), 1, MID, .010)
box('东台前缘', (18.44, 12.35, .885), (.06, 4.60, .10), 1, HULL, .008)
box('东台背板', (19.42, 12.35, 1.36), (.09, 4.60, .82), 0, VOID, .008)
for dy in (-2.00, 0.0, 2.00):
    box('东台支腿', (18.70, 12.35+dy, .44), (.09, .11, .88), 0, DARK, .008)
box('东台下横撑', (18.80, 12.35, .18), (.62, 4.40, .08), 0, EDGE, .005)
for dy in (-1.75, -0.60, 0.60, 1.75):
    box('东台台下柜', (18.95, 12.35+dy, .40), (.80, 1.00, .72), 1, PANEL, .012)
    for j in range(2):
        box('东台柜门缝', (18.54, 12.35+dy, .40), (.02, 1.00, .03), 0, VOID, .002)
        cyl('东台柜把手', (18.52, 12.35+dy-.34+j*.68, .40), (18.47, 12.35+dy-.34+j*.68, .40),
            .020, 0, STEEL, 6)
box('北台台面', (17.30, 14.10, .93), (4.20, .98, .07), 1, MID, .010)
box('北台前缘', (17.30, 13.59, .885), (4.20, .06, .10), 1, HULL, .008)
box('北台背板', (17.30, 14.57, 1.36), (4.20, .09, .82), 0, VOID, .008)
for dx in (-1.80, 0.0, 1.80):
    box('北台支腿', (17.30+dx, 14.30, .44), (.11, .09, .88), 0, DARK, .008)
box('工作台转角连板', (18.95, 14.10, .93), (.98, .98, .07), 1, MID, .010)
for i, (sx, sy) in enumerate([(18.55, 13.10), (18.55, 11.20), (17.30, 14.05), (15.60, 14.05)]):
    screen('台面显示%d' % (i+1), (sx, sy, .965), math.radians(-90) if sx > 17 else math.pi, True, HI2)
box('台面键盘', (18.75, 12.00, .965), (.20, .46, .026), 0, DARK, .004)
box('台面工具盘', (18.60, 12.90, .975), (.46, .42, .045), 0, EDGE, .005)
for j in range(5):
    box('台面工具件', (18.60, 12.72+j*.12, 1.010), (.32, .06, .075), 0, STEEL, .004)
box('台上分格料盒', (18.95, 13.60, 1.02), (.74, .52, .22), 1, PANEL, .006)
for j in range(3):
    box('料盒格挡', (18.95, 13.42+j*.18, 1.06), (.70, .02, .16), 0, VOID, .002)
box('台上仪器', (18.90, 10.30, 1.16), (.72, .62, .44), 0, HULL, .010)
box('仪器屏面', (18.52, 10.30, 1.24), (.03, .48, .26), 3, CYAN, .003)
for z in (4.30, 5.35):
    box('东墙工具板', (19.44, 14.20-z, z-.95), (.07, 3.40, .05), 0, VOID, .006)
for z in (3.40, 4.20, 5.00):
    box('东墙工具挂钩轨', (19.38, 12.35, z+.62), (.05, 3.30, .09), 0, EDGE, .004)
    for j in range(6):
        box('挂钩', (19.33, 11.05+j*.52, z+.58), (.04, .05, .20), 0, STEEL, .003)

# ---- 壁挂大屏组（挂在东墙与北墙高处；z≥3.3 不受门位净空约束）
pack('wall_screen_bank', '壁挂大屏组', 'facilities')
for i, (side, uu) in enumerate([('east', 9.6), ('east', 11.4), ('east', 13.2)]):
    wbox(side, '大屏支架', ru(side, uu), .30, 4.30, .40, .12, .40, 0, VOID, .006)
    wbox(side, '大屏外框', ru(side, uu), .40, 4.30, 2.10, .08, 1.30, 0, VOID, .010)
    wbox(side, '大屏发光面', ru(side, uu), .455, 4.30, 1.92, .024, 1.12, 3, CYAN, .003)
    for r in range(4):
        wbox(side, '大屏数据条', ru(side, uu)-.20, .470, 4.72-r*.26, 1.00-.14*r, .010, .050, 3, HI2, .001)
for i, uu in enumerate([16.6, 18.2]):
    wbox('north', '北墙屏支架', ru('north', uu), .30, 4.10, .38, .12, .38, 0, VOID, .006)
    wbox('north', '北墙屏外框', ru('north', uu), .40, 4.10, 1.80, .08, 1.15, 0, VOID, .010)
    wbox('north', '北墙屏发光面', ru('north', uu), .455, 4.10, 1.64, .024, .99, 3, HI2, .003)
    for r in range(4):
        wbox('north', '北墙屏数据条', ru('north', uu)-.16, .470, 4.48-r*.23, .86-.12*r, .010, .044, 3, BLUE, .001)

# ---- 红色抽屉工具车 ×2
pack('tool_chest_red_pair', '红色抽屉工具车', 'facilities')
for i, (cx, cy, rot) in enumerate(((-5.10, -5.40, 0.0), (8.60, -1.20, math.pi/2))):
    ca, sa = math.cos(rot), math.sin(rot)
    def P(u, v, z, _cx=cx, _cy=cy, _ca=ca, _sa=sa): return (_cx+u*_ca-v*_sa, _cy+u*_sa+v*_ca, z)
    box('工具车箱体', P(0, 0, .50), (1.02, .62, .86), 1, RED, .014, rot)
    box('工具车顶盘', P(0, 0, .955), (1.10, .70, .06), 0, DARK, .008, rot)
    box('工具车顶围边', P(0, .34, .995), (1.06, .06, .09), 0, EDGE, .005, rot)
    for j in range(5):
        z = .21+j*.175
        box('抽屉面板', P(0, .315, z), (.90, .022, .150), 1, RUST if j % 2 else RED, .004, rot)
        box('抽屉拉手', P(0, .335, z), (.44, .028, .030), 0, STEEL, .004, rot)
        box('抽屉锁孔', P(.36, .333, z), (.07, .022, .034), 0, VOID, .002, rot)
    box('箱体侧提手', P(-.53, 0, .92), (.05, .34, .07), 0, STEEL, .005, rot)
    casters('工具车脚轮', cx, cy, 0.0, .40, .24)

# ---- 中央作业台
pack('center_worktable', '中央作业台', 'facilities')
CX_, CY_ = -3.6, -3.2
box('作业台台面', (CX_, CY_, .93), (4.30, 1.66, .08), 1, MID, .012)
box('作业台前缘', (CX_, CY_+.86, .885), (4.30, .06, .11), 1, HULL, .008)
for dx in (-2.06, 2.06):
    box('作业台端立板', (CX_+dx, CY_, .45), (.07, 1.54, .90), 0, DARK, .008)
box('作业台横撑', (CX_, CY_, .30), (4.10, .10, .10), 0, EDGE, .005)
box('作业台背挡板', (CX_, CY_-.80, .44), (4.30, .06, .56), 0, VOID, .006)
box('作业台下层板', (CX_, CY_-.05, .20), (4.06, 1.40, .05), 1, HULL, .006)
box('作业台走线槽', (CX_, CY_+.55, .84), (3.90, .18, .10), 0, EDGE, .005)
box('台上测试机架', (CX_-1.30, CY_-.22, 1.40), (1.30, 1.00, .86), 1, PANEL, .014)
for j in range(6):
    box('机架面板条', (CX_-1.30, CY_+.30, 1.10+j*.15), (1.16, .022, .10), 1, HULL, .003)
    box('机架灯点', (CX_-.78, CY_+.315, 1.10+j*.15), (.05, .014, .04), 3, BLUE, .002)
for j in range(3):
    cyl('机架出线', (CX_-1.60+j*.30, CY_-.72, .98), (CX_-1.60+j*.30, CY_-.72, 1.62), .040, 0,
        [DARK, BLUE, RED][j], 8)
box('台上数据终端', (CX_+.20, CY_-.15, 1.13), (.62, .46, .34), 0, HULL, .010)
box('终端屏面', (CX_+.20, CY_+.10, 1.18), (.48, .024, .22), 3, CYAN, .003)
box('台上平板支架', (CX_+1.15, CY_-.10, .99), (.30, .24, .05), 0, VOID, .006)
box('台上平板', (CX_+1.15, CY_-.10, 1.13), (.44, .30, .028), 0, VOID, .008, math.radians(-28))
box('平板发光面', (CX_+1.15, CY_-.06, 1.155), (.38, .24, .016), 3, HI2, .002, math.radians(-28))
box('台上零件盒', (CX_+.75, CY_+.50, 1.02), (.46, .34, .18), 1, TAN, .006)
box('台上料盘', (CX_-0.10, CY_+.52, 1.00), (.58, .40, .14), 0, EDGE, .006)
for j in range(4):
    box('盘内零件', (CX_-.34+j*.20, CY_+.52, 1.075), (.13, .13, .05), 0, STEEL, .003)
box('台上资料夹', (CX_+1.72, CY_+.42, 1.01), (.50, .34, .13), 1, [RED, BLUE][0], .004)
box('台面线缆束', (CX_-0.55, CY_+.62, .995), (1.10, .11, .06), 0, DARK, .005)
screen('台面侧显', (CX_+1.95, CY_-.30, .975), math.radians(-120), False, HI2)
casters('作业台脚轮', CX_, CY_, 0.0, 1.90, .62, .05)

# ---- 货箱堆场
pack('crate_stack_field', '货箱与周转箱堆场', 'facilities')
CRATES = [(-8.30, 1.20, 3, 0.0), (-6.40, 1.20, 2, 0.0), (-8.30, -1.10, 4, math.pi/2),
          (9.40, -7.60, 3, 0.0), (11.10, -7.60, 4, 0.0), (1.60, -8.20, 2, math.pi/2),
          (-15.40, -4.20, 3, 0.0), (16.80, -0.60, 2, math.pi/2), (-11.60, 11.60, 3, 0.0)]
for gi, (gx, gy, rows, rot) in enumerate(CRATES):
    for r in range(rows):
        w_ = .92 if r % 2 == 0 else .74
        cell = TAN if (gi+r) % 2 == 0 else CARD
        box('周转箱体', (gx, gy, .10+r*.62), (w_, .80 if r % 2 == 0 else .66, .58), 1, cell, .008, rot)
        box('周转箱盖缝', (gx, gy, .395+r*.62), (w_+.02, (.80 if r % 2 == 0 else .66)+.02, .035), 0, VOID, .003, rot)
        box('周转箱封条', (gx, gy, .30+r*.62), (w_-.14, .05, .10), 1, HI2, .002, rot)
        for sx in (-1, 1):
            box('箱体提手孔', (gx+sx*(w_/2-.06), gy, .30+r*.62), (.03, .22, .12), 0, VOID, .002, rot)
    box('堆场托盘', (gx, gy, .045), (1.12, 1.00, .09), 0, EDGE, .006, rot)
# 敞开箱与散件
box('敞口箱体', (5.10, -8.00, .30), (1.24, .92, .60), 1, CARD, .010)
box('敞口箱内衬', (5.10, -8.00, .585), (1.12, .80, .05), 0, VOID, .003)
box('敞口箱内设备', (5.10, -8.00, .72), (.70, .52, .26), 0, HULL, .008)
for j in range(3):
    cyl('散落线缆', (4.30+j*.30, -8.90, .06), (4.30+j*.30, -8.90, .10), .045, 0,
        [DARK, BLUE, RED][j], 8)
box('散落纸页', (2.90, -8.70, .055), (.42, .30, .014), 1, WHITE, .002, math.radians(18))
box('散落纸页', (2.55, -8.35, .060), (.40, .28, .014), 1, HI2, .002, math.radians(-26))

# ---- 北墙重型货架（北墙西北角无门段 X∈[-20,-15]）
pack('shelving_heavy_north', '北墙重型货架', 'facilities')
SHX, SHY = -17.30, 13.60
for dx in (-1.90, 0.0, 1.90):
    box('货架立柱', (SHX+dx, SHY, 1.60), (.09, .80, 3.20), 0, DARK, .008)
for z in (.14, 1.10, 2.06, 3.02):
    box('货架层板', (SHX, SHY, z), (4.00, .82, .06), 1, PANEL, .008)
    box('层板挡边', (SHX, SHY-.44, z+.06), (4.00, .06, .10), 0, EDGE, .004)
for k, z in enumerate((1.24, 2.20)):
    for j in range(4):
        xx = SHX-1.55+j*1.04
        box('架上周转箱', (xx, SHY, z+.28), (.92, .70, .52), 1, TAN if (j+k) % 2 else CARD, .008)
        box('箱体封条', (xx, SHY-.36, z+.28), (.86, .04, .09), 1, HI2, .002)
for j in range(3):
    box('底层料盒', (SHX-1.30+j*1.30, SHY, .43), (1.10, .70, .50), 1, PANEL, .008)
    box('料盒标签', (SHX-1.30+j*1.30, SHY-.36, .50), (.62, .03, .18), 3, BLUEB, .002)
box('货架端部标识牌', (SHX+2.05, SHY, 2.60), (.10, .62, .40), 0, VOID, .006)
box('标识牌发光面', (SHX+2.09, SHY, 2.60), (.03, .48, .26), 3, AMBER, .003)

# ---- 多屉零件柜（南墙西段无门区）
pack('parts_drawer_cabinet', '多屉零件柜', 'facilities')
for ci, (px, py) in enumerate(((-17.75, -9.35), (-16.25, -9.35))):
    box('零件柜柜体', (px, py, 1.02), (1.30, .72, 2.04), 1, PANEL, .014)
    box('零件柜顶板', (px, py, 2.07), (1.38, .78, .06), 0, EDGE, .006)
    box('零件柜底板', (px, py, .03), (1.38, .78, .06), 0, VOID, .006)
    for r in range(6):
        for c in range(3):
            dx = -.42+c*.42; z = .22+r*.305
            box('抽屉面板', (px+dx, py-.365, z), (.40, .022, .255), 1, HULL if (r+c) % 2 else PANEL, .004)
            box('抽屉拉手', (px+dx, py-.383, z), (.22, .022, .030), 0, STEEL, .003)
            box('抽屉标签', (px+dx, py-.382, z-.085), (.19, .014, .05), 1, HI2, .002)
    box('柜顶收纳筐', (px, py, 2.24), (1.10, .62, .28), 0, STEEL, .005)
    box('筐内零件', (px, py, 2.36), (.92, .46, .12), 1, RUST, .003)
box('零件柜旁料架', (-15.20, -9.30, .90), (.06, .72, 1.80), 0, DARK, .006)
for z in (.98, 1.80):
    box('料架层板', (-15.55, -9.30, z), (.76, .72, .05), 1, PANEL, .006)

# ---- 落地电缆盘 + 壁挂线圈
pack('cable_reel_floor', '落地电缆盘与线圈', 'facilities')
for i, (rx, ry, rot) in enumerate(((-2.10, -11.30, math.radians(24)), (0.30, -12.20, math.radians(-44)))):
    box('电缆盘底架', (rx, ry, .07), (1.10, .60, .14), 0, VOID, .008, rot)
    cyl('电缆盘法兰A', (rx-.34, ry, .45), (rx-.26, ry, .45), .50, 1, RUST, 20)
    cyl('电缆盘法兰B', (rx+.34, ry, .45), (rx+.26, ry, .45), .50, 1, RUST, 20)
    cyl('电缆盘芯筒', (rx-.30, ry, .45), (rx+.30, ry, .45), .30, 0, CARD, 18)
    for j in range(3):
        cyl('盘绕电缆', (rx-.28, ry, .18+j*.28), (rx+.28, ry, .18+j*.28), .41, 0,
            [DARK, BLUE, VOID][j], 20)
    casters('电缆盘脚轮', rx, ry, 0.0, .36, .22, .05)
for i, rx in enumerate((-1.30, 0.90)):
    o = box('地面蜿蜒电缆', (rx, -9.60, .058), (2.30, .12, .05), 0, DARK, .006)
    o.rotation_euler.z = math.radians(12 - 30*i)

pack('cable_coil_wall', '壁挂电缆线圈', 'facilities')
for i, uu in enumerate((6.2, 7.4, 8.6, 10.4, 11.6)):
    wbox('east', '线圈挂架', ru('east', uu), .30, 3.85, .12, .22, .22, 0, VOID, .005)
    wcyl('east', '壁挂线圈', ru('east', uu)-.15, .34, 3.85, ru('east', uu)+.15, .34, 3.85, .34, 1,
         [DARK, RED, BLUE, DARK, AMBER][i], 22)
    wcyl('east', '线圈芯', ru('east', uu)-.16, .34, 3.85, ru('east', uu)+.16, .34, 3.85, .16, 0, VOID, 16)

# ---- 白色花箱绿植
pack('planter_white_pair', '白色花箱绿植', 'facilities')
PLANTS = [(-15.80, 12.20, 1.00), (16.30, 12.30, .95), (-4.10, -12.80, .90),
          (4.20, -11.00, .95), (-12.30, 8.60, .85), (12.30, -9.30, .90)]
for i, (px, py, sc) in enumerate(PLANTS):
    box('花箱箱体', (px, py, .30*sc), (.78*sc, .78*sc, .60*sc), 1, WHITE, .014)
    box('花箱口沿', (px, py, .61*sc), (.84*sc, .84*sc, .07*sc), 0, HI2, .004)
    box('花箱底座', (px, py, .035*sc), (.66*sc, .66*sc, .07*sc), 0, VOID, .006)
    box('种植基质', (px, py, .645*sc), (.68*sc, .68*sc, .06*sc), 1, CARD, .002)
    cyl('植株主干', (px, py, .66*sc), (px, py, 1.16*sc), .050*sc, 0, CARD, 8)
    for j in range(10):
        a = j*math.pi*2/10+i*.31; r = .36*sc
        box('植株叶片', (px+r*math.cos(a), py+r*math.sin(a), (1.18+j*.035)*sc),
            (.36*sc, .13*sc, .18*sc), 1, GREEN if j % 2 else TEAL, .003, a)

# ---- 东北设备机架
pack('equipment_rack_ne', '东北设备机架', 'facilities')
for i, xx in enumerate((14.30, 15.75)):
    box('设备机架底墩', (xx, 9.40, .08), (1.28, 1.02, .16), 0, VOID, .008)
    box('设备机架柜体', (xx, 9.40, 1.24), (1.22, .96, 2.16), 1, PANEL, .016)
    box('机架前门框', (xx, 9.40-.50, 1.24), (1.10, .05, 2.00), 0, VOID, .008)
    for j in range(9):
        box('机架单元面板', (xx, 8.88, .38+j*.19), (1.02, .03, .155), 1, HULL, .004)
        box('机架单元指示灯', (xx-.40, 8.86, .38+j*.19), (.06, .014, .05), 3, BLUE if j % 2 else ICE, .002)
    box('机架顶盖', (xx, 9.40, 2.36), (1.30, 1.04, .09), 0, DARK, .008)
    box('机架侧灯槽', (xx+.63, 9.40, 1.30), (.055, .70, 2.20), 0, VOID, .006)
    box('机架侧冷光灯柱', (xx+.665, 9.40, 1.30), (.030, .58, 2.06), 3, BLUE, .004)
box('机架顶部走线桥', (15.02, 9.40, 2.62), (2.60, .70, .20), 0, EDGE, .008)
for j in range(5):
    cyl('机架出线', (14.00+j*.52, 9.08, 2.72), (14.00+j*.52, 9.08, 3.05), .036, 0,
        [DARK, BLUE, AMBER, DARK, RED][j], 8)

# ---- 西南附区作业台
pack('bench_annex_southwest', '西南附区作业台', 'facilities')
AX, AY = -16.15, -7.80
box('附区台面', (AX, AY, .93), (3.80, .92, .07), 1, MID, .010)
box('附区台前缘', (AX, AY+.49, .885), (3.80, .06, .10), 1, HULL, .008)
box('附区台背板', (AX, AY-.50, 1.32), (3.80, .09, .76), 0, VOID, .008)
for dx in (-1.74, 0.0, 1.74):
    box('附区台支腿', (AX+dx, AY-.30, .44), (.10, .09, .88), 0, DARK, .008)
box('附区台下横撑', (AX, AY, .20), (3.60, .62, .08), 0, EDGE, .005)
for dx in (-1.10, 1.10):
    box('附区台下柜', (AX+dx, AY, .40), (.90, .80, .72), 1, PANEL, .012)
    for j in range(2):
        box('柜门缝', (AX+dx, AY+.41, .40), (.90, .02, .03), 0, VOID, .002)
        cyl('柜把手', (AX+dx-.30+j*.60, AY+.43, .40), (AX+dx-.30+j*.60, AY+.43, .40), .020, 0, STEEL, 6)
screen('附区显示屏', (AX-1.05, AY-.16, .965), 0.0, True, HI2)
screen('附区副屏', (AX+.30, AY-.16, .965), math.radians(22), False, CYAN)
box('附区台上料盒', (AX+1.45, AY-.05, 1.02), (.60, .60, .18), 1, TAN, .006)
box('附区台仪器', (AX+2.75, AY-.02, 1.12), (.56, .58, .38), 0, HULL, .010)
box('附区台仪器屏', (AX+2.75, AY-.30, 1.18), (.40, .03, .20), 3, CYAN, .003)
for j in range(3):
    box('附区台上工具', (AX-1.85+j*.42, AY+.28, 1.005), (.34, .12, .075), 0, STEEL, .004)

# ---- 黄色工具推车 + 圆凳
pack('tool_cart_yellow', '黄色工具推车与圆凳', 'facilities')
for i, (cx, cy, rot) in enumerate(((-14.90, 8.70, 0.0), (-13.60, -2.20, math.radians(90)))):
    ca, sa = math.cos(rot), math.sin(rot)
    def P(u, v, z, _cx=cx, _cy=cy, _ca=ca, _sa=sa): return (_cx+u*_ca-v*_sa, _cy+u*_sa+v*_ca, z)
    for z in (.30, .82, 1.34):
        box('推车层板', P(0, 0, z), (1.20, .72, .055), 1, AMBER, .008, rot)
        box('层板防滑条', P(0, .36, z+.04), (1.14, .05, .030), 0, VOID, .003, rot)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box('推车立柱', P(sx*.55, sy*.32, .82), (.065, .065, 1.10), 0, AMBER, .005, rot)
    box('推车推把', P(-.68, 0, 1.42), (.07, .76, .07), 0, AMBER, .005, rot)
    box('推车底层物料', P(.10, 0, .40), (.90, .60, .14), 1, PANEL, .006, rot)
    box('推车中层料盒', P(-.10, 0, .94), (.86, .60, .18), 1, TAN, .006, rot)
    casters('推车脚轮', cx, cy, 0.0, .48, .28, .05)
for i, (sx, sy) in enumerate(((-11.60, -5.60), (-6.20, -6.80), (17.30, 11.10), (1.20, -5.30))):
    stool('车间圆凳%d' % (i+1), (sx, sy, 0.0))

# ---- 墙面竖向冷光灯柱 + 墙顶走管收口（挂在墙上，z≥3.3 ⇒ 不受门位净空约束）
pack('wall_light_pylon', '墙面竖向冷光灯柱', 'facilities')
PYLONS = [('north', -17.5), ('north', -6.0), ('north', 6.0), ('north', 15.0),
          ('west', -5.0), ('west', 7.5), ('east', -5.0), ('east', 7.5),
          ('tab_w', 0.0), ('south_w', -12.5), ('south_e', 12.5)]
for side, uu in PYLONS:
    wbox(side, '灯柱底座', ru(side, uu), .30, 5.30, .34, .20, 4.20, 0, VOID, .010)
    wbox(side, '灯柱冷光条', ru(side, uu), .42, 5.30, .15, .07, 3.95, 3, BLUE, .004)
    wbox(side, '灯柱端头', ru(side, uu), .40, 7.62, .30, .12, .22, 0, EDGE, .006)
    wbox(side, '灯柱端头', ru(side, uu), .40, 3.18, .30, .12, .22, 0, EDGE, .006)

pack('wall_service_run', '墙面管道与线束', 'facilities')
for side, zs in (('north', (8.42, 8.72)), ('west', (8.42, 8.72)), ('east', (8.42, 8.72))):
    span = {'north': 39.0, 'west': 24.0, 'east': 24.0}[side]
    for k, z in enumerate(zs):
        wcyl(side, '墙面明装管', -span/2+1.2, .40, z, span/2-1.2, .40, z, .080-k*.018, 0, STEEL, 10)
        for j in range(int((span-3.0)//3.2)):
            uu = -span/2+2.0+j*3.2
            wcyl(side, '管道法兰', uu-.07, .40, z, uu+.07, .40, z, .108-k*.018, 0, EDGE, 10)
            wbox(side, '管道吊架', uu, .52, z, .10, .34, .10, 0, EDGE, .004)
    wbox(side, '线束槽', 0.0, .34, 9.42, span-1.6, .22, .20, 0, DARK, .008)
    for j in range(int((span-3.0)//4.0)):
        wbox(side, '线束固定卡', -span/2+2.2+j*4.0, .47, 9.42, .13, .07, .28, 0, STEEL, .004)
for side, uu in (('north', -13.0), ('north', 13.0), ('west', 5.0), ('east', 5.0)):
    wcyl(side, '墙面立管', ru(side, uu), .38, 3.05, ru(side, uu), .38, 9.60, .085, 0, STEEL, 10)
    for z in (4.40, 6.30, 8.20):
        wbox(side, '立管卡箍', ru(side, uu), .44, z, .22, .14, .12, 0, EDGE, .004)

pack('console_tripod', '落地仪器三脚架', 'facilities')
for i, (cx, cy, rot) in enumerate(((-9.40, 4.30, math.radians(200)), (7.40, 6.90, math.radians(-30)))):
    ca, sa = math.cos(rot), math.sin(rot)
    for j in range(3):
        a = rot + j*math.pi*2/3
        ex, ey = cx+.72*math.cos(a), cy+.72*math.sin(a)
        cyl('三脚架支腿', (cx, cy, .80), (ex, ey, .04), .042, 0, EDGE, 8)
        cyl('三脚架脚垫', (ex, ey, .02), (ex, ey, .07), .062, 0, VOID, 8)
    cyl('三脚架中柱', (cx, cy, .30), (cx, cy, .86), .048, 0, STEEL, 10)
    box('仪器机身', (cx, cy, 1.02), (.56, .40, .34), 1, PANEL, .010)
    box('仪器面板', (cx+.29*ca, cy+.29*sa, 1.02), (.02, .32, .26), 3, CYAN, .003)
    box('仪器提手', (cx, cy, 1.24), (.30, .10, .06), 0, EDGE, .004)

# ================================================================ 03 环境支持
for iy in range(-3, 3):
    pack('ceiling_deck_%d' % iy, '吊顶结构_%d' % iy, 'support', cut=True)
    for ix in range(-4, 4):
        x, y = ix*GRID+GRID/2, iy*GRID+GRID/2
        if not (inside(x-2.49, y-2.49) and inside(x+2.49, y-2.49)
                and inside(x-2.49, y+2.49) and inside(x+2.49, y+2.49)):
            continue
        box('吊顶承重板', (x, y, WALL_H-.20), (GRID, GRID, .34), 1, DARK, 0)
        box('吊顶板缝压条', (x+(-1.70 if ix % 2 else 1.70), y, WALL_H-.40), (1.50, .09, .045), 0, EDGE, .004)
        box('吊顶检修吊点', (x-(-1.70 if ix % 2 else 1.70), y, WALL_H-.44), (.16, .16, .16), 0, STEEL, .004)

pack('ceiling_ring_beam', '吊顶周圈圈梁', 'support', cut=True)
BEAM_SEGS = [((0, HY-.35), (W, .70)), ((0, -10+.35), (W, .70)), ((HX-.35, 2.5), (.70, 25.7)),
             ((-HX+.35, 2.5), (.70, 25.7)), ((0, -HY+.35), (10.7, .70)),
             ((-5+.35, -12.5), (.70, 5.70)), ((5-.35, -12.5), (.70, 5.70))]
for (px, py), (dx, dy) in BEAM_SEGS:
    box('吊顶圈梁', (px, py, WALL_H-.45), (dx, dy, .60), 0, EDGE, .015)

pack('ceiling_service_cable_tray', '顶部电缆桥架与线缆', 'support')
for x in (-6.4, 6.4):
    box('纵向电缆桥架槽', (x, 2.5, 10.45), (.50, 23.0, .19), 0, EDGE, .008)
    for dy in (-.22, .22):
        box('桥架侧边立板', (x+dy, 2.5, 10.58), (.045, 23.0, .28), 0, DARK, .003)
    for yy in range(-8, 15, 3):
        box('桥架吊杆', (x, yy, 11.05), (.08, .08, 1.00), 0, STEEL, .003)
    for j in range(5):
        cyl('桥架内线缆', (x-.16+j*.08, -9.0, 10.50), (x-.16+j*.08, 14.0, 10.50), .036, 0,
            [DARK, BLUE, RED, AMBER, DARK][j], 8)
box('横向电缆桥架', (0.0, 10.60, 10.28), (36.0, .46, .17), 0, EDGE, .008)
for xx in range(-17, 18, 4):
    box('横向桥架吊杆', (xx, 10.60, 10.88), (.08, .08, 1.00), 0, STEEL, .003)
box('竖向跨接桥架', (-13.0, -3.0, 10.36), (.44, 18.0, .16), 0, EDGE, .008)

pack('ceiling_service_pipe_run', '顶部管道与法兰', 'support')
for x, r in ((-11.6, .19), (-9.9, .13), (11.6, .16)):
    cyl('顶部主管', (x, -9.0, 10.10), (x, 14.0, 10.10), r, 0, STEEL, 14)
    for yy in range(-8, 15, 3):
        cyl('管道法兰', (x-.07, yy, 10.10), (x+.07, yy, 10.10), r+.048, 0, EDGE, 14)
    for yy in range(-7, 14, 5):
        box('管道吊架', (x, yy, 10.62), (r*2+.20, .10, .95), 0, EDGE, .004)
        cyl('管道吊杆', (x, yy, 10.10+r), (x, yy, 11.00), .030, 0, STEEL, 6)

pack('ceiling_service_duct', '顶部通风管与风口', 'support')
box('主通风管', (3.6, 1.5, 10.78), (1.20, 24.0, .64), 0, PANEL, .020)
for yy in range(-8, 15, 3):
    box('风管法兰环', (3.6, yy, 10.78), (1.32, .10, .76), 0, EDGE, .006)
for yy in (-6, 1, 8):
    box('风管风口框', (3.6, yy, 10.44), (.78, .94, .08), 0, DARK, .005)
    for j in range(7):
        box('风口叶片', (3.6, yy-.36+j*.12, 10.40), (.70, .048, .035), 0, EDGE, .003, math.radians(24))
for yy in (-7, 0, 7, 12):
    for sx in (-1, 1):
        cyl('风管吊架', (3.6+sx*.68, yy, 10.78), (3.6+sx*.68, yy, 11.24), .034, 0, STEEL, 6)

pack('ceiling_lighting', '顶部灯具', 'support')
for yy in (-6.5, -0.5, 5.5, 11.5):
    for sx in (-1, 1):
        box('灯具轨道', (sx*10.20, yy, 10.84), (17.60, .14, .10), 0, DARK, .004)
    for xx in (-16, -11, -6, 6, 11, 16):
        box('灯具吊座', (xx, yy, 10.74), (.20, .20, .22), 0, VOID, .005)
        box('灯具外壳', (xx, yy, 10.56), (1.45, .36, .18), 0, PANEL, .008)
        box('灯具发光面', (xx, yy, 10.45), (1.21, .26, .030), 3, HI2, .003)

pack('wall_top_service', '墙顶管线收口', 'support')
for side, ln in (('north', 39.0), ('west', 24.0), ('east', 24.0), ('south_w', 14.0),
                 ('south_e', 14.0), ('tab_s', 9.0), ('tab_w', 4.0), ('tab_e', 4.0)):
    wbox(side, '墙顶服务槽', 0.0, .40, WALL_H-.35, ln-.6, .20, .70, 0, EDGE, .010)
    for j in range(int((ln-1.4)//2.4)):
        wbox(side, '服务槽卡箍', -ln/2+.9+j*2.4, .50, WALL_H-.35, .14, .12, .80, 0, STEEL, .005)

pack('corner_guard', '转角护柱', 'support')
for gx, gy, a in ((-19.55, 14.55, 0.0), (19.55, 14.55, 1.0), (19.55, -9.55, 2.0),
                  (-19.55, -9.55, 3.0), (4.55, -14.55, 2.0), (-4.55, -14.55, 3.0)):
    box('转角护柱', (gx, gy, 1.10), (.32, .32, 2.20), 1, PANEL, .010)
    for z in (.35, 1.10, 1.85):
        box('护柱反光箍', (gx, gy, z), (.36, .36, .10), 0, AMBER, .003)
    box('护柱底座', (gx, gy, .06), (.48, .48, .12), 0, VOID, .006)

# ================================================================ QA
bpy.context.view_layer.update()
wb = json.loads(WHITEBOX.read_text(encoding='utf-8'))

def bounds(objects):
    pts = [o.matrix_world@Vector(v) for o in objects for v in o.bound_box]
    return [[round(min(p[i] for p in pts), 5) for i in range(3)],
            [round(max(p[i] for p in pts), 5) for i in range(3)]]

# 轮廓面积（鞋带公式）
POLY = [(-HX, HY), (HX, HY), (HX, -10.0), (5.0, -10.0), (5.0, -HY), (-5.0, -HY), (-5.0, -10.0), (-HX, -10.0)]
_area = 0.0
for i in range(len(POLY)):
    x1, y1 = POLY[i]; x2, y2 = POLY[(i+1) % len(POLY)]
    _area += x1*y2 - x2*y1
FLOOR_AREA = abs(_area)/2.0

# 墙件包原点必须落在轮廓外墙带上。
# 🔴 office 组件包的 origin = **整樘 bbox 的 x/y 中心 + z 底**（非结构墙中心面）：
#    整樘含朝房内前凸的装饰 ⇒ origin 相对结构边界内缩 ≈0.1675m（实测 north/south/east/west 一致，
#    门洞件因门洞掏空为 0.1575）。因此判据容差取 0.45（仍能抓住「浮到房间中间」的粗错）。
WALL_BAND_TOL = 0.45
def on_outline(px, py):
    n = len(POLY)
    for i in range(n):
        x1, y1 = POLY[i]; x2, y2 = POLY[(i+1) % n]
        if abs(y1-y2) < EPS and abs(py-y1) < WALL_BAND_TOL and min(x1, x2)-.02 <= px <= max(x1, x2)+.02: return True
        if abs(x1-x2) < EPS and abs(px-x1) < WALL_BAND_TOL and min(y1, y2)-.02 <= py <= max(y1, y2)+.02: return True
    return False

walls_off_outline = [w['side']+':'+str(w['u']) for w in wall_instances
                     if not on_outline(w['dst_origin_m'][0], w['dst_origin_m'][1])]

# 地砖必须整格落在轮廓内且互不重叠
def tile_in(ix, iy):
    x, y = ix*GRID+GRID/2, iy*GRID+GRID/2
    return all(inside(x+dx, y+dy) for dx in (-2.49, 2.49) for dy in (-2.49, 2.49))
tiles_out = [[t['grid'][0], t['grid'][1]] for t in tile_instances if not tile_in(*t['grid'])]
tile_keys = [(t['grid'][0], t['grid'][1]) for t in tile_instances]
tile_dupes = len(tile_keys) - len(set(tile_keys))

# 设施越界
oob = []
for p in packages:
    if p['category'] != 'facilities': continue
    for o in p['items']:
        b = bounds([o])
        for cx in (b[0][0], b[1][0]):
            for cy in (b[0][1], b[1][1]):
                if not inside_env(cx, cy):
                    oob.append(p['slug']+':'+o.name); break
            else: continue
            break
oob = sorted(set(oob))

# 门位净空：门洞通行体 = 沿墙方向「门洞净宽」× 自结构边线向房内 1.45m × z∈[0.30,3.00]。
# 🔴 沿墙方向按 door_contract 的**门净宽 2.2m（±0.10 余量）**取窗，而非整樘 5m：
#    运行时把某樘换成门洞墙件时，门洞两侧仍是实体墙（转角护柱 / 贴墙装饰可保留），
#    只有门洞净宽范围 + 门内 1.45m 的通行带必须无障碍。z 下界取门槛底 0.30、上界取过梁底 2.80 之上，
#    故吊顶 / 桥架 / 风管 / 高处壁挂件（z≥3.0）天然不受限。
DOOR_HALF = 2.2/2 + 0.10
LANE_DEPTH, LANE_OUT = WALL_T/2 + 1.30, WALL_T/2 + 0.30
LANE_BANDS = []
for x0 in (-12.5, -7.5, -2.5, 2.5, 7.5, 12.5):
    LANE_BANDS.append((x0-DOOR_HALF, x0+DOOR_HALF, HY-LANE_DEPTH, HY+LANE_OUT))
for x0 in (-2.5, 2.5):
    LANE_BANDS.append((x0-DOOR_HALF, x0+DOOR_HALF, -(HY+LANE_OUT), -(HY-LANE_DEPTH)))
for y0 in (-7.5, -2.5, 2.5, 7.5):
    LANE_BANDS.append((HX-LANE_DEPTH, HX+LANE_OUT, y0-DOOR_HALF, y0+DOOR_HALF))
    LANE_BANDS.append((-(HX+LANE_OUT), -(HX-LANE_DEPTH), y0-DOOR_HALF, y0+DOOR_HALF))

def _ov(b, r):
    return not (b[1][0] < r[0] or b[0][0] > r[1] or b[1][1] < r[2] or b[0][1] > r[3])

lane_conflicts = []
for p in packages:
    if p['category'] not in ('facilities', 'support'): continue
    for o in p['items']:
        b = bounds([o])
        if b[1][2] <= .30 or b[0][2] >= 3.00: continue
        for r in LANE_BANDS:
            if _ov(b, r): lane_conflicts.append(p['slug']+':'+o.name); break
lane_conflicts = sorted(set(lane_conflicts))

# 链接纯度：本房型自持几何只允许出现在「自产组件」里；墙/砖必须来自链接库
link_libs = {c.library.filepath for c in LINKED.values()}
authored_mesh_names = {o.data.name for p in packages for o in p['items']}
local_meshes = [m for m in bpy.data.meshes if m.library is None
                and m.name not in authored_mesh_names and not m.name.endswith(('_主体', '_自发光'))]

checks = {
    'template_dimensions_locked': wb['size_m'] == [40.0, 30.0],
    'footprint_variant_is_db_01': wb['variants'] == ['db_01', 'db_02'],
    'footprint_area_1050': abs(FLOOR_AREA-1050.0) < 1e-6,
    'wall_bays_28': len(wall_instances) == 28,
    'door_wall_piece_1': sum(1 for w in wall_instances if w['is_door']) == 1,
    'wall_bays_on_outline': walls_off_outline == [],
    'wall_bays_echo_template_lanes': all(
        round(abs(w['dst_origin_m'][0]), 5) in (2.5, 7.5, 12.5, 17.5)
        or round(abs(w['dst_origin_m'][1]), 5) in (2.5, 7.5, 12.5) for w in wall_instances),
    'floor_tiles_42': len(tile_instances) == 42,
    'floor_tiles_inside_footprint': tiles_out == [],
    'floor_tiles_unique': tile_dupes == 0,
    'floor_tiles_5m_grid': all(t['dst_origin_m'][2] == -0.32 for t in tile_instances),
    'linked_library_single': len(link_libs) == 1,
    'linked_from_office_room': next(iter(link_libs)).endswith('办公室房间种类_开放办公_30x40m_v001.blend'),
    'linked_collections_are_library_owned': all(c.library is not None for c in LINKED.values()),
    'no_local_wall_or_tile_meshes': local_meshes == [],
    'facilities_inside_footprint': oob == [],
    'perimeter_furniture_avoids_door_lanes': lane_conflicts == [],
    'door_contract_matches_whitebox': wb['door_contract'] == {'width_m': 2.2, 'height_m': 2.5,
                                                             'clear_floor_gap_m': 0.0, 'bottom_z_m': 0.3,
                                                             'lintel_bottom_z_m': 2.8},
    'openable_lanes_match_template': all(
        len(wb['wall_lane_table'][s]) == n for s, n in (('north', 6), ('south', 6), ('east', 4), ('west', 4))),
    'palette_external_unique': img.packed_file is None
                               and Path(bpy.path.abspath(img.filepath)).resolve() == PALETTE.resolve(),
    'four_local_materials': [m.name for m in bpy.data.materials if m.library is None] == roles,
    'all_packages_nonempty': all(p['items'] for p in packages),
    'categories_present': all(any(p['category'] == c for p in packages)
                              for c in ('floor', 'facilities', 'support')),
}
_failed = {k: v for k, v in checks.items() if not v}
if _failed:
    print('QA_FAILURES', json.dumps(_failed, ensure_ascii=False), flush=True)
    print('--- detail ---', flush=True)
    print('walls_off_outline', walls_off_outline, flush=True)
    print('tiles_out', tiles_out, flush=True)
    print('oob', oob, flush=True)
    print('lane_conflicts', lane_conflicts, flush=True)
    print('local_meshes', [m.name for m in local_meshes], flush=True)
assert all(checks.values()), _failed

# ================================================================ 合并 / 资产包
def merge_package(p, emission):
    objs = [o for o in p['items'] if (o['material_role'] == 3) == emission]
    if not objs: return None
    dg = bpy.context.evaluated_depsgraph_get(); vs = []; fs = []; mi = []; cells = []
    used = [3] if emission else [0, 1, 2]
    for o in objs:
        ev = o.evaluated_get(dg); me = ev.to_mesh(); off = len(vs)
        vs.extend([o.matrix_world@v.co for v in me.vertices])
        fs.extend([tuple(off+i for i in f.vertices) for f in me.polygons])
        mi.extend([used.index(o['material_role'])]*len(me.polygons))
        cells.extend([list(o['palette_cell'])]*len(me.polygons)); ev.to_mesh_clear()
    mesh = bpy.data.meshes.new(p['title']); mesh.from_pydata(vs, [], fs); mesh.update()
    for i in used: mesh.materials.append(mats[i])
    uv = mesh.uv_layers.new(name='PaletteUV'); mesh.uv_layers.active = uv; uv.active_render = True
    for poly, mat, cell in zip(mesh.polygons, mi, cells):
        poly.material_index = mat
        for j, li in enumerate(poly.loop_indices):
            a = 2*math.pi*j/len(poly.loop_indices)
            uv.data[li].uv = ((cell[0]+.5)/10+.022*math.cos(a), 1-(cell[1]+.5)/10+.022*math.sin(a))
    obj = bpy.data.objects.new(p['title']+('_自发光' if emission else '_主体'), mesh)
    p['col'].objects.link(obj)
    obj['package_id'] = 'ENV-EXPEDITION-L01-DB-'+p['slug'].upper()
    obj['version'] = 'v001'; obj['collision_owner'] = p['collision_owner']
    obj['visual_only'] = p['visual_only']
    return obj

records = []
for p in packages:
    merged = [o for o in (merge_package(p, False), merge_package(p, True)) if o]
    sc = collection(p['title']+'_制作组件', src)
    for o in p['items']: p['col'].objects.unlink(o); sc.objects.link(o)
    b = bounds(merged)
    origin = [(b[0][i]+b[1][i])/2 for i in range(2)]+[b[0][2]]
    for o in merged:
        for v in o.data.vertices: v.co -= Vector(origin)
        o.location = origin
    rec = {'package_id': 'ENV-EXPEDITION-L01-DB-'+p['slug'].upper(), 'slug': p['slug'],
           'name_zh': p['title'], 'category': p['category'], 'version': 'v001', 'source_blend': BLEND,
           'collection': p['col'].name, 'objects': [o.name for o in merged], 'world_origin_m': origin,
           'local_origin': 'bottom_center', 'provenance': 'authored_here',
           'world_bounds_m': b, 'dimensions_m': [round(b[1][i]-b[0][i], 5) for i in range(3)],
           'materials': roles, 'source_piece_count': len(p['items']),
           'reference_cutaway_hidden': p['cutaway'],
           'collision_owner': p['collision_owner'], 'visual_only': p['visual_only'],
           'collision_exported': False, 'exported': False, 'dependencies': []}
    directory = PKGDIR/p['category']/p['slug']; directory.mkdir(parents=True, exist_ok=True)
    (directory/'asset_manifest.json').write_text(
        json.dumps(rec, ensure_ascii=False, indent=2)+'\n', encoding='utf-8', newline='\r\n')
    records.append(rec); p['output'] = merged

src.hide_render = True; src.hide_viewport = True
for layer in bpy.context.view_layer.layer_collection.children[root.name].children:
    if layer.name == src.name: layer.exclude = True

_keep = {str(PKGDIR/p['category']/p['slug']) for p in packages}
for _m in PKGDIR.glob('*/*/asset_manifest.json'):
    if str(_m.parent) not in _keep:
        for _f in sorted(_m.parent.glob('**/*'), reverse=True):
            if _f.is_file(): _f.unlink()
        for _d in sorted([d for d in _m.parent.glob('**/*') if d.is_dir()], reverse=True):
            _d.rmdir()
        _m.parent.rmdir()
        print('STALE_PACKAGE_REMOVED', _m.parent.name, flush=True)

checks['output_uv_and_material_slots'] = all(
    'PaletteUV' in o.data.uv_layers and all(f.material_index < len(o.data.materials) for f in o.data.polygons)
    for p in packages for o in p['output'])
checks['one_package_per_output'] = all(len(o.users_collection) == 1 for p in packages for o in p['output'])
checks['disk_collection_count'] = len(records) == len(list(PKGDIR.glob('*/*/asset_manifest.json')))
output_meshes = [o for p in packages for o in p['output']]

# 链接引用清单（本房型不产出这些包，只是引用）
linked_records = []
for w in wall_instances:
    linked_records.append({'kind': 'wall_bay', 'source_package_collection': w['coll'],
                           'source_room_type': 'office_room/v001', 'linked_slug': w['slug'],
                           'target_side': w['side'], 'target_lane_m': w['u'],
                           'src_origin_offset_m': WALL_OFFSETS.get(w['slug']),
                           'rotation_deg': w['rotation_deg'], 'dst_origin_m': w['dst_origin_m'],
                           'is_door_wall': w['is_door']})
for t in tile_instances:
    linked_records.append({'kind': 'floor_tile', 'source_package_collection': t['coll'],
                           'source_room_type': 'office_room/v001', 'linked_slug': t['slug'],
                           'target_grid': t['grid'], 'rotation_deg': t['rotation_deg'],
                           'dst_origin_m': t['dst_origin_m'], 'is_door_wall': False})
linked_summary = {}
for r in linked_records:
    k = (r['kind'], r['linked_slug'])
    linked_summary[k] = linked_summary.get(k, 0) + 1

manifest = {
    'schema': 'shellstorm2.room_type_art_manifest', 'schema_version': 1, 'version': 'v001',
    'template_id': 'db_70x50', 'room_type': 'COMMON_ROOM', 'block_id': 'expedition',
    'design_scope': 'scene_art',
    'asset_ledger': 'assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx::3D-场景通用',
    'room_asset_id': wb['asset_ids']['room'],
    'source_blend': BLEND, 'whitebox_source': str(WHITEBOX.relative_to(ROOT)),
    'dimensions_m': [40, 30], 'bbox_m': [W, D],
    'footprint': {'variant_covered': 'db_01', 'variant_pending': ['db_02'],
                  'polygon_local_m': [list(p) for p in POLY], 'area_m2': FLOOR_AREA,
                  'bbox_area_m2': W*D,
                  'note': '本项目房型源按参考图（数据库房间01）做 db_01 布局；db_02（左下 15x10 / 右下 15x5 '
                          '双缺角 + 货架箱体堆场）为同一白盒契约的另一内部布局，待另轮制作。'},
    'wall_visual_height_m': WALL_H, 'wall_logic_height_m': 12,
    'interior_walls': False, 'door_contract': wb['door_contract'],
    'door_lanes': {'total': 16, 'north': 6, 'south': 2, 'east': 4, 'west': 4,
                   'note': '取自模板 wall_lane_table，且经 check_expedition_room_footprints.py 逐槽判定'
                           '「完全落在该向外墙线段上」。南向只有外凸段 2 槽（subject 主体南墙两段不在槽表里）。'},
    'door_lane_clearance': {'z_window_m': [0.30, 3.00], 'along_window_m': round(2*DOOR_HALF, 3),
                            'depth_into_room_m': round(LANE_DEPTH, 3),
                            'rule': '门洞通行体（门净宽 2.2m + 0.10 余量 × 自结构边线向房内 1.45m × z∈[0.30,3.00]）'
                                    '内不得有落地设施；z≥3.0 的高处壁挂件（灯柱/大屏/线圈/走管/吊顶桥架）与'
                                    '门洞净宽之外的贴墙件（含转角护柱）不受限。',
                            'authored_rule': '本房型源不冻结门位：三处实例（room_02 南+东 / room_06 北+东 / '
                                             'room_10 西+东）门位各异 ⇒ 全部 16 个可开槽保持净空。'},
    'door_wall_piece': {'reusable': True, 'linked_from': 'office_room/v001::门洞墙件_可复用_资产包',
                        'authored_at': 'north wall lane x=+2.5 (office)',
                        'placed_at': 'tab_south wall lane x=+2.5 (rotated 180 deg)',
                        'geometry_wdh_m': [GRID, WALL_H, WALL_T],
                        'note': '门洞墙件几何对各朝向一致；运行时按门位车道替换对应标准墙件。'},
    'linked_component_library': {
        'source_room_type': 'office_room/v001',
        'source_blend': str(OFFICE_BLEND.relative_to(ROOT)),
        'mechanism': 'bpy.data.libraries.load(link=True) 集合实例；未 Append、未复制共享组件网格、'
                     '未改组件几何/材质/根原点；实例空物体 L = P_dst - R * origin_src',
        'wall_bays_linked': len(wall_instances), 'floor_tiles_linked': len(tile_instances),
        'distinct_wall_packages': len({w['slug'] for w in wall_instances}),
        'distinct_tile_packages': len({t['slug'] for t in tile_instances}),
        'wall_src_choice': '只用「素件」（不含办公室专属装饰：旗幡 / 白板 / 通告板 / 窗带 / 监视屏 / '
                           '配电柜 / 货架标）；朝向匹配或按 0/90/180/270 旋转复用，共 %d 个不同源包服务 %d 樘素墙件。'
                           % (len({w['slug'] for w in wall_instances if not w['is_door']}),
                              sum(1 for w in wall_instances if not w['is_door'])),
        'floor_tile_mapping': 'db 网格 (ix,iy) -> office 网格 (ox,oy)：ox = ix（|ix|<=3），'
                              'ix=-4 -> ox=2，ix=3 -> ox=-3（差值 ±6 ⇒ 保留 (ix+iy) 奇偶相位，'
                              '地面警示斜条棋盘不翻相）；oy = iy。',
    },
    'required_components': ['linked office 5m plain wall bays (%d distinct source packages, %d instances)'
                            % (len({w['slug'] for w in wall_instances if not w['is_door']}),
                               sum(1 for w in wall_instances if not w['is_door'])),
                            'linked office reusable door wall bay',
                            'linked office 5m floor deck tiles (%d instances)' % len(tile_instances)],
    'required_facilities': ['west server rack row (7 racks)', 'centre rack cluster + rolling cart',
                            'west maintenance bench', 'east L-shaped workbench',
                            'wall screen bank', 'red tool chests x2', 'centre worktable',
                            'crate and tote field', 'north heavy shelving', 'parts drawer cabinets',
                            'floor cable reels', 'wall cable coils', 'white planters',
                            'north-east equipment racks', 'south-west annex bench',
                            'yellow tool carts + workshop stools', 'wall cold-light pylons',
                            'wall pipe/conduit runs', 'floor grates', 'floor zone markings',
                            'along-wall hazard edging', 'raised service pit platform',
                            'floor conduit runs', 'instrument tripods'],
    'door_geometry_in_source': False,
    'reference_image': str(REF), 'reference_sha256': hashlib.sha256(REF.read_bytes()).hexdigest(),
    'scope': {'modifiable': 'all new database-room scene-art geometry and presentation',
              'locked': 'whitebox dimensions and footprint, wall height, door contract, office wall/floor '
                        'component geometry (linked read-only), gameplay',
              'previous_versions_preserved': True},
    'package_count': len(records), 'output_mesh_count': len(output_meshes),
    'linked_instance_count': len(wall_instances)+len(tile_instances),
    'material_roles': roles, 'palette_texture': str(PALETTE),
    'preview_note': 'Cutaway images hide named near-wall linked bays and ceiling-deck packages; top view '
                    'additionally hides ceiling deck/services. Complete source retains all geometry. '
                    'No gameplay changes, no GLB, no engine integration.',
    'packages': records,
}
qa = {'status': 'PASS' if all(checks.values()) else 'FAIL', 'checks': checks,
      'measured': {'footprint_area_m2': FLOOR_AREA, 'wall_bay_count': len(wall_instances),
                   'door_wall_count': sum(1 for w in wall_instances if w['is_door']),
                   'floor_tile_count': len(tile_instances),
                   'linked_instance_count': len(wall_instances)+len(tile_instances),
                   'authored_package_count': len(records), 'output_meshes': len(output_meshes),
                   'source_piece_count': sum(len(p['items']) for p in packages),
                   'output_faces': sum(len(o.data.polygons) for o in output_meshes),
                   'wall_src_distinct': len({w['slug'] for w in wall_instances}),
                   'tile_src_distinct': len({t['slug'] for t in tile_instances})},
      'linked_reference': {'library': str(OFFICE_BLEND.relative_to(ROOT)),
                           'distinct_wall_bays': sorted({w['slug'] for w in wall_instances}),
                           'distinct_floor_tiles': sorted({t['slug'] for t in tile_instances}),
                           'instances': len(linked_records)},
      'scope_lock': {'whitebox_sha256': hashlib.sha256(WHITEBOX.read_bytes()).hexdigest(),
                     'reference_sha256': hashlib.sha256(REF.read_bytes()).hexdigest(),
                     'office_library_blend_sha256': hashlib.sha256(OFFICE_BLEND.read_bytes()).hexdigest(),
                     'method': 'all new art geometry authorized for authoring; wall and floor tile geometry '
                               'reused by library link only; preserve whitebox and reference by hash'},
      'visual_review': {'status': 'reviewed against reference (6 views)',
                        'views': ['top_plan', 'cutaway_sw', 'west_rack_row', 'east_workbench',
                                  'centre_workshop', 'tab_entry'],
                        'reference': 'docs/v0.1/design/refs/expedition01/数据库房间01.jpg',
                        'deepening': ['wall/floor shell linked from office_room (no re-authoring)',
                                      'server rack row: 7 racks with U-slot LED matrix and side light column',
                                      'east L workbench with under-counter cabinets + wall screens',
                                      'hazard edging follows the irregular footprint edge by edge',
                                      'numbered floor zone plates + chevrons + yellow diamonds',
                                      'raised service pit platform with hazard border',
                                      'cable reels, wall coils, planters, crates, parts drawers']},
      'palette_texture': {'image': PALETTE.name, 'filepath': str(PALETTE), 'is_relative': False,
                          'packed': False, 'materials_bound': roles, 'interpolation': 'Closest',
                          'uv_map': 'PaletteUV'},
      'runtime_integration': False}

for name, data in [('room_type_manifest.json', manifest), ('component_inventory.json', records),
                   ('linked_office_components.json',
                    {'schema': 'shellstorm2.room_type_linked_components', 'schema_version': 1,
                     'source_room_type': 'office_room/v001',
                     'source_blend': str(OFFICE_BLEND.relative_to(ROOT)),
                     'distinct_packages': len(linked_summary), 'instances': len(linked_records),
                     'packages': [{'kind': k, 'linked_slug': s, 'instance_count': n}
                                  for (k, s), n in sorted(linked_summary.items())],
                     'instances_detail': linked_records}), ('qa_report.json', qa)]:
    (OUT/name).write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n',
                          encoding='utf-8', newline='\r\n')
(OUT/'component_tree.txt').write_text(
    '\n'.join(p['category']+'/'+p['slug']+' -> '+p['col'].name for p in packages), encoding='utf-8')

scene.camera = None
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/BLEND), relative_remap=False)
print('SOURCE_SAVED', str(OUT/BLEND), len(records), len(output_meshes), flush=True)

# ================================================================ 灯光 / 相机 / 渲染
def area(name, loc, power, color, size, target):
    data = bpy.data.lights.new(name, 'AREA'); data.energy = power; data.color = color
    data.shape = 'DISK'; data.size = size
    o = bpy.data.objects.new(name, data); display.objects.link(o); o.location = loc
    o.rotation_euler = (Vector(target)-o.location).to_track_quat('-Z', 'Y').to_euler(); return o

area('主光_冷白顶光', (-18, -46, 50), 13000, (.56, .72, 1), 34, (0, 0, 0))
area('背缘冷蓝', (36, 28, 28), 6200, (.18, .44, 1), 22, (0, 0, -1))
area('前部柔光', (30, -36, 14), 4200, (.36, .56, 1), 26, (0, 0, -2))
area('顶部补光', (0, 0, 34), 5200, (.48, .66, 1), 30, (0, 0, 0))
area('北墙洗墙', (0, 13, 10), 2100, (.42, .62, 1), 14, (0, 20, 3))
area('南墙洗墙', (0, -14, 10), 2100, (.42, .62, 1), 12, (0, -20, 3))
area('东墙洗墙', (10, 2, 10), 1900, (.40, .60, 1), 14, (16, 2, 2))
area('西墙洗墙', (-10, 2, 10), 1900, (.40, .60, 1), 14, (-16, 2, 2))
area('机柜列工作光', (-14.0, 4.5, 5.2), 2000, (.72, .84, 1), 7, (-17.4, 4.5, 1.0))
area('东台工作光', (17.0, 12.4, 5.0), 1800, (.80, .88, 1), 6, (18.9, 12.4, 1.0))
area('中央工作光', (-3.6, -3.2, 5.4), 1700, (.84, .90, 1), 6, (-3.6, -3.2, 1.0))
area('南部作业补光', (0, -6.0, 6.0), 1500, (.70, .82, 1), 12, (0, -6.0, 0.5))

def camera(name, loc, target, scale):
    d = bpy.data.cameras.new(name); o = bpy.data.objects.new(name, d); display.objects.link(o)
    o.location = loc
    o.rotation_euler = (Vector(target)-o.location).to_track_quat('-Z', 'Y').to_euler()
    d.type = 'ORTHO'; d.ortho_scale = scale; d.clip_end = 500; return o

cam_top = camera('参考镜头_顶视', (0, 0, 130), (0, 0, 0), 49)
cam_cut = camera('参考镜头_南向等轴', (7, -55, 41), (-1, -1.5, 2.2), 58)
cam_rack = camera('参考镜头_西侧机柜列', (-30, -3.0, 10), (-17.45, 4.6, 1.5), 15)
cam_bench = camera('参考镜头_东墙工作台', (-4, 2, 8), (18.6, 12.4, 1.8), 16)
cam_centre = camera('参考镜头_中央作业区', (-23, -26, 14), (-2.0, -3.5, 1.0), 23)
cam_tab = camera('参考镜头_外凸入口', (0, -34, 9), (0, -12.0, 1.3), 18)

WALL_E = {i: e for i, e in enumerate(link_host.objects)}
_HEAVY_CEILING = ('ceiling_deck', 'ceiling_ring_beam', 'wall_top_service')
def set_hidden(sides, hide_ceiling, hide_all_support=False):
    for e in link_host.objects:
        e.hide_render = (e.get('link_wall_side') in sides)
    for p in packages:
        if p['category'] != 'support':
            p['col'].hide_render = False; continue
        if hide_all_support:
            p['col'].hide_render = True
        elif hide_ceiling:
            # 剖视：隐藏厚重吊顶结构与周圈圈梁（否则大片黑梁压住画面），
            # 保留桥架 / 管道 / 风管 / 灯具 —— 它们是参考图里最有工业感的顶部特征。
            p['col'].hide_render = p['slug'].startswith(_HEAVY_CEILING)
        else:
            p['col'].hide_render = False

def render(camera_, name, sides=(), hide_ceiling=False, hide_all_support=False):
    set_hidden(set(sides), hide_ceiling, hide_all_support)
    scene.camera = camera_; scene.render.filepath = str(RENDER/name)
    bpy.ops.render.render(write_still=True)

ALL_SIDES = {'north', 'west', 'east', 'south_w', 'south_e', 'tab_s', 'tab_w', 'tab_e'}
if not opts.no_render:
    # 顶视 = 干净平面图（连顶部服务一起隐去，只留地坪与地面标识）
    render(cam_top, 'db_01_top', ALL_SIDES, True, True)
    if not opts.preview:
        render(cam_cut, 'db_02_cutaway_sw', {'west', 'south_w', 'south_e', 'tab_s', 'tab_w', 'tab_e'}, True)
        render(cam_rack, 'db_03_west_rack_row', {'west'}, False)
        render(cam_bench, 'db_04_east_workbench', {'west', 'south_w', 'south_e'}, True)
        render(cam_centre, 'db_05_centre_workshop', {'west', 'south_w', 'south_e', 'tab_s', 'tab_w', 'tab_e'}, True)
        render(cam_tab, 'db_06_tab_entry', {'south_w', 'south_e', 'tab_s', 'tab_w', 'tab_e'}, False)
set_hidden(set(), False)
print('BUILD_COMPLETE', json.dumps(qa['measured'], ensure_ascii=False), flush=True)
