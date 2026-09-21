"""Audit the desktop 保安僵尸 FBX: units, meshes, armature, bones, vertex groups,
materials, images, bounds, rest pose, embedded animations. Read-only on the FBX.
Run:
  blender.exe --background --python-exit-code 1 --python this.py
"""
import sys, io

_LOGFP = "I:/工作项目/shellstrom2/ShellStorm2/_scratch/audit_fbx_result.txt"
_logf = open(_LOGFP, "w", encoding="utf-8")
class _Tee:
    def write(self, s):
        _logf.write(s); sys.__stdout__.write(s)
    def flush(self):
        _logf.flush(); sys.__stdout__.flush()
sys.stdout = _Tee()

import bpy
from mathutils import Vector

FBX = r"C:/Users/zhuangmenghong/Desktop/保安僵尸/tripo_convert_4b763a81-adc3-4d88-95dc-f269024b8c4b.fbx"

def vec(v):
    return "(" + ", ".join(f"{c:+.4f}" for c in v) + ")"

print("=" * 72)
print("AUDIT FBX: 保安僵尸")
print("=" * 72)

# remove all existing
bpy.ops.wm.read_factory_settings(use_empty=True)
print("[IMPORT] %s" % FBX)
try:
    bpy.ops.import_scene.fbx(filepath=FBX)
except Exception as e:
    print("IMPORT ERROR: %r" % e)
    raise SystemExit(1)

scene = bpy.context.scene
unit = scene.unit_settings
print(f"\n[SCENE] unit={unit.system} scale_length={unit.scale_length} frames={scene.frame_start}-{scene.frame_end}")

print(f"\n[OBJECTS] total={len(bpy.data.objects)}")
for obj in sorted(bpy.data.objects, key=lambda o: o.name):
    parent = obj.parent.name if obj.parent else "-"
    print(f"  [{obj.type:10s}] {obj.name!r} parent={parent!r} loc={vec(obj.location)} scale={vec(obj.scale)}")
    if obj.type == "MESH":
        mesh = obj.data
        print(f"        verts={len(mesh.vertices)} polys={len(mesh.polygons)} mats={[m.name if m else None for m in mesh.materials]}")
        print(f"        vgroups={[g.name for g in obj.vertex_groups]}")
        print(f"        uv={[u.name for u in mesh.uv_layers]} shape_keys={mesh.shape_keys is not None}")
        mods = [(m.name, m.type) for m in obj.modifiers]
        if mods:
            print(f"        modifiers={mods}")

print(f"\n[ARMATURES] n={len([o for o in bpy.data.objects if o.type=='ARMATURE'])}")
for arm in [o for o in bpy.data.objects if o.type == "ARMATURE"]:
    print(f"  {arm.name!r}: bones={len(arm.data.bones)}")
    for bone in arm.data.bones:
        par = bone.parent.name if bone.parent else '-'
        print(f"      {bone.name!r} parent={par!r} head={vec(bone.head_local)} tail={vec(bone.tail_local)}")

print(f"\n[MATERIALS] n={len(bpy.data.materials)}")
for mat in bpy.data.materials:
    print(f"  {mat.name!r} use_nodes={mat.use_nodes}")
    if not mat.use_nodes:
        continue
    for node in mat.node_tree.nodes:
        if node.type == "TEX_IMAGE":
            img = node.image
            if img is None:
                print("      TEX_IMAGE image=None")
                continue
            print(f"      TEX_IMAGE {img.name!r} size={tuple(img.size)} packed={img.packed_file is not None} path={img.filepath!r}")

print(f"\n[IMAGES] n={len(bpy.data.images)}")
for img in bpy.data.images:
    print(f"  {img.name!r} size={tuple(img.size)} path={img.filepath!r} packed={img.packed_file is not None}")

print(f"\n[ACTIONS] n={len(bpy.data.actions)}")
for a in bpy.data.actions:
    print(f"  {a.name!r} fcurves={len(a.fcurves)}")

# bounds of all meshes in world
print(f"\n[BOUNDS]")
lo = Vector((1e18,)*3); hi = Vector((-1e18,)*3)
for obj in bpy.data.objects:
    if obj.type != "MESH":
        continue
    for corner in obj.bound_box:
        w = obj.matrix_world @ Vector(corner)
        for i in range(3):
            lo[i] = min(lo[i], w[i]); hi[i] = max(hi[i], w[i])
size = hi - lo
print(f"  min={vec(lo)}")
print(f"  max={vec(hi)}")
print(f"  size=(X={size.x:.4f}, Y={size.y:.4f}, Z={size.z:.4f})")
print(f"  height/display: if display mult 0.70 -> display Z={size.z*0.70:.4f}")

print("\n" + "=" * 72)
print("AUDIT FBX END")
print("=" * 72)
