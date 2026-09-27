"""门洞区正投影覆盖率：判断门墙的门洞是否真的留空。"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

INDEX_FORMAT = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4)}
GRID = 44


def load(path: Path):
    data = path.read_bytes()
    length = struct.unpack_from("<I", data, 12)[0]
    document = json.loads(data[20 : 20 + length])
    binary = None
    offset = 12
    while offset < len(data):
        chunk_length, kind = struct.unpack_from("<II", data, offset)
        offset += 8
        if kind == 0x004E4942:
            binary = data[offset : offset + chunk_length]
        offset += chunk_length
    return document, binary


def read_vec3(document, binary, index):
    accessor = document["accessors"][index]
    view = document["bufferViews"][accessor["bufferView"]]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride") or 12
    return [
        struct.unpack_from("<fff", binary, start + i * stride)
        for i in range(accessor["count"])
    ]


def read_indices(document, binary, index):
    accessor = document["accessors"][index]
    view = document["bufferViews"][accessor["bufferView"]]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    fmt, size = INDEX_FORMAT[accessor["componentType"]]
    stride = view.get("byteStride") or size
    return [
        struct.unpack_from("<" + fmt, binary, start + i * stride)[0]
        for i in range(accessor["count"])
    ]


def coverage(path: Path, label: str) -> None:
    document, binary = load(path)
    grid = [[0] * GRID for _ in range(GRID)]
    x0, x1, y0, y1 = -1.1, 1.1, 0.0, 2.5
    for mesh in document.get("meshes", []):
        for primitive in mesh["primitives"]:
            positions = read_vec3(document, binary, primitive["attributes"]["POSITION"])
            indices = read_indices(document, binary, primitive["indices"])
            for tri in range(0, len(indices), 3):
                points = [
                    positions[indices[tri]],
                    positions[indices[tri + 1]],
                    positions[indices[tri + 2]],
                ]
                xs = [p[0] for p in points]
                ys = [p[1] for p in points]
                if max(xs) < x0 or min(xs) > x1 or max(ys) < y0 or min(ys) > y1:
                    continue
                (ax, ay), (bx, by), (cx, cy) = [(p[0], p[1]) for p in points]
                det = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
                if abs(det) < 1e-9:
                    continue
                for gx in range(GRID):
                    px = x0 + (gx + 0.5) * (x1 - x0) / GRID
                    for gy in range(GRID):
                        py = y0 + (gy + 0.5) * (y1 - y0) / GRID
                        u = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / det
                        v = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / det
                        if u >= -0.001 and v >= -0.001 and 1 - u - v >= -0.001:
                            grid[gy][gx] = 1
    filled = sum(sum(row) for row in grid)
    print("== %s  门洞区 x[-1.10, 1.10] y[0.00, 2.50] 正投影覆盖率 = %.1f%%"
          % (label, filled / (GRID * GRID) * 100))
    for gy in range(GRID - 1, -1, -1):
        print("   %4.2f |%s|" % (
            y0 + (gy + 1) * (y1 - y0) / GRID,
            "".join("#" if grid[gy][gx] else "." for gx in range(GRID)),
        ))


pairs = [
    ("assets/art/environments/tower_zones/expedition/components/room_type_components/office_room/door_wall/door_wall_visual_top3d.glb", "办公室门墙"),
    ("assets/art/environments/tower_zones/battle/components/common_components/wall_door_5m/wall_door_5m_visual_top3d.glb", "通用门墙（关卡规范）"),
]
for relative, label in pairs:
    coverage(Path(relative), label)
