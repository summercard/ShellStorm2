# -*- coding: utf-8 -*-
"""headless：给一个 .blend 渲侧面/正面两张图，判体型。用法：
blender --background X.blend --python _views_headless.py -- <outdir>
"""
import json
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv
tail = argv[argv.index("--") + 1:] if "--" in argv else []
outdir = tail[0] if tail else r"I:\工作项目\shellstrom2\_scratch\views_hl"
name_filter = tail[1] if len(tail) > 1 else ""
os.makedirs(outdir, exist_ok=True)

scene = bpy.context.scene
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
if name_filter:
    meshes = [o for o in meshes if name_filter in o.name]
# 取顶点最多的那个网格（主视觉网格）
mesh = max(meshes, key=lambda o: len(o.data.vertices)) if meshes else None
if mesh is None:
    print("NO_MESH")
    raise SystemExit(0)

corners = [mesh.matrix_world @ Vector(c) for c in mesh.bound_box]
xs = [c.x for c in corners]; ys = [c.y for c in corners]; zs = [c.z for c in corners]
center = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (min(zs) + max(zs)) / 2)
size = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
D = max(size) * 2.4

tgt = bpy.data.objects.new("_t", None)
tgt.location = center
scene.collection.objects.link(tgt)
cd = bpy.data.cameras.new("_c")
cd.lens = 50
cam = bpy.data.objects.new("_c", cd)
scene.collection.objects.link(cam)
con = cam.constraints.new("TRACK_TO")
con.target = tgt
scene.camera = cam

scene.render.engine = "BLENDER_WORKBENCH"
scene.render.resolution_x = scene.render.resolution_y = 560
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
try:
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
except Exception:
    pass

made = {}
views = {
    "side_+X": (D, 0, center[2] + size[2] * 0.2),
    "front_+Y": (0, D, center[2] + size[2] * 0.2),
}
for name, loc in views.items():
    cam.location = loc
    bpy.context.view_layer.update()
    fp = os.path.join(outdir, f"{name}.png")
    scene.render.filepath = fp
    bpy.ops.render.render(write_still=True)
    made[name] = os.path.exists(fp)

print("===VIEWS===")
print(json.dumps({
    "mesh": mesh.name,
    "dims": [round(v, 4) for v in size],
    "views": made,
    "outdir": outdir,
}, ensure_ascii=False))
print("===END===")
