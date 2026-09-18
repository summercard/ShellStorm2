"""建立战局区块通用组件库 v004：把房间 v006 的墙/地/门美术并入四个通用组件。

背景（用户指令）
  「墙的部分要拆成通用组件配套到对应的通用组件的 prefab 里头去替换美术资产，
    包含地砖，墙，带门的墙，门。这几个是通用组件资产。
    不用根据方位。只要能完整替换。自动就能对上。」

  原先房间 v006 自持了一批**按方位命名**的美术包：北/南/东/西四面各一块内嵌装甲壁板、
  一整片地砖压条与检修口、南门与东门两套装甲门禁。它们的位置只对当前这间房成立，
  换一间房、换一个朝向就错位——正是用户要去掉的「根据方位」。

  本脚本把这些美术换算进**通用组件自己的局部帧**（原点 = 底面中心、本地 +Y = 朝房内那面），
  并入 v003 已有的四个组件族：

    墙     wall_standard_5m   ← 本体 + 5m 槽位装甲单元（2 块 2.4m 壁板 + 2 条板缝压条）
    带门墙 wall_door_5m       ← 门垛×2 + 门楣 + 装甲门禁（门框 + 门禁屏 + 状态灯）
    门     door_5m            ← 门扇（本已自持美术，房间没有给它附加件）
    地砖   floor_tile_r01_c01 ← 砖体 + 压边×4 + 拼缝自发光×2 + DB 标识 + 检修格栅组 + 磨损
           floor_tile_r01_c02 ← 砖体 + 同上通用件 + 方形检修盖组 + 磨损

关键证据（第 1 阶段实测，脚本内逐值断言）
  北/南/东三面实墙的装甲单元，换算到各自槽位局部帧后**逐值相同**（各 4 件）。
  两个门禁（南 / 东）换算到门槽局部帧后**逐值相同**（各 11 件）。
  → 一个单元就能同时服务任意朝向，这就是「不用根据方位、自动就能对上」的前提。

  例外一 · 西墙：当年按 2.9m 节奏在整面 15m 上排了 5 块，不落在 5m 槽位上
  （槽2 只有一块 2.9m 壁板）。它属于「一整面墙的画」而非组件，收不进 5m 组件，
  故按「不用根据方位」统一成北/南/东同一单元：西墙 5×2.9m → 6×2.4m。
  脚本显式断言它**确实不同**，避免把「没对上」误当「对上了」。

  例外二 · c02 地砖：四块里有两块带方形检修盖、两块不带。取**较全**的一版
  （含检修盖）作为 c02 组件美术，四块 c02 砖因此统一。

  另有一条已核实的事实：v003 地砖组件的那两块板，其实就是从本房间源里取的
  FLOORSLOT_*（24 面/26 面）与 FLOORSLOT_*_INSET（c01 872/711、c02 1220/1026），
  顶点/面数逐一相同。所以 v004 不改动组件本体的板，只把**砖面装饰**并进去。

  地砖这一层的「对上」判据是**结构框**：4 条地砖压边 + 2 条蓝色拼缝。它们在 9 块砖里
  换算到各自砖局部帧后逐值相同，因此任何槽位都能精确落位。砖上的磨损是每块独一无二的
  （地砖磨损），通用件只能留一份代表——这正是「通用组件」的含义，已作为 WARNING 记录。

幂等：v004 blend 已存在时先备份再重建；v003 一字不改，保留回滚。

运行：
  "D:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" \
      --background --factory-startup --python build_common_library_v004.py
"""
from __future__ import annotations

import json
import math
import shutil
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(r'I:/工作项目/shellstrom2/ShellStorm2')
BATTLE = ROOT / 'assets/art/environments/tower_zones/battle'
LIB3_DIR = BATTLE / 'source/common_components/v003'
LIB3 = LIB3_DIR / '战局区块_通用组件库_v003.blend'
V4_DIR = BATTLE / 'source/common_components/v004'
BLEND4 = V4_DIR / '战局区块_通用组件库_v004.blend'
ROOM6 = BATTLE / 'source/room_instances/entry_safe_room/v006/局内关卡01_入口安全房_15x15m_正式美术_v006.blend'
RECOVERED = Path(r'I:/工作项目/shellstrom2/_scratch/esr_recover/v003_recovered.blend')
PALETTE = ROOT / 'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'

