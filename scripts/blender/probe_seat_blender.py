import bpy
from mathutils import Vector

print('FILE', bpy.data.filepath)
for scene in bpy.data.scenes:
    if scene.get('preview_clip') == 'idle':
        rig = next(o for o in scene.objects if o.type == 'ARMATURE')
        print('SCENE', scene.name, 'RIG', rig.name, 'ACTION', rig.animation_data.action.name)
        print('BONES', [(b.name, b.parent.name if b.parent else None, tuple(round(v, 3) for v in b.head_local), tuple(round(v, 3) for v in b.tail_local)) for b in rig.data.bones if b.name in ['root','pelvis','waist','chest','head','thigh_l','shin_l','foot_l','thigh_r','shin_r','foot_r','upper_arm_l','forearm_l','hand_l','upper_arm_r','forearm_r','hand_r']])
        scene.frame_set(1)
        for name in ['root','pelvis','waist','chest','head','thigh_l','shin_l','foot_l','thigh_r','shin_r','foot_r','upper_arm_l','forearm_l','hand_l','upper_arm_r','forearm_r','hand_r']:
            bone = rig.pose.bones.get(name)
            if bone:
                print('POSE', name, 'loc', tuple(round(v,3) for v in bone.location), 'quat', tuple(round(v,3) for v in bone.rotation_quaternion), 'global', tuple(round(v,3) for v in bone.matrix.translation))
        break
