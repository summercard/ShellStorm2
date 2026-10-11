import bpy
bpy.data.objects['02_俯视结构'].data.ortho_scale=73
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath,compress=True)