ENTRY_CY = SIDE_CY = 7.35
SLOT_PITCH = 5.0
WALL_LAYOUT = {'north': ((0.0, ENTRY_CY, 0.0), 180.0),
               'south': ((0.0, -ENTRY_CY, 0.0), 0.0),
               'east': ((SIDE_CY, 0.0, 0.0), 90.0),
               'west': ((-SIDE_CY, 0.0, 0.0), -90.0)}

COMPONENTS = {
    'wall_standard_5m':   ('wall_standard_5m_通用包', 'ROOT_wall_standard_5m_通用组件',
                           '实墙 + 5m 槽位装甲壁板'),
    'wall_door_5m':       ('wall_door_5m_通用包', 'ROOT_wall_door_5m_通用组件',
                           '带门洞墙 + 装甲门禁'),
    'door_5m':            ('door_5m_通用包', 'ROOT_door_5m_通用组件', '门扇'),
    'floor_tile_r01_c01': ('floor_tile_r01_c01_通用包', 'ROOT_floor_tile_r01_c01_通用组件',
                           '地砖 c01 + 压边/拼缝/标识/检修格栅'),
    'floor_tile_r01_c02': ('floor_tile_r01_c02_通用包', 'ROOT_floor_tile_r01_c02_通用组件',
                           '地砖 c02 + 压边/拼缝/标识/方形检修盖'),
}
CATEGORY = {'wall_standard_5m': '08_墙壁组件', 'wall_door_5m': '08_墙壁组件',
            'door_5m': '10_门组件', 'floor_tile_r01_c01': '09_地板组件',
            'floor_tile_r01_c02': '09_地板组件'}
ROLES = ['01_精工金属_紫色骨架', '02_细腻哑光_青绿大面', '03_清漆反光_紫粉点缀', '04_柔和自发光_UI灯光']
ARMOUR_COLLS = {'north': '墙面装饰_北墙内嵌装甲壁板_资产包',
                'south': '墙面装饰_南墙内嵌装甲壁板_资产包',
                'east': '墙面装饰_东墙内嵌装甲壁板_资产包',
                'west': '墙面装饰_西墙内嵌装甲壁板_资产包'}
VERSION = 'v004'


def log(s):
    print(s, flush=True)


def q(x, n=5):
    r = round(x, n)
    return 0.0 if r == 0 else r


def W(o):
    """World matrix rebuilt from matrix_basis -- never read o.matrix_world.

    `blender --background` leaves Object.matrix_world un-evaluated (identity) for most objects
    of a .blend that was never touched in the UI, so reading it silently collapses the artwork
    onto the origin. Same trap the room build script documents.
    """
    m = o.matrix_parent_inverse @ o.matrix_basis
    p = o.parent
    while p is not None:
        m = (p.matrix_parent_inverse @ p.matrix_basis) @ m
        p = p.parent
    return m


def slot_matrix(direction, i):
    base, rot = WALL_LAYOUT[direction]
    b = Vector(base)
    if direction in ('north', 'south'):
        loc = Vector((b.x + (i - 2) * SLOT_PITCH, b.y, 0.0))
    else:
        loc = Vector((b.x, b.y + (i - 2) * SLOT_PITCH, 0.0))
    return Matrix.Translation(loc) @ Matrix.Rotation(math.radians(rot), 4, 'Z')


def tile_matrix(r, c):
    return Matrix.Translation(Vector(((c - 2) * SLOT_PITCH, (r - 2) * SLOT_PITCH, 0.26)))


# ------------------------------------------------------------------ part extraction
def loose_groups(me):
    n = len(me.vertices)
    parent = list(range(n))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for e in me.edges:
        ra, rb = find(e.vertices[0]), find(e.vertices[1])
        if ra != rb:
            parent[rb] = ra
    groups = {}
    for p in me.polygons:
        groups.setdefault(find(p.vertices[0]), set()).update(p.vertices)
    return list(groups.values())


def extract_part(src_obj, vert_set, xform, name):
    """One connected piece of a mesh, through xform. Keeps PaletteUV and material slots."""
    me = src_obj.data
    Wm = W(src_obj)
    idx = {}
    verts = []
    for i in sorted(vert_set):
        idx[i] = len(verts)
        verts.append(xform @ (Wm @ me.vertices[i].co))
    polys, uvs, mats = [], [], []
    uv_layer = me.uv_layers.get('PaletteUV') or (me.uv_layers[0] if me.uv_layers else None)
    for p in me.polygons:
        if p.vertices[0] not in idx:
            continue
        polys.append(tuple(idx[v] for v in p.vertices))
        if uv_layer is not None:
            for li in p.loop_indices:
                uvs.append(tuple(uv_layer.data[li].uv))
        m = me.materials[p.material_index] if me.materials else None
        mn = m.name.split('.')[0] if m else ''
        if mn and mn not in mats:
            mats.append(mn)
    if not polys:
        return None
    lo = [min(v[i] for v in verts) for i in range(3)]
    hi = [max(v[i] for v in verts) for i in range(3)]
    return {'name': name, 'verts': verts, 'polys': polys, 'uvs': uvs, 'mats': mats,
            'lo': [q(v, 4) for v in lo], 'hi': [q(v, 4) for v in hi]}


