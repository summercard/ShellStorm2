import bpy
from pathlib import Path
from mathutils import Quaternion

root = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
source = root / 'art_source/characters/player/chr_player_capsule01_3d/variants/bunny01/production/v021/source/animation/chr_bunny01_animation_v021.blend'
target = root / 'art_source/characters/player/chr_player_capsule01_3d/variants/bunny01/production/v022/source/animation/chr_bunny01_animation_v022.blend'
backup = root / '_scratch/chr_bunny01_animation_v021_before_seat.blend'
assert Path(bpy.data.filepath).resolve() == source.resolve(), bpy.data.filepath
assert not target.exists(), 'v022 animation source already exists'
backup.parent.mkdir(parents=True, exist_ok=True)
target.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(backup), copy=True)

idle = next(s for s in bpy.data.scenes if s.get('preview_clip') == 'idle')
bpy.context.window.scene = idle
bpy.ops.scene.new(type='FULL_COPY')
scene = bpy.context.scene
scene.name = '13_座椅乘坐_滑行循环'
scene['preview_clip'] = 'seated'
scene['model_source'] = '../../../v021/source/model/chr_bunny01_model_v021.blend'
for library in bpy.data.libraries:
    if 'chr_bunny01_model' in library.filepath:
        library.filepath = '//../../../v021/source/model/chr_bunny01_model_v021.blend'
rig = next(o for o in scene.objects if o.type == 'ARMATURE')
assert rig.animation_data is not None
action = bpy.data.actions.new('anim_bunny01_seated_v022')
rig.animation_data.action = action
action.use_fake_user = True
action['state_id'] = 'seated'
action['duration'] = 1.2
action['loop'] = True
action.use_frame_range = True
action.frame_start = 1
action.frame_end = 73
action.use_cyclic = True
scene.frame_start = 1
scene.frame_end = 72
scene.frame_preview_end = 72

for frame, bob in [(1, 0.0), (19, 0.006), (37, 0.0), (55, -0.005), (73, 0.0)]:
    scene.frame_set(frame)
    for bone in rig.pose.bones:
        bone.rotation_mode = 'QUATERNION'
        bone.location = (0, 0, 0)
        bone.rotation_quaternion = Quaternion((1, 0, 0, 0))
        bone.scale = (1, 1, 1)
    # The whole seated pose is authored in the skeleton. The runtime clip maps
    # these bones to the existing modular body, shoes, hands and ears.
    rig.pose.bones['waist'].location = (0, 0, -0.07 + bob)
    rig.pose.bones['chest'].rotation_quaternion = Quaternion((1, 0, 0), -0.12)
    rig.pose.bones['head'].rotation_quaternion = Quaternion((1, 0, 0), 0.08)
    for side in ('l', 'r'):
        rig.pose.bones['thigh_' + side].rotation_quaternion = Quaternion((1, 0, 0), -1.08)
        rig.pose.bones['shin_' + side].rotation_quaternion = Quaternion((1, 0, 0), 0.88)
        foot = rig.pose.bones['foot_' + side]
        foot.location = (0, 0.14, -0.36)
        foot.rotation_quaternion = Quaternion((1, 0, 0), 0.18)
        arm = rig.pose.bones['upper_arm_' + side]
        arm.rotation_quaternion = Quaternion((1, 0, 0), -0.28)
        rig.pose.bones['forearm_' + side].rotation_quaternion = Quaternion((1, 0, 0), -0.42)
        rig.pose.bones['hand_' + side].rotation_quaternion = Quaternion((1, 0, 0), 0.12)
    for bone in rig.pose.bones:
        for prop in ('location', 'rotation_quaternion', 'scale'):
            bone.keyframe_insert(prop, frame=frame, group=bone.name)

for curve in action.fcurves:
    curve.extrapolation = 'CONSTANT'
    curve.modifiers.new('CYCLES')
    for key in curve.keyframe_points:
        key.interpolation = 'BEZIER'
        key.handle_left_type = 'AUTO_CLAMPED'
        key.handle_right_type = 'AUTO_CLAMPED'

scene.frame_set(1)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(target), relative_remap=False)
print('SEATED_SOURCE_SAVED', str(target), 'action', action.name, 'bones', len(rig.pose.bones))
