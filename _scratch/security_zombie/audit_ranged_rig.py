import bpy, sys, os
_LOGFP = "I:/工作项目/shellstrom2/ShellStorm2/_scratch/security_zombie/audit_ranged_rig.log"
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
ad = arm.data
print("armature %r skeleton_id=%r bones=%d" % (arm.name, ad.get("skeleton_id"), len(ad.bones)))

# switch to pose to read rest world matrices
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='POSE')
# rest pose basis
for pb in arm.pose.bones:
    pb.matrix_basis.identity()
bpy.context.view_layer.update()

def wp(bname):
    pb = arm.pose.bones[bname]
    m = arm.matrix_world @ pb.matrix
    return m

print("=== RIGHT-ARM CHAIN (L_* = character right) rest world ===")
for bname in ["L_Upperarm","L_Forearm","L_Hand","L_Thumb1","R_Upperarm","R_Forearm","R_Hand"]:
    if bname in arm.pose.bones:
        pb = arm.pose.bones[bname]
        head = arm.matrix_world @ pb.matrix @ pb.matrix_basis  # not exact; use bone head
        # use bone head/tail in armature space
        b = ad.bones[bname]
        h = (arm.matrix_world @ b.matrix_local) @ b.head_local
        t = (arm.matrix_world @ b.matrix_local) @ b.tail_local
        print("%-12s parent=%-12s headW=(%.3f,%.3f,%.3f) tailW=(%.3f,%.3f,%.3f)" % (
            bname, b.parent.name if b.parent else '-',
            h.x,h.y,h.z, t.x,t.y,t.z))
print("=== all bone head world (to find right side) ===")
for b in ad.bones:
    bw = (arm.matrix_world @ b.matrix_local) @ b.head_local
    print("%-14s headW=(%.3f,%.3f,%.3f)" % (b.name, bw.x, bw.y, bw.z))
print("AUDIT_RANGED_RIG_OK")
