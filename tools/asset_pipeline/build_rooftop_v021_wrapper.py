#!/usr/bin/env python3
"""Build the v021 rooftop facilities wrapper from Blender collision proxies.

The visual GLB and proxy report are authored from the same v021 Blend file.
This keeps the runtime collision layout locked to the editable Blender regions.
"""

from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ASSET = ROOT / "assets/art/environments/rooftop_shelter_3d"
SOURCE = ASSET / "runtime/env_rooftop_shelter_90x80m_facilities_root_top3d_v019.tscn"
TARGET = ASSET / "runtime/env_rooftop_shelter_90x80m_facilities_root_top3d_v021.tscn"
REPORT = ASSET / "reports/collision_layout_v021.json"
NODE_RE = re.compile(r'^\[node name="([^"]+)" type="([^"]+)"(?: parent="([^"]+)")?\]$')
PROXY_RE = re.compile(r'^metadata/source_proxy = "([^"]+)"$')


def godot_transform(proxy: dict[str, object]) -> str:
    """Format Blender->Godot basis using Transform3D column-vector order."""
    rows = proxy["basis"]
    position = proxy["position"]
    assert isinstance(rows, list) and len(rows) == 9
    assert isinstance(position, list) and len(position) == 3
    # Report stores matrix rows; Transform3D serializes Basis columns.
    basis = [rows[0], rows[3], rows[6], rows[1], rows[4], rows[7], rows[2], rows[5], rows[8]]
    values = [*basis, *position]
    return "transform = Transform3D(" + ", ".join(f"{float(value):.7f}" for value in values) + ")\n"


def flush_node(block: list[str], source_by_body: dict[str, str], proxy_by_name: dict[str, dict[str, object]]) -> list[str]:
    if not block:
        return []
    match = NODE_RE.match(block[0].rstrip("\n"))
    if match is None:
        return block
    name, node_type, parent = match.groups()
    if node_type == "StaticBody3D":
        for line in block:
            proxy_match = PROXY_RE.match(line.rstrip("\n"))
            if proxy_match:
                source_by_body[name] = proxy_match.group(1)
                break
        return block
    if node_type != "CollisionShape3D" or parent not in source_by_body:
        return block
    proxy_name = source_by_body[parent]
    proxy = proxy_by_name.get(proxy_name)
    if proxy is None:
        raise RuntimeError(f"No v021 collision proxy for {proxy_name}")
    result = [block[0], godot_transform(proxy)]
    result.extend(line for line in block[1:] if not line.startswith(("position = ", "rotation = ")))
    return result


def main() -> None:
    report = json.loads(REPORT.read_text(encoding="utf-8"))
    proxy_by_name = {item["name"]: item for item in report["proxies"]}
    source_lines = SOURCE.read_text(encoding="utf-8").splitlines(keepends=True)
    source_by_body: dict[str, str] = {}
    result: list[str] = []
    block: list[str] = []
    for line in source_lines:
        if line.startswith("[node "):
            result.extend(flush_node(block, source_by_body, proxy_by_name))
            block = [line]
        elif block:
            block.append(line)
        else:
            result.append(line)
    result.extend(flush_node(block, source_by_body, proxy_by_name))
    text = "".join(result)
    text = text.replace("env_rooftop_shelter_90x80m_facilities_v019.glb", "env_rooftop_shelter_90x80m_facilities_v021.glb")
    text = text.replace("末世天台生活聚落_90x80米_v019", "末世天台生活聚落_90x80米_v021")
    text = text.replace('metadata/version = "v019"', 'metadata/version = "v021"')
    text = text.replace('metadata/layout_revision = "north_wall_water_farm_stairs_v019"', 'metadata/layout_revision = "region_center_pivots_north_layout_v021"')
    expected = len(proxy_by_name)
    if len(source_by_body) != expected:
        raise RuntimeError(f"Expected {expected} collision bodies, found {len(source_by_body)}")
    TARGET.write_text(text, encoding="utf-8")
    print(f"Wrote {TARGET.relative_to(ROOT)} with {expected} synchronized collision proxies")


if __name__ == "__main__":
    main()
