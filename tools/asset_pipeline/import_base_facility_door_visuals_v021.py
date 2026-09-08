"""Integrate the v021 shared Base99 door visuals without changing door gameplay.

The four authored Blender packages represent two reusable visual contracts:
east/west wall-door modules share one wall visual and east/west lift doors share
one door-leaf visual.  Existing RoomDoor3D and DungeonRoom3D instances retain
all collision, triggers, save IDs, interaction and movement behaviour.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[2]
EXPORT = PROJECT / "source/art/blender/base_facility_layout/export/v021/door_visuals_export_manifest.json"
RUNTIME = PROJECT / "assets/art/environments/base_facility_3d/runtime"
COMPONENTS = PROJECT / "assets/art/environments/base_facility_3d/components"
SOURCE = PROJECT / "source/art/blender/base_facility_layout/component_packages"
LEDGER = PROJECT / "assets/art/environments/base_facility_3d/source/env_base99_door_visuals_v021_import_manifest.json"
GLOBAL_LEDGER = PROJECT / "assets/art/asset_import_manifest_v001.json"
POST_IMPORT = "res://tools/asset_pipeline/scene_facility_door_visual_post_import.gd"

VISUALS = {
    "wall_door": {
        "asset_id": "ENV-BASE99-WALL-DOOR-5X9",
        "glb": COMPONENTS / "env_base99_wall_door_5x9/env_base99_wall_door_5x9_visual_top3d_v002.glb",
        "old_root": RUNTIME / "env_base99_wall_door_5x9/env_base99_wall_door_5x9_root_top3d_v001.tscn",
        "new_root": RUNTIME / "env_base99_wall_door_5x9/env_base99_wall_door_5x9_root_top3d_v002.tscn",
        "runtime_owner": "DungeonRoom3D + RoomDoor3D",
        "packages": [
            ("architecture/west_door_wall_module", "114_西墙带门墙模块_资产包"),
            ("architecture/east_door_wall_module", "12_东墙带门墙模块_资产包"),
        ],
    },
    "door_lift": {
        "asset_id": "ENV-BASE99-DOOR-LIFT-22X25",
        "glb": COMPONENTS / "env_base99_door_lift_2p2x2p5/env_base99_door_lift_2p2x2p5_visual_top3d_v002.glb",
        "old_root": RUNTIME / "env_base99_door_lift_2p2x2p5/env_base99_door_lift_2p2x2p5_root_top3d_v001.tscn",
        "new_root": RUNTIME / "env_base99_door_lift_2p2x2p5/env_base99_door_lift_2p2x2p5_root_top3d_v002.tscn",
        "runtime_owner": "RoomDoor3D",
        "packages": [
            ("west_facilities/west_door_lift_instance", "115_西侧滑升门运行时实例_资产包"),
            ("east_facilities/east_personnel_security_door", "71_正式人员安全门_资产包"),
        ],
    },
}


def rel(path: Path) -> str:
    return str(path.relative_to(PROJECT)).replace("\\", "/")


def res(path: Path) -> str:
    return "res://" + rel(path)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def configure_glb_import(glb: Path) -> None:
    contract = Path(str(glb) + ".import")
    if not contract.is_file():
        raise RuntimeError(f"Godot import contract missing: {contract}")
    text = contract.read_text(encoding="utf-8")
    text = text.replace('import_script/path=""', f'import_script/path="{POST_IMPORT}"')
    text = text.replace(
        'import_script/path="res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"',
        f'import_script/path="{POST_IMPORT}"',
    )
    text = text.replace("gltf/embedded_image_handling=1", "gltf/embedded_image_handling=0")
    contract.write_text(text, encoding="utf-8")


def write_visual_root(spec: dict) -> None:
    text = spec["old_root"].read_text(encoding="utf-8")
    old_glb = "_v001.glb"
    if old_glb not in text:
        raise RuntimeError(f"Unexpected root contract: {spec['old_root']}")
    text = text.replace(old_glb, "_v002.glb")
    text = text.replace(
        'metadata/source_blend = "res://assets/art/environments/base_facility_3d/source/env_base99_modular_room/env_base99_modular_room_assets_clean_v001.blend"',
        'metadata/source_blend = "res://source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v021.blend"\n'
        'metadata/derived_blend = "res://source/art/blender/base_facility_layout/export/v021/base_facility_runtime_layout_hq-v021-door_visuals.blend"\n'
        'metadata/visual_revision = "v021_shared_east_west_door_visuals"',
    )
    spec["new_root"].write_text(text, encoding="utf-8")


def update_runtime_references() -> None:
    files = [
        PROJECT / "src/world3d/DungeonRoom3D.gd",
        PROJECT / "src/world3d/TowerDescent3D.gd",
        RUNTIME / "env_base100_upper_shell_30x30_h9/env_base100_upper_shell_30x30_h9_root_top3d_v001.tscn",
    ]
    for path in files:
        text = path.read_text(encoding="utf-8")
        if "env_base99_door_lift_2p2x2p5" in text:
            text = text.replace("env_base99_door_lift_2p2x2p5_root_top3d_v001.tscn", "env_base99_door_lift_2p2x2p5_root_top3d_v002.tscn")
        if "env_base99_wall_door_5x9" in text:
            text = text.replace("env_base99_wall_door_5x9_root_top3d_v001.tscn", "env_base99_wall_door_5x9_root_top3d_v002.tscn")
        path.write_text(text, encoding="utf-8")


def update_package_manifest(relative_dir: str, collection: str, visual_key: str) -> dict:
    path = SOURCE / relative_dir / "asset_manifest.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    spec = VISUALS[visual_key]
    data.update({
        "asset_id": spec["asset_id"],
        "version": "v021",
        "source_blend": "source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v021.blend",
        "expected_export": rel(spec["glb"]),
        "export_status": "exported_v021_shared_visual",
        "runtime_prefab": rel(spec["new_root"]),
        "runtime_visual_glb": rel(spec["glb"]),
        "runtime_owner": spec["runtime_owner"],
        "godot_import_manifest": rel(LEDGER),
        "visual_revision": "v021_shared_east_west_door_visuals",
        "shared_runtime_visual_contract": "East and west authored packages share this visual AssetID; only the existing runtime prefab is replaced.",
    })
    data["display_name"] = collection
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {"slug": data["asset_slug"], "collection": collection, "asset_id": spec["asset_id"], "shared_visual_key": visual_key,
            "asset_manifest": rel(path), "runtime_prefab": rel(spec["new_root"]), "runtime_visual_glb": rel(spec["glb"]),
            "runtime_owner": spec["runtime_owner"]}


def update_assembly(relative_path: str) -> None:
    path = SOURCE / relative_path
    data = json.loads(path.read_text(encoding="utf-8"))
    data["version"] = "v021"
    data["source_blend"] = "source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v021.blend"
    data["derived_blend"] = "source/art/blender/base_facility_layout/export/v021/base_facility_runtime_layout_hq-v021-door_visuals.blend"
    data["visual_revision"] = "v021_shared_east_west_door_visuals"
    for member in data.get("members", []):
        if member.get("asset_id") == VISUALS["wall_door"]["asset_id"]:
            member["runtime_prefab"] = rel(VISUALS["wall_door"]["new_root"])
        elif member.get("asset_id") == VISUALS["door_lift"]["asset_id"]:
            member["runtime_prefab"] = rel(VISUALS["door_lift"]["new_root"])
    data["direct_replacement_contract"] = "v021只替换两个既有共享视觉GLB和对应视觉Prefab；保留既有PackedScene根、AssetID、方向、碰撞、RoomDoor3D/DungeonRoom3D脚本、触发与存档职责。"
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_ledgers(export_data: dict, packages: list[dict]) -> None:
    data = {
        "asset_id": "ENV-BASE99-DOOR-VISUALS-V021",
        "version": "v021",
        "source_blend": export_data["source_blend"],
        "source_blend_sha256": export_data["source_blend_sha256"],
        "blender_export_manifest": rel(EXPORT),
        "derived_blend": export_data["derived_blend"],
        "shared_visuals": {
            key: {"asset_id": spec["asset_id"], "visual_glb": rel(spec["glb"]), "visual_glb_sha256": sha(spec["glb"]),
                  "runtime_prefab": rel(spec["new_root"]), "runtime_owner": spec["runtime_owner"],
                  "collision_policy": "preserved_by_existing_runtime_owner"}
            for key, spec in VISUALS.items()
        },
        "package_count": 4,
        "packages": packages,
        "function_preservation": "Only ext_resource references changed. RoomDoor3D/DungeonRoom3D interaction, collision, trigger, save and placement behaviour remains in existing runtime owners.",
    }
    LEDGER.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    global_data = json.loads(GLOBAL_LEDGER.read_text(encoding="utf-8"))
    global_data["base_facility_door_visuals_v021"] = {
        "asset_id": data["asset_id"], "version": "v021", "package_count": 4,
        "import_ledger": rel(LEDGER), "source_blend": data["source_blend"],
        "runtime_roots": {key: rel(spec["new_root"]) for key, spec in VISUALS.items()},
    }
    GLOBAL_LEDGER.write_text(json.dumps(global_data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    export_data = json.loads(EXPORT.read_text(encoding="utf-8"))
    if export_data.get("version") != "v021" or len(export_data.get("packages", [])) != 4:
        raise RuntimeError("Expected exactly four v021 door package exports")
    for spec in VISUALS.values():
        if not spec["glb"].is_file():
            raise RuntimeError(f"Missing Blender GLB: {spec['glb']}")
        configure_glb_import(spec["glb"])
        write_visual_root(spec)
    update_runtime_references()
    packages = []
    for key, spec in VISUALS.items():
        for relative_dir, collection in spec["packages"]:
            packages.append(update_package_manifest(relative_dir, collection, key))
    update_assembly("component_sets/west_door_wall_set/assembly_manifest.json")
    update_assembly("component_sets/east_door_wall_set/assembly_manifest.json")
    write_ledgers(export_data, packages)
    print("BASE99_DOOR_VISUALS_V021_INTEGRATED: packages=4 shared_visuals=2")


if __name__ == "__main__":
    main()
