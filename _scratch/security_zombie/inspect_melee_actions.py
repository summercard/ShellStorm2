import bpy, json
from pathlib import Path
P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
ANIM = P/'assets/art/enemies/normal_enemy_3d/melee_chaser/source/animation/enm_melee_fungboar01_animation_v003.blend'
bpy.ops.wm.open_mainfile(filepath=str(ANIM))
arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
print('ARM', arm.name, 'bones', len(arm.data.bones))
print('ARM matrix_world', [list(r) for r in arm.matrix_world])
out = {}
for a in bpy.data.actions:
    bones = {}
    for fc in a.fcurves:
        dp = fc.data_path
        if 'pose.bones["' not in dp:
            continue
        b = dp.split('"')[1]
        prop = dp.split('.')[-1]
        n = len(fc.keyframe_points)
        rng = [fc.keyframe_points[0].co[0], fc.keyframe_points[-1].co[0]] if n else None
        bones.setdefault(b, {})[prop] = {'keys': n, 'range': rng}
    out[a.name] = {'frame_range': list(a.frame_range), 'channels': bones}
    loc_bones = [b for b, c in bones.items() if 'location' in c]
    print('%-42s frames=%s bones=%d loc_bones=%s' % (a.name, [round(x) for x in a.frame_range], len(bones), loc_bones))
(P/'_scratch/security_zombie/melee_action_channels.json').write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding='utf-8')
print('MELEE_CHANNELS_OK', len(out))
