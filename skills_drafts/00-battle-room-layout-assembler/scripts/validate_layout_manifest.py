#!/usr/bin/env python3
"""Validate a ShellStorm2 battle room layout manifest without modifying it."""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

SCHEMA = "shellstorm2.battle.room_layout"
ALLOWED_ROLES = {
    "solid_wall", "door_wall", "door", "floor", "ceiling", "stair",
    "facility", "decor", "corridor_socket", "gameplay_anchor"
}

def fail(errors: list[str], message: str) -> None:
    errors.append(message)

def finite_number(value: object) -> bool:
    return isinstance(value, (int, float)) and math.isfinite(float(value))

def main() -> int:
    parser = argparse.ArgumentParser(description="Validate a battle room layout manifest")
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    try:
        data = json.loads(args.manifest.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"LAYOUT_INVALID read_error={exc}")
        return 2

    errors: list[str] = []
    if data.get("schema") != SCHEMA:
        fail(errors, f"schema must be {SCHEMA!r}")
    if data.get("schema_version") != 1:
        fail(errors, "schema_version must be 1")
    if data.get("block_id") != "battle":
        fail(errors, "block_id must be battle")
    if not isinstance(data.get("room_id"), str) or not data["room_id"]:
        fail(errors, "room_id is required")
    if not isinstance(data.get("layout_version"), str) or not data["layout_version"].startswith("v"):
        fail(errors, "layout_version must start with v")
    if data.get("coordinate_system") != "godot-y-up-room-local":
        fail(errors, "coordinate_system must be godot-y-up-room-local")
    if not isinstance(data.get("instances"), list):
        fail(errors, "instances must be an array")
        instances = []
    else:
        instances = data["instances"]
    seen: set[str] = set()
    non_unit = 0
    illegal_rotations = 0
    for index, instance in enumerate(instances):
        prefix = f"instances[{index}]"
        if not isinstance(instance, dict):
            fail(errors, f"{prefix} must be an object")
            continue
        instance_id = instance.get("instance_id")
        if not isinstance(instance_id, str) or not instance_id:
            fail(errors, f"{prefix}.instance_id is required")
        elif instance_id in seen:
            fail(errors, f"duplicate instance_id: {instance_id}")
        else:
            seen.add(instance_id)
        component_id = instance.get("component_id")
        if not isinstance(component_id, str) or not component_id:
            fail(errors, f"{prefix}.component_id is required")
        role = instance.get("slot_role")
        if role not in ALLOWED_ROLES:
            fail(errors, f"{prefix}.slot_role is not allowed: {role!r}")
        transform = instance.get("transform")
        if not isinstance(transform, dict):
            fail(errors, f"{prefix}.transform is required")
            continue
        position = transform.get("position_m")
        if not isinstance(position, list) or len(position) != 3 or not all(finite_number(v) for v in position):
            fail(errors, f"{prefix}.transform.position_m must contain 3 finite numbers")
        rotation = transform.get("rotation_y_deg")
        if not finite_number(rotation):
            fail(errors, f"{prefix}.transform.rotation_y_deg must be finite")
        else:
            normalized = float(rotation) % 360.0
            if min(abs(normalized - candidate) for candidate in (0.0, 90.0, 180.0, 270.0)) > 0.001:
                illegal_rotations += 1
        scale = transform.get("scale")
        if not isinstance(scale, list) or len(scale) != 3 or not all(finite_number(v) for v in scale):
            fail(errors, f"{prefix}.transform.scale must contain 3 finite numbers")
        elif any(abs(float(v) - 1.0) > 1e-6 for v in scale):
            non_unit += 1
    if data.get("validation", {}).get("room_owned_geometry") is True:
        fail(errors, "validation.room_owned_geometry must be false")
    if errors:
        print("LAYOUT_INVALID")
        for error in errors:
            print(f"- {error}")
        return 1
    print(
        "LAYOUT_OK "
        f"room_id={data['room_id']} instances={len(instances)} "
        f"non_unit_scale={non_unit} illegal_rotation={illegal_rotations}"
    )
    return 0

if __name__ == "__main__":
    sys.exit(main())
