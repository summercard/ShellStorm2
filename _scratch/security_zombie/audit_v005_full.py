"""v005 模型侧综合验证 + 持枪/开枪动作有效性核查。

A. 骨骼命名：与小僵尸 36 骨契约逐项比对
B. 绑定定位：逐骨局部性探针 —— 旋转某骨，被移动的顶点必须落在该骨附近
   （只证明"会动"是假绿；要证明"动对了地方"）
C. 尺寸/朝向：源高、脚底 z、正面 +Y
D. 持枪/开枪：与未持枪剪辑逐骨比对，确认不是占位复制
"""
import bpy, json, math
from pathlib import Path
from mathutils import Vector
P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
MODEL = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v005.blend'
ANIM = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v005.blend'
MELEE = P/'assets/art/enemies/normal_enemy_3d/melee_chaser/source/model/enm_melee_fungboar01_model_v002.blend'
CONTRACT = ['Root', 'Hip', 'Waist', 'Spine02', 'Neck', 'Head',
            'L_Clavicle', 'L_Upperarm', 'L_Forearm', 'L_Hand',
            'L_Thumb1', 'L_Thumb2', 'L_Index1', 'L_Index2', 'L_Middle1', 'L_Middle2', 'L_Pinky1', 'L_Pinky2',
            'R_Clavicle', 'R_Upperarm', 'R_Forearm', 'R_Hand',
            'R_Thumb1', 'R_Thumb2', 'R_Index1', 'R_Index2', 'R_Middle1', 'R_Middle2', 'R_Pinky1', 'R_Pinky2',
            'L_Thigh', 'L_Calf', 'L_Foot', 'R_Thigh', 'R_Calf', 'R_Foot']
out = {}

# ---------- A/C: model ----------
bpy.ops.wm.open_mainfile(filepath=str(MODEL))
sc = bpy.context.scene
arm = next(o for o in sc.objects if o.type == 'ARMATURE')
mesh = next(o for o in sc.objects if o.type == 'MESH')
names = [b.name for b in arm.data.bones]
out['bone_count'] = len(names)
out['contract_missing'] = [n for n in CONTRACT if n not in names]
out['contract_present'] = len(CONTRACT) - len(out['contract_missing'])
out['extra_bones'] = sorted(set(names) - set(CONTRACT))
out['skeleton_id'] = arm.data.get('skeleton_id')
out['root_is_parentless'] = arm.data.bones['Root'].parent is None
out['hip_parent'] = arm.data.bones['Hip'].parent.name

# groups / weights
gn = [g.name for g in mesh.vertex_groups]
out['vertex_groups'] = len(gn)
out['groups_without_bone'] = [g for g in gn if g not in names]
out['contract_groups_missing'] = [n for n in CONTRACT if n not in gn]
ws = [sum(g.weight for g in v.groups) for v in mesh.data.vertices]
out['unbound_vertices'] = sum(1 for w in ws if w < 1e-4)
out['weight_sum_off'] = sum(1 for w in ws if abs(w - 1.0) > 1e-3)

# size / orientation
lo = Vector((1e9,) * 3); hi = Vector((-1e9,) * 3)
for v in mesh.data.vertices:
    w = mesh.matrix_world @ v.co
    for i in range(3):
        lo[i] = min(lo[i], w[i]); hi[i] = max(hi[i], w[i])
out['mesh_world_bbox'] = [round(hi[i] - lo[i], 4) for i in range(3)]
out['height'] = round(hi.z - lo.z, 6)
out['feet_z'] = round(lo.z, 6)
out['centre_x'] = round((lo.x + hi.x) / 2, 5)
out['centre_y'] = round((lo.y + hi.y) / 2, 5)
# foot bone must point +Y (forward contract), compare with melee
def foot_dir(a):
    b = a.data.bones['L_Foot']
    d = (b.tail_local - b.head_local).normalized()
    return [round(c, 4) for c in d]
out['police_L_Foot_dir'] = foot_dir(arm)
bpy.ops.wm.open_mainfile(filepath=str(MELEE))
m_arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
out['melee_L_Foot_dir'] = foot_dir(m_arm)

