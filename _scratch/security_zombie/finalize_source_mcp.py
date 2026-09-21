import bpy
from pathlib import Path
asset = Path(r'I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/normal_enemy_3d/security_zombie/source/animation/enm_security_zombie_animation_v002.blend')
arm = bpy.data.objects.get('enm_security_zombie_armature')
mesh = bpy.data.objects.get('enm_security_zombie_mesh')
if arm is None or mesh is None:
    raise RuntimeError('character objects missing')
# Remove preview-only environment from the formal animation source.
for obj in list(bpy.data.objects):
    if obj not in (arm, mesh):
        bpy.data.objects.remove(obj, do_unlink=True)
for col in list(bpy.data.collections):
    if col.name != 'Collection':
        bpy.data.collections.remove(col)
for scene in list(bpy.data.scenes):
    if scene != bpy.context.scene:
        bpy.data.scenes.remove(scene)
bpy.context.scene.name = 'Scene'
bpy.context.scene.frame_start = 1
bpy.context.scene.frame_end = 121
bpy.context.scene.render.fps = 24
bpy.context.scene.frame_set(1)
arm.animation_data_create()
arm.animation_data.action = bpy.data.actions.get('Zombie_Walk_Reference_24fps_v001')
bpy.context.view_layer.objects.active = arm
arm.select_set(True)
mesh.select_set(False)
bpy.ops.wm.save_as_mainfile(filepath=str(asset))
print('FORMAL_ANIMATION_SOURCE_SAVED', asset)
print('OBJECTS', [(o.name, o.type) for o in bpy.context.scene.objects])
print('ACTION', arm.animation_data.action.name if arm.animation_data and arm.animation_data.action else None)
