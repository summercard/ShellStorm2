"""Reopen and audit the saved Battle level 01 v003 Blender files.

Run with:
    blender --background --python scripts/blender/audit_battle_level01_whitebox_v003.py
"""

from __future__ import annotations

import json
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
VERSION = "v003"
PACKAGE_DIR = (
    ROOT
    / "source/art/whitebox/tower_zones/battle_level01"
    / VERSION
    / "data/component_packages"
)
BASELINE_PACKAGE_DIR = (
    ROOT
    / "source/art/whitebox/tower_zones/battle_level01/v002/data/component_packages"
)
REPORT_PATH = (
    ROOT
    / "source/art/whitebox/tower_zones/battle_level01"
    / VERSION
    / "data/validation/blender_file_audit.json"
)
TOLERANCE_M = 0.011


def rounded(values: Vector) -> list[float]:
    return [round(float(value), 4) for value in values]


def object_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return (
        Vector(
            (
                min(point.x for point in points),
                min(point.y for point in points),
                min(point.z for point in points),
            )
        ),
        Vector(
            (
                max(point.x for point in points),
                max(point.y for point in points),
                max(point.z for point in points),
            )
        ),
    )


def close_vector(left: list[float], right: list[float]) -> bool:
    return all(abs(float(a) - float(b)) <= TOLERANCE_M for a, b in zip(left, right))


def descendant_collection_names(root: bpy.types.Collection) -> set[str]:
    names: set[str] = set()
    stack = list(root.children)
    while stack:
        collection = stack.pop()
        names.add(collection.name)
        stack.extend(collection.children)
    return names


