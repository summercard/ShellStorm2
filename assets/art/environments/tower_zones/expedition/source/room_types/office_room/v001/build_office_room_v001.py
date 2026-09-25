"""办公室房间种类（方形开放办公 30x40m）美术源 v001。参考图导向深化，Blender 4.5。

冻结契约：30x40m / 墙高 11.9m / 5m 模数 / 门洞 2.2x2.5 底 0.3m 过梁底 2.8m / 无内墙。
公共唯一色盘 + 四共享材质角色 + PaletteUV；每末级语义包一 Collection + asset_manifest.json。
"""
from pathlib import Path
import bpy, math, json, hashlib, random, sys, argparse
from mathutils import Vector

HERE = Path(__file__).resolve(); OUT = HERE.parent; ROOT = HERE.parents[9]
RENDER = OUT/'renders'; RENDER.mkdir(exist_ok=True)
PKGDIR = OUT/'component_packages_v001'
PALETTE = ROOT/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
WHITEBOX = ROOT/'source/art/whitebox/tower_zones/expedition_01/v001/data/room_templates/office_60x70.json'
REF = ROOT/'docs/v0.1/design/refs/expedition01/办公室01.jpg'
BLEND = '办公室房间种类_开放办公_30x40m_v001.blend'

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
scene.view_settings.look = 'AgX - Medium High Contrast'; scene.view_settings.exposure = -0.55
world = bpy.data.worlds.new('冷蓝灰展示环境'); scene.world = world; world.use_nodes = True
world.node_tree.nodes.clear()
bg = world.node_tree.nodes.new('ShaderNodeBackground'); wo = world.node_tree.nodes.new('ShaderNodeOutputWorld')
world.node_tree.links.new(bg.outputs['Background'], wo.inputs['Surface'])
bg.inputs['Color'].default_value = (.055, .085, .145, 1); bg.inputs['Strength'].default_value = .18

# ---------------------------------------------------------------- collections
def collection(name, parent):
    c = bpy.data.collections.new(name); parent.children.link(c); return c

root = collection('办公室房间_开放办公_v001', scene.collection)
src = collection('01_制作组件_按设施拆分', root)
game = collection('02_游戏输出_独立资产包_v001', root)
cats = {k: collection(v, game) for k, v in [('architecture', '01_建筑结构'), ('floor', '02_地面系统'),
                                            ('facilities', '03_区域固定设施'), ('support', '04_环境支持')]}
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

# 色盘取样实测值（assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png，10x10 纯色格；元组为 (列,行)）
VOID = (0, 9)     # #05050c 近黑
DARK = (9, 0)     # #1b2533 深蓝灰（结构主体）
PANEL = (9, 1)    # #263242 面板
HULL = (9, 2)     # #324052
EDGE = (9, 3)     # #3f4f62 结构棱线
MID = (9, 4)      # #4d5e72
STEEL = (9, 5)    # #5d6e82 金属
PALE = (9, 6)     # #718195
HI = (9, 7)       # #8998aa
HI2 = (9, 8)      # #a5b2c1
WHITE = (9, 9)    # #c5ced8
BLUE = (8, 0)     # #1b3b6f 蓝（灯带/标识）
BLUEB = (4, 6)    # #112d6a 深蓝
INDIGO = (2, 9)   # #16153a 深靛（大面暗部）
CYAN = (3, 0)     # #0f5f72 青（屏幕/冷光主色）
ICE = (6, 5)      # #0f5f6b 次青（冷光辅色）
TEAL = (5, 5)     # #145f56
GREEN = (6, 4)    # #21643a 绿植
GREEN_D = (1, 4)  # #092514 深绿
AMBER = (6, 3)    # #715c09 暖色（台灯/警示）
RUST = (4, 2)     # #692805
RED = (5, 1)      # #6e1c2a
TAN = (8, 2)      # #72614d 纸箱
CARD = (6, 9)     # #381408 深棕
PURPLE = (7, 7)   # #4b3f71

# ---------------------------------------------------------------- room contract
W, D = 30.0, 40.0
HX, HY = W/2, D/2
WALL_T, WALL_H, GRID = 0.30, 11.9, 5.0
WALL_IN = WALL_T/2 + 0.12          # 结构墙内表面 + 装甲前凸 = 0.27
FURN_X, FURN_Y = HX-WALL_IN, HY-WALL_IN   # 家具可用内边界 14.73 / 19.73

# ---------------------------------------------------------------- packaging
packages = []; current = None

def pack(slug, title, cat='architecture', cut=False, coll='self', visual_only=False):
    global current
    c = collection(title+'_资产包', cats[cat])
    current = {'slug': slug, 'title': title, 'category': cat, 'col': c, 'cutaway': cut,
               'collision_owner': coll, 'visual_only': visual_only, 'items': []}
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

def glyph(name, ch, loc, h=.62, cell=WHITE, w=.024, mat=1):
    """极简笔画字模，供地面分区标识用。"""
    S = {'A': [((-.45, -.50), (0, .50)), ((0, .50), (.45, -.50)), ((-.30, -.06), (.30, -.06))],
         'B': [((-.36, -.50), (-.36, .50)), ((-.36, .50), (.22, .30)), ((.22, .30), (-.36, .03)),
               ((-.36, .03), (.32, -.22)), ((.32, -.22), (-.36, -.50))]}[ch]
    for a, b in S:
        cyl(name, (loc[0]+a[0]*h, loc[1]+a[1]*h, loc[2]), (loc[0]+b[0]*h, loc[1]+b[1]*h, loc[2]), w, mat, cell, 8)

def bolts(x, y, z, w, d):
    for sx in (-1, 1):
        for sy in (-1, 1):
            cyl('固定螺栓', (x+sx*w, y+sy*d, z), (x+sx*w, y+sy*d, z+.035), .045, 0, STEEL, 6)

# ================================================================ 01 地面系统
rng = random.Random(250926)
floor_bases = []

def tile(ix, iy):
    x, y, z = ix*GRID+GRID/2, iy*GRID+GRID/2, 0.0
    pack('tile_%d_%d' % (ix, iy), '地砖_%d_%d' % (ix, iy), 'floor')
    o = box('结构地砖', (x, y, z-.16), (GRID, GRID, .32), 1, DARK, 0)
    o['contract_floor_base'] = True; floor_bases.append(o)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box('分块耐磨钢板', (x+sx*1.21, y+sy*1.21, z+.024), (2.36, 2.36, .048), 1, PANEL, .015)
    for dx in (-2.44, 2.44):
        box('纵向拼缝轨道', (x+dx, y, z+.056), (.055, 4.90, .028), 0, EDGE, .005)
    for dy in (-2.44, 2.44):
        box('横向拼缝轨道', (x, y+dy, z+.056), (4.90, .055, .028), 0, EDGE, .005)
    bolts(x, y, z+.052, 2.30, 2.30)
    # 板缝冷蓝导光条（参考图：整套拼缝网格均发冷蓝光），压在拼缝轨道顶面
    for dy in (-2.44, 2.44):
        box('拼缝冷蓝导光条', (x, y+dy, z+.078), (4.34, .038, .014), 3, BLUE, .002)
    for dx in (-2.44, 2.44):
        box('拼缝冷蓝导光条', (x+dx, y, z+.078), (.038, 4.34, .014), 3, BLUE, .002)
    # 斜向警示斜条（参考图：板块边缘人字警示带，南北两排反向）
    if (ix+iy) % 2 == 0:
        for k in range(5):
            for sy in (-1, 1):
                o = box('地面警示斜条', (x-1.32+k*.66, y+sy*1.72, z+.055), (.52, .19, .012), 1, WHITE, .003)
                o.rotation_euler.z = .62 if sy > 0 else -.62
    # 地面检修口
    if (ix*3+iy) % 5 == 0:
        box('凹入检修口框', (x+.55, y+.35, z+.056), (1.70, 1.18, .026), 0, DARK)
        for j in range(9):
            box('检修格栅叶片', (x-.14+j*.17, y+.35, z+.086), (.075, 1.02, .036), 0, EDGE, .005)
    # 中央大排水格栅
    if (ix, iy) in ((-1, -1), (0, 2)):
        box('中央排水口框', (x, y, z+.058), (1.40, .92, .030), 0, VOID, .006)
        for j in range(11):
            box('排水栅条', (x-.58+j*.116, y, z+.092), (.042, .80, .045), 0, STEEL, .004)
    # 局部磨损与刮痕（确定性随机，仅用色盘，不引私有贴图）
    for j in range(9):
        xx = x+rng.uniform(-2.15, 2.15); yy = y+rng.uniform(-2.15, 2.15); rr = rng.uniform(.08, .34)
        verts = []
        for k in range(7):
            a = k*math.pi*2/7; rad = rr*rng.uniform(.55, 1.4)
            verts.append((xx+rad*math.cos(a), yy+rad*math.sin(a), z+.051))
        mesh_obj('局部不规则磨损斑', verts, [tuple(range(7))], 1, DARK if j % 2 else HULL)
    for j in range(10):
        o = box('边缘磨痕', (x+rng.uniform(-2, 2), y+rng.uniform(-2, 2), z+.055),
                (rng.uniform(.09, .26), .015, .004), 0, EDGE, 0)
        o.rotation_euler.z = rng.uniform(-1, 1)

for iy in range(-4, 4):
    for ix in range(-3, 3):
        tile(ix, iy)

