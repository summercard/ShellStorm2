import bpy, json, math
from pathlib import Path
from mathutils import Vector
P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
MELEE = P/'assets/art/enemies/normal_enemy_3d/melee_chaser/source/animation/enm_melee_fungboar01_animation_v003.blend'
NEW = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v005.blend'
CLIPS = {'idle': 'anim_melee_fungboar01_idle_v002',
         'walking': 'anim_melee_fungboar01_walking_v002',
         'running': 'anim_melee_fungboar01_running_v003',
         'attack': 'anim_melee_fungboar01_attack_v003',
         'hurt': 'anim_melee_fungboar01_hurt_v002',
         'dead': 'anim_melee_fungboar01_dead_v002'}
PROBES = ['Head', 'Spine02', 'L_Upperarm', 'L_Forearm', 'L_Hand',
          'R_Upperarm', 'R_Forearm', 'R_Hand', 'L_Thigh', 'L_Calf', 'R_Thigh', 'R_Calf']

def sample(path, action_name):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    s = bpy.context.scene
    arm = next(o for o in s.objects if o.type == 'ARMATURE')
    arm.animation_data_create()
    act = bpy.data.actions.get(action_name)
    if act is None:
        raise RuntimeError('missing action %s in %s' % (action_name, path))
    arm.animation_data.action = act
    if hasattr(act, 'slots') and len(act.slots):
        arm.animation_data.action_slot = act.slots[0]
    start, end = int(act.frame_range[0]), int(act.frame_range[1])
    out = []
    for f in range(start, end + 1):
        s.frame_set(f)
        bpy.context.view_layer.update()
        rec = {}
        for n in PROBES:
            pb = arm.pose.bones[n]
            m = pb.matrix.to_3x3()
            y = Vector((m[0][1], m[1][1], m[2][1])).normalized()   # bone pointing axis
            rec[n] = list(y)
        rec['_Hip'] = list(arm.pose.bones['Hip'].matrix.to_translation())
        out.append(rec)
    return out

def ang(u, v):
    d = max(-1.0, min(1.0, Vector(u).dot(Vector(v))))
    return math.degrees(math.acos(d))

results = {}
worst = 0.0
for clip, act_name in CLIPS.items():
    a = sample(MELEE, act_name)
    b = sample(NEW, clip)
    n = min(len(a), len(b))
    per = {}
    for p in PROBES:
        per[p] = round(max(ang(a[i][p], b[i][p]) for i in range(n)), 3)
    # hip travel: length of the hip path relative to its own start
    hip_a = [Vector(a[i]['_Hip']) - Vector(a[0]['_Hip']) for i in range(n)]
    hip_b = [Vector(b[i]['_Hip']) - Vector(b[0]['_Hip']) for i in range(n)]
    hip_err = max((hip_a[i] - hip_b[i]).length for i in range(n))
    overall = max(per.values())
    worst = max(worst, overall)
    results[clip] = {'frames': n, 'max_bone_angle_deg': overall,
                     'per_bone_deg': per, 'hip_path_err_m': round(hip_err, 5),
                     'melee_frames': len(a), 'new_frames': len(b)}

print('ANGLE_COMPARE', json.dumps(results, ensure_ascii=False, indent=2))
print('WORST_BONE_ANGLE_DEG', round(worst, 4))
(P/'_scratch/security_zombie/angle_compare.json').write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
if worst > 8.0:
    raise RuntimeError('retarget drift too large: %.3f deg' % worst)
print('RETARGET_FIDELITY_OK')