def audit_manifest(manifest_path: Path) -> dict[str, object]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    baseline_matches = list(BASELINE_PACKAGE_DIR.glob(f"**/{manifest['slug']}/asset_manifest.json"))
    baseline = json.loads(baseline_matches[0].read_text(encoding="utf-8")) if baseline_matches else None
    blend_path = ROOT / str(manifest["source_blend"])
    bpy.ops.wm.open_mainfile(filepath=str(blend_path))

    failures: list[str] = []
    root = bpy.data.collections.get(str(manifest["blender_collection"]))
    if root is None:
        return {
            "asset_id": manifest["asset_id"],
            "blend": str(blend_path.relative_to(ROOT)).replace("\\", "/"),
            "status": "FAIL",
            "failures": ["缺少顶层资产管理集合"],
        }

    source = root.children.get(str(manifest["authoring_collection"]))
    output = root.children.get(str(manifest["output_collection"]))
    if source is None:
        failures.append("缺少制作组件集合")
    if output is None:
        failures.append("缺少游戏输出独立资产包集合")
    if source is not None and (not source.hide_viewport or not source.hide_render):
        failures.append("制作组件集合未默认隐藏")
    if output is not None and (output.hide_viewport or output.hide_render):
        failures.append("游戏输出集合未默认显示")
    if source is None or output is None:
        return {
            "asset_id": manifest["asset_id"],
            "blend": str(blend_path.relative_to(ROOT)).replace("\\", "/"),
            "status": "FAIL",
            "failures": failures,
        }

    output_descendants = descendant_collection_names(output)
    expected_names = [str(name) for name in manifest["objects"]]
    actual_output_objects = [
        obj
        for obj in bpy.data.objects
        if obj.type == "MESH"
        and obj.users_collection
        and obj.users_collection[0].name in output_descendants
    ]
    actual_names = sorted(obj.name for obj in actual_output_objects)
    if actual_names != sorted(expected_names):
        failures.append("输出对象清单与 manifest 不一致")
    if any(name.endswith("_主体") for name in actual_names):
        failures.append("存在合并主体对象")

    source_meshes = [
        obj
        for obj in bpy.data.objects
        if obj.type == "MESH" and obj.name.startswith("AP_")
    ]
    if len(source_meshes) != int(manifest["component_count"]):
        failures.append("制作组件数量与输出组件数量不一致")

    for component in manifest["components"]:
        name = str(component["name"])
        obj = bpy.data.objects.get(name)
        if obj is None:
            failures.append(f"缺少输出对象: {name}")
            continue
        if len(obj.users_collection) != 1:
            failures.append(f"{name} 不属于唯一末级集合")
        elif obj.users_collection[0].name != component["collection"]:
            failures.append(f"{name} 集合归属错误")
        if not close_vector(list(obj.location), list(component["origin_world_m"])):
            failures.append(f"{name} 原点错误")
        if not close_vector(list(obj.dimensions), list(component["dimensions_m"])):
            failures.append(f"{name} 尺寸错误")
        min_corner, max_corner = object_bounds(obj)
        expected_min = list(component["bounds_world_m"]["min"])
        expected_max = list(component["bounds_world_m"]["max"])
        if not close_vector(list(min_corner), expected_min):
            failures.append(f"{name} 最小包络错误")
        if not close_vector(list(max_corner), expected_max):
            failures.append(f"{name} 最大包络错误")
        if any(abs(float(value) - 1.0) > 0.0001 for value in obj.scale):
            failures.append(f"{name} Scale不是1")
        if component["kind"] in {"wall", "door_wall"}:
            horizontal_length = max(float(obj.dimensions.x), float(obj.dimensions.y))
            if horizontal_length > 5.001:
                failures.append(f"{name} 超过5m模块长度")

    if manifest["category"] != "corridors":
        wall_components = [
            component for component in manifest["components"]
            if component["kind"] in {"wall", "door_wall"}
        ]
        missing_slot_metadata = [
            component["name"] for component in wall_components
            if component.get("wall_module_type") not in {"solid_5m", "door_5m", "trim_fixed"}
        ]
        if missing_slot_metadata:
            failures.append(f"墙体缺少5m槽位元数据: {missing_slot_metadata}")
        door_groups: dict[tuple[str, int], list[dict[str, object]]] = {}
        for component in wall_components:
            if component.get("wall_module_type") != "door_5m":
                continue
            side = str(component["name"]).split("_")[1]
            key = (side, int(component["wall_slot_index"]))
            door_groups.setdefault(key, []).append(component)
        bad_door_groups = [key for key, parts in door_groups.items() if len(parts) != 3]
        if bad_door_groups:
            failures.append(f"带门墙槽不是左右柱+门楣三件: {bad_door_groups}")
        expected_ports = sorted(
            (str(port["side"]).upper(), round(float(port["offset_m"]), 4), str(port["target"]))
            for port in manifest["ports"]
        )
        actual_ports = sorted(
            (
                str(component["name"]).split("_")[1],
                round(float(component["wall_slot_center_m"]), 4),
                str(component["door_target"]),
            )
            for component in wall_components
            if component.get("wall_module_type") == "door_5m"
            and str(component["name"]).endswith("_LINTEL")
        )
        if actual_ports != expected_ports:
            failures.append(f"门墙槽中心或目标改变: expected={expected_ports}, actual={actual_ports}")

    if baseline is None:
        failures.append("缺少v002基线manifest")
    else:
        if manifest["dimensions_m"] != baseline["dimensions_m"]:
            failures.append("资产总尺寸偏离v002基线")
        if manifest["ports"] != baseline["ports"]:
            failures.append("门口端口偏离v002基线")
        baseline_floor = {
            component["name"]: component
            for component in baseline["components"]
            if str(component["kind"]).startswith("floor")
        }
        current_floor = {
            component["name"]: component
            for component in manifest["components"]
            if str(component["kind"]).startswith("floor")
        }
        floor_signature = lambda component: (
            component["kind"], component["origin_world_m"],
            component["dimensions_m"], component["bounds_world_m"],
        )
        if set(current_floor) != set(baseline_floor) or any(
            floor_signature(current_floor[name]) != floor_signature(baseline_floor[name])
            for name in current_floor.keys() & baseline_floor.keys()
        ):
            failures.append("地板组件几何或原点偏离v002锁定基线")

    return {
        "asset_id": manifest["asset_id"],
        "name_zh": manifest["name_zh"],
        "blend": str(blend_path.relative_to(ROOT)).replace("\\", "/"),
        "status": "PASS" if not failures else "FAIL",
        "failures": failures,
        "source_component_count": len(source_meshes),
        "output_component_count": len(actual_output_objects),
        "root_collection": root.name,
        "authoring_collection": source.name,
        "output_collection": output.name,
    }


def main() -> None:
    manifests = sorted(PACKAGE_DIR.glob("**/asset_manifest.json"))
    results = [audit_manifest(path) for path in manifests]
    failed = [result["asset_id"] for result in results if result["status"] != "PASS"]
    report = {
        "status": "PASS" if not failed else "FAIL",
        "asset_count": len(results),
        "failed_assets": failed,
        "checks": [
            "top-level Chinese asset-management collection exists",
            "authoring and output collections use the v002 contract",
            "authoring collection is hidden and output collection is visible",
            "output object names match the manifest exactly",
            "every output object belongs to exactly one output collection",
            "each component origin, dimensions and world bounds match the manifest",
            "source and output component counts match without merged body objects",
            "all room walls carry fixed 5m slot metadata and no mesh exceeds 5m",
            "each door-wall slot contains exactly left pier, right pier and lintel",
            "door centers, targets, asset bounds and all floor components match v002",
            "all output object scales equal 1",
        ],
        "assets": results,
    }
    REPORT_PATH.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "BATTLE_LEVEL01_WHITEBOX_V003_BLEND_AUDIT",
        json.dumps(
            {
                "status": report["status"],
                "asset_count": report["asset_count"],
                "failed_assets": failed,
                "report": str(REPORT_PATH),
            },
            ensure_ascii=False,
        ),
    )
    if failed:
        raise RuntimeError(f"Blend audit failed for: {failed}")


if __name__ == "__main__":
    main()
