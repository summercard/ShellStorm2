#!/usr/bin/env python3
"""Finish fallback source-folder mapping for the collection-only v017 pass."""

import importlib.util
import json
from pathlib import Path

import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
SCRIPT = PROJECT / "scripts/blender/reorganize_base_facility_component_packages_v017.py"

spec = importlib.util.spec_from_file_location("reorg_v017", SCRIPT)
reorg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reorg)

if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must start from v017")

before = {obj.name: reorg.signature(obj) for obj in bpy.data.objects}
mapped, unresolved, ignored, source_package_count = reorg.organize_sources(set(reorg.packages()))
after = {name: reorg.signature(bpy.data.objects[name]) for name in before if name in bpy.data.objects}
changed = sorted(name for name in before if name in after and before[name] != after[name])
removed = sorted(set(before) - set(after))
if changed or removed:
    raise RuntimeError(f"source folder pass changed objects: {changed[:8]} removed={removed[:8]}")
catalog = reorg.write_catalog(reorg.packages())
report = json.loads(reorg.REPORT.read_text(encoding="utf-8"))
report["final_source_folder_pass"] = {
    "locked_match": before == after,
    "mapped_count": len(mapped),
    "unresolved_count": len(unresolved),
    "ignored_non_source_count": len(ignored),
    "source_package_count": source_package_count,
    "package_count": catalog["package_count"],
}
reorg.REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
bpy.context.scene["v017_source_package_count"] = source_package_count
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print(f"V017_SOURCE_FALLBACK_MAPPED mapped={len(mapped)} unresolved={len(unresolved)} ignored={len(ignored)}")
