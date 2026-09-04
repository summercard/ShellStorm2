#!/usr/bin/env python3
"""Print actual imported visual-door transforms for orientation verification."""
from pathlib import Path
import bpy
from mathutils import Vector

PROJECT = Path("/Users/summercards/ShellStorm2")
GLB = PROJECT / "assets/art/environments/base_facility_3d/components/env_base99_door_lift_2p2x2p5/env_base99_door_lift_2p2x2p5_visual_top3d_v001.glb"
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(GLB))
for obj in [o for o in bpy.data.objects if o not in before and o.type == "MESH"]:
    obj.rotation_mode = "XYZ"
    obj.rotation_euler = (0.0, 0.0, -1.57079632679)
    bpy.context.view_layer.update()
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = [min(v[i] for v in corners) for i in range(3)]
    hi = [max(v[i] for v in corners) for i in range(3)]
    print({"name": obj.name, "rotation": list(obj.rotation_euler), "dimensions": list(obj.dimensions), "bbox": [hi[i]-lo[i] for i in range(3)], "matrix": [list(row) for row in obj.matrix_world]})
