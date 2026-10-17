"""地下街区 v001 —— 四机位渲染（参考三分之四 / 俯视正交 / 顶棚仰视 / 街角近景）。

用法（无头或在业主会话内均可）：
    blender --background <blend> --python render_underground_street_v001.py
"""

from __future__ import annotations

import math
import os

import bpy
from mathutils import Vector

VERSION_DIR = os.path.dirname(bpy.data.filepath)
OUT = VERSION_DIR

HIDE_FOR_TOP = ("cavern_ceiling_slab", "ceiling_truss_rib", "tunnel_portal", "ceiling_duct_bundle",
                "hanging_lamp", "ceiling_exhaust_fan", "cavern_support_column", "cavern_wall_module")


def setup_compositor(scene):
    scene.use_nodes = True
    nt = scene.node_tree
    nt.nodes.clear()
    rl = nt.nodes.new("CompositorNodeRLayers")
    glare = nt.nodes.new("CompositorNodeGlare")
    glare.glare_type = "FOG_GLOW"
    glare.quality = "HIGH"
    glare.threshold = 0.85
    glare.size = 7
    comp = nt.nodes.new("CompositorNodeComposite")
    nt.links.new(rl.outputs["Image"], glare.inputs["Image"])
    nt.links.new(glare.outputs["Image"], comp.inputs["Image"])


def set_cam(scene, name, loc, target, lens=34, ortho=None):
    cam = bpy.data.objects.get(name)
    if cam is None:
        data = bpy.data.cameras.new(name)
        cam = bpy.data.objects.new(name, data)
        bpy.context.scene.collection.objects.link(cam)
    cam.location = loc
    d = Vector(target) - Vector(loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    if ortho:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho
    else:
        cam.data.type = "PERSP"
        cam.data.lens = lens
    scene.camera = cam
    return cam


def render(scene, path, w=1600, h=900, samples=48):
    scene.render.resolution_x = w
    scene.render.resolution_y = h
    scene.render.resolution_percentage = 100
    scene.render.filepath = path
    scene.render.image_settings.file_format = "PNG"
    ee = getattr(scene, "eevee", None)
    if ee is not None and hasattr(ee, "taa_render_samples"):
        ee.taa_render_samples = samples
    bpy.ops.render.render(write_still=True)
    print("RENDERED", path)


def main():
    scene = bpy.context.scene
    # 渲染前强制隐藏制作源与输出包层：两者都堆在局部原点，显示会盖住实例布局
    for name in ("01_制作组件_按组件拆分_v001", "02_游戏输出_独立资产包_v001"):
        coll = bpy.data.collections.get(name)
        if coll is not None:
            coll.hide_render = True
    setup_compositor(scene)
    scene.view_settings.exposure = 1.05

    # 1) 参考三分之四（与参考图同风格：高处斜俯视街角，机位必须留在围护内部）
    set_cam(scene, "CAM_参考三分之四", (21.5, -24.0, 20.0), (-4.5, 3.5, 7.0), lens=32)
    render(scene, os.path.join(OUT, "render_ref_45deg_final.png"))

    # 2) 街角近景（酒店门头 / 药店霓虹）
    set_cam(scene, "CAM_街角近景", (3.2, -12.6, 3.4), (-9.4, 4.0, 5.4), lens=30)
    render(scene, os.path.join(OUT, "render_street_closeup_final.png"), 1600, 900)

    # 3) 顶棚仰视（验证地下围护与吊顶管线）
    set_cam(scene, "CAM_顶棚仰视", (2.0, -16.0, 2.4), (2.0, 6.0, 26.0), lens=22)
    render(scene, os.path.join(OUT, "render_ceiling_vault_final.png"), 1600, 900)

    # 4) 俯视正交（隐藏顶棚/桁架/隧道口，看街网与摆位）
    hidden = []
    for obj in bpy.data.objects:
        if obj.type == "EMPTY" and any(obj.name.startswith("inst_" + s) for s in HIDE_FOR_TOP):
            hidden.append((obj, obj.hide_render))
            obj.hide_render = True
    set_cam(scene, "CAM_俯视正交", (0, 0, 80), (0, 0, 0), ortho=56)
    render(scene, os.path.join(OUT, "render_top_ortho_final.png"), 1400, 1400)
    for obj, prev in hidden:
        obj.hide_render = prev

    # 5) 围护剖面（贴内壁高处俯看整个街区，验证穹顶/岩壁/桁架）
    set_cam(scene, "CAM_围护外视", (23.5, -23.5, 22.5), (-6.0, 6.0, 6.0), lens=26)
    render(scene, os.path.join(OUT, "render_shell_overview_final.png"), 1600, 900)


main()
