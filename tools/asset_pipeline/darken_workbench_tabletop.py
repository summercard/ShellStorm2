"""Move the workshop's large matte teal faces to a darker existing palette cell."""

from pathlib import Path

import bpy


SOURCE = Path(
    r"C:\Users\zhuangmenghong\Documents\图片制作\新建文件夹\中文游戏资产成品\风格统一重制V3"
    r"\02_赛博维修工作台_风格统一源文件.blend"
)
FROM_CELL = (3, 4)
TO_CELL = (2, 4)


def polygon_material_name(obj: bpy.types.Object, material_index: int) -> str:
    if material_index >= len(obj.material_slots):
        return ""
    material = obj.material_slots[material_index].material
    return material.name if material else ""


def remap_mesh(obj: bpy.types.Object) -> int:
    uv_layer = obj.data.uv_layers.get("PaletteUV")
    if uv_layer is None:
        return 0
    changed = 0
    target = ((TO_CELL[0] + 0.5) / 10.0, (TO_CELL[1] + 0.5) / 10.0)
    for polygon in obj.data.polygons:
        if not polygon_material_name(obj, polygon.material_index).startswith("02_"):
            continue
        sample = uv_layer.data[polygon.loop_start].uv
        cell = (min(9, int(sample.x * 10)), min(9, int(sample.y * 10)))
        if cell != FROM_CELL:
            continue
        for loop_index in polygon.loop_indices:
            uv_layer.data[loop_index].uv = target
        changed += 1
    obj.data.update()
    return changed


if __name__ == "__main__":
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    changes = {obj.name: remap_mesh(obj) for obj in bpy.data.objects if obj.type == "MESH"}
    changes = {name: count for name, count in changes.items() if count}
    if not changes:
        raise RuntimeError("No workshop matte faces found in palette cell (3,4)")
    bpy.context.scene["工作台桌面色板调整"] = "哑光大面由色块(3,4)切换为深青绿色块(2,4)"
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE), compress=True)
    print(f"WORKBENCH_DARK_TEAL_REMAP {sum(changes.values())} faces: {changes}")
