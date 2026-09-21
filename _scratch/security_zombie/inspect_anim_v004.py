import bpy, json
from pathlib import Path
P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
ANIM = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v004.blend'
bpy.ops.wm.open_mainfile(filepath=str(ANIM))
print('ACTIONS', [(a.name, a.use_fake_user, len(a.fcurves), [round(x) for x in a.frame_range]) for a in bpy.data.actions])
arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
print('ARM', arm.name, len(arm.data.bones))
for a in bpy.data.actions:
    if a.name == 'walking':
        print('walking fcurves', len(a.fcurves))
        if hasattr(a, 'slots'):
            print('walking slots', [(s.name_display if hasattr(s,"name_display") else s.name) for s in a.slots])
        if hasattr(a, 'layers'):
            for lay in a.layers:
                for st in lay.strips:
                    for cb in st.channelbags:
                        print('  channelbag fcurves', len(cb.fcurves))
