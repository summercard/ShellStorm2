"""确认每段剪辑在目标骨架上确实"在动"：统计帧间自运动幅度。
delta 逐帧与源 0 误差只说明"跟着源走"，本脚本另行确认源本身非静止。"""
import bpy, json, math
from pathlib import Path
P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
CASES = {
    'V005(目标)': P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v005.blend',
    'V003(源)': P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v003.blend',
    'MELEE(小僵尸)': P/'assets/art/enemies/normal_enemy_3d/melee_chaser/source/animation/enm_melee_fungboar01_animation_v003.blend',
}
PROBES = ['Head', 'L_Upperarm', 'L_Forearm', 'L_Hand', 'R_Upperarm', 'R_Forearm', 'R_Hand',
          'L_Thigh', 'L_Calf', 'R_Thigh', 'R_Calf', 'Hip']
res = {}
for label, path in CASES.items():
    bpy.ops.wm.open_mainfile(filepath=str(path))
    sc = bpy.context.scene
    arm = next(o for o in sc.objects if o.type == 'ARMATURE')
    rest = {n: arm.data.bones[n].matrix_local.to_3x3().copy() for n in PROBES}
    per_clip = {}
    for act in bpy.data.actions:
        arm.animation_data_create(); arm.animation_data.action = act
        if hasattr(arm.animation_data, 'action_slot') and hasattr(act, 'slots') and len(act.slots):
            arm.animation_data.action_slot = act.slots[0]
        s, e = int(act.frame_range[0]), int(act.frame_range[1])
        prev = None
        peak = 0.0
        span = {n: [] for n in PROBES}
        for f in range(s, e + 1):
            sc.frame_set(f); bpy.context.view_layer.update()
            cur = {n: (arm.pose.bones[n].matrix.to_3x3() @ rest[n].inverted()) for n in PROBES}
            for n in PROBES:
                span[n].append(cur[n])
            if prev is not None:
                d = max(math.degrees(abs(cur[n].to_quaternion().rotation_difference(prev[n].to_quaternion()).angle)) for n in PROBES)
                peak = max(peak, d)
            prev = cur
        # total range per bone over the clip (max pairwise deviation from frame 0)
        rng = {}
        for n in PROBES:
            rng[n] = round(max(math.degrees(abs(span[n][0].to_quaternion().rotation_difference(x.to_quaternion()).angle)) for x in span[n]), 3)
        per_clip[act.name] = {'frames': e - s + 1, 'max_frame_to_frame_deg': round(peak, 3),
                              'max_range_deg': max(rng.values()),
                              'range_per_bone': rng}
    res[label] = per_clip
    print('====', label, '====')
    for k, v in per_clip.items():
        print('  %-22s frames=%3d  step=%7.3f  range=%7.3f' % (k, v['frames'], v['max_frame_to_frame_deg'], v['max_range_deg']))
(P/'_scratch/security_zombie/motion_range.json').write_text(json.dumps(res, ensure_ascii=False, indent=2), encoding='utf-8')
print('MOTION_RANGE_REPORTED')
