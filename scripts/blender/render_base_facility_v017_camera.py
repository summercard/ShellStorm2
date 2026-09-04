#!/usr/bin/env python3
"""Render one fixed v017 acceptance camera without modifying the Blend."""

from pathlib import Path
import sys
import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(args) != 2:
    raise RuntimeError("usage: -- <camera object name> <absolute output png>")
if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must run with v017 open")

camera = bpy.data.objects.get(args[0])
if camera is None or camera.type != "CAMERA":
    raise RuntimeError(f"missing camera: {args[0]}")
output = Path(args[1])
output.parent.mkdir(parents=True, exist_ok=True)
scene = bpy.context.scene
original_camera = scene.camera
original_path = scene.render.filepath
scene.camera = camera
scene.render.filepath = str(output)
bpy.ops.render.render(write_still=True)
scene.camera = original_camera
scene.render.filepath = original_path
print(output)
