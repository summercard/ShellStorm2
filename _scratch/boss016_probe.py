import bpy
bpy.ops.wm.open_mainfile(filepath='I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/bosses/enm_boss_monitor002/source/enm_boss_monitor002_animation_v015.blend')
r=bpy.data.objects['Boss002_Rig']
for p in r.pose.bones:
 if any(x in p.name for x in ['support','monitor','face','rear','pedestal']):print(p.name,'parent',p.parent.name if p.parent else None,'head',tuple(p.bone.head_local),'tail',tuple(p.bone.tail_local),'constraints',[(c.type,c.name,getattr(c,'subtarget','')) for c in p.constraints])
