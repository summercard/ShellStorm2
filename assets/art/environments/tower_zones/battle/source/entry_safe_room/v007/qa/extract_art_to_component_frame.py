"""Extract the room's wall / floor / door art in COMMON-COMPONENT LOCal frames.

Why
  The user wants the wall art (armour panels), the floor tile art, the door walls and the doors
  to stop being room-owned ORIENTED packages and instead be baked into the four common
  components, so an instance placed on the 5 m grid lines up automatically with no
  per-direction handling.

  Every piece of that art already sits at the right world position in the room blend. The only
  thing missing is its expression in the component's own frame: origin = bottom-edge centre,
  local +Y = the face that looks into the room. So this probe measures, per slot,
      local = T_slot^-1 @ world,      T_slot = Translation(slot_loc) @ RotZ(slot_rot)
  and then checks that the SAME local geometry falls out of every slot of a family. If it does,
  one unit can be baked into the component and it will land identically anywhere.

  It also reports where the families DISAGREE, because those places are exactly the
  orientation-dependence the user wants removed.

Read-only.

Run:
  blender --background --factory-startup --python extract_art_to_component_frame.py
"""
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector, Matrix

ROOT = Path(r'I:/工作项目/shellstrom2/ShellStorm2')
BATTLE = ROOT / 'assets/art/environments/tower_zones/battle'
LIB3 = BATTLE / 'source/common_components/v003/战局区块_通用组件库_v003.blend'
ROOM6 = BATTLE / 'source/entry_safe_room/v006/局内关卡01_入口安全房_15x15m_正式美术_v006.blend'
RECOVERED = Path(r'I:/工作项目/shellstrom2/_scratch/esr_recover/v003_recovered.blend')

ENTRY_CY = SIDE_CY = 7.35
ROLES = ['01_精工金属_紫色骨架', '02_细腻哑光_青绿大面', '03_清漆反光_紫粉点缀', '04_柔和自发光_UI灯光']

# same table the room build uses
WALL_LAYOUT = {'north': ((0.0, ENTRY_CY, 0.0), 180.0),
               'south': ((0.0, -ENTRY_CY, 0.0), 0.0),
               'east': ((SIDE_CY, 0.0, 0.0), 90.0),
               'west': ((-SIDE_CY, 0.0, 0.0), -90.0)}
SLOT_PITCH = 5.0


def W(o):
    m = o.matrix_parent_inverse @ o.matrix_basis
    p = o.parent
    while p is not None:
        m = (p.matrix_parent_inverse @ p.matrix_basis) @ m
        p = p.parent
    return m


def slot_matrix(direction, i):
    """Centre slot i (1..3) of a wall. i=2 is the middle one at the tangential origin."""
    base, rot = WALL_LAYOUT[direction]
    b = Vector(base)
    if direction in ('north', 'south'):
        loc = Vector((b.x + (i - 2) * SLOT_PITCH, b.y, 0.0))
    else:
        loc = Vector((b.x, b.y + (i - 2) * SLOT_PITCH, 0.0))
    return Matrix.Translation(loc) @ Matrix.Rotation(math.radians(rot), 4, 'Z')


def loose_parts(o):
    """Connected-component decomposition -> per-part vertex index sets + material."""
    me = o.data
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
        r = find(p.vertices[0])
        groups.setdefault(r, {'verts': set(), 'mat': None})
        groups[r]['verts'].update(p.vertices)
        if groups[r]['mat'] is None and me.materials:
            groups[r]['mat'] = me.materials[p.material_index].name.split('.')[0]
    return [g['verts'] for g in groups.values()], [g['mat'] for g in groups.values()]


