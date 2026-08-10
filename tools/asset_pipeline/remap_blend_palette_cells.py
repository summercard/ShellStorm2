import sys
from pathlib import Path

import bpy


def arguments_after_separator():
    if "--" not in sys.argv:
        raise RuntimeError("Expected arguments after --")
    return sys.argv[sys.argv.index("--") + 1 :]


def parse_mapping(values):
    result = {}
    for value in values:
        before, after = value.split(":", 1)
        result[tuple(map(int, before.split(",")))] = tuple(map(int, after.split(",")))
    return result


def palette_cell(uv):
    return min(9, max(0, int(uv.x * 10))), min(9, max(0, int(uv.y * 10)))


values = arguments_after_separator()
output_path = Path(values[0])
material_name = values[1]
mapping = parse_mapping(values[2:])
changed = 0

for obj in bpy.data.objects:
    if obj.type != "MESH":
        continue
    uv_layer = obj.data.uv_layers.get("PaletteUV") or obj.data.uv_layers.active
    if uv_layer is None:
        continue
    for polygon in obj.data.polygons:
        if polygon.material_index >= len(obj.material_slots):
            continue
        material = obj.material_slots[polygon.material_index].material
        if material is None or material.name != material_name or not polygon.loop_indices:
            continue
        average = sum(
            (uv_layer.data[index].uv for index in polygon.loop_indices),
            start=uv_layer.data[polygon.loop_indices[0]].uv.copy() * 0.0,
        ) / len(polygon.loop_indices)
        current = palette_cell(average)
        if current not in mapping:
            continue
        target = mapping[current]
        target_uv = ((target[0] + 0.5) / 10.0, (target[1] + 0.5) / 10.0)
        for index in polygon.loop_indices:
            uv_layer.data[index].uv = target_uv
            changed += 1

if changed == 0:
    raise RuntimeError("No matching PaletteUV loops were found")

bpy.context.scene["palette_revision"] = "dark_violet_metal_v002"
bpy.context.scene["palette_revision_note"] = "Warm large-area metal cells remapped to dark violet; emissive and PBR roles preserved"
output_path.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(output_path), compress=True)
print(f"REMAPPED_BLEND {changed} loops -> {output_path}")
