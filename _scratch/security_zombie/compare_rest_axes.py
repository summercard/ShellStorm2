import bpy, json, math
from pathlib import Path
from mathutils import Vector
P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
MELEE = P/'assets/art/enemies/normal_enemy_3d/melee_chaser/source/model/enm_melee_fungboar01_model_v002.blend'
POLICE = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v005.blend'
NAMES = ['Root','Hip','Waist','Spine02','Neck','Head',
         'L_Clavicle','L_Upperarm','L_Forearm','L_Hand',
         'R_Clavicle','R_Upperarm','R_Forearm','R_Hand',
         'L_Thigh','L_Calf','L_Foot','R_Thigh','R_Calf','R_Foot']

def rest(path):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
    out = {}
    for n in NAMES:
        b = arm.data.bones.get(n)
        if b is None:
            continue
        m = b.matrix_local.to_3x3()
        out[n] = {
            'y_axis': [round(Vector((m[0][1], m[1][1], m[2][1])).normalized()[i], 5) for i in range(3)],
            'x_axis': [round(Vector((m[0][0], m[1][0], m[2][0])).normalized()[i], 5) for i in range(3)],
            'z_axis': [round(Vector((m[0][2], m[1][2], m[2][2])).normalized()[i], 5) for i in range(3)],
            'head': [round(c, 5) for c in b.head_local],
            'len': round(b.length, 5),
        }
    return out

def ang(u, v):
    d = max(-1.0, min(1.0, Vector(u).dot(Vector(v))))
    return round(math.degrees(math.acos(d)), 2)

m = rest(MELEE)
p = rest(POLICE)
rows = []
for n in NAMES:
    if n not in m or n not in p:
        rows.append({'bone': n, 'status': 'missing', 'in_melee': n in m, 'in_police': n in p})
        continue
    rows.append({'bone': n,
                 'y_angle_deg': ang(m[n]['y_axis'], p[n]['y_axis']),
                 'x_angle_deg': ang(m[n]['x_axis'], p[n]['x_axis']),
                 'z_angle_deg': ang(m[n]['z_axis'], p[n]['z_axis']),
                 'melee_len': m[n]['len'], 'police_len': p[n]['len'],
                 'melee_head': m[n]['head'], 'police_head': p[n]['head']})
for r in rows:
    if 'status' in r:
        print('%-14s MISSING in_melee=%s in_police=%s' % (r['bone'], r['in_melee'], r['in_police']))
    else:
        print('%-14s y=%6.2f x=%6.2f z=%6.2f  len %.4f vs %.4f' % (
            r['bone'], r['y_angle_deg'], r['x_angle_deg'], r['z_angle_deg'], r['melee_len'], r['police_len']))
(P/'_scratch/security_zombie/rest_axis_compare.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding='utf-8')
print('REST_AXIS_COMPARE_OK')
