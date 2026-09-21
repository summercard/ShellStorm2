import bpy, math, json
from pathlib import Path
from mathutils import Matrix, Vector

P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
MODEL = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v005.blend'
SRC_ANIM = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v003.blend'
MELEE_ANIM = P/'assets/art/enemies/normal_enemy_3d/melee_chaser/source/animation/enm_melee_fungboar01_animation_v003.blend'
OUT = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v005.blend'
REPORT = P/'_scratch/security_zombie/animation_v005_report.json'
CLIPS = ['idle', 'walking', 'running', 'attack', 'hurt', 'dead',
         'armed_idle', 'walking_armed', 'running_armed', 'shoot']

bpy.ops.wm.open_mainfile(filepath=str(MODEL))
tgt = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')

with bpy.data.libraries.load(str(SRC_ANIM), link=False) as (src, dst):
    dst.actions = list(src.actions)
    dst.objects = ['enm_ranged_sporeshooter01_armature']
src_arm = next(o for o in dst.objects if o is not None)
src_arm.name = 'SRC_RIG'
bpy.context.scene.collection.objects.link(src_arm)

with bpy.data.libraries.load(str(MELEE_ANIM), link=False) as (src2, dst2):
    dst2.objects = ['enm_melee_fungboar01_armature']
melee_arm = next(o for o in dst2.objects if o is not None)
melee_arm.name = 'REF_RIG'
bpy.context.scene.collection.objects.link(melee_arm)

# gate 1: the source rig must be the melee 36-bone contract
bad = []
for b in melee_arm.data.bones:
    s = src_arm.data.bones.get(b.name)
    if s is None:
        bad.append((b.name, 'missing'))
        continue
    d = max(abs(a - c) for ra, rb in zip(s.matrix_local, b.matrix_local) for a, c in zip(ra, rb))
    if d > 1e-5:
        bad.append((b.name, '%.6f' % d))
print('SOURCE_REST_MATCHES_MELEE', not bad, bad[:4])
if bad:
    raise RuntimeError('source rig not melee contract: %s' % bad[:4])

# gate 2: left/right must not be mirrored between target and melee
side = []
for n in ('L_Upperarm', 'R_Upperarm', 'L_Thigh', 'R_Thigh'):
    if tgt.data.bones[n].head_local.x * melee_arm.data.bones[n].head_local.x <= 0:
        side.append((n, tgt.data.bones[n].head_local.x, melee_arm.data.bones[n].head_local.x))
print('SIDE_CONVENTION_OK', not side, side)
if side:
    raise RuntimeError('mirrored sides: %s' % side)

# hierarchy order (parents before children)
order = []
def walk(b):
    order.append(b.name)
    for c in b.children:
        walk(c)
for b in tgt.data.bones:
    if b.parent is None:
        walk(b)

TR = {b.name: b.matrix_local.to_3x3().copy() for b in tgt.data.bones}
TRH = {b.name: b.matrix_local.to_translation().copy() for b in tgt.data.bones}
SR = {b.name: b.matrix_local.to_3x3().copy() for b in src_arm.data.bones}
STH = {b.name: b.matrix_local.to_translation().copy() for b in src_arm.data.bones}
TP = {b.name: (b.parent.name if b.parent else None) for b in tgt.data.bones}

for pb in tgt.pose.bones:
    pb.rotation_mode = 'QUATERNION'

def solve(src_pose_rot, src_pose_head, driven):
    world = {}
    for name in order:
        parent = TP[name]
        if name in driven:
            rot = src_pose_rot[name] @ SR[name].inverted() @ TR[name]
        elif parent is None:
            rot = TR[name].copy()
        else:
            rot = world[parent].to_3x3() @ (TR[parent].inverted() @ TR[name])
        if parent is None:
            head = TRH[name].copy()
        else:
            offs = TRH[name] - TRH[parent]
            head = world[parent].to_translation() + world[parent].to_3x3() @ (TR[parent].inverted() @ offs)
        # melee drives its whole-body offset through the Hip bone's location channel
        # (Root carries no animation). Hip's parent is Root, so the FK branch above
        # would freeze the pelvis; carry the source world displacement explicitly,
        # otherwise walk bob / fall slide are silently dropped.
        if name == 'Hip' and name in driven:
            head = head + (src_pose_head[name] - STH[name])
        m = rot.to_4x4()
        m.translation = head
        world[name] = m
    return world

