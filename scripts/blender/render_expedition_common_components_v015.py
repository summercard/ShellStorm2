"""远征关卡02 通用组件库 v015 · 验收图（资产墙）。

Run with:
    blender --background --python scripts/blender/render_expedition_common_components_v015.py

从**优化派生文件**（不是原始源）重新打开，把 5 件组件按网格摆开渲染一张总览图，
用于 02b 要求的「资产墙 / 实际场景验收图」。输出落在工作区外的过程目录，
确认后再由人工决定是否入库。
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
VERSION = "v015"
OPTIMIZED_BLEND = (
    ROOT / "art_source/environments/tower_zones/expedition/source/common_components"
    / VERSION / "export" / VERSION / f"expedition_common_components_source_{VERSION}_optimized.blend"
)
OUT_DIR = ROOT / "art_source/environments/tower_zones/expedition/source/common_components" / VERSION / "qa"
OUT_PNG = OUT_DIR / f"expedition_common_components_{VERSION}_验收图.png"

# 摆放：按组件尺寸给间距，门墙与坍塌洞排在一起方便看洞口
LAYOUT = [
    ("wall_standard_5m_h3", 0.0, 0.0),
    ("wall_door_5m_h3", 7.0, 0.0),
    ("ceiling_deck_5m", 14.0, 0.0),
    ("floor_base_5m", 21.0, 0.0),
    ("wall_collapse_5m_h12", 28.0, 0.0),
]


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.open_mainfile(filepath=str(OPTIMIZED_BLEND))

    scene = bpy.context.scene
    # 网格摆位，并把塌陷件整体抬到与其他件同底
    for slug, dx, dy in LAYOUT:
        obj = bpy.data.objects.get(f"{slug}_视觉")
        if obj is None:
            raise RuntimeError(f"优化文件里找不到 {slug}_视觉")
        obj.location = (dx, dy, 0.0)

    # 地面
    ground_mesh = bpy.data.meshes.new("验收地面_网格")
    ground_mesh.from_pydata(
        [(-6.0, -6.0, 0.0), (36.0, -6.0, 0.0), (36.0, 14.0, 0.0), (-6.0, 14.0, 0.0)],
        [],
        [(0, 1, 2, 3)],
    )
    ground_mesh.validate()
    ground_mesh.update()
    ground = bpy.data.objects.new("验收地面", ground_mesh)
    scene.collection.objects.link(ground)
    ground_mat = bpy.data.materials.new("验收地面_材质")
    ground_mat.use_nodes = True
    ground_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.16, 0.18, 0.22, 1.0)
    ground_mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.85
    ground.data.materials.append(ground_mat)

    # 相机：45° 斜俯视整排。方向必须由 (target − location) 算，
    # 直接拿目标点当「方向向量」会得出完全错误的取景（第一版就只拍到一根墙）。
    camera_data = bpy.data.cameras.new("验收相机")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 44.0
    camera = bpy.data.objects.new("验收相机", camera_data)
    scene.collection.objects.link(camera)
    focus = Vector((14.0, 0.0, 3.5))
    camera.location = focus + Vector((-6.0, -30.0, 20.0))
    camera.rotation_euler = (focus - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera

    # 灯光：主光 + 补光
    key = bpy.data.lights.new("验收主光", type="SUN")
    key.energy = 3.6
    key.angle = math.radians(7.0)
    key_obj = bpy.data.objects.new("验收主光", key)
    scene.collection.objects.link(key_obj)
    key_obj.rotation_euler = Vector((-0.55, 0.7, -0.6)).to_track_quat("-Z", "Y").to_euler()

    fill = bpy.data.lights.new("验收补光", type="SUN")
    fill.energy = 1.4
    fill_obj = bpy.data.objects.new("验收补光", fill)
    scene.collection.objects.link(fill_obj)
    fill_obj.rotation_euler = Vector((0.5, -0.75, -0.5)).to_track_quat("-Z", "Y").to_euler()

    scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in {
        item.identifier for item in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items
    } else "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 2000
    scene.render.resolution_y = 900
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 2.2
    scene.world = bpy.data.worlds.new("验收环境")
    scene.world.use_nodes = True
    background = next(n for n in scene.world.node_tree.nodes if n.bl_idname == "ShaderNodeBackground")
    background.inputs[0].default_value = (0.05, 0.07, 0.10, 1.0)
    background.inputs[1].default_value = 0.7

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(OUT_PNG)
    bpy.ops.render.render(write_still=True)
    print("EXPEDITION_COMMON_V015_QA_RENDER_OK %s" % OUT_PNG)


main()
