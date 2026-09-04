#!/usr/bin/env python3
"""Read-only light ownership inventory for Base Facility v017."""

import json
from pathlib import Path

import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
REPORT = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017/base_facility_light_ownership_audit_v017.json"

if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must start from v017")

packages = {c for c in bpy.data.collections if c.get("资产包")}
rows = []
for obj in sorted((o for o in bpy.data.objects if o.type == "LIGHT"), key=lambda o: o.name):
    owners = [c for c in obj.users_collection if c in packages]
    rows.append({
        "name": obj.name,
        "light_type": obj.data.type,
        "energy": round(float(obj.data.energy), 4),
        "color": [round(float(c), 3) for c in obj.data.color],
        "location": [round(float(c), 3) for c in obj.location],
        "current_packages": [c.get("资产包键") for c in owners],
        "collections": sorted(c.name for c in obj.users_collection),
    })
report = {"light_count": len(rows), "lights": rows}
REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report, ensure_ascii=False))
