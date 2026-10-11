import bpy
bpy.ops.object.mode_set(mode='OBJECT') if bpy.context.object and bpy.context.object.mode != 'OBJECT' else None
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
print('cleared_current_unsaved_scene')
