"""Bake the approved facing and scale correction into the existing chibi head GLB."""

from __future__ import annotations

import json
import math
import struct
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
GLB_PATH = PROJECT_ROOT / "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/accessories/head/chibi_anime_head_v001/runtime/chr_player_bunny01_head_chibi_anime_top3d_v001.glb"
SCALE = 1.35


def main() -> None:
    raw = GLB_PATH.read_bytes()
    magic, version, total_length = struct.unpack_from("<III", raw, 0)
    if magic != 0x46546C67 or version != 2 or total_length != len(raw):
        raise RuntimeError("invalid GLB header")
    cursor = 12
    json_chunk = None
    binary_chunks: list[tuple[int, bytes]] = []
    while cursor < len(raw):
        chunk_length, chunk_type = struct.unpack_from("<II", raw, cursor)
        cursor += 8
        payload = raw[cursor:cursor + chunk_length]
        cursor += chunk_length
        if chunk_type == 0x4E4F534A:
            json_chunk = json.loads(payload.rstrip(b" \0").decode("utf-8"))
        else:
            binary_chunks.append((chunk_type, payload))
    if json_chunk is None or not json_chunk.get("nodes"):
        raise RuntimeError("GLB has no root node")
    # Y-up glTF matrix, 180 degrees around Y and 1.35x size.
    s = SCALE
    json_chunk["nodes"][0]["matrix"] = [-s, 0.0, 0.0, 0.0, 0.0, s, 0.0, 0.0, 0.0, 0.0, -s, 0.0, 0.0, 0.0, 0.0, 1.0]
    encoded = json.dumps(json_chunk, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    encoded += b" " * ((4 - len(encoded) % 4) % 4)
    chunks = [(0x4E4F534A, encoded), *binary_chunks]
    output = bytearray(struct.pack("<III", 0x46546C67, 2, 0))
    for chunk_type, payload in chunks:
        output += struct.pack("<II", len(payload), chunk_type)
        output += payload
    struct.pack_into("<I", output, 8, len(output))
    GLB_PATH.write_bytes(output)
    print(f"CHIBI_ANIME_HEAD_RUNTIME_PATCHED:{GLB_PATH}:rotation_y=180:scale={SCALE}")


if __name__ == "__main__":
    main()
