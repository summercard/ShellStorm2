import bpy,json
from pathlib import Path
p=Path(r'I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/normal_enemy_3d/fat_zombie03')
bpy.ops.wm.open_mainfile(filepath=str(p/'source/animation/enm_normal_fat_zombie03_animation_v008.blend'));s=bpy.context.scene;m=next(o for o in s.objects if o.type=='MESH');mins=[]
for k in range(157):
 s.frame_set(k//2,subframe=k%2/2);ev=m.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=ev.to_mesh();mins.append(min(v.co.z for v in mesh.vertices)*.7);ev.to_mesh_clear()
print('MINIMUM',min(mins));(p/'previews/belly_v008/contact_check.json').write_text(json.dumps({'min_mesh_z_m':min(mins),'samples':157}),encoding='utf-8')
bpy.ops.wm.open_mainfile(filepath=str(p/'source/model/enm_normal_fat_zombie03_model_v003.blend'))
for action in list(bpy.data.actions):bpy.data.actions.remove(action)
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(p/'source/model/enm_normal_fat_zombie03_model_v003.blend'))
