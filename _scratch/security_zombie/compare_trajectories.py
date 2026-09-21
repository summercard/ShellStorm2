import bpy, json
from pathlib import Path
from mathutils import Vector
P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
MELEE = P/'assets/art/enemies/normal_enemy_3d/melee_chaser/source/animation/enm_melee_fungboar01_animation_v003.blend'
NEW = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v004.blend'
CLIPS = {'idle': 'anim_melee_fungboar01_idle_v002',
         'walking': 'anim_melee_fungboar01_walking_v002',
         'running': 'anim_melee_fungboar01_running_v003',
         'attack': 'anim_melee_fungboar01_attack_v003',
         'hurt': 'anim_melee_fungboar01_hurt_v002',
         'dead': 'anim_melee_fungboar01_dead_v002'}
PROBES = ['Head', 'L_Hand', 'R_Hand', 'L_Foot', 'R_Foot', 'Spine02']

def sample(path, clip, action_name):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    s = bpy.context.scene
    arm = next(o for o in s.objects if o.type == 'ARMATURE')
    arm.animation_data_create()
    act = bpy.data.actions.get(action_name)
    arm.animation_data.action = act
    if hasattr(act, 'slots') and len(act.slots):
        arm.animation_data.action_slot = act.slots[0]
    start, end = int(act.frame_range[0]), int(act.frame_range[1])
    out = []
    for f in range(start, end + 1):
        s.frame_set(f)
        bpy.context.view_layer.update()
        out.append({n: list(arm.pose.bones[n].tail) for n in PROBES})
    return out

result = {}
worst = 0.0
for clip, act_name in CLIPS.items():
    a = sample(MELEE, clip, act_name)
    b = sample(NEW, clip, clip if clip in ('idle','walking','running','attack','hurt','dead') else act_name)
    n = min(len(a), len(b))
    per = {}
    for p in PROBES:
        d = max((Vector(a[i][p]) - Vector(b[i][p])).length for i in range(n))
        per[p] = round(d, 5)
    overall = max(per.values())
    worst = max(worst, overall)
    result[clip] = {'frames_compared': n, 'max_delta_m': overall, 'per_bone': per,
                    'melee_frames': len(a), 'new_frames': len(b)}
print('TRAJECTORY_COMPARE', json.dumps(result, indent=2))
print('WORST_DELTA_M', round(worst, 6))
(P/'_scratch/security_zombie/trajectory_compare.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
