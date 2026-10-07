import bpy,json
from pathlib import Path
B=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/bosses/enm_boss_monitor002');P=B/'previews/expressions_v030';P.mkdir(exist_ok=True);r=bpy.data.objects['Boss002_Rig'];s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s
if bpy.context.screen.is_animation_playing:bpy.ops.screen.animation_cancel(restore_frame=False)
bpy.ops.wm.save_as_mainfile(filepath='I:/工作项目/shellstrom2/ShellStorm2/_scratch/boss030_before.blend',copy=True)
im=bpy.data.images.load(str(B/'source/textures_v030/expressions_atlas.png'),check_existing=False);im.name='BOSS002_Expressions_v030';im.pack()
for mat in bpy.data.materials:
 if mat.use_nodes:
  for node in mat.node_tree.nodes:
   if node.type=='TEX_IMAGE' and node.image and node.image.name=='expressions_atlas.png':node.image=im
for name in ['hurt','stun_enter','stun_loop','stun_exit']:
 a=bpy.data.actions[name]
 for fc in a.fcurves:
  if fc.data_path=='["expression_state"]':
   for k in fc.keyframe_points:
    f=k.co.x
    if name=='hurt':k.co.y=4 if f<11 else 0
    elif name=='stun_enter':k.co.y=4 if f<5 else 5
    elif name=='stun_loop':k.co.y=5
    else:k.co.y=5 if f<20 else 0
    k.interpolation='CONSTANT'
for sc in bpy.data.scenes:sc['asset_version']='v030'
r.animation_data.action=bpy.data.actions['stun_loop'];s.frame_start=1;s.frame_end=49;s.frame_set(25);bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v030.blend'))
(P/'binding.json').write_text(json.dumps({'version':'v030','atlas':'source/textures_v030/expressions_atlas.png','hurt':{'expression':4,'active_frames':[1,10]},'stun_enter':{'hit_expression':4,'dizzy_expression':5,'switch_frame':5},'stun_loop':5,'stun_exit':{'dizzy_expression':5,'restore_frame':20}},indent=2));print('V030 expression binding saved')
