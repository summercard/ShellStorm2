import bpy
import json
import os


ROOT = os.path.dirname(bpy.data.filepath)
SOURCE = os.path.abspath(
    os.path.join(
        ROOT,
        "../../../../../../../tools/3Dgame-design/save/blocks/stairs/whitebox_tower_stairs_v018/whitebox_tower_stairs_v018.blend",
    )
)
MANIFEST_ROOT = os.path.join(ROOT, "component_packages")
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
RESTORED = {
    "墙体.043_游戏输出_v017输出",
    "墙体.051_游戏输出_v017输出",
    "右墙_装甲面板_L1_1_v017输出",
    "右墙_装甲面板_L2_1_v017输出",
    "侧墙_竖向骨架_47.22_-2.45_v017输出",
}
REMOVED = {
    "左墙_装甲面板_L1_1_v017输出",
    "左墙_装甲面板_L2_1_v017输出",
    "侧墙_竖向骨架_32.78_-2.45_v017输出",
}
MODIFIED = {
    f"侧墙_横向骨架_{side}_{height}_v017输出"
    for side in ("32.78", "47.22")
    for height in ("-20.60", "-9.10", "2.15")
}
MANIFEST_PATHS = {
    "通用墙组件_资产包": "architecture/wall_component/asset_manifest.json",
    "通用地板组件_资产包": "architecture/floor_component/asset_manifest.json",
    "通用楼梯组件_资产包": "architecture/stair_component/asset_manifest.json",
    "墙面装甲与结构框_装饰组件": "decorations/wall_surface/asset_manifest.json",
    "地面导光与警示_装饰组件": "decorations/floor_guidance/asset_manifest.json",
    "工业管线_装饰组件": "decorations/pipes/asset_manifest.json",
    "灯带与发光几何_装饰组件": "decorations/light_geometry/asset_manifest.json",
    "楼层标识与海报_装饰组件": "decorations/signage/asset_manifest.json",
    "控制盒_装饰组件": "decorations/controls/asset_manifest.json",
    "固定绿植_装饰组件": "decorations/fixed_plant/asset_manifest.json",
}


def world_bounds(obj):
    points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    return tuple(round(value, 3) for axis in range(3) for value in (min(p[axis] for p in points), max(p[axis] for p in points)))


current = {}
membership = {}
for collection_name in LEAVES:
    for obj in bpy.data.collections[collection_name].objects:
        if obj.type != "MESH":
            continue
        current[obj.name] = obj
        membership.setdefault(obj.name, []).append(collection_name)

locked_names = sorted(set(current) - RESTORED - MODIFIED)
with bpy.data.libraries.load(SOURCE, link=True) as (data_from, data_to):
    data_to.objects = [name for name in data_from.objects if name in locked_names]
source = {obj.name: obj for obj in data_to.objects if obj is not None}

locked_mismatches = []
for name in locked_names:
    obj = current[name]
    old = source.get(name)
    same = old is not None
    if same:
        same = all(abs(obj.matrix_basis[row][column] - old.matrix_basis[row][column]) < 1e-6 for row in range(4) for column in range(4))
    if same:
        same = (
            len(obj.data.vertices) == len(old.data.vertices)
            and len(obj.data.edges) == len(old.data.edges)
            and len(obj.data.polygons) == len(old.data.polygons)
            and all((a.co - b.co).length < 1e-7 for a, b in zip(obj.data.vertices, old.data.vertices))
        )
    if not same:
        locked_mismatches.append(name)

manifest_mismatches = {}
for collection_name, relative_path in MANIFEST_PATHS.items():
    with open(os.path.join(MANIFEST_ROOT, relative_path), encoding="utf-8") as handle:
        manifest_objects = set(json.load(handle)["objects"])
    collection_objects = {obj.name for obj in bpy.data.collections[collection_name].objects if obj.type == "MESH"}
    if manifest_objects != collection_objects:
        manifest_mismatches[collection_name] = {
            "missing_from_manifest": sorted(collection_objects - manifest_objects),
            "extra_in_manifest": sorted(manifest_objects - collection_objects),
        }

expected_frame_bounds = {
    "left": (2.5, 26.8),
    "right": (-2.2, 26.8),
}
frame_bounds = {}
frame_bounds_ok = True
for side, key in (("32.78", "left"), ("47.22", "right")):
    name = f"侧墙_横向骨架_{side}_-9.10_v017输出"
    bounds = world_bounds(current[name])
    frame_bounds[key] = [bounds[2], bounds[3]]
    frame_bounds_ok &= abs(bounds[2] - expected_frame_bounds[key][0]) < 1e-3 and abs(bounds[3] - expected_frame_bounds[key][1]) < 1e-3

upper_right = world_bounds(current["右墙_装甲面板_L2_1_v017输出"])
result = {
    "source": SOURCE,
    "output_mesh_count": len(current),
    "component_counts": {name: sum(obj.type == "MESH" for obj in bpy.data.collections[name].objects) for name in LEAVES},
    "locked_object_count": len(locked_names),
    "locked_mismatches": locked_mismatches,
    "restored_missing": sorted(RESTORED - set(current)),
    "removed_still_present": sorted(REMOVED & set(current)),
    "frame_y_bounds": frame_bounds,
    "frame_bounds_ok": frame_bounds_ok,
    "restored_upper_right_panel_z": [upper_right[4], upper_right[5]],
    "empty_packages": [name for name in LEAVES if not bpy.data.collections[name].objects],
    "multi_package_objects": {name: owners for name, owners in membership.items() if len(owners) != 1},
    "manifest_mismatches": manifest_mismatches,
}
result["passed"] = not any(
    (
        result["locked_mismatches"],
        result["restored_missing"],
        result["removed_still_present"],
        result["empty_packages"],
        result["multi_package_objects"],
        result["manifest_mismatches"],
    )
) and frame_bounds_ok and result["restored_upper_right_panel_z"] == [-9.0, 2.3]
print(json.dumps(result, ensure_ascii=False, indent=2))
raise SystemExit(0 if result["passed"] else 1)
