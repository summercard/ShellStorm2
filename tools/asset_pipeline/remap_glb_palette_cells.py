import argparse
import json
import struct
from pathlib import Path


def read_chunks(path):
    data = Path(path).read_bytes()
    magic, version, _length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2:
        raise ValueError(f"Not a glTF 2.0 GLB: {path}")
    json_length, json_type = struct.unpack_from("<II", data, 12)
    json_start = 20
    document = json.loads(data[json_start : json_start + json_length].decode("utf-8"))
    bin_header = json_start + json_length
    bin_length, bin_type = struct.unpack_from("<II", data, bin_header)
    binary = bytearray(data[bin_header + 8 : bin_header + 8 + bin_length])
    return document, binary, json_type, bin_type


def write_chunks(path, document, binary, json_type, bin_type):
    encoded = json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    encoded += b" " * ((4 - len(encoded) % 4) % 4)
    binary += b"\x00" * ((4 - len(binary) % 4) % 4)
    total = 12 + 8 + len(encoded) + 8 + len(binary)
    output = bytearray(struct.pack("<4sII", b"glTF", 2, total))
    output.extend(struct.pack("<II", len(encoded), json_type))
    output.extend(encoded)
    output.extend(struct.pack("<II", len(binary), bin_type))
    output.extend(binary)
    Path(path).write_bytes(output)


def parse_cell_mapping(values):
    mapping = {}
    for value in values:
        before, after = value.split(":", 1)
        mapping[tuple(map(int, before.split(",")))] = tuple(map(int, after.split(",")))
    return mapping


def palette_cell(u, v):
    return min(9, max(0, int(u * 10))), min(9, max(0, int(v * 10)))


def remap(input_path, output_path, material_name, mapping):
    document, binary, json_type, bin_type = read_chunks(input_path)
    materials = [material.get("name", "") for material in document.get("materials", [])]
    changed = 0
    touched_accessors = set()
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            index = primitive.get("material", -1)
            if index < 0 or index >= len(materials) or materials[index] != material_name:
                continue
            accessor_index = primitive.get("attributes", {}).get("TEXCOORD_0")
            if accessor_index is None or accessor_index in touched_accessors:
                continue
            touched_accessors.add(accessor_index)
            accessor = document["accessors"][accessor_index]
            if accessor["componentType"] != 5126 or accessor["type"] != "VEC2":
                raise ValueError("Palette remapping requires float VEC2 texture coordinates")
            view = document["bufferViews"][accessor["bufferView"]]
            stride = view.get("byteStride", 8)
            start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
            for row in range(accessor["count"]):
                offset = start + row * stride
                u, v = struct.unpack_from("<ff", binary, offset)
                current = palette_cell(u, v)
                if current not in mapping:
                    continue
                target = mapping[current]
                struct.pack_into("<ff", binary, offset, (target[0] + 0.5) / 10.0, (target[1] + 0.5) / 10.0)
                changed += 1
    if changed == 0:
        raise RuntimeError(f"No matching UVs found in {input_path}")
    write_chunks(output_path, document, binary, json_type, bin_type)
    print(f"REMAPPED {changed} UVs: {input_path} -> {output_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("input")
    parser.add_argument("output")
    parser.add_argument("--material", required=True)
    parser.add_argument("--map", action="append", required=True, dest="mappings")
    arguments = parser.parse_args()
    remap(
        arguments.input,
        arguments.output,
        arguments.material,
        parse_cell_mapping(arguments.mappings),
    )