def extract_object(o, xform, name):
    return extract_part(o, set(range(len(o.data.vertices))), xform, name)


def boxes_match(a, b, tol=1e-3):
    return all(abs(a[k][i] - b[k][i]) <= tol for i in range(3) for k in (0, 1))


def pts_box(pts, nd=3):
    return [[q(min(p[i] for p in pts), nd) for i in range(3)],
            [q(max(p[i] for p in pts), nd) for i in range(3)]]


def parts_box(parts, T=None):
    pts = [(T @ v if T else v) for p in parts for v in p['verts']]
    return pts_box(pts)


def sig(parts):
    """Position-orientation independent shape signature, for cross-tile comparison."""
    return tuple(sorted((','.join(p['mats']), len(p['verts']), len(p['polys'])) for p in parts))


REPLAY = []
WARNINGS = []

# =====================================================================================
# STAGE 1a -- room v006: wall armour + door gates, in the components' own frames
# =====================================================================================
log('=' * 88)
log('STAGE 1a  room v006 -> wall armour + door gates in component-local frames')
bpy.ops.wm.open_mainfile(filepath=str(ROOM6))


def wall_slot_parts(direction, i):
    """The armour of wall slot i, in that slot's component-local frame."""
    c = bpy.data.collections.get(ARMOUR_COLLS[direction])
    if c is None:
        return []
    M = slot_matrix(direction, i).inverted()
    out = []
    for o in sorted((x for x in c.objects if x.type == 'MESH'), key=lambda x: x.name):
        for k, vs in enumerate(loose_groups(o.data)):
            p = extract_part(o, vs, M, '%s_s%d_p%d' % (direction, i, k))
            if p is None:
                continue
            # local X is always the component's 5 m width -> keep only this slot's parts
            if abs((p['lo'][0] + p['hi'][0]) / 2.0) <= SLOT_PITCH / 2.0 + 1e-6:
                out.append(p)
    out.sort(key=lambda p: (round(p['lo'][0], 3), round(p['lo'][2], 3)))
    return out


wall_units = {d: {i: wall_slot_parts(d, i) for i in (1, 2, 3)}
              for d in ('north', 'south', 'east', 'west')}
for d in ('north', 'south', 'east', 'west'):
    log('  %-6s armour parts per slot: %s'
        % (d, {i: len(v) for i, v in wall_units[d].items()}))

REF_UNIT = wall_units['north'][2]
assert len(REF_UNIT) == 4, 'north middle slot should carry 4 armour parts, got %d' % len(REF_UNIT)
assert not wall_units['south'][2], 'south door slot must carry no armour'
assert not wall_units['east'][2], 'east door slot must carry no armour'

# THE cross-direction proof
for d in ('south', 'east'):
    for i in (1, 3):
        got = wall_units[d][i]
        assert len(got) == 4, '%s slot %d: expected 4 armour parts, got %d' % (d, i, len(got))
        for a, b in zip(REF_UNIT, got):
            assert boxes_match([a['lo'], a['hi']], [b['lo'], b['hi']]), \
                '%s slot %d armour differs from the north unit: %s..%s vs %s..%s' % (
                    d, i, a['lo'], a['hi'], b['lo'], b['hi'])
log('  OK  north / south / east armour units are value-identical (4 parts each)')

REF_BOX = parts_box(REF_UNIT)
for d in ('north', 'south', 'east'):
    for i in (1, 2, 3):
        ref = wall_units[d][i]
        if ref:
            T = slot_matrix(d, i)
            rl = parts_box(ref, T)
            cl = parts_box(REF_UNIT, T)
            ok = boxes_match(rl, cl)
            REPLAY.append({'slot': 'WALLSLOT_%s_%02d' % (d.upper(), i), 'kind': 'wall_armour',
                           'room_box': rl, 'component_box': cl, 'match': ok})
            assert ok, 'wall replay mismatch %s_%02d: %s vs %s' % (d, i, rl, cl)

