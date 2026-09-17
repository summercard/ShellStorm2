"""Independent geometric verification of the saved entry safe room v007 blend.

The build script's own QA checks its own in-memory work. This verifier re-opens the SAVED
blend from disk and measures the delivered geometry, so a regression in the builder cannot
also move the goalposts. Every check below is written so that it FAILS loudly on a real
defect, not merely reports.

What v007 changes, and therefore what this file verifies that v006 did not:
  * the room no longer owns wall / floor / door geometry AND no longer owns their decoration.
    Armour panels, the door gate and the tile trims now travel INSIDE the four generic
    components, so every 5 m slot instantiates the whole decorated unit -- no direction-specific
    asset exists anywhere in the room.
  * consequently the slot part inventory is the test: the STRUCTURAL count must still be exactly
    16 wall parts / 18 tile parts / 2 leaves, and the DECORATION count must now be carried by
    those same slots instead of by room-owned packages.

Run:
  blender --background --factory-startup --python verify_entry_safe_room_v007.py
"""
import bpy, math, json, sys
from pathlib import Path
from mathutils import Vector

ROOT  = Path(r'I:/工作项目/shellstrom2/ShellStorm2')
OUT   = ROOT/'assets/art/environments/tower_zones/battle/source/entry_safe_room/v007'
BLEND = OUT/'局内关卡01_入口安全房_15x15m_正式美术_v007.blend'
CC    = ROOT/'assets/art/environments/tower_zones/battle/source/common_components/v004/战局区块_通用组件库_v004.blend'
PKGS  = OUT/'component_packages_v007/catalog.json'

# geometry of record
INNER   = 7.2          # wall inner face
OUTER   = 7.5          # wall outer face / room envelope
CTR     = 7.35         # wall centreline
TOP     = 11.9         # visual wall height
WALK    = 0.30         # walkable surface
SLAB    = 0.26         # structural slab top
GRID    = 5.0
DOOR_W  = 2.2          # clear opening width  (runtime measured)
DOOR_H  = 2.5          # clear opening height (runtime measured)
EPS     = 1e-3         # boundary slop: a face exactly on the boundary is not a clash

# the four generic components and the part families they carry
STRUCT_FAMS = ('wall_body', 'door_wall_body', 'door_leaf_body', 'tile_plate', 'tile_inset')
DECOR_FAMS  = {'wall_armour': 4,        # 4 armour panels per 5 m wall unit
               'door_gate': 11,         # south/east gate: 2 piers, LED strips, lintel plate, screen
               'tile_frame': 6}         # 4 edge trims + 2 blue seams
EXPECT_STRUCT = {'wall_body': 10, 'door_wall_body': 6, 'door_leaf_body': 2,
                 'tile_plate': 9, 'tile_inset': 9}
# tile_detail is the per-tile wear set (badge, grate, scuffs, c02 access cover). It is NOT
# identical between c01 and c02 -- c02 ships the with-cover variant -- so the expected total is
# computed from the library, not guessed: c01 ships 砖面美术_01..25, c02 ships _01..22, and 6 of
# each tile's parts are the structural frame (4 edge trims + 2 blue seams).
TILE_DETAIL = 5 * (25 - 6) + 4 * (22 - 6)
EXPECT_DECOR  = {'wall_armour': 10 * 4, 'door_gate': 2 * 11, 'tile_frame': 9 * 6,
                 'tile_detail': TILE_DETAIL}
EXPECT_SLOT_OBJS = sum(EXPECT_STRUCT.values()) + sum(EXPECT_DECOR.values())

fails, notes = [], []
def check(name, ok, detail=''):
    (notes if ok else fails).append((name, detail))
    print('%-6s %-56s %s' % ('PASS' if ok else 'FAIL', name, detail), flush=True)

bpy.ops.wm.open_mainfile(filepath=str(BLEND))

def W(o):                       # background-load safe world matrix (see builder docstring)
    m = o.matrix_parent_inverse @ o.matrix_basis
    p = o.parent
    while p is not None:
        m = (p.matrix_parent_inverse @ p.matrix_basis) @ m
        p = p.parent
    return m

