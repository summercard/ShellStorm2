import bpy, math, json, hashlib, os
from pathlib import Path
from mathutils import Matrix, Vector, Quaternion

P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
SRC_MODEL = P / 'assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v005.blend'
MODEL_OUT = P / 'assets/art/enemies/normal_enemy_3d/security_zombie/source/model/enm_security_zombie_model_v001.blend'
ANIM_OUT = P / 'assets/art/enemies/normal_enemy_3d/security_zombie/source/animation/enm_security_zombie_animation_v001.blend'
GUN_SRC = P / 'assets/art/weapons/weapon_3d/source/security_short_shotgun/wpn_security_short_shotgun_source_v002.blend'
REPORT = P / '_scratch/security_zombie/security_zombie_action_report.json'
PREV_DIR = P / 'assets/art/enemies/normal_enemy_3d/security_zombie/previews'
PREV_DIR.mkdir(parents=True, exist_ok=True)
MODEL_OUT.parent.mkdir(parents=True, exist_ok=True)
ANIM_OUT.parent.mkdir(parents=True, exist_ok=True)

# Independent model source: copy the already verified police-zombie bind without changing weights.
bpy.ops.wm.open_mainfile(filepath=str(SRC_MODEL))
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
mesh = next(o for o in bpy.data.objects if o.type == 'MESH')
arm.name = 'enm_security_zombie_armature'
arm.data.name = 'enm_security_zombie_armature'
mesh.name = 'enm_security_zombie_mesh'
mesh.data.name = 'enm_security_zombie_mesh'
arm.data['asset_id'] = 'ENM-NORMAL-SECURITY-ZOMBIE-3D'
arm.data['logic_id'] = 'security_zombie'
arm.data['display_name_zh'] = '警察僵尸'
arm.data['source_role'] = 'independent armed enemy; no melee action reuse'
mesh['asset_id'] = 'ENM-NORMAL-SECURITY-ZOMBIE-3D'
mesh['logic_id'] = 'security_zombie'
# Rename materials only inside the independent copy.
for mat in mesh.data.materials:
    if mat:
        mat.name = mat.name.replace('ranged_sporeshooter01', 'security_zombie')
bpy.ops.wm.save_as_mainfile(filepath=str(MODEL_OUT))

# Re-open independent model for action authoring.
bpy.ops.wm.open_mainfile(filepath=str(MODEL_OUT))
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.render.fps = 30
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
mesh = next(o for o in bpy.data.objects if o.type == 'MESH')
arm.data.pose_position = 'POSE'
arm.animation_data_clear()
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
for pb in arm.pose.bones:
    pb.rotation_mode = 'QUATERNION'

# Store rest matrices and hierarchy. The action source is generated from rest pose only;
# no action is appended from the melee or ranged-caster files.
M = arm.matrix_world.copy()
BONES = [b.name for b in arm.data.bones]

def reset_pose():
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()
        pb.location = (0.0, 0.0, 0.0)
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()

def rest_head(name):
    return (M @ Vector(arm.data.bones[name].head_local)).copy()

def rest_axis_x(name):
    b = arm.data.bones[name]
    R = M @ b.matrix_local
    return (R @ Vector((1, 0, 0)) - R @ Vector((0, 0, 0))).normalized()

def build_world_bone(head, direction, rest_x):
    y = Vector(direction).normalized()
    x = Vector(rest_x) - y * Vector(rest_x).dot(y)
    if x.length < 1e-6:
        x = Vector((1, 0, 0)) - y * y.dot(Vector((1, 0, 0)))
    x.normalize()
    z = x.cross(y).normalized()
    x = y.cross(z).normalized()
    W = Matrix(((x.x, x.y, x.z, 0.0), (y.x, y.y, y.z, 0.0),
                (z.x, z.y, z.z, 0.0), (0.0, 0.0, 0.0, 1.0)))
    W.translation = Vector(head)
    return W

