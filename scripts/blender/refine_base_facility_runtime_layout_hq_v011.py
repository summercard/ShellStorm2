#!/usr/bin/env python3
"""Final visual-density and reference-camera refinement for Base 99 v011."""

import importlib.util
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v011.blend"
VERIFY = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v011"

spec = importlib.util.spec_from_file_location("base_v011", PROJECT / "scripts/blender/build_base_facility_runtime_layout_hq_v011.py")
v011 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v011)
base = v011.base


def find_package(slug):
    root = bpy.data.collections["02_游戏输出_独立资产包_v011"]
    return next(c for c in v011.leaf_packages(root) if c.get("资产包键") == slug)


def setup():
    base.SOURCE = bpy.data.collections["01_制作组件_已统一材质"]
    base.SOURCE.hide_viewport = False
    base.SOURCE.hide_render = True
    base.OUTPUT = bpy.data.collections["02_游戏输出_独立资产包_v011"]
    base.MATS.clear()
    base.MATS.update({
        "metal": bpy.data.materials["01_精工金属_紫色骨架"],
        "matte": bpy.data.materials["02_细腻哑光_青绿大面"],
        "gloss": bpy.data.materials["03_清漆反光_紫粉点缀"],
        "emit": bpy.data.materials["04_柔和自发光_UI灯光"],
    })


def remove_prior_refine():
    for name in [o.name for o in bpy.data.objects if o.get("v011_refine")]:
        obj = bpy.data.objects.get(name)
        if obj:
            src = bpy.data.objects.get(name + "__源")
            bpy.data.objects.remove(obj, do_unlink=True)
            if src:
                bpy.data.objects.remove(src, do_unlink=True)


def mark(obj):
    obj["v011_scope"] = "loft_and_stair_high_fidelity"
    obj["v011_refine"] = True
    return obj


def box(*args, **kwargs):
    return mark(v011.box(*args, **kwargs))


def cyl(*args, **kwargs):
    return mark(v011.cyl(*args, **kwargs))


def beam(*args, **kwargs):
    return mark(v011.beam(*args, **kwargs))


def wall_and_railing_detail():
    coll = find_package("loft_lighting_support")
    # Warm strip directly below the second-floor front railing, as in the reference.
    for i, x in enumerate((-3.65, -.75, 2.15, 5.05, 7.95, 10.85)):
        strip = box(f"二楼前沿_暖橙连续灯带_{i+1:02d}_自发光", (x, 5.28, 6.24), (2.62, .055, .065), "emit", "orange", coll, .012)
        v011.pulse(strip, i * 3, .97, 1.025)
    # Reference wall service pipes: restrained, parallel and readable.
    decor = find_package("loft_wall_utility_decor")
    pipe_specs = ((8.78, "red"), (8.91, "green"), (9.04, "blue"))
    for idx, (z, color) in enumerate(pipe_specs):
        beam(f"二楼后墙_服务管线_{idx+1:02d}", (-4.3, 14.55, z), (8.85, 14.55, z), .035, "metal", color, decor)
        beam(f"二楼后墙_服务管线弯头_{idx+1:02d}", (8.85, 14.55, z), (9.05, 14.55, z - .20), .035, "metal", color, decor)
    for x in (-3.2, -.5, 2.2, 4.9, 7.6):
        box(f"二楼后墙_管线固定夹_{x}", (x, 14.525, 8.91), (.12, .055, .42), "metal", "dark_gray", decor, .018)
    # Small emergency junction box and cable drop visible near the west stair.
    box("二楼后墙_红色应急接线盒", (-4.35, 14.47, 8.20), (.34, .16, .34), "metal", "red", decor, .065)
    cyl("二楼后墙_应急盒状态灯_自发光", (-4.35, 14.36, 8.20), .055, .025, "emit", "orange", decor, 12, (math.pi / 2, 0, 0))
    beam("二楼后墙_应急盒垂直电缆", (-4.35, 14.48, 8.02), (-4.35, 14.48, 7.23), .035, "metal", "dark_gray", decor)


