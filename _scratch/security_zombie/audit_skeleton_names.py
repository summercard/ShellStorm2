import bpy, json
from pathlib import Path
P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
MELEE = P/'assets/art/enemies/normal_enemy_3d/melee_chaser/source/model/enm_melee_fungboar01_model_v002.blend'
NEW = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v004.blend'
REPORT = P/'_scratch/security_zombie/skeleton_name_audit.json'

def dump(path):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
    mesh = next(o for o in bpy.context.scene.objects if o.type == 'MESH')
    return {
        'armature': arm.name,
        'skeleton_id': arm.data.get('skeleton_id'),
        'bones': [(b.name, b.parent.name if b.parent else None) for b in arm.data.bones],
        'groups': [g.name for g in mesh.vertex_groups],
    }

melee = dump(MELEE)
new = dump(NEW)
mn = [b[0] for b in melee['bones']]
nn = [b[0] for b in new['bones']]
nm = {b[0]: b[1] for b in new['bones']}
mm = {b[0]: b[1] for b in melee['bones']}

report = {
    'melee_bone_count': len(mn),
    'new_bone_count': len(nn),
    'count_equal': len(mn) == len(nn),
    'missing_in_new': [b for b in mn if b not in nm],
    'extra_in_new': [b for b in nn if b not in mm],
    'order_equal': mn == nn,
    'melee_only_order_sample': mn,
    'new_only_order_sample': nn,
    'parent_mismatch': [
        {'bone': b, 'melee_parent': mm[b], 'new_parent': nm[b]}
        for b in mn if b in nm and mm[b] != nm[b]
    ],
    'melee_groups': melee['groups'],
    'new_groups': new['groups'],
    'groups_missing_in_new': [g for g in melee['groups'] if g not in set(new['groups'])],
    'groups_extra_in_new': [g for g in new['groups'] if g not in set(melee['groups'])],
}
REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print('SKELETON_NAME_AUDIT', json.dumps(report, ensure_ascii=False))
