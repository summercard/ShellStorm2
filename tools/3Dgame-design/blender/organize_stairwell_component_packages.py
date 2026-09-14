import os
import sys

import bpy


args = sys.argv[sys.argv.index("--") + 1 :]
output_blend = os.path.abspath(args[0])

definitions = (
    ("Stair_Special_Rooftop", "01_楼梯间A_天台至基地_组件包", "A"),
    ("Stair_Generic_Rotatable", "02_楼梯间B_通用旋转_组件包", "B"),
)


def category_for(obj):
    name = obj.name
    if "EnclosureWall" in name:
        return "02_墙壁"
    if any(token in name for token in ("DoorLanding", "TurnLanding", "CoreConnector")):
        return "01_楼板"
    return "03_楼梯"


scene_root = bpy.context.scene.collection
for prefix, package_name, short_name in definitions:
    objects = [obj for obj in bpy.context.scene.objects if obj.name.startswith(prefix)]
    if not objects:
        raise RuntimeError(f"找不到楼梯间对象: {prefix}")
    root = bpy.data.objects.get(f"{prefix}_ROOT")
    if root is None:
        raise RuntimeError(f"找不到楼梯间根对象: {prefix}_ROOT")

    package = bpy.data.collections.get(package_name) or bpy.data.collections.new(package_name)
    package["3dgame_component_package"] = True
    package["component_root"] = root.name
    if package.name not in scene_root.children:
        scene_root.children.link(package)

    category_collections = {}
    for category_name in ("01_楼板", "02_墙壁", "03_楼梯"):
        collection_name = f"{short_name}_{category_name}"
        category = bpy.data.collections.get(collection_name) or bpy.data.collections.new(collection_name)
        category["3dgame_component_category"] = category_name
        category["3dgame_component"] = True
        if category.name not in package.children:
            package.children.link(category)
        category_collections[category_name] = category

    for obj in objects:
        target = package if obj == root else category_collections[category_for(obj)]
        for collection in list(obj.users_collection):
            collection.objects.unlink(obj)
        target.objects.link(obj)

    for category_name, category in category_collections.items():
        category_root_name = f"{prefix}_{category_name}_ROOT"
        category_root = bpy.data.objects.get(category_root_name) or bpy.data.objects.new(category_root_name, None)
        for collection in list(category_root.users_collection):
            collection.objects.unlink(category_root)
        category.objects.link(category_root)
        category_root.parent = root
        category_root.matrix_parent_inverse = root.matrix_world.inverted()
        category["component_root"] = category_root.name
        for obj in list(category.objects):
            if obj == category_root:
                continue
            world = obj.matrix_world.copy()
            obj.parent = category_root
            obj.matrix_world = world

changed = True
while changed:
    changed = False
    for collection in list(bpy.data.collections):
        if collection.get("3dgame_component_package") or collection.get("3dgame_component_category"):
            continue
        if not collection.objects and not collection.children:
            bpy.data.collections.remove(collection)
            changed = True

bpy.context.scene["whitebox_structure"] = "stairwell_component_packages_v012"
bpy.ops.wm.save_as_mainfile(filepath=output_blend, check_existing=False)
