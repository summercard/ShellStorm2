"""Author three standing carry loops, preserving v024 and all existing actions.

Run with Blender --background --factory-startup --python this_file.
Preview weapons/cameras are explicitly excluded from character export.
"""
from pathlib import Path
import ast
import hashlib
import json
import math
import os
import re
import sys

import bpy
from mathutils import Euler, Matrix, Vector

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from export_character_bundle import signature

BASE = ROOT / 'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01'
SOURCE = BASE / 'production/v024/source/animation/chr_bunny01_animation_v024.blend'
TARGET = BASE / 'source/animation/chr_bunny01_animation_v025.blend'
OUT = ROOT / 'outputs/character_pipeline/weapon_idle_v025'
TRANSFER = BASE / 'source/animation/chr_bunny01_weapon_idles_v025.json'
SCALE = 1.5 / 2.475
SPECS = {
    'sidearm': dict(title='14_短枪_站立待机_枪口朝上', period=192,
                    weapon='hair_dryer/wpn_hair_dryer_root_top3d_v001.tscn',
                    palm=(.38, .085, .50), yaw=-25, pitch=76, breath=.005),
    'longgun': dict(title='15_长枪_站立待机_胸前斜持', period=216,
                    weapon='broom_rifle/wpn_broom_rifle_root_top3d_v001.tscn',
                    palm=(.17, .125, .32), yaw=75, pitch=12, breath=.004),
    'machinegun': dict(title='16_机枪_站立待机_低位承重', period=240,
                    weapon='water_tank_blaster/wpn_water_tank_blaster_root_top3d.tscn',
                    palm=(.18, .095, .21), yaw=85, pitch=-10, breath=.0028),
}

tree = ast.parse((ROOT / 'scripts/blender/complete_character_basics_v019.py').read_text(encoding='utf-8'))
nodes = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in ('tr', 'pivot', 'along', 'curves_digest')]
exec(compile(ast.Module(body=nodes, type_ignores=[]), '<pure-pose-helpers>', 'exec'))


def gun_rotation(spec, phase):
    # Upward short-gun carry and two distinct low-amplitude weight responses.
    yaw = math.radians(spec['yaw']) + .006 * math.sin(phase)
    pitch = math.radians(spec['pitch']) + (.008 if spec['pitch'] > 0 else .004) * math.sin(phase - .3)
    return Matrix.Rotation(yaw, 4, 'Z') @ Matrix.Rotation(pitch, 4, 'X')


def solve_arm(rig, rest, posed, side, palm):
    upper, lower, hand = ['%s_%s' % (n, side) for n in ('upper_arm', 'forearm', 'hand')]
    shoulder = posed['chest'] @ rest['chest'].inverted() @ rest[upper].translation
    direction = (palm - shoulder).normalized()
    l1, l2, l3 = [rig.data.bones[n].length for n in (upper, lower, hand)]
    wrist = palm - direction * l3
    d = (wrist - shoulder).length
    assert abs(l1 - l2) + .0001 < d < l1 + l2 - .0001, (side, d, l1 + l2, tuple(palm))
    axis = (wrist - shoulder).normalized()
    a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
    h = math.sqrt(max(0, l1 * l1 - a * a))
    bend = Vector((-.18 if side == 'l' else .18, 0, -1))
    bend = (bend - axis * bend.dot(axis)).normalized()
    elbow = shoulder + axis * a + bend * h
    posed[upper] = along(rest[upper], shoulder, elbow - shoulder)
    posed[lower] = along(rest[lower], elbow, wrist - elbow)
    posed[hand] = along(rest[hand], wrist, palm - wrist)
    delta = posed[hand] @ rest[hand].inverted()
    for prefix in ('thumb', 'index', 'fingers'):
        for segment in ('01', '02'):
            name = '%s_%s_%s' % (prefix, segment, side)
            posed[name] = delta @ rest[name]


