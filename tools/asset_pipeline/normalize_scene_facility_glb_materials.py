"""Canonicalize materials in current Base99 scene/facility GLBs.

Only material names, material indices and the JSON chunk are changed. Mesh,
accessor, image, sampler and binary payload chunks are preserved byte-for-byte.
"""
from __future__ import annotations

import argparse
import json
import re
import struct
from pathlib import Path


ROLE_RULES = (
    ("01_精工金属", "01_精工金属_紫色骨架"),
    ("02_细腻哑光", "02_细腻哑光_青绿大面"),
    ("03_清漆反光", "03_清漆反光_紫粉点缀"),
    ("04_柔和自发光", "04_柔和自发光_UI灯光"),
)
ROLE_ORDER = {canonical: index for index, (_, canonical) in enumerate(ROLE_RULES)}
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


def canonical_role(name: str) -> str | None:
    for prefix, canonical in ROLE_RULES:
        if name == canonical or name.startswith(prefix):
            return canonical
    return None


def read_glb(path: Path) -> tuple[list[tuple[int, bytes]], dict]:
    data = path.read_bytes()
    magic, version, total = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or version != 2 or total != len(data):
        raise RuntimeError(f"Invalid GLB header: {path}")
    chunks = []
    offset = 12
    document = None
    while offset < len(data):
        length, kind = struct.unpack_from("<II", data, offset)
        offset += 8
        payload = data[offset:offset + length]
        offset += length
        chunks.append((kind, payload))
        if kind == JSON_CHUNK:
            document = json.loads(payload.decode("utf-8").rstrip("\x00 "))
    if document is None:
        raise RuntimeError(f"Missing JSON chunk: {path}")
    return chunks, document


def write_glb(path: Path, chunks: list[tuple[int, bytes]], document: dict) -> None:
    encoded = json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    encoded += b" " * ((4 - len(encoded) % 4) % 4)
    output_chunks = []
    for kind, payload in chunks:
        if kind == JSON_CHUNK:
            payload = encoded
        elif kind == BIN_CHUNK:
            payload += b"\x00" * ((4 - len(payload) % 4) % 4)
        output_chunks.append((kind, payload))
    total = 12 + sum(8 + len(payload) for _, payload in output_chunks)
    with path.open("wb") as handle:
        handle.write(struct.pack("<III", 0x46546C67, 2, total))
        for kind, payload in output_chunks:
            handle.write(struct.pack("<II", len(payload), kind))
            handle.write(payload)


def normalize(path: Path, dry_run: bool) -> dict:
    chunks, document = read_glb(path)
    materials = document.get("materials", [])
    if not materials:
        return {"file": str(path), "before": [], "after": [], "changed": False}

    before = [material.get("name", f"material_{index}") for index, material in enumerate(materials)]
    primary_by_role: dict[str, int] = {}
    for index, material in enumerate(materials):
        role = canonical_role(material.get("name", ""))
        if role is None:
            continue
        current = primary_by_role.get(role)
        if current is None or material.get("name", "") == role:
            primary_by_role[role] = index

    old_to_new: dict[int, int] = {}
    new_materials = []
    for old_index, material in enumerate(materials):
        role = canonical_role(material.get("name", ""))
        if role is None:
            target_index = primary_by_role.get(material.get("name", ""), old_index)
            if target_index == old_index:
                primary_by_role[material.get("name", "")] = old_index
            old_to_new[old_index] = -1
            continue
        primary = primary_by_role[role]
        if primary == old_index:
            old_to_new[old_index] = old_index

    selected = []
    for old_index, material in enumerate(materials):
        role = canonical_role(material.get("name", ""))
        if role is not None and primary_by_role.get(role) != old_index:
            continue
        target = dict(material)
        if role is not None:
            target["name"] = role
        selected.append((old_index, target))

    role_to_new: dict[str, int] = {}
    for new_index, (old_index, material) in enumerate(selected):
        old_to_new[old_index] = new_index
        role = canonical_role(material.get("name", ""))
        if role is not None:
            role_to_new[role] = new_index
        new_materials.append(material)

    # Every legacy copy must map to the selected material for its role.
    for old_index, material in enumerate(materials):
        role = canonical_role(material.get("name", ""))
        if role is not None:
            old_to_new[old_index] = role_to_new[role]

    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            if "material" in primitive:
                primitive["material"] = old_to_new.get(primitive["material"], primitive["material"])
    variants = document.get("extensions", {}).get("KHR_materials_variants", {}).get("variants", [])
    for variant in variants:
        if "material" in variant:
            variant["material"] = old_to_new.get(variant["material"], variant["material"])

    document["materials"] = new_materials
    after = [material.get("name", "") for material in new_materials]
    changed = before != after or len(before) != len(after)
    if changed and not dry_run:
        write_glb(path, chunks, document)
    return {"file": str(path), "before": before, "after": after, "changed": changed}


def referenced_glbs(project: Path) -> list[Path]:
    runtime = project / "assets/art/environments/base_facility_3d/runtime"
    refs = set()
    for scene in runtime.rglob("*.tscn"):
        text = scene.read_text(encoding="utf-8", errors="ignore")
        for match in re.finditer(r'path="res://([^"]+\.glb)"', text):
            refs.add((project / match.group(1)).resolve())
    return sorted(refs)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--root", type=Path)
    parser.add_argument("--referenced-only", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    project = args.project.resolve()
    if args.root:
        paths = sorted(args.root.resolve().rglob("*.glb"))
    elif args.referenced_only:
        paths = referenced_glbs(project)
    else:
        paths = sorted((project / "assets/art/environments/base_facility_3d/components").rglob("*.glb"))
    reports = [normalize(path, args.dry_run) for path in paths]
    changed = [report for report in reports if report["changed"]]
    print(f"GLB_MATERIAL_NORMALIZE files={len(reports)} changed={len(changed)} dry_run={args.dry_run}")
    for report in changed:
        print(report["file"])
        print("  before=" + ",".join(report["before"]))
        print("  after=" + ",".join(report["after"]))


if __name__ == "__main__":
    main()