def solve_chain(side, target, pole):
    names = [side + '_Upperarm', side + '_Forearm', side + '_Hand']
    shoulder = rest_head(names[0])
    upper = arm.data.bones[names[0]].length
    fore = arm.data.bones[names[1]].length
    hand = arm.data.bones[names[2]].length
    hand_tip = Vector(target)
    fore_tip = hand_tip - Vector((0.0, 1.0, 0.0)) * hand
    v = fore_tip - shoulder
    d = min(max(v.length, abs(upper - fore) + 1e-4), upper + fore - 1e-4)
    u = v.normalized()
    pole_v = Vector(pole) - u * Vector(pole).dot(u)
    pole_v.normalize()
    along = (upper * upper - fore * fore + d * d) / (2.0 * d)
    height = math.sqrt(max(0.0, upper * upper - along * along))
    elbow = shoulder + u * along + pole_v * height
    desired = {
        names[0]: (shoulder, elbow - shoulder),
        names[1]: (elbow, fore_tip - elbow),
        names[2]: (fore_tip, Vector((0.0, 1.0, 0.0))),
    }
    # Convert desired world matrices to Blender pose matrices and solve matrix_basis
    # through the actual rest parent chain. Directly assigning PoseBone.matrix here
    # loses the clavicle parent and causes the gun hand to drift toward the face.
    desired_arm = {}
    solved = {}
    for name in names:
        W = build_world_bone(desired[name][0], desired[name][1], rest_axis_x(name))
        desired_arm[name] = M.inverted() @ W
        pb = arm.pose.bones[name]
        parent = pb.parent
        if parent is None:
            basis = pb.bone.matrix_local.inverted() @ desired_arm[name]
        else:
            rest_rel = parent.bone.matrix_local.inverted() @ pb.bone.matrix_local
            basis = rest_rel.inverted() @ parent.matrix.inverted() @ desired_arm[name]
        pb.matrix_basis = basis
        bpy.context.view_layer.update()
        solved[name] = pb.matrix_basis.copy()
    return solved, hand_tip

# Character faces +Y; L_* is the gun hand used by the existing police-zombie naming.
# The v002 gun's grip is at its WeaponRoot origin. Keep the weapon low and
# centered in front of the torso so the mesh sits between both hands, not at the face.
# L_Hand is the authored main-hand side in this rig. First solve both hands
# to chest-level targets; the weapon transform is then derived from the actual
# two hand tips, not guessed from a front-view offset.
GUN_GRIP_TARGET = Vector((0.16, 0.33, 0.87))
GUN_SUPPORT_TARGET = Vector((0.16, 0.57, 0.91))
left_solution, _ = solve_chain('L', GUN_GRIP_TARGET, Vector((-0.40, -0.25, -0.45)))
right_solution, _ = solve_chain('R', GUN_SUPPORT_TARGET, Vector((0.40, -0.25, -0.45)))
bpy.context.view_layer.update()
GUN_GRIP = (M @ arm.pose.bones['L_Hand'].tail).copy()
GUN_SUPPORT = (M @ arm.pose.bones['R_Hand'].tail).copy()
# v002 support socket is (0, 0.04, -0.24) in WeaponRoot space. Align this
# exact vector to the two-hand vector while keeping local -Z pointing forward.
SOCKET_DELTA_LOCAL = Vector((0.0, 0.04, -0.24))
hand_delta = GUN_SUPPORT - GUN_GRIP
if hand_delta.length < 1e-5:
    raise RuntimeError('two hand targets collapsed')
base_rot = SOCKET_DELTA_LOCAL.normalized().rotation_difference(hand_delta.normalized())
GUN_ROT = base_rot.to_matrix().to_4x4()
GUN_ROT.translation = GUN_GRIP
ARMED_BASIS = {}
for n in ('L_Upperarm', 'L_Forearm', 'L_Hand', 'R_Upperarm', 'R_Forearm', 'R_Hand'):
    ARMED_BASIS[n] = (left_solution if n.startswith('L_') else right_solution)[n]

# Actual shotgun source objects are appended only for editable visual preview.
with bpy.data.libraries.load(str(GUN_SRC), link=False) as (src, dst):
    dst.objects = list(src.objects)
loaded = [o for o in dst.objects if o is not None]
for o in loaded:
    if o.name not in scene.objects:
        scene.collection.objects.link(o)
gun = next((o for o in loaded if o.name == 'WeaponRoot'), None)
if gun is None:
    raise RuntimeError('WeaponRoot missing from short shotgun source')
# Remove every source-side object animation in the character preview. The weapon
# keeps its own fire_pump_cycle in its standalone source, but that action must not
# move SupportHandSocket while the character clip is being evaluated.
for o in loaded:
    if o.animation_data:
        o.animation_data_clear()
for o in loaded:
    o['preview_only'] = True
    o['linked_asset_id'] = 'WPN-GUN-SECURITY-SHORT-SHOTGUN'
# Attach the gun to the authored main hand while preserving the solved world
# transform. Setting matrix_world after parenting is intentional; Blender keeps
# the exact grip transform, then the bone drives the weapon during playback.
gun.parent = arm
gun.parent_type = 'BONE'
gun.parent_bone = 'L_Hand'
gun.matrix_world = GUN_ROT
for o in loaded:
    if o.name != 'WeaponRoot' and o.type == 'EMPTY':
        o.hide_render = True
        o.hide_viewport = True

# Keying helpers.
def new_action(name, end, loop=False):
    a = bpy.data.actions.new(name)
    a.use_fake_user = True
    a.use_frame_range = True
    a.frame_start = 1
    a.frame_end = end
    a['loop'] = bool(loop)
    a['authored_independently'] = True
    return a