pack('floor_zone_mark', '地面分区标识', 'floor', coll='visual_only', visual_only=True)
for ch, px, py in (('A', -11.4, 15.2), ('B', 11.6, -1.2)):
    box('标识底板', (px, py, .056), (2.70, 2.70, .012), 1, HULL, .004, math.pi/4)
    glyph('地面分区字母', ch, (px, py, .068), 1.15, WHITE, .046)

# ================================================================ 02 建筑结构
wall_bases = []

def wall_bay(side, k, door=False):
    """u 沿墙走向；v 自墙体中心面指向房内。"""
    long = side in ('east', 'west')
    sign = 1 if side in ('east', 'north') else -1
    pos = k*GRID+GRID/2
    cut = side in ('west', 'south')
    slug = 'door_wall' if door else 'wall_%s_%d' % (side, k)
    title = '门洞墙件_可复用' if door else '%s_墙体_%d' % (side, k)
    p = pack(slug, title, 'architecture', cut)
    p['inward_normal'] = (('%sY' % ('-' if sign > 0 else '+')) if not long
                          else ('%sX' % ('-' if sign > 0 else '+')))
    p['wall_side'] = side; p['lane_k'] = k; p['door_opening'] = door

    def pt(u, v, z):
        return (pos+u, sign*(HY-v), z) if not long else (sign*(HX-v), pos+u, z)

    def wb(name, u, v, z, w, d, h, mat=0, cell=PANEL, bev=.025):
        return box(name, pt(u, v, z), (w, d, h) if not long else (d, w, h), mat, cell, bev)

    # 主体墙 5.0 x 0.30 x 11.9；内嵌装甲前凸 0.120m
    wall_bases.append(wb('标准结构墙', 0, 0, WALL_H/2, GRID, WALL_T, WALL_H, 1, DARK, 0))
    for z, h in [(1.55, 2.60), (5.35, 4.20), (9.75, 3.10)]:
        wb('内嵌装甲板', 0, .21, z, 4.66, .120, h, 1, PANEL, .020)
        for u in (-2.32, 0.0, 2.32):
            wb('装甲板竖向分缝', u, .245, z, .075, .040, h-.10, 0, VOID, .004)
        for u in (-2.42, 2.42):
            wb('装甲板亮边', u, .230, z, .06, .030, h-.12, 0, EDGE, .002)
    for u in (-2.42, 2.42):
        wb('墙面纵向压筋', u, .30, WALL_H/2-.35, .13, .16, WALL_H-.70, 0, EDGE, .020)
    for z in (3.10, 7.45):
        wb('墙面横向管槽', 0, .34, z, 4.80, .15, .14, 0, DARK, .010)
        for u in (-1.6, 0.0, 1.6):
            wb('管槽卡箍', u, .40, z, .14, .09, .20, 0, STEEL, .006)
    wb('可维护踢脚梁', 0, .27, .20, 4.86, .30, .26, 0, EDGE, .015)
    for z in (9.00, 9.27):
        cyl('墙上成束导管', pt(-2.46, .40, z), pt(2.46, .40, z), .065, 0, EDGE, 8)
    for u in (-1.85, 1.85):
        wb('墙面分区竖脊', u, .29, WALL_H/2-.6, .085, .13, 8.6, 0, DARK, .006)
        for z in (1.05, 3.55, 6.85, 10.85):
            wb('墙板固定扣', u, .40, z, .16, .12, .22, 0, STEEL, .008)
    wb('墙面检修铭牌', 1.25, .40, 2.85, .54, .05, .28, 0, EDGE, .004)
    for zz in (4.95, 5.17):
        cyl('壁装支线', pt(-2.30, .39, zz), pt(-.30, .39, zz), .032, 0, STEEL, 8)
    # 高处冷蓝连续灯带（参考图：墙体上部成排蓝光灯）
    wb('蓝光灯带槽', 0, .245, 10.62, 4.62, .085, .230, 0, DARK, .006)
    wb('冷蓝连续灯带', 0, .300, 10.62, 4.44, .048, .135, 3, BLUE, .004)
    # 低位冷蓝洗墙灯带（参考图：踢脚上方连续蓝光）
    wb('低位灯带槽', 0, .250, .62, 4.50, .080, .140, 0, DARK, .006)
    wb('低位冷蓝灯带', 0, .296, .62, 4.34, .042, .080, 3, BLUE, .003)
    # 竖向蓝色灯柱
    if not door and (k % 3 == 0):
        wb('竖向灯柱底座', 1.95, .30, 3.90, .30, .20, 5.40, 0, VOID, .010)
        wb('竖向蓝色灯柱', 1.95, .42, 3.90, .13, .07, 5.05, 3, BLUE, .004)
    # 沿墙明装走管（参考图：墙体上部横向管道成束）
    if not door and k % 2 == 1:
        for zz, rr in ((8.62, .075), (8.86, .058)):
            cyl('墙面明装管', pt(-2.44, .38, zz), pt(2.44, .38, zz), rr, 0, STEEL, 8)
            for u in (-1.60, 1.60):
                cyl('墙面管法兰', pt(u, .38, zz), pt(u+.12, .38, zz), rr+.030, 0, EDGE, 8)
    for z in (4.20, 6.60, 10.55):
        if not door:
            wb('钢板横向阴缝', 0, .275, z, 4.45, .075, .045, 0, DARK, .003)
    for u in (-2.10, 2.10):
        for z in (2.20, 8.80):
            wb('装甲固定螺栓座', u, .28, z, .18, .05, .18, 0, STEEL, .004)

    if door:
        # 门洞：净宽 2.2 / 底 0.3 / 过梁底 2.8（与白盒 door_contract 逐值一致）
        for u in (-1.80, 1.80):
            wall_bases.append(wb('门洞边柱', u, 0, 5.95, 1.40, WALL_T, WALL_H, 1, PANEL, .020))
        wall_bases.append(wb('门洞过梁', 0, 0, 7.35, 2.20, WALL_T, 9.10, 1, PANEL, .020))
        wb('门槛', 0, 0, .15, 2.20, WALL_T, .30, 0, EDGE, .010)
        for u in (-1.22, 1.22):
            wb('门框轨道', u, .22, 1.65, .15, .18, 2.70, 0, EDGE, .006)
        wb('门头灯盒', 0, .26, 3.15, 2.80, .26, .32, 0, DARK, .012)
        wb('门楣蓝灯', 0, .42, 3.15, 2.50, .06, .105, 3, BLUE, .004)
        for u in (-1.72, 1.72):
            wb('门侧警示斜纹板', u, .24, 1.30, .46, .06, 2.30, 0, AMBER, .004)
        wb('门牌底板', 1.95, .30, 3.05, .80, .08, .34, 0, VOID, .006)
        wb('门牌蓝色标识', 1.95, .37, 3.05, .62, .04, .17, 3, BLUE, .003)
    return p

EQUIP = {}
def wall_equip(side, k, kind): EQUIP[(side, k)] = kind

# 🔴 门位净空硬约束：north/south 车道墙件 k∈{-2,-1,0,1}、east/west 车道墙件 k∈{-3..2}
# 运行时这些墙件会按关卡门位换成「门洞墙件」⇒ 墙面装饰只能挂在非车道墙件上，
# 否则会被门洞吞掉（或与门框穿模）。非车道墙件共 8 处：
#   north/south k=-3,2；east/west k=-4,3
wall_equip('north', -3, 'banner')      # 西北角旗幡（参考图主标志物）
wall_equip('north', 2, 'whiteboard')   # 东北角白板
wall_equip('south', -3, 'power')       # 西南角配电
wall_equip('south', 2, 'shelflabel')   # 东南角货架标
wall_equip('east', -4, 'windowband')   # 东墙南段窗带
wall_equip('east', 3, 'windowband')    # 东墙北段窗带
wall_equip('west', -4, 'screens')      # 西墙南段监视屏组
wall_equip('west', 3, 'notice')        # 西墙北段通告板

for k in range(-3, 3): wall_bay('north', k, door=(k == 0))
for k in range(-3, 3): wall_bay('south', k)
for k in range(-4, 4): wall_bay('east', k)
for k in range(-4, 4): wall_bay('west', k)

