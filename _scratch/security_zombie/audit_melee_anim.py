import bpy, sys, os
_LOGFP = "I:/工作项目/shellstrom2/ShellStorm2/_scratch/security_zombie/audit_melee_anim.log"
_logf = open(_LOGFP, "w", encoding="utf-8")
class _Tee:
    def write(self, s):
        _logf.write(s)
        try: sys.__stdout__.write(s)
        except Exception: pass
    def flush(self): _logf.flush()
sys.stdout = _Tee(); sys.stderr = _Tee()

PROJ = "I:/工作项目/shellstrom2/ShellStorm2"
MELEE_ANIM = os.path.join(PROJ, "assets/art/enemies/normal_enemy_3d/melee_chaser/source/animation/enm_melee_fungboar01_animation_v003.blend")
bpy.ops.wm.open_mainfile(filepath=MELEE_ANIM)

print("=== OBJECTS ===")
for o in bpy.data.objects:
    print("obj: name=%r type=%r parent=%r" % (o.name, o.type, o.parent.name if o.parent else None))
print("=== ARMATURES (data) ===")
for ad in bpy.data.armatures:
    print("armature data: name=%r bones=%d skeleton_id=%r" % (ad.name, len(ad.bones), ad.get("skeleton_id")))
print("=== ACTIONS ===")
for a in bpy.data.actions:
    f0 = int(a.frame_range[0]); f1 = int(a.frame_range[1])
    print("action: name=%r frames=[%d..%d] nkeys=%d" % (a.name, f0, f1, len(a.fcurves)))
print("=== ACTION NLA? ===")
for o in bpy.data.objects:
    if o.animation_data:
        print("obj %r has animation_data action=%r nla_tracks=%d" % (
            o.name, o.animation_data.action.name if o.animation_data.action else None,
            len(o.animation_data.nla_tracks)))
print("AUDIT_MELEE_ANIM_OK")
