"""Entry safe room formal art v007-style rebuild of v006.

Base : recovered v003 formal art (facilities already accepted, built from whitebox v003)
Fix  : remove every room-owned wall / floor MODULE asset; rebuild walls + floors as
       visual-only references to the shared common_components v003 library, and re-lay the
       wall armour as room-level DECOR packages on the 5m slot grid.

Contract of record
  assets/art/3D模型资产目录与命名规范.md  §坐标与替换契约
    L104 wall origin = bottom-edge centre; 5x12m span; decoration MAY exceed the 0.30m
         structural thickness; gameplay collision stays with Godot's 0.30m proxy
    L107 plain / door / window walls must be different AssetIDs; door leaf independent;
         opening, lock, switch, pathing, prompt and collision owned by Godot
    L108 GLB is visual only; replacing it must not change room size, 5m grid, collision
         layer, navigation, camera-occlusion flag, door FSM or interaction nodes

Slot layout = the RUNTIME layout (runtime probe), which is the sanctioned basis:
    N 3 solid | S solid+door+solid | E solid+door+solid | W 3 solid
    10x wall_standard_5m + 2x wall_door_5m + 2x door_5m
  The runtime puts both doorways in the MIDDLE 5m slot (tangential centre 0) and the
  door-wall node on the outer face (+-7.5). The common-component origin is the wall
  centrelines, so the same occupancy is 7.2..7.5 at slot +-7.35.

  DIVERGENCE, recorded not hidden: whitebox v003 authored the south door off-centre
  (slot centre +2.5, south wall = 2.5 trim + 5 solid + 5 door + 2.5 trim) and had no
  east door at all. v006 follows the runtime per the user's decision.

Blender background trap this script works around
  `blender --background` leaves Object.matrix_world UN-EVALUATED (identity) for ~85% of
  the objects of any .blend that was never touched in the UI. view_layer.update(),
  depsgraph.update(), frame_set() and evaluated_get() all leave it at identity; only an
  unlink/link cycle refreshes it. Reading it silently collapsed every merged package onto
  the origin and turned every relocation delta into a teleport. Everything below goes
  through world_matrix() instead, which rebuilds the transform from matrix_basis.

Run:
  blender --background --factory-startup --python build_entry_safe_room_v006.py
  ESR_FAST=1 -> skip the Cycles renders (fast QA iteration)
"""
import bpy, math, json, os, hashlib
from pathlib import Path
from mathutils import Vector, Matrix

ROOT  = Path(r'I:/工作项目/shellstrom2/ShellStorm2')
SRC   = Path(r'I:/工作项目/shellstrom2/_scratch/esr_recover/v003_recovered.blend')
CC    = ROOT/'assets/art/environments/tower_zones/battle/source/common_components/v003/战局区块_通用组件库_v003.blend'
WBMA  = ROOT/'source/art/whitebox/tower_zones/battle_level01/v003/data/component_packages/safe_rooms/局内关卡01_白模_入口安全房_15x15m/asset_manifest.json'
OUT   = ROOT/'assets/art/environments/tower_zones/battle/source/entry_safe_room/v006'
BLEND = OUT/'局内关卡01_入口安全房_15x15m_正式美术_v006.blend'
PAL   = ROOT/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
ASSET_ID, BLOCK_ID, FLOOR_RANGE, SCOPE = 'ENV-BATTLE-L01-SAFE-ENTRY', 'battle', '01F', '入口安全房'
DOCS   = ['docs/v0.1/05.1_关卡区块设计.md', 'docs/v0.1/10.1_3D场景美术生产流程.md']
LEDGER = 'assets/registry/ShellStorm2_美术资产台账_v001.xlsx#3D-场景通用'
ROLES  = ['01_精工金属_紫色骨架', '02_细腻哑光_青绿大面', '03_清漆反光_紫粉点缀', '04_柔和自发光_UI灯光']
FAST   = os.environ.get('ESR_FAST') == '1'

ENTRY_CY, SIDE_CY = 7.35, 7.35       # wall centrelines (whitebox envelope)
INNER_FACE, OUTER_FACE = 7.2, 7.5    # wall inner / outer face (0.30 structural thickness)
WALK_Z, SLAB_Z    = 0.30, 0.26       # walkable surface / structural slab top
PLATE_W           = 2.4              # armour panel unit width (authored north cadence)
WALL_VIS_H        = 11.9

def log(s): print(s, flush=True)
def dump(p, v):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(v, ensure_ascii=False, indent=2), encoding='utf8')
def q(x, n):
    """round, folding -0.0 into 0.0 so a sign flip never fakes a hash change"""
    r = round(x, n)
    return 0.0 if r == 0 else r

# ------------------------------------------------------- world matrix, rebuilt
def world_matrix(o):
    """Authoritative world matrix. See the module docstring for why NOT o.matrix_world."""
    m = o.matrix_parent_inverse @ o.matrix_basis
    p = o.parent
    while p is not None:
        m = (p.matrix_parent_inverse @ p.matrix_basis) @ m
        p = p.parent
    return m

def assert_rebuild_safe(where):
    unsafe = [o.name for o in bpy.data.objects
              if o.constraints or (o.animation_data and o.animation_data.drivers)]
    assert not unsafe, ('%s: world_matrix() rebuild cannot honour constraints/drivers on %d object(s): %s'
                        % (where, len(unsafe), unsafe[:8]))

# ---------------------------------------------------------------- signatures
def obj_sig(o):
    return {'m': [[q(v, 6) for v in row] for row in world_matrix(o)],
            'v': [[q(v, 6) for v in p.co] for p in o.data.vertices],
            'f': [list(p.vertices) for p in o.data.polygons]}
def sha(v):
    return hashlib.sha256(json.dumps(v, sort_keys=True).encode()).hexdigest()
def obj_hash(o):
    return {k: sha(v) for k, v in obj_sig(o).items()}
def mesh_sig(me):
    """Signature of an already-root-relative mesh: coords + topology + palette roles."""
    vs = [(q(v.co.x, 5), q(v.co.y, 5), q(v.co.z, 5)) for v in me.vertices]
    fs = [tuple(p.vertices) for p in me.polygons]
    ms = [(m.name.split('.')[0] if m else '') for m in me.materials]
    return sha([vs, fs, ms])

def canonical_mesh(src_obj, remap_materials, drop=False):
    """Clone one library PART into root-local space -- the frame the contract is written in.

    Measured shape of the library (probe_cc_space.py): every part sits at location (0,0,0) with
    its vertices ALREADY in the component's root-local frame, and the part is parented to the
    component's ROOT_* empty, which carries the library's layout position (e.g. wall_standard_5m
    lives at (4.0, -58.3444, 0)). So the canonical mesh is the mesh taken through the part's OWN
    transform -- never through the parent's. Subtracting the ROOT_* world position double-counts
    it and shifts the whole slot by that layout offset (walls landed 58.19 m off, the floor grid
    56 m off the room), which no self-consistency check can see.

    The same routine mints the library contract in pass 1 and every slot in pass 2, so both
    signatures come from a byte-identical pipeline.
    """
    me = src_obj.data.copy()
    M = src_obj.matrix_basis
    for v in me.vertices:
        v.co = M @ v.co
    if remap_materials:
        order, remap = [], []
        for m in me.materials:
            base = m.name.split('.')[0]
            tgt = bpy.data.materials.get(base) or m
            if tgt not in order:
                order.append(tgt)
            remap.append(order.index(tgt))
        for p in me.polygons:
            if p.material_index < len(remap):
                p.material_index = remap[p.material_index]
        me.materials.clear()
        for m in order:
            me.materials.append(m)
    if drop:
        bpy.data.meshes.remove(me)
    return me