for (side, k), kind in EQUIP.items():
    long = side in ('east', 'west')
    sign = 1 if side in ('east', 'north') else -1
    pos = k*GRID+GRID/2
    current = next(q for q in packages if q['slug'] == 'wall_%s_%d' % (side, k))

    def pt2(u, v, z):
        return (pos+u, sign*(HY-v), z) if not long else (sign*(HX-v), pos+u, z)

    def wb2(name, u, v, z, w, d, h, mat=0, cell=PANEL, bev=.02, rot=0.0):
        return box(name, pt2(u, v, z), (w, d, h) if not long else (d, w, h), mat, cell, bev, rot)

    if kind == 'banner':
        # 参考图：西北角大幅深蓝旗面 + 白色三角环徽标（三角边须绕墙向平面轴旋转）
        wb2('旗幡悬挂横杆', 0, .40, 8.62, 3.96, .10, .10, 0, EDGE, .006)
        wb2('旗面深蓝底板', 0, .335, 7.15, 3.66, .05, 2.84, 1, INDIGO, .004)
        wb2('旗面亮边', 0, .366, 8.53, 3.66, .03, .10, 0, HI, .002)
        wb2('旗面下摆压边', 0, .366, 5.77, 3.66, .03, .10, 0, HI, .002)
        for u in (-1.68, 1.68):
            cyl('旗杆吊环', pt2(u, .40, 8.62), pt2(u, .40, 8.44), .030, 0, STEEL, 6)
        for u, zc, ang in ((-0.405, 7.383, math.radians(60)),
                           (0.405, 7.383, math.radians(-60)),
                           (0.0, 6.683, 0.0)):
            o = wb2('徽记三角边', u, .378, zc, 1.62, .035, .12, 0, HI2, .002)
            o.rotation_euler.y = ang if not long else -ang
        wb2('徽记中竖杆', 0, .378, 7.10, .11, .035, 1.24, 0, HI2, .002)
    elif kind == 'whiteboard':
        wb2('白板背衬框', 0, .295, 1.95, 2.85, .08, 1.66, 0, VOID, .008)
        wb2('白板瓷面板', 0, .345, 1.95, 2.72, .035, 1.54, 1, WHITE, .003)
        for u, z, ww, hh in [(-.95, 2.30, .95, .52), (.55, 2.36, .80, .40),
                             (-.55, 1.62, .72, .46), (.85, 1.66, .86, .56)]:
            wb2('白板张贴纸页', u, .372, z, ww, .012, hh, 1, HI2, .002)
        wb2('白板笔槽', 0, .385, 1.10, 2.60, .08, .09, 0, EDGE, .004)
        for u in (-1.0, 0.4, 1.1):
            wb2('白板笔', u, .40, 1.14, .13, .04, .04, 0, AMBER if u < 0 else BLUE, .002)
        wb2('白板照明灯槽', 0, .40, 2.92, 2.60, .10, .11, 0, DARK, .005)
        wb2('白板照明灯条', 0, .46, 2.92, 2.40, .05, .06, 3, HI2, .003)
    elif kind == 'screens':
        for u in (-.95, .95):
            wb2('壁挂屏幕支架', u, .30, 2.62, .34, .10, .34, 0, VOID, .006)
            wb2('壁挂屏幕外框', u, .38, 2.62, 1.72, .07, 1.08, 0, VOID, .010)
            wb2('屏幕内容发光面', u, .425, 2.62, 1.56, .022, .92, 3, CYAN, .003)
            for r in range(3):
                wb2('屏幕数据横条', u, .44, 3.02-r*.28, .80-r*.18, .010, .045, 3, HI2, .001)
    elif kind == 'notice':
        wb2('记录板背板', 0, .295, 4.30, 2.30, .07, 1.45, 0, VOID, .008)
        wb2('记录板软木面', 0, .340, 4.30, 2.18, .03, 1.34, 1, TAN, .003)
        for u, z, ww, hh in [(-.72, 4.70, .62, .46), (-.05, 4.78, .70, .40), (.72, 4.62, .58, .52),
                             (-.45, 3.98, .80, .50), (.52, 4.02, .66, .44)]:
            wb2('张贴纸页', u, .362, z, ww, .012, hh, 1, HI2, .002)
        for u, z in [(-.72, 4.90), (.72, 4.84), (-.45, 4.20), (.52, 4.22)]:
            cyl('图钉', pt2(u, .38, z), pt2(u, .40, z), .022, 0, RED, 6)
        wb2('记录板下沿托板', 0, .375, 3.55, 2.20, .10, .07, 0, EDGE, .004)
    elif kind == 'emblem':
        wb2('徽标底板', 0, .30, 6.10, 1.90, .06, 1.60, 0, VOID, .008)
        wb2('徽标外框', 0, .34, 6.10, 1.62, .03, 1.32, 0, EDGE, .004)
        wb2('徽标竖向主形', 0, .362, 6.10, .26, .02, 1.06, 0, HI, .003)
        wb2('徽标斜向支形', 0, .362, 6.10, .18, .02, .92, 0, HI, .003, math.radians(34))
        wb2('徽标下横条', 0, .362, 5.52, .90, .02, .12, 0, HI, .003)
    elif kind == 'power':
        wb2('配电柜基座', 0, .52, .14, 2.60, .70, .28, 0, VOID, .010)
        for u in (-.62, .62):
            wb2('配电柜柜体', u, .52, 1.25, 1.10, .62, 2.22, 1, PANEL, .014)
            wb2('配电柜门缝', u, .86, 1.25, .05, .03, 2.00, 0, VOID, .002)
            wb2('配电柜蓝窗', u, .845, 1.95, .72, .03, .36, 3, BLUEB, .003)
            for z in (0.82, 0.52, 0.22):
                wb2('配电柜通风百叶', u, .845, z, .70, .03, .06, 0, DARK, .002)
            cyl('配电柜把手', pt2(u+.48, .86, 1.30), pt2(u+.48, .96, 1.30), .026, 0, STEEL, 6)
        wb2('配电母排槽', 0, .55, 2.48, 2.60, .40, .22, 0, EDGE, .010)
        for u in (-.8, -0.2, .4):
            cyl('母排出线', pt2(u, .62, 2.60), pt2(u, .62, 3.30), .055, 0, DARK, 8)
    elif kind == 'windowband':
        wb2('窗带框', 0, .255, 6.30, 4.10, .12, 1.70, 0, VOID, .010)
        for j in range(4):
            wb2('窗带冷蓝发光面', -1.50+j*1.00, .325, 6.30, .86, .035, 1.44, 3, BLUE, .003)
        wb2('窗带竖向分格', 0, .345, 6.30, .07, .05, 1.62, 0, EDGE, .004)
        wb2('窗带下窗台板', 0, .34, 5.38, 4.20, .22, .12, 0, EDGE, .008)
        wb2('窗带上檐遮光板', 0, .36, 7.24, 4.20, .24, .12, 0, DARK, .008)
    elif kind == 'shelflabel':
        wb2('壁挂托架', 0, .30, 3.40, 2.10, .12, .10, 0, EDGE, .005)
        for u in (-.95, .95):
            cyl('托架斜撑', pt2(u, .30, 3.40), pt2(u, .62, 2.60), .035, 0, EDGE, 6)
        wb2('壁挂层板', 0, .62, 3.50, 2.10, .40, .06, 0, PANEL, .008)
        for i, (u, hh) in enumerate([(-.70, .34), (-.20, .42), (.32, .28), (.78, .38)]):
            wb2('层板档案盒', u, .62, 3.53+hh/2, .30, .30, hh, 1, [RED, BLUE, AMBER, TEAL][i], .003)

# ================================================================ 03 吊顶与顶部管线
for iy in range(-4, 4):
    pack('ceiling_deck_%d' % iy, '吊顶结构_%d' % iy, 'support', cut=True)
    for ix in range(-3, 3):
        x, y = ix*GRID+GRID/2, iy*GRID+GRID/2
        box('吊顶承重板', (x, y, WALL_H-.20), (GRID, GRID, .34), 1, DARK, 0)
        box('吊顶板缝压条', (x+(-1.70 if ix % 2 else 1.70), y, WALL_H-.40), (1.50, .09, .045), 0, EDGE, .004)
pack('ceiling_ring_beam', '吊顶周圈圈梁', 'support', cut=True)
for (px, py, dx, dy) in [(0, HY-.35, W, .70), (0, -(HY-.35), W, .70),
                         (HX-.35, 0, .70, D-.70), (-(HX-.35), 0, .70, D-.70)]:
    box('吊顶圈梁', (px, py, WALL_H-.45), (dx, dy, .60), 0, EDGE, .015)

pack('ceiling_service_cable_tray', '顶部电缆桥架与线缆', 'support')
for x in (-7.0, 7.0):
    box('纵向电缆桥架槽', (x, 0, 10.55), (.46, D-1.4, .17), 0, EDGE, .008)
    for dy in (-.20, .20):
        box('桥架侧边立板', (x+dy, 0, 10.66), (.04, D-1.4, .26), 0, DARK, .003)
    for yy in (-16.5, -11, -5.5, 0, 5.5, 11, 16.5):
        box('桥架吊杆', (x, yy, 11.10), (.07, .07, .95), 0, STEEL, .003)
    for j in range(4):
        cyl('桥架内线缆', (x-.13+j*.09, -(D/2-1.2), 10.60), (x-.13+j*.09, D/2-1.2, 10.60),
            .035, 0, [DARK, BLUE, RED, AMBER][j], 8)
pack('ceiling_service_pipe_run', '顶部管道与法兰', 'support')
for x, r in ((-11.2, .18), (11.2, .14)):
    cyl('顶部主管', (x, -(D/2-1.0), 10.15), (x, D/2-1.0, 10.15), r, 0, STEEL, 14)
    for yy in range(-18, 19, 3):
        cyl('管道法兰', (x-.06, yy, 10.15), (x+.06, yy, 10.15), r+.045, 0, EDGE, 14)
    for yy in range(-16, 17, 5):
        box('管道吊架', (x, yy, 10.70), (r*2+.20, .10, .95), 0, EDGE, .004)
        cyl('管道吊杆', (x, yy, 10.15+r), (x, yy, 11.05), .030, 0, STEEL, 6)
pack('ceiling_service_duct', '顶部通风管与风口', 'support')
box('主通风管', (0, 0, 10.85), (1.10, D-2.2, .62), 0, PANEL, .020)
for yy in range(-17, 18, 3):
    box('风管法兰环', (0, yy, 10.85), (1.22, .10, .74), 0, EDGE, .006)
