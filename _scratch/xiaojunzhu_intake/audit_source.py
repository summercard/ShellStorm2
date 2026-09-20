"""审计 Tripo 交付的小菌猪模型：对象、包围盒、尺寸、材质、贴图、朝向。

只读，不修改任何文件。
运行：
  blender.exe --background "<blend>" --python-exit-code 1 --python this.py
"""

import sys
from pathlib import Path

import bpy
from mathutils import Vector


def vec(v):
    return "(" + ", ".join(f"{c:+.4f}" for c in v) + ")"


def report_bounds(label, objects):
    mins = Vector((1e18, 1e18, 1e18))
    maxs = Vector((-1e18, -1e18, -1e18))
    found = False
    for obj in objects:
        if obj.type != "MESH":
            continue
        found = True
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            for i in range(3):
                mins[i] = min(mins[i], world[i])
                maxs[i] = max(maxs[i], world[i])
    if not found:
        print(f"{label}: <no mesh>")
        return None, None
    size = maxs - mins
    print(f"{label}:")
    print(f"    min  = {vec(mins)}")
    print(f"    max  = {vec(maxs)}")
    print(f"    size = {vec(size)}   (X={size.x:.4f}m  Y={size.y:.4f}m  Z={size.z:.4f}m)")
    return mins, maxs


print("=" * 72)
print("AUDIT: xiaojunzhu source model")
print("=" * 72)

scene = bpy.context.scene
unit = scene.unit_settings
print(f"\n[SCENE]")
print(f"  unit system      = {unit.system}")
print(f"  scale_length     = {unit.scale_length}")
print(f"  frame_current    = {scene.frame_current}")

print(f"\n[COLLECTIONS]")
for coll in bpy.data.collections:
    print(f"  {coll.name}: {len(coll.objects)} objects")

print(f"\n[OBJECTS]  total={len(bpy.data.objects)}")
for obj in sorted(bpy.data.objects, key=lambda o: o.name):
    parent = obj.parent.name if obj.parent else "-"
    print(f"  [{obj.type:10s}] {obj.name!r}")
    print(f"        parent={parent!r}  loc={vec(obj.location)}  rot_euler={vec(obj.rotation_euler)}  scale={vec(obj.scale)}")
    if obj.type == "MESH":
        mesh = obj.data
        print(f"        verts={len(mesh.vertices)}  polys={len(mesh.polygons)}  materials={[m.name if m else None for m in mesh.materials]}")
        bb = obj.bound_box
        local_size = Vector((
            max(c[i] for c in bb) - min(c[i] for c in bb) for i in range(3)
        ))
        print(f"        local_bbox_size={vec(local_size)}  dims={vec(obj.dimensions)}")
        print(f"        uv_layers={[uv.name for uv in mesh.uv_layers]}  shape_keys={mesh.shape_keys is not None}")
        print(f"        vertex_groups={[g.name for g in obj.vertex_groups]}")
        mods = [(m.name, m.type) for m in obj.modifiers]
        if mods:
            print(f"        modifiers={mods}")

print(f"\n[ARMATURES]")
armatures = [o for o in bpy.data.objects if o.type == "ARMATURE"]
if not armatures:
    print("  <none — 静态网格，无骨骼>")
for arm in armatures:
    print(f"  {arm.name!r}: bones={len(arm.data.bones)}")
    for bone in arm.data.bones:
        print(f"      {bone.name!r}  parent={bone.parent.name if bone.parent else '-'}")

print(f"\n[MATERIALS]  total={len(bpy.data.materials)}")
for mat in bpy.data.materials:
    print(f"  {mat.name!r}  use_nodes={mat.use_nodes}  blend_method={getattr(mat, 'blend_method', '-')}")
    if not mat.use_nodes:
        continue
    for node in mat.node_tree.nodes:
        print(f"      node [{node.type}] {node.name!r}")
        if node.type == "TEX_IMAGE":
            img = node.image
            if img is None:
                print("          image=<None>")
                continue
            path = img.filepath
            resolved = bpy.path.abspath(path)
            exists = Path(resolved).is_file() if resolved else False
            print(f"          image={img.name!r}")
            print(f"          filepath={path!r}  (packed={img.packed_file is not None})")
            print(f"          resolved={resolved!r}  exists={exists}")
            print(f"          size={tuple(img.size)}  colorspace={img.colorspace_settings.name!r}")
        if node.type == "BSDF_PRINCIPLED":
            for key in ("Base Color", "Metallic", "Roughness", "Alpha", "Emission Strength"):
                if key in node.inputs:
                    inp = node.inputs[key]
                    linked = inp.is_linked
                    try:
                        val = tuple(round(v, 4) for v in inp.default_value)
                    except TypeError:
                        val = round(inp.default_value, 4)
                    print(f"          {key}: linked={linked} default={val}")

print(f"\n[IMAGES]  total={len(bpy.data.images)}")
for img in bpy.data.images:
    print(f"  {img.name!r}  size={tuple(img.size)}  filepath={img.filepath!r}  packed={img.packed_file is not None}")

print(f"\n[BOUNDS]")
report_bounds("  all meshes (world)", list(bpy.data.objects))
print(f"\n  per-object:")
for obj in sorted(bpy.data.objects, key=lambda o: o.name):
    if obj.type == "MESH":
        report_bounds(f"    {obj.name!r}", [obj])

print("\n" + "=" * 72)
print("AUDIT END")
print("=" * 72)
