import sys, io

_LOGFP = "I:/工作项目/shellstrom2/ShellStorm2/_scratch/audit_blend_result.txt"
_logf = open(_LOGFP, "w", encoding="utf-8")
class _Tee:
    def write(self, s):
        _logf.write(s); sys.__stdout__.write(s)
    def flush(self):
        _logf.flush(); sys.__stdout__.flush()
sys.stdout = _Tee()

import bpy
from mathutils import Vector

def vec(v):
    return "(" + ", ".join(f"{c:+.4f}" for c in v) + ")"

TARGET = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else bpy.data.filepath
print("AUDIT BLEND:", bpy.data.filepath)

scene = bpy.context.scene
print("[SCENE] unit=%s scale_length=%s fps=%s frames=%s-%s" % (
    scene.unit_settings.system, scene.unit_settings.scale_length,
    scene.render.fps, scene.frame_start, scene.frame_end))

# ---- meshes ----
print("\n[MESHES]")
for obj in [o for o in bpy.data.objects if o.type == "MESH"]:
    m = obj.data
    print("  %r verts=%d polys=%d vgroups=%d uv=%s" % (
        obj.name, len(m.vertices), len(m.polygons), len(obj.vertex_groups), [u.name for u in m.uv_layers]))
    # weight summary
    vgcount = len(obj.vertex_groups)
    unbound = 0
    for v in m.vertices:
        s = sum(g.weight for g in v.groups)
        if abs(s) < 1e-4:
            unbound += 1
    print("    unbound(zero-weight) verts = %d / %d" % (unbound, len(m.vertices)))

# ---- armatures / bones ----
print("\n[ARMATURES]")
for arm in [o for o in bpy.data.objects if o.type == "ARMATURE"]:
    ad = arm.data
    print("  %r bones=%d" % (arm.name, len(ad.bones)))
    print("  skeleton name (id): %r" % ad.get("skeleton_id", "NONE"))
    # rest pose bones
    for b in ad.bones:
        par = b.parent.name if b.parent else "-"
        print("    %-22s parent=%-22s head=%s tail=%s" % (b.name, par, vec(b.head_local), vec(b.tail_local)))

# ---- actions ----
print("\n[ACTIONS] n=%d" % len(bpy.data.actions))
for a in bpy.data.actions:
    fr = a.frame_range
    # bones with fcurves
    bones = set()
    for fc in a.fcurves:
        if fc.data_path.startswith("pose.bones["):
            bones.add(fc.data_path.split('"')[1])
    print("  %r range=[%.1f,%.1f] frames=%d fcurves=%d bones=%d" % (
        a.name, fr[0], fr[1], int(round(fr[1]-fr[0])), len(a.fcurves), len(bones)))

# ---- bounds (world) ----
print("\n[BOUNDS]")
lo = Vector((1e18,)*3); hi = Vector((-1e18,)*3)
for obj in bpy.data.objects:
    if obj.type != "MESH":
        continue
    for c in obj.bound_box:
        w = obj.matrix_world @ Vector(c)
        for i in range(3):
            lo[i] = min(lo[i], w[i]); hi[i] = max(hi[i], w[i])
sz = hi - lo
print("  min=%s max=%s size=(X=%.4f Y=%.4f Z=%.4f)" % (vec(lo), vec(hi), sz.x, sz.y, sz.z))

# ---- materials/images ----
print("\n[MATERIALS]")
for mat in bpy.data.materials:
    print("  %r use_nodes=%s" % (mat.name, mat.use_nodes))
    if mat.use_nodes:
        for n in mat.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image:
                print("    TEX %r size=%s packed=%s path=%s" % (n.image.name, tuple(n.image.size), n.image.packed_file is not None, n.image.filepath))
print("AUDIT END")
