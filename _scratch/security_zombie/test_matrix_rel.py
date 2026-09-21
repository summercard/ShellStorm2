import bpy, sys, os
from mathutils import Vector, Matrix, Quaternion
_LOGFP = "I:/工作项目/shellstrom2/ShellStorm2/_scratch/security_zombie/test_matrix_rel.log"
_logf = open(_LOGFP, "w", encoding="utf-8")
class _Tee:
    def write(self, s):
        _logf.write(s)
        try: sys.__stdout__.write(s)
        except Exception: pass
    def flush(self): _logf.flush()
sys.stdout = _Tee(); sys.stderr = _Tee()

PROJ = "I:/工作项目/shellstrom2/ShellStorm2"
MDL = os.path.join(PROJ, "assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v001.blend")
bpy.ops.wm.open_mainfile(filepath=MDL)
arm = [o for o in bpy.data.objects if o.type=='ARMATURE'][0]
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='POSE')
arm.data.pose_position = 'POSE'
for pb in arm.pose.bones: pb.matrix_basis.identity()

bn = "L_Upperarm"
b = arm.data.bones[bn]
ml = (arm.matrix_world @ b.matrix_local)
print("bone.matrix_local (world rest):")
print("  translation=", tuple(round(c,4) for c in ml.translation))
print("  head_local=", tuple(round(c,4) for c in b.head_local))
print("  tail_local=", tuple(round(c,4) for c in b.tail_local))
print("  matrix_local @ head_local =", tuple(round(c,4) for c in (ml @ b.head_local)))
print("  matrix_local @ tail_local =", tuple(round(c,4) for c in (ml @ b.tail_local)))

# rest pose.matrix
pb = arm.pose.bones[bn]
bpy.context.view_layer.update()
print("rest pose.matrix translation =", tuple(round(c,4) for c in pb.matrix.translation))

# set a 90deg rotation about Z and read
q = Quaternion((0,0,1), 1.5707963)
pb.rotation_mode = 'QUATERNION'
pb.rotation_quaternion = q
bpy.context.view_layer.update()
pm = pb.matrix
print("after 90deg Z rot, pose.matrix translation =", tuple(round(c,4) for c in pm.translation))
print("after 90deg Z rot, pose.matrix col1 (Y) =", tuple(round(c,4) for c in pm.col[1]))
print("bone.matrix_local @ q-as-matrix translation =", tuple(round(c,4) for c in (ml @ q.to_matrix().to_4x4()).translation))
print("bone.matrix_local @ q-as-matrix col1 (Y) =", tuple(round(c,4) for c in (ml @ q.to_matrix().to_4x4()).col[1]))
print("TEST_DONE")
