import bpy
from collections import defaultdict


GRID = 10


def palette_cell(uv):
    x = min(GRID - 1, max(0, int(uv.x * GRID)))
    y = min(GRID - 1, max(0, int(uv.y * GRID)))
    return x, y


print("FILE", bpy.data.filepath)
for obj in bpy.data.objects:
    if obj.type != "MESH":
        continue
    uv_layer = obj.data.uv_layers.get("PaletteUV") or obj.data.uv_layers.active
    if uv_layer is None:
        print("NO_UV", obj.name)
        continue
    usage = defaultdict(lambda: [0, 0.0])
    for polygon in obj.data.polygons:
        if not polygon.loop_indices:
            continue
        average_uv = sum(
            (uv_layer.data[index].uv for index in polygon.loop_indices),
            start=uv_layer.data[polygon.loop_indices[0]].uv.copy() * 0.0,
        ) / len(polygon.loop_indices)
        material_name = (
            obj.material_slots[polygon.material_index].material.name
            if polygon.material_index < len(obj.material_slots)
            and obj.material_slots[polygon.material_index].material
            else "<none>"
        )
        key = material_name, palette_cell(average_uv)
        usage[key][0] += 1
        usage[key][1] += polygon.area
    print("OBJECT", obj.name, "POLYGONS", len(obj.data.polygons))
    material_totals = defaultdict(float)
    for (material_name, _cell), (_count, area) in usage.items():
        material_totals[material_name] += area
    for material_name in sorted(material_totals):
        print(" MATERIAL", material_name, "AREA", round(material_totals[material_name], 4))
        rows = [
            (cell, count, area, area / material_totals[material_name])
            for (name, cell), (count, area) in usage.items()
            if name == material_name
        ]
        for cell, count, area, ratio in sorted(rows, key=lambda row: row[2], reverse=True)[:12]:
            print("  CELL", cell, "FACES", count, "AREA", round(area, 4), "RATIO", round(ratio, 4))
