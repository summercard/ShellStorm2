import bpy, json
from pathlib import Path
from mathutils import Vector
P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
MELEE = P/'assets/art/enemies/normal_enemy_3d/melee_chaser/source/animation/enm_melee_fungboar01_animation_v003.blend'
NEW = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v005.blend'

def diag(path, label, probes):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    s = bpy.context.scene
    arms = [o for o in s.objects if o.type == 'ARMATURE']
    arm = arms[0]
    ad = arm.animation_data
    print('---', label, 'arm=', arm.name, 'armatures=', [a.name for a in arms])
    print('   animation_data=', ad is not None,
          '| action=', (ad.action.name if ad and ad.action else None),
          '| nla_tracks=', len(ad.nla_tracks) if ad else 0,
          '| has_action_slot=', hasattr(ad, 'action_slot') if ad else False)
    print('   all_actions=', [a.name for a in bpy.data.actions][:20])
    for probe, act_name in probes:
        arm.animation_data_create()
        act = bpy.data.actions.get(act_name)
        if act is None:
            print('   MISSING', act_name); continue
        arm.animation_data.action = act
        nslots = len(act.slots) if hasattr(act, 'slots') else -1
        if hasattr(arm.animation_data, 'action_slot') and nslots > 0:
            arm.animation_data.action_slot = act.slots[0]
        fr = act.frame_range
        print('   act=%s fcurves=%d slots=%s range=%s slot_now=%s' % (
            act_name, len(act.fcurves), nslots, (int(fr[0]), int(fr[1])),
            ('set' if getattr(arm.animation_data, 'action_slot', None) else None)))
        marks = []
        for f in (int(fr[0]), int(fr[0]) + (int(fr[1]) - int(fr[0])) // 2, int(fr[1])):
            s.frame_set(f)
            bpy.context.view_layer.update()
            pb = arm.pose.bones[probe]
            m = pb.matrix
            marks.append((f, [round(v, 4) for v in Vector((m[0][1], m[1][1], m[2][1])).normalized()]))
        print('     head_vec@frames:', marks)

diag(MELEE, 'MELEE', [('Head', 'anim_melee_fungboar01_idle_v002'), ('Head', 'anim_melee_fungboar01_attack_v003')])
diag(NEW, 'NEW', [('Head', 'idle'), ('Head', 'attack')])
