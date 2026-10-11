import bpy
import json
import os


SOURCE = os.path.abspath(
    os.path.join(os.path.dirname(bpy.data.filepath), "../whitebox_tower_stairs_v017/whitebox_tower_stairs_v017.blend")
)
LEAVES = [
    "通用墙组件_资产包",
    "通用地板组件_资产包",
    "通用楼梯组件_资产包",
    "墙面装甲与结构框_装饰组件",
    "地面导光与警示_装饰组件",
    "工业管线_装饰组件",
    "灯带与发光几何_装饰组件",
    "楼层标识与海报_装饰组件",
    "控制盒_装饰组件",
    "固定绿植_装饰组件",
]
REMOVED = {
    "墙体.043_游戏输出_v017输出",
    "墙体.051_游戏输出_v017输出",
    "右墙_装甲面板_L1_1_v017输出",
    "右墙_装甲面板_L2_1_v017输出",
    "侧墙_竖向骨架_47.22_-2.45_v017输出",
}


def is_modified(name):
    return (
        name.startswith("侧墙_横向骨架_47.22_")
        or ("_L2_" in name and "装甲面板" in name)
        or name.startswith("海报")
    )


current = {}
membership = {}
for collection_name in LEAVES:
    for obj in bpy.data.collections[collection_name].objects:
        if obj.type != "MESH":
            continue
        current[obj.name] = obj
        membership.setdefault(obj.name, []).append(collection_name)

new_names = {name for name, obj in current.items() if obj.get("SS2_platform_railing")}
wanted_names = set(current) - new_names | REMOVED
with bpy.data.libraries.load(SOURCE, link=True) as (data_from, data_to):
    requested = [name for name in data_from.objects if name in wanted_names]
    data_to.objects = requested

source = {obj.name: obj for obj in data_to.objects if obj is not None}
mismatches = []
for name, obj in current.items():
    if name in new_names or is_modified(name):
        continue
    old = source.get(name)
    same = old is not None
    if same:
        same = all(
            abs(obj.matrix_basis[row][column] - old.matrix_basis[row][column]) < 1e-6
            for row in range(4)
            for column in range(4)
        )
    if same:
        same = (
            len(obj.data.vertices) == len(old.data.vertices)
            and len(obj.data.edges) == len(old.data.edges)
            and len(obj.data.polygons) == len(old.data.polygons)
        )
    if same:
        same = all((new_vertex.co - old_vertex.co).length < 1e-7 for new_vertex, old_vertex in zip(obj.data.vertices, old.data.vertices))
    if not same:
        mismatches.append(name)

missing_removals = sorted(name for name in REMOVED if name in current)
result = {
    "source": SOURCE,
    "output_mesh_count": len(current),
    "locked_object_count": len(current) - len(new_names) - sum(is_modified(name) for name in current),
    "new_platform_railing_objects": len(new_names),
    "removed_objects": sorted(REMOVED),
    "missing_removals": missing_removals,
    "locked_mismatches": mismatches,
    "empty_packages": [name for name in LEAVES if not bpy.data.collections[name].objects],
    "multi_package_objects": {name: owners for name, owners in membership.items() if len(owners) != 1},
    "passed": not missing_removals and not mismatches and all(len(owners) == 1 for owners in membership.values()),
}
print(json.dumps(result, ensure_ascii=False, indent=2))
raise SystemExit(0 if result["passed"] else 1)