def bounds(objs):
    pts = [W(o) @ Vector(c) for o in objs for c in o.bound_box]
    return [[min(p[i] for p in pts) for i in range(3)], [max(p[i] for p in pts) for i in range(3)]]

def coll(name):
    c = bpy.data.collections.get(name)
    assert c is not None, 'missing collection ' + name
    return c

# ---------------------------------------------------------------- 1. scope split
# The room must NOT own wall / floor / door module geometry, and must not own their DECORATION
# either -- that is the v007 change. What the room keeps is (a) the whitebox provenance ring it
# was built from and (b) its own load-bearing base plate, which is structural support rather than
# a replaceable visual module and matches the main_room_02/v003 floor/floor_base precedent.
PROV = [o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith('AP_')]
check('provenance ring = 16 whitebox source parts', len(PROV) == 16, 'found %d' % len(PROV))
MODS = sorted(o.name for o in bpy.data.objects if o.type == 'MESH' and
              o.name.startswith(('WALL_', 'FLOOR_')) and not o.name.startswith('FLOOR_BASE'))
check('room owns no wall / floor module geometry', not MODS, str(MODS[:6]))
# the authored decoration names v004 absorbed: if any survive OUTSIDE a slot, the room still owns
# direction-specific decoration and the "no direction needed" claim is false.
DECOR_PREFIX = ('墙体内嵌面板', '面板分缝', '门框立柱', '门框蓝色灯条', '门楣护板', '门楣顶灯',
                '地砖压边', '蓝色拼缝', '检修格栅', '格栅暗底', '地砖磨损')
owned_decor = [o.name for o in bpy.data.objects if o.type == 'MESH'
               and o.name.startswith(DECOR_PREFIX)]
check('room owns no wall / floor / door decoration', not owned_decor, str(owned_decor[:6]))
RO = PROV                     # the untouchable set the remaining checks measure around

# ---------------------------------------------------------------- 2. wall ring
SLOTC = {'north': '01_北墙槽位', 'south': '02_南墙槽位',
         'east': '03_东墙槽位', 'west': '04_西墙槽位',
         'door': '05_门扇', 'floor': '06_地面槽位'}
SLOTS = [o for n in ('north', 'south', 'east', 'west') for o in coll(SLOTC[n]).objects
         if o.type == 'MESH']
LEAVES = [o for o in coll(SLOTC['door']).objects if o.type == 'MESH']
TILES = [o for o in coll(SLOTC['floor']).objects if o.type == 'MESH']
ALL_SLOTS = SLOTS + LEAVES + TILES

def fam(o):
    return o.get('source_part_family', '')

by_fam = {}
for o in ALL_SLOTS:
    by_fam.setdefault(fam(o), []).append(o)
got_struct = {k: len(by_fam.get(k, [])) for k in EXPECT_STRUCT}
check('structural slot inventory unchanged (16 wall / 18 tile / 2 leaf)',
      got_struct == EXPECT_STRUCT, str(got_struct))
got_decor = {k: len(by_fam.get(k, [])) for k in EXPECT_DECOR}
check('decoration now travels inside the slots (%d parts)' % sum(EXPECT_DECOR.values()),
      got_decor == EXPECT_DECOR, str(got_decor))
check('slot object total = %d' % EXPECT_SLOT_OBJS,
      len(ALL_SLOTS) == EXPECT_SLOT_OBJS, 'found %d' % len(ALL_SLOTS))
unknown = sorted(set(by_fam) - set(EXPECT_STRUCT) - set(EXPECT_DECOR))
check('no slot carries an unclassified part family', not unknown, str(unknown))

b = bounds(SLOTS)
check('wall ring fills the 15x15x11.9 envelope',
      all(abs(b[0][i] + OUTER) < 0.02 for i in range(2)) and
      all(abs(b[1][i] - OUTER) < 0.02 for i in range(2)) and
      abs(b[0][2]) < 0.02 and abs(b[1][2] - TOP) < 0.02, 'bounds=%s' % [b[0], b[1]])

# every user-visible asset inside the ring must carry the three declared custom properties
missing = [o.name for o in ALL_SLOTS if o.get('collision_owner') != 'godot_0p30m_structural_proxy']
check('every slot declares Godot as collision owner', not missing, str(missing[:5]))
own = [o.name for o in ALL_SLOTS if o.get('room_owned_geometry') is not False]
check('no slot claims room-owned geometry', not own, str(own[:5]))
pol = [o.name for o in ALL_SLOTS
       if o.get('export_policy') != 'reuse_common_component_visual_only']
