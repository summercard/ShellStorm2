#!/usr/bin/env python3
"""Validate v008 scope locks, facility placement and asset-package ownership."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import bpy


PROJECT = Path("/Users/summercards/ShellStorm2")
V007 = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v007.blend"
V008 = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v008.blend"
CATALOG = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v008/base_facility_component_catalog_v008.json"
PACKAGE_ROOT = PROJECT / "source/art/blender/base_facility_layout/component_packages_v008"

LOCKED = (
    "11_四向保留墙体系统_资产包",
    "12_东墙阁楼主体结构_资产包",
    "13_阁楼下方铁皮封闭体_资产包",
    "14_西北贴墙L型楼梯_资产包",
    "20_统一地面系统_36块独立地砖",
    "30_阁楼生活设施",
    "50_仓库与辅助设施",
)


def capture_locked(path):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    payload = {}
    for collection_name in LOCKED:
        collection = bpy.data.collections[collection_name]
        for obj in collection.all_objects:
            mesh = None
            if obj.type == "MESH":
                mesh = (
                    obj.data.name,
                    len(obj.data.vertices), len(obj.data.edges), len(obj.data.polygons),
                    tuple(material.name if material else None for material in obj.data.materials),
                )
            payload[obj.name] = {
                "type": obj.type,
                "parent": obj.parent.name if obj.parent else None,
                "matrix": tuple(round(float(value), 8) for row in obj.matrix_world for value in row),
                "dimensions": tuple(round(float(value), 8) for value in obj.dimensions),
                "mesh": mesh,
            }
    digest = hashlib.sha256(json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")).hexdigest()
    return payload, digest


def assert_near(label, actual, expected, tolerance=0.004):
    if abs(actual - expected) > tolerance:
        raise RuntimeError(f"{label}: actual={actual}, expected={expected}")


def main():
    before, before_hash = capture_locked(V007)
    after, after_hash = capture_locked(V008)
    if before != after or before_hash != after_hash:
        changed = sorted(name for name, value in before.items() if after.get(name) != value)
        raise RuntimeError(f"锁定范围变化: {changed[:20]}")

    root = bpy.data.collections["基地99层高品质微缩模型_中文资产管理"]
    output = bpy.data.collections["02_游戏输出_独立资产包_v008"]
    if root.get("version") != "v008" or root.get("v008_asset_id") != "ENV-BASE99-ART-LAYOUT-3D":
        raise RuntimeError("v008根元数据错误")
    categories = list(output.children)
    packages = [package for category in categories for package in category.children]
    if len(categories) != 6 or len(packages) != 82:
        raise RuntimeError(f"分类/资产包数量错误: {len(categories)}/{len(packages)}")
    if len(bpy.data.collections["20_统一地面系统_36块独立地砖"].children) != 36:
        raise RuntimeError("地砖资产包不再是36个")
    if any(category.objects for category in categories) or any(package.children for package in packages):
        raise RuntimeError("一级分类或叶级资产包层级不干净")
    if any(len(package.objects) == 0 for package in packages):
        raise RuntimeError("存在空资产包")

    package_set = set(packages)
    output_objects = list(output.all_objects)
    for obj in output_objects:
        owners = [collection for collection in obj.users_collection if collection in package_set]
        if len(owners) != 1:
            raise RuntimeError(f"对象未唯一归入资产包: {obj.name}, owners={len(owners)}")

    required_collections = {
        "41_南墙工业墙板附着结构_资产包",
        "42_BASE_CAMP大型卷帘主门_资产包",
        "43_主门下方低矮设备柜_资产包",
        "44_BASE_CAMP立体霓虹标识_资产包",
        "45_MEDICAL医疗柜_资产包",
        "46_TOOLS工具柜_资产包",
        "47_窄型电池柜_资产包",
        "48_窄型应急柜_资产包",
        "51_圆形全息设备平台_资产包",
        "52_ACCESS门禁终端_资产包",
        "53_BASE_STATUS状态终端_资产包",
        "54_STORAGE储物终端_资产包",
        "55_南墙工业管线系统_资产包",
        "56_二层栏杆附着细节_资产包",
    }
    missing_collections = sorted(name for name in required_collections if bpy.data.collections.get(name) is None)
    if missing_collections:
        raise RuntimeError(f"缺少本批次独立设施包: {missing_collections}")

    if any(obj.name.startswith(("工业电视墙_", "电视扫描线_")) for obj in bpy.data.objects):
        raise RuntimeError("旧电视误读对象仍残留")
    door = bpy.data.objects["BASE主门_外围门框底衬"]
    for index, expected in enumerate((5.0, 4.64, 2.20)):
        assert_near(f"主门中心{index}", door.location[index], expected)
    for index, expected in enumerate((5.80, 0.40, 2.55)):
        assert_near(f"主门包络{index}", door.dimensions[index], expected)
    low = bpy.data.objects["主门下方低矮设备柜_主体"]
    for index, expected in enumerate((5.0, 4.18, 0.68)):
        assert_near(f"低柜中心{index}", low.location[index], expected)
    for index, expected in enumerate((6.2, 0.78, 1.15)):
        assert_near(f"低柜尺寸{index}", low.dimensions[index], expected)
    holo = bpy.data.objects["全息终端平台_深灰主底座"]
    assert_near("全息平台X", holo.location.x, 5.0)
    assert_near("全息平台Y", holo.location.y, 1.72)
    assert_near("全息平台直径", holo.dimensions.x, 2.28, 0.01)
    for name, x in (("工业储物柜_01_柜体", -3.65), ("工业储物柜_02_柜体", -1.85), ("工业储物柜_03_柜体", 11.85), ("工业储物柜_04_柜体", 13.65)):
        obj = bpy.data.objects[name]
        assert_near(name + " X", obj.location.x, x)
        assert_near(name + " Y", obj.location.y, 4.46)

    scoped = [obj for obj in output_objects if obj.get("v008_scope") == "south_facility_detail"]
    if len(scoped) < 300:
        raise RuntimeError(f"本批次资产级细节不足: {len(scoped)}")
    outside = []
    for obj in scoped:
        x, y, z = obj.matrix_world.translation
        if not (-5.05 <= x <= 14.95 and 0.30 <= y <= 5.40 and -0.02 <= z <= 7.10):
            outside.append((obj.name, tuple(round(v, 3) for v in (x, y, z))))
    if outside:
        raise RuntimeError(f"本批次对象越出南面设施范围: {outside[:20]}")

    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    manifests = list(PACKAGE_ROOT.glob("*/*/asset_manifest.json"))
    if catalog["package_count"] != 82 or catalog["floor_tile_package_count"] != 36 or len(manifests) != 82:
        raise RuntimeError("v008分类清单或磁盘资产目录数量错误")
    for manifest_path in manifests:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        collection = bpy.data.collections.get(manifest["collection_path"][-1])
        if collection is None or manifest["object_count"] != len(collection.objects):
            raise RuntimeError(f"清单与Blend不一致: {manifest_path}")

    print("BASE_FACILITY_V008_SCOPE_AND_PACKAGING_VALID")
    print(f"locked_signature_v007={before_hash}")
    print(f"locked_signature_v008={after_hash}")
    print(f"locked_match={before_hash == after_hash}")
    print(f"categories={len(categories)} packages={len(packages)} floor_tiles=36")
    print(f"output_objects={len(output_objects)} scoped_new_details={len(scoped)}")
    print(f"scene_objects={len(bpy.data.objects)} meshes={sum(obj.type == 'MESH' for obj in bpy.data.objects)} lights={sum(obj.type == 'LIGHT' for obj in bpy.data.objects)} cameras={sum(obj.type == 'CAMERA' for obj in bpy.data.objects)} materials={len(bpy.data.materials)}")
    print("main_door_envelope=5.80x0.40x2.55 center=(5.0,4.64,2.20)")
    print("hologram_center=(5.0,1.72) diameter=2.28")
    print("old_tv_objects=0 empty_packages=0 multi_package_objects=0 disk_manifests=82")


if __name__ == "__main__":
    main()
