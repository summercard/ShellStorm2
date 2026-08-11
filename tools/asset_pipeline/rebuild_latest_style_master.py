"""Rebuild the showcase master from the latest facility and seating outputs.

Run with Blender:
  blender --background old_master.blend --python rebuild_latest_style_master.py -- --output new_master.blend
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import bpy
from mathutils import Vector


LIBRARY = Path(
    r"C:\Users\zhuangmenghong\Documents\图片制作\新建文件夹\中文游戏资产成品\风格统一重制V3\01_正式版本_待验收"
)

ASSETS = (
    ("01_赛博储物站", "01_赛博储物站_体量强化源文件_v004.blend", (-12.0, 0.0, 0.0)),
    ("02_赛博维修工作台", "02_赛博维修工作台_体量强化源文件_v004.blend", (-6.0, 0.0, 0.0)),
    ("03_复古游戏电视站", "03_复古游戏电视站_体量强化源文件_v004.blend", (0.0, 0.0, 0.0)),
    ("04_远征情报终端", "04_战术指挥桌_体量强化源文件_v004.blend", (6.0, 0.0, 0.0)),
    ("05_科幻自动贩卖机", "05_科幻自动贩卖机_风格统一源文件_v003.blend", (12.0, 0.0, 0.0)),
    ("06_赛博维修圆凳_独立资产", "07_赛博维修圆凳_独立源文件_v003.blend", (-6.0, -3.7, 0.0)),
    ("07_战术指挥椅_独立资产", "08_战术指挥椅_独立源文件_v003.blend", (6.0, -3.7, 0.0)),
)


def parse_args() -> argparse.Namespace:
    values = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args(values)


def remove_collection_tree(collection: bpy.types.Collection) -> None:
    for child in list(collection.children):
        remove_collection_tree(child)
    for obj in list(collection.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(collection)


def append_output_collection(source_file: Path) -> bpy.types.Collection:
    before = set(bpy.data.collections)
    with bpy.data.libraries.load(str(source_file), link=False) as (available, requested):
        if "02_游戏输出_整合模型" not in available.collections:
            raise RuntimeError(f"{source_file.name} 缺少 02_游戏输出_整合模型")
        requested.collections = ["02_游戏输出_整合模型"]
    appended = [collection for collection in bpy.data.collections if collection not in before]
    if len(appended) != 1:
        raise RuntimeError(f"{source_file.name} 输出集合追加数量异常：{len(appended)}")
    return appended[0]


def normalized_material_name(name: str) -> str:
    return re.sub(r"\.\d{3}$", "", name)


def remap_facility_materials(objects: list[bpy.types.Object]) -> None:
    """Keep one low-bright facility material set, separate from the gun palette."""
    for obj in objects:
        if obj.type != "MESH":
            continue
        for slot in obj.material_slots:
            material = slot.material
            if material is None:
                continue
            target_name = f"设施_{normalized_material_name(material.name)}"
            canonical = bpy.data.materials.get(target_name)
            if canonical is None:
                material.name = target_name
                canonical = material
            elif canonical != material:
                slot.material = canonical


def main() -> None:
    options = parse_args()
    bpy.context.preferences.filepaths.save_version = 0
    old_parents = [
        collection
        for collection in bpy.data.collections
        if collection.name == "01_大型资产_风格统一排列"
        or collection.name.startswith("01_设施资产_最新尺寸与独立座椅")
    ]
    for old_parent in old_parents:
        remove_collection_tree(old_parent)

    root = bpy.data.collections.get("六类游戏资产_风格统一总合集_中文资产管理")
    if root is None:
        root = bpy.data.collections.new("六类游戏资产_风格统一总合集_中文资产管理")
        bpy.context.scene.collection.children.link(root)

    parent = bpy.data.collections.new("01_设施资产_最新尺寸与独立座椅")
    root.children.link(parent)

    for collection_name, source_name, offset in ASSETS:
        source_file = source_name if isinstance(source_name, Path) else LIBRARY / source_name
        if not source_file.exists():
            raise FileNotFoundError(source_file)
        collection = append_output_collection(source_file)
        collection.name = collection_name
        parent.children.link(collection)
        objects = [obj for obj in collection.all_objects if obj.type == "MESH"]
        if not objects:
            raise RuntimeError(f"{collection_name} 没有输出网格")
        remap_facility_materials(objects)
        translation = Vector(offset)
        for obj in objects:
            obj.location += translation
            obj.hide_set(False)
            obj.hide_viewport = False
            obj.hide_render = False
        collection.hide_viewport = False
        collection.hide_render = False

    # Remove duplicate or legacy material datablocks that no scene mesh references.
    used_materials = {
        material
        for obj in bpy.context.scene.objects
        if obj.type == "MESH"
        for material in obj.data.materials
        if material is not None
    }
    for material in list(bpy.data.materials):
        if material not in used_materials:
            bpy.data.materials.remove(material)

    for collection in bpy.data.collections:
        collection.hide_viewport = False
        collection.hide_render = False

    bpy.context.scene["asset_master_revision"] = "v003_latest_facility_volume_and_detached_seating"
    bpy.context.scene["facility_seating_embedded"] = False
    bpy.context.scene["facility_source_count"] = 5
    bpy.context.scene["standalone_seating_count"] = 2
    for image in bpy.data.images:
        if image.source != "FILE":
            continue
        basename = Path(bpy.path.abspath(image.filepath)).name or image.name
        candidate = LIBRARY / basename
        if candidate.exists():
            image.filepath = str(candidate)
    bpy.ops.file.pack_all()
    options.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(options.output), compress=True)
    print("REBUILT_MASTER", options.output)


if __name__ == "__main__":
    main()
