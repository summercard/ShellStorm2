import bpy
bpy.ops.wm.open_mainfile(filepath='I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/bosses/enm_boss_monitor002/source/enm_boss_monitor002_animation_v017.blend')
r=bpy.data.objects['Boss002_Rig'];s=bpy.context.scene
for f in [19,20,21,22,23,29,30,40,45,48,49]:
 s.frame_set(f);print(f,r['heavy_spin_turns'],bpy.data.objects['Dedicated rotor ribbon 00'].rotation_euler.y)
for fc in r.animation_data.action.fcurves:
 if 'heavy_spin_turns' in fc.data_path:print([tuple(k.co) for k in fc.keyframe_points][18:24])
