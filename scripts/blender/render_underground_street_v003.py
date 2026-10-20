"""地下街区 v003（编号02 · 主体楼深化）—— 多机位渲染。

用法：
    blender --background <blend> --python render_underground_street_v003.py
"""

from __future__ import annotations

import os

import bpy
from mathutils import Vector

OUT = os.path.dirname(bpy.data.filepath)

HIDE_FOR_TOP = ("cavern_ceiling_slab", "ceiling_truss_rib", "tunnel_portal", "ceiling_duct_bundle",
                "hanging_lamp", "ceiling_exhaust_fan", "cavern_support_column", "cavern_wall_module",
                "sky_cable_span", "skybridge_truss", "skybridge_sign")


def _configure_glare(glare, threshold=0.82, size=7):
    """Blender 5.2 把 Glare 的模式/质量/阈值改成节点输入 socket（MENU/VALUE），
    5.1 及以前是 glare_type / quality 等 RNA 属性；两套都试，能设上就够。"""
    if hasattr(glare, "glare_type"):
        glare.glare_type = "FOG_GLOW"
        glare.quality = "HIGH"
        glare.threshold = threshold
        glare.size = size
        return
    for name, value in (("Type", "Fog Glow"), ("Quality", "High"),
                        ("Threshold", threshold), ("Size", size)):
        sock = glare.inputs.get(name)
        if sock is None:
            continue
        try:
            sock.default_value = value
        except (TypeError, ValueError):
            if name == "Type":
                try:
                    sock.default_value = "Bloom"
                except (TypeError, ValueError):
                    pass


def setup_compositor(scene):
    """霓虹辉光。Blender 5.x 的合成器改成了场景级节点组（scene.compositing_node_group），
    老的 scene.use_nodes / scene.node_tree 已移除，这里两套 API 都兼容。"""
    if hasattr(scene, "compositing_node_group"):
        ng = bpy.data.node_groups.new("COMP_地下街区_v002", "CompositorNodeTree")
        ng.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
        rl = ng.nodes.new("CompositorNodeRLayers")
        glare = ng.nodes.new("CompositorNodeGlare")
        out = ng.nodes.new("NodeGroupOutput")
        _configure_glare(glare)
        ng.links.new(rl.outputs["Image"], glare.inputs["Image"])
        ng.links.new(glare.outputs["Image"], out.inputs[0])
        scene.compositing_node_group = ng
        return
    scene.use_nodes = True
    nt = scene.node_tree
    nt.nodes.clear()
    rl = nt.nodes.new("CompositorNodeRLayers")
    glare = nt.nodes.new("CompositorNodeGlare")
    _configure_glare(glare)
    comp = nt.nodes.new("CompositorNodeComposite")
    nt.links.new(rl.outputs["Image"], glare.inputs["Image"])
    nt.links.new(glare.outputs["Image"], comp.inputs["Image"])