def obj_bounds(objs):
    pts = []
    for o in objs:
        pts += [world_matrix(o) @ Vector(c) for c in o.bound_box]
    if not pts:
        return [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
    return [[round(fn(p[i] for p in pts), 4) for i in range(3)] for fn in (min, max)]

def unit(lo, hi):
    """normalised vector so a bounds pair can be compared with a tolerance"""
    return [abs(hi[i] - lo[i]) for i in range(3)]
def same_box(a, b, tol=0.02, where=''):
    for i in range(3):
        for k in (0, 1):
            if abs(a[k][i] - b[k][i]) > tol:
                return False
    return True

# ============================================================ pass 1 : library
bpy.ops.wm.open_mainfile(filepath=str(CC))
assert_rebuild_safe('common library')
LIB = {'wall_standard_5m':        ['wall_standard_5m_主体_输出'],
       'wall_door_5m':            ['wall_door_5m_门垛左_输出', 'wall_door_5m_门垛右_输出', 'wall_door_5m_门楣_输出'],
       'door_5m':                 ['door_5m_门扇_输出'],
       'floor_tile_r01_c01':      ['floor_tile_r01_c01_主体_输出', 'floor_tile_r01_c01_主体_输出.001'],
       'floor_tile_r01_c02':      ['floor_tile_r01_c02_主体_输出', 'floor_tile_r01_c02_主体_输出.001']}
markers = {c.name.replace('ROOT_', '').replace('_通用组件', ''): [q(v, 5) for v in c.location]
           for c in bpy.data.objects if c.type == 'EMPTY' and c.name.startswith('ROOT_')}
CONTRACT = {}
for comp, names in LIB.items():
    CONTRACT[comp] = {'component': comp,
                      'root_local_origin': 'library world origin (0,0,0); see shape_convention',
                      'library_layout_marker': markers.get(comp),
                      'shape_convention': 'origin = bottom-edge centre; body is centred in the two '
                                          'tangential axes and extends from local z=0 upward',
                      'source_library': str(CC.relative_to(ROOT)), 'parts': {}}
    pts = []
    for n in names:
        o = bpy.data.objects[n]
        me = canonical_mesh(o, remap_materials=True)
        lo = [min(q(v.co[i], 5) for v in me.vertices) for i in range(3)]
        hi = [max(q(v.co[i], 5) for v in me.vertices) for i in range(3)]
        pts += [Vector((x, y, z)) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]
        CONTRACT[comp]['parts'][n] = {
            'local_bounds': [lo, hi],
            'local_dims': [round(hi[i] - lo[i], 5) for i in range(3)],
            'materials': sorted({(m.name.split('.')[0] if m else '') for m in me.materials}),
            'canon_sha256': mesh_sig(me)}
        bpy.data.meshes.remove(me)
        log('LIB %-20s %-26s dims=%s' % (comp, n, CONTRACT[comp]['parts'][n]['local_dims']))
    cb = [[min(p[i] for p in pts) for i in range(3)], [max(p[i] for p in pts) for i in range(3)]]
    CONTRACT[comp]['component_bounds'] = cb
    CONTRACT[comp]['component_dims'] = [round(cb[1][i] - cb[0][i], 5) for i in range(3)]
    # THE assertion that catches a wrong canonicalisation: the declared shape convention is a
    # claim about the numbers, so check the numbers. A double-counted library layout offset shows
    # up here as a component whose box is not centred on its own origin.
    for i, ax in enumerate('xy'):
        mid = (cb[0][i] + cb[1][i]) / 2.0
        assert abs(mid) < 0.01, ('%s: component box is not centred on the origin in %s '
                                 '(mid=%.4f, bounds=%s) -- canonicalisation is off'
                                 % (comp, ax, mid, cb))
    assert abs(cb[0][2]) < 0.01, ('%s: component box does not start at local z=0 (z_min=%.4f) '
                                   '-- canonicalisation is off' % (comp, cb[0][2]))

# ============================================================ pass 2 : build
bpy.ops.wm.open_mainfile(filepath=str(SRC))
scene = bpy.context.scene
assert_rebuild_safe('recovered v003 artwork')

# --- cross-check the source envelope against the whitebox manifest of record ----
wb_manifest = json.loads(WBMA.read_text(encoding='utf8'))
# The whitebox of record is the 16 AP_* plan meshes, which live in the whitebox authoring
# collections. Scope by COLLECTION, not by name prefix: the room's own authored art reuses the
# same name stems (WALL_NORTH_01, FLOOR_BASE, FLOOR_TILE_R01_C01 ...), and a prefix sweep silently
# swallowed the authored base plate along with the modules -- which hid the floor plate from
# rendering and left the 60 mm tile grout see-through.
WB_COLLS = ('01_建筑结构', '02_地面系统')
assert all(c in bpy.data.collections for c in WB_COLLS), [c for c in WB_COLLS if c not in bpy.data.collections]
WB = [o for c in WB_COLLS for o in bpy.data.collections[c].objects if o.type == 'MESH']
off_names = [o.name for o in WB if not o.name.startswith('AP_')]
assert not off_names, 'whitebox source collections hold non-AP_ objects: %s' % off_names
assert len(WB) == 16, 'expected the 16 whitebox plan objects, found %d' % len(WB)
AUTHORED_MODULES = sorted(o.name for o in bpy.data.objects
                          if o.type == 'MESH' and o.name.startswith(('WALL_', 'FLOOR_')))
SRC_ENVELOPE = {'walls': obj_bounds([o for o in WB if o.name.startswith('AP_WALL')]),
                'floors': obj_bounds([o for o in WB if o.name.startswith('AP_FLOOR')])}
log('source envelope: walls=%s floors=%s' % (SRC_ENVELOPE['walls'], SRC_ENVELOPE['floors']))
log('authored wall/floor modules in the source art: %d %s' % (len(AUTHORED_MODULES), AUTHORED_MODULES))

mats = []
for n in ROLES:
    m = bpy.data.materials.get(n)
    assert m is not None, 'missing role material ' + n
    mats.append(m)
from mathutils import Matrix as _M
image = bpy.data.images.load(str(PAL), check_existing=True)
image.filepath = str(PAL)
if image.packed_file:
    image.unpack(method='REMOVE')
assert list(image.size) == [512, 512], image.size
for n in ROLES:
    node = [x for x in bpy.data.materials[n].node_tree.nodes if x.type == 'TEX_IMAGE']
    assert node and node[0].image is not None, 'palette not bound on ' + n

def coll(name, parent):
    c = bpy.data.collections.new(name); parent.children.link(c); return c
top        = coll('局内关卡01_入口安全房_15x15m_正式美术_中文资产管理', scene.collection)
c_readonly = coll('00_白模结构来源_只读', top)
c_src      = coll('01_制作组件_按设施拆分', top)
c_out      = coll('02_游戏输出_独立资产包_v006', top)
c_fac      = coll('00_区域固定设施_逐设施', c_out)
c_decor    = coll('01_墙面与地面装饰_逐面', c_out)
c_support  = coll('02_环境支持_跨设施', c_out)
c_slot     = coll('03_墙体与地面槽位_引用通用组件_v003', top)
SLOTC = {'north': coll('01_北墙槽位', c_slot), 'south': coll('02_南墙槽位', c_slot),
         'east':  coll('03_东墙槽位', c_slot), 'west':  coll('04_西墙槽位', c_slot),
         'door':  coll('05_门扇', c_slot),     'floor': coll('06_地面槽位', c_slot)}
c_display  = coll('90_展示与验收_灯光相机', top)

# --- whitebox-origin objects become read-only provenance ---------------------
for o in WB:
    for c in list(o.users_collection):
        c.objects.unlink(o)
    c_readonly.objects.link(o)
c_readonly.hide_render = True
bpy.context.view_layer.update()
RO_LOCK = {o.name: obj_hash(o) for o in WB}
RO_BOX = {o.name: obj_bounds([o]) for o in WB}
assert len(RO_LOCK) == 16, len(RO_LOCK)
log('provenance -> readonly: %d objects' % len(WB))

# --- harvest authored source parts into v006 packages -----------------------
def parts_of(colname, drop_armour=False, allow=()):
    c = bpy.data.collections.get(colname)
    if not c:
        return []
    out = []
    for o in c.objects:
        if (o.type != 'MESH'
                or (o.name.startswith(('AP_', 'WALL_', 'FLOOR_')) and o.name not in allow)):
            continue
        if drop_armour and (o.name.startswith('墙体内嵌面板') or o.name.startswith('面板分缝')):
            continue                       # superseded by the slot-grid re-lay
        out.append(o)
    return out

# Capture the authored armour UNIT before the harvest runs. build_pkg() relinks its parts out
# of their source collection, so by the time the door-wall re-lay needs a panel to clone,
# 制作_北墙.001 is already empty (this was the 'armour unit not found' crash).
def find_armour_unit():
    def pick(objs):
        panel = next((o for o in sorted(objs, key=lambda x: x.name)
                      if o.type == 'MESH' and o.name.startswith('墙体内嵌面板')), None)
        cap = next((o for o in sorted(objs, key=lambda x: x.name)
                    if o.type == 'MESH' and o.name.startswith('面板分缝')), None)
        return panel, cap
    for cn in ('制作_北墙.001', '制作_墙面装饰_北墙内嵌装甲壁板'):
        c = bpy.data.collections.get(cn)
        if c:
            p, k = pick(c.objects)
            if p is not None and k is not None:
                return p, k
    return None, None
PANEL_SRC, CAP_SRC = find_armour_unit()
assert PANEL_SRC is not None and CAP_SRC is not None, 'authored north armour unit not found'
assert PANEL_SRC is not CAP_SRC, 'panel and cap collapsed onto one object'
assert world_matrix(PANEL_SRC).translation.y > 0.0, \
    'armour unit is not the north-wall one: %s' % (world_matrix(PANEL_SRC).translation[:],)

FACILITY_SRC = [
    ('north_server_00', '服务器柜_north_server_00', ['制作_服务器柜_north_server_00'], 'facilities', (0, 0, 0), False),
    ('north_server_01', '服务器柜_north_server_01', ['制作_服务器柜_north_server_01'], 'facilities', (0, 0, 0), False),
    ('north_server_02', '服务器柜_north_server_02', ['制作_服务器柜_north_server_02'], 'facilities', (0, 0, 0), False),
    ('north_server_03', '服务器柜_north_server_03', ['制作_服务器柜_north_server_03'], 'facilities', (0, 0, 0), False),
    ('north_server_04', '服务器柜_north_server_04', ['制作_服务器柜_north_server_04'], 'facilities', (0, 0, 0), False),
    ('north_server_05', '服务器柜_north_server_05', ['制作_服务器柜_north_server_05'], 'facilities', (0, 0, 0), False),
    ('north_broken_core', '北墙破损服务器核心', ['制作_北墙破损服务器核心'], 'facilities', (0, 0, 0), False),
    ('north_nexus_sign', '北墙标识_NEXUS', ['制作_北墙 NEXUS 标识'], 'facilities', (0, 0, 0), False),
    ('west_glass_office', '西北玻璃办公室', ['制作_西北玻璃办公室'], 'facilities', (0, 0, 0), False),
    ('central_terminal_island', '中央四屏终端岛', ['制作_中央四屏终端岛'], 'facilities', (0, 0, 0), False),
    ('east_repair_bay', '东侧维修间', ['制作_东侧维修间'], 'facilities', (0, 5.0, 0), True),
    ('east_robot_arm', '东侧黄色机械臂', ['制作_东侧黄色机械臂'], 'facilities', (0, -5.0, 0), True),
    ('office_planter', '办公室外固定绿植', ['制作_办公室外固定绿植'], 'facilities', (0, 0, 0), False),
    ('maintenance_chair', '固定展示检修椅', ['制作_固定展示检修椅'], 'facilities', (0, 0, 0), False),
    ('overhead_services', '跨设施顶部管线与灯带', ['制作_跨设施顶部管线与灯带'], 'support', (0, 0, 0), False),
    ('debris_papers', '固定碎片与散落文件', ['制作_固定碎片与散落文件'], 'support', (0, 0, 0), False),
]
CAT = {'facilities': c_fac, 'decor': c_decor, 'support': c_support}
packages = []

def build_pkg(slug, zh, srcs, category, delta, moved, allow=(), ownership=None, contract=None):
    ps = sum((parts_of(s, allow=allow) for s in srcs), [])
    if not ps:
        log('!! empty source for ' + slug); return None
    pc = coll(zh + '_资产包', CAT[category])
    pc['package_id'] = 'esr_' + slug; pc['block_id'] = BLOCK_ID; pc['asset_id'] = ASSET_ID
    gen = coll('制作_' + zh, c_src)
    T = Matrix.Translation(Vector(delta))
    for o in ps:
        before = world_matrix(o).translation.copy()
        for c in list(o.users_collection):
            c.objects.unlink(o)
        gen.objects.link(o)
        if moved:
            o.matrix_world = T @ world_matrix(o)
            moved_by = world_matrix(o).translation - before
            assert (moved_by - Vector(delta)).length < 1e-4, \
                '%s: relocation went to %s, expected delta %s' % (o.name, moved_by[:], delta)
    bpy.context.view_layer.update()
    rec = {'slug': slug, 'name': zh, 'category': category, 'collection': pc,
           'src_coll': gen, 'parts': ps, 'delta': list(delta), 'relocated': moved,
           'ownership': ownership or ('room_owned_facility' if category == 'facilities'
                                      else 'room_owned_decoration'),
           'contract': contract or ('decoration only; must not change room size, 5m grid, '
                                    'collision layer or navigation')}
    packages.append(rec)
    return rec

for slug, zh, srcs, cat, delta, moved in FACILITY_SRC:
    build_pkg(slug, zh, srcs, cat, delta, moved)

# south door gate: align the gate's DOOR FRAME -- not the package bounding box -- onto the
# runtime door slot centre (tangential u = 0). The authored gate hangs a service screen off one
# pier, so the bounding box is 0.1225 m off the frame centre; recentring on it would push the
# right pier 0.07 m into the 2.2 m clear opening.
gate_src = parts_of('制作_南门装甲与门禁')
piers = [o for o in gate_src if o.name.startswith('门框立柱')]
assert len(piers) == 2, 'expected the two south gate frame piers, found %d' % len(piers)
frame_u = sum(world_matrix(o).translation.x for o in piers) / len(piers)
gate_dx = round(-frame_u, 4)
assert abs(gate_dx + 2.5) < 1e-3, \
    'south gate frame is not on the whitebox door centre +2.5: frame_u=%s dx=%s' % (frame_u, gate_dx)
gate = build_pkg('south_door_gate', '南门装甲与门禁', ['制作_南门装甲与门禁'], 'facilities',
                 (gate_dx, 0, 0), True)
log('south door gate frame re-centred on the runtime door slot by dx=%s' % gate_dx)

# The authored 制作_南门楣 collection holds only WALL_SOUTH_DOOR_01_LINTEL -- a wall MODULE, not a
# decoration -- so it is correctly excluded by parts_of() and there is no lintel-trim package.

# north / west armour: no doorway on those walls, reuse the authored art verbatim
build_pkg('wall_armor_north', '墙面装饰_北墙内嵌装甲壁板', ['制作_北墙.001'], 'decor', (0, 0, 0), False)
build_pkg('wall_armor_west',  '墙面装饰_西墙内嵌装甲壁板', ['制作_西墙.001'], 'decor', (0, 0, 0), False)

# The structural base plate stays room-owned. It is NOT a replaceable wall/floor MODULE: the
# common component library has no counterpart for it, and the reference room of record
# (main_room_02/v003 component_packages_v003/floor/floor_base) keeps the very same package,
# same object name FLOOR_BASE, same 0.26 thickness. Its 0.26 top face is what the 5m floor tile
# modules seat on and what shows through the 60 mm grout between tiles. Dropping it opens the
# grout into the void (the 'no visible through-holes in the walk plane' check guards that).
build_pkg('floor_base', '承重底板与结构底台', ['制作_承重底板.001'], 'support', (0, 0, 0), False,
          allow=('FLOOR_BASE',),
          ownership='room_owned_structure',
          contract='structural support, not a replaceable visual module; the 5m floor tile modules '
                   'seat on its 0.26 top face and the 60 mm grout shows this surface. Godot keeps the '
                   '0.30 structural collision proxy.')

# floor trim: the 3x3 tile grid is unchanged, so the per-tile trims carry over
build_pkg('floor_trim', '地面装饰_地砖压条与检修口',
          ['制作_地砖_R%02d_C%02d.001' % (r, c) for r in (1, 2, 3) for c in (1, 2, 3)],
          'decor', (0, 0, 0), False)
log('harvested packages: %d' % len(packages))

# --- armour re-lay for the two door walls, on the 5m slot grid ---------------
# The authored armour was drawn around the whitebox's off-centre south door and a solid
# east wall; both now carry a runtime doorway in the middle 5 m slot. Re-lay the authored
# north panel unit (2.4 m, which tiles a 5 m slot exactly twice) per NON-DOOR slot, and
# rotate it onto the target wall. The panel is a flat plate, so the room-centre rotation
# also carries its proudness onto the correct face.
panel_src, cap_src = PANEL_SRC, CAP_SRC        # captured before the harvest (see find_armour_unit)
PANEL_LO = obj_bounds([panel_src])[0]
UNIT_U = (PANEL_LO[0] + obj_bounds([panel_src])[1][0]) / 2.0     # authored tangential centre (-6.25)
assert abs(UNIT_U - (-6.25)) < 1e-3, 'authored armour unit is not centred at -6.25: %s' % UNIT_U

WALL_ROT = {'north': 0.0, 'west': 90.0, 'south': 180.0, 'east': -90.0}
ARMOUR_USED = []
for d, door_i in (('south', 1), ('east', 1)):
    R = Matrix.Rotation(math.radians(WALL_ROT[d]), 4, 'Z')
    zh = '墙面装饰_%s墙内嵌装甲壁板' % ('南' if d == 'south' else '东')
    pc = coll(zh + '_资产包', c_decor)
    pc['package_id'] = 'esr_wall_armor_' + d; pc['block_id'] = BLOCK_ID; pc['asset_id'] = ASSET_ID
    gen = coll('制作_' + zh, c_src)
    parts = []
    for i in range(1, 4):                       # 3 slots of 5 m
        if i - 1 == door_i:
            continue                            # door slot carries no decoration
        for h in (-1.25, 1.25):                 # two 2.4 m panels per slot, 0.05 inset
            shift = ((i - 1 - 1) * 5.0 + h) - UNIT_U
            T = R @ Matrix.Translation(Vector((shift, 0.0, 0.0)))
            for src in (panel_src, cap_src):
                dup = src.copy(); dup.data = src.data.copy()
                dup.name = '%s_%s_槽%02d%s' % ('墙板' if src is panel_src else '板缝',
                                               'S' if d == 'south' else 'E', i,
                                               'A' if h < 0 else 'B')
                # T maps authored-wall space onto the target wall, so it must be composed with
                # the source's own transform (which carries the panel's y proudness and z lift).
                # Assigning T alone would drop every panel to the room centre at z=0.
                gen.objects.link(dup); dup.matrix_world = T @ world_matrix(src)
                assert abs(world_matrix(dup).translation.z - world_matrix(src).translation.z) < 1e-4, \
                    're-laid armour lost its wall height: %s z=%s' % (dup.name, world_matrix(dup).translation.z)
                parts.append(dup)
    bpy.context.view_layer.update()
    packages.append({'slug': 'wall_armor_' + d, 'name': zh, 'category': 'decor',
                     'collection': pc, 'src_coll': gen, 'parts': parts,
                     'delta': 're-laid on the 5m slot grid, door slot skipped', 'relocated': True,
                     'ownership': 'room_owned_decoration',
                     'contract': 'wall decor only; may be proud of the 0.30 m structure per the '
                                 'contract of record, must not change room size, 5m grid, collision '
                                 'layer or navigation'})
    ARMOUR_USED.append((d, parts))
    log('armour re-laid on %s wall: %d objects' % (d, len(parts)))

# --- east door gate: derived from the south gate, rotated onto the east wall -
# RotZ(+90) maps the south wall (Blender -Y) onto the east wall (Blender +X) exactly:
# (0,-7.35) -> (7.35,0), so no translation is needed or wanted.
gate = next(p for p in packages if p['slug'] == 'south_door_gate')
M = Matrix.Rotation(math.radians(90), 4, 'Z')
pc = coll('东门装甲与门禁_资产包', c_fac)
pc['package_id'] = 'esr_east_door_gate'; pc['block_id'] = BLOCK_ID; pc['asset_id'] = ASSET_ID
gen = coll('制作_东门装甲与门禁', c_src)
east_parts = []
for src_o in gate['parts']:
    dup = src_o.copy(); dup.data = src_o.data.copy()
    dup.name = src_o.name.replace('南门装甲与门禁', '东门装甲与门禁')
    gen.objects.link(dup); dup.matrix_world = M @ world_matrix(src_o)
    east_parts.append(dup)
bpy.context.view_layer.update()
packages.append({'slug': 'east_door_gate', 'name': '东门装甲与门禁', 'category': 'facilities',
                 'collection': pc, 'src_coll': gen, 'parts': east_parts,
                 'delta': 'derived from south_door_gate by Rz(+90) onto the east wall', 'relocated': True,
                 'ownership': 'room_owned_facility',
                 'contract': 'decorative gate frame only; the doorway, lock, switch, prompt, pathing and '
                             'collision stay with Godot'})
log('east door gate derived: %d parts' % len(east_parts))

# --- evaluate each package into 整合主体 + UI灯光_柔和自发光 ------------------
def merge(objs, name, collection):
    verts, faces, uvs, idxs, ml = [], [], [], [], []
    for o in objs:
        me = o.data; off = len(verts)
        W = world_matrix(o)
        verts += [W @ v.co for v in me.vertices]
        uv = me.uv_layers.get('PaletteUV')
        for p in me.polygons:
            faces.append(tuple(off + i for i in p.vertices))
            if uv:
                uvs += [tuple(uv.data[i].uv) for i in p.loop_indices]
            m = me.materials[p.material_index] if me.materials else None
            if m not in ml:
                ml.append(m)
            idxs.append(ml.index(m))
    me = bpy.data.meshes.new(name); me.from_pydata(verts, [], faces)
    for m in ml:
        me.materials.append(m)
    if uvs:
        uv = me.uv_layers.new(name='PaletteUV'); uv.active_render = True
        for i, val in enumerate(uvs):
            uv.data[i].uv = val
    for p, i in zip(me.polygons, idxs):
        p.material_index = i
    o = bpy.data.objects.new(name, me); collection.objects.link(o); return o

for p in packages:
    c = p['collection']
    for emit in (False, True):
        sel = [o for o in p['parts'] if bool(o.data.materials and o.data.materials[0] == mats[3]) == emit]
        if sel:
            merge(sel, p['name'] + ('_UI灯光_柔和自发光' if emit else '_整合主体'), c)
    p['outputs'] = list(c.objects)
    p['parts_bounds'] = obj_bounds(p['parts'])
    p['bounds'] = obj_bounds(p['outputs'])
    p['dims'] = [round(p['bounds'][1][i] - p['bounds'][0][i], 4) for i in range(3)]
    p['merge_consistent'] = same_box(p['parts_bounds'], p['bounds'], 0.02)
log('packages evaluated')

# --- the authored wall / floor MODULES must be replaced by components -------
# Exactly the modules the whitebox art carried, minus FLOOR_BASE, which is the structural base
# plate and stays room-owned (see its package above). Verified against the source inventory.
MODULES_OUT = [n for n in AUTHORED_MODULES if n != 'FLOOR_BASE']
assert len(MODULES_OUT) == 15, 'expected 6 wall + 9 tile modules, found %d: %s' % (
    len(MODULES_OUT), MODULES_OUT)
removed_modules = []
for n in MODULES_OUT:
    o = bpy.data.objects.get(n)
    if o is None:
        continue
    d = o.data; bpy.data.objects.remove(o, do_unlink=True)
    if d and d.users == 0:
        bpy.data.meshes.remove(d)
    removed_modules.append(n)

# --- stale room-owned wall / floor package wrappers must be gone ------------
STALE = ['北墙_资产包', '东墙_资产包', '西墙_资产包', '南门左墙_资产包', '南门右墙_资产包', '南门楣_资产包',
         '承重底板_资产包'] + ['地砖_R%02d_C%02d_资产包' % (r, c) for r in (1, 2, 3) for c in (1, 2, 3)]
removed = []
for n in STALE:
    c = bpy.data.collections.get(n)
    if not c:
        continue
    for o in list(c.objects):
        d = o.data; bpy.data.objects.remove(o, do_unlink=True)
        if d and d.users == 0:
            bpy.data.meshes.remove(d)
    bpy.data.collections.remove(c); removed.append(n)
# the authored (superseded) room-owned wall armour is dropped with its collections
SUPERSEDED = ['制作_北墙', '制作_东墙', '制作_西墙', '制作_南门左墙', '制作_南门右墙', '制作_承重底板']
for n in SUPERSEDED:
    c = bpy.data.collections.get(n)
    if not c:
        continue
    for o in list(c.objects):
        d = o.data; bpy.data.objects.remove(o, do_unlink=True)
        if d and d.users == 0:
            bpy.data.meshes.remove(d)
    bpy.data.collections.remove(c)
for n in ['制作_东墙.001', '制作_南门左墙.001', '制作_南门右墙.001']:
    c = bpy.data.collections.get(n)
    if not c:
        continue
    for o in list(c.objects):
        if o.name.startswith(('AP_', 'WALL_', 'FLOOR_')):
            continue
        d = o.data; bpy.data.objects.remove(o, do_unlink=True)
        if d and d.users == 0:
            bpy.data.meshes.remove(d)
    if not c.objects:
        bpy.data.collections.remove(c)
log('stale packages removed: %d' % len(removed))

# ============================================================ slots
with bpy.data.libraries.load(str(CC), link=False) as (df, dt):
    dt.objects = [n for n in df.objects if n in sum(LIB.values(), [])]
ALL_LIB_PARTS = sum(LIB.values(), [])
by_base = {}
for o in bpy.data.objects:
    if o.name in ALL_LIB_PARTS:
        by_base[o.name] = o
for n in ALL_LIB_PARTS:
    if n not in by_base:
        for o in bpy.data.objects:
            if o.name == n or o.name.startswith(n + '.'):
                by_base[n] = o
                break
assert set(by_base) == set(ALL_LIB_PARTS), sorted(set(ALL_LIB_PARTS) - set(by_base))

SLOTS = []
def place(pid, comp, part_name, loc, rot_deg, role_tag, target, sub=None):
    """Mint one visual-only slot. `pid` is the placement id; `sub` names an extra part
    of the same placement (e.g. the floor tile's inset detail mesh)."""
    sid = pid if sub is None else '%s_%s' % (pid, sub)
    src = by_base[part_name]
    o = bpy.data.objects.new(sid, canonical_mesh(src, remap_materials=True))
    SLOTC[target].objects.link(o)
    # measure the slot against the contract's component box: the placement is only correct if the
    # slot's own geometry lands where the convention says it should
    exp = CONTRACT[comp]['parts'][part_name]
    o.location = Vector(loc)
    o.rotation_euler = (0.0, 0.0, math.radians(rot_deg))
    o['slot_id'] = sid; o['placement_id'] = pid; o['slot_role'] = role_tag
    o['source_component'] = comp; o['source_library_object'] = part_name
    o['source_library'] = CONTRACT[comp]['source_library']
    o['source_canon_sha256'] = exp['canon_sha256']
    o['room_owned_geometry'] = False
    o['export_policy'] = 'reuse_common_component_visual_only'
    o['collision_owner'] = 'godot_0p30m_structural_proxy'
    o['front_direction'] = 'local +Y faces the room interior'
    SLOTS.append({'slot_id': sid, 'placement_id': pid, 'sub_part': sub, 'slot_role': role_tag,
                  'component': comp, 'library_object': part_name,
                  'location': [round(v, 4) for v in loc], 'rotation_z_deg': rot_deg,
                  'local_dims': exp['local_dims'], 'room_owned_geometry': False})
    return o

# walls: N 3 solid | S solid+door+solid | E solid+door+solid | W 3 solid  (runtime layout)
# door_i is the 0-based slot index carrying the doorway; -1 means the side has none.
# local +Y is the component front, so it is rotated to face the room interior.
WALL_LAYOUT = {'north': (3, -1, 180.0), 'south': (3, 1, 0.0), 'east': (3, 1, 90.0), 'west': (3, -1, -90.0)}
for d, (n, door_i, rot) in WALL_LAYOUT.items():
    for i in range(1, n + 1):
        k = i - 1
        if d in ('north', 'south'):
            loc = ((k - 1) * 5.0, ENTRY_CY if d == 'north' else -ENTRY_CY, 0.0)
        else:
            loc = (SIDE_CY if d == 'east' else -SIDE_CY, (k - 1) * 5.0, 0.0)
        pid = 'WALLSLOT_%s_%02d' % (d.upper(), i)
        if k == door_i:
            for suffix, part in (('PIER_L', 'wall_door_5m_门垛左_输出'),
                                 ('PIER_R', 'wall_door_5m_门垛右_输出'),
                                 ('LINTEL', 'wall_door_5m_门楣_输出')):
                place(pid, 'wall_door_5m', part, loc, rot, 'door_wall', d, sub=suffix)
        else:
            place(pid, 'wall_standard_5m', 'wall_standard_5m_主体_输出', loc, rot, 'solid_wall', d)
# door leaves on the two real doorways (S -> hub, E -> facility), filling the component opening
for d, rot in (('south', 0.0), ('east', 90.0)):
    loc = (0.0, -ENTRY_CY, 0.0) if d == 'south' else (SIDE_CY, 0.0, 0.0)
    place('DOORLEAF_' + d.upper(), 'door_5m', 'door_5m_门扇_输出', loc, rot, 'door_leaf', 'door')
# floor: 3x3 5m grid on the structural slab; tile top lands on the 0.30 walkable surface
for r in (1, 2, 3):
    for c in (1, 2, 3):
        comp = 'floor_tile_r01_c01' if (r + c) % 2 == 0 else 'floor_tile_r01_c02'
        pid = 'FLOORSLOT_R%02d_C%02d' % (r, c)
        xyz = ((c - 2) * 5.0, (r - 2) * 5.0, SLAB_Z)
        place(pid, comp, comp + '_主体_输出', xyz, 0.0, 'floor_tile', 'floor')
        place(pid, comp, comp + '_主体_输出.001', xyz, 0.0, 'floor_tile', 'floor', sub='INSET')
c_slot['slot_policy'] = 'shared common_components v003 instance; room owns no wall/floor module geometry'
c_slot['common_library'] = str(CC.relative_to(ROOT))
log('slots placed: %d objects' % len(SLOTS))
for o in by_base.values():
    bpy.data.objects.remove(o, do_unlink=True)

# ============================================================ lighting / camera
for o in list(c_display.objects):
    bpy.data.objects.remove(o, do_unlink=True)
def light(name, loc, energy, color, size):
    dt = bpy.data.lights.new(name, 'AREA'); dt.energy = energy; dt.color = color; dt.shape = 'DISK'; dt.size = size
    o = bpy.data.objects.new(name, dt); c_display.objects.link(o); o.location = loc
    o.rotation_euler = (Vector((0, 0, 1)) - o.location).to_track_quat('-Z', 'Y').to_euler(); return o
light('冷白主光', (-7, -9, 22), 2600, (.63, .78, 1), 11)
light('房间顶反射', (6, 7, 18), 1800, (.4, .66, 1), 9)
light('柔和前侧补光', (-13, -17, 10), 1500, (.72, .82, 1), 12)
light('微暖边缘光', (15, -6, 12), 520, (1, .74, .48), 7)
for x, y in [(0, 7), (7, 3), (-7, 4), (5, -4)]:
    light('蓝色设备反射', (x, y, 5.4), 78, (.08, .48, 1), 2.6)
wd = bpy.data.worlds.new('安全房冷灰展示环境'); scene.world = wd; wd.use_nodes = True
bg = next(n for n in wd.node_tree.nodes if n.type == 'BACKGROUND')
bg.inputs[0].default_value = (.17, .23, .33, 1); bg.inputs[1].default_value = .17
def camera(name, pos, target, ortho):
    dt = bpy.data.cameras.new(name); dt.type = 'ORTHO'; dt.ortho_scale = ortho; dt.clip_end = 300
    o = bpy.data.objects.new(name, dt); c_display.objects.link(o); o.location = pos
    o.rotation_euler = (Vector(target) - o.location).to_track_quat('-Z', 'Y').to_euler(); return o
cam   = camera('01_参考构图_剖切全景', (-30, -35, 34), (0, 0, 2.6), 30)
topc  = camera('02_顶视_完整墙体', (0, 0, 46), (0, 0, 0), 24)
close = camera('03_北墙柜组与破损核心近景', (-1, -12, 10), (0, 6.4, 3.2), 20)
office= camera('04_西北玻璃办公室近景', (-1.0, 0.0, 6.0), (-5.1, 3.3, 1.9), 7.5)
repair= camera('05_东侧维修间与机械臂近景', (14, -6, 8), (5.6, 0.6, 1.6), 18)
scene.camera = cam
scene.render.engine = 'CYCLES'; scene.cycles.samples = 32; scene.cycles.use_denoising = True
scene.render.resolution_x = 1400; scene.render.resolution_y = 1400; scene.render.resolution_percentage = 100
scene.view_settings.view_transform = 'AgX'; scene.view_settings.look = 'AgX - Medium High Contrast'
scene.view_settings.exposure = .60
scene.render.image_settings.file_format = 'PNG'
scene.unit_settings.system = 'METRIC'; scene.unit_settings.scale_length = 1
scene['block_id'] = BLOCK_ID; scene['asset_id'] = ASSET_ID
scene['geometry_source'] = 'whitebox v003 结构信封 + 通用组件 v003 墙地槽位 + 复用 v003 已验收设施'
scene['wall_floor_replacement'] = '房间自有墙体/地砖模块资产已全部移除；墙0地1全部引用 common_components v003'
scene['review_note'] = ('剖切展示层按机位逐面隐藏近侧墙与对应装饰（南/西用于参考全景），'
                        '交付层保留完整 11.9m 墙体；门扇仅在剖切层隐藏。')

for vl in list(scene.view_layers)[1:]:
    scene.view_layers.remove(vl)
full = scene.view_layers[0]
full.name = '01_完整结构_交付'
cut = scene.view_layers.new('02_剖切展示_隐藏近侧墙')
def find_lc(lc, name):
    if lc.name == name:
        return lc
    for ch in lc.children:
        r = find_lc(ch, name)
        if r:
            return r
    return None
# The cutaway layer starts fully visible; each cutaway render hides exactly the walls it needs
# (see the per-camera set_cutaway calls at the render step). The saved state keeps the reference
# overview's {south, west} pair.
CUT_COLLS = ['01_北墙槽位', '02_南墙槽位', '03_东墙槽位', '04_西墙槽位', '05_门扇',
             '墙面装饰_北墙内嵌装甲壁板_资产包', '墙面装饰_南墙内嵌装甲壁板_资产包',
             '墙面装饰_东墙内嵌装甲壁板_资产包', '墙面装饰_西墙内嵌装甲壁板_资产包']
for n in CUT_COLLS:
    lc = find_lc(cut.layer_collection, n)
    assert lc is not None, 'cutaway collection missing: ' + n
    lc.exclude = False
find_lc(cut.layer_collection, '05_门扇').exclude = True   # leaves belong to the hidden walls
full.use = False
cut.use = True

# ============================================================ QA
def diff(n):
    if n not in bpy.data.objects:
        return ['DELETED']
    now = obj_hash(bpy.data.objects[n])
    return [k for k in RO_LOCK[n] if now[k] != RO_LOCK[n][k]]
changed = {n: v for n, v in ((n, diff(n)) for n in RO_LOCK) if v}
moved = [n for n, b in RO_BOX.items()
         if n in bpy.data.objects and not same_box(b, obj_bounds([bpy.data.objects[n]]), 0.001)]
# independent cross-check: the provenance envelope must still equal the whitebox manifest
DECL = wb_manifest['bounds_world_m']
env_ok = same_box(SRC_ENVELOPE['walls'], [DECL['min'], DECL['max']], 0.02)
floor_ok = same_box([[DECL['min'][0], DECL['min'][1], 0.0], [DECL['max'][0], DECL['max'][1], 0.30]],
                    SRC_ENVELOPE['floors'], 0.02)

FORBIDDEN = [(5.0, 0.3, 11.9), (1.4, 0.3, 11.9), (2.2, 0.3, 9.4), (2.2, 0.18, 2.5),
             (15.0, 0.3, 11.9), (4.94, 4.94, 0.04)]
def near(a, b, tol=0.02):
    return all(abs(a[i] - b[i]) <= tol for i in range(3))
slot_objs = [o for c in SLOTC.values() for o in c.objects]
offenders = []
for o in bpy.data.objects:
    if o.type != 'MESH' or o in slot_objs or o.name in RO_LOCK:
        continue
    d = tuple(round(v, 3) for v in o.dimensions)
    if any(near(d, f) for f in FORBIDDEN):
        offenders.append([o.name, list(d)])
hash_ok, role_ok = [], []
for s in SLOTS:
    o = bpy.data.objects[s['slot_id']]
    exp = CONTRACT[s['component']]['parts'][s['library_object']]['canon_sha256']
    hash_ok.append([s['slot_id'], mesh_sig(o.data) == exp])
    role_ok.append([s['slot_id'], set((m.name.split('.')[0] if m else '') for m in o.data.materials) <= set(ROLES)])
placements = lambda role: {s['placement_id'] for s in SLOTS if s['slot_role'] == role}
spec = {}
for s in SLOTS:
    if s['sub_part'] is None:
        spec[s['component']] = spec.get(s['component'], 0) + 1

# --- where the slots actually LAND ------------------------------------------
# The library's parts are authored around their own origin but hang off a ROOT_* empty that
# carries the library's layout position. Canonicalising through the wrong frame still produces
# meshes whose dims and hashes look perfect while the whole ring sits tens of metres away, so
# these three checks measure final world position, not shape.
WALL_PARTS = [o for k in ('north', 'south', 'east', 'west') for o in SLOTC[k].objects]
RING = obj_bounds(WALL_PARTS)
TILE_MAIN = [o for o in SLOTC['floor'].objects if not o.name.endswith('_INSET')]
GRID = obj_bounds(TILE_MAIN)
DECL_LO, DECL_HI = [-7.5, -7.5, 0.0], [7.5, 7.5, 11.9]
ring_ok = same_box(RING, [DECL_LO, DECL_HI], 0.02)
# The tile module is 4.94 m on a 5 m pitch (0.06 m grout), so the 3x3 union is 14.94 m: it must
# COVER the structural inner face (no hole at the wall base) and stay INSIDE the envelope.
INNER_FACE = 7.2
grid_ok = (GRID[0][0] <= -INNER_FACE and GRID[0][1] <= -INNER_FACE and
           GRID[1][0] >= INNER_FACE and GRID[1][1] >= INNER_FACE and
           GRID[0][0] >= -7.5 and GRID[0][1] >= -7.5 and GRID[1][0] <= 7.5 and GRID[1][1] <= 7.5 and
           abs(GRID[0][2] - SLAB_Z) < 0.01 and abs(GRID[1][2] - WALK_Z) < 0.01)
# each door leaf must land inside its own doorway, not somewhere else in the room
LEAF_AT = {'DOORLEAF_SOUTH': (0.0, -ENTRY_CY), 'DOORLEAF_EAST': (SIDE_CY, 0.0)}
leaf_ok = []
for s in SLOTS:
    if s['slot_role'] != 'door_leaf':
        continue
    o = bpy.data.objects[s['slot_id']]
    want = LEAF_AT[s['slot_id']]
    M = world_matrix(o)
    leaf_ok.append([s['slot_id'], abs(M.translation.x - want[0]) < 1e-4 and abs(M.translation.y - want[1]) < 1e-4,
                    [round(M.translation.x, 4), round(M.translation.y, 4)], list(want)])

# decoration must not intrude into either doorway's clear volume (2.2 x 2.5 from the wall base)
DOOR_CLEAR = {'south': ('x', -1.1, 1.1), 'east': ('y', -1.1, 1.1)}
clash = []
for d, parts in ARMOUR_USED:
    axis, lo, hi = DOOR_CLEAR[d]
    ai = 0 if axis == 'x' else 1
    for o in parts:
        b = obj_bounds([o])
        if b[1][ai] > lo and b[0][ai] < hi and b[0][2] < 2.5:
            clash.append(o.name)

def _box(o):
    pts = [world_matrix(o) @ Vector(c) for c in o.bound_box]
    return ([min(p[i] for p in pts) for i in range(3)], [max(p[i] for p in pts) for i in range(3)])
FLOOR_OBJS = set(o.name for o in SLOTC['floor'].objects)
for _pc in c_decor.children:
    if '地面装饰' in _pc.name:
        FLOOR_OBJS |= set(o.name for o in _pc.objects)

# --- the walk plane must have no through-holes ------------------------------
# The 5m floor tile module is 4.94 m wide, so the 3x3 grid leaves a 60 mm grout line at every
# 5 m. Something renderable has to sit under those lines or the room's floor is open to the void.
# This is the check that catches a missing base plate -- no shape or hash test can see it.
COVER_OBJS = []
for o in bpy.data.objects:
    if o.type != 'MESH' or o.name in RO_LOCK or o.get('slot_role') == 'door_leaf':
        continue
    if any(c.hide_render for c in o.users_collection):      # the read-only provenance ring
        continue
    blo, bhi = _box(o)
    if bhi[2] > -0.02 and blo[2] < 0.32:
        COVER_OBJS.append((blo, bhi))
def covered(x, y):
    return any(lo[0] <= x <= hi[0] and lo[1] <= y <= hi[1] for lo, hi in COVER_OBJS)
floor_gaps = []
for u in (-2.5, 2.5):                       # the two interior grout lines each way
    v = -7.4
    while v <= 7.4001:
        if not covered(u, v):
            floor_gaps.append(['x=%.1f' % u, round(v, 2)])
        if not covered(v, u):
            floor_gaps.append([round(v, 2), 'y=%.1f' % u])
        v += 0.2
if not covered(3.74, 3.74):                 # a tile centre must still seat on the plate
    floor_gaps.append(['x=3.74', 'y=3.74'])
plate = next((o for p in packages if p['slug'] == 'floor_base' for o in p['outputs']), None)
PLATE_OK = (plate is not None and
            abs(plate.dimensions[0] - 15.0) < 0.02 and abs(plate.dimensions[1] - 15.0) < 0.02 and
            abs(plate.dimensions[2] - SLAB_Z) < 0.01)

# --- the doorway CORE must be empty -----------------------------------------
# The usable opening is the intersection of the two contracts of record:
#   whitebox v003   bottom_z 0.30 + height 2.5        -> 0.30 .. 2.80
#   shared library  opening 0 .. 2.5 (lintel 9.4 tall)-> 0.00 .. 2.50
# so nothing may be delivered higher than 2.50, and the walkable surface is 0.30.
# Two bands, because "is the opening empty" is not a yes/no question:
#   CORE -- the opening inset 30 mm on every side: a hard gate for WALLS, FACILITIES and WALL
#           DECOR. The floor grid and its trim are excluded: they ARE the threshold surface.
#   EDGE -- the exact 2.2 x 2.5 box, every object, reported with what it eats. This is where the
#           inherited details show up instead of being hidden (the gate's LED strips muzzle
#           ~17 mm into the reveal, the wall-base trim bar crosses the threshold ~7 mm proud, and
#           the shared floor tile carries a raised inlay ~41 mm proud on the c02 variant).
CORE_SKIN = 0.03
DOOR_HEAD_Z = 2.50
DOOR_REVEAL = {'south': (0, 1, -OUTER_FACE, -INNER_FACE),   # (tangential axis, radial axis, r_lo, r_hi)
               'east':  (1, 0, INNER_FACE, OUTER_FACE)}
def _scan(objs, evlo, evhi, ezlo, ezhi):
    """what each object eats out of the opening: (width, height, depth) of the intersection, m"""
    hits = {}
    for d, (ta, ra, rlo, rhi) in DOOR_REVEAL.items():
        for o in objs:
            if o.type != 'MESH' or o.name in RO_LOCK or o.get('slot_role') == 'door_leaf':
                continue
            blo, bhi = _box(o)
            if not (bhi[ra] > rlo and blo[ra] < rhi):
                continue
            eat_w = min(bhi[ta], evhi) - max(blo[ta], evlo)
            eat_h = min(bhi[2], ezhi) - max(blo[2], ezlo)
            eat_d = min(bhi[ra], rhi) - max(blo[ra], rlo)
            if eat_w <= 1e-4 or eat_h <= 1e-4 or eat_d <= 1e-4:
                continue
            hits['%s/%s' % (d, o.name)] = {'eaten_width_m': round(eat_w, 4),
                                           'eaten_height_m': round(eat_h, 4),
                                           'eaten_depth_m': round(eat_d, 4),
                                           'volume_m3': round(eat_w * eat_h * eat_d, 6)}
    return hits
# Scan the INDIVIDUAL parts, not the merged output packages. A package's 整合主体 is the union of
# every part in it, so its bounding box spans the whole package and a door gate -- whose two frame
# piers legitimately flank the opening -- reads as filling it edge to edge.
MERGED_OUT = set(o.name for p in packages for o in p['outputs'])
SCAN = [o for o in bpy.data.objects if o.type == 'MESH' and o.name not in MERGED_OUT]
door_edge = _scan(SCAN, -1.1, 1.1, WALK_Z, DOOR_HEAD_Z)
door_core = sorted(k for k, v in door_edge.items() if k.split('/', 1)[1] not in FLOOR_OBJS
                   and v['eaten_width_m'] > CORE_SKIN and v['eaten_height_m'] > CORE_SKIN
                   and v['eaten_depth_m'] > CORE_SKIN)

# every package must sit inside the room envelope (0.60 allowance for wall-mounted decor)
def inside(b, margin=0.60):
    return (b[0][0] >= -7.5 - margin and b[1][0] <= 7.5 + margin and
            b[0][1] >= -7.5 - margin and b[1][1] <= 7.5 + margin and
            b[0][2] >= -0.01 and b[1][2] <= 11.9 + 0.10)
outside = [p['slug'] for p in packages if not inside(p['bounds'])]

checks = {
    'whitebox_provenance_geometry_untouched': not changed,
    'whitebox_provenance_position_untouched': not moved,
    'whitebox_envelope_matches_manifest': env_ok and floor_ok,
    'merged_output_matches_source_parts': all(p['merge_consistent'] for p in packages),
    'no_room_owned_wall_or_floor_module': not offenders,
    'every_slot_matches_common_library_geometry': all(h[1] for h in hash_ok),
    'every_slot_uses_shared_palette_roles': all(r[1] for r in role_ok),
    'solid_wall_slot_count_10': len(placements('solid_wall')) == 10,
    'door_wall_slot_count_2': len(placements('door_wall')) == 2,
    'door_leaf_count_2': len(placements('door_leaf')) == 2,
    'floor_tile_slot_count_9': len(placements('floor_tile')) == 9,
    'wall_placement_count_12': len(placements('solid_wall') | placements('door_wall')) == 12,
    'stale_room_owned_packages_removed': len(removed) == 16,
    'superseded_wall_floor_modules_removed': len(removed_modules) == 15,
    'structural_base_plate_present': PLATE_OK,
    'walk_plane_has_no_through_holes': not floor_gaps,
    'armour_keeps_both_doorways_clear': not clash,
    'packages_inside_room_envelope': not outside,
    'wall_ring_lands_on_declared_envelope': ring_ok,
    'floor_grid_lands_on_declared_envelope': grid_ok,
    'door_leaves_land_in_their_openings': all(l[1] for l in leaf_ok),
    'doorway_core_is_empty': not door_core,
    'four_material_roles': all(bpy.data.materials.get(n) for n in ROLES),
    'shared_palette_external': not image.packed_file and image.filepath.endswith('设施低亮多巴胺色盘_10x10_512.png'),
    'packages_nonempty': all(len(p['outputs']) > 0 for p in packages),
    'one_output_package_per_object': all(len(o.users_collection) == 1 for p in packages for o in p['outputs']),
    'no_wall_or_floor_asset_id_in_room': not any(o.get('export_policy') == 'reuse_common_component_visual_only'
                                                for o in bpy.data.objects if o not in slot_objs),
}
report = {'passed': all(checks.values()), 'checks': checks,
          'changed_provenance_objects': changed, 'moved_provenance_objects': moved,
          'provenance_envelope': SRC_ENVELOPE, 'whitebox_manifest_bounds': DECL,
          'room_owned_module_offenders': offenders,
          'slot_ring_bounds': RING, 'floor_grid_bounds': GRID, 'door_leaf_placements': leaf_ok,
          'doorway_core_intruders': door_core,
          'doorway_edge_grazes_m': door_edge,
          'doorway_clash_objects': clash, 'packages_outside_envelope': outside,
          'slot_hashes': hash_ok, 'slot_roles': role_ok,
          'component_usage': spec, 'package_count': len(packages),
          'slot_object_count': len(SLOTS), 'slot_placement_count': len({s['placement_id'] for s in SLOTS}),
          'removed_room_owned_packages': removed,
          'removed_wall_floor_modules': removed_modules,
          'floor_gap_samples': floor_gaps[:20],
          'structural_base_plate': {'present': PLATE_OK,
                                    'bounds': obj_bounds([plate]) if plate else None,
                                    'why_room_owned': 'the shared library has no base plate; the '
                                                      'reference room main_room_02/v003 keeps the same '
                                                      'floor/floor_base package (object FLOOR_BASE, '
                                                      '0.26 thick). Its top face is what shows through '
                                                      'the 60 mm grout between the 5 m tile modules.'},
          'door_wall_origin_note': 'common_components origin = wall centreline, so slots sit at +-7.35 '
                                   'and the wall occupies 7.2..7.5, the same occupancy the runtime gets by '
                                   'putting its door-wall node at the outer face 7.5',
          'open_issues': [
              {'id': 'door_clear_height_0p30',
               'detail': 'common_components wall_door_5m lintel is 9.4m tall (local z 2.5..11.9), so the '
                         'opening runs 0..2.5 from the wall base. With the walkable floor top at z=0.30 the '
                         'usable clear height is 2.2m, while whitebox v003 door_contract specifies '
                         'bottom_z 0.30 + height 2.5 (clear 2.5m, lintel 9.1m tall). 0.30m disagreement '
                         'between the shared component library and the whitebox contract; the library was '
                         'used unmodified (GLB is visual-only) and Godot owns the opening.',
               'owner': 'common_components v004 or whitebox contract revision'},
              {'id': 'south_door_off_centre',
               'detail': 'whitebox v003 authored the south doorway on slot centre +2.5 (south wall = 2.5 trim '
                         '+ 5 solid + 5 door + 2.5 trim) and no east doorway. The runtime puts both doorways '
                         'in the middle 5m slot and the 5m shared component cannot represent a 2.5m trim, so '
                         'v006 follows the runtime.',
               'owner': 'user decision, recorded'},
              {'id': 'armour_relaid_for_door_walls',
               'detail': 'the authored south/east wall armour was drawn around the old door positions and '
                         'has been re-laid on the 5m slot grid from the authored north panel unit (2.4m, '
                         'which tiles a 5m slot exactly twice). North and west keep their authored armour '
                         'verbatim because those walls have no doorway.',
               'owner': 'art review'},
              {'id': 'doorway_edge_grazes_sub_5cm',
               'detail': 'measured encroachments into the exact 2.2 x 2.5 opening, none of them '
                         'blocking (the hard CORE gate is empty; Godot owns the opening, the door FSM, '
                         'navigation and collision, and the GLB is visual only). Both doorways carry '
                         'the same set, all inherited from v003 art: the shared floor tile (r01_c02 / '
                         'r02_c03) raises its decorative inlay 41 mm proud of the 0.30 walkable surface '
                         'at the threshold; the gate frame LED strips muzzle 17.5 mm into the clear '
                         'width on each side (the opening is 2.2 m nominal, 2.165 m between strips); '
                         'the wall-base trim bar crosses the threshold 7 mm proud, and an east-wall inlay '
                         'seam 9 mm. See doorway_edge_grazes_m for the full table.',
               'owner': 'art review; cosmetic, no gameplay effect'},
              {'id': 'canonicalisation_frame',
               'detail': 'the shared library authors every wall/floor part at location (0,0,0) with its '
                         'vertices already in the component root-local frame, parented to a ROOT_* empty '
                         'that marks the library layout position. Canonicalising through that root offset '
                         'double-counts it and displaces whole slots by tens of metres while every shape '
                         'hash still agrees. The build now verifies the declared shape convention '
                         '(x/y centred on the origin, z from 0) and the final ring / grid world bounds, '
                         'and qa/verify_entry_safe_room_v006.py re-measures the saved blend independently.',
               'owner': 'common_components v003 contract note'}]}

bpy.ops.wm.save_as_mainfile(filepath=str(BLEND), compress=True)
log('SAVED ' + str(BLEND))
if not FAST:
    # Every cutaway render needs its OWN hidden wall set. Hiding a fixed south+west pair is wrong
    # twice over: the close-up cameras sit outside the room looking in (so with the delivery layer
    # they render a blank wall), and camera 05 looks in through the EAST wall, which that pair does
    # not hide. Hide exactly the walls between each camera and the room.
    # Camera 04 is the exception: it shoots from INSIDE. The glass office is tucked hard into the
    # north-west corner, so any exterior camera has to pierce a wall, and cutting that wall punches
    # a visible hole through the picture. The interior camera hides nothing and instead frames the
    # office against the north server wall, which is also what the room reads as from the doorway.
    def set_cutaway(hidden, tag):
        for d, cn in (('north', '01_北墙槽位'), ('south', '02_南墙槽位'),
                      ('east', '03_东墙槽位'), ('west', '04_西墙槽位')):
            lc = find_lc(cut.layer_collection, cn)
            assert lc is not None, 'cutaway collection missing: ' + cn
            lc.exclude = d in hidden
            dc = find_lc(cut.layer_collection, '墙面装饰_%s墙内嵌装甲壁板_资产包' % ({'north': '北', 'south': '南',
                                                                               'east': '东', 'west': '西'}[d]))
            assert dc is not None, 'cutaway decor collection missing for ' + d
            dc.exclude = d in hidden
        bpy.context.view_layer.update()
        log('cutaway %s hides: %s' % (tag, sorted(hidden)))
    def render(name, camobj, complete, hidden):
        scene.camera = camobj
        full.use = complete; cut.use = not complete
        if not complete:
            set_cutaway(hidden, name)
        scene.render.filepath = str(OUT/'renders'/name)
        bpy.ops.render.render(write_still=True); log('RENDERED ' + name)
    (OUT/'renders').mkdir(parents=True, exist_ok=True)
    render('01_参考全景.png', cam, False, {'south', 'west'})
    render('02_完整结构顶视.png', topc, True, set())
    render('03_北墙柜组与核心近景.png', close, False, {'south'})
    render('04_西北办公室近景.png', office, False, set())
    render('05_东侧维修间与机械臂近景.png', repair, False, {'east'})
    scene.camera = cam
    cut.use = True; set_cutaway({'south', 'west'}, 'saved state'); full.use = False
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND), compress=True)
else:
    log('FAST mode: renders skipped')

