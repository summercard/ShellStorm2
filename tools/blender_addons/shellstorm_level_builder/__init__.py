bl_info = {
    "name": "ShellStorm Level Builder",
    "author": "ShellStorm2",
    "version": (0, 2, 0),
    "blender": (4, 3, 0),
    "location": "3D View > Sidebar > ShellStorm",
    "description": "ShellStorm2 关卡组件库：底面中心锚点白盒、吸附对齐、预览统计与资产包清单",
    "category": "3D View",
}

import bpy

from . import operators, properties, ui


CLASSES = (*properties.CLASSES, *operators.CLASSES, *ui.CLASSES)


def register():
    for cls in CLASSES:
        bpy.utils.register_class(cls)
    properties.register_properties()


def unregister():
    properties.unregister_properties()
    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)


if __name__ == "__main__":
    register()
