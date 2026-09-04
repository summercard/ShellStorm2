#!/usr/bin/env python3
"""Finish v016 source-component organization without touching v015-authored objects."""

import importlib.util
import json
from pathlib import Path

import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v016.blend"

spec = importlib.util.spec_from_file_location(
    "base_v016", PROJECT / "scripts/blender/build_base_facility_runtime_layout_hq_v016.py"
)
v016 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v016)

if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must start from generated v016")

root = v016.setup()
organized = v016.organize_v016_sources(root)
doc = v016.write_catalog(root)
report_path = v016.LOCK_REPORT
report = json.loads(report_path.read_text(encoding="utf-8"))
report["v016_organized_source_count"] = organized
report["source_component_organization"] = (
    "every v016 editable source is stored under a facility-specific mirrored source folder"
)
report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
bpy.context.scene["v016_organized_source_count"] = organized
bpy.context.scene["v016_source_organization"] = "按设施资产包镜像归类，无v016源组件混放"
v016.base.SOURCE.hide_viewport = True
v016.base.SOURCE.hide_render = True
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print(f"V016_SOURCES_ORGANIZED count={organized} packages={doc['package_count']}")