for yy in (-13, -6, 1, 8, 15):
    box('风管风口框', (0, yy, 10.50), (.72, .90, .08), 0, DARK, .005)
    for j in range(7):
        box('风口叶片', (0, yy-.34+j*.113, 10.46), (.66, .045, .035), 0, EDGE, .003, math.radians(24))
for yy in (-16, -9, -2, 5, 12):
    for sx in (-1, 1):
        cyl('风管吊架', (sx*.62, yy, 10.85), (sx*.62, yy, 11.30), .034, 0, STEEL, 6)
pack('ceiling_lighting', '顶部灯具', 'support')
for yy in (-15, -7.5, 0, 7.5, 15):
    # 轨道在 x=0 断开，避让主通风管
    for sx in (-1, 1):
        box('灯具轨道', (sx*7.60, yy, 10.90), (13.60, .14, .10), 0, DARK, .004)
    for xx in (-12, -6, 6, 12):
        box('灯具吊座', (xx, yy, 10.80), (.20, .20, .22), 0, VOID, .005)
        box('灯具外壳', (xx, yy, 10.62), (1.35, .34, .18), 0, PANEL, .008)
        box('灯具发光面', (xx, yy, 10.51), (1.13, .24, .030), 3, HI2, .003)

# ================================================================ 04 区域固定设施
def chair(name, loc, rot=0.0):
    x, y = loc[0], loc[1]
    sa, ca = math.sin(rot), math.cos(rot)
    box(name+'_气压柱', (x, y, .42), (.11, .11, .40), 0, STEEL, .008)
    box(name+'_坐垫', (x, y, .50), (.58, .56, .11), 1, HULL, .020)
    box(name+'_座前沿', (x-.26*ca, y-.26*sa, .465), (.10, .50, .06), 1, DARK, .008, rot)
    box(name+'_靠背', (x+.25*sa, y-.25*ca, .98), (.54, .12, .78), 1, HULL, .020, rot)
    box(name+'_腰托', (x+.24*sa, y-.24*ca, .70), (.42, .09, .18), 0, DARK, .008, rot)
    box(name+'_头枕杆', (x+.28*sa, y-.28*ca, 1.42), (.10, .07, .16), 0, DARK, .004, rot)
    box(name+'_头枕', (x+.30*sa, y-.30*ca, 1.56), (.38, .10, .22), 1, HULL, .014, rot)
    for s in (-1, 1):
        cyl(name+'_扶手', (x+s*.31*math.cos(rot)+.10*sa, y+s*.31*sa-.10*math.cos(rot), .70),
            (x+s*.31*math.cos(rot)-.12*sa, y+s*.31*sa+.12*math.cos(rot), .78), .032, 0, DARK, 8)
    for j in range(5):
        a = j*math.pi*2/5+rot
        ex, ey = x+.30*math.cos(a), y+.30*math.sin(a)
        box(name+'_五星脚', ((x+ex)/2, (y+ey)/2, .07), (.34, .07, .06), 0, DARK, .006, a)
        cyl(name+'_滚轮', (ex, ey, .03), (ex, ey, .09), .045, 0, VOID, 8)
    cyl(name+'_脚踏圈', (x, y, .16), (x, y, .20), .28, 0, EDGE, 16)

def monitor(name, loc, rot, wide=True):
    """参考图屏幕：宽屏横置 / 竖屏副显，屏面冷青发光 + 深色边框 + 支柱。"""
    x, y, z = loc
    sa, ca = math.sin(rot), math.cos(rot)
    box(name+'_底座', (x, y, z), (.32, .24, .038), 0, VOID, .008, rot)
    cyl(name+'_立杆', (x, y, z), (x, y, z+.26), .032, 0, DARK, 8)
    cx, cy = x-.09*sa, y+.09*ca
    sw, sh = (.80, .46) if wide else (.36, .62)
    box(name+'_屏壳', (cx, cy, z+.52), (sw, .055, sh), 0, VOID, .010, rot)
    box(name+'_屏框', (cx+.030*sa, cy-.030*ca, z+.52), (sw-.045, .020, sh-.045), 0, DARK, .004, rot)
    box(name+'_发光面', (cx+.045*sa, cy-.045*ca, z+.52), (sw-.105, .018, sh-.105), 3, HI2, .003, rot)
    rows = 6 if wide else 8
    for r in range(rows):
        w = (sw-.22)*(1.0-.06*r) if wide else (sw-.16)
        box(name+'_界面条', (cx+.062*sa, cy-.062*ca, z+.52+sh*.30-r*.062), (w, .012, .024), 3, BLUE, .001, rot)
    box(name+'_颈部', (cx, cy, z+.27), (.14, .11, .06), 0, DARK, .004, rot)

def desk_lamp(name, loc, rot):
    x, y, z = loc
    ca, sa = math.cos(rot), math.sin(rot)
    box(name+'_座', (x, y, z), (.22, .16, .030), 0, DARK, .006, rot)
    cyl(name+'_臂下', (x, y, z), (x+.06*ca, y+.06*sa, z+.34), .020, 0, EDGE, 8)
    box(name+'_悬臂', (x+.24*ca, y+.24*sa, z+.38), (.44, .05, .05), 0, EDGE, .004, rot)
    box(name+'_灯罩', (x+.44*ca, y+.44*sa, z+.33), (.20, .14, .09), 0, DARK, .006, rot)
    box(name+'_暖光', (x+.44*ca, y+.44*sa, z+.28), (.15, .10, .018), 3, AMBER, .002, rot)

def binder_stack(name, loc, rot=0.0, n=5):
    x, y = loc[0], loc[1]; z = loc[2] if len(loc) > 2 else 0.0
    ca, sa = math.cos(rot), math.sin(rot)
    for j in range(n):
        box(name+'_档案夹', (x-.14*ca+j*.07*ca, y-.14*sa+j*.07*sa, z+.075),
            (.055, .29, .15), 1, [RED, BLUE, AMBER, TEAL, HI][j % 5], .003, rot)

def work_cluster(tag, cx, cy, rot=0.0):
    """一组工位：2 座并排长条工台 + 双屏 + 椅 + 主机 + 台灯 + 档案 + 隔断屏。"""
    ca, sa = math.cos(rot), math.sin(rot)
    def P(u, v, z=0.0): return (cx+u*ca-v*sa, cy+u*sa+v*ca, z)
    pack('work_cluster_'+tag, '工位_'+tag, 'facilities')
    box('工台台面', P(0, 0, .745), (5.80, 1.62, .075), 1, MID, .010, rot)
    box('台面前缘翻边', P(0, .825, .705), (5.80, .055, .095), 1, HULL, .008, rot)
    box('工台前挡板', P(0, .78, .52), (5.80, .05, .42), 1, DARK, .006, rot)
    box('工台背挡板', P(0, -.78, .40), (5.80, .05, .58), 0, DARK, .006, rot)
    for u in (-2.72, 2.72):
        box('工台端立板', P(u, 0, .37), (.06, 1.50, .74), 0, DARK, .008, rot)
    box('工台横撑', P(0, 0, .58), (5.60, .09, .09), 0, EDGE, .005, rot)
    box('台下走线槽', P(0, -.30, .28), (5.40, .22, .16), 0, EDGE, .006, rot)
    for u in (-2.0, 0.0, 2.0):
        cyl('走线下引线束', P(u, -.30, .28), P(u, -.30, .02), .045, 0, DARK, 8)
    box('工位隔断屏框', P(0, -.62, 1.22), (3.60, .06, .70), 0, VOID, .008, rot)
    box('隔断吸音面', P(0, -.58, 1.22), (3.46, .04, .60), 1, HULL, .004, rot)
    for u in (-1.35, -0.45, 0.45, 1.35):
        box('隔断挂条', P(u, -.55, 1.22), (.14, .03, .52), 1, TEAL, .002, rot)
    for s in (-1, 1):
        u = s*1.45
        monitor('工位屏_%d' % s, P(u-.34, -.22, .785), rot, True)
        monitor('工位副屏_%d' % s, P(u+.46, -.24, .785), rot+math.radians(20)*s, False)
        box('键盘', P(u, .18, .79), (.42, .15, .028), 0, DARK, .004, rot)
        box('鼠标垫', P(u+.40, .24, .775), (.26, .19, .012), 1, VOID, .003, rot)
        box('鼠标', P(u+.40, .24, .79), (.09, .06, .030), 0, DARK, .006, rot)
        box('主机箱', P(u-.62, -.52, .34), (.22, .50, .62), 1, HULL, .012, rot)
        box('主机前发光条', P(u-.62, -.27, .34), (.05, .03, .48), 3, BLUE, .002, rot)
        box('主机顶散热格', P(u-.62, -.52, .66), (.16, .40, .015), 0, VOID, .002, rot)
        desk_lamp('台灯_%d' % s, P(u+.62, -.12, .77), rot)
        binder_stack('档案_%d' % s, P(u+.92, -.30), rot, 4)
        box('文件托盘', P(u-.92, .30, .79), (.34, .26, .07), 0, EDGE, .006, rot)
        box('笔筒', P(u+.86, .32, .80), (.10, .10, .12), 0, EDGE, .006, rot)
        box('水杯', P(u+.60, .34, .80), (.08, .08, .11), 1, HI2, .006, rot)
        box('笔记本', P(u-.30, .30, .78), (.28, .21, .015), 1, WHITE, .003, rot)
        chair('工位椅_%d' % s, P(u, 1.28), rot+math.radians(180))
    for du in (-2.10, 2.10):
        box('台下抽柜', P(du, -.20, .33), (.50, .58, .64), 1, HULL, .010, rot)
        for j in range(3):
            box('抽柜面板', P(du, .095, .14+j*.19), (.46, .02, .16), 0, DARK, .004, rot)
            cyl('抽柜把手', P(du, .115, .14+j*.19), P(du, .150, .14+j*.19), .020, 0, STEEL, 6)
    box('工位资料盒', P(-2.20, -.28, .86), (.60, .34, .22), 1, TAN, .006, rot)
    box('文件立架', P(-1.55, -.46, .92), (.46, .28, .30), 0, EDGE, .006, rot)
    for j in range(4):
        box('立架档案夹', P(-1.72+j*.11, -.46, .96), (.045, .24, .22), 1, [BLUE, RED, TEAL, AMBER][j], .003, rot)
    box('工位绿植盆', P(2.60, -.42, .80), (.22, .22, .16), 0, VOID, .010, rot)
    for j in range(6):
        a = j*math.pi/3
        box('工位绿植叶', P(2.60+.13*math.cos(a), -.42+.13*math.sin(a), .94), (.14, .05, .20),
            1, GREEN if j % 2 else TEAL, .002, rot+a)

