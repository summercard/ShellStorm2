import bpy,math
bpy.ops.wm.open_mainfile(filepath='I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/bosses/enm_boss_monitor002/source/enm_boss_monitor002_animation_v016.blend')
r=bpy.data.objects['Boss002_Rig'];s=bpy.context.scene
for f in range(19,50,2):
 s.frame_set(f);q=r.pose.bones['monitor_spin'].rotation_quaternion;print(f,r['heavy_spin_turns'],tuple(q),2*math.atan2(q.y,q.w))
