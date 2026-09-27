"""只读检视一个组件包 blend 的材质槽与输出对象口径。"""

from __future__ import annotations

import sys

import bpy

blend = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.open_mainfile(filepath=blend)

print("=== materials ===")
for material in bpy.data.materials:
    node = None
    for candidate in material.node_tree.nodes if material.use_nodes else []:
        if candidate.type == "BSDF_PRINCIPLED":
            node = candidate
            break
    metallic = float(node.inputs["Metallic"].default_value) if node else None
    rough = float(node.inputs["Roughness"].default_value) if node else None
    print(f"  {material.name}  metallic={metallic} rough={rough} users={material.users}")

print("=== mesh objects ===")
for obj in bpy.data.objects:
    if obj.type != "MESH":
        continue
    slots = [slot.material.name if slot.material else "<none>" for slot in obj.material_slots]
    output = "_输出_" in obj.name
    print(f"  {'OUT' if output else '   '} {obj.name}  faces={len(obj.data.polygons)} slots={slots}")

print("=== collections ===")
for collection in bpy.data.collections:
    print(f"  {collection.name}  objects={len(collection.objects)}")
print("INSPECT_DONE")
