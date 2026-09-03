#!/usr/bin/env python3
"""Reorganize the v006 base scene into independent game-asset packages.

This pass is intentionally non-visual: it only changes Blender Collection links,
collection metadata, and the output file path. Object transforms, parenting,
mesh data, materials, animation, lighting, and render settings stay unchanged.
"""

from __future__ import annotations

import hashlib
import json
import math
import re
from pathlib import Path

import bpy


PROJECT_ROOT = Path("/Users/summercards/ShellStorm2")
SOURCE_BLEND = PROJECT_ROOT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v006.blend"
OUTPUT_BLEND = PROJECT_ROOT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v007.blend"
PACKAGE_ROOT = PROJECT_ROOT / "source/art/blender/base_facility_layout/component_packages"
VERIFY_ROOT = PROJECT_ROOT / "outputs/verification/base_facility_runtime_layout_hq_v007"
CATALOG_JSON = VERIFY_ROOT / "base_facility_component_catalog_v007.json"
TREE_TXT = VERIFY_ROOT / "base_facility_component_tree_v007.txt"
HERO_RENDER = VERIFY_ROOT / "base_facility_runtime_layout_hq_v007.png"
TOP_RENDER = VERIFY_ROOT / "base_facility_runtime_layout_hq_v007_top.png"

ROOT_NAME = "基地99层高品质微缩模型_中文资产管理"
OUTPUT_NAME_V006 = "02_游戏输出_整合模型"
OUTPUT_NAME_V007 = "02_游戏输出_独立资产包_v007"
DISPLAY_NAME = "90_展示环境_灯光相机"