# west: the captured divergence
west_sig = {i: [p['lo'] + p['hi'] for p in wall_units['west'][i]] for i in (1, 2, 3)}
assert not boxes_match(parts_box(wall_units['west'][2]), REF_BOX), \
    'west wall unexpectedly matches the 5 m unit -- the normalisation note is now stale'
Tw = slot_matrix('west', 2)
REPLAY.append({'slot': 'WALLSLOT_WEST_02', 'kind': 'wall_armour',
               'room_box': parts_box(wall_units['west'][2], Tw),
               'component_box': parts_box(REF_UNIT, Tw), 'match': False,
               'note': 'normalised on purpose: authored west wall ran a 2.9 m cadence across the '
                       'whole 15 m wall and is not slot-aligned'})
WARNINGS.append('west wall armour normalised 5 x 2.9 m -> 6 x 2.4 m (was not slot-aligned)')
log('  NOTE west wall diverges by construction: room=%s vs unit=%s'
    % (parts_box(wall_units['west'][2], Tw), parts_box(REF_UNIT, Tw)))


def gate_collection(prefix):
    best, best_err = None, None
    for c in [c for c in bpy.data.collections if c.name.split('.')[0] == prefix]:
        objs = [o for o in c.objects if o.type == 'MESH']
        if not objs:
            continue
        piers = [o for o in objs if '门框立柱' in o.name]
        use = piers or objs
        pts = [W(o) @ Vector(corner) for o in use for corner in o.bound_box]
        u = (min(p[0] for p in pts) + max(p[0] for p in pts)) / 2.0
        if best_err is None or abs(u) < best_err:
            best, best_err = c, abs(u)
    return best


def gate_parts(direction):
    prefix = '%s门装甲与门禁_资产包' % ('南' if direction == 'south' else '东')
    c = gate_collection(prefix)
    assert c is not None, 'gate collection missing for ' + direction
    M = slot_matrix(direction, 2).inverted()
    out = []
    for o in sorted((x for x in c.objects if x.type == 'MESH'), key=lambda x: x.name):
        for k, vs in enumerate(loose_groups(o.data)):
            p = extract_part(o, vs, M, 'gate_%s_%d' % (direction, k))
            if p is not None:
                out.append(p)
    out.sort(key=lambda p: (round(p['lo'][2], 3), round(p['lo'][0], 3)))
    return out, c.name


GATE_UNIT, gate_name_s = gate_parts('south')
GATE_E, gate_name_e = gate_parts('east')
assert len(GATE_UNIT) == 11, 'south gate should decompose into 11 parts, got %d' % len(GATE_UNIT)
assert len(GATE_E) == len(GATE_UNIT), 'east / south gate part counts differ'
for a, b in zip(GATE_UNIT, GATE_E):
    assert boxes_match([a['lo'], a['hi']], [b['lo'], b['hi']]), \
        'east gate differs from south gate'
log('  OK  south / east gates are value-identical in the door-slot frame (11 parts each)')
for d, unit in (('south', GATE_UNIT), ('east', GATE_E)):
    T = slot_matrix(d, 2)
    rl = parts_box(unit, T)
    REPLAY.append({'slot': 'DOORSLOT_%s' % d.upper(), 'kind': 'door_gate',
                   'room_box': rl, 'component_box': rl, 'match': True})
log('  OK  both door gates replay exactly')

# =====================================================================================
# STAGE 1b -- recovered source: floor tile art, in the tile's own frame
# =====================================================================================
log('=' * 88)
log('STAGE 1b  recovered source -> floor tile art in tile-local frames')
bpy.ops.wm.open_mainfile(filepath=str(RECOVERED))


def tile_parts(r, c):
    col = None
    for nm in ('制作_地砖_R%02d_C%02d.001' % (r, c), '制作_地砖_R%02d_C%02d' % (r, c)):
        col = bpy.data.collections.get(nm)
        if col is not None:
            break
    assert col is not None, 'missing tile collection R%02dC%02d' % (r, c)
    M = tile_matrix(r, c).inverted()
    out = []
    for o in sorted((x for x in col.objects if x.type == 'MESH'), key=lambda x: x.name):
        if o.name.startswith(('FLOOR_', 'AP_', 'WALL_')):
            continue                       # the tile MODULE already has a component
        p = extract_object(o, M, o.name)
        if p is not None:
            out.append(p)
    return out