dump(OUT/'qa/task_validation.json', report)
dump(OUT/'qa/slot_table.json', {
    'envelope': {'outer_face_m': 7.5, 'centreline_m': 7.35, 'inner_face_m': 7.2, 'wall_thickness_m': 0.30,
                 'visual_height_m': 11.9, 'logical_height_m': 12.0, 'walkable_surface_z_m': 0.30,
                 'slab_top_z_m': 0.26, 'grid_m': 5.0},
    'wall_layout': {'north': '3x solid', 'south': 'solid + door + solid', 'east': 'solid + door + solid',
                    'west': '3x solid', 'doorway_tangential_centre_m': 0.0,
                    'basis': 'runtime probe (runtime probe _probe_safe_room_door.txt)'},
    'runtime_measured': {'door_wall_node_outer_face_m': 7.5, 'door_pier_offset_m': 1.8,
                         'door_lintel_bottom_m': 2.5, 'door_clear_width_m': 2.2, 'door_clear_height_m': 2.5},
    'component_usage': {'wall_standard_5m': 10, 'wall_door_5m': 2, 'door_5m': 2, 'floor_tile': 9},
    'slots': SLOTS, 'removed_room_owned_packages': removed})
dump(OUT/'qa/common_component_contract.json', CONTRACT)
dump(OUT/'qa/armour_relayout.json', {
    'unit': {'name': panel_src.name, 'cap': cap_src.name, 'width_m': PLATE_W, 'source': '制作_北墙.001'},
    'rule': '2x2.4m panel + cap per 5m slot, 0.05 inset at the slot edge, door slot skipped',
    'walls': {d: {'objects': len(ps), 'rotation_z_deg': WALL_ROT[d]} for d, ps in ARMOUR_USED},
    'reused_verbatim': ['north', 'west']})
