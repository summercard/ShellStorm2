"""Refine saved directional Actions; never regenerate the original gait.

Blender --background --python scripts/blender/refine_bunny_locomotion_v038.py
Upper-body yaw is authored around the torso, not a lateral translation.
"""
from pathlib import Path
import sys, math, json, ast
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'scripts'))
sys.path.insert(0, str(Path(__file__).parent))
from workspace_paths import work_path
from art_source_paths import source_path
import author_bunny_directional_v027 as d
h = d.h
tree = ast.parse((Path(__file__).parent/'author_bunny_firing_v030.py').read_text(encoding='utf-8'))
exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'solve'], type_ignores=[]), '<arm-solver>', 'exec'))
SOURCE = source_path(h.BASE/'source/animation/chr_bunny01_animation_v037.blend')
TARGET = SOURCE.with_name('chr_bunny01_animation_v038.blend')
OUT = work_path('sessions/2026-10-14_player_jog_v038/source_report.json').parent

def target(state):
    return state.startswith(('unarmed_', 'sidearm_', 'longgun_', 'machinegun_')) and ('_walking_' in state or '_moving_' in state)

def curves(action):
    if hasattr(action, 'fcurves'):
        return action.fcurves
    return [c for layer in action.layers for strip in layer.strips for bag in strip.channelbags for c in bag.fcurves]

def set_action(obj, action):
    obj.animation_data.action = action
    if action.slots:
        obj.animation_data.action_slot = action.slots[0]

def build():
    assert not TARGET.exists() or '--replace-generated' in sys.argv
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    specs = {}
    for scene in list(bpy.data.scenes):
        state = scene.get('preview_clip', '')
        if not target(state):
            continue
        bpy.context.window.scene = scene
        rig = next(o for o in scene.objects if o.type == 'ARMATURE')
        gun = next((o for o in scene.objects if o.name.startswith('PREVIEW_GripSocket')), None)
        rest = {b.name:b.matrix_local.copy() for b in rig.data.bones}
        prior = rig.animation_data.action
        first, last = map(int, prior.frame_range)
        samples = []
        for f in range(first, last+1):
            scene.frame_set(f)
            dg = bpy.context.evaluated_depsgraph_get()
            samples.append(({p.name:p.matrix.copy() for p in rig.evaluated_get(dg).pose.bones}, gun.evaluated_get(dg).matrix_world.copy() if gun else None))
        action = bpy.data.actions.new('anim_bunny01_'+state+'_v038')
        for k in prior.keys(): action[k] = prior[k]
        action['source_revision'] = 'v038_natural_jog'
        set_action(rig, action)
        if gun:
            set_action(gun, bpy.data.actions.new('PREVIEW_ONLY_'+state+'_v038'))
            gun.animation_data.action['preview_only'] = True
        moving = '_moving_' in state
        firing = '_fire_' in state
        family = state.split('_')[0]
        direction = 'forward' if state.endswith('_forward') else 'backward' if state.endswith('_backward') else 'strafe_right' if state.endswith('_strafe_right') else 'strafe_left'
        weight = .78 if family == 'machinegun' else 1.0
        amplitude = math.radians(7 if moving else 4)*weight
        if firing: amplitude *= .65
        bob = (.020 if moving else .009)*weight
        forward = (.026 if moving else .014) if direction == 'forward' else 0.0
        previous = {}
        for i, (original, gm) in enumerate(samples):
            phase = math.tau*i/(last-first)
            # Side-leading phase agrees with the existing independently authored feet.
            swing = math.sin(phase) * (-1 if direction == 'strafe_right' else 1)
            bounce = (1-math.cos(2*phase))*.5
            pivot = Vector((0, 0, original['chest'].translation.z))
            shift = Vector((0, 0, bob*bounce))
            upper = Matrix.Translation(shift) @ Matrix.Translation(pivot) @ Matrix.Rotation(amplitude*swing, 4, 'Z') @ Matrix.Translation(-pivot)
            posed = {n:(m.copy() if n == 'root' or n.startswith(('foot_', 'thigh_', 'shin_')) else upper@m) for n,m in original.items()}
            # Head stays visually attentive; only small vertical follow-through and nod.
            hp = original['head'].translation
            head_shift = shift+Vector((0, forward, (.007 if moving else .003)*bounce))
            pitch = -math.radians((1.5 if moving else .8) if direction == 'forward' else 0) + math.radians(.7 if moving else .35)*math.sin(2*phase-.3)
            head = Matrix.Translation(head_shift) @ Matrix.Translation(hp) @ Matrix.Rotation(pitch, 4, 'X') @ Matrix.Translation(-hp)
            for n in ('head', 'ear_l', 'ear_r'):
                posed[n] = head@original[n]
            if gun:
                new_gm = upper@gm
                if firing:
                    # Preserve the authored firing aim direction; solve both hands offline.
                    new_gm = gm.copy()
                    new_gm.translation = (upper@gm).translation
                    solve(rig, rest, posed, 'r', new_gm.translation)
                    if family != 'sidearm':
                        solve(rig, rest, posed, 'l', new_gm.translation+new_gm.to_quaternion()@Vector(gun['support_local']))
                gun.location = new_gm.translation
                gun.rotation_mode = 'QUATERNION'
                gun.rotation_quaternion = new_gm.to_quaternion()
                for prop in ('location', 'rotation_quaternion'): gun.keyframe_insert(prop, frame=i+first)
            h.key_pose(rig, rest, posed, i+first, previous)
        for a in [action]+([gun.animation_data.action] if gun else []):
            a.use_fake_user = True
            a.use_frame_range = True
            a.frame_start, a.frame_end = first, last
            a.use_cyclic = True
            for c in curves(a):
                c.extrapolation = 'CONSTANT'
                for key in c.keyframe_points: key.interpolation = 'LINEAR'
        specs[state] = dict(body_yaw_amplitude_deg=math.degrees(amplitude), added_body_bob_m=bob, head_forward_m=forward, firing_aim_stabilized=firing, duration=float(action['duration']))
        scene['source_revision'] = 'v038_natural_jog'
        scene.frame_set(first)
        print('REFINED', state, flush=True)
    assert len(specs) == 56, len(specs)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(TARGET), relative_remap=True)
    (OUT/'source_report.json').write_text(json.dumps(specs, indent=2))

if __name__ == '__main__':
    build()
