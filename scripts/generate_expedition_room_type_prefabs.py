from __future__ import annotations

import json
from pathlib import Path


LIBRARIES = (
    ("office_room", "v006"),
    ("bridge_room", "v007"),
)
CATALOG_PATH = Path(
    "assets/art/environments/tower_zones/shared/runtime/shell_component_catalog.json"
)
RUNTIME_ROOT = Path(
    "assets/art/environments/tower_zones/expedition/runtime/room_type_components"
)
COMPONENT_ROOT = Path(
    "assets/art/environments/tower_zones/expedition/components/room_type_components"
)
SOURCE_ROOT = Path(
    "assets/art/environments/tower_zones/expedition/source/common_components"
)
IMPORT_SCRIPT = (
    "res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"
)

OFFICE_BOX_COLLISION = {
    "filing_run",
    "locker_bank",
    "power_cabinet_bank",
    "prep_bench",
    "printer_station",
    "shelving",
    "totem_column",
    "water_and_supply_corner",
    "work_cluster",
}
BRIDGE_BOX_COLLISION = {
    "bank_crate",
    "bridge_guardrail",
    "end_crate",
    "end_power",
    "half_partition",
    "lower_control",
    "near_crate",
    "near_server",
    "partition_box",
    "pit_end",
    "pit_side",
    "platform_edge",
    "shaft_column",
    "upper_bank_z5450",
    "upper_bank_z6197",
    "upper_console",
    "vertical_service",
}


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_text_crlf(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    path.write_bytes(normalized.replace("\n", "\r\n").encode("utf-8"))


def write_json_crlf(path: Path, data: dict) -> None:
    write_text_crlf(path, json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def godot_bounds(bounds: list[float]) -> list[float]:
    return [float(bounds[0]), float(bounds[2]), float(bounds[1])]


def classify(room_slug: str, slug: str) -> tuple[str, str, str]:
    if room_slug == "office_room":
        if slug == "door_wall":
            return "door_wall", "room_door_owned", "split_door_wall_proxy"
        if slug == "floor_tile_5m":
            return "floor_tile", "floor_support", "external_floor_support"
        if slug.startswith("wall_t"):
            return "solid_wall", "self", "structural_box_proxy"
        if slug in OFFICE_BOX_COLLISION:
            return "room_type_component", "self", "safe_box_proxy"
        return "room_type_component", "none", "visual_only"
    if slug == "tile_upper":
        return "floor_tile", "floor_support", "external_floor_support"
    if slug == "tile_lower":
        return "room_type_component", "none", "lower_level_visual_only"
    if slug in {"wall_x670", "wall_x780"}:
        return "solid_wall", "self", "structural_box_proxy"
    if slug in BRIDGE_BOX_COLLISION:
        return "room_type_component", "self", "safe_box_proxy"
    return "room_type_component", "none", "visual_only"


def tscn_text(
    room_slug: str,
    version: str,
    package: dict,
    slot_role: str,
    collision_owner: str,
    collision_policy: str,
) -> str:
    slug = str(package["slug"])
    component_id = str(package["component_id"])
    bounds = godot_bounds(package["bounds_size_m"])
    bx, by, bz = bounds
    visual_path = (
        f"res://{COMPONENT_ROOT.as_posix()}/{room_slug}/{slug}/"
        f"{slug}_visual_top3d.glb"
    )
    source_blend = (
        f"res://{SOURCE_ROOT.as_posix()}/{version}/component_packages/{slug}/{slug}.blend"
    )
    subresources: list[str] = []
    collision_nodes: list[str] = []
    load_steps = 2
    if collision_policy in {"safe_box_proxy", "structural_box_proxy"}:
        load_steps += 1
        subresources.extend(
            [
                '[sub_resource type="BoxShape3D" id="BoxShape3D_proxy"]',
                f"size = Vector3({bx:g}, {by:g}, {bz:g})",
                "",
            ]
        )
        collision_nodes.extend(
            [
                '[node name="CollisionBody" type="StaticBody3D" parent="."]',
                "collision_layer = 1",
                "collision_mask = 0",
                "",
                '[node name="CollisionShape" type="CollisionShape3D" parent="CollisionBody"]',
                f"position = Vector3(0, {by * 0.5:g}, 0)",
                'shape = SubResource("BoxShape3D_proxy")',
                "",
            ]
        )
    elif collision_policy == "split_door_wall_proxy":
        load_steps += 3
        jamb_width = max((bx - 2.2) * 0.5, 0.1)
        header_height = max(by - 2.5, 0.1)
        subresources.extend(
            [
                '[sub_resource type="BoxShape3D" id="BoxShape3D_jamb"]',
                f"size = Vector3({jamb_width:g}, 2.5, {bz:g})",
                "",
                '[sub_resource type="BoxShape3D" id="BoxShape3D_header"]',
                f"size = Vector3({bx:g}, {header_height:g}, {bz:g})",
                "",
            ]
        )
        jamb_x = 1.1 + jamb_width * 0.5
        collision_nodes.extend(
            [
                '[node name="CollisionBody" type="StaticBody3D" parent="."]',
                "collision_layer = 1",
                "collision_mask = 0",
                "",
                '[node name="LeftJamb" type="CollisionShape3D" parent="CollisionBody"]',
                f"position = Vector3({-jamb_x:g}, 1.25, 0)",
                'shape = SubResource("BoxShape3D_jamb")',
                "",
                '[node name="RightJamb" type="CollisionShape3D" parent="CollisionBody"]',
                f"position = Vector3({jamb_x:g}, 1.25, 0)",
                'shape = SubResource("BoxShape3D_jamb")',
                "",
                '[node name="Header" type="CollisionShape3D" parent="CollisionBody"]',
                f"position = Vector3(0, {2.5 + header_height * 0.5:g}, 0)",
                'shape = SubResource("BoxShape3D_header")',
                "",
            ]
        )
    root_name = "RoomTypeComponent" + "".join(part.title() for part in slug.split("_"))
    lines = [
        f"[gd_scene load_steps={load_steps} format=3]",
        "",
        f'; Stable AssetID: {component_id}',
        f'; 房型组件 {room_slug} / {version} / {slug}',
        f'[ext_resource type="PackedScene" path="{visual_path}" id="1_visual"]',
        "",
        *subresources,
        f'[node name="{root_name}" type="Node3D"]',
        f'metadata/asset_id = "{component_id}"',
        f'metadata/asset_version = "{version}"',
        f'metadata/room_type = "{package["room_type"]}"',
        f'metadata/component_slug = "{slug}"',
        f'metadata/display_name_zh = "{package["name_zh"]}"',
        f'metadata/source_blend = "{source_blend}"',
        'metadata/origin_contract = "bottom_center"',
        f'metadata/front_axis_blender = "{package["front_axis"]}"',
        'metadata/up_axis = "+Y"',
        f"metadata/bounds_size_m = Vector3({bx:g}, {by:g}, {bz:g})",
        f'metadata/slot_role = "{slot_role}"',
        f'metadata/collision_owner = "{collision_owner}"',
        f'metadata/collision_policy = "{collision_policy}"',
        f"metadata/collision_shape_count = {len([line for line in collision_nodes if 'type=\"CollisionShape3D\"' in line])}",
        'metadata/runtime_instantiation = "per_instance_prefab"',
        "",
        '[node name="ImportedModel" parent="." instance=ExtResource("1_visual")]',
        "",
        *collision_nodes,
    ]
    return "\n".join(lines).rstrip() + "\n"


def patch_import(path: Path) -> None:
    if not path.is_file():
        raise FileNotFoundError(path)
    text = path.read_text(encoding="utf-8")
    if 'import_script/path=""' in text:
        text = text.replace(
            'import_script/path=""', f'import_script/path="{IMPORT_SCRIPT}"'
        )
    elif "import_script/path=" not in text:
        raise RuntimeError(f"missing import_script/path in {path}")
    else:
        lines = text.splitlines()
        lines = [
            f'import_script/path="{IMPORT_SCRIPT}"'
            if line.startswith("import_script/path=")
            else line
            for line in lines
        ]
        text = "\n".join(lines) + "\n"
    text = text.replace("gltf/embedded_image_handling=1", "gltf/embedded_image_handling=0")
    write_text_crlf(path, text)


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    runtime_catalog_path = root / CATALOG_PATH
    runtime_catalog = read_json(runtime_catalog_path)
    existing = [
        entry
        for entry in runtime_catalog.get("components", [])
        if not str(entry.get("component_id", "")).startswith(
            ("ENV-EXPEDITION-L01-OFFICE-", "ENV-EXPEDITION-L01-BRIDGE-")
        )
    ]
    generated: list[dict] = []
    manifest_records: list[dict] = []
    for room_slug, version in LIBRARIES:
        catalog_path = root / SOURCE_ROOT / version / "component_catalog.json"
        catalog = read_json(catalog_path)
        for package in catalog["packages"]:
            slug = str(package["slug"])
            component_id = str(package["component_id"])
            slot_role, collision_owner, collision_policy = classify(room_slug, slug)
            runtime_rel = RUNTIME_ROOT / room_slug / slug / f"{slug}_root_top3d.tscn"
            component_rel = COMPONENT_ROOT / room_slug / slug / f"{slug}_visual_top3d.glb"
            import_rel = Path(f"{component_rel.as_posix()}.import")
            if not (root / component_rel).is_file():
                raise FileNotFoundError(root / component_rel)
            write_text_crlf(
                root / runtime_rel,
                tscn_text(
                    room_slug,
                    version,
                    package,
                    slot_role,
                    collision_owner,
                    collision_policy,
                ),
            )
            patch_import(root / import_rel)
            bounds = godot_bounds(package["bounds_size_m"])
            entry = {
                "component_id": component_id,
                "kind": "room_type",
                "aliases": [],
                "slug": slug,
                "category": str(package["name_zh"]),
                "room_type": str(package["room_type"]),
                "slot_role": slot_role,
                "source_package_id": str(package.get("source_package_id", component_id)),
                "prefab_asset_id": component_id,
                "prefab_path": f"res://{runtime_rel.as_posix()}",
                "bounds_size_m_godot": bounds,
                "collision_owner": collision_owner,
                "collision_policy": collision_policy,
                "note": "房型组件默认布局重放；坐标由 component_instances.json 唯一提供。",
            }
            generated.append(entry)
            manifest_records.append(
                {
                    "component_id": component_id,
                    "room_type": str(package["room_type"]),
                    "version": version,
                    "slug": slug,
                    "slot_role": slot_role,
                    "collision_owner": collision_owner,
                    "collision_policy": collision_policy,
                    "bounds_size_m_godot": bounds,
                    "visual_glb": f"res://{component_rel.as_posix()}",
                    "prefab_path": f"res://{runtime_rel.as_posix()}",
                    "source_blend": (
                        f"res://{SOURCE_ROOT.as_posix()}/{version}/component_packages/"
                        f"{slug}/{slug}.blend"
                    ),
                }
            )
    ids = [str(entry["component_id"]) for entry in existing + generated]
    if len(ids) != len(set(ids)):
        raise RuntimeError("duplicate component_id after catalog merge")
    runtime_catalog["component_count"] = len(existing) + len(generated)
    runtime_catalog["room_type_sources"] = [
        f"{SOURCE_ROOT.as_posix()}/v006/component_catalog.json",
        f"{SOURCE_ROOT.as_posix()}/v007/component_catalog.json",
    ]
    runtime_catalog["components"] = existing + generated
    write_json_crlf(runtime_catalog_path, runtime_catalog)
    manifest = {
        "schema": "shellstorm2.expedition.room_type_component_runtime.v001",
        "component_count": len(manifest_records),
        "catalog_component_count": len(existing) + len(generated),
        "import_script": IMPORT_SCRIPT,
        "records": manifest_records,
    }
    write_json_crlf(root / RUNTIME_ROOT / "runtime_manifest.json", manifest)
    print(f"ROOM_TYPE_PREFABS_WRITTEN:{len(manifest_records)}")
    print(f"SHELL_COMPONENT_CATALOG_COUNT:{runtime_catalog['component_count']}")


if __name__ == "__main__":
    main()
