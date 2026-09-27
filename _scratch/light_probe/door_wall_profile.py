"""把门墙 GLB 沿厚度轴投影成 X-Y 占用图，看门洞位置、净宽净高与门板升降空腔。"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

INDEX_FORMAT = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4)}


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
    return [
        struct.unpack_from("<" + fmt, binary, start + i * size)[0]
        for i in range(accessor["count"])
    ]


def sample_points(document, binary):
    points = []
    for mesh in document.get("meshes", []):
        for primitive in mesh["primitives"]:
            positions = read_vec3(document, binary, primitive["attributes"]["POSITION"])
            indices = read_indices(document, binary, primitive["indices"])
            for tri in range(0, len(indices), 3):
                a, b, c = (
                    positions[indices[tri]],
                    positions[indices[tri + 1]],
                    positions[indices[tri + 2]],
                )
                for s in range(0, 11):
                    t = s / 10.0
                    for p, q in ((a, b), (b, c), (c, a)):
                        points.append(
                            (
                                p[0] + (q[0] - p[0]) * t,
                                p[1] + (q[1] - p[1]) * t,
                                p[2] + (q[2] - p[2]) * t,
                            )
                        )
    return points


def render(path: Path) -> None:
    document, binary = load(path)
    points = sample_points(document, binary)
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    print("=" * 74)
    print(path.name)
    print(
        "  原始 X[%.2f, %.2f]  Y[%.2f, %.2f]  Z[%.2f, %.2f]"
        % (
            min(xs),
            max(xs),
            min(ys),
            max(ys),
            min(p[2] for p in points),
            max(p[2] for p in points),
        )
    )
    columns, rows = 60, 34
    x_min, x_max = -2.6, 2.6
    y_min, y_max = -0.1, 12.0
    grid = [[False] * columns for _ in range(rows)]
    for x, y, _z in points:
        col = int((x - x_min) / (x_max - x_min) * columns)
        row = int((y - y_min) / (y_max - y_min) * rows)
        if 0 <= col < columns and 0 <= row < rows:
            grid[row][col] = True
    print("  X: -2.6 .. +2.6 （每列 %.2fm）   Y: 0 .. 12 （每行 %.2fm）" % (
        (x_max - x_min) / columns,
        (y_max - y_min) / rows,
    ))
    for row in range(rows - 1, -1, -1):
        y_top = y_min + (row + 1) * (y_max - y_min) / rows
        print("  %5.2f |%s|" % (y_top, "".join("#" if c else "." for c in grid[row])))
    print("         " + "".join("|" if (i % 10) == 0 else " " for i in range(columns)))
    # 门洞净宽净高：在 y=0.05..2.4 的中间带里找连续空列
    band = []
    for col in range(columns):
        occupied = any(
            grid[row][col]
            for row in range(rows)
            if 0.05 <= y_min + (row + 0.5) * (y_max - y_min) / rows <= 2.4
        )
        band.append(occupied)
    runs = []
    start = None
    for col, occupied in enumerate(band):
        if not occupied and start is None:
            start = col
        elif occupied and start is not None:
            runs.append((start, col - 1))
            start = None
    if start is not None:
        runs.append((start, columns - 1))
    print("  y∈[0.05,2.40] 的空洞列区间：")
    for a, b in runs:
        xa = x_min + a * (x_max - x_min) / columns
        xb = x_min + (b + 1) * (x_max - x_min) / columns
        print("      x ∈ [%+.2f, %+.2f]  净宽 %.2f m" % (xa, xb, xb - xa))
    if not runs:
        print("      无空洞（该高度带整幅都是实体）")


for argument in sys.argv[sys.argv.index("--") + 1 :]:
    render(Path(argument))
