#!/usr/bin/env python3
"""Align only the east door-wall main-panel PaletteUV to adjacent east walls."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import math
from pathlib import Path

import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
PACKAGES = PROJECT / "source/art/blender/base_facility_layout/component_packages_v017"
VERIFY = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017"
REPORT = VERIFY / "east_door_wall_palette_alignment_acceptance.json"
MANIFEST = PACKAGES / "architecture/east_door_wall_module/asset_manifest.json"
if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must run with v017 open")

spec = importlib.util.spec_from_file_location("v017_reorg", PROJECT / "scripts/blender/reorganize_base_facility_component_packages_v017.py")
reorg = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(reorg)

package = reorg.package_by_slug("east_door_wall_module")
source_package = bpy.data.collections["v017_源资产包_east_door_wall_module"]
wall = bpy.data.objects["带门墙体_主体_金属哑光反光.002"]
source = bpy.data.objects["带门墙体_主体_金属哑光反光.002__源"]
allowed = set(package.objects) | set(source_package.objects)
locked_before = {obj.name: reorg.signature(obj) for obj in bpy.data.objects if obj not in allowed}


def uv_digest(obj):
    uv = obj.data.uv_layers["PaletteUV"]
    values = tuple(round(float(component), 6) for point in uv.data for component in point.uv)
    return hashlib.sha256(repr(values).encode()).hexdigest()


outside_uv_before = {obj.name: uv_digest(obj) for obj in bpy.data.objects if obj.type == "MESH" and obj not in allowed and obj.data.uv_layers.get("PaletteUV")}


def align_main_matte_faces(obj):
    uv = obj.data.uv_layers["PaletteUV"]
    changed = []
    for polygon in obj.data.polygons:
        # Slot 1 is the wall's broad matte main-panel surface; frame metals and
        # orange gloss accents intentionally retain their own palette cells.
        if polygon.material_index != 1:
            continue
        changed.append(polygon.index)
        for point_index, loop_index in enumerate(polygon.loop_indices):
            angle = math.tau * point_index / max(3, len(polygon.loop_indices))
            uv.data[loop_index].uv = (0.95 + math.cos(angle) * 0.022, 0.95 + math.sin(angle) * 0.022)
    return changed


changed_output = align_main_matte_faces(wall)
changed_source = align_main_matte_faces(source)
if len(changed_output) != 50 or len(changed_source) != 50:
    raise RuntimeError(f"expected 50 east main-wall faces, got {len(changed_output)} / {len(changed_source)}")

bpy.context.view_layer.update()
manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
manifest.update({
    "visual_revision": "v017_east_door_wall_palette_aligned_004",
    "palette_alignment": "Only material-slot-1 main wall panels use shared PaletteUV cell (9,9), matching adjacent east wall modules. Portal frame and door assets retain their own cells.",
})
MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

catalog = json.loads(reorg.CATALOG.read_text(encoding="utf-8"))
entry = next(candidate for candidate in catalog["packages"] if candidate["asset_slug"] == "east_door_wall_module")
entry.update({"visual_revision": manifest["visual_revision"], "palette_alignment": manifest["palette_alignment"]})
catalog["source"] = "v017 east door wall PaletteUV main-panel alignment"
catalog["scope"] = "Only PaletteUV on the east_door_wall_module output/source main-panel faces was edited; all geometry, transforms, fixtures and other packages remain locked."
reorg.CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

locked_after = {obj.name: reorg.signature(obj) for obj in bpy.data.objects if obj.name in locked_before}
mismatches = {name: {"before": locked_before[name], "after": locked_after.get(name)} for name in locked_before if locked_before[name] != locked_after.get(name)}
outside_uv_after = {obj.name: uv_digest(obj) for obj in bpy.data.objects if obj.type == "MESH" and obj.name in outside_uv_before}
uv_mismatches = [name for name, digest in outside_uv_before.items() if outside_uv_after.get(name) != digest]
if mismatches or uv_mismatches:
    raise RuntimeError(f"outside-scope mutation: transforms={list(mismatches)[:4]} uv={uv_mismatches[:4]}")

report = {
    "status": "pass",
    "revision": manifest["visual_revision"],
    "scope": "east_door_wall_module PaletteUV only",
    "changed_output_polygon_count": len(changed_output),
    "changed_source_polygon_count": len(changed_source),
    "target_palette_cell": [9, 9],
    "locked_outside_scope": len(locked_before),
    "outside_transform_mismatches": mismatches,
    "outside_palette_uv_mismatches": uv_mismatches,
}
REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
bpy.context.scene["v017_iteration"] = "east_door_wall_palette_aligned_004"
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print(json.dumps(report, ensure_ascii=False))
