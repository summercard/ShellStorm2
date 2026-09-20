"""Patch the 11 new rooftop component .import files to bind the shared palette import script.

.IdImport files are Godot-generated and use LF (project convention lists only
.gd/.tscn/.json/.md as CRLF), so line endings are left untouched.
"""
import io
import sys
from pathlib import Path

COMPONENTS = Path("assets/art/environments/tower_zones/rooftop/components")
PALETTE = "res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"

STEMS = [
    "env_rooftop_ref_room_wall_top3d",
    "env_rooftop_ref_room_window_top3d",
    "env_rooftop_ref_room_doorwall_top3d",
    "env_rooftop_ref_room_wall_ivy_top3d",
    "env_rooftop_ref_room_window_ivy_top3d",
    "env_rooftop_ref_room_doorwall_ivy_top3d",
    "env_rooftop_ref_room_door_top3d",
    "env_rooftop_ref_room_door_leaf_top3d",
    "env_rooftop_ref_roof_full_top3d",
    "env_rooftop_ref_roof_edge_top3d",
    "env_rooftop_ref_roof_corner_top3d",
]

EMPTY = b'import_script/path=""'
BOUND = ('import_script/path="%s"' % PALETTE).encode("utf-8")

failures = []
patched = 0
for stem in STEMS:
    path = COMPONENTS / (stem + ".glb.import")
    if not path.exists():
        failures.append("%s missing" % path)
        continue
    data = path.read_bytes()
    if data.count(BOUND) == 1 and data.count(EMPTY) == 0:
        print("ALREADY %-52s" % path.name)
        patched += 1
        continue
    count = data.count(EMPTY)
    if count != 1:
        failures.append("%s: expected 1 empty import_script, found %d" % (path.name, count))
        continue
    before = len(data)
    data = data.replace(EMPTY, BOUND)
    with io.open(path, "wb") as fh:
        fh.write(data)
    verify = path.read_bytes()
    if verify.count(BOUND) != 1 or verify.count(EMPTY) != 0:
        failures.append("%s: post-write verification failed" % path.name)
        continue
    print("PATCHED %-52s (%+d bytes)" % (path.name, len(verify) - before))
    patched += 1

if failures:
    print("PATCH_FAILED:")
    for item in failures:
        print("   -", item)
    sys.exit(1)
print("PATCH_OK count=%d" % patched)
