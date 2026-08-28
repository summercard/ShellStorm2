"""Remove per-GLB palette copies and bind Godot imports to one shared palette.

Dry-run is the default. Pass --apply only after reviewing the resolved GLB and
duplicate PNG list. The GLB rewrite removes texture/image JSON plus embedded
image buffer views while preserving all geometry buffers and material roles.
"""

from __future__ import annotations

import argparse
import json
import re
import struct
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[2]
GLB_ROOTS = (
    PROJECT_ROOT / "assets/art/environments",
    PROJECT_ROOT / "assets/art/props/base_world_3d",
)
COMPONENT_ROOTS = (
    PROJECT_ROOT / "assets/art/environments/base_facility_3d/components",
    PROJECT_ROOT / "assets/art/props/base_world_3d/components",
)
LEGACY_SOURCE_TEXTURE_ROOT = PROJECT_ROOT / "assets/art/environments/base_facility_3d/source/env_base99_modular_room/textures"
POST_IMPORT = "res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"
SHARED_PALETTE = PROJECT_ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
PALETTE_TOKENS = ("多巴胺色盘", "palette_dopamine")
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


def parse_glb(path: Path) -> tuple[dict[str, Any], bytes]:
    data = path.read_bytes()
    magic, version, declared_length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2 or declared_length != len(data):
        raise ValueError("Unsupported GLB header: %s" % path)
    offset = 12
    document: dict[str, Any] | None = None
    binary = b""
    while offset < len(data):
        length, chunk_type = struct.unpack_from("<II", data, offset)
        payload = data[offset + 8 : offset + 8 + length]
        if chunk_type == JSON_CHUNK:
            document = json.loads(payload.rstrip(b" \x00"))
        elif chunk_type == BIN_CHUNK:
            binary = payload
        offset += 8 + length
    if document is None:
        raise ValueError("GLB has no JSON chunk: %s" % path)
    return document, binary


def write_glb(path: Path, document: dict[str, Any], binary: bytes) -> None:
    json_payload = json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    json_payload += b" " * ((4 - len(json_payload) % 4) % 4)
    binary += b"\x00" * ((4 - len(binary) % 4) % 4)
    chunks = struct.pack("<II", len(json_payload), JSON_CHUNK) + json_payload
    if binary:
        chunks += struct.pack("<II", len(binary), BIN_CHUNK) + binary
    payload = struct.pack("<4sII", b"glTF", 2, 12 + len(chunks)) + chunks
    path.write_bytes(payload)


def is_palette_glb(document: dict[str, Any]) -> bool:
    images = document.get("images", [])
    if not images:
        return False
    descriptors = "|".join(str(image.get("name", "")) + str(image.get("uri", "")) for image in images)
    return any(token.lower() in descriptors.lower() for token in PALETTE_TOKENS)


def strip_texture_slots(value: Any) -> None:
    if isinstance(value, dict):
        for key in list(value):
            child = value[key]
            if key.lower().endswith("texture") and isinstance(child, dict) and "index" in child:
                del value[key]
                continue
            strip_texture_slots(child)
    elif isinstance(value, list):
        for child in value:
            strip_texture_slots(child)


def remap_buffer_views(value: Any, mapping: dict[int, int]) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key == "bufferView" and isinstance(child, int):
                if child not in mapping:
                    raise ValueError("Removed image bufferView is still referenced: %d" % child)
                value[key] = mapping[child]
            else:
                remap_buffer_views(child, mapping)
    elif isinstance(value, list):
        for child in value:
            remap_buffer_views(child, mapping)


def strip_embedded_palette(document: dict[str, Any], binary: bytes) -> bytes:
    removed_views = {
        int(image["bufferView"])
        for image in document.get("images", [])
        if "bufferView" in image
    }
    strip_texture_slots(document.get("materials", []))
    document.pop("images", None)
    document.pop("textures", None)
    document.pop("samplers", None)
    if not removed_views:
        return binary

    old_views = document.get("bufferViews", [])
    new_views: list[dict[str, Any]] = []
    mapping: dict[int, int] = {}
    rebuilt = bytearray()
    for old_index, old_view in enumerate(old_views):
        if old_index in removed_views:
            continue
        while len(rebuilt) % 4:
            rebuilt.append(0)
        start = int(old_view.get("byteOffset", 0))
        length = int(old_view["byteLength"])
        copied = dict(old_view)
        copied["byteOffset"] = len(rebuilt)
        mapping[old_index] = len(new_views)
        new_views.append(copied)
        rebuilt.extend(binary[start : start + length])
    document["bufferViews"] = new_views
    remap_buffer_views(document, mapping)
    if document.get("buffers"):
        document["buffers"][0]["byteLength"] = len(rebuilt)
    return bytes(rebuilt)


