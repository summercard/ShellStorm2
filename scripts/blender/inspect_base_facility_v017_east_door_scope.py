#!/usr/bin/env python3
"""Read-only scope inventory for the v017 east-door / SUPPLY swap."""

import json
from pathlib import Path
import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
OUT = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017/east_door_swap_scope_before.json"

if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must run with v017 open")

target_keys = {"east_personnel_security_door", "east_supply_24h_station"}
packages = [c for c in bpy.data.collections if c.get("资产包键") in target_keys]
target_objects = {o for c in packages for o in c.objects}

def row(obj):
    return {
        "name": obj.name,
        "type": obj.type,
        "location": [round(float(v), 5) for v in obj.location],
        "rotation": [round(float(v), 5) for v in obj.rotation_euler],
        "dimensions": [round(float(v), 5) for v in obj.dimensions],
        "collections": sorted(c.name for c in obj.users_collection),
    }

report = {
    "blend": str(BLEND),
    "target_packages": [
        {
            "name": c.name,
            "key": c.get("资产包键"),
            "objects": [row(o) for o in sorted(c.objects, key=lambda x: x.name)],
        }
        for c in sorted(packages, key=lambda x: x.get("资产包键"))
    ],
    "nearby_east_objects": [
        row(o) for o in sorted(bpy.data.objects, key=lambda x: x.name)
        if o not in target_objects and 11.5 <= o.location.x <= 15.5 and -5.0 <= o.location.y <= 5.0 and o.type in {"MESH", "LIGHT"}
    ],
    "cameras": [
        {"name": c.name, "location": [round(float(v), 4) for v in c.location], "lens": round(float(c.data.lens), 4), "ortho": round(float(c.data.ortho_scale), 4)}
        for c in bpy.data.objects if c.type == "CAMERA"
    ],
}
OUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"target_object_count": len(target_objects), "packages": [p["key"] for p in report["target_packages"]], "camera_count": len(report["cameras"])}, ensure_ascii=False))
