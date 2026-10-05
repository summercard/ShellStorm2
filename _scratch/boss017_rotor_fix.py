import bpy,math
from pathlib import Path
R=Path.cwd();B=R/'assets/art/enemies/bosses/enm_boss_monitor002';p=B/'source/enm_boss_monitor002_animation_v017.blend';bpy.ops.wm.open_mainfile(filepath=str(p));r=bpy.data.objects['Boss002_Rig'];r['heavy_spin_turns']=float(r['heavy_spin_turns']);s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s
for fc in r.animation_data.action.fcurves:
 if 'heavy_spin_turns' in fc.data_path:fc.update_autoflags(r)
for f in range(1,98):
 s.frame_set(f)
 for j in range(6):
  ob=bpy.data.objects['Dedicated rotor ribbon %02d'%j];ob.rotation_euler=(0,float(r['heavy_spin_turns'])*math.tau+j*math.tau/3,0);ob.keyframe_insert('rotation_euler',frame=f)
s.frame_set(1);bpy.ops.wm.save_as_mainfile(filepath=str(p))
