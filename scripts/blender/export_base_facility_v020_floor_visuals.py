"""Export the repaired Base99 v020 floor visuals as a versioned Godot payload.

The existing v017 GLBs remain untouched for rollback.  This script exports only
the visual overlays; collision continues to be supplied by the existing floor
and mezzanine runtime geometry.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import export_base_facility_v017_floor_visuals as base


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SOURCE_BLEND = PROJECT_ROOT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v020.blend"
COMPONENT_ROOT = PROJECT_ROOT / "assets/art/environments/base_facility_3d/components"
GROUND_OUTPUT = COMPONENT_ROOT / "env_base99_floor_details_v020" / "env_base99_floor_details_v020_visual_top3d_v002.glb"
LOFT_OUTPUT = COMPONENT_ROOT / "env_base99_loft_floor_finish_v020" / "env_base99_loft_floor_finish_v020_visual_top3d_v002.glb"
MANIFEST_OUTPUT = COMPONENT_ROOT / "env_base99_floor_details_v020" / "env_base99_floor_details_v020_runtime_manifest_v002.json"


def main() -> None:
    if Path(bpy.data.filepath).resolve() != SOURCE_BLEND.resolve():
        raise RuntimeError(f"Expected v020 source, got {bpy.data.filepath}")
    collections = base.floor_collections()
    ground_details, floor_rows = base.ground_detail_objects(collections)
    loft_collection = bpy.data.collections.get(base.LOFT_COLLECTION_NAME)
    if loft_collection is None:
        raise RuntimeError(f"Missing collection: {base.LOFT_COLLECTION_NAME}")
    loft_details = [obj for obj in loft_collection.objects if obj.type == "MESH"]
    if not loft_details:
        raise RuntimeError("Second-floor finish collection contains no mesh objects")

    base.export_glb(ground_details, GROUND_OUTPUT, "Base99FloorDetailsV020")
    base.export_glb(loft_details, LOFT_OUTPUT, "Base99LoftFloorFinishV020")
    manifest = base.build_manifest(floor_rows, ground_details, loft_details)
    manifest.update(
        {
            "source_blend": str(SOURCE_BLEND.relative_to(PROJECT_ROOT)),
            "source_blend_sha256": hashlib.sha256(SOURCE_BLEND.read_bytes()).hexdigest(),
            "version": "v020",
            "runtime_export_version": "v002",
            "optimization": {
                "rivet_inner_shadow_strip_lift_m": 0.002,
                "lifted_rivet_inner_shadow_strip_count": 72,
                "lifted_logo_joint_mesh_count": 2,
                "removed_downward_source_faces_v018": 34673,
                "removed_downward_triangles_v020": 47,
                "final_overlap_audit": "outputs/verification/base99_floor_v020_overlap_audit.json",
            },
        }
    )
    manifest["ground_floor"].update(
        {
            "asset_id": "ENV-BASE99-FLOOR-DETAILS-V017",
            "visual_glb": str(GROUND_OUTPUT.relative_to(PROJECT_ROOT)),
            "runtime_export_version": "v002",
        }
    )
    manifest["loft_floor_finish"].update(
        {
            "asset_id": "ENV-BASE99-LOFT-FLOOR-FINISH-V017",
            "visual_glb": str(LOFT_OUTPUT.relative_to(PROJECT_ROOT)),
            "runtime_export_version": "v002",
        }
    )
    MANIFEST_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST_OUTPUT.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"BASE99_FLOOR_DETAILS_GLB_WRITTEN:{GROUND_OUTPUT}")
    print(f"BASE99_LOFT_FLOOR_FINISH_GLB_WRITTEN:{LOFT_OUTPUT}")
    print(f"BASE99_FLOOR_RUNTIME_MANIFEST_WRITTEN:{MANIFEST_OUTPUT}")


if __name__ == "__main__":
    main()
