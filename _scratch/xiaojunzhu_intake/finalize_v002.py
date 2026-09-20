import bpy,json,math,shutil,hashlib
from pathlib import Path
from mathutils import Vector,Quaternion
P=Path(__file__).parent;root=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/normal_enemy_3d/melee_chaser');out=root/'source/model/enm_melee_fungboar01_model_v002.blend';tex=root/'source/model/textures/enm_melee_fungboar01_basecolor_v002.png'
m=next(o for o in bpy.context.scene.objects if o.type=='MESH');a=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');bpy.context.preferences.filepaths.save_version=0
shutil.copy2(P/'basecolor_v002.png',tex);im=bpy.data.images.load(str(tex));im.colorspace_settings.name='sRGB';im.pack()
for mat in m.data.materials:
 for n in mat.node_tree.nodes:
  if n.type=='TEX_IMAGE':n.image=im;n.interpolation='Linear';n.extension='EXTEND'
 mat['texture_role']='BaseColor only; no fabricated normal map';mat['display_name']='小僵尸'
im.filepath='//textures/enm_melee_fungboar01_basecolor_v002.png'
# Store editable technical reference, not a gameplay animation.
t=bpy.data.texts.new('小僵尸_v002_制作说明');t.write('小僵尸 / ENM-MELEE-FUNGBOAR01\n源高1.857143m；运行倍率0.70，展示高1.30m。\n保留左右纹理差异；UVMap，2K sRGB BaseColor已嵌入。\n四指造型，每手四条两节指链。骨架已重建，旧动作不可直接复用。\n本文件为模型与绑定源，不含正式动作库，未接入Godot。\nFinger局部X旋转可试弯；默认静止姿势，不保存测试Pose。\n')
a['source_status']='model_only_pending_animation';a['height_locked']=True
for ob in [a,m]:ob.lock_scale=(True,True,True)
for screen in bpy.data.screens:
 for ar in screen.areas:
  if ar.type=='VIEW_3D':
   ar.spaces.active.shading.type='MATERIAL';ar.spaces.active.region_3d.view_distance=2.8;ar.spaces.active.region_3d.view_location=(0,0,.9)
bpy.ops.object.select_all(action='DESELECT');a.select_set(True);bpy.context.view_layer.objects.active=a
bpy.ops.wm.save_as_mainfile(filepath=str(out));print('FINAL_MODEL_SAVED',out)