def apply(world):
    for name in order:
        bone = tgt.data.bones[name]
        pb = tgt.pose.bones[name]
        m = world[name]
        if bone.parent is None:
            basis = TR[name].to_4x4().inverted() @ m
        else:
            p = bone.parent.name
            rel = TR[p].to_4x4().inverted() @ TR[name].to_4x4()
            basis = rel.inverted() @ world[p].inverted() @ m
        pb.location = basis.to_translation()
        pb.rotation_quaternion = basis.to_quaternion()

actions = {}
for a in dst.actions:
    if a is None:
        continue
    a.name = 'SRCTMP_' + a.name
    a.use_fake_user = True
    actions[a.name[7:]] = a
print('LOADED_ACTIONS', sorted(actions))

made = {}
for clip in CLIPS:
    src_act = actions.get(clip)
    if src_act is None:
        continue
    src_arm.animation_data_create()
    src_arm.animation_data.action = src_act
    if hasattr(src_act, 'slots') and len(src_act.slots):
        src_arm.animation_data.action_slot = src_act.slots[0]
    start, end = int(src_act.frame_range[0]), int(src_act.frame_range[1])

    new = bpy.data.actions.new(clip)
    new.use_fake_user = True
    tgt.animation_data_create()
    tgt.animation_data.action = new
    if hasattr(new, 'slots'):
        try:
            new.slots.new(id_type='OBJECT', name='Rig')
            tgt.animation_data.action_slot = new.slots[0]
        except Exception:
            pass

    for f in range(start, end + 1):
        bpy.context.scene.frame_set(f)
        bpy.context.view_layer.update()
        src_rot = {}
        src_head = {}
        driven = set()
        for name in order:
            spb = src_arm.pose.bones.get(name)
            if spb is None:
                continue
            driven.add(name)
            src_rot[name] = spb.matrix.to_3x3().copy()
            src_head[name] = spb.matrix.to_translation().copy()
        apply(solve(src_rot, src_head, driven))
        for name in order:
            pb = tgt.pose.bones[name]
            pb.keyframe_insert('location', frame=f)
            pb.keyframe_insert('rotation_quaternion', frame=f)
    made[clip] = {'frames': [start, end], 'seconds': round((end - start) / 30.0, 4)}

bpy.context.scene.render.fps = 30

for o in ('SRC_RIG', 'REF_RIG'):
    ob = bpy.data.objects.get(o)
    if ob:
        bpy.data.objects.remove(ob, do_unlink=True)
for a in list(bpy.data.actions):
    if a.name not in CLIPS:
        a.use_fake_user = False
        bpy.data.actions.remove(a)

tgt.animation_data.action = bpy.data.actions.get('idle')
bpy.context.scene.frame_set(1)

missing = [c for c in CLIPS if c not in made]
leftover = [a.name for a in bpy.data.actions if a.name not in CLIPS]
bpy.context.preferences.filepaths.save_version = 0
OUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT))

report = {'output': str(OUT), 'source_animation': str(SRC_ANIM), 'target_model': str(MODEL),
          'clips': made, 'clips_made': len(made), 'missing_clips': missing,
          'unexpected_actions': leftover, 'target_bones': len(tgt.data.bones),
          'retarget_formula': 'M_t = M_s @ R_s^-1 @ R_t with FK position propagation'}
REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
if missing or leftover:
    raise RuntimeError('clip set wrong: missing=%s leftover=%s' % (missing, leftover))
print('ANIM_V005_OK', json.dumps(made, ensure_ascii=False))
