import bpy, sys, os
from mathutils import Vector
_LOGFP = "I:/工作项目/shellstrom2/ShellStorm2/_scratch/security_zombie/diag_ik.log"
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
print("pose_position =", arm.data.pose_position)
for pb in arm.pose.bones: pb.matrix_basis.identity()

hand_target = Vector((-0.18, 1.05, 1.18))
pole_target = Vector((-0.35, 0.45, 0.75))
tgt = bpy.data.objects.new("aim_target", None)
bpy.context.scene.collection.objects.link(tgt)
tgt.location = hand_target
pole = bpy.data.objects.new("aim_pole", None)
bpy.context.scene.collection.objects.link(pole)
pole.location = pole_target
print("tgt.location =", tuple(tgt.location))

hand = arm.pose.bones["L_Hand"]
ik = hand.constraints.new('IK')
ik.target = tgt
ik.chain_count = 2
ik.pole_target = pole
ik.pole_subtarget = pole.name
ik.pole_angle = 0.0
ik.use_tail = True
print("ik.target =", ik.target.name if ik.target else None)
print("ik.pole_target =", ik.pole_target.name if ik.pole_target else None)

def report(tag):
    # original pose bones
    hb = arm.pose.bones["L_Hand"]
    world = arm.matrix_world @ hb.matrix @ Vector((0, hb.length, 0))
    print("[%s] ORIG hand tip world = %s" % (tag, tuple(round(c,3) for c in world)))
    ub = arm.pose.bones["L_Upperarm"]
    q = ub.rotation_quaternion
    print("    ORIG L_Upperarm quat = (%.3f,%.3f,%.3f,%.3f)" % (q.w, q.x, q.y, q.z))
    # evaluated
    deps = bpy.context.evaluated_depsgraph_get()
    deps.update()
    ae = arm.evaluated_get(deps)
    heb = ae.pose.bones["L_Hand"]
    ew = arm.matrix_world @ heb.matrix @ Vector((0, heb.length, 0))
    print("    EVAL hand tip world = (%.3f,%.3f,%.3f)" % (ew.x, ew.y, ew.z))

bpy.context.view_layer.update()
report("after view_layer.update")
bpy.context.scene.frame_set(1)
report("after frame_set(1)")
# try nla/pose update operator if exists
try:
    bpy.ops.pose.ik_add()
    print("pose.ik_add OK")
except Exception as e:
    print("pose.ik_add not avail: %r" % e)
report("after pose.ik_add")

# Is there an update scene method?
print("has scene.update:", hasattr(bpy.context.scene, 'update'))
if hasattr(bpy.context.scene, 'update'):
    bpy.context.scene.update()
    report("after scene.update")

print("DIAG_DONE")
