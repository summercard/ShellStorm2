"""Repair Base99 source/derived/import JSON lineage for the current asset policy."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


SHA_TARGETS = {
    "source_blend_sha256": ("source_blend",),
    "source_sha256": ("source_blend", "source"),
    "derived_sha256": ("derived_blend", "derived"),
    "glb_sha256": ("glb", "visual_glb", "exported_glb"),
    "visual_glb_sha256": ("visual_glb", "glb"),
    "sha256": ("visual_glb", "glb", "source_blend", "source", "derived_blend", "derived"),
}


def normalize_path(value: str) -> str:
    old = value
    value = value.replace(
        "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_",
        "source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_",
    )
    replacements = {
        "source/art/blender/base_facility_layout/v021/base_facility_runtime_layout_hq_v021_structural.blend":
            "source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v021.blend",
        "source/art/blender/base_facility_layout/v021/base_facility_runtime_layout_hq_v021_wall_contents.blend":
            "source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v021.blend",
        "source/art/blender/base_facility_layout/v021/base_facility_runtime_layout_hq_v021_remaining_facilities.blend":
            "source/art/blender/base_facility_layout/export/v021/base_facility_runtime_layout_hq-v021-remaining_facilities.blend",
        "assets/art/environments/base_facility_3d/components/env_base99_remaining_facilities_v021/volumetric_dust_fx/volumetric_dust_fx_visual_top3d_v001.glb":
            "assets/art/vfx/environment_3d/base_facility_dust_particles/vfx_base99_dust_particles_root_top3d_v001.tscn",
        "assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities_v021/volumetric_dust_fx/volumetric_dust_fx_root_top3d_v001.tscn":
            "assets/art/vfx/environment_3d/base_facility_dust_particles/vfx_base99_dust_particles_root_top3d_v001.tscn",
    }
    value = replacements.get(value, value)
    if value != old:
        return value
    return value


def resolve(root: Path, value: str) -> Path | None:
    if not isinstance(value, str):
        return None
    value = normalize_path(value)
    if value.startswith("res://"):
        value = value[6:]
    if not value or value.startswith("=") or value.startswith("/"):
        return None
    if not re.match(r"^(assets|source|scenes|src|tools)/", value):
        return None
    return root / value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def repair(root: Path, path: Path, dry_run: bool) -> tuple[int, int]:
    data = json.loads(path.read_text(encoding="utf-8"))
    path_fixes = 0
    hash_fixes = 0

    def walk(value):
        nonlocal path_fixes, hash_fixes
        if isinstance(value, dict):
            for key in list(value):
                child = value[key]
                if isinstance(child, str):
                    fixed = normalize_path(child)
                    if fixed != child:
                        value[key] = fixed
                        path_fixes += 1
                walk(child)
            for sha_key, target_keys in SHA_TARGETS.items():
                if sha_key not in value or not isinstance(value[sha_key], str):
                    continue
                target = next((value.get(key) for key in target_keys if isinstance(value.get(key), str)), None)
                resolved = resolve(root, target) if target else None
                if resolved is not None and resolved.is_file():
                    actual = sha256(resolved)
                    if actual != value[sha_key]:
                        value[sha_key] = actual
                        hash_fixes += 1
        elif isinstance(value, list):
            for child in value:
                walk(child)

    walk(data)
    if not dry_run:
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return path_fixes, hash_fixes


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    root = args.project.resolve()
    json_files = {
        root / "assets/art/asset_import_manifest_v001.json",
        *sorted((root / "assets/art/environments/base_facility_3d").rglob("*.json")),
        *sorted((root / "source/art/blender/base_facility_layout/export").rglob("*.json")),
    }
    total_paths = total_hashes = 0
    for path in sorted(json_files):
        paths, hashes = repair(root, path, args.dry_run)
        total_paths += paths
        total_hashes += hashes
        if paths or hashes:
            print(f"LINEAGE_REPAIR {path.relative_to(root)} paths={paths} hashes={hashes}")
    print(f"BASE99_LINEAGE_REPAIR files={len(json_files)} paths={total_paths} hashes={total_hashes} dry_run={args.dry_run}")


if __name__ == "__main__":
    main()
