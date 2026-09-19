"""Render door_5m source vs A-suite derived leaf from identical viewpoints.

Decides whether the world-downward face cull (983 faces / 4.2% of area) removes
anything the player can see, or only hidden undersides as it does for the A-suite
wall module.

Run:
    blender --background --factory-startup --python render_door_cull_compare.py -- <phase>
      phase = source | derived
"""

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

PROJECT = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
OUT = PROJECT / "_scratch"

SOURCE_BLEND = (
    PROJECT / "assets/art/environments/tower_zones/battle/source/common_components/v006"
    / "env_battle_common_components_source_v006.blend"
)
DERIVED_BLEND = (
    PROJECT / "assets/art/environments/tower_descent_3d/source/door_leaf_5m"
    / "env_tower_door_leaf_5m_source_v001.blend"
)

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["source"]
PHASE = argv[0]

bpy.ops.wm.open_mainfile(filepath=str(SOURCE_BLEND if PHASE == "source" else DERIVED_BLEND))

if PHASE == "source":
    root = bpy.data.objects["ROOT_door_5m_通用组件"]
    origin = root.matrix_world.translation.copy()
    # Hide everything that is not the door leaf so the render is unambiguous.
    keep = {"door_5m_门扇_输出", "door_5m_UI灯光_柔和自发光"}
    for obj in bpy.data.objects:
        if obj.name not in keep:
            obj.hide_render = True
else:
    origin = Vector((0.0, 0.0, 0.0))

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.render.resolution_x = 760
scene.render.resolution_y = 760
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "MATERIAL"
scene.display.shading.show_shadows = True
scene.display.shading.show_cavity = True
scene.display.shading.cavity_type = "BOTH"
scene.world = scene.world or bpy.data.worlds.new("W")
scene.world.color = (0.05, 0.05, 0.06)

cam_data = bpy.data.cameras.new("CmpCam")
cam = bpy.data.objects.new("CmpCam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

VIEWS = {
    # name: (eye offset from the bottom-centre origin, look-at offset)
    "front_three_quarter": (Vector((1.5, -3.4, 2.1)), Vector((0.0, 0.0, 1.25))),
    "low_underside": (Vector((0.9, -3.2, 0.22)), Vector((0.0, 0.0, 1.55))),
}

for name, (eye_off, look_off) in VIEWS.items():
    eye = origin + eye_off
    target = origin + look_off
    cam.location = eye
    direction = (target - eye).normalized()
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam_data.lens = 50.0
    scene.render.filepath = str(OUT / ("door_cull_%s_%s.png" % (PHASE, name)))
    bpy.ops.render.render(write_still=True)
    print("RENDERED %s" % scene.render.filepath)

print("RENDER_COMPARE_DONE phase=%s" % PHASE)
