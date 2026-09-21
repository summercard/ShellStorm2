import bpy, math, json
from pathlib import Path
from mathutils import Matrix, Vector

P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
MODEL = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v005.blend'
SRC_ANIM = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v003.blend'
MELEE_ANIM = P/'assets/art/enemies/normal_enemy_3d/melee_chaser/source/animation/enm_melee_fungboar01_animation_v003.blend'
OUT = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v004.blend'
REPORT = P/'_scratch/security_zombie/animation_v004_report.json'
CLIPS = ['idle', 'walking', 'running', 'attack', 'hurt', 'dead',
         'armed_idle', 'walking_armed', 'running_armed', 'shoot']

bpy.ops.wm.open_mainfile(filepath=str(MODEL))
tgt = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
tgt.name = 'enm_ranged_sporeshooter01_armature'

# Bring in the source rig (36-bone melee contract) plus its actions.
with bpy.data.libraries.load(str(SRC_ANIM), link=False) as (src, dst):
    dst.actions = [n for n in src.actions if any(n.endswith(c) or n == c or n.replace('anim_ranged_sporeshooter01_', '') in CLIPS for c in CLIPS)]
    dst.objects = ['enm_ranged_sporeshooter01_armature']
src_arm = next(o for o in dst.objects if o is not None)
if src_arm is None:
    raise RuntimeError('source armature not loaded')
src_arm.name = 'SRC_RIG'
for o in list(bpy.context.scene.objects):
    if o.type == 'ARMATURE' and o is not src_arm:
        pass
bpy.context.scene.collection.objects.link(src_arm)

# Reference melee rig to prove the source rest pose is the 36-bone contract.
with bpy.data.libraries.load(str(MELEE_ANIM), link=False) as (src2, dst2):
    dst2.objects = ['enm_melee_fungboar01_armature']
melee_arm = next(o for o in dst2.objects if o is not None)
melee_arm.name = 'REF_RIG'
bpy.context.scene.collection.objects.link(melee_arm)

# --- equivalence gate: source rest == melee rest, and both use melee bone names ---
mismatch = []
for b in melee_arm.data.bones:
    s = src_arm.data.bones.get(b.name)
    if s is None:
        mismatch.append((b.name, 'missing on source'))
        continue
    if (s.matrix_local - b.matrix_local).median_scale > 1e-5 if hasattr(s.matrix_local - b.matrix_local, 'median_scale') else False:
        pass
    d = max(abs(a - c) for ra, rb in zip(s.matrix_local, b.matrix_local) for a, c in zip(ra, rb))
    if d > 1e-5:
        mismatch.append((b.name, 'rest delta %.6f' % d))
print('SOURCE_REST_MATCHES_MELEE', len(mismatch) == 0, mismatch[:5])
if mismatch:
    raise RuntimeError('source rig is not the melee contract: %s' % mismatch[:5])

# --- side convention gate: L_ chains must sit on -X for both rigs ---
side_bad = []
for n in ('L_Upperarm', 'R_Upperarm', 'L_Thigh', 'R_Thigh'):
    t_x = tgt.data.bones[n].head_local.x
    m_x = melee_arm.data.bones[n].head_local.x
    if t_x * m_x <= 0:
        side_bad.append((n, 'target %.4f vs melee %.4f' % (t_x, m_x)))
print('SIDE_CONVENTION_OK', len(side_bad) == 0, side_bad)
if side_bad:
    raise RuntimeError('left/right sides are mirrored: %s' % side_bad)

for pb in tgt.pose.bones:
    pb.rotation_mode = 'QUATERNION'

k = 1.0  # both rigs are authored at the same 1.857143 m source height
tgt_rest = {b.name: b.matrix_local.copy() for b in tgt.data.bones}
src_rest = {b.name: b.matrix_local.copy() for b in src_arm.data.bones}

order = []
def walk(bone):
    order.append(bone.name)
    for c in bone.children:
        walk(c)
for b in tgt.data.bones:
    if b.parent is None:
        walk(b)
order_index = {n: i for i, n in enumerate(order)}

def retarget_frame(action, frame):
    src_arm.animation_data_create()
    src_arm.animation_data.action = action
    if hasattr(action, 'slots') and len(action.slots):
        src_arm.animation_data.action_slot = action.slots[0]
    bpy.context.scene.frame_set(int(frame))
    bpy.context.view_layer.update()

    desired = {}
    for name in order:
        sb = src_arm.data.bones.get(name)
        if sb is None:
            continue
        spb = src_arm.pose.bones[name]
        msrc = spb.matrix.copy()
        sr = src_rest[name]
        tr = tgt_rest[name]
        align = tr.to_3x3() @ sr.to_3x3().inverted()
        rot = (align @ msrc.to_3x3())
        t = tr.to_translation()
        if name == 'Hip':
            t = t + (msrc.to_translation() - sr.to_translation()) * k
        m = rot.to_4x4()
        m.translation = t
        desired[name] = m

    # unmapped bones ride their parent (they hold no melee channel)
    for name in order:
        if name in desired:
            continue
        bone = tgt.data.bones[name]
        parent = bone.parent
        if parent is None:
            desired[name] = tgt_rest[name]
        else:
            rel = tgt_rest[parent.name].inverted() @ tgt_rest[name]
            desired[name] = desired[parent.name] @ rel

    for name in order:
        bone = tgt.data.bones[name]
        pb = tgt.pose.bones[name]
        m = desired[name]
        if bone.parent is None:
            basis = tgt_rest[name].inverted() @ m
        else:
            p = bone.parent
            rel = tgt_rest[p.name].inverted() @ tgt_rest[name]
            basis = rel.inverted() @ desired[p.name].inverted() @ m
        if name not in tgt_rest:
            continue
        pb.location = basis.to_translation()
        pb.rotation_quaternion = basis.to_quaternion()
        if name == 'Hip' or name in ('L_Upperarm','R_Upperarm','L_Thigh','R_Thigh','Spine02','Neck','Head'):
            pass
    return desired