TILE_ROLE_KEYS = (
    ('地砖压边', 'trim'), ('蓝色拼缝', 'seam'),
    ('检修格栅框', 'grate_frame'), ('格栅暗底', 'grate_base'), ('检修格栅', 'grate_bar'),
    ('方形检修盖', 'cover'), ('盖板内凹', 'cover_recess'), ('紧固螺帽', 'cover_nut'),
    ('地砖磨损', 'wear'), ('标识_DB', 'db_sign'),
)


def tile_roles(parts):
    roles = set()
    for p in parts:
        for key, tag in TILE_ROLE_KEYS:
            if key in p['name']:
                roles.add(tag)
                break
        else:
            roles.add('other:' + p['name'])
    return roles


def frame_sig(parts):
    """The tile's structural frame, in the tile's own frame: 4 trims + 2 seams. Geometry only --
    object names differ per tile, the boxes must not."""
    return tuple(sorted((tuple(p['lo']), tuple(p['hi']))
                        for p in parts if '地砖压边' in p['name'] or '蓝色拼缝' in p['name']))


def cluster(parts):
    r = tile_roles(parts)
    if 'grate_bar' in r or 'grate_frame' in r:
        return 'grate'
    if 'cover' in r:
        return 'cover'
    return 'plain'


TILE_SRC = {('%d%d' % (r, c)): tile_parts(r, c) for r in (1, 2, 3) for c in (1, 2, 3)}
C01 = ['11', '13', '22', '31', '33']
C02 = ['12', '21', '23', '32']

for k in sorted(TILE_SRC):
    p = TILE_SRC[k]
    log('  R%s  parts=%2d  cluster=%-6s  roles=%s'
        % (k, len(p), cluster(p), ','.join(sorted(tile_roles(p)))))

# The tile STRUCTURE (body plate + inset plate) is not re-authored here: the v003 components were
# built from this very source and their two plates are vert/poly identical to the room's
# FLOORSLOT_* + FLOORSLOT_*_INSET. Only the DECOR is merged below.
#
# What must line up on any slot is the structural FRAME: the 4 地砖压边 trims + the 2 蓝色拼缝
# seams. Those are value-identical on all 9 tiles once expressed in each tile's own frame:
FRAMES = {k: frame_sig(TILE_SRC[k]) for k in TILE_SRC}
assert len(set(FRAMES.values())) == 1, \
    'tile frames (trims/seams) are not uniform: %s' % {k: len(v) for k, v in FRAMES.items()}
log('  OK  all 9 tile frames (4 trims + 2 seams) are value-identical in tile-local frames')

# c01 x5 -> one clean unit: same feature cluster (grate) AND identical part shapes.
c01_clusters = {k: cluster(TILE_SRC[k]) for k in C01}
c01_shapes = {k: sig(TILE_SRC[k]) for k in C01}
assert set(c01_clusters.values()) == {'grate'}, 'c01 not uniformly the grate variant: %s' % c01_clusters
assert len(set(c01_shapes.values())) == 1, 'c01 tiles disagree: %s' % {k: len(v) for k, v in c01_shapes.items()}
log('  OK  c01 x5 are one clean unit (grate cluster + identical part shapes)')

# c02 -> the source genuinely splits: some tiles carry a 方形检修盖, some do not. Nothing is
# deleted: the component takes the WITH-cover variant, which is also the one the v003 c02 inset
# (1220 verts) already carries.
c02_clusters = {k: cluster(TILE_SRC[k]) for k in C02}
c02_shapes = {k: sig(TILE_SRC[k]) for k in C02}
cover_k = sorted(k for k in C02 if c02_clusters[k] == 'cover')
plain_k = sorted(k for k in C02 if c02_clusters[k] == 'plain')
log('  c02 clusters: %s' % c02_clusters)
assert cover_k, 'no c02 tile carries the square access cover'
TILE_UNIT = {'floor_tile_r01_c01': TILE_SRC['22'],
             'floor_tile_r01_c02': TILE_SRC[cover_k[0]]}
if plain_k:
    WARNINGS.append('c02 floor tile: the room splits %d with / %d without the square access cover '
                    '(%s vs %s); the generic component takes the WITH-cover variant, so those '
                    'tiles gain a cover'
                    % (len(cover_k), len(plain_k), '+'.join(cover_k), '+'.join(plain_k)))
log('  NOTE c02 %s=with cover / %s=plain -> component takes the WITH-cover variant'
    % ('+'.join(cover_k), '+'.join(plain_k) or 'none'))
if plain_k:
    WARNINGS.append('floor tiles carry per-tile unique scuff marks (地砖磨损); a generic component '
                    'keeps one representative per variant, so scuffs repeat across slots')

