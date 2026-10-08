"""Reference-guided gun placement, updating only three carry arm poses.

Preserve v025 on disk and every old action; source-only, no runtime writes.
"""
from pathlib import Path
import sys, math, json, hashlib, os
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import author_bunny_weapon_idles_v025 as base

SOURCE = base.TARGET
base.TARGET = base.BASE / 'source/animation/chr_bunny01_animation_v026.blend'
base.OUT = base.ROOT / 'outputs/character_pipeline/weapon_idle_v026'
base.TRANSFER = base.BASE / 'source/animation/chr_bunny01_weapon_idles_v026.json'
base.SPECS['sidearm'].update(palm=(.48, .53, .43), yaw=-12, pitch=55)
base.SPECS['longgun'].update(palm=(.17, .30, .32))
base.SPECS['machinegun'].update(palm=(.18, .47, .245))
max_reach = {'l': 0., 'r': 0.}


def solve(rig, rest, posed, side, palm):
    # This character has floating glove geometry. Preserve bone lengths/rest;
    # use a recorded pose-only shoulder protraction for forward carry reach.
    n = 'upper_arm_' + side
    shoulder = posed['chest'] @ rest['chest'].inverted() @ rest[n].translation
    reach = sum(rig.data.bones[k + '_' + side].length for k in ('upper_arm', 'forearm', 'hand')) - .012
    delta = palm - shoulder
    shift = delta.normalized() * max(0., delta.length - reach)
    max_reach[side] = max(max_reach[side], shift.length)
    # The shared solver derives shoulder from rest. Supply a transient input
    # shoulder location; this does not modify the Blender rest skeleton.
    adjusted = dict(rest)
    adjusted[n] = rest[n].copy()
    adjusted[n].translation += (posed['chest'] @ rest['chest'].inverted()).to_3x3().inverted() @ shift
    base.solve_arm(rig, adjusted, posed, side, palm)


def build():
    assert not base.TARGET.exists() or '--replace-generated' in sys.argv
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    original = {a.name: base.curves_digest(a) for a in bpy.data.actions if a.library is None}
    for a in bpy.data.actions:
        if a.library is None:
            a.use_fake_user = True
    for family, spec in base.SPECS.items():
        scene = bpy.data.scenes[spec['title']]
        bpy.context.window.scene = scene
        if bpy.context.object and bpy.context.object.mode != 'OBJECT':
            bpy.ops.object.mode_set(mode='OBJECT')
        rig = next(o for o in scene.objects if o.type == 'ARMATURE')
        gun = next(o for o in scene.objects if o.name.startswith('PREVIEW_GripSocket'))
        rest = {b.name: b.matrix_local.copy() for b in rig.data.bones}
        samples = []
        for i in range(spec['period'] + 1):
            scene.frame_set(i + 1)
            er = rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
            samples.append({p.name: p.matrix.copy() for p in er.pose.bones})
        action = bpy.data.actions.new('anim_bunny01_' + family + '_idle_v026')
        for k in rig.animation_data.action.keys():
            action[k] = rig.animation_data.action[k]
        rig.animation_data.action = action
        gun.animation_data.action = bpy.data.actions.new('PREVIEW_ONLY_' + family + '_idle_v026')
        gun.animation_data.action['preview_only'] = True
        previous = {}
        for i, posed in enumerate(samples):
            phase = math.tau * i / spec['period']
            palm = Vector(spec['palm']) + Vector((.0015 * math.sin(phase), 0, spec['breath'] * math.sin(phase)))
            rotation = base.gun_rotation(spec, phase)
            solve(rig, rest, posed, 'r', palm)
            if family != 'sidearm':
                solve(rig, rest, posed, 'l', palm + rotation.to_3x3() @ Vector(gun['support_local']))
            base.key_pose(rig, rest, posed, i + 1, previous)
            gun.location = palm
            gun.rotation_quaternion = rotation.to_quaternion()
            for prop in ('location', 'rotation_quaternion'):
                gun.keyframe_insert(prop, frame=i + 1)
        base.cyclic(action, spec['period'])
        base.cyclic(gun.animation_data.action, spec['period'])
        scene['source_revision'] = 'v026_reference_forward_clearance'
        scene.frame_set(1)
    assert all(base.curves_digest(bpy.data.actions[n]) == digest for n, digest in original.items())
    base.OUT.mkdir(parents=True, exist_ok=True)
    bpy.context.window.scene = bpy.data.scenes[base.SPECS['sidearm']['title']]
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(base.TARGET), relative_remap=True)
    (base.OUT / 'original_actions.json').write_text(json.dumps(original, indent=2), encoding='utf-8')
    (base.OUT / 'reach.json').write_text(json.dumps(max_reach, indent=2), encoding='utf-8')


def geometry(obj, dg):
    eo = obj.evaluated_get(dg)
    mesh = eo.to_mesh()
    verts = [eo.matrix_world @ v.co for v in mesh.vertices]
    polygons = [list(p.vertices) for p in mesh.polygons]
    tree = BVHTree.FromPolygons(verts, polygons)
    eo.to_mesh_clear()
    return tree, verts


def clearance():
    report = {}
    for family, spec in base.SPECS.items():
        scene = bpy.data.scenes[spec['title']]
        bpy.context.window.scene = scene
        samples = []
        for i in range(16):
            f = 1 + i * spec['period'] / 16
            scene.frame_set(int(f), subframe=f % 1)
            dg = bpy.context.evaluated_depsgraph_get()
            bodies = [o for o in scene.objects if o.type == 'MESH' and not o.hide_render and (o.name.startswith('SRC_Body') or o.name.startswith('SRC_Head'))]
            weapons = [o for o in scene.objects if o.type == 'MESH' and o.get('preview_only') and not o.hide_render]
            count, distance = 0, 10.
            for b in bodies:
                tb, vb = geometry(b, dg)
                for g in weapons:
                    tg, vg = geometry(g, dg)
                    count += len(tb.overlap(tg))
                    distance = min(distance, min(tb.find_nearest(v)[3] for v in vg), min(tg.find_nearest(v)[3] for v in vb))
            samples.append(dict(frame=f, intersecting_face_pairs=count, vertex_surface_gap=distance))
        report[family] = samples
    (base.OUT / 'clearance.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('GUN_BODY_CLEARANCE', json.dumps({k: {'max_intersections': max(s['intersecting_face_pairs'] for s in v), 'min_gap': min(s['vertex_surface_gap'] for s in v)} for k, v in report.items()}), flush=True)
    assert all(s['intersecting_face_pairs'] == 0 for v in report.values() for s in v), 'Gun intersects body/head'


if '--verify-only' not in sys.argv:
    build()
base.verify_and_render()
clearance()
transfer = json.loads(base.TRANSFER.read_text(encoding='utf-8'))
transfer.update(version='v026', reference='User front and side screenshots, 2026-10-07; no access to that live player session',
                source_parent=str(SOURCE.relative_to(base.ROOT)), source_parent_sha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                reach=json.loads((base.OUT / 'reach.json').read_text()), clearance=json.loads((base.OUT / 'clearance.json').read_text()),
                note='Only three carry arms/gun previews adjusted. Body/head/ears/feet curves and all original actions preserved; pose-only shoulder protraction for floating hands, no rest/scale changes.')
base.TRANSFER.write_text(json.dumps(transfer, ensure_ascii=False, indent=2), encoding='utf-8')
print('V026_COMPLETE', base.TARGET, flush=True)