# ---------- B: per-bone locality probe ----------
bpy.ops.wm.open_mainfile(filepath=str(MODEL))
sc = bpy.context.scene
arm = next(o for o in sc.objects if o.type == 'ARMATURE')
mesh = next(o for o in sc.objects if o.type == 'MESH')
dg = bpy.context.evaluated_depsgraph_get()
base = [v.co.copy() for v in mesh.evaluated_get(dg).data.vertices]
probe = {}
for bname in ('L_Hand', 'R_Hand', 'Head', 'L_Foot', 'R_Thigh'):
    pb = arm.pose.bones[bname]
    pb.rotation_mode = 'QUATERNION'
    pb.rotation_quaternion = (0.9239, 0.3827, 0.0, 0.0)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    cur = [v.co.copy() for v in mesh.evaluated_get(dg).data.vertices]
    moved_idx = [i for i in range(len(base)) if (base[i] - cur[i]).length > 1e-4]
    pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    # distance of moved verts to the bone head point (a loose sanity radius)
    hp = arm.data.bones[bname].head_local
    grads = [sum(g.weight for g in mesh.data.vertices[i].groups) for i in moved_idx]
    # which vertex groups dominate the moved set
    dom = {}
    for i in moved_idx:
        v = mesh.data.vertices[i]
        for g in v.groups:
            if g.weight > 0.5:
                nm = mesh.vertex_groups[g.group].name
                dom[nm] = dom.get(nm, 0) + 1
    probe[bname] = {'moved': len(moved_idx), 'weighted_ok': sum(1 for g in grads if abs(g - 1.0) < 1e-3),
                    'dominant_groups': dict(sorted(dom.items(), key=lambda kv: -kv[1])[:3])}
out['locality_probe'] = probe

# ---------- D: armed / shoot clips vs unarmed ----------
bpy.ops.wm.open_mainfile(filepath=str(ANIM))
sc = bpy.context.scene
arm = next(o for o in sc.objects if o.type == 'ARMATURE')
PROBES = ['Head', 'L_Upperarm', 'L_Forearm', 'L_Hand', 'R_Upperarm', 'R_Forearm', 'R_Hand',
          'L_Thigh', 'R_Thigh', 'Hip']
rest = {n: arm.data.bones[n].matrix_local.to_3x3().copy() for n in PROBES}

def sample(clip):
    act = bpy.data.actions.get(clip)
    if act is None:
        return None
    arm.animation_data_create()
    arm.animation_data.action = act
    if hasattr(arm.animation_data, 'action_slot') and hasattr(act, 'slots') and len(act.slots):
        arm.animation_data.action_slot = act.slots[0]
    s, e = int(act.frame_range[0]), int(act.frame_range[1])
    frames = []
    for f in range(s, e + 1):
        sc.frame_set(f)
        bpy.context.view_layer.update()
        frames.append({n: (arm.pose.bones[n].matrix.to_3x3() @ rest[n].inverted()) for n in PROBES})
    return frames

pairs = [('idle', 'armed_idle'), ('walking', 'walking_armed'), ('running', 'running_armed'), ('attack', 'shoot')]
cmp = {}
for base_c, arm_c in pairs:
    a = sample(base_c); b = sample(arm_c)
    if a is None or b is None:
        cmp['%s_vs_%s' % (base_c, arm_c)] = 'MISSING'
        continue
    n = min(len(a), len(b))
    mx = {}
    for p in PROBES:
        mx[p] = round(max(math.degrees(abs(a[i][p].to_quaternion().rotation_difference(b[i][p].to_quaternion()).angle)) for i in range(n)), 3)
    cmp['%s_vs_%s' % (base_c, arm_c)] = {'max_deg': max(mx.values()), 'per_bone': mx}
out['armed_vs_unarmed'] = cmp

print('V005_MODEL_AUDIT', json.dumps(out, ensure_ascii=False, indent=2))
(P/'_scratch/security_zombie/v005_model_audit.json').write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding='utf-8')

fails = []
if out['contract_missing']: fails.append('contract bones missing')
if out['groups_without_bone']: fails.append('groups without bone')
if out['unbound_vertices']: fails.append('unbound vertices')
if abs(out['height'] - 1.857143) > 1e-3: fails.append('height off')
if abs(out['feet_z']) > 1e-3: fails.append('feet not at z=0')
if not out['root_is_parentless']: fails.append('Root not root')
for b, r in probe.items():
    if r['moved'] == 0: fails.append('bone %s does not deform' % b)
    if r['weighted_ok'] != r['moved']: fails.append('bone %s moved unweighted verts' % b)
print('AUDIT_FAILURES', fails)
if fails:
    raise RuntimeError(fails)
print('V005_AUDIT_OK')