# Map every clip name to its loaded action. The library actions carry the plain
# clip names, so park them under a temporary prefix before the baked ones are made.
actions = {}
for a in dst.actions:
    if a is None:
        continue
    short = a.name.replace('anim_ranged_sporeshooter01_', '')
    a.name = 'SRCTMP_' + short
    a.use_fake_user = False
    actions[short] = a
print('LOADED_ACTIONS', sorted(actions))

made = {}
for clip in CLIPS:
    if clip not in actions:
        print('SKIP_MISSING_CLIP', clip)
        continue
    src_action = actions[clip]
    start, end = int(src_action.frame_range[0]), int(src_action.frame_range[1])
    tgt.animation_data_create()
    new_action = bpy.data.actions.new(clip)
    new_action.use_fake_user = True
    tgt.animation_data.action = new_action
    if hasattr(new_action, 'slots'):
        try:
            slot = new_action.slots.new(id_type='OBJECT', name='Rig')
            tgt.animation_data.action_slot = slot
        except Exception:
            pass
    src_arm.animation_data_create()
    src_arm.animation_data.action = src_action
    if hasattr(src_action, 'slots') and len(src_action.slots):
        src_arm.animation_data.action_slot = src_action.slots[0]
    for f in range(start, end + 1):
        bpy.context.scene.frame_set(f)
        bpy.context.view_layer.update()
        desired = {}
        for name in order:
            spb = src_arm.pose.bones.get(name)
            if spb is None:
                continue
            msrc = spb.matrix.copy()
            sr = src_rest[name]; tr = tgt_rest[name]
            align = tr.to_3x3() @ sr.to_3x3().inverted()
            m = (align @ msrc.to_3x3()).to_4x4()
            m.translation = tr.to_translation()
            if name == 'Hip':
                m.translation = tr.to_translation() + (msrc.to_translation() - sr.to_translation()) * k
            desired[name] = m
        for name in order:
            if name in desired:
                continue
            bone = tgt.data.bones[name]
            if bone.parent is None:
                desired[name] = tgt_rest[name]
            else:
                rel = tgt_rest[bone.parent.name].inverted() @ tgt_rest[name]
                desired[name] = desired[bone.parent.name] @ rel
        for name in order:
            bone = tgt.data.bones[name]
            pb = tgt.pose.bones[name]
            m = desired[name]
            if bone.parent is None:
                basis = tgt_rest[name].inverted() @ m
            else:
                p = bone.parent
                rel = tgt_rest[p.name].inverted() @ tgt_rest[name]
                basis = rel.inverted() @ desired[p.name].inverted() @ m
            pb.location = basis.to_translation()
            pb.rotation_quaternion = basis.to_quaternion()
            pb.keyframe_insert('location', frame=f)
            pb.keyframe_insert('rotation_quaternion', frame=f)
    made[clip] = {'frames': [start, end], 'seconds': (end - start) / 30.0}

bpy.context.scene.render.fps = 30
tgt.animation_data.action = bpy.data.actions.get('idle')
bpy.context.scene.frame_set(1)

# Drop the helper rigs and the temporary source actions before saving.
for o in ('SRC_RIG', 'REF_RIG'):
    ob = bpy.data.objects.get(o)
    if ob:
        bpy.data.objects.remove(ob, do_unlink=True)
for a in list(bpy.data.actions):
    if a.name not in CLIPS:
        a.use_fake_user = False
        bpy.data.actions.remove(a)

missing_clips = [c for c in CLIPS if c not in made]
leftover = [a.name for a in bpy.data.actions if a.name not in CLIPS]
bpy.context.preferences.filepaths.save_version = 0
OUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT))

report = {'output': str(OUT), 'source_animation': str(SRC_ANIM),
          'target_model': str(MODEL), 'clips': made,
          'target_bones': len(tgt.data.bones), 'clips_made': len(made),
          'missing_clips': missing_clips, 'unexpected_actions': leftover,
          'source_rest_matches_melee': True, 'side_convention_ok': True}
REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
if missing_clips or leftover:
    raise RuntimeError('clip set wrong: missing=%s leftover=%s' % (missing_clips, leftover))
print('ANIM_V004_OK', json.dumps(made, ensure_ascii=False))
