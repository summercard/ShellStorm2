"""地下街区 v001 —— 灯光/色彩管理调优（可在业主会话内直接跑）。

低亮多巴胺色盘底色极深，必须把环境光与主光抬上来，否则整片发黑。
这里只改灯光功率、世界环境与色彩管理，不动几何。
"""

from __future__ import annotations

import math

import bpy

# 目标 (名称, 类型, 位置, 功率, 颜色, 旋转, 尺寸)
NET = [
    ("补光_顶棚主光", "AREA", (0, 0, 26.6), 9000, (0.50, 0.64, 1.0), (0, 0, 0), 34.0),
    ("补光_顶棚副光A", "AREA", (-12, -12, 26.2), 5200, (0.48, 0.60, 1.0), (0, 0, 0), 22.0),
    ("补光_顶棚副光B", "AREA", (12, 8, 26.2), 5200, (0.48, 0.60, 1.0), (0, 0, 0), 22.0),
    ("补光_街口冷光", "AREA", (0, -22.0, 12.0), 4200, (0.38, 0.56, 1.0), (math.radians(64), 0, 0), 14.0),
    ("补光_横街冷光", "AREA", (-22.0, 0.0, 12.0), 3800, (0.38, 0.56, 1.0), (0, math.radians(-64), 0), 14.0),
    ("补光_街心补", "AREA", (0, 0, 14.0), 2200, (0.58, 0.68, 1.0), (0, 0, 0), 18.0),
    ("霓虹_酒店粉", "POINT", (-6.0, 2.4, 12.5), 1600, (1.0, 0.12, 0.30), (0, 0, 0), 0),
    ("霓虹_药店青", "POINT", (-8.0, -14.0, 5.0), 2800, (0.08, 0.95, 0.85), (0, 0, 0), 0),
    ("霓虹_酒吧红", "POINT", (8.2, 12.6, 9.4), 3200, (1.0, 0.16, 0.24), (0, 0, 0), 0),
    ("霓虹_高架橙", "POINT", (-1.0, 6.6, 12.2), 2400, (1.0, 0.58, 0.14), (0, 0, 0), 0),
    ("霓虹_巷尾紫", "POINT", (14.0, -12.0, 8.0), 2200, (0.60, 0.26, 1.0), (0, 0, 0), 0),
    ("街口射灯", "SPOT", (7.0, -15.0, 13.0), 6000, (0.70, 0.80, 1.0),
     (math.radians(56), 0, math.radians(-26)), 0),
    ("酒店门头暖光", "SPOT", (-7.8, 5.0, 3.8), 1600, (1.0, 0.52, 0.26),
     (math.radians(74), 0, math.radians(-90)), 0),
]

WORLD_STRENGTH = 0.30
WORLD_COLOR = (0.012, 0.016, 0.032)
EXPOSURE = 1.05


def main():
    scene = bpy.context.scene
    coll = bpy.data.collections.get("90_展示与动态_灯光相机")
    if coll is None:
        coll = bpy.data.collections.new("90_展示与动态_灯光相机")
        scene.collection.children.link(coll)

    wanted = {item[0] for item in NET}
    for obj in list(coll.objects):
        if obj.type == "LIGHT" and obj.name not in wanted:
            coll.objects.unlink(obj)
            bpy.data.objects.remove(obj, do_unlink=True)

    for name, kind, loc, energy, color, rot, size in NET:
        obj = bpy.data.objects.get(name)
        if obj is None:
            data = bpy.data.lights.new(name, kind)
            obj = bpy.data.objects.new(name, data)
            coll.objects.link(obj)
        data = obj.data
        obj.data.type = kind
        data.energy = energy
        data.color = color
        if kind == "AREA":
            data.shape = "SQUARE"
            data.size = size
        if kind == "SPOT":
            data.spot_size = math.radians(72)
            data.spot_blend = 0.5
            data.shadow_soft_size = 0.6
        obj.location = loc
        obj.rotation_euler = rot

    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (*WORLD_COLOR, 1.0)
        bg.inputs[1].default_value = WORLD_STRENGTH

    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = EXPOSURE
    print("LIGHTING_OK", len(coll.objects), "objects")


main()
