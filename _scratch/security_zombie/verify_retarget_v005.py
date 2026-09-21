"""端到端保真验证：从已保存的 animation_v005.blend 读回姿态，独立复算
世界旋转增量 delta = M_pose @ R_rest^-1，与 melee 源逐帧比对。

判据依据：本流程保持原绑定不动、只做旋转重定向 M_t = M_s @ R_s^-1 @ R_t，
⇒ delta_t == delta_s 应当成立。骨指向轴(bone Y)因两套 rest 朝向不同而必然有差，
不是有效判据。delta 一致 = 角色"动的方式"一致 = 新骨架能正确播放动作。
"""
import bpy, json, math
from pathlib import Path
from mathutils import Vector
P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
MELEE = P/'assets/art/enemies/normal_enemy_3d/melee_chaser/source/animation/enm_melee_fungboar01_animation_v003.blend'
NEW = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v005.blend'
MELEE_ACT = {'idle': 'anim_melee_fungboar01_idle_v002',
             'walking': 'anim_melee_fungboar01_walking_v002',
             'running': 'anim_melee_fungboar01_running_v003',
             'attack': 'anim_melee_fungboar01_attack_v003',
             'hurt': 'anim_melee_fungboar01_hurt_v002',
             'dead': 'anim_melee_fungboar01_dead_v002'}
PROBES = ['Hip', 'Spine02', 'Neck', 'Head', 'L_Upperarm', 'L_Forearm', 'L_Hand',
          'R_Upperarm', 'R_Forearm', 'R_Hand', 'L_Thigh', 'L_Calf', 'L_Foot',
          'R_Thigh', 'R_Calf', 'R_Foot']


def load(path):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
    return bpy.context.scene, arm


def bind(arm, act_name):
    arm.animation_data_create()
    act = bpy.data.actions.get(act_name)
    if act is None:
        raise RuntimeError('missing action %s' % act_name)
    arm.animation_data.action = act
    if hasattr(arm.animation_data, 'action_slot') and hasattr(act, 'slots') and len(act.slots):
        arm.animation_data.action_slot = act.slots[0]
    return act


def sample(arm, act, probes):
    scene = bpy.context.scene
    rest = {n: arm.data.bones[n].matrix_local.to_3x3().copy() for n in probes}
    start, end = int(act.frame_range[0]), int(act.frame_range[1])
    rot_delta = {n: [] for n in probes}
    hip = []
    for f in range(start, end + 1):
        scene.frame_set(f)
        bpy.context.view_layer.update()
        for n in probes:
            m = arm.pose.bones[n].matrix.to_3x3()
            rot_delta[n].append(m @ rest[n].inverted())
        hip.append(arm.pose.bones['Hip'].matrix.to_translation().copy())
    return {'frames': [start, end], 'delta': rot_delta, 'hip': hip}


def ang(a, b):
    q = a.to_quaternion().rotation_difference(b.to_quaternion())
    return math.degrees(abs(q.angle))


# --- melee 侧采样 ---
scene, m_arm = load(MELEE)
melee = {}
for clip, act_name in MELEE_ACT.items():
    act = bind(m_arm, act_name)
    melee[clip] = sample(m_arm, act, PROBES)

# --- 目标侧采样 ---
scene, t_arm = load(NEW)
rows = {}
worst = 0.0
for clip in MELEE_ACT:
    act = bind(t_arm, clip)
    tgt = sample(t_arm, act, PROBES)
    n = min(len(melee[clip]['hip']), len(tgt['hip']))
    per = {}
    for p in PROBES:
        per[p] = round(max(ang(melee[clip]['delta'][p][i], tgt['delta'][p][i]) for i in range(n)), 4)
    hd_s = [melee[clip]['hip'][i] - melee[clip]['hip'][0] for i in range(n)]
    hd_t = [tgt['hip'][i] - tgt['hip'][0] for i in range(n)]
    travel_s = max(v.length for v in hd_s)
    hip_err = max((hd_s[i] - hd_t[i]).length for i in range(n))
    overall = max(per.values())
    worst = max(worst, overall)
    rows[clip] = {'frames': n,
                  'max_delta_angle_deg': overall,
                  'per_bone_deg': per,
                  'melee_hip_travel_m': round(travel_s, 4),
                  'hip_path_err_m': round(hip_err, 4)}
    print('CLIP', clip, 'max_delta=%.4f deg' % overall,
          'hip_travel=%.3f err=%.4f' % (travel_s, hip_err))

print('DELTA_COMPARE', json.dumps(rows, ensure_ascii=False, indent=2))
print('WORST_DELTA_ANGLE_DEG', round(worst, 4))
(P/'_scratch/security_zombie/delta_compare_v005.json').write_text(
    json.dumps(rows, ensure_ascii=False, indent=2), encoding='utf-8')
if worst > 2.0:
    raise RuntimeError('delta mismatch too large: %.4f deg' % worst)
print('RETARGET_DELTA_OK')
