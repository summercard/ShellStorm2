"""Create the v003 authored source and GLB for the Base99 underdeck blocker.

The visual remains the approved cool-grey horizontal cladding.  This revision
records the exact three-panel collision envelope consumed by the Godot v003
PackedScene, while keeping collision geometry out of the GLB.
"""

from __future__ import annotations

import importlib.util
import hashlib
import json
from pathlib import Path


PREVIOUS_PATH = Path(__file__).with_name("build_base99_mezzanine_underdeck_blocker_v002.py")
SPEC = importlib.util.spec_from_file_location("base99_underdeck_v002", PREVIOUS_PATH)
assert SPEC is not None and SPEC.loader is not None
previous = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(previous)

VERSION = "v003"
base = previous.base
base.VERSION = VERSION
base.OUTPUT_BLEND = base.SOURCE_DIR / f"{base.ASSET_SLUG}_source_{VERSION}.blend"
base.OUTPUT_GLB = (
    base.ASSET_ROOT / "components" / base.ASSET_SLUG
    / f"{base.ASSET_SLUG}_visual_top3d_{VERSION}.glb"
)
base.PREVIEW = base.SOURCE_DIR / "previews" / f"{base.ASSET_SLUG}_preview_{VERSION}.png"
base.MANIFEST = base.SOURCE_DIR / f"{base.ASSET_SLUG}_manifest_{VERSION}.json"
previous.VERSION = VERSION

original_build_panel = base.build_panel
original_duplicate_output = base.duplicate_output


def build_panel(*args, **kwargs):
    root = args[1]
    root["asset_version"] = VERSION
    root["collision_owner"] = "Godot PackedScene v003"
    root["collision_contract"] = "three authored panel-aligned permanent blockers"
    root["collision_panel_centers_blender"] = [
        [0.0, -4.45, 2.475],
        [-9.45, 0.0, 2.475],
        [9.45, 0.0, 2.475],
    ]
    return original_build_panel(*args, **kwargs)


def duplicate_output(source_objects, output_collection, output_root):
    body = original_duplicate_output(source_objects, output_collection, output_root)
    output_root["asset_version"] = VERSION
    output_root["collision_owner"] = "Godot PackedScene v003"
    output_root["collision_contract"] = "three authored panel-aligned permanent blockers"
    output_root["collision_panel_count"] = 3
    output_root["collision_height_m"] = 4.95
    return body


base.build_panel = build_panel
base.duplicate_output = duplicate_output


if __name__ == "__main__":
    base.main()
    manifest = json.loads(base.MANIFEST.read_text(encoding="utf-8"))
    manifest.update({
        "runtime": (
            "assets/art/environments/base_facility_3d/runtime/"
            "env_base99_mezzanine_underdeck_blocker/"
            "env_base99_mezzanine_underdeck_blocker_root_top3d_v003.tscn"
        ),
        "collision": "v003 PackedScene owns three authored panel-aligned permanent blockers",
        "collision_panel_count": 3,
        "collision_height_m": 4.95,
        "source_sha256": hashlib.sha256(base.OUTPUT_BLEND.read_bytes()).hexdigest(),
        "glb_sha256": hashlib.sha256(base.OUTPUT_GLB.read_bytes()).hexdigest(),
        "status": "approved_runtime",
    })
    base.MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
