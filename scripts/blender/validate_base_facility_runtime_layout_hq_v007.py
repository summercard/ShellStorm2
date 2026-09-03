#!/usr/bin/env python3
"""Strict organization/asset-package validation for base facility v007."""

from __future__ import annotations

import json
from pathlib import Path

import bpy


PROJECT_ROOT = Path("/Users/summercards/ShellStorm2")
BLEND_PATH = PROJECT_ROOT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v007.blend"
CATALOG_PATH = PROJECT_ROOT / "outputs/verification/base_facility_runtime_layout_hq_v007/base_facility_component_catalog_v007.json"
PACKAGE_ROOT = PROJECT_ROOT / "source/art/blender/base_facility_layout/component_packages"
OUTPUT_NAME = "02_游戏输出_独立资产包_v007"
OLD_NAMES = {
    "10_保留墙体与地板",
    "20_中央东西主通道",
    "21_地板系统深化_v006",
    "30_北侧楼中楼与L型楼梯",
    "31_阁楼生活区",
    "40_阁楼下方视觉中心与固定设施",
    "50_南侧仓库与辅助设施",
    "60_独立展示附件_不焊接",
    "70_基础动效几何",
    "80_实际灯光与动效",
}


def fail(message):
    raise RuntimeError(message)


def main():
    if Path(bpy.data.filepath).resolve() != BLEND_PATH.resolve():
        fail(f"验收文件错误: {bpy.data.filepath}")

    root = bpy.data.collections.get("基地99层高品质微缩模型_中文资产管理")
    output = bpy.data.collections.get(OUTPUT_NAME)
    if root is None or output is None:
        fail("缺少 v007 根集合或游戏输出集合")
    if root.get("version") != "v007" or root.get("v007_package_count") != 76:
        fail("根集合版本/资产包元数据错误")
    if any(bpy.data.collections.get(name) is not None for name in OLD_NAMES):
        fail("旧版总集合仍残留")

    expected_categories = {
        "10_建筑结构",
        "20_统一地面系统_36块独立地砖",
        "30_阁楼生活设施",
        "40_阁楼外侧视觉中心设施",
        "50_仓库与辅助设施",
        "60_共享照明与环境动效",
    }
    actual_categories = {collection.name for collection in output.children}
    if actual_categories != expected_categories:
        fail(f"一级分类不符: {actual_categories}")
    if len(output.objects):
        fail("输出根集合不应直接存放对象")

    packages = [package for category in output.children for package in category.children]
    if len(packages) != 76:
        fail(f"资产包数量错误: {len(packages)}")
    if any(category.objects for category in output.children):
        fail("一级分类集合不应直接存放对象")
    if any(package.children for package in packages):
        fail("资产包必须是叶级集合")
    if any(not package.get("资产包") for package in packages):
        fail("存在未标记为资产包的叶级集合")
    if any(len(package.objects) == 0 for package in packages):
        fail("存在空资产包")

    floor_category = bpy.data.collections["20_统一地面系统_36块独立地砖"]
    if len(floor_category.children) != 36:
        fail(f"地砖资产包数量错误: {len(floor_category.children)}")
    for row in range(1, 7):
        for column in range(1, 7):
            collection_name = f"地砖_R{row:02d}C{column:02d}_原砖与深化内容_资产包"
            collection = bpy.data.collections.get(collection_name)
            if collection is None:
                fail(f"缺少地砖资产包: {collection_name}")
            root_name = f"保留地板_{row - 1:02d}_{column - 1:02d}"
            tile_root = bpy.data.objects.get(root_name)
            if tile_root is None or collection not in tile_root.users_collection:
                fail(f"地砖原模块未归入对应资产包: {root_name}")
            descendants = list(tile_root.children_recursive)
            if not descendants or any(collection not in child.users_collection for child in descendants):
                fail(f"地砖原模块子物体跨包: {root_name}")
            if not any(obj.name.startswith("地板深化_") or "地板" in obj.name or "接口" in obj.name or "标识" in obj.name or "轮痕" in obj.name or "油渍" in obj.name for obj in collection.objects if obj is not tile_root):
                fail(f"地砖包缺少深化内容: {collection_name}")

    output_objects = list(output.all_objects)
    if len(output_objects) != 1696:
        fail(f"游戏输出对象数错误: {len(output_objects)}")
    package_set = set(packages)
    for obj in output_objects:
        owners = [collection for collection in obj.users_collection if collection in package_set]
        if len(owners) != 1:
            fail(f"对象未唯一归入资产包: {obj.name}, owners={len(owners)}")

    output_meshes = [obj for obj in output_objects if obj.type == "MESH"]
    missing_uv = [obj.name for obj in output_meshes if "PaletteUV" not in obj.data.uv_layers]
    if missing_uv:
        fail(f"游戏输出网格缺少 PaletteUV: {missing_uv[:10]}")
    if len(bpy.data.objects) != 3211 or len([obj for obj in bpy.data.objects if obj.type == "MESH"]) != 3048:
        fail("全场景对象或网格数量与 v006 不一致")
    if len([obj for obj in bpy.data.objects if obj.type == "LIGHT"]) != 22:
        fail("灯光数量与 v006 不一致")
    if len([obj for obj in bpy.data.objects if obj.type == "CAMERA"]) != 3:
        fail("相机数量与 v006 不一致")
    if len(bpy.data.materials) != 4:
        fail(f"材质数量不符合四材质契约: {len(bpy.data.materials)}")

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    if not catalog.get("signature_match") or catalog.get("package_count") != 76:
        fail("分类清单签名或资产包数量错误")
    if catalog.get("floor_tile_package_count") != 36:
        fail("分类清单地砖数量错误")
    manifests = list(PACKAGE_ROOT.glob("*/*/asset_manifest.json"))
    if len(manifests) != 76:
        fail(f"磁盘资产目录/清单数量错误: {len(manifests)}")
    for manifest_path in manifests:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        collection = bpy.data.collections.get(manifest["collection_path"][-1])
        if collection is None or manifest["object_count"] != len(collection.objects):
            fail(f"磁盘清单与 Blender Collection 不一致: {manifest_path}")

    print("BASE_FACILITY_V007_ORGANIZATION_VALID")
    print(f"packages={len(packages)} floor_tiles={len(floor_category.children)}")
    print(f"output_objects={len(output_objects)} output_meshes={len(output_meshes)}")
    print("scene_objects=3211 meshes=3048 lights=22 cameras=3 materials=4")
    print("old_output_collections=0 empty_packages=0 multi_package_objects=0")
    print("all_output_meshes_have_PaletteUV=True")
    print("object_transform_mesh_material_animation_signature_match=True")


if __name__ == "__main__":
    main()
