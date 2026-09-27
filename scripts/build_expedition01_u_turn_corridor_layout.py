#!/usr/bin/env python3
"""Build/check expedition_01 room_04 U-turn layout from L-corridor v012 components only."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE_REL = "assets/art/environments/tower_zones/expedition/source/common_components/v012/component_instances.json"
CATALOG_REL = "assets/art/environments/tower_zones/expedition/source/common_components/v012/component_catalog.json"
OUT_REL = "assets/art/environments/tower_zones/expedition/source/room_instances/f00_room_04/v001/room_layout.json"
OUT = ROOT / OUT_REL

FLOOR = "ENV-EXPEDITION-L01-CORRIDOR-FLOOR_TILE_5M_B"
WALL_A = "ENV-EXPEDITION-L01-CORRIDOR-WALL_5M_A"  # horizontal full-height
WALL_C = "ENV-EXPEDITION-L01-CORRIDOR-WALL_5M_C"  # vertical full-height
DECOR = [
    ("ACCESS_CONSOLE_A", 12.5, -12.0, 0.0),
    ("ACCESS_CONSOLE_B", 18.0, 10.0, 90.0),
    ("CRATE", 10.5, 11.5, 0.0),
    ("HANGING_CABLE_A", 15.5, -10.0, 0.0),
    ("HANGING_CABLE_C", 15.5, 10.0, 0.0),
    ("HANGING_CABLE_E", 17.5, 0.0, 0.0),
    ("HIGH_PIPE_A", 19.5, -10.0, 0.0),
    ("HIGH_PIPE_A", 19.5, 10.0, 0.0),
    ("HIGH_PIPE_B", -2.5, -13.0, 0.0),
    ("HIGH_PIPE_C", -2.5, 13.0, 0.0),
    ("PIPE_RISER", 20.5, 0.0, 0.0),
    ("PLANTER", 11.5, -10.0, 0.0),
    ("SERVER_GALLERY", -2.5, -13.5, 0.0),
    ("SERVER_RACK", 12.5, 10.0, 0.0),
    ("SERVICE_CART_A", -14.5, -10.0, 0.0),
    ("SERVICE_CART_B", -14.5, 10.0, 0.0),
    ("WALL_LABEL", 2.5, 13.5, 0.0),
]


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def instance(instance_id: str, component_id: str, x: float, y: float, z: float = 0.0, rotation: float = 0.0) -> dict:
    return {
        "instance_id": instance_id,
        "component_id": component_id,
        "position_m": [x, y, z],
        "rotation_y_deg": rotation,
        "scale": [1.0, 1.0, 1.0],
    }


def build() -> dict:
    base_path = ROOT / BASE_REL
    catalog_path = ROOT / CATALOG_REL
    base = read_json(base_path)
    catalog = read_json(catalog_path)
    ids = {row["component_id"] for row in catalog["packages"]}
    slug_to_id = {row["slug"].upper(): row["component_id"] for row in catalog["packages"]}
    required = {FLOOR, WALL_A, WALL_C} | {slug_to_id[slug] for slug, *_ in DECOR}
    missing = sorted(required - ids)
    if missing:
        raise SystemExit(f"catalog missing components: {missing}")

    resolved: list[dict] = []
    # U footprint in the existing v012 source frame: x=0..45, y=-25..15.
    # Top/bottom arms are each 15m deep; the middle band keeps only x=30..45.
    floor_index = 0
    for row in range(8):
        y = -22.5 + row * 5.0
        for col in range(9):
            x = -20.0 + col * 5.0
            if row in (3, 4) and col < 6:
                continue
            resolved.append(instance(f"ROOM04_U_FLOOR_R{row:02d}_C{col:02d}", FLOOR, x, y + 5.0, -0.3))
            floor_index += 1

    wall_index = 0
    def add_h(y: float, cols: range, tag: str) -> None:
        nonlocal wall_index
        authored_y = y + 5.0 - 0.1055
        for col in cols:
            x = -20.0 + col * 5.0
            resolved.append(instance(f"ROOM04_U_WALL_{tag}_{col:02d}", WALL_A, x, authored_y, 0.0, 0.0))
            wall_index += 1

    def add_v(x: float, rows: range, tag: str) -> None:
        nonlocal wall_index
        authored_x = x - 22.5 - 0.113
        for row in rows:
            y = -17.5 + row * 5.0
            resolved.append(instance(f"ROOM04_U_WALL_{tag}_{row:02d}", WALL_C, authored_x, y, 0.0, 0.0))
            wall_index += 1

    # Outer perimeter: north/south full width, east full height, west only the two arms.
    add_h(-25.0, range(9), "NORTH")
    add_h(15.0, range(9), "SOUTH")
    add_v(45.0, range(8), "EAST")
    add_v(0.0, range(0, 3), "WEST_N")
    add_v(0.0, range(5, 8), "WEST_S")
    # Re-entrant boundary around the 30x10 solid island/open notch.
    add_h(-10.0, range(0, 6), "INNER_N")
    add_h(0.0, range(0, 6), "INNER_S")
    add_v(30.0, range(3, 5), "INNER_E")

    for index, (slug, x, y, rotation) in enumerate(DECOR):
        resolved.append(instance(f"ROOM04_U_DECOR_{index:02d}_{slug}", slug_to_id[slug], x, y, 0.0, rotation))

    base_ids = [row["instance_id"] for row in base["instances"]]
    overrides = [{"op": "remove", "instance_id": value} for value in base_ids]
    overrides.extend({"op": "add", "instance_id": row["instance_id"], "instance": row} for row in resolved)
    unique_components = sorted({row["component_id"] for row in resolved})
    return {
        "schema": "shellstorm2.battle.room_instance_layout",
        "schema_version": 1,
        "level_id": "expedition_01",
        "block_id": "expedition",
        "room_id": "f00_room_04",
        "room_key": "room_04",
        "room_type": "COMMON_ROOM",
        "template_id": "corridor_45x40",
        "template_variant": "u_turn",
        "layout_version": "v001",
        "dimensions_m": [45.0, 40.0],
        "whitebox_source": "source/art/whitebox/tower_zones/expedition_01/v001/data/floors/floor_00.json",
        "component_source": CATALOG_REL,
        "component_source_version": "v012",
        "base_layout": BASE_REL,
        "base_layout_sha256": sha256(base_path),
        "source_blend": None,
        "coordinate_contract": {
            "source": "blender_z_up_room_centered_layout_space",
            "source_bounds_xy_m": [[-22.5, -20.0], [22.5, 20.0]],
            "target": "godot_y_up_room_local",
            "mapping": "(bx, by, bz) -> (bx, bz, -by)",
            "rotation_y_deg_semantics_in_source": "rotation_about_blender_Z",
        },
        "instance_overrides": overrides,
        "instances": resolved,
        "validation": {
            "room_owned_geometry": False,
            "component_budget_limit": 50,
            "unique_component_count": len(unique_components),
            "unique_component_ids": unique_components,
            "base_instance_count": len(base_ids),
            "resolved_instance_count": len(resolved),
            "floor_tile_count": floor_index,
            "solid_wall_count": wall_index,
            "room_type_component_count": len(DECOR),
            "non_unit_scale_count": 0,
            "missing_components": [],
            "footprint_area_m2": 1500.0,
            "notch_bounds_xy_m": [[-22.5, -5.0], [7.5, 5.0]],
            "room_specific_component_count": 0,
        },
    }


def encoded(data: dict) -> bytes:
    return (json.dumps(data, ensure_ascii=False, indent=2) + "\n").replace("\n", "\r\n").encode("utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = parser.parse_args()
    payload = encoded(build())
    if args.write:
        OUT.parent.mkdir(parents=True, exist_ok=True)
        OUT.write_bytes(payload)
        print(f"U_TURN_LAYOUT_WRITTEN path={OUT_REL} bytes={len(payload)}")
        return 0
    if not OUT.exists() or OUT.read_bytes() != payload:
        print(f"U_TURN_LAYOUT_DRIFT path={OUT_REL}")
        return 1
    print(f"U_TURN_LAYOUT_OK path={OUT_REL}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
