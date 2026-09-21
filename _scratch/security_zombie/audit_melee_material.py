import bpy, sys, os
_LOGFP = "I:/工作项目/shellstrom2/ShellStorm2/_scratch/security_zombie/audit_melee_material.log"
_logf = open(_LOGFP, "w", encoding="utf-8")
class _Tee:
    def write(self, s):
        _logf.write(s)
        try: sys.__stdout__.write(s)
        except Exception: pass
    def flush(self): _logf.flush()
sys.stdout = _Tee(); sys.stderr = _Tee()

PROJ = "I:/工作项目/shellstrom2/ShellStorm2"
MELEE = os.path.join(PROJ, "assets/art/enemies/normal_enemy_3d/melee_chaser/source/model/enm_melee_fungboar01_model_v002.blend")
bpy.ops.wm.open_mainfile(filepath=MELEE)

print("=== IMAGES ===")
for img in bpy.data.images:
    print("img: name=%r filepath=%r users=%d" % (img.name, img.filepath, img.users))
print("=== MATERIALS ===")
for m in bpy.data.materials:
    print("mat: name=%r users=%d" % (m.name, m.users))
    if m.node_tree:
        for n in m.node_tree.nodes:
            if n.type == "TEX_IMAGE":
                print("   TEX_IMAGE node: name=%r image=%r" % (n.name, n.image.name if n.image else None))
            if n.type == "BSDF_PRINCIPLED":
                print("   PRINCIPLED has inputs:", [i.name for i in n.inputs if i.links])
print("=== OBJECTS ===")
for o in bpy.data.objects:
    print("obj: name=%r type=%r" % (o.name, o.type))
print("=== ARMATURE BONE COUNT ===")
for o in bpy.data.objects:
    if o.type == "ARMATURE":
        print("armature %r bones=%d" % (o.name, len(o.data.bones)))
print("AUDIT_MELEE_MATERIAL_OK")