for tag, cx, cy, rot in [('a', -6.5, -9.7, 0.0), ('b', 6.5, -9.7, math.pi),
                         ('c', -6.5, 4.3, 0.0), ('d', 6.5, 4.3, math.pi)]:
    work_cluster(tag, cx, cy, rot)

# ---- 西墙档案柜带（+X 朝内，轴对齐）
# 🔴 西墙 6 车道占 y∈[-15,15] ⇒ 柜带只放南北两端非车道段 [+15.2,+19.8] / [-19.8,-15.2]
pack('filing_run_west', '西墙档案柜带', 'facilities')
# 每个非车道角段（5m）内排满 4 组矮柜，其中近角一组做高柜，还原参考图的柜墙密度
CB_SEG = [(16.30, 17.35, 17.95, 18.55), (-18.55, -17.95, -17.35, -16.30)]
for seg in CB_SEG:
    y0, y1 = min(seg), max(seg); yc = (y0+y1)/2
    ylen = (y1-y0)+1.20          # 🔴 收窄：不得触到 y=±15.0 的车道边界
    box('档案柜带背衬', (-14.30, yc, 1.42), (.10, ylen, 2.84), 0, VOID, .008)
    box('档案柜带顶部托板', (-14.34, yc, 2.86), (.62, ylen+.20, .06), 0, EDGE, .008)
    for yy in seg:
        box('柜体', (-14.30, yy, .66), (.68, 1.02, 1.32), 1, PANEL, .012)
        box('柜顶压边', (-14.30, yy, 1.335), (.73, 1.07, .03), 0, EDGE, .006)
        for j in range(4):
            z = .17+j*.323
            box('抽屉面板', (-13.955, yy, z), (.02, .94, .276), 0, HULL, .004)
            box('抽面拉手', (-13.930, yy, z), (.035, .44, .035), 0, STEEL, .004)
            box('标签插槽', (-13.942, yy, z+.115), (.012, .30, .06), 1, HI2, .002)
        box('柜顶收纳箱', (-14.30, yy, 1.52), (.58, .82, .36), 1, TAN if yy < 0 else CARD, .006)
    # 近角高柜（2.84m），补足垂直层次
    hy = y0-.62 if y0 < 0 else y1+.62
    box('高柜柜体', (-14.30, hy, 1.42), (.70, .96, 2.84), 1, PANEL, .014)
    for z in (.62, 1.42, 2.22):
        box('高柜门缝', (-13.945, hy, z), (.02, .86, .04), 0, VOID, .002)
        cyl('高柜把手', (-13.92, hy-.24, z), (-13.90, hy-.24, z), .020, 0, STEEL, 6)
    box('高柜顶灯条', (-14.30, hy, 2.90), (.62, .88, .05), 3, BLUE, .002)
    binder_stack('柜顶档案', (-14.34, yc, 2.90), math.pi/2, 5)
    for yy in (y0-1.10, y1+1.10):
        box('档案柜侧立板', (-14.30, yy, .72), (.72, .08, 1.44), 0, EDGE, .008)

# ---- 南墙配电柜带
pack('power_cabinet_bank_south', '南墙配电柜带', 'facilities')
box('配电柜底座梁', (-13.4, -19.34, .12), (3.00, .74, .24), 0, VOID, .010)
for xx in (-14.3, -13.4, -12.5):
    box('落地配电柜', (xx, -19.30, 1.24), (.86, .70, 2.24), 1, PANEL, .014)
    box('柜门缝', (xx-.43, -18.95, 1.24), (.03, .03, 2.00), 0, VOID, .002)
    box('柜体蓝窗', (xx+.20, -18.94, 1.92), (.36, .03, .38), 3, BLUEB, .003)
    for z in (0.78, 0.50, 0.22):
        box('柜体通风百叶', (xx, -18.94, z), (.70, .03, .06), 0, DARK, .002)
    cyl('柜门把手', (xx+.36, -18.90, 1.30), (xx+.36, -18.80, 1.30), .026, 0, STEEL, 6)
box('配电母排槽', (-13.4, -19.35, 2.52), (3.10, .44, .22), 0, EDGE, .010)
for xx in (-14.2, -13.4, -12.6):
    cyl('母排出线', (xx, -19.20, 2.64), (xx, -19.20, 3.34), .055, 0, DARK, 8)
box('配电区标牌', (-13.4, -19.02, 3.62), (1.60, .06, .40), 0, VOID, .006)
box('配电区标识发光面', (-13.4, -18.98, 3.62), (1.30, .03, .22), 3, AMBER, .003)

# ---- 打印机与耗材位
pack('printer_station', '打印机与耗材位', 'facilities')
box('打印机柜体', (-10.6, -19.05, .62), (.92, .74, 1.24), 1, PANEL, .014)
box('打印机上部机组', (-10.6, -19.05, 1.44), (.86, .68, .42), 0, HULL, .012)
box('打印机出纸口', (-10.6, -18.70, 1.20), (.62, .05, .14), 0, VOID, .004)
box('打印机操作面', (-10.6, -18.68, 1.50), (.40, .03, .22), 3, CYAN, .003)
for j in range(3):
    box('打印纸仓', (-10.6, -19.05, .30+j*.28), (.78, .05, .20), 0, DARK, .004)
box('备用纸箱', (-11.50, -19.15, .28), (.60, .48, .54), 1, TAN, .008)
box('备用纸箱', (-11.50, -19.15, .84), (.52, .42, .50), 1, CARD, .008)
# 🔴 耗材架原置于 x=-9.45 ⇒ 落入 south 车道墙件 k=-2（x∈[-10,-5]）⇒ 改为打印机上方壁挂
box('耗材架', (-10.60, -19.48, 2.12), (.90, .30, .26), 0, EDGE, .008)
for i, xx in enumerate((-10.87, -10.60, -10.33)):
    box('墨盒盒', (xx, -19.48, 2.32), (.20, .26, .14), 1, [RED, BLUE, AMBER][i], .003)

# ---- 东墙整备台
# 🔴 东墙 6 车道占 y∈[-15,15] ⇒ 整备台移到东南非车道段（k=-4，y∈[-20,-15]）
pack('prep_bench_east', '东墙整备台', 'facilities')
BENCH_Y = -17.5
box('整备台台面', (14.05, BENCH_Y, .92), (.86, 3.40, .06), 1, PANEL, .010)
for dy in (-1.5, 0.0, 1.5):
    box('整备台支腿', (14.35, BENCH_Y+dy, .45), (.08, .10, .90), 0, DARK, .006)
box('整备台下横撑', (14.05, BENCH_Y, .16), (.80, 3.20, .08), 0, EDGE, .005)
box('整备台背板', (14.48, BENCH_Y, 1.34), (.08, 3.40, .78), 0, VOID, .008)
for dy in (-1.2, 0.0, 1.2):
    box('台上工具架', (14.30, BENCH_Y+dy, 1.86), (.30, .80, .10), 0, EDGE, .006)
    box('工具挂板', (14.44, BENCH_Y+dy, 1.52), (.05, .74, .52), 1, HULL, .003)
    for j in range(4):
        box('挂具', (14.40, BENCH_Y+dy-.26+j*.17, 1.52), (.04, .07, .30), 0, STEEL, .003)
box('整备台料盒', (14.05, BENCH_Y-1.4, 1.06), (.60, .60, .22), 1, TAN, .006)
box('整备台仪器', (14.05, BENCH_Y+1.4, 1.14), (.56, .60, .38), 0, HULL, .010)
box('仪器显示面', (13.78, BENCH_Y+1.4, 1.22), (.03, .44, .22), 3, CYAN, .003)

# ---- 置物架
# 🔴 原在北墙 k=1 车道墙件（x∈[5,10]）⇒ 移到南墙非车道段（k=2，x∈[10,15]）
pack('shelving_south', '置物架', 'facilities')
SX, SY = 12.50, -19.20
for xx in (SX-0.85, SX+0.85):
    box('置物架侧板', (xx, SY, 1.16), (.06, .60, 2.32), 0, DARK, .008)
