import bpy, math, json
from pathlib import Path
from mathutils import Matrix, Vector
P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
MODEL = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v005.blend'
SRC_ANIM = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v003.blend'

bpy.ops.wm.open_mainfile(filepath=str(MODEL))
tgt = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
with bpy.data.libraries.load(str(SRC_ANIM), link=False) as (src, dst):
    dst.objects = ['enm_ranged_sporeshooter01_armature']
    dst.actions = ['attack']
sarm = next(o for o in dst.objects if o is not None)
bpy.context.scene.collection.objects.link(sarm)
act = next(a for a in dst.actions if a)
sarm.animation_data_create(); sarm.animation_data.action = act
if hasattr(act, 'slots') and len(act.slots):
    sarm.animation_data.action_slot = act.slots[0]

def yaxis(m):
    return Vector((m[0][1], m[1][1], m[2][1])).normalized()

def ang(u, v):
    d = max(-1.0, min(1.0, Vector(u).dot(Vector(v))))
    return round(math.degrees(math.acos(d)), 2)

# use the frame with the largest pose delta in the source
bpy.context.scene.frame_set(26)
bpy.context.view_layer.update()
print('target connect flags:')
for n in ('L_Upperarm', 'L_Forearm', 'L_Hand', 'R_Upperarm', 'L_Thigh', 'L_Calf', 'Hip', 'Waist', 'Spine02', 'Neck', 'Head'):
    b = tgt.data.bones.get(n)
    if b:
        print('  %-12s use_connect=%-5s inherit_rot=%-5s parent=%s' % (n, b.use_connect, b.use_inherit_rotation, b.parent.name if b.parent else None))

rows = []
for n in ('Head', 'Spine02', 'L_Upperarm', 'L_Forearm', 'L_Hand', 'R_Forearm', 'L_Thigh', 'L_Calf'):
    b = tgt.data.bones.get(n)
    if b is None:
        continue
    R_s = sarm.data.bones[n].matrix_local.to_3x3()
    R_t = tgt.data.bones[n].matrix_local.to_3x3()
    M_s = sarm.pose.bones[n].matrix.to_3x3()
    # candidate A: deformation transported into target rest frame
    D = M_s @ R_s.inverted()
    M_ideal = D @ R_t
    # candidate B: the formula used by the current bake
    M_mine = R_t @ R_s.inverted() @ M_s
    rows.append({'bone': n,
                 'src_y': [round(c, 4) for c in yaxis(M_s)],
                 'tgt_rest_y': [round(c, 4) for c in yaxis(R_t)],
                 'ideal_y': [round(c, 4) for c in yaxis(M_ideal)],
                 'mine_y': [round(c, 4) for c in yaxis(M_mine)],
                 'ideal_vs_src_deg': ang(yaxis(M_ideal), yaxis(M_s)),
                 'mine_vs_src_deg': ang(yaxis(M_mine), yaxis(M_s))})
for r in rows:
    print('%-12s ideal_vs_src=%6.2f  mine_vs_src=%6.2f' % (r['bone'], r['ideal_vs_src_deg'], r['mine_vs_src_deg']))
print('DEBUG_JSON', json.dumps(rows, ensure_ascii=False))