def part_boxes(o, world_to_local):
    """Per loose part: bounds + material, in the given target frame."""
    verts_list, mats = loose_parts(o)
    Wm = W(o)
    out = []
    for idxs, mat in zip(verts_list, mats):
        pts = [world_to_local @ (Wm @ o.data.vertices[i].co) for i in idxs]
        lo = [q(min(p[i] for p in pts)) for i in range(3)]
        hi = [q(max(p[i] for p in pts)) for i in range(3)]
        out.append({'mat': mat, 'lo': lo, 'hi': hi,
                    'ctr': [q((lo[i] + hi[i]) / 2.0) for i in range(3)]})
    out.sort(key=lambda d: (round(d['ctr'][0], 3), round(d['ctr'][1], 3), round(d['ctr'][2], 3)))
    return out


def q(x, n=5):
    r = round(x, n)
    return 0.0 if r == 0 else r


report = {}

# ============================================================ library material inventory
bpy.ops.wm.open_mainfile(filepath=str(LIB3))
report['library'] = {
    'roles_present': {r: (bpy.data.materials.get(r) is not None) for r in ROLES},
    'materials_total': len(bpy.data.materials),
    'blend_size_bytes': LIB3.stat().st_size,
}

# ============================================================ wall armour, per slot frame
bpy.ops.wm.open_mainfile(filepath=str(ROOM6))
armour = {}
for d in ('north', 'south', 'east', 'west'):
    cn = '墙面装饰_%s内嵌装甲壁板_资产包' % {'north': '北墙', 'south': '南墙',
                                              'east': '东墙', 'west': '西墙'}[d]
    c = bpy.data.collections.get(cn)
    if not c:
        armour[d] = None
        continue
    objs = [o for o in c.objects if o.type == 'MESH']
    per_slot = {}
    for i in (1, 2, 3):
        M = slot_matrix(d, i).inverted()
        boxes = []
        for o in objs:
            for b in part_boxes(o, M):
                # Keep only the parts of THIS 5 m slot. The component's local X is always the
                # 5 m width, so the wall's tangential axis is local X for every direction --
                # reading local Y here instead (the first cut of this probe) swept the
                # neighbouring slot's panels into the window and made the east wall look wrong.
                u = b['ctr'][0]
                if -SLOT_PITCH / 2.0 - 1e-6 <= u <= SLOT_PITCH / 2.0 + 1e-6:
                    boxes.append(b)
        per_slot[i] = boxes
    # the door slots carry nothing; report every slot so the door gap is visible
    armour[d] = {str(k): v for k, v in per_slot.items()}
report['wall_armour'] = armour

# ============================================================ door gate, door-slot frame
# Read this while the ROOM blend is still open. The first cut of this probe ran it after the
# floor block had already opened the recovered v003 blend, so it silently measured the
# pre-fix gate (frame centre +2.5, the very offset the room build re-centres by dx=-2.5).
def gate_collection(prefix):
    """Pick the CURRENT gate collection by geometry, so a stale leftover cannot win."""
    cands = [c for c in bpy.data.collections if c.name.split('.')[0] == prefix]
    best, best_err = None, None
    for c in cands:
        objs = [o for o in c.objects if o.type == 'MESH']
        if not objs:
            continue
        piers = [o for o in objs if '门框立柱' in o.name]
        if piers:
            pp = [W(o) @ Vector(corner) for o in piers for corner in o.bound_box]
            u = (min(p[0] for p in pp) + max(p[0] for p in pp)) / 2.0
        else:
            pts = [W(o) @ Vector(corner) for o in objs for corner in o.bound_box]
            u = (min(p[0] for p in pts) + max(p[0] for p in pts)) / 2.0
        if best_err is None or abs(u) < best_err:
            best, best_err = c, abs(u)
    return best, len(cands)


gates = {}
gate_audit = {}
for d, prefix in (('south', '南门装甲与门禁_资产包'), ('east', '东门装甲与门禁_资产包')):
    c, n_cands = gate_collection(prefix)
    gate_audit[d] = {'candidates': n_cands, 'chosen': c.name if c else None}
    if not c:
        gates[d] = None
        continue
    M = slot_matrix(d, 2).inverted()
    boxes = []
    for o in sorted((x for x in c.objects if x.type == 'MESH'), key=lambda x: x.name):
        for b in part_boxes(o, M):
            b['src'] = o.name
            boxes.append(b)
    gates[d] = boxes