for z in (0.16, .72, 1.28, 1.84, 2.32):
    box('置物架层板', (SX, SY, z), (1.80, .58, .05), 1, PANEL, .008)
for z in (.88, 1.44, 2.00):
    binder_stack('架上层档案', (SX-0.45, SY, z+.03), 0, 5)
    binder_stack('架上层档案', (SX+0.55, SY, z+.03), 0, 5)
box('架上资料盒', (SX, SY, .96), (.50, .44, .38), 1, TAN, .006)
box('架上收纳箱', (SX, SY, 1.52), (.46, .42, .36), 1, CARD, .006)
box('架上小盆栽', (SX, SY, 2.44), (.22, .22, .16), 0, VOID, .010)
for j in range(7):
    a = j*math.pi*2/7
    box('架上叶片', (SX+.14*math.cos(a), SY+.14*math.sin(a), 2.58), (.16, .06, .20),
        1, GREEN if j % 2 else TEAL, .002)

# ---- 北墙储物柜组
pack('locker_bank_north', '北墙储物柜组', 'facilities')
for xx in (12.0, 13.05):
    box('储物柜柜体', (xx, 19.15, 1.06), (.96, .64, 2.12), 1, PANEL, .014)
    box('柜门缝', (xx, 18.83, 1.06), (.03, .03, 2.02), 0, VOID, .002)
    for z in (1.86, 1.62):
        box('柜门通风百叶', (xx, 18.81, z), (.72, .03, .07), 0, DARK, .002)
    box('柜门编号牌', (xx, 18.81, 1.30), (.34, .03, .16), 3, BLUEB, .002)
    cyl('柜门锁扣', (xx+.36, 18.79, 1.06), (xx+.36, 18.69, 1.06), .024, 0, STEEL, 6)
    for z in (.34, 1.06, 1.78):
        cyl('柜门铰链', (xx-.42, 18.81, z), (xx-.42, 18.69, z), .030, 0, EDGE, 6)
box('储物柜顶压条', (12.5, 19.15, 2.14), (2.10, .70, .04), 0, EDGE, .006)
box('柜顶收纳箱', (12.15, 19.15, 2.36), (.62, .50, .40), 1, TAN, .006)
box('柜顶收纳箱', (12.95, 19.15, 2.34), (.56, .48, .36), 1, CARD, .006)

# ---- 饮水与箱货区
pack('water_and_supply_corner', '饮水与箱货区', 'facilities')
box('饮水机柜体', (13.90, 16.60, .55), (.44, .44, 1.10), 0, PANEL, .012)
box('饮水机取水腔', (13.68, 16.60, .86), (.06, .30, .30), 0, VOID, .004)
cyl('取水龙头', (13.62, 16.60, .92), (13.50, 16.60, .92), .020, 0, STEEL, 6)
cyl('饮水机水桶', (13.90, 16.60, 1.36), (13.90, 16.60, 1.68), .155, 0, CYAN, 12)
cyl('水桶桶盖', (13.90, 16.60, 1.68), (13.90, 16.60, 1.72), .075, 0, BLUE, 10)
for j in range(3):
    box('箱货托盘', (12.30, 15.0+j*1.05, .07), (1.10, .92, .14), 0, EDGE, .006)
    box('箱货纸箱', (12.30, 15.0+j*1.05, .44), (.92, .78, .60), 1, TAN if j % 2 else CARD, .008)
    box('箱货封条', (12.30, 15.0+j*1.05, .78), (.96, .10, .03), 1, HI2, .002)
for yy in (14.30, 17.30):
    box('货架立柱', (10.85, yy, .90), (.07, .07, 1.80), 0, DARK, .006)
for z in (0.95, 1.78):
    box('货架横梁', (10.85, 15.80, z), (.08, 3.20, .08), 0, EDGE, .006)
box('货架层板', (10.85, 15.80, 1.85), (.70, 3.10, .06), 1, PANEL, .008)

# ---- 图腾立柱
# 🔴 原在西墙 y=6.20 ⇒ 正对 west 车道墙件 ⇒ 移到西北角自由位（车道区外）
pack('totem_column', '图腾立柱', 'facilities')
x, y = -11.60, 17.20
box('图腾基座', (x, y, .12), (.86, .86, .24), 0, VOID, .010)
box('图腾柱身', (x, y, 1.42), (.56, .56, 2.60), 1, INDIGO, .012)
for z in (.60, 1.42, 2.24):
    box('图腾环箍', (x, y, z), (.62, .62, .09), 0, EDGE, .006)
for z in (.95, 1.42, 1.89):
    box('图腾发光面', (x-.29, y, z), (.02, .34, .30), 3, BLUE, .002)
    box('图腾发光面', (x, y+.29, z), (.34, .02, .30), 3, BLUE, .002)
box('图腾冠部', (x, y, 2.83), (.62, .62, .30), 0, DARK, .010)
box('图腾冠灯', (x, y, 2.70), (.40, .40, .04), 3, HI2, .003)

# ---- 周圈绿植
# 🔴 全部落在「四角非车道区」或「室内空档」，绝不进入任何门位车道带
pack('planting_perimeter', '周圈绿植', 'facilities')
PLANTS = [(-12.90,  15.60, 1.00), (-11.00,  18.90, .90),   # 西北角
          ( 14.40,  19.10, 1.00), ( 14.40,  17.60, .95),   # 东北角
          (-12.90, -15.60, 1.00), ( 12.80, -15.60, .95),   # 西南 / 东南角
          (-4.20,  -15.00, 1.00), (  4.20, -15.00, .90),   # 室内南侧
          (-4.20,   15.00, .95), (  4.20,  15.00, .90)]    # 室内北侧
for i, (px, py, sc) in enumerate(PLANTS):
    box('绿植盆体', (px, py, .26*sc), (.62*sc, .62*sc, .52*sc), 1, VOID, .012)
    box('绿植盆口沿', (px, py, .53*sc), (.68*sc, .68*sc, .06*sc), 0, EDGE, .004)
    box('种植基质', (px, py, .565*sc), (.54*sc, .54*sc, .05*sc), 1, CARD, .002)
    cyl('绿植主干', (px, py, .58*sc), (px, py, 1.00*sc), .045*sc, 0, CARD, 8)
    for j in range(9):
        a = j*math.pi*2/9+i*.3; r = .30*sc
        box('绿植叶片', (px+r*math.cos(a), py+r*math.sin(a), (1.02+j*.03)*sc),
            (.30*sc, .11*sc, .16*sc), 1, GREEN if j % 2 else TEAL, .003, a)

# ================================================================ 05 环境支持
pack('wall_top_service', '墙顶管线收口', 'support')
for (px, py, dx, dy) in [(0, HY-.40, W-.6, .18), (0, -(HY-.40), W-.6, .18),
                         (HX-.40, 0, .18, D-.6), (-(HX-.40), 0, .18, D-.6)]:
    box('墙顶服务槽', (px, py, 11.55), (dx if dx > 1 else .18, dy if dy > 1 else .18, .70), 0, EDGE, .010)
pack('corner_guard', '转角护柱与墙裙', 'support')
for sx in (-1, 1):
    for sy in (-1, 1):
        cx, cy = sx*(HX-.42), sy*(HY-.42)
        box('转角护柱', (cx, cy, 1.10), (.30, .30, 2.20), 1, PANEL, .010)
        for z in (.35, 1.10, 1.85):
            box('护柱反光箍', (cx, cy, z), (.34, .34, .10), 0, AMBER, .003)
        box('护柱底座', (cx, cy, .06), (.46, .46, .12), 0, VOID, .006)
# 🔴 墙裙原横贯全宽（W-1.6）⇒ 会跨过 north/south 门位车道 k∈{-2,-1,0,1}
#    ⇒ 拆为东西两段（各 4.0m，落在非车道段 x∈[±10.2,±14.2]），彻底避开车道区
for sy in (-1, 1):
    for sx in (-12.20, 12.20):
        box('墙裙防撞条', (sx, sy*(HY-.38), .70), (4.00, .12, .22), 0, EDGE, .008)
        for j in range(5):
            box('墙裙反光块', (sx-1.60+j*.80, sy*(HY-.42), .70), (.34, .04, .14), 0, AMBER, .002)
pack('floor_service', '地面管线与检修', 'support')
for xx in (-9.0, 9.0):
    box('地面纵向线槽', (xx, 0, .052), (.26, D-2.0, .022), 0, EDGE, .004)
    for yy in range(-18, 19, 4):
        box('线槽检查盖', (xx, yy, .058), (.34, .60, .020), 1, DARK, .004)
for yy in (-13.0, 13.0):
    box('地面横向线槽', (0, yy, .050), (W-3.0, .22, .020), 0, EDGE, .004)

# ================================================================ 灯光（仅展示层）
def area(name, loc, power, color, size, target):
    data = bpy.data.lights.new(name, 'AREA'); data.energy = power; data.color = color
    data.shape = 'DISK'; data.size = size
    o = bpy.data.objects.new(name, data); display.objects.link(o); o.location = loc
    o.rotation_euler = (Vector(target)-o.location).to_track_quat('-Z', 'Y').to_euler(); return o

