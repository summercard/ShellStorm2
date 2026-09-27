"""只读：打印每个输出网格对象的 material_index 直方图。"""

from __future__ import annotations

import sys
from collections import Counter

import bpy

paths = sys.argv[sys.argv.index("--") + 1 :]
for blend in paths:
    bpy.ops.wm.open_mainfile(filepath=blend)
    print("==== " + blend)
    for obj in bpy.data.objects:
        if obj.type != "MESH" or "_输出_" not in obj.name:
            continue
        slots = [
            (slot.material.name if slot.material else "<none>")
            for slot in obj.material_slots
        ]
        histogram = Counter(polygon.material_index for polygon in obj.data.polygons)
        print("  " + obj.name)
        for index, count in sorted(histogram.items()):
            name = slots[index] if index < len(slots) else "<out-of-range>"
            print("      slot%d %s faces=%d" % (index, name, count))
print("SLOTS_INSPECT_DONE")