def key_all(action, frame):
    arm.animation_data_create()
    arm.animation_data.action = action
    for pb in arm.pose.bones:
        pb.keyframe_insert('location', frame=frame)
        pb.keyframe_insert('rotation_quaternion', frame=frame)
        pb.keyframe_insert('scale', frame=frame)

def set_local_rot(name, axis, degrees):
    pb = arm.pose.bones[name]
    pb.rotation_mode = 'QUATERNION'
    pb.rotation_quaternion = Quaternion(Vector(axis), math.radians(degrees))

def set_armed_pose():
    for name, basis in ARMED_BASIS.items():
        arm.pose.bones[name].matrix_basis = basis.copy()
    set_grip_fingers()
    bpy.context.view_layer.update()

def set_grip_fingers():
    # The imported police rig has articulated finger chains. In rest pose they
    # point forward with the palm, which reads as an open hand in front of the
    # gun. Curl each chain around its own local X axis so the main hand closes
    # around GripSocket and the support hand closes around SupportHandSocket.
    for side in ('L', 'R'):
        for finger in ('Index', 'Middle', 'Ring', 'Pinky'):
            for i, angle in enumerate((34.0, 52.0, 62.0, 68.0), 1):
                name = f'{side}_{finger}{i}'
                if arm.pose.bones.get(name):
                    set_local_rot(name, (1, 0, 0), -angle)
        for i, angle in enumerate((28.0, 42.0, 48.0, 52.0), 1):
            name = f'{side}_Thumb{i}'
            if arm.pose.bones.get(name):
                set_local_rot(name, (0, 0, 1), angle)

def set_walk_legs(phase, amount, hip_bob):
    # Procedural local FK walk cycle; action keys are baked, not runtime logic.
    s = math.sin(phase)
    c = math.sin(phase + math.pi)
    set_local_rot('L_Thigh', (1, 0, 0), amount * s)
    set_local_rot('R_Thigh', (1, 0, 0), amount * c)
    set_local_rot('L_Calf', (1, 0, 0), max(0.0, -amount * 0.42 * s))
    set_local_rot('R_Calf', (1, 0, 0), max(0.0, -amount * 0.42 * c))
    arm.pose.bones['Hip'].location.z = hip_bob * max(0.0, math.sin(phase))

def bake_clip(name, end, loop, mode):
    action = new_action(name, end, loop)
    arm.animation_data_create()
    arm.animation_data.action = action
    for f in range(1, end + 1):
        reset_pose()
        phase = (f - 1) / float(end - 1) * (2.0 * math.pi if loop else math.pi)
        if mode == 'idle':
            set_local_rot('Spine02', (0, 0, 1), 1.2 * math.sin(phase))
            set_local_rot('Head', (0, 0, 1), -1.5 * math.sin(phase + 0.4))
        elif mode == 'walking':
            set_walk_legs(phase, 18.0, 0.012)
            set_local_rot('Spine02', (0, 0, 1), 2.0 * math.sin(phase))
        elif mode == 'running':
            set_walk_legs(phase, 30.0, 0.02)
            set_local_rot('Spine02', (0, 0, 1), 4.0 * math.sin(phase))
        elif mode in ('hurt', 'armed_hurt'):
            if mode == 'armed_hurt':
                set_armed_pose()
                # Keep both hands on the gun: the whole upper body moves through
                # Hip, rather than twisting only one forearm away from the socket.
                jolt = math.sin(math.pi * (f - 1) / max(1, end - 1))
                arm.pose.bones['Hip'].location.y = -0.018 * jolt
            else:
                set_local_rot('Spine02', (1, 0, 0), -18.0 * math.sin(math.pi * (f - 1) / max(1, end - 1)))
                set_local_rot('Head', (1, 0, 0), 10.0 * math.sin(math.pi * (f - 1) / max(1, end - 1)))
        elif mode in ('dead', 'armed_dead'):
            if mode == 'armed_dead':
                set_armed_pose()
            t = (f - 1) / float(end - 1)
            set_local_rot('Hip', (1, 0, 0), -68.0 * min(1.0, t * 1.35))
            if mode != 'armed_dead':
                set_local_rot('Spine02', (1, 0, 0), -22.0 * min(1.0, max(0.0, (t - 0.18) * 1.5)))
        elif mode.startswith('armed_'):
            set_armed_pose()
            kind = mode[6:]
            if kind == 'idle':
                set_local_rot('Spine02', (0, 0, 1), 1.0 * math.sin(phase))
            elif kind == 'walking':
                set_walk_legs(phase, 12.0, 0.01)
            elif kind == 'running':
                set_walk_legs(phase, 22.0, 0.016)
        elif mode == 'shoot':
            set_armed_pose()
            recoil = math.sin((f - 7) / 6.0 * math.pi) if 7 <= f <= 13 else 0.0
            # Keep both hands locked to the two weapon sockets. Recoil is shown
            # by a small upper-body kick, never by independently rotating either
            # forearm away from its grip.
            set_local_rot('Spine02', (1, 0, 0), -4.0 * recoil)
        elif mode == 'shoot_armed':
            set_armed_pose()
            recoil = math.sin((f - 5) / 8.0 * math.pi) if 5 <= f <= 13 else 0.0
            set_local_rot('Spine02', (1, 0, 0), -5.0 * recoil)
        key_all(action, f)
    return action