area('主光_冷白顶光', (-16, -40, 46), 7000, (.54, .70, 1), 30, (0, 0, 0))
area('背缘冷蓝', (30, 24, 26), 4200, (.18, .42, 1), 20, (0, 0, -1))
area('前部柔光', (26, -30, 12), 2200, (.34, .54, 1), 22, (0, 0, -2))
area('顶部补光', (0, 0, 30), 2600, (.46, .64, 1), 26, (0, 0, 0))
area('北墙洗墙', (0, 14, 11), 1200, (.40, .60, 1), 12, (0, 20, 3))
area('南墙洗墙', (0, -14, 11), 1200, (.40, .60, 1), 12, (0, -20, 3))
area('东墙洗墙', (9, 0, 11), 1000, (.38, .58, 1), 12, (15, 0, 3))
area('西墙洗墙', (-9, 0, 11), 1000, (.38, .58, 1), 12, (-15, 0, 3))
for cx, cy in [(-6.5, -9.7), (6.5, -9.7), (-6.5, 4.3), (6.5, 4.3)]:
    area('工位工作光_%d_%d' % (cx, cy), (cx, cy, 6.6), 1050, (1, .84, .58), 5, (cx, cy, .8))
area('门头补光', (2.5, 12, 6.0), 1400, (.80, .88, 1), 5, (2.5, 20, 2.6))

# ================================================================ 相机
def camera(name, loc, target, scale):
    d = bpy.data.cameras.new(name); o = bpy.data.objects.new(name, d); display.objects.link(o)
    o.location = loc
    o.rotation_euler = (Vector(target)-o.location).to_track_quat('-Z', 'Y').to_euler()
    d.type = 'ORTHO'; d.ortho_scale = scale; d.clip_end = 500; return o

cam = camera('参考镜头_剖视全景', (-42, -52, 46), (0, 0, 3.0), 58)
cam_work = camera('参考镜头_工位近景', (-13.0, -17.0, 6.2), (-6.5, -9.7, .95), 12)
cam_peri = camera('参考镜头_周圈设施', (-4.8, -3.0, 4.6), (-14.2, -17.4, 1.10), 16)
cam_top = camera('参考镜头_顶视', (0, 0, 100), (0, 0, 0), 51)
cam_complete = camera('参考镜头_完整结构', (-42, -52, 58), (0, 0, 3.0), 68)

# ================================================================ QA 实测
bpy.context.view_layer.update()
wb = json.loads(WHITEBOX.read_text(encoding='utf-8'))

def bounds(objects):
    pts = [o.matrix_world@Vector(v) for o in objects for v in o.bound_box]
    return [[round(min(p[i] for p in pts), 5) for i in range(3)],
            [round(max(p[i] for p in pts), 5) for i in range(3)]]

fb = bounds(floor_bases)
door_pkg = next(q for q in packages if q['slug'] == 'door_wall')
if door_pkg['wall_side'] in ('east', 'west'):
    # 门洞开在 x=+15 墙的 y 走向上：净宽沿 y
    dj = sorted([bounds([o]) for o in door_pkg['items'] if o.name.startswith('门洞边柱')],
                key=lambda b: b[0][1])
    door_w = round(dj[1][0][1]-dj[0][1][1], 4)
else:
    dj = sorted([bounds([o]) for o in door_pkg['items'] if o.name.startswith('门洞边柱')],
                key=lambda b: b[0][0])
    door_w = round(dj[1][0][0]-dj[0][1][0], 4)
dlintel = next(o for o in door_pkg['items'] if o.name.startswith('门洞过梁'))
dsill = next(o for o in door_pkg['items'] if o.name.startswith('门槛'))
door_measures = {'axis': 'y' if door_pkg['wall_side'] in ('east', 'west') else 'x', 'width': door_w,
                 'bottom': round(bounds([dsill])[1][2], 4),
                 'lintel': round(bounds([dlintel])[0][2], 4)}
std_walls = [q for q in packages if q['slug'].startswith('wall_')]
perimeter_ok = True
for q in std_walls:
    b = bounds(q['items'])
    on_n = abs(b[0][1]-HY) < .40 or abs(b[1][1]-HY) < .40
    on_s = abs(b[0][1]+HY) < .40 or abs(b[1][1]+HY) < .40
    on_e = abs(b[0][0]-HX) < .40 or abs(b[1][0]-HX) < .40
    on_w = abs(b[0][0]+HX) < .40 or abs(b[1][0]+HX) < .40
    if not (on_n or on_s or on_e or on_w): perimeter_ok = False
armor_pkg = next(q for q in packages if q['slug'] == 'wall_north_1')
armor_o = next(o for o in armor_pkg['items'] if o.name.startswith('内嵌装甲板'))
armor_protrusion = round((HY-WALL_T/2)-bounds([armor_o])[0][1], 4)
interior_arch = [q['slug'] for q in packages if q['category'] == 'architecture'
                 and not q['slug'].startswith('wall_') and q['slug'] != 'door_wall']
cluster_pkgs = [q for q in packages if q['slug'].startswith('work_cluster_')]
# 家具越界实测：所有设施/支持类包不得穿出结构墙内表面
out_of_bounds = []
for q in packages:
    if q['category'] not in ('facilities', 'support'): continue
    b = bounds(q['items'])
    if (b[0][0] < -HX-WALL_T/2-.01 or b[1][0] > HX+WALL_T/2+.01
            or b[0][1] < -HY-WALL_T/2-.01 or b[1][1] > HY+WALL_T/2+.01):
        out_of_bounds.append((q['slug'], b))
print('OOB_DIAG', json.dumps(out_of_bounds, ensure_ascii=False), flush=True)

# 门位净空实测：门位车道带（north/south k∈{-2,-1,0,1}；east/west k∈{-3..2}）内
# 不得有「高过 0.5m 的固定设施」——运行时这些墙件会按关卡门位换成门洞墙件，
# 家具若压在上面就会堵门。这是防堵门的硬断言。
LANE_BANDS = []
for k in (-2, -1, 0, 1):
    x0 = k*GRID
    LANE_BANDS.append((x0, x0+GRID, HY-WALL_T/2-1.30, HY+WALL_T/2+0.30))
    LANE_BANDS.append((x0, x0+GRID, -(HY+WALL_T/2+0.30), -(HY-WALL_T/2-1.30)))
for k in (-3, -2, -1, 0, 1, 2):
    y0 = k*GRID
    LANE_BANDS.append((HX-WALL_T/2-1.30, HX+WALL_T/2+0.30, y0, y0+GRID))
    LANE_BANDS.append((-(HX+WALL_T/2+0.30), -(HX-WALL_T/2-1.30), y0, y0+GRID))

def _ov(b, r):
    return not (b[1][0] < r[0] or b[0][0] > r[1] or b[1][1] < r[2] or b[0][1] > r[3])

lane_conflicts = []
for q in packages:
    if q['category'] not in ('facilities', 'support'): continue
    for o in q['items']:
        b = bounds([o])
        # 只统计「门洞通行带」内的物件：z ∈ [0.30, 3.00]（门槛底 → 过梁底之上）
        # 吊顶/桥架/风管/墙顶收口都在 ~10m 以上，不构成通行障碍 ⇒ 排除
        if b[1][2] <= .30 or b[0][2] >= 3.00: continue
        for r in LANE_BANDS:
            if _ov(b, r): lane_conflicts.append(q['slug'] + ':' + o.name); break
print('LANE_DIAG', json.dumps(lane_conflicts, ensure_ascii=False), flush=True)