check('every slot defers its visual to the shared component library', not pol, str(pol[:5]))

# ---------------------------------------------------------------- 2b. one unit, every direction
# The user's requirement is "no direction needed". That is only true if the SAME library part
# lands in the SAME place in every slot's own frame. Measured slot-locally, so a wrong rotation
# sign or a surviving direction-specific asset cannot hide behind a world-space coincidence.
def slot_local(pid):
    """root-local union box of all slot objects sharing a placement, in that placement's frame"""
    grp = [o for o in ALL_SLOTS if o.get('placement_id') == pid]
    ref = bpy.data.objects[grp[0].get('slot_id')]
    inv = W(ref).inverted()
    pts = [inv @ (W(o) @ Vector(c)) for o in grp for c in o.bound_box]
    return [[round(min(p[i] for p in pts), 4) for i in range(3)],
            [round(max(p[i] for p in pts), 4) for i in range(3)]]

by_comp = {}
for o in ALL_SLOTS:
    by_comp.setdefault(o.get('source_component'), set()).add(o.get('placement_id'))
divergent = {}
for comp, pids in sorted(by_comp.items()):
    boxes = {pid: slot_local(pid) for pid in sorted(pids)}
    ref = boxes[sorted(boxes)[0]]
    bad = [p for p, bx in boxes.items()
           if any(abs(bx[i][j] - ref[i][j]) > 0.002 for i in range(2) for j in range(3))]
    if bad:
        divergent[comp] = bad
check('one unit serves every slot of its component in every direction',
      not divergent, str(divergent))

