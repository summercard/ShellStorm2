"""Record the v025 palette-only door-wall replacement in project ledgers."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GLB = "assets/art/environments/base_facility_3d/components/env_base99_wall_door_5x9/env_base99_wall_door_5x9_visual_top3d_v003.glb"
RUNTIME = "assets/art/environments/base_facility_3d/runtime/env_base99_wall_door_5x9/env_base99_wall_door_5x9_root_top3d_v003.tscn"
SOURCE = "source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v025.blend"
DERIVED = "source/art/blender/base_facility_layout/export/v025/base_facility_runtime_layout_hq-v025-door_wall_palette.blend"
EXPORT = "source/art/blender/base_facility_layout/export/v025/door_wall_palette_export_manifest.json"


def write(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    glb_sha = hashlib.sha256((ROOT / GLB).read_bytes()).hexdigest()
    export = json.loads((ROOT / EXPORT).read_text(encoding="utf-8"))
    ledger_path = ROOT / "assets/art/environments/base_facility_3d/source/env_base99_door_wall_palette_v025_import_manifest.json"
    ledger = {
        "asset_id": "ENV-BASE99-WALL-DOOR-5X9",
        "version": "v025",
        "source_blend": SOURCE,
        "derived_blend": DERIVED,
        "blender_export_manifest": EXPORT,
        "visual_glb": GLB,
        "visual_glb_sha256": glb_sha,
        "runtime_prefab": RUNTIME,
        "runtime_owner": "DungeonRoom3D + RoomDoor3D",
        "palette_uv_change": export["palette_uv_change"],
        "collision_policy": "unchanged; owned by DungeonRoom3D + RoomDoor3D",
        "shared_runtime_visual_contract": "East and west instances use the same v003 visual.",
    }
    write(ledger_path, ledger)
    for relative in (
        "source/art/blender/base_facility_layout/component_packages/architecture/west_door_wall_module/asset_manifest.json",
        "source/art/blender/base_facility_layout/component_packages/architecture/east_door_wall_module/asset_manifest.json",
    ):
        path = ROOT / relative
        data = json.loads(path.read_text(encoding="utf-8"))
        data.update({"version": "v025", "source_blend": SOURCE, "derived_blend": DERIVED,
                     "expected_export": GLB, "runtime_visual_glb": GLB, "runtime_prefab": RUNTIME,
                     "godot_import_manifest": str(ledger_path.relative_to(ROOT)),
                     "visual_revision": "v025_plain_wall_panel_palette"})
        write(path, data)
    for relative in (
        "source/art/blender/base_facility_layout/component_packages/component_sets/west_door_wall_set/assembly_manifest.json",
        "source/art/blender/base_facility_layout/component_packages/component_sets/east_door_wall_set/assembly_manifest.json",
    ):
        path = ROOT / relative
        data = json.loads(path.read_text(encoding="utf-8"))
        data.update({"version": "v025", "source_blend": SOURCE, "derived_blend": DERIVED,
                     "visual_revision": "v025_plain_wall_panel_palette"})
        for member in data.get("members", []):
            if member.get("asset_id") == "ENV-BASE99-WALL-DOOR-5X9":
                member["runtime_prefab"] = RUNTIME
        write(path, data)
    global_path = ROOT / "assets/art/asset_import_manifest_v001.json"
    global_data = json.loads(global_path.read_text(encoding="utf-8"))
    global_data["base99_door_wall_palette_v025"] = {"asset_id": "ENV-BASE99-WALL-DOOR-5X9", "source": SOURCE,
        "derived_export": DERIVED, "glb": GLB, "runtime_scene": RUNTIME, "import_ledger": str(ledger_path.relative_to(ROOT)),
        "scope": "Shared east/west Base99 door-wall visual; PaletteUV only."}
    write(global_path, global_data)
    print("BASE99_DOOR_WALL_V025_IMPORTED")


if __name__ == "__main__":
    main()