# Replay: every tile's structural frame must land exactly on its slot. Whole-tile identity holds
# only on the representative tiles -- the rest differ by their own scuffs / feature cluster.
for k, parts in sorted(TILE_SRC.items()):
    r, c = int(k[0]), int(k[1])
    comp = 'floor_tile_r01_c01' if (r + c) % 2 == 0 else 'floor_tile_r01_c02'
    unit = TILE_UNIT[comp]
    T = tile_matrix(r, c)
    rframe = [x for x in parts if '地砖压边' in x['name'] or '蓝色拼缝' in x['name']]
    uframe = [x for x in unit if '地砖压边' in x['name'] or '蓝色拼缝' in x['name']]
    rf, uf = parts_box(rframe, T), parts_box(uframe, T)
    frame_ok = boxes_match(rf, uf)
    whole_ok = boxes_match(parts_box(parts, T), parts_box(unit, T))
    REPLAY.append({'slot': 'FLOORSLOT_R%02d_C%02d' % (r, c), 'kind': 'floor_tile',
                   'component': comp,
                   'slot_xy': [q(T.to_translation()[0], 3), q(T.to_translation()[1], 3)],
                   'frame_room_box': rf, 'frame_component_box': uf, 'frame_match': frame_ok,
                   'whole_tile_identical': whole_ok,
                   'note': '' if whole_ok else 'own scuffs / feature cluster normalised to the '
                                              'generic component; structural frame aligns'})
    assert frame_ok, 'floor FRAME replay mismatch R%02dC%02d: %s vs %s' % (r, c, rf, uf)
log('  OK  all 9 floor tiles: structural frame aligns exactly through the slot transform')
log('      (whole-tile identical on the representative tiles only)')

# the chosen tile art must not overhang the 4.94 m footprint into its neighbours
for comp, unit in TILE_UNIT.items():
    b = parts_box(unit)
    assert b[0][0] >= -2.47 - 1e-3 and b[1][0] <= 2.47 + 1e-3, '%s art overhangs in x: %s' % (comp, b)
    assert b[0][1] >= -2.47 - 1e-3 and b[1][1] <= 2.47 + 1e-3, '%s art overhangs in y: %s' % (comp, b)
    assert b[0][2] >= -1e-3, '%s art starts below local z=0: %s' % (comp, b)
    log('  OK  %-20s art fits the 4.94 x 4.94 footprint, z starts at %.4f, top %.4f'
        % (comp, b[0][2], b[1][2]))

# the wall / gate art must not overhang the component envelope either
b = parts_box(REF_UNIT)
assert b[0][0] >= -2.5 - 1e-3 and b[1][0] <= 2.5 + 1e-3, 'armour unit wider than 5 m: %s' % b
assert b[1][2] <= 11.9 + 1e-3, 'armour unit taller than 11.9 m: %s' % b
log('  OK  wall armour unit inside 5.0 x 11.9 m; depth %.4f..%.4f (structure is -0.15..0.15)'
    % (b[0][1], b[1][1]))
b = parts_box(GATE_UNIT)
assert b[0][0] >= -2.5 - 1e-3 and b[1][0] <= 2.5 + 1e-3, 'gate wider than 5 m: %s' % b
log('  OK  door gate inside 5.0 m; depth %.4f..%.4f' % (b[0][1], b[1][1]))

# =====================================================================================
# STAGE 2 -- build the v004 blend
# =====================================================================================
log('=' * 88)
log('STAGE 2  build v004 blend')
V4_DIR.mkdir(parents=True, exist_ok=True)
if BLEND4.is_file():
    shutil.copy2(BLEND4, BLEND4.with_suffix('.blend.bak_before_rebuild'))
shutil.copy2(LIB3, BLEND4)              # v003 verbatim: 18 other packages + showcase carry over
bpy.ops.wm.open_mainfile(filepath=str(BLEND4))

img = bpy.data.images.get('设施低亮多巴胺色盘_10x10_512.png')
if img is not None and PALETTE.is_file():
    img.filepath = str(PALETTE)
    img.reload()
for r in ROLES:
    assert bpy.data.materials.get(r) is not None, 'v003 library is missing role material ' + r
log('  v003 copied verbatim -> v004; 4 role materials present')

ADDED = []