def key_pose(rig, rest, posed, frame, previous):
    for bone in rig.data.bones:
        p = rig.pose.bones[bone.name]
        parent = bone.parent.name if bone.parent else None
        p.rotation_mode = 'QUATERNION'
        p.matrix_basis = bone.convert_local_to_pose(
            posed[bone.name], rest[bone.name],
            parent_matrix=posed[parent] if parent else Matrix.Identity(4),
            parent_matrix_local=rest[parent] if parent else Matrix.Identity(4), invert=True)
        p.scale = (1, 1, 1)
        if bone.name in previous and previous[bone.name].dot(p.rotation_quaternion) < 0:
            p.rotation_quaternion.negate()
        previous[bone.name] = p.rotation_quaternion.copy()
        for prop in ('location', 'rotation_quaternion', 'scale'):
            p.keyframe_insert(prop, frame=frame, group=bone.name)


def cyclic(action, period):
    action.use_fake_user = True
    action.use_frame_range = True
    action.frame_start, action.frame_end = 1, period + 1
    action.use_cyclic = True
    for curve in action.fcurves:
        curve.extrapolation = 'CONSTANT'
        curve.modifiers.new('CYCLES')
        for key in curve.keyframe_points:
            key.interpolation = 'BEZIER'
            key.handle_left_type = key.handle_right_type = 'AUTO_CLAMPED'


