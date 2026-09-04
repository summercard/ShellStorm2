"""Export the full v020 Base99 floor as the v021 runtime visual replacement.

This output contains all 36 structural floor slabs plus their Blender-authored
details.  It replaces the old plain/rivet MultiMesh *visuals* as one coherent
layout while keeping Godot's existing shared FloorSupport collision unchanged.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

import bpy


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SOURCE_BLEND = PROJECT_ROOT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v020.blend"
COMPONENT_ROOT = PROJECT_ROOT / "assets/art/environments/base_facility_3d/components"
OUTPUT = COMPONENT_ROOT / "env_base99_floor_full_replacement_v021" / "env_base99_floor_full_replacement_v021_visual_top3d_v003.glb"
MANIFEST_OUTPUT = COMPONENT_ROOT / "env_base99_floor_full_replacement_v021" / "env_base99_floor_full_replacement_v021_runtime_manifest_v003.json"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import export_base_facility_v017_floor_visuals as base


def main() -> None:
    if Path(bpy.data.filepath).resolve() != SOURCE_BLEND.resolve():
        raise RuntimeError(f"Expected v020 source, got {bpy.data.filepath}")
    collections = base.floor_collections()
    all_floor_meshes: list[bpy.types.Object] = []
    plain_count = 0
    rivet_count = 0
    detail_count = 0
    for collection in collections:
        meshes = [obj for obj in collection.objects if obj.type == "MESH"]
        if not meshes:
            raise RuntimeError(f"Empty floor package: {collection.name}")
        all_floor_meshes.extend(meshes)
        if any("普通地板_主体" in obj.name for obj in meshes):
            plain_count += 1
        elif any("带铆钉地板_主体" in obj.name for obj in meshes):
            rivet_count += 1
        else:
            raise RuntimeError(f"No reusable structural floor mesh: {collection.name}")
        detail_count += sum(not base.is_reused_base_object(obj) for obj in meshes)
    if plain_count != 18 or rivet_count != 18:
        raise RuntimeError(f"Expected 18 plain and 18 rivet slabs, got {plain_count}/{rivet_count}")

    base.export_glb(all_floor_meshes, OUTPUT, "Base99FloorFullReplacementV021")
    manifest = {
        "schema": "shellstorm2.base99.full_floor_replacement_runtime.v1",
        "source_blend": str(SOURCE_BLEND.relative_to(PROJECT_ROOT)),
        "source_blend_sha256": hashlib.sha256(SOURCE_BLEND.read_bytes()).hexdigest(),
        "source_blender_version": "v020",
        "runtime_export_version": "v003",
        "asset_id": "ENV-BASE99-FLOOR-VISUAL-LAYOUT-V017",
        "visual_glb": str(OUTPUT.relative_to(PROJECT_ROOT)),
        "replacement_policy": "Replaces DungeonRoom3D's old plain/rivet MultiMesh visuals; no old floor visual remains rendered.",
        "collision_compatibility": {
            "owner": "TowerFloorStage3D/FloorSupport",
            "grid": "6x6 modules at 5m each",
            "horizontal_bounds_m": [-15.0, 15.0, -15.0, 15.0],
            "collision_surface_y_m": 0.0,
            "visual_origin_contract": "Matches retired 5m modules: center-bottom, Godot local -Z forward",
            "new_collision_in_glb": False,
        },
        "source_content": {
            "plain_structural_slab_count": plain_count,
            "rivet_structural_slab_count": rivet_count,
            "detail_mesh_count": detail_count,
            "source_bounds_m": {"min": [-15.0, -15.0, -0.3], "max": [15.0, 15.0, 0.193]},
        },
        "source_repairs": {
            "lifted_rivet_inner_shadow_strip_count": 72,
            "top_coplanar_overlap_count": 0,
            "downward_facing_triangle_count": 0,
            "audit": "outputs/verification/base99_floor_v020_overlap_audit.json",
        },
    }
    MANIFEST_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST_OUTPUT.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"BASE99_FULL_FLOOR_REPLACEMENT_GLB_WRITTEN:{OUTPUT}")
    print(f"BASE99_FULL_FLOOR_REPLACEMENT_MANIFEST_WRITTEN:{MANIFEST_OUTPUT}")


if __name__ == "__main__":
    main()