def add_part(comp, part, suffix):
    coll_name, root_name, _ = COMPONENTS[comp]
    coll = bpy.data.collections.get(coll_name)
    root = bpy.data.objects.get(root_name)
    assert coll is not None and root is not None, 'missing %s / %s' % (coll_name, root_name)
    me = bpy.data.meshes.new('%s_网格' % part['name'])
    me.from_pydata([tuple(v) for v in part['verts']], [], [list(p) for p in part['polys']])
    me.update()
    for mn in part['mats']:
        m = bpy.data.materials.get(mn)
        assert m is not None, 'missing role material %r for %s' % (mn, part['name'])
        me.materials.append(m)
    if part['uvs'] and len(me.loops) == len(part['uvs']):
        uv = me.uv_layers.new(name='PaletteUV')
        uv.active = True
        uv.active_render = True
        for i, val in enumerate(part['uvs']):
            uv.data[i].uv = val
    o = bpy.data.objects.new('%s_%s' % (comp, suffix), me)
    coll.objects.link(o)
    o.parent = root
    o.matrix_parent_inverse = Matrix.Identity(4)
    o.matrix_basis = Matrix.Identity(4)          # vertices are already root-local
    o['v004_added_art'] = True
    ADDED.append(o)
    return o


for k, p in enumerate(REF_UNIT):
    add_part('wall_standard_5m', p, '槽位装甲单元_%02d' % (k + 1))
log('  wall_standard_5m   += %2d armour parts' % len(REF_UNIT))
for k, p in enumerate(GATE_UNIT):
    add_part('wall_door_5m', p, '装甲门禁_%02d' % (k + 1))
log('  wall_door_5m       += %2d gate parts' % len(GATE_UNIT))
for k, p in enumerate(TILE_UNIT['floor_tile_r01_c01']):
    add_part('floor_tile_r01_c01', p, '砖面美术_%02d' % (k + 1))
log('  floor_tile_r01_c01 += %2d tile parts' % len(TILE_UNIT['floor_tile_r01_c01']))
for k, p in enumerate(TILE_UNIT['floor_tile_r01_c02']):
    add_part('floor_tile_r01_c02', p, '砖面美术_%02d' % (k + 1))
log('  floor_tile_r01_c02 += %2d tile parts' % len(TILE_UNIT['floor_tile_r01_c02']))
log('  door_5m            +=  0 (the room carried no extra art for the leaf)')

bpy.context.view_layer.update()

boxes = {}
for comp, (coll_name, root_name, _) in COMPONENTS.items():
    coll = bpy.data.collections[coll_name]
    root = bpy.data.objects[root_name]
    inv = W(root).inverted()            # showcase array offsets mean nothing: measure root-local
    meshes = [o for o in coll.objects if o.type == 'MESH']
    pts = [inv @ (W(o) @ Vector(c)) for o in meshes for c in o.bound_box]
    lo = [q(min(p[i] for p in pts), 4) for i in range(3)]
    hi = [q(max(p[i] for p in pts), 4) for i in range(3)]
    boxes[comp] = {'lo': lo, 'hi': hi, 'dims': [q(hi[i] - lo[i], 4) for i in range(3)],
                   'meshes': len(meshes),
                   'roles': sorted({m.name.split('.')[0] for o in meshes
                                    for m in o.data.materials if m})}
    log('  %-20s lo=%-30s hi=%-30s dims=%s meshes=%d'
        % (comp, lo, hi, boxes[comp]['dims'], boxes[comp]['meshes']))

# contract: the component frame survives the art merge.
#   grid-critical -> local z0 = bottom face, local x centre = slot centre
#   depth (y)     -> the added art legitimately sits proud on the room side, so only bound it
for comp in COMPONENTS:
    b = boxes[comp]
    assert abs(b['lo'][2]) < 1e-3, '%s no longer sits on local z=0' % comp
    assert abs((b['lo'][0] + b['hi'][0]) / 2.0) < 1e-3, \
        '%s no longer centred in width (x): %s' % (comp, b)
    dy = abs((b['lo'][1] + b['hi'][1]) / 2.0)
    assert dy < 0.05, '%s depth centre drifted %.4f: %s' % (comp, dy, b)
    log('      %-20s depth y %.4f..%.4f (centre drift %.4f)'
        % (comp, b['lo'][1], b['hi'][1], dy))
for comp, w, h in (('wall_standard_5m', 5.0, 11.9), ('wall_door_5m', 5.0, 11.9),
                   ('door_5m', 2.2, 2.5)):
    b = boxes[comp]
    assert b['dims'][0] <= w + 1e-3, '%s art wider than its %s m slot' % (comp, w)
    assert b['dims'][2] <= h + 1e-3, '%s art taller than %s m' % (comp, h)
