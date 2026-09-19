"""在 GLB 字节层证明「破损变体的端头带与 intact 件逐位相同」。

为什么需要这个独立脚本：Godot 的 glTF 导入是一条固定管线，顶点位置在
float32 -> double -> float32 之间过一遍，同一个源值在 intact 与派生件里可能差
1 个 ULP（实测 -2.47101 vs -2.47100）。任何在 Godot 侧按十进制打印再比对的写法
都会把「源文件逐位相同」的几何误报成「端头带不同」。本脚本绕开导入管线，
直接读 GLB 的 POSITION accessor 原始 float32 字节，做逐位比对。

判据（全部满足才 OK）：
  1. 四个 GLB 的 POSITION 包络逐位相同（X 长度 5.00 / Y 高 1.80 / Z 厚 0.50，底面 Z=0）；
  2. 每件破损件的端头带 |x| >= END_BAND_START_M - 容差 顶点「数量」与 intact 件相同；
  3. 上述顶点按 (x, y, z) 排序后，逐点 float32 字节完全一致。

跑法：python assets/art/environments/tower_zones/rooftop/source/verify_env_rooftop_parapet_damage_bands.py
"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
COMPONENTS = HERE.parent / "components"
END_BAND_START_M = 2.05
BAND_TOLERANCE_M = 0.01

INTACT = "env_rooftop_ref_parapet_top3d.glb"
VARIANTS = {
    "dmg_a": "env_rooftop_ref_parapet_dmg_a_top3d.glb",
    "dmg_b": "env_rooftop_ref_parapet_dmg_b_top3d.glb",
    "dmg_c": "env_rooftop_ref_parapet_dmg_c_top3d.glb",
}
# GLB POSITION accessor 实测包络：X = 5.00（长），Y = 1.80（高），Z = 0.50（厚），
# 底面 Y=0、上下居中于 X/Z。
EXPECTED_ENVELOPE = ((-2.5, 0.0, -0.25), (2.5, 1.8, 0.25))
ENVELOPE_TOLERANCE_M = 1.0e-6


def read_glb(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    if data[:4] != b"glTF":
        raise SystemExit("%s is not a GLB" % path)
    offset = 12
    document = None
    binary = b""
    while offset < len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        payload = data[offset + 8 : offset + 8 + chunk_length]
        if chunk_type == 0x4E4F534A:
            document = json.loads(payload.decode("utf-8"))
        elif chunk_type == 0x004E4942:
            binary = payload
        offset += 8 + chunk_length
    if document is None:
        raise SystemExit("%s has no JSON chunk" % path)
    return document, binary


def read_positions(document: dict, binary: bytes) -> list[tuple[float, float, float]]:
    accessor_index = document["meshes"][0]["primitives"][0]["attributes"]["POSITION"]
    accessor = document["accessors"][accessor_index]
    view = document["bufferViews"][accessor["bufferView"]]
    start = int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
    count = int(accessor["count"])
    return [struct.unpack_from("<3f", binary, start + index * 12) for index in range(count)]


def envelope(points: list[tuple[float, float, float]]) -> tuple[tuple[float, ...], tuple[float, ...]]:
    lows = tuple(min(point[axis] for point in points) for axis in range(3))
    highs = tuple(max(point[axis] for point in points) for axis in range(3))
    return lows, highs


def band(points: list[tuple[float, float, float]]) -> list[tuple[float, float, float]]:
    selected = [p for p in points if abs(p[0]) >= END_BAND_START_M - BAND_TOLERANCE_M]
    selected.sort()
    return selected


def bit_key(point: tuple[float, float, float]) -> bytes:
    return struct.pack("<3f", *point)


def main() -> int:
    failures: list[str] = []
    reference_document, reference_binary = read_glb(COMPONENTS / INTACT)
    reference_points = read_positions(reference_document, reference_binary)
    reference_band = band(reference_points)
    reference_lows, reference_highs = envelope(reference_points)
    print(
        "DMG_BANDS intact verts=%d band=%d envelope=(%.4f,%.4f,%.4f)~(%.4f,%.4f,%.4f)"
        % (
            len(reference_points),
            len(reference_band),
            *reference_lows,
            *reference_highs,
        )
    )
    expected_lows, expected_highs = EXPECTED_ENVELOPE
    for axis, (actual, expected) in enumerate(zip(reference_lows, expected_lows)):
        if abs(actual - expected) > ENVELOPE_TOLERANCE_M:
            failures.append("intact 包络 min[%d]=%.6f != %.6f" % (axis, actual, expected))
    for axis, (actual, expected) in enumerate(zip(reference_highs, expected_highs)):
        if abs(actual - expected) > ENVELOPE_TOLERANCE_M:
            failures.append("intact 包络 max[%d]=%.6f != %.6f" % (axis, actual, expected))
    if not reference_band:
        failures.append("intact 端头带为 0（哨兵：后面的比对会假绿）")

    for key, file_name in VARIANTS.items():
        path = COMPONENTS / file_name
        document, binary = read_glb(path)
        points = read_positions(document, binary)
        variant_band = band(points)
        lows, highs = envelope(points)
        mismatch = None
        if lows != reference_lows or highs != reference_highs:
            mismatch = "包络不同 %s~%s" % (lows, highs)
        elif len(variant_band) != len(reference_band):
            mismatch = "端头带顶点数 %d != %d" % (len(variant_band), len(reference_band))
        else:
            for index in range(len(variant_band)):
                if bit_key(variant_band[index]) != bit_key(reference_band[index]):
                    mismatch = "端头带第 %d 点逐位不同 %s vs %s" % (
                        index,
                        variant_band[index],
                        reference_band[index],
                    )
                    break
        print(
            "DMG_BANDS %-6s verts=%d band=%d envelope=(%.4f,%.4f,%.4f)~(%.4f,%.4f,%.4f) band_bit_identical=%s"
            % (
                key,
                len(points),
                len(variant_band),
                *lows,
                *highs,
                "false" if mismatch else "true",
            )
        )
        if mismatch:
            failures.append("%s %s" % (key, mismatch))

    if failures:
        for failure in failures:
            print("DMG_BANDS_FAIL %s" % failure)
        print("DMG_BANDS_DONE samples=%d failures=%d" % (len(VARIANTS), len(failures)))
        return 1
    print("DMG_BANDS_OK variants=%d band_bit_identical=true envelope_identical=true" % len(VARIANTS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