def patch_import_settings(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    text, script_count = re.subn(r'import_script/path="[^"]*"', 'import_script/path="%s"' % POST_IMPORT, text)
    text, handling_count = re.subn(r"gltf/embedded_image_handling=\d+", "gltf/embedded_image_handling=0", text)
    if script_count != 1 or handling_count != 1:
        raise ValueError("Unexpected Godot import settings: %s" % path)
    path.write_text(text, encoding="utf-8")


def duplicate_palette_files() -> list[Path]:
    roots = (*COMPONENT_ROOTS, LEGACY_SOURCE_TEXTURE_ROOT)
    return sorted({
        path
        for root in roots
        if root.exists()
        for path in root.rglob("*.png")
        if any(token.lower() in path.name.lower() for token in PALETTE_TOKENS)
    })


def discover_palette_glbs() -> list[Path]:
    result = []
    for root in GLB_ROOTS:
        for path in root.rglob("*.glb"):
            document, _ = parse_glb(path)
            if is_palette_glb(document):
                result.append(path)
    return sorted(result)


def verify(glbs: list[Path]) -> None:
    failures = []
    for path in glbs:
        document, _ = parse_glb(path)
        if document.get("images") or document.get("textures"):
            failures.append("embedded texture remains: %s" % path)
        import_path = Path(str(path) + ".import")
        if not import_path.exists():
            failures.append("missing import file: %s" % import_path)
            continue
        text = import_path.read_text(encoding="utf-8")
        if 'import_script/path="%s"' % POST_IMPORT not in text or "gltf/embedded_image_handling=0" not in text:
            failures.append("shared import contract missing: %s" % import_path)
    leftovers = duplicate_palette_files()
    failures.extend("duplicate PNG remains: %s" % path for path in leftovers)
    palette_import = Path(str(SHARED_PALETTE) + ".import")
    if not SHARED_PALETTE.exists() or not palette_import.exists():
        failures.append("shared palette or import contract missing: %s" % SHARED_PALETTE)
    else:
        palette_text = palette_import.read_text(encoding="utf-8")
        if "compress/mode=0" not in palette_text or "mipmaps/generate=false" not in palette_text:
            failures.append("shared palette must import losslessly without mipmaps: %s" % palette_import)
    if failures:
        raise SystemExit("\n".join(failures))
    print("SCENE_FACILITY_SHARED_PALETTE_STATIC_OK:glbs=%d:duplicate_pngs=0" % len(glbs))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    glbs = discover_palette_glbs()
    duplicates = duplicate_palette_files()
    print("PALETTE_GLB_COUNT=%d" % len(glbs))
    print("DUPLICATE_PALETTE_PNG_COUNT=%d" % len(duplicates))
    if args.verify:
        # After migration, discovery by embedded image is empty; verify every
        # explicitly managed import instead.
        managed = sorted(path for root in COMPONENT_ROOTS for path in root.rglob("*.glb"))
        verify(managed)
        return
    if not args.apply:
        for path in glbs:
            print("WOULD_REWRITE:%s" % path.relative_to(PROJECT_ROOT))
        for path in duplicates:
            print("WOULD_DELETE:%s" % path.relative_to(PROJECT_ROOT))
        return
    if len(glbs) != 44:
        raise SystemExit("Refusing unexpected palette GLB count: %d (expected 44)" % len(glbs))
    for path in glbs:
        document, binary = parse_glb(path)
        binary = strip_embedded_palette(document, binary)
        write_glb(path, document, binary)
        patch_import_settings(Path(str(path) + ".import"))
    for path in duplicates:
        import_path = Path(str(path) + ".import")
        path.unlink()
        if import_path.exists():
            import_path.unlink()
    print("SCENE_FACILITY_SHARED_PALETTE_APPLIED:glbs=%d:deleted_pngs=%d" % (len(glbs), len(duplicates)))


if __name__ == "__main__":
    main()