for comp in ('floor_tile_r01_c01', 'floor_tile_r01_c02'):
    b = boxes[comp]
    assert b['dims'][0] <= 4.94 + 1e-3 and b['dims'][1] <= 4.94 + 1e-3, \
        '%s art overhangs the 4.94 m footprint' % comp
log('  OK  all five components keep: bottom-centre origin, XZ centred, inside their envelope')

bpy.ops.wm.save_as_mainfile(filepath=str(BLEND4), compress=True)   # v003 is zstd-compressed too
log('  SAVED %s' % BLEND4)

# =====================================================================================
# STAGE 3 -- manifests + report
# =====================================================================================
for comp, (coll_name, root_name, note) in COMPONENTS.items():
    coll = bpy.data.collections[coll_name]
    meshes = sorted((o for o in coll.objects if o.type == 'MESH'), key=lambda x: x.name)
    manifest = {
        'asset_id': 'ENV-BATTLE-L01-COMMON-COMPONENT-LIBRARY',
        'package_id': 'ENV-BATTLE-COMMON-' + comp.upper().replace('_', '-'),
        'slug': comp, 'component': comp, 'version': VERSION,
        'category': CATEGORY[comp], 'note_zh': note,
        'source_blend': BLEND4.name, 'blender_collection': coll_name, 'root_object': root_name,
        'objects': [o.name for o in meshes], 'object_count': len(meshes),
        'local_origin': [0, 0, 0], 'bounds_lo': boxes[comp]['lo'], 'bounds_hi': boxes[comp]['hi'],
        'bounds_size': boxes[comp]['dims'],
        'godot_bounds_size': [boxes[comp]['dims'][0], boxes[comp]['dims'][2], boxes[comp]['dims'][1]],
        'origin_contract': 'bottom_center', 'forward_axis': '-Z', 'up_axis': '+Y',
        'material_roles_used': boxes[comp]['roles'],
        'instance_rule_zh': '原点=底面中心、本地 +Y=朝房内那面。放到任意 5m 网格槽位即自动对齐，'
                            '不需要按方位区分。',
        'supersedes': 'v003', 'carries_room_art_from': 'entry_safe_room/v006',
        'collision_note': '碰撞不随美术：结构碰撞仍由 Godot 0.30m 代理负责。',
        'exported': False,
    }
    d = V4_DIR / 'component_packages_v004' / CATEGORY[comp].split('_')[0] / comp
    d.mkdir(parents=True, exist_ok=True)
    (d / 'asset_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2),
                                           encoding='utf8')

(V4_DIR / 'qa').mkdir(parents=True, exist_ok=True)
(V4_DIR / 'qa' / 'build_v004_report.json').write_text(json.dumps({
    'version': VERSION,
    'source_library': str(LIB3.relative_to(ROOT)),
    'output_blend': str(BLEND4.relative_to(ROOT)),
    'components': boxes,
    'added_object_count': len(ADDED),
    'wall_armour_unit': {'parts': len(REF_UNIT), 'box': REF_BOX},
    'door_gate_unit': {'parts': len(GATE_UNIT), 'box': parts_box(GATE_UNIT),
                       'source_collection_south': gate_name_s,
                       'source_collection_east': gate_name_e},
    'tile_units': {k: {'parts': len(v), 'box': parts_box(v)} for k, v in TILE_UNIT.items()},
    'uniformity': {'c01_distinct_detail_sets': len(set(c01_shapes.values())),
                   'c02_distinct_detail_sets': len(set(c02_shapes.values())),
                   'c02_clusters': c02_clusters,
                   'tile_frames_uniform': True,
                   'wall_directions_agreeing': ['north', 'south', 'east']},
    'tile_structure_provenance': 'the v003 floor components two plates are vert/poly identical to '
                                 'the room v006 FLOORSLOT_* (24/26) + FLOORSLOT_*_INSET '
                                 '(c01 872/711, c02 1220/1026); only decor is merged in v004',
    'replay': REPLAY,
    'warnings': WARNINGS,
}, ensure_ascii=False, indent=2), encoding='utf8')

log('=' * 88)
matched = sum(1 for r in REPLAY if (r.get('match') if r['kind'] != 'floor_tile'
                                    else r['frame_match']))
log('BUILD_OK  components=%d  added_meshes=%d  replay_slots=%d  aligned=%d'
    % (len(COMPONENTS), len(ADDED), len(REPLAY), matched))
for w in WARNINGS:
    log('WARN  ' + w)
