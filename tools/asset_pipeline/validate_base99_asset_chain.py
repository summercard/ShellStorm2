"""Validate the current Base99 Blender -> GLB -> PackedScene -> ledger chain."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
from pathlib import Path


ROLE_NAMES = {
    "01_精工金属_紫色骨架",
    "02_细腻哑光_青绿大面",
    "03_清漆反光_紫粉点缀",
    "04_柔和自发光_UI灯光",
}
SHA_TARGETS = {
    "source_blend_sha256": ("source_blend",),
    "source_sha256": ("source_blend", "source"),
    "derived_sha256": ("derived_blend", "derived"),
    "glb_sha256": ("glb", "visual_glb"),
    "visual_glb_sha256": ("visual_glb", "glb"),
    "sha256": ("visual_glb", "glb"),
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_glb_json(path: Path) -> dict:
    with path.open("rb") as handle:
        magic, version, total = struct.unpack("<III", handle.read(12))
        if magic != 0x46546C67 or version != 2 or total != path.stat().st_size:
            raise RuntimeError(f"invalid GLB header: {path}")
        while handle.tell() < total:
            length, kind = struct.unpack("<II", handle.read(8))
            payload = handle.read(length)
            if kind == 0x4E4F534A:
                return json.loads(payload.decode("utf-8").rstrip("\x00 "))
    raise RuntimeError(f"GLB has no JSON chunk: {path}")


def json_path(value: str, root: Path) -> Path | None:
    if value.startswith("res://"):
        value = value[6:]
    if not value or value.startswith("=") or not re.match(r"^(assets|source|scenes|src|tools)/", value):
        return None
    return root / value


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    root = args.project.resolve()
    errors: list[str] = []

    source_root = root / "source/art/blender/base_facility_layout/source"
    sources = sorted(source_root.glob("base_facility_runtime_layout_hq_v*.blend"))
    latest = max(sources, key=lambda p: int(re.search(r"v(\d{3})\.blend$", p.name).group(1)))
    if latest.name != "base_facility_runtime_layout_hq_v026.blend":
        errors.append(f"unexpected current master: {latest.name}")

    runtime = root / "assets/art/environments/base_facility_3d/runtime"
    layout = runtime / "env_base_facility_art_layout_top3d_v002.tscn"
    layout_text = layout.read_text(encoding="utf-8")
    if re.search(r'path="res://[^"]+\.glb"', layout_text):
        errors.append("art layout directly references a GLB")

    referenced_glbs = set()
    for scene in runtime.rglob("*.tscn"):
        text = scene.read_text(encoding="utf-8", errors="ignore")
        for match in re.finditer(r'path="res://([^"]+)"', text):
            target = root / match.group(1)
            if not target.exists():
                errors.append(f"missing tscn reference: {scene.relative_to(root)} -> {match.group(1)}")
            if target.suffix.lower() == ".glb":
                referenced_glbs.add(target.resolve())

    for glb in sorted(referenced_glbs):
        document = load_glb_json(glb)
        names = [material.get("name", "") for material in document.get("materials", [])]
        if len(names) > 4:
            errors.append(f"{glb.relative_to(root)} has {len(names)} materials")
        for name in names:
            if name not in ROLE_NAMES:
                errors.append(f"{glb.relative_to(root)} has non-canonical material {name}")
        if document.get("images") or document.get("textures"):
            errors.append(f"{glb.relative_to(root)} embeds images/textures")
        material_count = len(document.get("materials", []))
        for mesh in document.get("meshes", []):
            for primitive in mesh.get("primitives", []):
                material_index = primitive.get("material")
                if material_index is not None and (not isinstance(material_index, int) or material_index >= material_count):
                    errors.append(f"{glb.relative_to(root)} has invalid material index {material_index}")
        import_path = Path(str(glb) + ".import")
        if not import_path.is_file():
            errors.append(f"missing import contract: {import_path.relative_to(root)}")
            continue
        import_text = import_path.read_text(encoding="utf-8", errors="ignore")
        if "gltf/embedded_image_handling=0" not in import_text:
            errors.append(f"embedded_image_handling != 0: {import_path.relative_to(root)}")
        if 'import_script/path=""' in import_text:
            errors.append(f"missing post-import palette script: {import_path.relative_to(root)}")

    palette_import = root / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png.import"
    palette_text = palette_import.read_text(encoding="utf-8")
    if "compress/mode=0" not in palette_text or "mipmaps/generate=false" not in palette_text:
        errors.append("palette import contract is not lossless/no-mipmap")
    if list((root / "assets/art/environments/base_facility_3d/components").rglob("*.png")):
        errors.append("private PNG files remain under Base99 components")

    json_files = {
        root / "assets/art/asset_import_manifest_v001.json",
        *sorted((root / "assets/art/environments/base_facility_3d").rglob("*.json")),
        *sorted((root / "source/art/blender/base_facility_layout/export").rglob("*.json")),
    }
    for path in json_files:
        data = json.loads(path.read_text(encoding="utf-8"))

        def walk(value):
            if isinstance(value, dict):
                for key, child in value.items():
                    if isinstance(child, str):
                        target = json_path(child, root)
                        if target is not None and not target.exists():
                            errors.append(f"missing JSON path: {path.relative_to(root)} {key}={child}")
                    if isinstance(child, str) and key.lower().endswith("sha256"):
                        target_value = next((value.get(name) for name in SHA_TARGETS.get(key.lower(), ()) if isinstance(value.get(name), str)), None)
                        target = json_path(target_value, root) if target_value else None
                        if target is not None and target.is_file() and sha256(target) != child:
                            errors.append(f"JSON hash mismatch: {path.relative_to(root)} {key} -> {target.relative_to(root)}")
                    walk(child)
            elif isinstance(value, list):
                for child in value:
                    walk(child)

        walk(data)

    if errors:
        print(f"BASE99_ASSET_CHAIN_INVALID errors={len(errors)}")
        for error in errors:
            print(" -", error)
        raise SystemExit(1)
    print(
        "BASE99_ASSET_CHAIN_OK",
        f"master={latest.name}",
        f"referenced_glbs={len(referenced_glbs)}",
        f"json_manifests={len(json_files)}",
    )


if __name__ == "__main__":
    main()