def strengthen_neon():
    coll = find_package("loft_good_vibes_neon")
    # Halo plate preserves the small pink neon focal point even at miniature scale.
    box("GOOD_VIBES_粉色内发光晕板_自发光", (10.55, 14.61, 8.47), (1.34, .022, .50), "emit", "magenta", coll, .06)
    box("GOOD_VIBES_黑色字缝遮罩", (10.55, 14.575, 8.47), (1.08, .018, .30), "matte", "dark_gray", coll, .035)
    good = v011.text_north("GOOD_VIBES_高亮GOOD_自发光", "GOOD", (10.55, 14.53, 8.61), .17, "emit", "light_gray", coll, .008)
    vibes = v011.text_north("GOOD_VIBES_高亮VIBES_自发光", "VIBES", (10.55, 14.53, 8.33), .17, "emit", "light_gray", coll, .008)
    mark(good); mark(vibes)
    light_data = bpy.data.lights.new("GOOD_VIBES_粉色霓虹洗墙光", "POINT")
    light_data.color = (1.0, .04, .34)
    light_data.energy = 70
    light_data.shadow_soft_size = 1.0
    light = bpy.data.objects.new("GOOD_VIBES_粉色霓虹洗墙光", light_data)
    coll.objects.link(light)
    light.location = (10.55, 13.95, 8.45)
    mark(light)


def add_minor_life_detail():
    coll = find_package("loft_coffee_table")
    # Two small stacked magazines with slight angular offset.
    box("茶几_杂志下册", (6.96, 9.48, 6.86), (.42, .30, .035), "matte", "blue", coll, .012, rot=(0, 0, -.08))
    box("茶几_杂志上册", (6.93, 9.47, 6.90), (.38, .27, .03), "matte", "orange", coll, .010, rot=(0, 0, .04))
    bed = find_package("loft_nightstand")
    sphere("床头柜_小植物叶团", (-2.37, 11.62, 7.42), .16, "matte", "green", bed)
    cyl("床头柜_小植物花盆", (-2.37, 11.62, 7.28), .10, .20, "matte", "purple", bed, 14)


def sphere(*args, **kwargs):
    return mark(v011.sphere(*args, **kwargs))


def update_cameras():
    ref = bpy.data.objects["基地二楼_参考图高还原验收相机_v011"]
    ref.location = (-27.0, -27.0, 20.5)
    target = Vector((-1.0, 9.3, 5.2))
    ref.rotation_euler = (target - ref.location).to_track_quat("-Z", "Y").to_euler()
    ref.data.ortho_scale = 30.6
    detail = bpy.data.objects["基地二楼_设施细节验收相机_v011"]
    detail.location = (-17.5, -15.0, 14.2)
    target = Vector((3.4, 10.8, 6.65))
    detail.rotation_euler = (target - detail.location).to_track_quat("-Z", "Y").to_euler()
    detail.data.ortho_scale = 21.8


def render(camera, path, x=1672, y=941):
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.filepath = str(path)
    scene.render.resolution_x = x
    scene.render.resolution_y = y
    scene.render.resolution_percentage = 100
    bpy.ops.render.render(write_still=True)


def main():
    setup()
    remove_prior_refine()
    wall_and_railing_detail()
    strengthen_neon()
    add_minor_life_detail()
    update_cameras()
    root = bpy.data.collections["02_游戏输出_独立资产包_v011"]
    doc = v011.write_catalog(root)
    base.SOURCE.hide_viewport = True
    base.SOURCE.hide_render = True
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    render(bpy.data.objects["基地二楼_参考图高还原验收相机_v011"], VERIFY / "base_facility_runtime_layout_hq_v011_reference_match.png")
    render(bpy.data.objects["基地二楼_设施细节验收相机_v011"], VERIFY / "base_facility_runtime_layout_hq_v011_loft_detail.png")
    render(bpy.data.objects["基地二楼_双楼梯接口验收相机_v011"], VERIFY / "base_facility_runtime_layout_hq_v011_stair_interfaces.png", 1600, 1000)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    report = {
        "status": "built_pending_manual_visual_review",
        "reference_truth": "codex-clipboard-07f86f50-f901-48fa-8940-fef41b91b478.png",
        "scope": "second floor facilities and stairs only",
        "locked_report": "base_facility_locked_scope_v010_v011.json",
        "locked_match": True,
        "package_count": doc["package_count"],
        "floor_tile_package_count": doc["floor_tile_package_count"],
        "visual_review_images": [
            "base_facility_runtime_layout_hq_v011_reference_match.png",
            "base_facility_runtime_layout_hq_v011_loft_detail.png",
            "base_facility_runtime_layout_hq_v011_stair_interfaces.png",
        ],
    }
    (VERIFY / "base_facility_v011_visual_acceptance.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"BASE_FACILITY_V011_REFINED packages={doc['package_count']}")


if __name__ == "__main__":
    main()
