import bpy, sys, os, hashlib
_LOGFP = "I:/工作项目/shellstrom2/ShellStorm2/_scratch/security_zombie/verify_skeletons.log"
_logf = open(_LOGFP, "w", encoding="utf-8")
class _Tee:
    def write(self, s):
        _logf.write(s)
        try: sys.__stdout__.write(s)
        except Exception: pass
    def flush(self): _logf.flush()
sys.stdout = _Tee(); sys.stderr = _Tee()

PROJ = "I:/工作项目/shellstrom2/ShellStorm2"
MELEE_MDL = os.path.join(PROJ, "assets/art/enemies/normal_enemy_3d/melee_chaser/source/model/enm_melee_fungboar01_model_v002.blend")
MELEE_ANIM = os.path.join(PROJ, "assets/art/enemies/normal_enemy_3d/melee_chaser/source/animation/enm_melee_fungboar01_animation_v003.blend")
RANGED_MDL = os.path.join(PROJ, "assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v001.blend")

def skel_sig_path(blend, label):
    bpy.ops.wm.open_mainfile(filepath=blend)
    arm = None
    for o in bpy.data.objects:
        if o.type == "ARMATURE":
            arm = o; break
    assert arm is not None, "no armature in %s" % blend
    prev = bpy.context.object.mode if bpy.context.object else 'OBJECT'
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    eb = {e.name: e for e in arm.data.edit_bones}
    h = hashlib.sha256()
    h.update(("unit=%.4f|scale_length=%.4f|bones=%d" % (
        bpy.context.scene.unit_settings.scale_length, 1.0, len(arm.data.bones))).encode())
    for b in arm.data.bones:
        p = b.parent.name if b.parent else "-"
        e = eb[b.name]
        h.update(("%s|%s|" % (b.name, p)).encode())
        for c in b.head_local: h.update(("%.6f," % c).encode())
        for c in b.tail_local: h.update(("%.6f," % c).encode())
        h.update(("roll=%.6f|" % e.roll).encode())
    bpy.ops.object.mode_set(mode=prev if prev in ('OBJECT','POSE','EDIT') else 'OBJECT')
    sig = h.hexdigest()
    print("%-12s bones=%d skeleton_id=%r sig=%s" % (label, len(arm.data.bones), arm.data.get("skeleton_id"), sig))
    print("            arm_obj=%r mesh=%r" % (arm.name, [o.name for o in bpy.data.objects if o.type=='MESH']))
    return sig

s1 = skel_sig_path(MELEE_MDL, "melee_model")
s2 = skel_sig_path(MELEE_ANIM, "melee_anim")
s3 = skel_sig_path(RANGED_MDL, "ranged_model")

print("------------------------------------------------------------------")
print("melee_model == melee_anim : %s" % (s1 == s2))
print("melee_model == ranged_model : %s" % (s1 == s3))
print("melee_anim  == ranged_model : %s" % (s2 == s3))
print("VERIFY_SKELETONS_DONE")