report['door_gates'] = gates
report['door_gate_audit'] = gate_audit

# ============================================================ blend hygiene audit
# Every collection whose base name collides with another is a stale duplicate: the recovered
# v003 artwork already used these names, so the v006 rebuild minted `.001` siblings while the
# originals stayed put. Duplicated slots mean coincident doubled geometry.
by_base = {}
for c in bpy.data.collections:
    by_base.setdefault(c.name.split('.')[0], []).append(c.name)
report['duplicate_collections'] = {k: v for k, v in sorted(by_base.items()) if len(v) > 1}
dup_geom = {}
for k, names in report['duplicate_collections'].items():
    boxes = []
    for n in names:
        c = bpy.data.collections[n]
        objs = [o for o in c.objects if o.type == 'MESH']
        if not objs:
            continue
        pts = [W(o) @ Vector(corner) for o in objs for corner in o.bound_box]
        boxes.append({'coll': n,
                      'lo': [q(min(p[i] for p in pts), 4) for i in range(3)],
                      'hi': [q(max(p[i] for p in pts), 4) for i in range(3)]})
    dup_geom[k] = boxes
report['duplicate_collection_geometry'] = dup_geom

# ============================================================ floor tile art, tile frame
bpy.ops.wm.open_mainfile(filepath=str(RECOVERED))
tiles = {}
for r in (1, 2, 3):
    for c in (1, 2, 3):
        cn = '制作_地砖_R%02d_C%02d.001' % (r, c)
        col = bpy.data.collections.get(cn)
        if not col:
            tiles['%d%d' % (r, c)] = None
            continue
        centre = Vector(((c - 2) * SLOT_PITCH, (r - 2) * SLOT_PITCH, 0.26))
        M = Matrix.Translation(centre).inverted()
        boxes = []
        for o in sorted((x for x in col.objects if x.type == 'MESH'), key=lambda x: x.name):
            if o.name.startswith(('FLOOR_', 'AP_')):
                continue                       # the tile MODULE itself, not its detail
            for b in part_boxes(o, M):
                b['src'] = o.name
                boxes.append(b)
        tiles['%d%d' % (r, c)] = boxes
report['floor_tiles'] = tiles

out = BATTLE / 'source/entry_safe_room/v006/qa/_extract_component_frames.json'
out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')

# ------------------------------------------------------------------------ console digest
print('=' * 88)
print('library roles present:', report['library']['roles_present'])
print('-' * 88)
for d, slots in report['wall_armour'].items():
    print('WALL ARMOUR %s' % d)
    for i, boxes in slots.items():
        print('   slot %s  n=%d' % (i, len(boxes)))
        for b in boxes[:6]:
            print('      lo=%-30s hi=%-30s %s' % (b['lo'], b['hi'], b['mat']))
print('-' * 88)
for k, boxes in report['floor_tiles'].items():
    print('TILE %s  n=%d' % (k, 0 if boxes is None else len(boxes)))
print('-' * 88)
for d, boxes in report['door_gates'].items():
    print('GATE %s  n=%s  audit=%s' % (d, 'None' if boxes is None else len(boxes),
                                      report['door_gate_audit'][d]))
    if boxes:
        for b in boxes:
            print('      lo=%-30s hi=%-30s %s' % (b['lo'], b['hi'], b['mat']))
print('-' * 88)
print('DUPLICATE COLLECTIONS (stale leftovers):')
for k, v in report['duplicate_collections'].items():
    print('  %-40s %s' % (k, v))
print('-' * 88)
print('TILE SET UNIFORMITY (compare like-variant tiles):')
for k in ('11', '13', '22', '31', '33', '12', '21', '23', '32'):
    boxes = report['floor_tiles'].get(k)
    mats = {}
    for b in (boxes or []):
        mats[b['mat']] = mats.get(b['mat'], 0) + 1
    print('  tile %s n=%-3d mats=%s' % (k, 0 if boxes is None else len(boxes), mats))
print('=' * 88)
print('wrote', out.name)
