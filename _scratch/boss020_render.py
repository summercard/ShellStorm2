import bpy,json,hashlib,shutil
from pathlib import Path
R=Path.cwd();B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/heavy_v020';F=P/'frames';F.mkdir(exist_ok=True)
def snapshot():
 return hashlib.sha256(repr([(a.name,[(f.data_path,f.array_index,[tuple(k.co) for k in f.keyframe_points]) for f in a.fcurves]) for a in bpy.data.actions if a.name in ['idle','move','melee_keyboard','heavy_spin_slam']]).encode()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v019.blend'));old=snapshot()
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v020.blend'));assert old==snapshot()
for p in (B/'previews/heavy_v019/frames').glob('*.png'):shutil.copy2(p,F/p.name)
s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s;s.cycles.samples=8;s.render.resolution_x=800;s.render.resolution_y=660
for f in list(range(19,53))+list(range(65,86)):
 s.frame_set(f);s.render.filepath=str(F/('%04d.png'%(f-1)));bpy.ops.render.render(write_still=True)
