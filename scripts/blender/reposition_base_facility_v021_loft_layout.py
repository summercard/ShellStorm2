"""Apply the approved v021 loft layout-only adjustments in the Blender source.

This changes only the three selected asset-package output collections.  Mesh
topology, material assignments, UVs and the derived GLB exports are untouched.
Godot consumes matching package-root transforms rather than a new export.
"""

import bpy
from math import cos, pi, sin
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[2]
SOURCE = PROJECT / "source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v021.blend"

# Blender XY layout coordinates.  The bed's pillow vector rotates from -X to
# +Y (clockwise); the paired cabinet drawers rotate outward to the south rail.
ADJUSTMENTS = {
    "31__02_游戏输出_整合模型": {
        "label": "31_参考床架床品与床下收纳_资产包",
        "pivot": (0.300, 11.250), "target": (1.750, 11.550), "angle": -pi * 0.5,
    },
    "32__02_游戏输出_整合模型": {
        "label": "32_参考床头柜与生活物件_资产包",
        "pivot": (-3.235, 11.320), "target": (-3.700, 7.200), "angle": pi * 0.5,
    },
    "37__02_游戏输出_整合模型": {
        "label": "37_红棕茶几与生活物件_资产包",
        "pivot": (6.200, 9.380), "target": (3.600, 6.550), "angle": 0.0,
    },
}


def move_vertex(co, pivot, target, angle):
    dx, dy = co.x - pivot[0], co.y - pivot[1]
    co.x = target[0] + cos(angle) * dx - sin(angle) * dy
    co.y = target[1] + sin(angle) * dx + cos(angle) * dy


def apply_collection(collection, spec):
    for obj in collection.objects:
        if obj.type != "MESH":
            continue
        if obj.parent is not None or not obj.matrix_world.is_identity:
            raise RuntimeError(f"{obj.name} must be an unparented baked-layout mesh")
        for vertex in obj.data.vertices:
            move_vertex(vertex.co, spec["pivot"], spec["target"], spec["angle"])
        obj.data.update()
    collection["layout_revision"] = "v021_loft_layout_adjustment_001"
    collection["layout_pivot_xy_m"] = spec["pivot"]
    collection["layout_target_xy_m"] = spec["target"]
    collection["layout_rotation_z_rad"] = spec["angle"]


for name, spec in ADJUSTMENTS.items():
    collection = bpy.data.collections.get(name)
    if collection is None:
        raise RuntimeError(f"Missing selected output collection: {name}")
    apply_collection(collection, spec)
    print("LOFT_LAYOUT_APPLIED", spec["label"], spec["target"], round(spec["angle"], 6))

bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
print("BASE99_LOFT_LAYOUT_V021_SAVED")