def import_weapon(scene, family, spec):
    path = ROOT / 'assets/art/weapons/weapon_3d/runtime' / spec['weapon']
    content = path.read_text(encoding='utf-8')
    glb = ROOT / re.search(r'path="res://([^"\n]+\.glb)"', content)[1]
    def socket(name):
        m = re.search(r'\[node name="' + name + r'"[^\n]*\]\nposition = Vector3\(([^)]+)\)', content)
        if not m:
            return Vector((0, 0, 0))
        x, y, z = map(float, m[1].split(','))
        return Vector((x, -z, y))
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(glb))
    imported = set(bpy.data.objects) - before
    coll = bpy.data.collections.new('90_预览环境_不导出_' + family)
    scene.collection.children.link(coll)
    coll['preview_only'], coll['export'] = True, False
    gun = bpy.data.objects.new('PREVIEW_GripSocket_' + family, None)
    coll.objects.link(gun)
    gun['preview_only'], gun['export'] = True, False
    gun['source_scene'] = str(path.relative_to(ROOT)).replace('\\', '/')
    gun['support_local'] = list(socket('SupportHandSocket') * SCALE)
    gun['grip_contract'] = 'Origin equals hand_r tail (palm); orientation baked preview-only. Runtime orientation handoff pending.'
    gun.scale = (SCALE,) * 3
    offset = socket('VisualRoot')
    for obj in imported:
        for c in list(obj.users_collection):
            c.objects.unlink(obj)
        coll.objects.link(obj)
        obj['preview_only'], obj['export'] = True, False
        if obj.parent not in imported:
            matrix = obj.matrix_world.copy()
            obj.parent = gun
            obj.matrix_parent_inverse = Matrix.Identity(4)
            obj.matrix_basis = Matrix.Translation(offset) @ matrix
        obj.hide_set(False)
        obj.hide_render = False
        if obj.type == 'MESH':
            for material in obj.data.materials:
                if material and material.use_nodes:
                    bsdf = next((n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
                    if bsdf:
                        material.diffuse_color = bsdf.inputs['Base Color'].default_value
    return gun


def setup_camera(scene):
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'MATERIAL'
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.display.shading.background_type = 'WORLD'
    scene.world = bpy.data.worlds.new('PreviewWorld_' + scene['preview_clip'])
    scene.world.color = (.075, .085, .10)
    scene.render.resolution_x = scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    data = bpy.data.cameras.new('PREVIEW_Camera_' + scene['preview_clip'])
    cam = bpy.data.objects.new(data.name, data)
    scene.collection.objects.link(cam)
    cam['preview_only'], cam['export'] = True, False
    data.type, data.ortho_scale = 'ORTHO', 1.95
    scene.camera = cam
    return cam


def point_camera(cam, pos):
    cam.location = pos
    cam.rotation_euler = (Vector((0, .06, .72)) - cam.location).to_track_quat('-Z', 'Y').to_euler()


def build():
    assert not TARGET.exists() or '--replace-generated' in sys.argv, 'Refuse overwrite without explicit generated-file flag'
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    # Resolve library before saving at a different depth.
    for lib in bpy.data.libraries:
        lib.filepath = str(Path(bpy.path.abspath(lib.filepath)).resolve())
    template = next(s for s in bpy.data.scenes if s.get('preview_clip') == 'idle')
    source_rig = next(o for o in template.objects if o.type == 'ARMATURE')
    original = {a.name: curves_digest(a) for a in bpy.data.actions if a.library is None}
    for a in bpy.data.actions:
        if a.library is None:
            a.use_fake_user = True
    for family, spec in SPECS.items():
        state = family + '_idle'
        scene = bpy.data.scenes.new(spec['title'])
        scene['preview_clip'] = state
        scene['asset_id'] = 'CHR-PLY-CAPSULE01-3D-BUNNY01'
        scene['production_status'] = 'authored_pending_export'
        scene['weapon_family'] = family
        scene['preview_help'] = 'Standing carry loop; preview guns do not export. Feet and gameplay root fixed.'
        scene.render.fps = 60
        scene.frame_start, scene.frame_end = 1, spec['period']
        scene.use_preview_range = True
        scene.frame_preview_start, scene.frame_preview_end = 1, spec['period']
        coll = bpy.data.collections.new('01_角色_' + state)
        scene.collection.children.link(coll)
        mapping = {}
        for obj in template.objects:
            if obj.get('preview_only'):
                continue
            copy = obj.copy()
            coll.objects.link(copy)
            mapping[obj] = copy
        rig = mapping[source_rig]
        rig.name = 'RIG_bunny01_' + state
        for obj, copy in mapping.items():
            if obj.parent in mapping:
                copy.parent = mapping[obj.parent]
            for mod in copy.modifiers:
                if mod.type == 'ARMATURE':
                    mod.object = rig
            for con in copy.constraints:
                if getattr(con, 'target', None) == source_rig:
                    con.target = rig
            if copy.get('variant_id') == 'chibi_anime':
                copy.hide_render = copy.hide_viewport = True
        bpy.context.window.scene = scene
        gun = import_weapon(scene, family, spec)
        rest = {b.name: b.matrix_local.copy() for b in rig.data.bones}
        action = bpy.data.actions.new('anim_bunny01_' + state + '_v025')
        rig.animation_data_create()
        rig.animation_data.action = action
        action['state_id'], action['gameplay_state'] = state, 'idle'
        action['weapon_family'], action['loop'] = family, True
        action['duration'] = spec['period'] / 60
        action['pose_role'] = 'standing_carry_not_aim'
        previous = {}
        for i in range(spec['period'] + 1):
            phase = math.tau * i / spec['period']
            posed = {n: m.copy() for n, m in rest.items()}
            # Distinct authored breathing, with planted feet and an immobile root.
            breath = spec['breath'] * math.sin(phase)
            lean = -.035 if family == 'machinegun' else -.012 if family == 'longgun' else .006
            torso = tr((0, 0, breath)) @ pivot(rest['waist'].translation, (lean + .008 * math.sin(phase), .004 * math.sin(phase), 0))
            for n in ('waist', 'chest'):
                posed[n] = torso @ rest[n]
            head_delta = tr((0, 0, breath * .6)) @ pivot(rest['head'].translation, (.004 * math.sin(phase - .4), 0, .008 * math.sin(phase - .25)))
            posed['head'] = head_delta @ rest['head']
            for side in ('l', 'r'):
                n = 'ear_' + side
                posed[n] = head_delta @ pivot(rest[n].translation, (.015 * math.sin(phase - .7), 0, 0)) @ rest[n]
            palm = Vector(spec['palm']) + Vector((.0015 * math.sin(phase), 0, breath))
            rotation = gun_rotation(spec, phase)
            solve_arm(rig, rest, posed, 'r', palm)
            if family == 'sidearm':
                left = Vector((-.29, .09, .235)) + Vector((0, .002 * math.sin(phase - .3), breath * .3))
            else:
                left = palm + rotation.to_3x3() @ Vector(gun['support_local'])
            solve_arm(rig, rest, posed, 'l', left)
            key_pose(rig, rest, posed, i + 1, previous)
            gun.location = palm
            gun.rotation_mode = 'QUATERNION'
            gun.rotation_quaternion = rotation.to_quaternion()
            for prop in ('location', 'rotation_quaternion'):
                gun.keyframe_insert(prop, frame=i + 1)
        cyclic(action, spec['period'])
        cyclic(gun.animation_data.action, spec['period'])
        gun.animation_data.action.name = 'PREVIEW_ONLY_' + state + '_v025'
        gun.animation_data.action['preview_only'] = True
        cam = setup_camera(scene)
        point_camera(cam, (2.6, 4, 1.8))
        scene.frame_set(1)
        bpy.context.view_layer.objects.active = rig
        for obj in scene.objects:
            obj.select_set(obj == rig)
        # Restore author-friendly framing in all inherited workspace viewports.
        for screen in bpy.data.screens:
            for area in screen.areas:
                if area.type == 'VIEW_3D':
                    area.spaces.active.region_3d.view_distance = 2.2
                    area.spaces.active.region_3d.view_location = (0, .05, .72)
                    area.spaces.active.region_3d.view_rotation = cam.rotation_euler.to_quaternion()
    assert all(curves_digest(bpy.data.actions[n]) == digest for n, digest in original.items())
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    for lib in bpy.data.libraries:
        lib.filepath = '//' + os.path.relpath(lib.filepath, TARGET.parent).replace('\\', '/')
    bpy.context.window.scene = bpy.data.scenes[SPECS['sidearm']['title']]
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(TARGET), relative_remap=False)
    (OUT / 'original_actions.json').write_text(json.dumps(original, indent=2), encoding='utf-8')


def verify_and_render():
    bpy.ops.wm.open_mainfile(filepath=str(TARGET))
    original = json.loads((OUT / 'original_actions.json').read_text(encoding='utf-8'))
    assert all(curves_digest(bpy.data.actions[n]) == digest for n, digest in original.items())
    report = {'status': 'authored_pending_export', 'original_actions_preserved': len(original), 'clips': {}}
    for family, spec in SPECS.items():
        scene = bpy.data.scenes[spec['title']]
        bpy.context.window.scene = scene
        rig = next(o for o in scene.objects if o.type == 'ARMATURE')
        gun = next(o for o in scene.objects if o.name.startswith('PREVIEW_GripSocket'))
        assert signature(rig) == '203cbcaf9a7d4eaa55baacc6ea4d2093e157ad853ecab5bf08abb8a38f41edb8'
        errors = dict(scale=0., arm_gap=0., right_grip=0., left_support=0., planted_feet=0., root_motion=0., loop=0.)
        first = None
        ground = {'character': 10., 'weapon': 10.}
        for i in range(spec['period'] * 4 + 1):
            f = 1 + i / 4
            scene.frame_set(int(f), subframe=f - int(f))
            dg = bpy.context.evaluated_depsgraph_get()
            er, eg = rig.evaluated_get(dg), gun.evaluated_get(dg)
            mats = {p.name: p.matrix.copy() for p in er.pose.bones}
            if first is None:
                first = mats
            errors['scale'] = max(errors['scale'], *(abs(v - 1) for m in mats.values() for v in m.to_scale()))
            for n, metric in [('root', 'root_motion'), ('foot_l', 'planted_feet'), ('foot_r', 'planted_feet')]:
                errors[metric] = max(errors[metric], max(abs(mats[n][a][b] - first[n][a][b]) for a in range(4) for b in range(4)))
            for side in ('l', 'r'):
                for a, b in [('upper_arm_', 'forearm_'), ('forearm_', 'hand_')]:
                    errors['arm_gap'] = max(errors['arm_gap'], (mats[a + side] @ Vector((0, rig.data.bones[a + side].length, 0)) - mats[b + side].translation).length)
                palm = er.matrix_world @ mats['hand_' + side] @ Vector((0, rig.data.bones['hand_' + side].length, 0))
                if side == 'r':
                    errors['right_grip'] = max(errors['right_grip'], (palm - eg.matrix_world.translation).length)
                elif family != 'sidearm':
                    support = eg.matrix_world.translation + eg.matrix_world.to_quaternion() @ Vector(gun['support_local'])
                    errors['left_support'] = max(errors['left_support'], (palm - support).length)
            if i % 16 == 0:
                for obj in scene.objects:
                    if obj.type != 'MESH' or obj.hide_render:
                        continue
                    eo = obj.evaluated_get(dg)
                    mesh = eo.to_mesh()
                    category = 'weapon' if obj.get('preview_only') else 'character'
                    ground[category] = min(ground[category], min((eo.matrix_world @ v.co).z for v in mesh.vertices))
                    eo.to_mesh_clear()
        errors['loop'] = max(abs(mats[n][a][b] - first[n][a][b]) for n in mats for a in range(4) for b in range(4))
        assert max(errors.values()) < .0001, (family, errors)
        assert min(ground.values()) > -.002, (family, 'ground', ground)
        scene.frame_set(1 + spec['period'] * 2)
        again = rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
        repeat_error = max(abs(p.matrix[a][b] - first[p.name][a][b]) for p in again.pose.bones for a in range(4) for b in range(4))
        assert repeat_error < .0001, (family, repeat_error)
        scene.frame_set(1)
        forward = gun.matrix_world.to_quaternion() @ Vector((0, 1, 0))
        if family == 'sidearm':
            assert forward.z > math.sin(math.radians(spec['pitch'] - 3))
        elif family == 'machinegun':
            assert forward.z < -.15
        report['clips'][family + '_idle'] = dict(duration=spec['period'] / 60, frames=[1, spec['period'] + 1], errors=errors, ground_min_z=ground, two_cycle_error=repeat_error, muzzle_direction=list(forward), skeleton_sha256=signature(rig))
        for view, pos in [('front', (0, 4, .85)), ('side', (4, 0, .85)), ('threequarter', (2.6, 4, 1.8))]:
            point_camera(scene.camera, pos)
            scene.render.filepath = str(OUT / (family + '_' + view + '.png'))
            bpy.ops.render.render(write_still=True)
        if '--animate-preview' in sys.argv:
            folder = OUT / family
            folder.mkdir(exist_ok=True)
            for i in range(32):
                frame = 1 + i * spec['period'] / 32
                scene.frame_set(int(frame), subframe=frame - int(frame))
                scene.render.filepath = str(folder / ('%03d.png' % i))
                bpy.ops.render.render(write_still=True)
    (OUT / 'validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    transfer = dict(asset_id='CHR-PLY-CAPSULE01-3D-BUNNY01', version='v025', status='authored_pending_export', runtime_changed=False,
                    model_source='production/v021/source/model/chr_bunny01_model_v021.blend',
                    skeleton_id='SKEL-BUNNY01-004', validation=report,
                    source=str(TARGET.relative_to(ROOT)).replace('\\', '/'), sha256=hashlib.sha256(TARGET.read_bytes()).hexdigest(),
                    integration_warning='Runtime v021 wrapper currently uses v024 motion library. New idles require weapon-family selection and gun orientation binding, not just hand-tip translation. Preview guns and their actions must not export.',
                    preserved_source_scene_note='v024 moving preview scene already plays climbing; unchanged. Original moving action retained.')
    TRANSFER.write_text(json.dumps(transfer, ensure_ascii=False, indent=2), encoding='utf-8')
    print('WEAPON_IDLE_V025_VERIFIED', json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    if '--verify-only' not in sys.argv:
        build()
    verify_and_render()
