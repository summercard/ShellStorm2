import argparse
import json
import math
import struct
from collections import defaultdict
from pathlib import Path


COMPONENTS = {
    5120: ("b", 1),
    5121: ("B", 1),
    5122: ("h", 2),
    5123: ("H", 2),
    5125: ("I", 4),
    5126: ("f", 4),
}
TYPE_SIZE = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_glb(path):
    data = Path(path).read_bytes()
    if data[:4] != b"glTF":
        raise ValueError(f"Not a GLB file: {path}")
    offset = 12
    gltf = None
    binary = None
    while offset < len(data):
        length, chunk_type = struct.unpack_from("<II", data, offset)
        payload = data[offset + 8 : offset + 8 + length]
        if chunk_type == 0x4E4F534A:
            gltf = json.loads(payload.rstrip(b"\x00 ").decode("utf-8"))
        elif chunk_type == 0x004E4942:
            binary = payload
        offset += 8 + length
    return gltf, binary


def read_accessor(gltf, binary, index):
    accessor = gltf["accessors"][index]
    view = gltf["bufferViews"][accessor["bufferView"]]
    fmt, component_size = COMPONENTS[accessor["componentType"]]
    component_count = TYPE_SIZE[accessor["type"]]
    item_size = component_size * component_count
    stride = view.get("byteStride", item_size)
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    unpack = struct.Struct("<" + fmt * component_count).unpack_from
    return [unpack(binary, start + row * stride) for row in range(accessor["count"])]


def triangle_area(a, b, c):
    ab = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
    ac = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
    cross = (
        ab[1] * ac[2] - ab[2] * ac[1],
        ab[2] * ac[0] - ab[0] * ac[2],
        ab[0] * ac[1] - ab[1] * ac[0],
    )
    return 0.5 * math.sqrt(sum(value * value for value in cross))


def cell(uv):
    return tuple(min(9, max(0, int(value * 10))) for value in uv)


def report(path):
    gltf, binary = read_glb(path)
    names = [material.get("name", f"material_{index}") for index, material in enumerate(gltf.get("materials", []))]
    usage = defaultdict(lambda: [0, 0.0])
    for mesh in gltf.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            attributes = primitive["attributes"]
            if "POSITION" not in attributes or "TEXCOORD_0" not in attributes:
                continue
            positions = read_accessor(gltf, binary, attributes["POSITION"])
            uvs = read_accessor(gltf, binary, attributes["TEXCOORD_0"])
            indices = [row[0] for row in read_accessor(gltf, binary, primitive["indices"])]
            material = names[primitive.get("material", 0)]
            for offset in range(0, len(indices), 3):
                triangle = indices[offset : offset + 3]
                if len(triangle) != 3:
                    continue
                average_uv = tuple(sum(uvs[index][axis] for index in triangle) / 3 for axis in range(2))
                key = material, cell(average_uv)
                usage[key][0] += 1
                usage[key][1] += triangle_area(*(positions[index] for index in triangle))
    print("FILE", path)
    totals = defaultdict(float)
    for (material, _cell), (_count, area) in usage.items():
        totals[material] += area
    for material in names:
        print(" MATERIAL", material, "AREA", round(totals[material], 4))
        rows = [
            (uv_cell, count, area, area / totals[material] if totals[material] else 0.0)
            for (name, uv_cell), (count, area) in usage.items()
            if name == material
        ]
        for uv_cell, count, area, ratio in sorted(rows, key=lambda row: row[2], reverse=True)[:12]:
            print("  CELL", uv_cell, "TRIS", count, "AREA", round(area, 4), "RATIO", round(ratio, 4))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+")
    for input_path in parser.parse_args().paths:
        report(input_path)
