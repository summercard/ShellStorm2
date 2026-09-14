"""白盒预览材质：按组件类型区分的低饱和占位材质，便于在视口与顶视图中读懂布局。"""

import bpy

PALETTE = {
    "WALL": ("SSLB_白盒_墙体", (0.52, 0.55, 0.60, 1.0)),
    "FLOOR": ("SSLB_白盒_地板", (0.26, 0.42, 0.55, 1.0)),
    "COLUMN": ("SSLB_白盒_结构柱", (0.66, 0.52, 0.34, 1.0)),
    "DOOR_OPENING": ("SSLB_白盒_门洞", (0.76, 0.44, 0.30, 1.0)),
    "STAIR": ("SSLB_白盒_楼梯", (0.40, 0.58, 0.43, 1.0)),
    "RAILING": ("SSLB_白盒_栏杆", (0.80, 0.72, 0.34, 1.0)),
    "FIXTURE": ("SSLB_白盒_设施", (0.54, 0.42, 0.64, 1.0)),
}
ANNOTATION_MATERIAL = "SSLB_标注_亮色"
GRID_MATERIAL = "SSLB_标注_网格"
DEFAULT_KEY = "WALL"
ROUGHNESS = 0.85


def ensure_material(component_type):
    name, color = PALETTE.get(component_type, PALETTE[DEFAULT_KEY])
    return _ensure_color_material(name, color)


def palette_names():
    """插件自带的占位材质名集合，用于区分用户自定义材质。"""
    return {name for name, _color in PALETTE.values()}


def ensure_annotation_material():
    return _ensure_color_material(ANNOTATION_MATERIAL, (0.93, 0.93, 0.90, 1.0))


def ensure_grid_material():
    return _ensure_color_material(GRID_MATERIAL, (0.30, 0.33, 0.38, 1.0))


def _ensure_color_material(name, color):
    material = bpy.data.materials.get(name)
    if material is None:
        material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.roughness = ROUGHNESS
    material.metallic = 0.0
    material.use_nodes = True
    tree = material.node_tree
    principled = tree.nodes.get("Principled BSDF") if tree else None
    if principled is not None:
        principled.inputs["Base Color"].default_value = color
        principled.inputs["Roughness"].default_value = ROUGHNESS
        metallic = principled.inputs.get("Metallic")
        if metallic is not None:
            metallic.default_value = 0.0
    return material


def apply_appearance(obj, component_type, palette=True, wireframe=True):
    """把白盒配色与线框描边应用到组件对象上。"""
    obj.show_wire = wireframe
    if obj.type != "MESH":
        return
    if not palette:
        drop_palette_materials(obj)
        return
    material = ensure_material(component_type)
    if obj.data.materials:
        obj.data.materials[0] = material
    else:
        obj.data.materials.append(material)


def drop_palette_materials(obj):
    """关闭白盒配色时只摘掉插件占位材质，保留用户自定义材质。"""
    names = palette_names()
    kept = [
        slot.material
        for slot in obj.material_slots
        if slot.material is not None and slot.material.name not in names
    ]
    if len(kept) == len(obj.material_slots):
        return
    obj.data.materials.clear()
    for material in kept:
        obj.data.materials.append(material)
