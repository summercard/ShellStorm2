#!/usr/bin/env python3
"""静态验收远征01低墙、远征03墙高及场景资产路由契约。"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


DEFAULT_ROOT = Path(__file__).resolve().parents[1]
CONTRACT_REL = Path("assets/registry/expedition_scene_height_contract.json")
LEVEL_SOURCE_ROOT = Path("art_source/design/whitebox/tower_zones")
LEVEL_RUNTIME_ROOT = Path("data/level_plans")
EXP01_SOURCE_PLAN = LEVEL_SOURCE_ROOT / "expedition_01" / "v001" / "data" / "level_plan.json"
EXP01_RUNTIME_PLAN = LEVEL_RUNTIME_ROOT / "expedition_01" / "level_plan.json"
EXP01_SOURCE_FLOOR = LEVEL_SOURCE_ROOT / "expedition_01" / "v001" / "data" / "floors" / "floor_00.json"
EXP01_RUNTIME_FLOOR = LEVEL_RUNTIME_ROOT / "expedition_01" / "floors" / "floor_00.json"
EXP01_SOURCE_TEMPLATE_ROOT = LEVEL_SOURCE_ROOT / "expedition_01" / "v001" / "data" / "room_templates"
EXP01_TEMPLATE_ROOT = LEVEL_RUNTIME_ROOT / "expedition_01" / "room_templates"
EXP03_SOURCE_PLAN = LEVEL_SOURCE_ROOT / "expedition_03" / "v001" / "data" / "level_plan.json"
EXP03_RUNTIME_PLAN = LEVEL_RUNTIME_ROOT / "expedition_03" / "level_plan.json"
EXP03_TEMPLATE_ROOT = LEVEL_RUNTIME_ROOT / "expedition_03" / "room_templates"
EXP03_SOURCE_TEMPLATE_ROOT = LEVEL_SOURCE_ROOT / "expedition_03" / "v001" / "data" / "room_templates"
EXP01_ROOM_ROOT = Path("assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01")
EXP01_LOW_WALL_ROOT = Path("assets/art/environments/tower_zones/expedition/runtime/expedition_01_low_h28")
EXP01_COMPONENT_CATALOG = Path("art_source/environments/tower_zones/expedition/source/expedition_01_low_h28/v001/component_catalog.json")
EXP01_BOSS_MANIFESTS = (
    Path("data/level_plans/expedition_01/component_packages/boss_arena/远征关卡01_白模_boss竞技场_50x40m/asset_manifest.json"),
    Path("art_source/design/whitebox/tower_zones/expedition_01/v001/data/component_packages/boss_arena/远征关卡01_白模_boss竞技场_50x40m/asset_manifest.json"),
)
FORBIDDEN_EXP03_TOKENS = (
    "wall_standard_5m_h12",
    "wall_door_5m_h12",
    "wall_collapse_5m_h12",
    "ENV-EXPEDITION-COMMON-WALL-STANDARD-5M-H12",
    "ENV-EXPEDITION-COMMON-WALL-DOOR-5M-H12",
    "ENV-EXPEDITION-COMMON-WALL-COLLAPSE-5M-H12",
)
MANOR_PREFABS = {
    "manor_wall_standard": "assets/art/environments/tower_zones/expedition/runtime/common_components/manor_wall_standard/env_manor_wall_standard_root_top3d.tscn",
    "manor_wall_door": "assets/art/environments/tower_zones/expedition/runtime/common_components/manor_wall_door/env_manor_wall_door_root_top3d.tscn",
    "manor_wall_window": "assets/art/environments/tower_zones/expedition/runtime/common_components/manor_wall_window/env_manor_wall_window_root_top3d.tscn",
    "manor_wall_door_boss": "assets/art/environments/tower_zones/expedition/runtime/common_components/manor_wall_door_boss/env_manor_wall_door_boss_root_top3d.tscn",
}
EXP01_FORMAL_ROOM_SCENES = {
    "entry": "f00_start_static_layout.tscn",
    **{f"room_{index:02d}": f"f00_room_{index:02d}_static_layout.tscn" for index in range(1, 11)},
    "extraction": "f00_extraction_static_layout.tscn",
}
EXPECTED_EXP01_TEMPLATES = {
    "safe_15x15.json",
    "corridor_45x40.json",
    "db_70x50.json",
    "office_60x70.json",
    "bridge_60x50.json",
    "extraction_25x25.json",
    "std_25x25.json",
}


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def fail(errors: list[str], message: str) -> None:
    errors.append(message)


def assert_close(errors: list[str], label: str, actual: float, expected: float) -> None:
    if abs(float(actual) - expected) > 1e-6:
        fail(errors, f"{label}: expected {expected}, got {actual}")


def check_level_plan_projection(errors: list[str], source: Path, runtime: Path, label: str) -> dict[str, Any] | None:
    if not source.is_file():
        fail(errors, f"missing {label} source: {source}")
        return None
    if not runtime.is_file():
        fail(errors, f"missing {label} runtime projection: {runtime}")
        return None
    source_bytes = source.read_bytes()
    runtime_bytes = runtime.read_bytes()
    if source_bytes != runtime_bytes:
        fail(errors, f"{label} source/runtime projection drift: {source} != {runtime}")
    try:
        return json.loads(source_bytes)
    except json.JSONDecodeError as exc:
        fail(errors, f"invalid JSON {label}: {source}: {exc}")
        return None


def check_json_projection(errors: list[str], source: Path, runtime: Path, label: str) -> Any | None:
    if not source.is_file() or not runtime.is_file():
        fail(errors, f"missing {label} source/runtime: {source} / {runtime}")
        return None
    if source.read_bytes() != runtime.read_bytes():
        fail(errors, f"{label} source/runtime projection drift: {source} != {runtime}")
    try:
        return load_json(source)
    except json.JSONDecodeError as exc:
        fail(errors, f"invalid JSON {label}: {source}: {exc}")
        return None


def check_exp01_templates(errors: list[str]) -> int:
    checked = 0
    non_boss_names = {path.name for path in EXP01_TEMPLATE_ROOT.glob("*.json")} - {"boss_50x40.json", "boss_deep_shaft_80x100.json"}
    if non_boss_names != EXPECTED_EXP01_TEMPLATES:
        fail(errors, f"expedition_01 must expose exactly seven non-Boss templates: {EXP01_TEMPLATE_ROOT}")
    for name in sorted(EXPECTED_EXP01_TEMPLATES):
        runtime = EXP01_TEMPLATE_ROOT / name
        source = EXP01_SOURCE_TEMPLATE_ROOT / name
        data = check_json_projection(errors, source, runtime, f"expedition_01 template {name}")
        if not isinstance(data, dict):
            continue
        checked += 1
        assert_close(errors, f"{runtime}: wall_height_m", data.get("wall_height_m", -1.0), 2.8)
        assert_close(errors, f"{runtime}: logical_wall_height_m", data.get("logical_wall_height_m", -1.0), 2.8)
        assert_close(errors, f"{runtime}: visual_wall_height_m", data.get("visual_wall_height_m", -1.0), 2.8)
        if data.get("asset_family") != "expedition_01_low_h28":
            fail(errors, f"{runtime}: asset_family must be expedition_01_low_h28")
        if not str(data.get("runtime_wall_scene_prefix", "")).endswith("expedition_01_low_h28/"):
            fail(errors, f"{runtime}: missing low-wall runtime scene prefix")
        door = data.get("door_contract", {})
        assert_close(errors, f"{runtime}: door width", door.get("width_m", -1.0), 2.2)
        assert_close(errors, f"{runtime}: door clear height", door.get("height_m", -1.0), 2.5)
        assert_close(errors, f"{runtime}: door lintel bottom", door.get("lintel_bottom_z_m", -1.0), 2.8)
    return checked


def check_exp01_floor_projection(errors: list[str]) -> tuple[int, dict[str, Any] | None]:
    floor = check_json_projection(errors, EXP01_SOURCE_FLOOR, EXP01_RUNTIME_FLOOR, "expedition_01 floor")
    if not isinstance(floor, dict):
        return 0, None
    assert_close(errors, "expedition_01 floor spacing", floor.get("wall_contract", {}).get("floor_spacing_m", -1.0), 12.0)
    assert_close(errors, "expedition_01 floor logical wall", floor.get("wall_contract", {}).get("logical_wall_height_m", -1.0), 2.8)
    assert_close(errors, "expedition_01 floor visual wall", floor.get("wall_contract", {}).get("visual_wall_height_m", -1.0), 2.8)
    if floor.get("asset_family") != "expedition_01_low_h28":
        fail(errors, "expedition_01 floor asset_family must be expedition_01_low_h28")
    preserved = floor.get("preserved_exceptions", {})
    if preserved.get("room_08_internal_barrier_count") != 15:
        fail(errors, "expedition_01 floor must declare 15 preserved room_08 internal barriers")
    if preserved.get("room_08_internal_barrier_collision_preserved") is not True:
        fail(errors, "expedition_01 floor must preserve room_08 internal barrier collision")
    curtain = floor.get("room_view_curtain", {})
    for key in ("enabled",):
        if curtain.get(key) is not True:
            fail(errors, f"expedition_01 floor room_view_curtain.{key} must be true")
    for key in ("collision", "shadow", "projection"):
        if curtain.get(key) is not False:
            fail(errors, f"expedition_01 floor room_view_curtain.{key} must be false")
    rooms = {room.get("key"): room for room in floor.get("rooms", []) if isinstance(room, dict)}
    expected_keys = set(EXP01_FORMAL_ROOM_SCENES) | {"boss"}
    if set(rooms) != expected_keys:
        fail(errors, f"expedition_01 floor room keys changed: expected {sorted(expected_keys)}, got {sorted(rooms)}")
    return len(EXP01_FORMAL_ROOM_SCENES), floor


def check_exp01_scene_instances(errors: list[str], floor: dict[str, Any] | None) -> int:
    checked = 0
    for room_key, scene_name in EXP01_FORMAL_ROOM_SCENES.items():
        path = DEFAULT_ROOT / EXP01_ROOM_ROOT / scene_name
        if not path.is_file():
            fail(errors, f"missing expedition_01 formal non-Boss scene ({room_key}): {path}")
            continue
        checked += 1
        text = path.read_text(encoding="utf-8", errors="replace")
        if not re.search(r"metadata/room_wall_height_m\s*=\s*2\.8(?:\s|$)", text):
            fail(errors, f"{path}: missing root metadata room_wall_height_m=2.8")
        if room_key != "entry" and "runtime/expedition_01_low_h28/" not in text:
            fail(errors, f"{path}: missing expedition_01_low_h28 wall prefab reference")
        if room_key == "room_08":
            enclosure_count = len(re.findall(r"\[node name=\"EquipmentEnclosure_[^\"]+\"", text))
            if enclosure_count != 15:
                fail(errors, f"{path}: expected 15 preserved room_08 internal barriers, got {enclosure_count}")
            if 'id="enclosure_wall"' not in text or "wall_standard_5m_root_top3d.tscn" not in text:
                fail(errors, f"{path}: room_08 internal barrier collision source was not preserved")
    if floor is not None:
        rooms = {room.get("key"): room for room in floor.get("rooms", []) if isinstance(room, dict)}
        if rooms.get("boss", {}).get("template_id") != "boss_deep_shaft_80x100":
            fail(errors, "expedition_01 boss deep-shaft template was not preserved")
        if rooms.get("room_05", {}).get("template_id") != "bridge_60x50":
            fail(errors, "expedition_01 bridge template was not preserved")
        for room_key in EXP01_FORMAL_ROOM_SCENES:
            if room_key not in rooms:
                continue
            for port in rooms[room_key].get("connection_ports", []):
                if "position_m" not in port or "target" not in port:
                    fail(errors, f"expedition_01 {room_key}: original door/port contract is incomplete")
    return checked


def check_low_wall_prefabs(errors: list[str]) -> int:
    catalog_path = DEFAULT_ROOT / EXP01_COMPONENT_CATALOG
    if not catalog_path.is_file():
        fail(errors, f"missing low-wall component catalog: {catalog_path}")
        return 0
    try:
        catalog = load_json(catalog_path)
    except json.JSONDecodeError as exc:
        fail(errors, f"invalid low-wall component catalog: {exc}")
        return 0
    expected_slugs = {item.get("slug") for item in catalog if isinstance(item, dict)}
    checked = 0
    for item in catalog:
        if not isinstance(item, dict):
            continue
        prefab = item.get("prefab_path", "")
        path = DEFAULT_ROOT / prefab
        if not path.is_file():
            fail(errors, f"missing low-wall prefab: {path}")
            continue
        checked += 1
        if not str(prefab).startswith(EXP01_LOW_WALL_ROOT.as_posix() + "/") or not str(prefab).endswith("_h28_root_top3d.tscn"):
            fail(errors, f"low-wall prefab violates common prefix/suffix: {prefab}")
        text = path.read_text(encoding="utf-8", errors="replace")
        for token in ("metadata/asset_family = \"expedition_01_low_h28\"", "metadata/wall_visual_height_m = 2.8", "metadata/wall_logical_height_m = 2.8"):
            if token not in text:
                fail(errors, f"{path}: missing {token}")
        if item.get("slug") in {"wall_door_5m_h28", "door_wall_h28"}:
            if "metadata/door_clear_width_m = 2.2" not in text or "metadata/door_clear_height_m = 2.5" not in text:
                fail(errors, f"{path}: missing 2.2x2.5 door contract")
    if len(expected_slugs) != 11:
        fail(errors, f"low-wall component catalog expected 11 entries, got {len(expected_slugs)}")
    return checked


def check_manifest_contract(errors: list[str]) -> int:
    checked = 0
    for path in EXP01_BOSS_MANIFESTS:
        manifest = load_json(path) if path.is_file() else None
        if not isinstance(manifest, dict):
            fail(errors, f"missing or invalid Boss manifest: {path}")
            continue
        checked += 1
        low = manifest.get("non_boss_wall_contract", {})
        if low.get("asset_family") != "expedition_01_low_h28":
            fail(errors, f"{path}: missing non-Boss low-wall family")
        if low.get("runtime_scene_suffix") != "_h28_root_top3d.tscn":
            fail(errors, f"{path}: missing low-wall scene suffix")
        boss = manifest.get("boss_exception", {})
        if boss.get("preserve") is not True or boss.get("room_template") != "boss_deep_shaft_80x100":
            fail(errors, f"{path}: Boss deep-shaft exception not preserved")
    return checked


def scan_json_text(root: Path, tokens: tuple[str, ...]) -> list[str]:
    hits: list[str] = []
    if not root.is_dir():
        return hits
    for path in sorted(root.rglob("*.json")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for token in tokens:
            if token in text:
                hits.append(f"{path.as_posix()} contains {token}")
    return hits


def check_exp03_templates(errors: list[str]) -> int:
    count = 0
    if not EXP03_TEMPLATE_ROOT.is_dir():
        fail(errors, f"missing expedition_03 runtime template root: {EXP03_TEMPLATE_ROOT}")
        return count
    for path in sorted(EXP03_TEMPLATE_ROOT.glob("*.json")):
        count += 1
        try:
            data = load_json(path)
        except json.JSONDecodeError as exc:
            fail(errors, f"invalid expedition_03 template JSON {path}: {exc}")
            continue
        assert_close(errors, f"{path}: wall_height_m", data.get("wall_height_m", -1.0), 2.8)
        door_contract = data.get("door_contract", {})
        assert_close(errors, f"{path}: door_contract.lintel_bottom_z_m", door_contract.get("lintel_bottom_z_m", -1.0), 2.8)
        text = path.read_text(encoding="utf-8")
        if any(token in text for token in FORBIDDEN_EXP03_TOKENS):
            fail(errors, f"{path}: contains forbidden expedition_01 h12 family")
    if EXP03_SOURCE_TEMPLATE_ROOT.is_dir():
        for path in sorted(EXP03_SOURCE_TEMPLATE_ROOT.glob("*.json")):
            runtime = EXP03_TEMPLATE_ROOT / path.name
            if runtime.is_file() and runtime.read_bytes() != path.read_bytes():
                fail(errors, f"expedition_03 template source/runtime projection drift: {path} != {runtime}")
    return count


def check_manor_prefabs(root: Path, errors: list[str]) -> int:
    checked = 0
    vector_y = re.compile(r"Vector3\([^,]+,\s*2\.8(?:,|\))")
    for family, relative in MANOR_PREFABS.items():
        path = root / relative
        if not path.is_file():
            fail(errors, f"missing expedition_03 manor prefab ({family}): {path}")
            continue
        checked += 1
        text = path.read_text(encoding="utf-8", errors="replace")
        if not vector_y.search(text):
            fail(errors, f"{path}: no Vector3 height of 2.8m found")
        if "11.9" in text:
            fail(errors, f"{path}: contains forbidden 11.9m height")
    return checked


def main() -> int:
    global DEFAULT_ROOT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=DEFAULT_ROOT)
    args = parser.parse_args()
    DEFAULT_ROOT = args.project_root.resolve()
    errors: list[str] = []

    contract_path = DEFAULT_ROOT / CONTRACT_REL
    try:
        contract = load_json(contract_path)
    except (FileNotFoundError, json.JSONDecodeError) as exc:
        fail(errors, f"invalid or missing machine contract {contract_path}: {exc}")
        contract = {}

    exp01_source = check_level_plan_projection(errors, DEFAULT_ROOT / EXP01_SOURCE_PLAN, DEFAULT_ROOT / EXP01_RUNTIME_PLAN, "expedition_01 level_plan")
    exp03_source = check_level_plan_projection(errors, DEFAULT_ROOT / EXP03_SOURCE_PLAN, DEFAULT_ROOT / EXP03_RUNTIME_PLAN, "expedition_03 level_plan")
    if exp01_source is not None:
        assert_close(errors, "expedition_01 floor_spacing_m", exp01_source.get("floor_spacing_m", -1.0), 12.0)
        assert_close(errors, "expedition_01 logical_wall_height_m", exp01_source.get("logical_wall_height_m", -1.0), 2.8)
        assert_close(errors, "expedition_01 visible_wall_height_m", exp01_source.get("visible_wall_height_m", -1.0), 2.8)
        if exp01_source.get("asset_family") != "expedition_01_low_h28":
            fail(errors, "expedition_01 level_plan asset_family must be expedition_01_low_h28")
    if exp03_source is not None:
        assert_close(errors, "expedition_03 floor_height_m", exp03_source.get("floor_height_m", -1.0), 12.0)
        assert_close(errors, "expedition_03 visible_wall_height_m", exp03_source.get("visible_wall_height_m", -1.0), 2.8)
        assert_close(errors, "expedition_03 wall_thickness_m", exp03_source.get("wall_thickness_m", -1.0), 0.3)

    formal_count, exp01_floor = check_exp01_floor_projection(errors)
    exp01_template_count = check_exp01_templates(errors)
    exp01_scene_count = check_exp01_scene_instances(errors, exp01_floor)
    low_wall_prefab_count = check_low_wall_prefabs(errors)
    manifest_count = check_manifest_contract(errors)
    exp03_template_count = check_exp03_templates(errors)
    forbidden_hits = scan_json_text(DEFAULT_ROOT / LEVEL_RUNTIME_ROOT / "expedition_03", FORBIDDEN_EXP03_TOKENS)
    for hit in forbidden_hits:
        fail(errors, hit)
    manor_prefab_count = check_manor_prefabs(DEFAULT_ROOT, errors)

    contracts = {item.get("contract_id"): item for item in contract.get("contracts", []) if isinstance(item, dict)}
    low_contract = contracts.get("expedition_01_low_h28", {})
    legacy_contract = contracts.get("expedition_tower_h12_legacy", {})
    if low_contract.get("asset_family") != "expedition_01_low_h28":
        fail(errors, "machine contract missing expedition_01_low_h28")
    if low_contract.get("formal_non_boss_layouts", {}).get("expected_count") != 12:
        fail(errors, "machine contract must require 12 expedition_01 non-Boss formal layouts")
    if legacy_contract.get("asset_family") != "tower_h12":
        fail(errors, "machine contract missing legacy tower_h12 contract")
    if contracts.get("expedition_03_manor_h28", {}).get("asset_family") != "manor_h28":
        fail(errors, "machine contract missing expedition_03_manor_h28")
    if low_contract.get("asset_family") == contracts.get("expedition_03_manor_h28", {}).get("asset_family"):
        fail(errors, "expedition_01 and expedition_03 asset families must differ")

    result = {
        "contract": CONTRACT_REL.as_posix(),
        "expedition_01_formal_non_boss_layouts_checked": exp01_scene_count,
        "expedition_01_formal_non_boss_layouts_expected": formal_count,
        "expedition_01_templates_checked": exp01_template_count,
        "expedition_01_low_wall_prefabs_checked": low_wall_prefab_count,
        "expedition_01_boss_manifests_checked": manifest_count,
        "expedition_03_templates_checked": exp03_template_count,
        "manor_prefabs_checked": manor_prefab_count,
        "forbidden_exp03_h12_hits": len(forbidden_hits),
        "errors": errors,
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if errors:
        print("EXPEDITION_SCENE_HEIGHT_CONTRACT_FAIL", file=sys.stderr)
        return 1
    print("EXPEDITION_SCENE_HEIGHT_CONTRACT_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