# Ten clips: the six ordinary-enemy names stay stable. The attack slot is the
# shotgun fire presentation (not a melee attack), and the base locomotion clips
# themselves are armed because this enemy always carries the shotgun.
clips = [
    ('idle', 97, True, 'armed_idle'),
    ('walking', 49, True, 'armed_walking'),
    ('running', 25, True, 'armed_running'),
    ('attack', 25, False, 'shoot_armed'),
    ('hurt', 25, False, 'armed_hurt'),
    ('dead', 73, False, 'armed_dead'),
    ('armed_idle', 97, True, 'armed_idle'),
    ('walking_armed', 49, True, 'armed_walking'),
    ('running_armed', 25, True, 'armed_running'),
    ('shoot', 25, False, 'shoot_armed'),
]
made = {}
for name, end, loop, mode in clips:
    made[name] = bake_clip(name, end, loop, mode)

# Save with the gun preview included as an explicit editable reference.
arm.animation_data.action = made['armed_idle']
scene.frame_set(25)
scene.render.engine = 'BLENDER_WORKBENCH'
scene.display.shading.light = 'STUDIO'
scene.display.shading.color_type = 'TEXTURE'
scene.display.shading.show_shadows = True
scene.display.shading.show_cavity = True
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(ANIM_OUT))

# Render a front armed hold and recoil frame for visual verification.
def setup_cam(name, loc, target):
    cd = bpy.data.cameras.get(name) or bpy.data.cameras.new(name)
    cam = bpy.data.objects.get(name) or bpy.data.objects.new(name, cd)
    if cam.name not in scene.objects:
        scene.collection.objects.link(cam)
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = 2.25
    return cam
cam = setup_cam('security_zombie_preview_camera', (0.0, 2.8, 1.0), (0.0, 0.0, 0.95))
scene.camera = cam
scene.render.resolution_x = 600
scene.render.resolution_y = 700
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
for clip_name, frame, out_name in [('armed_idle', 25, 'security_zombie_armed_idle_front.png'), ('attack', 10, 'security_zombie_attack_front.png')]:
    arm.animation_data.action = made[clip_name]
    scene.frame_set(frame)
    scene.render.filepath = str(PREV_DIR / out_name)
    bpy.ops.render.render(write_still=True)

# Verification report.
def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

def action_info(a):
    return {'frames': [int(a.frame_range[0]), int(a.frame_range[1])],
            'seconds': round((a.frame_range[1] - a.frame_range[0]) / 30.0, 4),
            'loop': bool(a.get('loop', False)),
            'fcurves': len(a.fcurves)}

report = {
    'status': 'authored_pending_godot_validation',
    'model': str(MODEL_OUT),
    'animation': str(ANIM_OUT),
    'gun_source': str(GUN_SRC),
    'asset_id': 'ENM-NORMAL-SECURITY-ZOMBIE-3D',
    'logic_id': 'security_zombie',
    'skeleton_id': arm.data.get('skeleton_id'),
    'bone_count': len(arm.data.bones),
    'source_policy': 'independent procedural FK actions; no melee or ranged action datablock reused',
    'gun_mount': {'weapon_asset_id': 'WPN-GUN-SECURITY-SHORT-SHOTGUN', 'main_hand_bone': 'L_Hand', 'support_hand_bone': 'R_Hand', 'grip_world_m': list(GUN_GRIP), 'support_world_m': list(GUN_SUPPORT), 'weapon_forward': 'local -Z -> character +Y'},
    'clips': {name: action_info(a) for name, a in made.items()},
    'clip_count': len(made),
    'preview_files': [str(PREV_DIR / 'security_zombie_armed_idle_front.png'), str(PREV_DIR / 'security_zombie_attack_front.png')],
    'model_sha256': sha256(MODEL_OUT),
    'animation_sha256': sha256(ANIM_OUT),
}
REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print('SECURITY_ZOMBIE_INDEPENDENT_ACTIONS_OK')
print(json.dumps(report, ensure_ascii=False, indent=2))
