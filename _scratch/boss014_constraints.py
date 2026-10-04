import bpy
bpy.ops.wm.open_mainfile(filepath='I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/bosses/enm_boss_monitor002/source/enm_boss_monitor002_animation_v014.blend')
r=bpy.data.objects['Boss002_Rig'];s=bpy.context.scene;s.frame_set(33)
for name in ['hand_ctrl.L','hand.L','arm_06.L']:
 p=r.pose.bones[name];print(name,'matrix',p.matrix.translation[:],'loc',p.location[:],'parent',p.parent.name,'constraints',[(c.name,c.type) for c in p.constraints])
 for c in p.constraints:
  for n in ['target','subtarget','use_location_x','use_location_y','use_location_z','head_tail','influence']:
   if hasattr(c,n):print(n,getattr(c,n))
