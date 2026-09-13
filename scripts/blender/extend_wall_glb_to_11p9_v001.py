"""Create a versioned 11.9 m wall GLB while preserving the 2.5 m door zone."""

import argparse
from pathlib import Path

import bpy
from mathutils import Vector


parser = argparse.ArgumentParser()
parser.add_argument("--input", required=True)
parser.add_argument("--output", required=True)
parser.add_argument("--source-blend", required=True)
parser.add_argument("--asset-id", required=True)
parser.add_argument("--asset-version", required=True)
args = parser.parse_args(__import__("sys").argv[__import__("sys").argv.index("--") + 1 :])

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(Path(args.input).resolve()))
meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
if not meshes:
    raise RuntimeError("Imported GLB contains no meshes")

points = [obj.matrix_world @ vertex.co for obj in meshes for vertex in obj.data.vertices]
raw_bottom = min(point.z for point in points)
top = max(point.z for point in points)
# An opened door leaf may rotate a few centimetres below the wall baseline.
# The modular wall origin remains the authoritative Z=0 floor interface.
bottom = 0.0 if -0.5 < raw_bottom < 0.5 else raw_bottom
door_ceiling = bottom + 2.5
target_top = bottom + 11.9
if top <= door_ceiling:
    raise RuntimeError(f"Unexpected wall bounds {bottom}..{top}")

for obj in meshes:
    inverse = obj.matrix_world.inverted()
    obj.data = obj.data.copy()
    for vertex in obj.data.vertices:
        point = obj.matrix_world @ vertex.co
        if point.z > door_ceiling:
            ratio = (point.z - door_ceiling) / (top - door_ceiling)
            point.z = door_ceiling + ratio * (target_top - door_ceiling)
            vertex.co = inverse @ point
    obj.data.update()

# Preserve the base door-wall's existing in-game dark-metal response. The
# shared palette is rebound by Godot's post-import hook; these scalar values
# keep direct sun from washing the frame to white after that binding.
if args.asset_id == "ENV-BASE99-WALL-DOOR-5X12":
    for material in bpy.data.materials:
        if material.name.startswith("01_精工金属"):
            material.metallic = 0.30
            material.roughness = 0.58
            material.diffuse_color = (0.18, 0.08, 0.20, 1.0)
            if material.use_nodes:
                for node in material.node_tree.nodes:
                    if node.type != "BSDF_PRINCIPLED":
                        continue
                    node.inputs["Metallic"].default_value = 0.30
                    node.inputs["Roughness"].default_value = 0.58
                    node.inputs["Base Color"].default_value = (0.18, 0.08, 0.20, 1.0)

roots = [obj for obj in bpy.context.scene.objects if obj.parent is None]
for root in roots:
    root["asset_id"] = args.asset_id
    root["asset_version"] = args.asset_version
    root["logical_height_m"] = 12.0
    root["visual_height_m"] = 11.9
    root["visual_top_clearance_m"] = 0.1

scene = bpy.context.scene
scene["asset_id"] = args.asset_id
scene["asset_version"] = args.asset_version
scene["derived_from_glb"] = str(Path(args.input).resolve())
scene["door_clear_height_preserved_m"] = 2.5
source_blend = Path(args.source_blend).resolve()
source_blend.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(source_blend))

bpy.ops.object.select_all(action="SELECT")
output = Path(args.output).resolve()
output.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=str(output), export_format="GLB", use_selection=True,
    export_apply=True, export_yup=True, export_extras=True,
    export_materials="EXPORT", export_image_format="NONE",
    export_cameras=False, export_lights=False, export_animations=False,
)
print(f"WALL_11P9_EXPORT_OK asset={args.asset_id} bounds={bottom:.3f}..{target_top:.3f} output={output}")