def set_cam(scene, name, loc, target, lens=34, ortho=None):
    cam = bpy.data.objects.get(name)
    if cam is None:
        data = bpy.data.cameras.new(name)
        cam = bpy.data.objects.new(name, data)
        scene.collection.objects.link(cam)
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
    for name in ("01_制作组件_按组件拆分_v002", "02_游戏输出_独立资产包_v002"):
        coll = bpy.data.collections.get(name)
        if coll is not None:
            coll.hide_render = True
    setup_compositor(scene)
    scene.view_settings.exposure = 1.15

    # 1) 主构图：南口西侧高处向北 —— 前景机房顶 + 沿街纵深 + 跨街桥
    set_cam(scene, "CAM_参考构图", (10.5, -23.0, 17.0), (-5.0, 2.0, 5.5), lens=22)
    render(scene, os.path.join(OUT, "render_ref_45deg_final.png"))

    # 2) 街道纵深（一点透视，验证窄谷两侧立面与招牌序列）
    set_cam(scene, "CAM_街道纵深", (2.2, -22.0, 5.4), (0.0, 20.0, 9.6), lens=28)
    render(scene, os.path.join(OUT, "render_street_axis_final.png"))

    # 3) 街角近景（酒店门头 / 藥字招牌 / 蒸汽 / 售货机）
    set_cam(scene, "CAM_街角近景", (5.6, -15.0, 4.2), (-6.5, -2.0, 6.0), lens=26)
    render(scene, os.path.join(OUT, "render_street_closeup_final.png"))

    # 4) 顶棚仰视（地下围护 / 桁架 / 风管）
    set_cam(scene, "CAM_顶棚仰视", (2.0, -14.0, 2.0), (0.5, 6.0, 26.0), lens=20)
    render(scene, os.path.join(OUT, "render_ceiling_vault_final.png"))

    # 5) 俯视正交（隐藏穹顶/桁架/隧道口/围护，看街网与摆位）
    hidden = []
    for obj in bpy.data.objects:
        if obj.type == "EMPTY" and any(obj.name.startswith("inst_" + s) for s in HIDE_FOR_TOP):
            hidden.append((obj, obj.hide_render))
            obj.hide_render = True
    set_cam(scene, "CAM_俯视正交", (0, 0, 80), (0, 0, 0), ortho=56)
    render(scene, os.path.join(OUT, "render_top_ortho_final.png"), 1400, 1400)
    for obj, prev in hidden:
        obj.hide_render = prev

    # 6) 围护剖面（贴内壁高处俯看整条街，验证穹顶/岩壁/跨街桥的层次）
    set_cam(scene, "CAM_围护外视", (-21.0, -21.0, 23.0), (4.0, 7.0, 5.0), lens=22)
    render(scene, os.path.join(OUT, "render_shell_overview_final.png"))

    # 7) 药店楼颗粒度专拍（v002 细化对象，保留为对照）
    #    加这三张的理由：远景主构图里药店只占 ~40% 画面高，看不到线脚与藥字；
    #    细化的验收必须有近景证据，不能只靠"主图看着还行"。
    detail = (
        ("detail_pharmacy_34", (-1.6, -18.4, 9.6), (-10.6, -9.0, 4.6), 32, 1.30),
        ("detail_pharmacy_face", (-2.2, -9.0, 5.2), (-10.6, -9.0, 4.6), 30, 1.28),
        ("detail_pharmacy_street", (2.4, -20.6, 4.2), (-10.6, -9.0, 4.6), 26, 1.24),
    )
    old_exp = scene.view_settings.exposure
    for (tag, loc, tgt, lens, exp) in detail:
        set_cam(scene, "CAM_" + tag, loc, tgt, lens=lens)
        scene.view_settings.exposure = exp
        render(scene, os.path.join(OUT, tag + "_final.png"), 1400, 960)
    scene.view_settings.exposure = old_exp

    # 8) v003 深化对象近景验收：酒店 / 酒吧 / 背景楼招牌与立面
    # 机位全部按「目标点投影到 NDC 落在 0.45~0.55」反算，不靠目测。
    # 上一版 detail_backdrop 的机位落在楼后，画面上半是墙下半全黑 —— 就是这个没验。
    detail2 = (
        ("detail_hotel_34", (1.0, -18.0, 13.0), (-12.0, 2.0, 11.0), 26, 1.22),
        ("detail_hotel_face", (2.0, 2.0, 12.0), (-11.0, 2.0, 12.0), 24, 1.26),
        # 屋顶**拍不到**：穹顶底 28.6m、酒店屋面 27.1m，中间只有 1.5m，任何平视镜位
        # 都被吊顶桁架挡死（实测整幅是桁架）。改成从街面仰视檐口与女儿墙。
        ("detail_hotel_upper", (1.5, 1.0, 2.2), (-11.0, 2.0, 23.0), 20, 1.20),
        # 酒吧：q2 机位（整栋入画）。上一版机位贴到 9m 内，整幅只有一片板墙。
        ("detail_bar_34", (-3.0, -17.0, 13.0), (12.0, -6.0, 12.0), 24, 1.24),
        ("detail_bar_face", (1.0, -2.0, 10.0), (11.8, -2.0, 10.0), 22, 1.26),
        # 背景楼：b1 机位（能看见 8×3 窄窗阵列 + 广告灯箱 + 叠涩檐口）
        ("detail_backdrop", (-0.5, 1.0, 16.0), (11.5, 8.0, 14.0), 20, 1.24),
        ("detail_street_paint", (0.5, -17.0, 3.2), (0.0, -4.0, 0.0), 22, 1.30),
    )
    for (tag, loc, tgt, lens, exp) in detail2:
        set_cam(scene, "CAM_" + tag, loc, tgt, lens=lens)
        scene.view_settings.exposure = exp
        render(scene, os.path.join(OUT, tag + "_final.png"), 1400, 900)
    scene.view_settings.exposure = old_exp


main()
