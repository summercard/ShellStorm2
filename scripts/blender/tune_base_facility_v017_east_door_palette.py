#!/usr/bin/env python3
"""Keep the canonical door silhouette while restoring base palette contrast."""
from pathlib import Path
import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must run with v017 open")

corners = {
    # Palette column 10, cool blue-grey: readable but not visually detached
    # from the dark east wall.
    "东墙标准滑升门_主体_金属哑光反光": ((0.92, 0.32), (0.98, 0.32), (0.98, 0.38), (0.92, 0.38)),
    # Top-row cyan for the compact UI/state strip.
    "东墙标准滑升门_状态灯_柔和自发光": ((0.32, 0.92), (0.38, 0.92), (0.38, 0.98), (0.32, 0.98)),
}
for base, points in corners.items():
    for name in (base, f"{base}__源"):
        obj = bpy.data.objects.get(name)
        if obj is None:
            raise RuntimeError(f"missing door mesh: {name}")
        layer = obj.data.uv_layers.get("PaletteUV")
        if layer is None:
            raise RuntimeError(f"missing PaletteUV: {name}")
        for poly in obj.data.polygons:
            for i, loop_index in enumerate(poly.loop_indices):
                layer.data[loop_index].uv = points[i % len(points)]
        obj.data.uv_layers.active = layer
        layer.active_render = True
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print("east door palette tuned")