checks = {
    'template_dimensions_locked': wb['size_m'] == [30.0, 40.0],
    'floor_extent_measured': fb[0] == [-15.0, -20.0, -0.32] and fb[1] == [15.0, 20.0, 0.0],
    'floor_tiles_48_all_5m': len(floor_bases) == 48 and all(
        abs(o.dimensions.x-5) < .0001 and abs(o.dimensions.y-5) < .0001 for o in floor_bases),
    'visible_wall_top_11_9': abs(max(bounds([o])[1][2] for o in wall_bases)-WALL_H) < .001,
    'wall_height_consistent_with_whitebox': abs(wb['wall_height_m']-WALL_H) < .001,
    'standard_wall_bays_28': len(std_walls) == 28,
    'wall_bays_on_perimeter_only': perimeter_ok,
    'no_interior_architectural_walls': interior_arch == [],
    'facilities_inside_room_envelope': out_of_bounds == [],
    'perimeter_furniture_avoids_door_lanes': lane_conflicts == [],
    'door_opening_measured': abs(door_measures['width']-2.2) < .001
                             and abs(door_measures['bottom']-.3) < .001
                             and abs(door_measures['lintel']-2.8) < .001,
    'door_contract_matches_whitebox': all(abs(door_measures[k]-wb['door_contract'][v]) < .001
                                          for k, v in [('width', 'width_m'), ('bottom', 'bottom_z_m'),
                                                       ('lintel', 'lintel_bottom_z_m')]),
    'openable_lanes_match_whitebox': wb['openable_walls'] == ['north', 'south', 'east', 'west']
                                     and all(len(wb['wall_lane_table'][s]) == (4 if s in ('north', 'south') else 6)
                                             for s in wb['openable_walls']),
    'wall_armor_protrusion_ge_100mm': armor_protrusion >= .100,
    'work_clusters_4': len(cluster_pkgs) == 4,
    'palette_external_unique': img.packed_file is None
                               and Path(bpy.path.abspath(img.filepath)).resolve() == PALETTE.resolve(),
    'four_materials': len(bpy.data.materials) == 4,
    'all_packages_nonempty': all(q['items'] for q in packages),
    'facility_categories_present': all(any(q['category'] == c for q in packages)
                                       for c in ('architecture', 'floor', 'facilities', 'support')),
}
assert all(checks.values()), {k: v for k, v in checks.items() if not v}

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
    obj['package_id'] = 'ENV-EXPEDITION-L01-OFFICE-'+p['slug'].upper()
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
    inward = p.get('inward_normal', 'n/a')
    rec = {'package_id': 'ENV-EXPEDITION-L01-OFFICE-'+p['slug'].upper(), 'slug': p['slug'],
           'name_zh': p['title'], 'category': p['category'], 'version': 'v001', 'source_blend': BLEND,
           'collection': p['col'].name, 'objects': [o.name for o in merged], 'world_origin_m': origin,
           'local_origin': 'bottom_center',
           'forward_axis': ('inward_normal=%s (Blender world); Blender +Y maps to glTF -Z after +Y-up export'
                            % inward),
           'inward_normal_world': inward,
           'world_bounds_m': b, 'dimensions_m': [round(b[1][i]-b[0][i], 5) for i in range(3)],
           'materials': roles, 'source_piece_count': len(p['items']),
           'reference_cutaway_hidden': p['cutaway'],
           'collision_owner': p['collision_owner'], 'visual_only': p['visual_only'],
           'collision_exported': False, 'exported': False, 'dependencies': []}
    if p['slug'].startswith('wall_') or p['slug'] == 'door_wall':
        rec['wall_piece_contract'] = {'geometry_wdh_m': [GRID, WALL_H, WALL_T], 'grid_unit_m': GRID,
                                      'visual_height_m': WALL_H, 'origin': 'bottom_center',
                                      'armor_protrusion_m': armor_protrusion,
                                      'inward_normal_world': inward,
                                      'door_opening': p.get('door_opening', False)}
        rec['collision_owner'] = 'self'; rec['visual_only'] = False
    directory = PKGDIR/p['category']/p['slug']; directory.mkdir(parents=True, exist_ok=True)
    (directory/'asset_manifest.json').write_text(
        json.dumps(rec, ensure_ascii=False, indent=2)+'\n', encoding='utf-8', newline='\r\n')
    records.append(rec); p['output'] = merged

src.hide_render = True; src.hide_viewport = True
for layer in bpy.context.view_layer.layer_collection.children[root.name].children:
    if layer.name == src.name: layer.exclude = True

# 清理历史残留包目录（包改名/删除后旧目录会留在磁盘上，导致 disk_collection_count 假红）
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

manifest = {
    'schema': 'shellstorm2.room_type_art_manifest', 'schema_version': 1, 'version': 'v001',
    'template_id': 'office_60x70', 'room_type': 'COMMON_ROOM', 'block_id': 'expedition',
    'design_scope': 'scene_art',
    'asset_ledger': 'assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx::3D-场景通用',
    'room_asset_id': wb['asset_ids']['room'],
    'source_blend': BLEND, 'whitebox_source': str(WHITEBOX.relative_to(ROOT)),
    'dimensions_m': [30, 40], 'wall_visual_height_m': WALL_H, 'wall_logic_height_m': 12,
    'interior_walls': False, 'door_contract': wb['door_contract'],
    'door_lanes': {'total': 20, 'north': 4, 'south': 4, 'east': 6, 'west': 6},
    'door_wall_piece': {'reusable': True, 'authored_at': 'north wall lane x=+2.5',
                        'geometry_wdh_m': [GRID, WALL_H, WALL_T],
                        'note': '门洞墙件几何对各朝向一致；运行时按门位车道替换对应标准墙件。'
                                '本关 room_03 门在 {west,north}、room_09 门在 {north,east}，'
                                '故房型源不冻结门位、不预切四个朝向的门洞。'},
    'required_components': ['segmented floor deck tiles', 'perimeter wall bays',
                            'reusable door wall bay', 'acoustic partitions (furniture level, not architecture)',
                            'ceiling deck and perimeter ring beam',
                            'overhead cable trays / pipe runs / duct', 'ceiling light fixtures',
                            'corner guards and base protection',
                            'floor conduits, drains and zone markings'],
    'required_facilities': ['4 workstation clusters', 'filing cabinet run', 'power cabinet bank',
                            'printer station', 'prep bench', 'shelving unit', 'locker bank',
                            'water dispenser and supply corner', 'wall screens and notice boards',
                            'banner and wall emblems', 'perimeter planting', 'wall totem pylon'],
    'door_geometry_in_source': False,
    'reference_image': str(REF), 'reference_sha256': hashlib.sha256(REF.read_bytes()).hexdigest(),
    'scope': {'modifiable': 'all scene-art geometry and presentation',
              'locked': 'whitebox dimensions, floor plane, wall height, door contract, no interior walls, gameplay',
              'previous_versions_preserved': True},
    'package_count': len(records), 'output_mesh_count': len(output_meshes),
    'material_roles': roles, 'palette_texture': str(PALETTE),
    'preview_note': 'Cutaway images hide only named near-wall and ceiling-deck packages; top and complete '
                    'views additionally hide ceiling deck/services to keep the interior readable. '
                    'Complete source retains all geometry. No gameplay changes, no GLB, no engine integration.',
    'packages': records,
}
qa = {'status': 'PASS' if all(checks.values()) else 'FAIL', 'checks': checks,
      'measured': {'floor_bounds': fb, 'wall_bay_count': len(std_walls), 'door_measures': door_measures,
                   'armor_protrusion_m': armor_protrusion, 'work_clusters': len(cluster_pkgs),
                   'source_piece_count': sum(len(p['items']) for p in packages),
                   'output_meshes': len(output_meshes),
                   'output_faces': sum(len(o.data.polygons) for o in output_meshes)},
      'scope_lock': {'whitebox_sha256': hashlib.sha256(WHITEBOX.read_bytes()).hexdigest(),
                     'reference_sha256': hashlib.sha256(REF.read_bytes()).hexdigest(),
                     'method': 'all art geometry authorized for authoring; preserve whitebox and reference '
                               'by hash; measure structural contract'},
      'visual_review': {'status': 'reviewed against reference (5 views)',
                        'views': ['reference_cutaway', 'workstation_detail',
                                  'perimeter_facilities_detail', 'top_plan', 'complete_structure'],
                        'reference': 'docs/v0.1/design/refs/expedition01/办公室01.jpg',
                        'deepening': ['palette cell CYAN corrected to (3,0) — screens/light strips were '
                                      'sampling the wrong cell (orange-brown)',
                                      'ambient darkened, emission raised 6->16, blue kept as hue',
                                      'floor light-grid densified over the whole seam lattice',
                                      'wall layering re-darkened (dark body + panel armor + bright edges)',
                                      'workstation deepened: wide + portrait monitors, dual under-desk drawers',
                                      'chair given headrest and seat front lip',
                                      'filing wall rebuilt as low bank + tall corner cabinets']},
      'palette_texture': {'image': PALETTE.name, 'filepath': str(PALETTE), 'is_relative': False,
                          'packed': False, 'materials_bound': roles, 'interpolation': 'Closest',
                          'uv_map': 'PaletteUV'},
      'runtime_integration': False}

for name, data in [('room_type_manifest.json', manifest), ('component_inventory.json', records),
                   ('qa_report.json', qa)]:
    (OUT/name).write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8', newline='\r\n')
(OUT/'component_tree.txt').write_text(
    '\n'.join(p['category']+'/'+p['slug']+' -> '+p['col'].name for p in packages), encoding='utf-8')

scene.camera = cam
for area_ in bpy.context.screen.areas if bpy.context.screen else []:
    if area_.type == 'VIEW_3D':
        area_.spaces.active.region_3d.view_perspective = 'CAMERA'
        area_.spaces.active.clip_end = 500
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/BLEND), relative_remap=False)
print('SOURCE_SAVED', str(OUT/BLEND), len(records), len(output_meshes), flush=True)

# ================================================================ 渲染
# 剖视敞开顶棚：隐藏全部顶部包（吊顶板/圈梁/桥架/风管/灯具），与参考图敞开天空一致
CEIL_HIDE = ('ceiling_deck', 'ceiling_ring_beam', 'ceiling_service', 'ceiling_lighting')

def render(camera_, name, cutaway, hide_ceiling=False):
    for p in packages:
        p['col'].hide_render = ((cutaway and p['cutaway'])
                                or (hide_ceiling and p['slug'].startswith(CEIL_HIDE)))
    scene.camera = camera_; scene.render.filepath = str(RENDER/name)
    bpy.ops.render.render(write_still=True)

if not opts.no_render:
    render(cam, 'reference_cutaway.png', True, True)
    if not opts.preview:
        render(cam_work, 'workstation_detail.png', True)
        render(cam_peri, 'perimeter_facilities_detail.png', True)
        render(cam_top, 'top_plan.png', True, True)
        render(cam_complete, 'complete_structure.png', False, True)
for p in packages: p['col'].hide_render = False
scene.camera = cam
print('BUILD_COMPLETE', json.dumps(qa['measured']), flush=True)
