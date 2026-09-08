"""Integrate the 30 audited Base Facility v021 package exports into Godot.

This consumes the Blender-generated export/v021/export_manifest.json.  It keeps
all previous GLBs and PackedScenes, creates v002 package wrappers (v004 for the
floor assembly), updates only the three existing aggregate references, and
writes an auditable Godot import ledger.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[2]
EXPORT_MANIFEST = PROJECT / "source/art/blender/base_facility_layout/export/v021/export_manifest.json"
COMPONENTS = PROJECT / "assets/art/environments/base_facility_3d/components"
RUNTIME = PROJECT / "assets/art/environments/base_facility_3d/runtime"
SOURCE_LEDGER = PROJECT / "assets/art/environments/base_facility_3d/source"
GLOBAL_LEDGER = PROJECT / "assets/art/asset_import_manifest_v001.json"

WALL_SLUGS = {
    "loft_tool_pegboard",
    "loft_explore_poster",
    "loft_hanging_plant",
    "hose_reel",
    "south_wall_information_boards",
}
FLOOR_SLUG = "loft_floor_finish"
VISUAL_ONLY = {
    "loft_bedside_lamp",
    "loft_bedside_rug",
    "loft_striped_privacy_curtain",
    "loft_lounge_rug",
    "east_plant_group",
}


def project_path(path: Path) -> str:
    return str(path.relative_to(PROJECT)).replace("\\", "/")


def res_path(path: Path) -> str:
    return "res://" + project_path(path)


def read_export() -> tuple[dict, list[dict]]:
    data = json.loads(EXPORT_MANIFEST.read_text(encoding="utf-8"))
    packages = []
    for scope in ("remaining_facilities", "floor_visuals"):
        section = data["scopes"].get(scope)
        if not section:
            raise RuntimeError(f"Missing {scope} from {EXPORT_MANIFEST}")
        for package in section["packages"]:
            package = dict(package)
            package["scope"] = scope
            packages.append(package)
    if len(packages) != 30:
        raise RuntimeError(f"Expected exactly 30 audited packages, found {len(packages)}")
    return data, packages


def glb_for(package: dict) -> Path:
    stem = f"{package['slug']}_visual_top3d_"
    candidates = sorted((PROJECT / package["scope"] if False else COMPONENTS).glob(f"**/{package['slug']}/{stem}v*.glb"))
    # The exporter places the two scopes in their corresponding Godot component roots.
    candidates = [path for path in candidates if ("floor_visuals" in str(path)) == (package["scope"] == "floor_visuals")]
    if not candidates:
        raise RuntimeError(f"Missing freshly exported GLB for {package['slug']}")
    # Existing GLBs are retained for rollback; the greatest numeric suffix is the
    # exporter-created replacement for package streams that already had v001.
    return max(candidates, key=lambda path: int(path.stem.rsplit("v", 1)[1]))


def bbox_to_godot(bbox: dict) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    lo, hi = bbox["min"], bbox["max"]
    # Blender (X, Y, Z) becomes Godot (X, Z, -Y) under the GLB Y-up export.
    center = ((lo[0] + hi[0]) / 2, (lo[2] + hi[2]) / 2, -(lo[1] + hi[1]) / 2)
    size = (hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1])
    return center, size


def v3(value: tuple[float, float, float]) -> str:
    return "Vector3(" + ", ".join(f"{part:.6f}" for part in value) + ")"


def wrapper_path(slug: str) -> Path:
    return RUNTIME / "env_base99_remaining_facilities_v021" / slug / f"{slug}_root_top3d_v002.tscn"


def configure_glb_import_contract(glb: Path, dry_run: bool) -> None:
    """Bind every replacement GLB to the source-controlled shared-palette import hook."""
    target = Path(str(glb) + ".import")
    if not target.is_file():
        raise RuntimeError(f"Godot has not generated an import contract for {glb}")
    text = target.read_text(encoding="utf-8")
    text = text.replace('import_script/path=""', 'import_script/path="res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"')
    text = text.replace("gltf/embedded_image_handling=1", "gltf/embedded_image_handling=0")
    if not dry_run:
        target.write_text(text, encoding="utf-8")


def floor_wrapper_path() -> Path:
    return RUNTIME / "env_base99_floor_visuals_v021/loft_floor_finish/loft_floor_finish_root_top3d_v003.tscn"


def write_floor_wrapper(glb: Path, dry_run: bool) -> Path:
    target = floor_wrapper_path()
    text = "\n".join([
        "[gd_scene load_steps=2 format=3]",
        "",
        f'[ext_resource type="PackedScene" path="{res_path(glb)}" id="1_visual"]',
        "",
        '[node name="116_二楼地板色彩深化_资产包" type="Node3D"]',
        'metadata/asset_id = "ENV-BASE99-OPTIMIZED-V021::loft_floor_finish"',
        'metadata/asset_version = "v021"',
        'metadata/visual_only = true',
        'metadata/collision_policy = "visual_only_no_collision"',
        'metadata/source_blend = "res://source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v021.blend"',
        'metadata/derived_blend = "res://source/art/blender/base_facility_layout/export/v021/base_facility_runtime_layout_hq-v021-floor_visuals.blend"',
        'metadata/placement_policy = "baked world coordinates from Blender; root stays at origin"',
        "",
        '[node name="ImportedModel" parent="." instance=ExtResource("1_visual")]',
        "",
    ])
    if not dry_run:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
    return target


def write_wrapper(package: dict, glb: Path, dry_run: bool) -> Path:
    target = wrapper_path(package["slug"])
    visual_only = package["slug"] in VISUAL_ONLY
    text = [
        "[gd_scene load_steps=2 format=3]" if visual_only else "[gd_scene load_steps=3 format=3]",
        "",
        f'[ext_resource type="PackedScene" path="{res_path(glb)}" id="1_visual"]',
    ]
    if not visual_only:
        center, size = bbox_to_godot(package["bbox_blender"])
        text.extend([
            "",
            '[sub_resource type="BoxShape3D" id="Box_optimized_bounds"]',
            f"size = {v3(size)}",
        ])
    text.extend([
        "",
        f'[node name="{package["collection"]}" type="Node3D"]',
        f'metadata/asset_id = "ENV-BASE99-OPTIMIZED-V021::{package["slug"]}"',
        'metadata/asset_version = "v021"',
        'metadata/source_blend = "res://source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v021.blend"',
        f'metadata/derived_blend = "res://source/art/blender/base_facility_layout/export/v021/base_facility_runtime_layout_hq-v021-{package["scope"]}.blend"',
        f'metadata/source_collection = "{package["source_output_collection"]}"',
        f'metadata/forward = "{package["forward"]}"',
        f'metadata/triangles_before = {package["triangles_before"]}',
        f'metadata/triangles_after = {package["triangles_after"]}',
        f'metadata/downward_triangles_removed = {package["downward_triangles_removed"]}',
        f'metadata/collision_policy = "{"visual_only_no_collision" if visual_only else "optimized_output_bounds_box"}"',
        'metadata/placement_policy = "baked world coordinates from Blender; root stays at origin"',
        "",
        '[node name="ImportedModel" parent="." instance=ExtResource("1_visual")]',
    ])
    if not visual_only:
        text.extend([
            "",
            '[node name="StaticCollision" type="StaticBody3D" parent="."]',
            "collision_layer = 1",
            "collision_mask = 1",
            "",
            '[node name="OptimizedOutputBounds" type="CollisionShape3D" parent="StaticCollision"]',
            f"position = {v3(center)}",
            'shape = SubResource("Box_optimized_bounds")',
        ])
    text.append("")
    if not dry_run:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("\n".join(text), encoding="utf-8")
    return target


def update_remaining_root(packages: list[dict], wrappers: dict[str, Path], dry_run: bool) -> Path:
    old = RUNTIME / "env_base99_remaining_facilities_v021/env_base99_remaining_facilities_root_top3d_v001.tscn"
    target = old.with_name("env_base99_remaining_facilities_root_top3d_v002.tscn")
    text = old.read_text(encoding="utf-8")
    for package in packages:
        slug = package["slug"]
        if slug in WALL_SLUGS or slug == FLOOR_SLUG:
            continue
        old_ref = f"{slug}_root_top3d_v001.tscn"
        if old_ref not in text:
            raise RuntimeError(f"{old} does not reference {old_ref}")
        text = text.replace(old_ref, f"{slug}_root_top3d_v002.tscn")
    text = text.replace('metadata/source_blend = "res://source/art/blender/base_facility_layout/v021/base_facility_runtime_layout_hq_v021_remaining_facilities.blend"',
                        'metadata/source_blend = "res://source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v021.blend"')
    text = text.replace('metadata/derived_from_blender = "base_facility_runtime_layout_hq_v017.blend"',
                        'metadata/derived_blend = "res://source/art/blender/base_facility_layout/export/v021/base_facility_runtime_layout_hq-v021-remaining_facilities.blend"')
    text = text.replace('metadata/derived_from_version = "v017"', 'metadata/derived_from_version = "v021"')
    text = text.replace('metadata/package_count = 45', 'metadata/package_count = 45\nmetadata/optimized_package_count = 24')
    if not dry_run:
        target.write_text(text, encoding="utf-8")
    return target


def update_wall_root(packages: list[dict], glbs: dict[str, Path], dry_run: bool) -> Path:
    old = RUNTIME / "env_base99_wall_contents_v021/env_base99_wall_contents_root_top3d_v001.tscn"
    target = old.with_name("env_base99_wall_contents_root_top3d_v002.tscn")
    text = old.read_text(encoding="utf-8")
    for package in packages:
        slug = package["slug"]
        if slug not in WALL_SLUGS:
            continue
        old_ref = res_path(
            COMPONENTS / "env_base99_wall_contents_v021" / slug / f"{slug}_visual_top3d_v001.glb"
        )
        if old_ref not in text:
            raise RuntimeError(f"{old} does not reference {old_ref}")
        text = text.replace(old_ref, res_path(glbs[slug]))
    text = text.replace('metadata/source_blend = "res://source/art/blender/base_facility_layout/v021/base_facility_runtime_layout_hq_v021_wall_contents.blend"',
                        'metadata/source_blend = "res://source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v021.blend"')
    text = text.replace('metadata/derived_from_blender = "base_facility_runtime_layout_hq_v017.blend"',
                        'metadata/derived_blend = "res://source/art/blender/base_facility_layout/export/v021/base_facility_runtime_layout_hq-v021-remaining_facilities.blend"')
    text = text.replace('metadata/derived_from_version = "v017"', 'metadata/derived_from_version = "v021"')
    text = text.replace('metadata/runtime_mesh_count = 18', 'metadata/runtime_mesh_count = 18\nmetadata/optimized_package_count = 5')
    if not dry_run:
        target.write_text(text, encoding="utf-8")
    return target


def update_floor_root(floor_wrapper: Path, dry_run: bool) -> Path:
    old = RUNTIME / "env_base99_floor_visuals_v021/env_base99_floor_visuals_root_top3d_v003.tscn"
    target = old.with_name("env_base99_floor_visuals_root_top3d_v004.tscn")
    text = old.read_text(encoding="utf-8")
    old_ref = res_path(
        RUNTIME / "env_base99_loft_floor_finish_v020/env_base99_loft_floor_finish_v020_root_top3d_v002.tscn"
    )
    if old_ref not in text:
        raise RuntimeError(f"{old} does not reference the previous loft finish")
    text = text.replace(old_ref, res_path(floor_wrapper))
    text = text.replace('metadata/asset_id = "ENV-BASE99-FLOOR-VISUAL-LAYOUT-V017"',
                        'metadata/asset_id = "ENV-BASE99-FLOOR-VISUAL-LAYOUT-V021"')
    text = text.replace('metadata/runtime_export_version = "v003"', 'metadata/runtime_export_version = "v004"')
    text = text.replace('metadata/source_blend = "res://source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v020.blend"',
                        'metadata/source_blend = "res://source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v021.blend"')
    text = text.replace('metadata/source_blender_version = "v020"', 'metadata/source_blender_version = "v021"')
    text = text.replace('Uses Blender V020 baked placement', 'Uses Blender V021 optimized export placement')
    if not dry_run:
        target.write_text(text, encoding="utf-8")
    return target


def update_layout(remaining: Path, wall: Path, floor: Path, dry_run: bool) -> Path:
    target = RUNTIME / "env_base_facility_art_layout_top3d_v001.tscn"
    text = target.read_text(encoding="utf-8")
    replacements = {
        "env_base99_remaining_facilities_root_top3d_v001.tscn": remaining.name,
        "env_base99_wall_contents_root_top3d_v001.tscn": wall.name,
        "env_base99_floor_visuals_root_top3d_v003.tscn": floor.name,
        'metadata/source_layout = "base_facility_runtime_layout_hq_v020.blend"':
            'metadata/source_layout = "base_facility_runtime_layout_hq_v021.blend"',
        'metadata/source_blender_version = "v020"': 'metadata/source_blender_version = "v021"',
    }
    for old, new in replacements.items():
        if old not in text and new not in text:
            raise RuntimeError(f"{target} does not contain expected reference {old}")
        if old in text:
            text = text.replace(old, new)
    if not dry_run:
        target.write_text(text, encoding="utf-8")
    return target


def update_blender_catalogs(packages: list[dict], dry_run: bool) -> None:
    catalog_versions = {"v019", "v020", "v021"}
    wanted = {package["slug"] for package in packages}
    for version in catalog_versions:
        path = PROJECT / f"source/art/blender/base_facility_layout/component_packages/{version}/catalog.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        for row in data:
            if row["package_id"] in wanted:
                row["exported"] = True
                row["runtime_integrated"] = True
                row["runtime_version"] = "v021_optimized"
                row["godot_import_manifest"] = project_path(SOURCE_LEDGER / "env_base99_optimized_packages_v021_import_manifest.json")
        if not dry_run:
            path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_ledgers(export_data: dict, packages: list[dict], glbs: dict[str, Path], wrappers: dict[str, Path], roots: dict[str, Path], floor_wrapper: Path, dry_run: bool) -> Path:
    source_sha = export_data["scopes"]["remaining_facilities"]["source_sha256"]
    records = []
    for package in packages:
        slug = package["slug"]
        glb = glbs[slug]
        runtime = floor_wrapper if slug == FLOOR_SLUG else roots["wall"] if slug in WALL_SLUGS else wrappers[slug]
        records.append({
            **package,
            "visual_glb": project_path(glb),
            "visual_glb_sha256": hashlib.sha256(glb.read_bytes()).hexdigest(),
            "runtime_scene": project_path(runtime),
            "runtime_root": project_path(roots["floor"] if slug == FLOOR_SLUG else roots["wall"] if slug in WALL_SLUGS else roots["remaining"]),
            "collision_policy": "visual_only_no_collision" if slug in VISUAL_ONLY or slug in WALL_SLUGS or slug == FLOOR_SLUG else "optimized_output_bounds_box",
        })
    ledger = {
        "asset_id": "ENV-BASE99-OPTIMIZED-PACKAGES-V021",
        "version": "v021",
        "source_blend": "source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v021.blend",
        "source_blend_sha256": source_sha,
        "blender_export_manifest": project_path(EXPORT_MANIFEST),
        "derived_blends": {scope: section["derived_blend"] for scope, section in export_data["scopes"].items()},
        "runtime_roots": {key: project_path(value) for key, value in roots.items()},
        "package_count": len(records),
        "packages": records,
    }
    target = SOURCE_LEDGER / "env_base99_optimized_packages_v021_import_manifest.json"
    global_ledger = json.loads(GLOBAL_LEDGER.read_text(encoding="utf-8"))
    global_ledger["base_facility_v021_optimized_packages"] = {
        "asset_id": ledger["asset_id"],
        "version": ledger["version"],
        "package_count": ledger["package_count"],
        "import_ledger": project_path(target),
        "source_blend": ledger["source_blend"],
        "runtime_roots": ledger["runtime_roots"],
    }
    if not dry_run:
        target.write_text(json.dumps(ledger, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        GLOBAL_LEDGER.write_text(json.dumps(global_ledger, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return target


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    export_data, packages = read_export()
    glbs = {package["slug"]: glb_for(package) for package in packages}
    for glb in glbs.values():
        configure_glb_import_contract(glb, args.dry_run)
    wrappers = {
        package["slug"]: write_wrapper(package, glbs[package["slug"]], args.dry_run)
        for package in packages
        if package["slug"] not in WALL_SLUGS and package["slug"] != FLOOR_SLUG
    }
    floor_wrapper = write_floor_wrapper(glbs[FLOOR_SLUG], args.dry_run)
    roots = {
        "remaining": update_remaining_root(packages, wrappers, args.dry_run),
        "wall": update_wall_root(packages, glbs, args.dry_run),
        "floor": update_floor_root(floor_wrapper, args.dry_run),
    }
    layout = update_layout(roots["remaining"], roots["wall"], roots["floor"], args.dry_run)
    roots["layout"] = layout
    write_ledgers(export_data, packages, glbs, wrappers, roots, floor_wrapper, args.dry_run)
    update_blender_catalogs(packages, args.dry_run)
    print(f"BASE_FACILITY_V021_IMPORT:packages={len(packages)}:dry_run={args.dry_run}")


if __name__ == "__main__":
    main()