for p in packages:
    dump(OUT/'component_packages_v006'/p['category']/p['slug']/'asset_manifest.json',
         {'package_id': 'esr_' + p['slug'], 'asset_id': ASSET_ID, 'name': p['name'], 'slug': p['slug'],
          'category': p['category'], 'version': 'v006', 'block_id': BLOCK_ID, 'floor_range': FLOOR_RANGE,
          'design_scope': SCOPE, 'scene_design_docs': DOCS, 'asset_ledger': LEDGER,
          'source_blend': str(BLEND.relative_to(ROOT)), 'blender_collection': p['collection'].name,
          'objects': [o.name for o in p['outputs']], 'root_objects': [o.name for o in p['outputs']],
          'world_delta': p['delta'], 'relocated_from_v003': p['relocated'],
          'local_origin': 'package bounds bottom-centre in blender world space',
          'forward': 'Blender -Y / Godot -Z', 'bounds': p['bounds'], 'dimensions': p['dims'],
          'material_roles': ROLES, 'emission': any('UI灯光' in o.name for o in p['outputs']),
          'animation': False, 'dependencies': [],
          'geometry_ownership': p['ownership'],
          'structural_geometry': ('load-bearing base slab at z 0..0.26' if p['slug'] == 'floor_base'
                                  else 'none: no wall/floor module, no collision shape'),
          'replacement_contract': p['contract'],
          'exported': False, 'expected_export': p['slug'] + '_v006.glb',
          'collision_status': '未制作；玩法碰撞由 Godot 0.30m 结构代理负责'})
dump(OUT/'component_packages_v006/catalog.json',
     [{'package_id': 'esr_' + p['slug'], 'asset_id': ASSET_ID, 'name': p['name'], 'slug': p['slug'],
       'category': p['category'], 'version': 'v006', 'objects': [o.name for o in p['outputs']],
       'bounds': p['bounds'], 'dimensions': p['dims'], 'exported': False,
       'expected_export': p['slug'] + '_v006.glb'} for p in packages])
(OUT/'component_packages_v006/tree.txt').write_text(
    '\n'.join(p['category'] + '/' + p['slug'] + ' / ' + p['collection'].name for p in packages), encoding='utf8')
log('checks failed: %s' % [k for k, v in checks.items() if not v])
log('manifests: %d packages | checks passed=%s' % (len(packages), all(checks.values())))
log('FINISHED')
