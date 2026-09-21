"""直接把小僵尸动作套上新骨架的直观后果：手/脚会跑到错误位置（米）+ 渲染对比图。

两版都跑在同一套新骨架上（v005），所以手/脚世界位置可以直接相减 —— 差异只来自
"通道值是原封不动套用"还是"已按目标静止系重定向"。
"""
import bpy, json, math
from pathlib import Path
from mathutils import Vector

P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
MELEE_ANIM = P/'assets/art/enemies/normal_enemy_3d/melee_chaser/source/animation/enm_melee_fungboar01_animation_v003.blend'
POLICE_MODEL = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v005.blend'
POLICE_ANIM = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v005.blend'
MELEE_ACT = 'anim_melee_fungboar01_idle_v002'
TRACK = ['R_Hand', 'L_Hand', 'R_Foot', 'L_Foot', 'Head']
OUT = P/'_scratch/security_zombie/direct_vs_retarget'
OUT.mkdir(parents=True, exist_ok=True)
res = {}


def tips(arm, start, count, frames):
    return [frames[i] for i in range(count)]


def collect(arm, act, start, count):
    sc = bpy.context.scene
    rows = []
    for f in range(start, start + count):
        sc.frame_set(f); bpy.context.view_layer.update()
        rows.append({n: arm.pose.bones[n].matrix.to_translation().copy() for n in TRACK})
    return rows


# ---- A. 直接套用 ----
bpy.ops.wm.open_mainfile(filepath=str(POLICE_MODEL))
sc = bpy.context.scene
arm = next(o for o in sc.objects if o.type == 'ARMATURE')
with bpy.data.libraries.load(str(MELEE_ANIM), link=False) as (src, dst):
    dst.actions = [MELEE_ACT]
dact = next(a for a in dst.actions if a is not None)
arm.animation_data_create(); arm.animation_data.action = dact
if hasattr(arm.animation_data, 'action_slot') and hasattr(dact, 'slots') and len(dact.slots):
    arm.animation_data.action_slot = dact.slots[0]
ds, de = int(dact.frame_range[0]), int(dact.frame_range[1])
N = de - ds + 1
direct = collect(arm, dact, ds, N)

# 渲染"直接套用"的一帧
sc.render.engine = 'BLENDER_WORKBENCH'
sh = sc.display.shading; sh.light = 'STUDIO'; sh.color_type = 'TEXTURE'; sh.show_shadows = True
sc.render.resolution_x = 420; sc.render.resolution_y = 560
cd = bpy.data.cameras.new('c'); cd.type = 'ORTHO'; cd.ortho_scale = 2.3
cam = bpy.data.objects.new('c', cd); sc.collection.objects.link(cam)
cam.location = Vector((0, 3.4, 1.05))
cam.rotation_euler = (Vector((0, 0, 0.95)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
sc.camera = cam
SHOT_FRAME = ds + 48
sc.frame_set(SHOT_FRAME); bpy.context.view_layer.update()
sc.render.filepath = str(OUT / 'A_direct_reuse.png')
bpy.ops.render.render(write_still=True)

# ---- B. 正确重定向 ----
bpy.ops.wm.open_mainfile(filepath=str(POLICE_ANIM))
sc = bpy.context.scene
arm2 = next(o for o in sc.objects if o.type == 'ARMATURE')
a2 = bpy.data.actions.get('idle')
arm2.animation_data_create(); arm2.animation_data.action = a2
if hasattr(arm2.animation_data, 'action_slot') and hasattr(a2, 'slots') and len(a2.slots):
    arm2.animation_data.action_slot = a2.slots[0]
fixed = collect(arm2, a2, int(a2.frame_range[0]), N)

sc.render.engine = 'BLENDER_WORKBENCH'
sh = sc.display.shading; sh.light = 'STUDIO'; sh.color_type = 'TEXTURE'; sh.show_shadows = True
sc.render.resolution_x = 420; sc.render.resolution_y = 560
cd = bpy.data.cameras.new('c'); cd.type = 'ORTHO'; cd.ortho_scale = 2.3
cam = bpy.data.objects.new('c', cd); sc.collection.objects.link(cam)
cam.location = Vector((0, 3.4, 1.05))
cam.rotation_euler = (Vector((0, 0, 0.95)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
sc.camera = cam
sc.frame_set(int(a2.frame_range[0]) + 48); bpy.context.view_layer.update()
sc.render.filepath = str(OUT / 'B_after_retarget.png')
bpy.ops.render.render(write_still=True)

# ---- 位置差（米）----
pos = {}
for n in TRACK:
    pos[n] = round(max((direct[i][n] - fixed[i][n]).length for i in range(N)), 4)
res['max_tip_position_err_m'] = pos
res['frames'] = N
res['worst_bone'] = max(pos, key=pos.get)
res['worst_m'] = pos[res['worst_bone']]
print('TIP_POSITION_ERR', json.dumps(res, ensure_ascii=False, indent=2))
(P/'_scratch/security_zombie/direct_vs_retarget.json').write_text(
    json.dumps(res, ensure_ascii=False, indent=2), encoding='utf-8')
print('DIRECT_VS_RETARGET_RENDERED', str(OUT))
