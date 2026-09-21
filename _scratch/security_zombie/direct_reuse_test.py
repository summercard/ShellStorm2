"""实测「直接把小僵尸动作套到新骨架上」会发生什么。

新骨架的骨名已经和小僵尸完全一致（v005 改名后），所以通道能匹配上、动作"能播"。
本脚本量化它播出来到底对不对，并与正确重定向的结果对照。

判据：世界旋转增量 Δ = M_pose @ R_rest^-1（"骨骼相对自身静止姿态实际转了多少"）。
直接套用时，同一组通道值会被解释到不同的静止系上 ⇒ Δ 应出现大偏差。
"""
import bpy, json, math
from pathlib import Path
from mathutils import Vector

P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
MELEE_ANIM = P/'assets/art/enemies/normal_enemy_3d/melee_chaser/source/animation/enm_melee_fungboar01_animation_v003.blend'
POLICE_MODEL = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v005.blend'
POLICE_ANIM = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v005.blend'
MELEE_ACT = 'anim_melee_fungboar01_idle_v002'
PROBES = ['Hip', 'Waist', 'Spine02', 'Neck', 'Head',
          'L_Upperarm', 'L_Forearm', 'L_Hand', 'R_Upperarm', 'R_Forearm', 'R_Hand',
          'L_Thigh', 'L_Calf', 'L_Foot', 'R_Thigh', 'R_Calf', 'R_Foot']

out = {}

# ---------- 1. 小僵尸原版（基准） ----------
bpy.ops.wm.open_mainfile(filepath=str(MELEE_ANIM))
sc = bpy.context.scene
arm = next(o for o in sc.objects if o.type == 'ARMATURE')
act = bpy.data.actions.get(MELEE_ACT)
arm.animation_data_create(); arm.animation_data.action = act
if hasattr(arm.animation_data, 'action_slot') and hasattr(act, 'slots') and len(act.slots):
    arm.animation_data.action_slot = act.slots[0]
rest_m = {n: arm.data.bones[n].matrix_local.to_3x3().copy() for n in PROBES}
s, e = int(act.frame_range[0]), int(act.frame_range[1])
base = []
for f in range(s, e + 1):
    sc.frame_set(f); bpy.context.view_layer.update()
    base.append({n: arm.pose.bones[n].matrix.to_3x3() @ rest_m[n].inverted() for n in PROBES})
D = e - s + 1

# 通道匹配情况：melee action 的 fcurve 有多少能落到新骨架上
paths = sorted({fc.data_path.split('"')[1] for fc in act.fcurves if '"' in fc.data_path})
out['melee_action_bone_channels'] = len(paths)

# ---------- 2. 直接套用：melee action 赋给新骨架 ----------
bpy.ops.wm.open_mainfile(filepath=str(POLICE_MODEL))
sc = bpy.context.scene
parm = next(o for o in sc.objects if o.type == 'ARMATURE')
with bpy.data.libraries.load(str(MELEE_ANIM), link=False) as (src, dst):
    dst.actions = [MELEE_ACT]
direct_act = next(a for a in dst.actions if a is not None)
parm.animation_data_create(); parm.animation_data.action = direct_act
if hasattr(parm.animation_data, 'action_slot') and hasattr(direct_act, 'slots') and len(direct_act.slots):
    parm.animation_data.action_slot = direct_act.slots[0]
rest_p = {n: parm.data.bones[n].matrix_local.to_3x3().copy() for n in PROBES}
s2, e2 = int(direct_act.frame_range[0]), int(direct_act.frame_range[1])
n2 = min(D, e2 - s2 + 1)
direct = []
for f in range(s2, s2 + n2):
    sc.frame_set(f); bpy.context.view_layer.update()
    direct.append({n: parm.pose.bones[n].matrix.to_3x3() @ rest_p[n].inverted() for n in PROBES})

# 直接套用的偏差
def qdiff(a, b):
    return math.degrees(abs(a.to_quaternion().rotation_difference(b.to_quaternion()).angle))

direct_err = {}
for p in PROBES:
    direct_err[p] = round(max(qdiff(base[i][p], direct[i][p]) for i in range(n2)), 3)
out['direct_reuse'] = {'frames_compared': n2, 'max_delta_err_deg': max(direct_err.values()),
                       'per_bone_deg': direct_err}

# 顺带：世界朝向差（最直观的"看起来歪了多少"）
world_err = {}
for p in PROBES:
    vals = []
    for i in range(n2):
        # 用骨指向轴（世界系）比"身体朝向歪多少"，这是肉眼能看到的量
        vals.append(qdiff(base[i][p], direct[i][p]))
    world_err[p] = round(max(vals), 3)
out['direct_reuse_world_tilt_deg'] = world_err

# ---------- 3. 正确重定向后的偏差（对照） ----------
bpy.ops.wm.open_mainfile(filepath=str(POLICE_ANIM))
sc = bpy.context.scene
parm2 = next(o for o in sc.objects if o.type == 'ARMATURE')
a2 = bpy.data.actions.get('idle')
parm2.animation_data_create(); parm2.animation_data.action = a2
if hasattr(parm2.animation_data, 'action_slot') and hasattr(a2, 'slots') and len(a2.slots):
    parm2.animation_data.action_slot = a2.slots[0]
rest_p2 = {n: parm2.data.bones[n].matrix_local.to_3x3().copy() for n in PROBES}
s3, e3 = int(a2.frame_range[0]), int(a2.frame_range[1])
n3 = min(D, e3 - s3 + 1)
fixed = []
for f in range(s3, s3 + n3):
    sc.frame_set(f); bpy.context.view_layer.update()
    fixed.append({n: parm2.pose.bones[n].matrix.to_3x3() @ rest_p2[n].inverted() for n in PROBES})
fixed_err = {}
for p in PROBES:
    fixed_err[p] = round(max(qdiff(base[i][p], fixed[i][p]) for i in range(n3)), 3)
out['after_retarget'] = {'frames_compared': n3, 'max_delta_err_deg': max(fixed_err.values()),
                         'per_bone_deg': fixed_err}

print('DIRECT_REUSE_RESULT', json.dumps(out, ensure_ascii=False, indent=2))
(P/'_scratch/security_zombie/direct_reuse_test.json').write_text(
    json.dumps(out, ensure_ascii=False, indent=2), encoding='utf-8')
print('DIRECT_REUSE_TEST_DONE')
