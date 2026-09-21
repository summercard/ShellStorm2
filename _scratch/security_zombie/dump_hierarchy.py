import bpy
from pathlib import Path
P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
NEW = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v005.blend'
MELEE = P/'assets/art/enemies/normal_enemy_3d/melee_chaser/source/model/enm_melee_fungboar01_model_v002.blend'
for path, label in ((MELEE, 'MELEE'), (NEW, 'POLICE')):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
    print('==== %s  arm=%s  bones=%d ====' % (label, arm.name, len(arm.data.bones)))
    for b in arm.data.bones:
        if b.parent is None:
            chain = []
            cur = b
            while cur:
                chain.append(cur.name)
                cur = cur.children[0] if cur.children else None
            print('  ROOT:', b.name, '->', ' > '.join(chain))
            break
    for n in ('Root', 'Hip', 'Waist', 'Spine01', 'Spine02', 'Neck', 'Head'):
        b = arm.data.bones.get(n)
        if b is None:
            print('  %-8s MISSING' % n); continue
        print('  %-8s parent=%-10s head_local=%s' % (
            n, (b.parent.name if b.parent else None),
            [round(v, 4) for v in b.head_local]))
    # which bones have location keyframes in the melee/idle action
    print('  armature object scale=%s' % ([round(v, 5) for v in arm.scale]))