OLD_OUTPUT_COLLECTIONS = {
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


def round_seq(values, digits=8):
    return tuple(round(float(value), digits) for value in values)


def object_signature(obj):
    data = obj.data
    mesh_info = None
    if obj.type == "MESH":
        mesh_info = (
            data.name,
            len(data.vertices),
            len(data.edges),
            len(data.polygons),
            len(data.loops),
            tuple(material.name if material else None for material in data.materials),
        )
    elif data is not None:
        mesh_info = (data.name,)
    action = None
    if obj.animation_data and obj.animation_data.action:
        action = obj.animation_data.action.name
    return {
        "type": obj.type,
        "parent": obj.parent.name if obj.parent else None,
        "matrix_world": round_seq(value for row in obj.matrix_world for value in row),
        "dimensions": round_seq(obj.dimensions),
        "data": mesh_info,
        "action": action,
        "hide_render": bool(obj.hide_render),
        "hide_viewport": bool(obj.hide_viewport),
    }


def scene_signature():
    payload = {obj.name: object_signature(obj) for obj in sorted(bpy.data.objects, key=lambda item: item.name)}
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return payload, hashlib.sha256(encoded).hexdigest()


def ensure_child(parent, name):
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
    if collection.name not in parent.children:
        parent.children.link(collection)
    return collection


def set_package_metadata(collection, *, slug, category, export_dir):
    collection["资产包"] = True
    collection["资产包键"] = slug
    collection["资产类别"] = category
    collection["源场景资产ID"] = "ENV-BASE99-ART-LAYOUT-3D"
    collection["未来导出目录"] = str(export_dir.relative_to(PROJECT_ROOT))
    collection["组织版本"] = "v007"
    collection["当前状态"] = "已归类_待独立导出"


def make_package(parent, name, slug, category):
    collection = ensure_child(parent, name)
    export_dir = PACKAGE_ROOT / category / slug
    set_package_metadata(collection, slug=slug, category=category, export_dir=export_dir)
    return collection


def top_ancestor(obj):
    current = obj
    while current.parent is not None:
        current = current.parent
    return current


def tile_key_from_xy(x, y):
    column = max(1, min(6, int(math.floor((x + 15.0) / 5.0)) + 1))
    row = max(1, min(6, int(math.floor((y + 15.0) / 5.0)) + 1))
    return f"R{row:02d}C{column:02d}"


def source_output_collection(obj):
    names = sorted(collection.name for collection in obj.users_collection if collection.name in OLD_OUTPUT_COLLECTIONS)
    return names[0] if names else None


def build_collection_tree(output_collection):
    categories = {
        "architecture": ensure_child(output_collection, "10_建筑结构"),
        "floor": ensure_child(output_collection, "20_统一地面系统_36块独立地砖"),
        "loft": ensure_child(output_collection, "30_阁楼生活设施"),
        "underloft": ensure_child(output_collection, "40_阁楼外侧视觉中心设施"),
        "warehouse": ensure_child(output_collection, "50_仓库与辅助设施"),
        "support": ensure_child(output_collection, "60_共享照明与环境动效"),
    }

    packages = {}

    def add(key, category, label, slug):
        packages[key] = make_package(categories[category], label, slug, category)

    add("walls", "architecture", "11_四向保留墙体系统_资产包", "retained_wall_system")
    add("mezzanine", "architecture", "12_东墙阁楼主体结构_资产包", "east_mezzanine_structure")
    add("underdeck", "architecture", "13_阁楼下方铁皮封闭体_资产包", "underdeck_sheet_blocker")
    add("stair", "architecture", "14_西北贴墙L型楼梯_资产包", "northwest_l_stair")

    tile_packages = {}
    for row in range(1, 7):
        for column in range(1, 7):
            key = f"R{row:02d}C{column:02d}"
            slug = f"tile_r{row:02d}_c{column:02d}"
            label = f"地砖_{key}_原砖与深化内容_资产包"
            tile_packages[key] = make_package(categories["floor"], label, slug, "floor")
    packages.update({f"tile_{key}": value for key, value in tile_packages.items()})

    add("loft_bed", "loft", "31_金属床与床下收纳_资产包", "metal_bed_storage")
    add("loft_curtain", "loft", "32_床区隐私布帘_资产包", "bed_privacy_curtain")
    add("loft_bar_table", "loft", "33_高脚桌_资产包", "loft_bar_table")
    add("loft_bar_stool_1", "loft", "34_高脚椅01_资产包", "loft_bar_stool_01")
    add("loft_bar_stool_2", "loft", "35_高脚椅02_资产包", "loft_bar_stool_02")
    add("loft_workbench", "loft", "36_小型工作台_资产包", "loft_workbench")
    add("loft_computer", "loft", "37_电脑终端_资产包", "loft_computer_terminal")
    add("loft_radio", "loft", "38_电台_资产包", "loft_radio")
    add("loft_firstaid", "loft", "39_急救包_资产包", "loft_first_aid_kit")
    add("loft_extinguisher", "loft", "40_灭火器_资产包", "loft_fire_extinguisher")
    add("loft_supply", "loft", "41_东墙补给柜与散件_资产包", "loft_supply_cabinet")

    add("tv_backdrop", "underloft", "41_电视复合背景墙_资产包", "tv_composite_backdrop")
    add("tv_display", "underloft", "42_工业电视与扫描线_资产包", "industrial_tv_display")
    add("tv_lowcab", "underloft", "43_电视低柜_资产包", "tv_low_storage_cabinet")
    add("base_sign", "underloft", "44_BASE_CAMP立体霓虹标识_资产包", "base_camp_neon_sign")
    for index in range(1, 5):
        add(
            f"locker_{index}",
            "underloft",
            f"{44 + index:02d}_工业储物柜{index:02d}_资产包",
            f"industrial_locker_{index:02d}",
        )
    add("armory", "underloft", "49_武器工作台与弹药附件_资产包", "weapon_workshop_station")
    add("vending", "underloft", "50_自动补给机与商品回收附件_资产包", "supply_vending_station")

    add("shelf", "warehouse", "51_重型货架与补给箱_资产包", "heavy_supply_shelf")
    add("maintenance", "warehouse", "52_维修工作台工具墙与挂件_资产包", "maintenance_workstation")
    add("generator", "warehouse", "53_备用发电机_资产包", "backup_generator")
    add("batteries", "warehouse", "54_蓄电池组_资产包", "battery_bank")
    add("power_box", "warehouse", "55_东墙配电箱_资产包", "east_power_box")
    add("water_tank", "warehouse", "56_工业水箱_资产包", "industrial_water_tank")
    add("purifier", "warehouse", "57_净水器_资产包", "water_purifier")
    add("compressor", "warehouse", "58_空气压缩机_资产包", "air_compressor")
    add("hose", "warehouse", "59_水管卷盘_资产包", "hose_reel")
    add("bins", "warehouse", "60_分类垃圾箱组_资产包", "sorting_bin_group")
    add("boards", "warehouse", "61_南墙资料板组_资产包", "south_wall_information_boards")

    add("pendant_lights", "support", "61_仓库防爆吊灯组_资产包", "warehouse_pendant_light_group")
    add("emergency_lights", "support", "62_主通道应急灯组_资产包", "corridor_emergency_light_group")
    add("steam", "support", "63_设备蒸汽动效组_资产包", "equipment_steam_fx")
    add("dust", "support", "64_光束尘埃动效组_资产包", "volumetric_dust_fx")

    return categories, packages, tile_packages


def classify(obj, tile_packages):
    source = source_output_collection(obj)
    name = obj.name

    if source == "10_保留墙体与地板":
        root_name = top_ancestor(obj).name
        match = re.match(r"保留地板_(\d{2})_(\d{2})", root_name)
        if match:
            row = int(match.group(1)) + 1
            column = int(match.group(2)) + 1
            return f"tile_R{row:02d}C{column:02d}"
        if root_name.startswith("保留北墙") or root_name.startswith("保留南墙") or root_name.startswith("保留西墙") or root_name.startswith("保留东墙"):
            return "walls"

    if source == "21_地板系统深化_v006":
        match = re.search(r"R(\d{2})C(\d{2})", name)
        if match:
            return f"tile_R{int(match.group(1)):02d}C{int(match.group(2)):02d}"
        location = obj.matrix_world.translation
        return f"tile_{tile_key_from_xy(location.x, location.y)}"

    if source == "30_北侧楼中楼与L型楼梯":
        if name.startswith("L梯_"):
            return "stair"
        if "阁楼下方三面铁皮封闭体" in name or "UNDERDECK-BLOCKER" in name or name.startswith("仓库挡板_"):
            return "underdeck"
        return "mezzanine"

    if source == "31_阁楼生活区":
        if name.startswith("阁楼床_") or name.startswith("床下储物箱") or name.startswith("床头灯_"):
            return "loft_bed"
        if name.startswith("床区布帘"):
            return "loft_curtain"
        if name.startswith("阁楼高脚桌"):
            return "loft_bar_table"
        if name.startswith("阁楼高脚椅_1"):
            return "loft_bar_stool_1"
        if name.startswith("阁楼高脚椅_2"):
            return "loft_bar_stool_2"
        if name.startswith("阁楼小型工作台"):
            return "loft_workbench"
        if name.startswith("阁楼电脑"):
            return "loft_computer"
        if name.startswith("阁楼电台") or name.startswith("电台旋钮"):
            return "loft_radio"
        if name.startswith("阁楼急救包"):
            return "loft_firstaid"
        if name.startswith("阁楼灭火器"):
            return "loft_extinguisher"
        if name.startswith("阁楼东墙补给柜") or name.startswith("阁楼补给"):
            return "loft_supply"

    if source == "40_阁楼下方视觉中心与固定设施":
        if name.startswith("电视背景墙_"):
            return "tv_backdrop"
        if name == "工业电视墙_下方储物柜":
            return "tv_lowcab"
        if name.startswith("工业电视墙_"):
            return "tv_display"
        if name.startswith("电视低柜门_"):
            return "tv_lowcab"
        if name.startswith("BASE_CAMP_"):
            return "base_sign"
        match = re.match(r"工业储物柜_(\d{2})_", name)
        if match:
            return f"locker_{int(match.group(1))}"
        if name.startswith("武器") or name.startswith("ARMORY_"):
            return "armory"
        if name.startswith("复古工业自动贩卖机") or name.startswith("自动贩卖机"):
            return "vending"

    if source == "50_南侧仓库与辅助设施":
        if name.startswith("南仓库重型货架_A_"):
            return "shelf"
        if name.startswith("南仓维修台") or name.startswith("南仓工具墙"):
            return "maintenance"
        if name.startswith("备用发电机"):
            return "generator"
        if name.startswith("蓄电池组"):
            return "batteries"
        if name.startswith("东墙配电箱"):
            return "power_box"
        if name.startswith("工业水箱"):
            return "water_tank"
        if name.startswith("净水器"):
            return "purifier"
        if name.startswith("空气压缩机"):
            return "compressor"
        if name.startswith("水管卷盘"):
            return "hose"
        if name.startswith("分类垃圾箱"):
            return "bins"
        if name.startswith("南墙资料板"):
            return "boards"

    if source == "60_独立展示附件_不焊接":
        if name.startswith("阁楼备用电池箱") or name.startswith("阁楼工具箱"):
            return "loft_supply"
        match = re.match(r"柜顶工具箱_(\d+)", name)
        if match:
            return f"locker_{int(match.group(1)) + 1}"
        if name.startswith("武器台弹药箱"):
            return "armory"
        if name.startswith("自动贩卖机_商品"):
            return "vending"
        if name.startswith("南仓库重型货架_A_补给箱"):
            return "shelf"
        if name.startswith("南仓工具挂件"):
            return "maintenance"

    if source == "70_基础动效几何":
        if name.startswith("铁皮外立面线性灯"):
            return "underdeck"
        if name.startswith("L梯_"):
            return "stair"
        if name.startswith("床区布帘"):
            return "loft_curtain"
        if name.startswith("电视扫描线"):
            return "tv_display"
        if name.startswith("自动贩卖机_指示灯"):
            return "vending"
        if name.startswith("仓库吊灯") or name.startswith("仓库防爆吊灯"):
            return "pendant_lights"
        if name.startswith("主通道应急灯"):
            return "emergency_lights"
        if name.startswith("设备蒸汽"):
            return "steam"
        if name.startswith("光束尘埃"):
            return "dust"

    if source == "80_实际灯光与动效":
        if name.startswith("铁皮外立面呼吸灯"):
            return "underdeck"
        if name.startswith("床头暖光"):
            return "loft_bed"
        if name.startswith("BASE_CAMP_背光"):
            return "base_sign"
        if name.startswith("武器台红色警示灯"):
            return "armory"
        if name.startswith("仓库吊灯摆动轴") or name.startswith("仓库主吊灯光"):
            return "pendant_lights"
        if name.startswith("主通道应急红光"):
            return "emergency_lights"

    raise RuntimeError(f"未分类对象: {name}（来源集合: {source}）")


def move_to_package(obj, target):
    if target not in obj.users_collection:
        target.objects.link(obj)
    for collection in list(obj.users_collection):
        if collection.name in OLD_OUTPUT_COLLECTIONS:
            collection.objects.unlink(obj)


def remove_old_collections(output_collection):
    for name in sorted(OLD_OUTPUT_COLLECTIONS):
        collection = bpy.data.collections.get(name)
        if collection is None:
            continue
        if len(collection.objects) or len(collection.children):
            raise RuntimeError(f"旧集合未清空: {name}, objects={len(collection.objects)}, children={len(collection.children)}")
        if collection.name in output_collection.children:
            output_collection.children.unlink(collection)
        bpy.data.collections.remove(collection)


def collection_path(collection):
    parent_map = {}
    for candidate in bpy.data.collections:
        for child in candidate.children:
            parent_map[child.name] = candidate
    parts = [collection.name]
    current = collection
    while current.name in parent_map:
        current = parent_map[current.name]
        parts.append(current.name)
    return list(reversed(parts))


def write_catalog(packages, before_hash, after_hash):
    VERIFY_ROOT.mkdir(parents=True, exist_ok=True)
    entries = []
    for key, collection in sorted(packages.items(), key=lambda item: collection_path(item[1])):
        export_dir = PROJECT_ROOT / collection["未来导出目录"]
        export_dir.mkdir(parents=True, exist_ok=True)
        objects = sorted(collection.objects, key=lambda obj: obj.name)
        entry = {
            "package_key": key,
            "asset_slug": collection["资产包键"],
            "category": collection["资产类别"],
            "collection_path": collection_path(collection),
            "future_export_directory": collection["未来导出目录"],
            "source_blend": str(OUTPUT_BLEND.relative_to(PROJECT_ROOT)),
            "source_asset_id": collection["源场景资产ID"],
            "status": collection["当前状态"],
            "object_count": len(objects),
            "mesh_count": sum(obj.type == "MESH" for obj in objects),
            "light_count": sum(obj.type == "LIGHT" for obj in objects),
            "object_names": [obj.name for obj in objects],
        }
        manifest = dict(entry)
        manifest["note"] = "该目录已完成资产归类占位；后续从指定 Blender Collection 独立导出 GLB/碰撞/场景。"
        with (export_dir / "asset_manifest.json").open("w", encoding="utf-8") as handle:
            json.dump(manifest, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        entries.append(entry)

    catalog = {
        "schema": "shellstorm2.base_facility.component_catalog.v1",
        "organization_version": "v007",
        "source_asset_id": "ENV-BASE99-ART-LAYOUT-3D",
        "source_blend": str(SOURCE_BLEND.relative_to(PROJECT_ROOT)),
        "organized_blend": str(OUTPUT_BLEND.relative_to(PROJECT_ROOT)),
        "visual_or_transform_changes": False,
        "scene_signature_before": before_hash,
        "scene_signature_after": after_hash,
        "signature_match": before_hash == after_hash,
        "package_count": len(entries),
        "floor_tile_package_count": sum(entry["category"] == "floor" for entry in entries),
        "packages": entries,
    }
    with CATALOG_JSON.open("w", encoding="utf-8") as handle:
        json.dump(catalog, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    lines = [
        "基地场景独立资产包树 v007",
        f"源资产ID: ENV-BASE99-ART-LAYOUT-3D",
        f"独立资产包数量: {len(entries)}",
        f"地砖资产包数量: {catalog['floor_tile_package_count']}",
        "",
    ]
    output = bpy.data.collections[OUTPUT_NAME_V007]
    for category in output.children:
        lines.append(f"{category.name}/")
        for package in category.children:
            lines.append(
                f"  {package.name}/  [{package['资产包键']}]  objects={len(package.objects)}  -> {package['未来导出目录']}"
            )
        lines.append("")
    TREE_TXT.write_text("\n".join(lines), encoding="utf-8")
    return catalog


def render_preview(camera_name, filepath):
    scene = bpy.context.scene
    scene.camera = bpy.data.objects[camera_name]
    scene.render.filepath = str(filepath)
    bpy.ops.render.render(write_still=True)


def main():
    if Path(bpy.data.filepath).resolve() != SOURCE_BLEND.resolve():
        raise RuntimeError(f"请以 v006 为输入运行，当前文件: {bpy.data.filepath}")
    if OUTPUT_BLEND.exists():
        raise RuntimeError(f"目标文件已存在，为避免覆盖已停止: {OUTPUT_BLEND}")

    before_payload, before_hash = scene_signature()
    root = bpy.data.collections[ROOT_NAME]
    root["version"] = "v007"
    root["v007_scope"] = "collection hierarchy and future export folder organization only"
    root["v007_visual_change"] = False
    root["v007_package_count"] = 76
    output_collection = bpy.data.collections[OUTPUT_NAME_V006]
    output_collection.name = OUTPUT_NAME_V007
    output_collection["资产组织版本"] = "v007"
    output_collection["资产组织说明"] = "地面按单砖归类；所有固定设施主体、附件、灯光、动效按设施独立归类。"

    categories, packages, tile_packages = build_collection_tree(output_collection)
    candidates = [obj for obj in bpy.data.objects if source_output_collection(obj)]
    if len(candidates) != 1696:
        raise RuntimeError(f"v006 输出对象数量异常，预期 1696，实际 {len(candidates)}")

    classification_counts = {}
    for obj in candidates:
        key = classify(obj, tile_packages)
        move_to_package(obj, packages[key])
        classification_counts[key] = classification_counts.get(key, 0) + 1

    remove_old_collections(output_collection)
    bpy.context.view_layer.update()

    after_payload, after_hash = scene_signature()
    if before_payload != after_payload or before_hash != after_hash:
        changed = sorted(name for name in before_payload if before_payload[name] != after_payload.get(name))
        raise RuntimeError(f"组织过程中模型或变换发生变化: {changed[:20]}")

    if len(packages) != 76:
        raise RuntimeError(f"资产包数量异常，预期 76，实际 {len(packages)}")
    if any(len(collection.objects) == 0 for collection in packages.values()):
        empty = [collection.name for collection in packages.values() if len(collection.objects) == 0]
        raise RuntimeError(f"存在空资产包: {empty}")

    catalog = write_catalog(packages, before_hash, after_hash)
    bpy.context.scene["base_facility_asset_id"] = "ENV-BASE99-ART-LAYOUT-3D"
    bpy.context.scene["base_facility_revision"] = "v007"
    bpy.context.scene["base_facility_change_scope"] = "collection_and_folder_organization_only"
    bpy.context.scene["base_facility_package_count"] = len(packages)
    bpy.context.scene["base_facility_floor_tile_package_count"] = 36

    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND), check_existing=False)
    render_preview("基地微缩模型_英雄相机", HERO_RENDER)
    render_preview("基地微缩模型_顶视相机", TOP_RENDER)
    bpy.context.scene.camera = bpy.data.objects["基地微缩模型_英雄相机"]
    bpy.context.scene.render.filepath = str(HERO_RENDER)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND), check_existing=False)

    print("=== BASE FACILITY V007 ORGANIZATION COMPLETE ===")
    print(f"output_blend={OUTPUT_BLEND}")
    print(f"package_count={catalog['package_count']}")
    print(f"floor_tile_package_count={catalog['floor_tile_package_count']}")
    print(f"candidate_objects={len(candidates)}")
    print(f"scene_signature={after_hash}")
    print(f"signature_match={before_hash == after_hash}")
    print(f"catalog={CATALOG_JSON}")
    print(f"tree={TREE_TXT}")


if __name__ == "__main__":
    main()
