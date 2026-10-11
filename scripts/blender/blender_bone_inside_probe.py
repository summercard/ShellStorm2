# -*- coding: utf-8 -*-
"""步骤3e：骨骼摆位验收 —— ① 每根骨 head/tail 是否在网格内部（数值）
② 把骨骼画成薄盒几何叠加渲染（肉眼）。渲完删掉临时几何。
"""
import json
import os

import bpy
from mathutils import Vector

OUT = r"I:\工作项目\shellstrom2\_scratch\metarig_fit2"
os.makedirs(OUT, exist_ok=True)

rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
mesh = next(o for o in bpy.data.objects if o.type == "MESH")

# ---------- ① 内外判定 ----------
def inside(pt_world):
    ok, loc, nor, _ = mesh.closest_point_on_mesh(mesh.matrix_world.inverted() @ pt_world)
    if not ok:
        return None
    loc_w = mesh.matrix_world @ loc
    nor_w = (mesh.matrix_world.to_3x3() @ nor).normalized()
    return (pt_world - loc_w).dot(nor_w) < 0


checks = []
for b in rig.data.bones:
    checks.append({
        "name": b.name,
        "head_inside": inside(b.head_local),
        "tail_inside": inside(b.tail_local),
        "head": [round(v, 4) for v in b.head_local],
        "tail": [round(v, 4) for v in b.tail_local],
    })

# ---------- ② 骨骼可视化几何 ----------
verts, faces = [], []
R = 0.007
for b in rig.data.bones:
    h = b.head_local.copy(); t = b.tail_local.copy()
    d = (t - h)
    L = d.length
    if L < 1e-6:
        continue
    d.normalize()
    up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
    u = d.cross(up).normalized()
    v = d.cross(u).normalized()
    base = len(verts)
    for p, s in ((h, 0), (t, 0)):
        for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            verts.append(p + u * (R * su) + v * (R * sv))
    faces += [(base + 0, base + 1, base + 2, base + 3),
              (base + 4, base + 7, base + 6, base + 5),
              (base + 0, base + 4, base + 5, base + 1),
              (base + 1, base + 5, base + 6, base + 2),
              (base + 2, base + 6, base + 7, base + 3),
              (base + 3, base + 7, base + 4, base + 0)]

me = bpy.data.meshes.new("_bones_viz")
me.from_pydata([tuple(v) for v in verts], [], faces)
me.update()
viz = bpy.data.objects.new("_bones_viz", me)
bpy.context.scene.collection.objects.link(viz)

mat = bpy.data.materials.new("_bones_viz_mat")
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get("Principled BSDF")
if bsdf:
    bsdf.inputs["Base Color"].default_value = (1.0, 0.15, 0.05, 1.0)
    bsdf.inputs["Emission Color"].default_value = (1.0, 0.25, 0.05, 1.0)
    if "Emission Strength" in bsdf.inputs:
        bsdf.inputs["Emission Strength"].default_value = 2.0
me.materials.append(mat)

# ---------- 渲染 ----------
scene = bpy.context.scene
cs = [mesh.matrix_world @ Vector(c) for c in mesh.bound_box]
xs = [c.x for c in cs]; ys = [c.y for c in cs]; zs = [c.z for c in cs]
center = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (min(zs) + max(zs)) / 2)
size = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
D = max(size) * 2.4

tgt = bpy.data.objects.new("_t", None); tgt.location = center
scene.collection.objects.link(tgt)
cd = bpy.data.cameras.new("_c"); cd.lens = 50
cam = bpy.data.objects.new("_c", cd); scene.collection.objects.link(cam)
cam.constraints.new("TRACK_TO").target = tgt
scene.camera = cam

old = (scene.render.engine, scene.render.resolution_x, scene.render.resolution_percentage)
scene.render.engine = "BLENDER_WORKBENCH"
scene.render.resolution_x = scene.render.resolution_y = 700
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
try:
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "OBJECT"
    scene.display.shading.show_xray = True   # 透视：否则骨骼全被网格挡住看不见
    scene.display.shading.xray_alpha = 0.15
except Exception:
    pass
mesh.color = (0.55, 0.55, 0.58, 1.0)
viz.color = (1.0, 0.08, 0.03, 1.0)

made = {}
for name, loc in {
    "side_+X": (D, 0, center[2] + size[2] * 0.15),
    "quarter": (D * 0.8, -D * 0.8, center[2] + size[2] * 0.5),
}.items():
    cam.location = loc
    bpy.context.view_layer.update()
    fp = os.path.join(OUT, f"{name}.png")
    scene.render.filepath = fp
    bpy.ops.render.render(write_still=True)
    made[name] = os.path.exists(fp)

# 再来一组"只渲骨骼"，把骨架形状看清楚
mesh.hide_render = True
scene.display.shading.show_xray = False
for name, loc in {
    "bones_side": (D, 0, center[2] + size[2] * 0.15),
    "bones_quarter": (D * 0.8, -D * 0.8, center[2] + size[2] * 0.5),
}.items():
    cam.location = loc
    bpy.context.view_layer.update()
    fp = os.path.join(OUT, f"{name}.png")
    scene.render.filepath = fp
    bpy.ops.render.render(write_still=True)
    made[name] = os.path.exists(fp)
mesh.hide_render = False

scene.render.engine, scene.render.resolution_x, scene.render.resolution_percentage = old
scene.camera = None
bpy.data.objects.remove(cam, do_unlink=True)
bpy.data.objects.remove(tgt, do_unlink=True)
bpy.data.objects.remove(viz, do_unlink=True)
bpy.data.cameras.remove(cd)
bpy.data.meshes.remove(me)
bpy.data.materials.remove(mat)

bad = [c["name"] for c in checks if c["head_inside"] is False or c["tail_inside"] is False]
print(json.dumps({
    "inside_fail": bad,
    "inside_fail_count": len(bad),
    "checks": checks,
    "renders": made,
    "outdir": OUT,
    "objects_after": [o.name for o in bpy.data.objects],
}, ensure_ascii=False, indent=1))