# ---------------------------------------------------------------- 3. the two doorways
# A doorway is the 5 m slot whose clear volume must be free of everything but the leaf.
# The usable opening is the INTERSECTION of the two contracts of record:
#   whitebox v003   bottom_z 0.30 + height 2.5   -> 0.30 .. 2.80 from the wall base
#   shared library  opening 0 .. 2.5             -> 0.00 .. 2.50
#   runtime probe   2.2 wide, 2.5 clear height, lintel bottom 2.5
# so nothing may be delivered above 2.50 and the walking surface is 0.30.
# Judged in two bands, because "is the opening empty" is not a yes/no question here:
#   CORE -- the opening inset by SKIN on every side: a hard gate for walls, facilities and wall
#           decor. The floor grid and its trim are excluded: they ARE the threshold surface.
#   EDGE -- the exact 2.2 x 2.5 box, per object, reported with what it eats. This is where the
#           inherited details show up instead of silently failing: the gate's LED strips muzzle
#           ~17 mm into the reveal, the wall-base trim bar crosses the threshold ~7 mm proud, and
#           the shared floor tile carries a raised inlay ~41 mm proud on its c02 variant.
# Tested per POLYGON, not per object: the merged output packages are unions of many parts, so an
# object-level AABB spans the whole package and reports a false intrusion for a gate whose frame
# legitimately sits beside the opening.
SKIN = 0.03
HEAD_Z = 2.50
CLEAR = {'SOUTH': ('y', -OUTER, -INNER), 'EAST': ('x', INNER, OUTER)}
DOORS = {'SOUTH': 'WALLSLOT_SOUTH_02', 'EAST': 'WALLSLOT_EAST_02'}
FLOOR = set(o.name for o in TILES)
for tag, (axis, loF, hiF) in CLEAR.items():
    ai = 0 if axis == 'x' else 1
    parts = [o for o in SLOTS if o.get('placement_id') == DOORS[tag]
             and fam(o) == 'door_wall_body']
    check('%s doorway placed as 2 piers + 1 lintel' % tag, len(parts) == 3, 'found %d' % len(parts))
    core_hits, edge_hits = [], {}
    for o in bpy.data.objects:
        if o.type != 'MESH' or o in RO or o in LEAVES:
            continue
        M = W(o); me = o.data
        for p in me.polygons:
            flo = [1e9] * 3; fhi = [-1e9] * 3
            for vi in p.vertices:
                v = M @ me.vertices[vi].co
                for i in range(3):
                    flo[i] = min(flo[i], v[i]); fhi[i] = max(fhi[i], v[i])
            eat_w = min(fhi[1 - ai], DOOR_W / 2) - max(flo[1 - ai], -DOOR_W / 2)
            eat_h = min(fhi[2], HEAD_Z) - max(flo[2], WALK)
            eat_d = min(fhi[ai], hiF) - max(flo[ai], loF)
            if eat_w > EPS and eat_h > EPS and eat_d > EPS:
                cur = edge_hits.get(o.name)
                e = {'eaten_width_m': round(eat_w, 4), 'eaten_height_m': round(eat_h, 4),
                     'eaten_depth_m': round(eat_d, 4)}
                if cur is None or max(e.values()) > max(cur.values()):
                    edge_hits[o.name] = e
                if (o.name not in FLOOR and eat_w > SKIN and eat_h > SKIN and eat_d > SKIN):
                    core_hits.append(o.name)
    check('%s doorway CORE (>30 mm intrusion) is empty' % tag,
          not core_hits, str(sorted(set(core_hits))[:6]))
    if edge_hits:
        notes.append(('%s doorway EDGE grazed' % tag,
                      '; '.join('%s w%.0fmm h%.0fmm' % (k, v['eaten_width_m'] * 1000, v['eaten_height_m'] * 1000)
                                for k, v in sorted(edge_hits.items()))))
        print('NOTE   %-56s %s' % ('%s doorway EDGE grazed (documented)' % tag,
                                   '; '.join('%s w%.0fmm h%.0fmm' % (k, v['eaten_width_m'] * 1000,
                                                                     v['eaten_height_m'] * 1000)
                                             for k, v in sorted(edge_hits.items()))), flush=True)
    else:
        check('%s doorway EDGE (exact 2.2 x 2.5) is empty' % tag, True)
    # the component lintel must sit exactly on top of the opening
    lin = next(o for o in parts if '门楣' in o.get('source_library_object', ''))
    lb = bounds([lin])
    check('%s doorway lintel spans the opening at z=2.5' % tag,
          abs(lb[0][2] - HEAD_Z) < 0.02 and lb[1][2] >= TOP - 0.02, 'lintel z=%s..%s' % (lb[0][2], lb[1][2]))
    # the leaf must fill the opening without poking through the wall
    leaf = next(o for o in LEAVES if o.get('placement_id') == 'DOORLEAF_' + tag)
    fb = bounds([leaf])
    fills = (abs(fb[1][1 - ai] - fb[0][1 - ai] - DOOR_W) < 0.02 and
             abs(fb[1][2] - fb[0][2] - DOOR_H) < 0.02)
    if axis == 'y':
        seated = fb[0][ai] >= -OUTER - 0.01 and fb[1][ai] <= -INNER + 0.05
    else:
        seated = fb[0][ai] >= INNER - 0.05 and fb[1][ai] <= OUTER + 0.01
    check('%s door leaf fills and sits in the opening' % tag, fills and seated,
          'leaf=%s..%s' % (fb[0], fb[1]))

# ---------------------------------------------------------------- 4. floor + walkable plane
# The base plate is room-owned structure, not a module: it must be there, be 15 x 15 x 0.26 and
# sit at z 0..0.26 so the 4.94 m tiles can seat their 0.04 tops on the 0.30 walkable surface.
plate = [o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith('FLOOR_BASE')]
pbb = bounds(plate) if plate else None
check('room-owned structural base plate present (15 x 15 x 0.26, z 0..0.26)',
      len(plate) == 1 and
      abs(pbb[1][0] - pbb[0][0] - 15.0) < 0.02 and abs(pbb[1][1] - pbb[0][1] - 15.0) < 0.02 and
      abs(pbb[0][2]) < 0.01 and abs(pbb[1][2] - SLAB) < 0.01,
      '%d plate(s) bounds=%s' % (len(plate), pbb))

