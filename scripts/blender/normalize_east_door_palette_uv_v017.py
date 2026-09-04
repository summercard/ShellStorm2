#!/usr/bin/env python3
"""Normalize only the v017 canonical east-door meshes to the shared palette UV contract."""
from __future__ import annotations

import json
from pathlib import Path

import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
REPORT = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017/east_door_supply_swap_acceptance.json"

if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must run with v017 open")

names = (
    "东墙标准滑升门_主体_金属哑光反光",
    "东墙标准滑升门_状态灯_柔和自发光",
    "东墙标准滑升门_主体_金属哑光反光__源",
    "东墙标准滑升门_状态灯_柔和自发光__源",
)
uv_corners = ((0.72, 0.72), (0.78, 0.72), (0.78, 0.78), (0.72, 0.78))
result = []
for name in names:
    obj = bpy.data.objects.get(name)
    if obj is None or obj.type != "MESH":
        raise RuntimeError(f"missing door mesh: {name}")
    mesh = obj.data
    while mesh.uv_layers:
        mesh.uv_layers.remove(mesh.uv_layers[0])
    layer = mesh.uv_layers.new(name="PaletteUV", do_init=False)
    for poly in mesh.polygons:
        for position, loop_index in enumerate(poly.loop_indices):
            layer.data[loop_index].uv = uv_corners[position % len(uv_corners)]
    mesh.uv_layers.active = layer
    layer.active_render = True
    result.append({"object": name, "polygons": len(mesh.polygons), "uv_layers": [u.name for u in mesh.uv_layers]})

report = json.loads(REPORT.read_text(encoding="utf-8"))
report["door"]["palette_uv"] = {
    "status": "pass",
    "uv_layer": "PaletteUV",
    "safe_cell": "row 8 / column 8 (0.72–0.78)",
    "objects": result,
}
REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print(json.dumps({"status": "pass", "objects": result}, ensure_ascii=False))
