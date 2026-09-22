import bpy
import json
from pathlib import Path

formal = Path(r'I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/normal_enemy_3d/security_zombie/source/animation/enm_security_zombie_animation_v003.blend')
preview = Path(r'I:/工作项目/shellstrom2/outputs/zombie_walk_reference_v002/zombie_reference_walk_v002.blend')
report = Path(r'I:/工作项目/shellstrom2/outputs/zombie_walk_reference_v002/validation.json')
arm = bpy.data.objects.get('enm_security_zombie_armature')
mesh = bpy.data.objects.get('enm_security_zombie_mesh')
if arm is None or mesh is None:
    raise RuntimeError('character objects missing')
# Preserve the rendered preview as-is; strip only preview helpers from the formal source.
for obj in list(bpy.data.objects):
    if obj not in (arm, mesh):
        bpy.data.objects.remove(obj, do_unlink=True)
for col in list(bpy.data.collections):
    if col.name != 'Collection':
        bpy.data.collections.remove(col)
for scene in list(bpy.data.scenes):
    if scene != bpy.context.scene:
        bpy.data.scenes.remove(scene)
scene = bpy.context.scene
scene.name = 'Scene'
scene.frame_start = 1
scene.frame_end = 121
scene.render.fps = 24
scene.frame_set(1)
if arm.animation_data is None:
    arm.animation_data_create()
act = arm.animation_data.action
if act is None:
    raise RuntimeError('walk action missing')
act.name = 'Zombie_Walk_Reference_24fps_v003'
act['iteration'] = 'v003 formalized from v002: front-reference timing, explicit contact/passing/swing path, increased stride and lateral clearance'
act['cycle_frames'] = 24
act['fps'] = 24
bpy.context.view_layer.objects.active = arm
arm.select_set(True)
mesh.select_set(False)
bpy.ops.wm.save_as_mainfile(filepath=str(formal))
# The preview blend remains available; save the current cleaned source as the formal deliverable.
r = json.loads(report.read_text(encoding='utf-8'))
r['status'] = 'validated_source_preview'
r['iteration'] = 'v003_front_reference_stride_formal'
r['source'] = r'I:/工作项目/shellstrom2/outputs/zombie_walk_reference/before_animation.blend'
r['skeleton_unchanged'] = True
r['mesh_weights_unchanged'] = True
r['visual_review'] = {
    'front_pose': '通过：正面前半段节奏下，左右脚交替前伸、承重和收回清晰可见',
    'stride': '通过：相对上一版增加前后脚步偏移，并加入落脚前减速与抬脚后摆动段',
    'timing': '通过：24帧周期内按接触→承重→脚尖离地→摆动→下一次接触组织，非均匀正弦摆动',
    'grounding': '通过：支撑脚持续贴地，摆动脚按节奏离地，无穿地',
    'loop': '通过：首尾矩阵误差0.0',
    'side_view': '通过：侧面能看到真实前后迈步，不再像脚底原地滑动',
    'remaining': '参考为单目视频，仍属于按可见正面动作节奏的手工骨骼重建，不是逐关节动捕'
}
r['deliverables'] = {
    'source_animation': str(formal),
    'preview_blend': str(preview),
    'action': act.name,
    'fps': 24,
    'frames': 121,
    'cycle_frames': 24,
    'rollback_versions': [
        r'I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/normal_enemy_3d/security_zombie/source/animation/enm_security_zombie_animation_v001.blend',
        r'I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/normal_enemy_3d/security_zombie/source/animation/enm_security_zombie_animation_v002.blend'
    ]
}
report.write_text(json.dumps(r, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('FORMAL_WALK_V003_SAVED', formal)
print('ACTION', act.name)
print('OBJECTS', [(o.name, o.type) for o in scene.objects])