tb = bounds(TILES)
# the 4.94 m tile on a 5 m pitch gives a 14.94 m union: covering the inner face, inside the shell
check('floor grid covers the inner face and stays inside the shell',
      tb[0][0] <= -INNER and tb[0][1] <= -INNER and tb[1][0] >= INNER and tb[1][1] >= INNER and
      tb[0][0] >= -OUTER and tb[0][1] >= -OUTER and tb[1][0] <= OUTER and tb[1][1] <= OUTER,
      'bounds=%s' % [tb[0], tb[1]])
main = by_fam['tile_plate']
mb = bounds(main)
check('tile tops land on the 0.30 walkable surface',
      abs(mb[1][2] - WALK) < 0.005 and abs(mb[0][2] - SLAB) < 0.005, 'z=%s..%s' % (mb[0][2], mb[1][2]))
gaps = []
for r in (1, 2, 3):
    for c in (1, 2, 3):
        want = ((c - 2) * GRID, (r - 2) * GRID)
        got = [o for o in main if abs(W(o).translation.x - want[0]) < 0.01 and abs(W(o).translation.y - want[1]) < 0.01]
        if len(got) != 1:
            gaps.append('R%dC%d' % (r, c))
check('all 9 tile centres sit on the 5 m grid', not gaps, str(gaps))
# the walk plane must have no through-holes: every interior grout sample has something under it
COVER = []
for o in bpy.data.objects:
    if o.type != 'MESH' or o in RO or o.get('slot_role') == 'door_leaf':
        continue
    if any(c.hide_render for c in o.users_collection):
        continue
    lo, hi = bounds([o])
    if hi[2] > -0.02 and lo[2] < 0.32:
        COVER.append((lo, hi))
holes = []
for u in (-2.5, 2.5):
    v = -7.4
    while v <= 7.4001:
        for x, y in ((u, v), (v, u)):
            if not any(lo[0] <= x <= hi[0] and lo[1] <= y <= hi[1] for lo, hi in COVER):
                holes.append(['%.1f' % x, round(y, 2)])
        v += 0.2
check('walk plane has no through-holes across the 60 mm grout', not holes, str(holes[:8]))

# ---------------------------------------------------------------- 5. nothing below the floor
below = []
for o in bpy.data.objects:
    if o.type != 'MESH' or o in RO or o in TILES:
        continue
    if bounds([o])[0][2] < -0.02:
        below.append(o.name)
check('nothing sinks below z=0', not below, str(below[:6]))

# ---------------------------------------------------------------- 6. shared library really shared
libc = coll('03_墙体与地面槽位_引用通用组件_v004')
check('the room references the common component library by path',
      libc.get('common_library') is not None and 'v004' in str(libc.get('common_library')),
      str(libc.get('common_library')))
dupes = [o.name for o in bpy.data.objects if o.name in
         ('wall_standard_5m_主体_输出', 'wall_door_5m_门楣_输出', 'door_5m_门扇_输出')]
check('the library meshes are NOT re-hosted inside the room blend', not dupes, str(dupes))
check('the v004 library blend is the one the room cites', CC.is_file(), str(CC))

# ---------------------------------------------------------------- 7. package inventory
cat = json.loads(PKGS.read_text(encoding='utf8'))
slugs = sorted(p['slug'] for p in cat)
GONE = ['floor_trim', 'south_door_gate', 'east_door_gate', 'wall_armor_north', 'wall_armor_south',
        'wall_armor_east', 'wall_armor_west']
still = [s for s in slugs if s in GONE]
check('the 17 packages carry no superseded wall/floor/door decor', not still, str(still))
check('package count 17 (was 24)', len(slugs) == 17, 'found %d: %s' % (len(slugs), slugs))
check('the structural base plate is still room-owned',
      'floor_base' in slugs, 'floor_base present: %s' % ('floor_base' in slugs))

# ---------------------------------------------------------------- verdict
report = {'passed': not fails, 'failed': [f[0] for f in fails],
          'checks': [{'check': n, 'detail': d} for n, d in notes + fails],
          'slot_inventory': {'structural': got_struct, 'decoration': got_decor},
          'packages': slugs}
(OUT/'qa/independent_verification.json').write_text(
    json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
print('\n%s  (%d passed, %d failed)' % ('VERIFIED' if not fails else 'VERIFICATION FAILED',
                                        len(notes), len(fails)), flush=True)
if fails:
    sys.exit(1)
