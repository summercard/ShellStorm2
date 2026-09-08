from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FILES = [
    "assets/art/environments/base_facility_3d/components/env_base99_remaining_facilities_v021/volumetric_dust_fx/volumetric_dust_fx_visual_top3d_v001.glb",
    "assets/art/environments/base_facility_3d/components/env_base99_remaining_facilities_v021/volumetric_dust_fx/volumetric_dust_fx_visual_top3d_v001.glb.import",
    "assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities_v021/volumetric_dust_fx/volumetric_dust_fx_root_top3d_v001.tscn",
]
for relative in FILES:
    path = ROOT / relative
    if path.exists():
        path.unlink()
print("DEPRECATED_BASE99_DUST_MESH_REMOVED=3")
