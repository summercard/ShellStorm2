"""将塔楼组件候选导入稳定路径，保持正式布局不变。"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import struct
from datetime import datetime
from pathlib import Path

DEFAULT_ROOT = Path("I:/工作项目/shellstrom2/ShellStorm2")
ASSET_ID = "ENV-OPENWORLD-TOWER03"
COMPONENT_COUNT = 217
PENDING_STATE = "awaiting_import_acceptance"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def rel(root: Path, path: Path) -> str:
    return path.relative_to(root).as_posix()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def dump_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def glb_measure(path: Path) -> dict:
    raw = path.read_bytes()
    magic, version, total_length = struct.unpack_from("<4sII", raw, 0)
    assert (magic, version, total_length) == (b"glTF", 2, len(raw)), path
    cursor = 12
    document = None
    while cursor < total_length:
        chunk_length, chunk_type = struct.unpack_from("<I4s", raw, cursor)
        cursor += 8
        chunk = raw[cursor:cursor + chunk_length]
        cursor += chunk_length
        if chunk_type == b"JSON":
            document = json.loads(chunk.decode("utf-8"))
    assert document is not None, path
    triangles = 0
    mins = []
    maxs = []
    primitive_count = 0
    uv_primitive_count = 0
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            primitive_count += 1
            assert primitive.get("mode", 4) == 4, (path, primitive.get("mode"))
            assert "TEXCOORD_0" in primitive.get("attributes", {}), path
            uv_primitive_count += 1
            if "indices" in primitive:
                triangles += document["accessors"][primitive["indices"]]["count"] // 3
            else:
                triangles += document["accessors"][primitive["attributes"]["POSITION"]]["count"] // 3
            accessor = document["accessors"][primitive["attributes"]["POSITION"]]
            mins.append(accessor["min"])
            maxs.append(accessor["max"])
    assert mins, path
    assert not document.get("images") and not document.get("textures"), path
    bbox_min = [min(values[0] for values in mins), min(values[2] for values in mins), min(values[1] for values in mins)]
    bbox_max = [max(values[0] for values in maxs), max(values[2] for values in maxs), max(values[1] for values in maxs)]
    return {
        "sha256": sha256(path),
        "triangles": triangles,
        "bbox_min": bbox_min,
        "bbox_max": bbox_max,
        "mesh_count": len(document.get("meshes", [])),
        "primitive_count": primitive_count,
        "uv_primitive_count": uv_primitive_count,
        "material_count": len(document.get("materials", [])),
    }


def tree_hashes(root: Path, directories: list[Path]) -> dict:
    result = {}
    for directory in directories:
        files = sorted(path for path in directory.rglob("*") if path.is_file())
        file_hashes = {rel(root, path): sha256(path) for path in files}
        aggregate = hashlib.sha256()
        for file_name, file_hash in file_hashes.items():
            aggregate.update(file_name.encode("utf-8"))
            aggregate.update(b"\0")
            aggregate.update(file_hash.encode("ascii"))
            aggregate.update(b"\n")
        result[rel(root, directory)] = {"tree_sha256": aggregate.hexdigest(), "files": file_hashes}
    return result


def verify_tree_hashes(root: Path, protected: dict) -> None:
    for directory_name, expected in protected.items():
        directory = root / directory_name
        actual = tree_hashes(root, [directory])[directory_name]
        assert actual == expected, directory_name


def metadata_stripped(text: str) -> str:
    kept = []
    for line in text.splitlines(keepends=True):
        if line.startswith("metadata/asset_version = ") or line.startswith("metadata/source_blend = "):
            continue
        kept.append(line)
    return "".join(kept)


def update_scene_metadata(path: Path, version: str, source_blend: str) -> tuple[str, str]:
    before = path.read_text(encoding="utf-8")
    lines = before.splitlines(keepends=True)
    version_lines = [line for line in lines if line.startswith("metadata/asset_version = ")]
    source_lines = [line for line in lines if line.startswith("metadata/source_blend = ")]
    assert len(version_lines) == 1, path
    assert len(source_lines) == 1, path
    after_lines = []
    for line in lines:
        if line.startswith("metadata/asset_version = "):
            ending = "\n" if line.endswith("\n") else ""
            after_lines.append(f'metadata/asset_version = "{version}"{ending}')
        elif line.startswith("metadata/source_blend = "):
            ending = "\n" if line.endswith("\n") else ""
            after_lines.append(f'metadata/source_blend = "{source_blend}"{ending}')
        else:
            after_lines.append(line)
    after = "".join(after_lines)
    assert metadata_stripped(before) == metadata_stripped(after), path
    path.write_text(after, encoding="utf-8", newline="")
    return hashlib.sha256(metadata_stripped(before).encode("utf-8")).hexdigest(), hashlib.sha256(metadata_stripped(after).encode("utf-8")).hexdigest()


def make_backup(root: Path, components: Path, runtime: Path, version: str) -> Path:
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    backup = root / "_scratch" / f"tower03_{version}_stable_backup_{stamp}"
    backup.mkdir(parents=True, exist_ok=False)
    (backup / ".gdignore").write_text("", encoding="utf-8")
    shutil.copytree(components, backup / "components" / "tower_03")
    shutil.copytree(runtime, backup / "runtime" / "tower_03")
    return backup


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    parser.add_argument("--from-version", default="v001")
    parser.add_argument("--to-version", default="v004")
    parser.add_argument("--stable-before-version", default="v004")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--candidate-final", type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    root = args.root
    base = root / "assets/art/environments/open_world"
    source_root = base / "source/tower_03"
    from_export = source_root / "export" / args.from_version
    to_export = source_root / "export" / args.to_version
    source_manifest_path = from_export / "export_manifest.json"
    export_manifest_path = to_export / "export_manifest.json"
    catalog_path = source_root / args.to_version / "catalog.json"
    components = base / "components/tower_03"
    runtime_dir = base / "runtime/tower_03"
    root_scene = runtime_dir / "env_tower_03_root_top3d.tscn"
    runtime_manifest_path = runtime_dir / "asset_manifest.json"
    route = base / "runtime/cross_tower_route/env_cross_tower_route_root_top3d.tscn"
    output = args.output or root / "outputs" / f"tower03_{args.to_version}" / "stable_promotion.json"
    candidate_final_path = args.candidate_final or root / "outputs" / f"tower03_{args.to_version}" / f"tower03_{args.to_version}_final.json"

    assert source_manifest_path.is_file()
    assert export_manifest_path.is_file()
    assert catalog_path.is_file()
    assert root_scene.is_file()
    assert runtime_manifest_path.is_file()
    assert components.is_dir() and runtime_dir.is_dir() and route.is_file()

    source_manifest = load_json(source_manifest_path)
    export_manifest = load_json(export_manifest_path)
    catalog = load_json(catalog_path)
    candidate_final = load_json(candidate_final_path)
    existing_runtime_manifest = load_json(runtime_manifest_path)
    assert existing_runtime_manifest["version"] == args.stable_before_version
    assert candidate_final["version"] == args.to_version
    assert candidate_final["passed"] is True
    assert candidate_final["conclusion"] == "PASS"
    assert candidate_final["records"] == COMPONENT_COUNT
    assert candidate_final["triangles_glb_actual"] == export_manifest["triangles_glb"]
    assert candidate_final["mesh_objects"] == 228
    assert candidate_final["strict_palette_uv"]["passed"] is True
    assert candidate_final["strict_palette_uv"]["counts"]["faces"] == candidate_final["strict_palette_uv"]["counts"]["ok"] == export_manifest["triangles_glb"]
    assert candidate_final["retention_errors"] == []
    assert candidate_final["signature_errors"] == []
    assert candidate_final["visual_acceptance"]["status"] == "passed_same_condition_readback"
    rail_slugs = {f"lower_rail_{index}" for index in range(4)} | {f"upper_rail_{index}" for index in range(4)}
    rail_retention = {item["slug"]: item for item in candidate_final["retention_details"] if item["slug"] in rail_slugs}
    assert set(rail_retention) == rail_slugs
    assert all(item["retention"] == 1.0 and item["before"] == item["after"] for item in rail_retention.values())
    assert candidate_final["visual_acceptance"]["rail_structure"]["all_eight_components_restored"] is True
    assert candidate_final["visual_acceptance"]["rail_structure"]["crossbars_and_uprights_readable"] is True
    assert len(candidate_final["upper_rail_details"]) == 8
    assert all(item["retention"] == 1.0 for item in candidate_final["upper_rail_details"].values())
    for detail in candidate_final["upper_rail_details"].values():
        assert detail["before"] == detail["after"] == detail["manifest"]
        assert len(detail["source_geometry"]) == 1
        source_geometry = next(iter(detail["source_geometry"].values()))
        assert source_geometry["source_signature"]
        assert source_geometry["source_triangles"] == source_geometry["source_polygons"]
        assert source_geometry["source_vertices"] > 0
    assert all(item["retention"] >= 0.82 for item in candidate_final["retention_details"] if item["category"] in {"support", "hvac", "telecom"})
    assert source_manifest["asset_id"] == ASSET_ID
    assert source_manifest["version"] == args.from_version
    assert export_manifest["asset_id"] == ASSET_ID
    assert export_manifest["version"] == args.to_version
    assert export_manifest["role"] == "optimized_candidate"
    assert export_manifest["runtime_integrated"] is False
    assert len(export_manifest["records"]) == COMPONENT_COUNT
    assert catalog["asset_id"] == ASSET_ID and catalog["version"] == args.to_version
    assert len(catalog["packages"]) == COMPONENT_COUNT
    assert sha256(root / export_manifest["source"]) == export_manifest["source_sha256"]
    assert sha256(root / export_manifest["reference_source"]) == export_manifest["reference_source_sha256"]
    assert sha256(root / export_manifest["derived"]) == export_manifest["derived_sha256"]

    source_records = {record["slug"]: record for record in source_manifest["records"]}
    export_records = {record["slug"]: record for record in export_manifest["records"]}
    catalog_packages = {package["slug"]: package for package in catalog["packages"]}
    assert len(source_records) == len(export_records) == len(catalog_packages) == COMPONENT_COUNT
    assert set(source_records) == set(export_records) == set(catalog_packages)

    stable_glbs = {slug: root / record["stable_glb"] for slug, record in export_records.items()}
    staged_glbs = {slug: root / record["glb"] for slug, record in export_records.items()}
    prefabs = {slug: root / record["stable_prefab"] for slug, record in export_records.items()}
    component_manifests = {
        slug: runtime_dir / slug / "asset_manifest.json" for slug in export_records
    }
    assert len(stable_glbs) == len(staged_glbs) == len(prefabs) == len(component_manifests) == COMPONENT_COUNT
    assert set(stable_glbs) == set(staged_glbs) == set(prefabs) == set(component_manifests) == set(export_records)
    assert all(path.is_file() for path in stable_glbs.values())
    assert all(path.is_file() for path in staged_glbs.values())
    assert all(path.is_file() for path in prefabs.values())
    assert all(path.is_file() for path in component_manifests.values())

    import_paths_before = {path: sha256(path) for path in components.rglob("*.import")}
    uid_paths_before = {path: sha256(path) for path in components.rglob("*.uid")}
    runtime_import_paths_before = {path: sha256(path) for path in runtime_dir.rglob("*.import")}
    runtime_uid_paths_before = {path: sha256(path) for path in runtime_dir.rglob("*.uid")}
    tscn_bytes_before = {path: path.read_bytes() for path in runtime_dir.rglob("*.tscn")}
    component_manifest_bytes_before = {path: path.read_bytes() for path in component_manifests.values()}
    root_manifest_before = runtime_manifest_path.read_bytes()
    catalog_before = catalog_path.read_bytes()
    export_manifest_before = export_manifest_path.read_bytes()
    route_hash_before = sha256(route)
    other_dirs = []
    for parent in (base / "components", base / "runtime"):
        other_dirs.extend(path for path in parent.iterdir() if path.is_dir() and path.name.startswith("tower_") and path.name != "tower_03")
    protected_other_towers = tree_hashes(root, sorted(other_dirs))
    protected_before = {
        "route": {rel(root, route): route_hash_before},
        "other_towers": protected_other_towers,
    }

    glb_measurements = {}
    for slug, record in sorted(export_records.items()):
        staged = root / record["glb"]
        stable = root / record["stable_glb"]
        assert staged.is_file() and stable.is_file()
        measured = glb_measure(staged)
        assert measured["sha256"] == record["glb_sha256"]
        assert measured["triangles"] == record["triangle_count_glb"] == record["triangle_count"]
        for actual, expected in zip(measured["bbox_min"] + measured["bbox_max"], record["local_bounds_blender"][0] + record["local_bounds_blender"][1]):
            assert abs(actual - expected) <= 2e-6, (slug, actual, expected)
        glb_measurements[slug] = measured
        assert record["stable_glb"].split("/")[-2] == slug
        assert record["stable_glb"] == record["runtime_glb"]
        assert record["stable_prefab"] == record["runtime_prefab"]
        assert record["formal_layout_rewritten"] is False
        assert record["export_memory_invariance"]["triangles_before_export"] == record["export_memory_invariance"]["triangles_after_export_memory"] == record["triangle_count"]
        assert record["export_memory_invariance"]["geometry_signatures_unchanged"] is True
        source_record = source_records[slug]
        for actual, expected in zip(record["bounds_blender"][0] + record["bounds_blender"][1], source_record["bounds_blender"][0] + source_record["bounds_blender"][1]):
            assert abs(float(actual) - float(expected)) <= 2e-6, (slug, "source_bbox", actual, expected)
        for key in ("front_direction", "anchor_blender", "position_godot", "local_origin"):
            if key in source_records[slug] and key in record:
                left, right = source_records[slug][key], record[key]
                if isinstance(left, list):
                    assert max(abs(float(a) - float(b)) for a, b in zip(left, right)) <= 1e-6, (slug, key)
                else:
                    assert left == right, (slug, key)

    backup = make_backup(root, components, runtime_dir, args.to_version)
    scene_layout_hashes = {}
    promoted = []
    try:
        for slug, record in sorted(export_records.items()):
            staged = root / record["glb"]
            stable = root / record["stable_glb"]
            shutil.copy2(staged, stable)
            assert sha256(stable) == record["glb_sha256"]
            promoted.append({
                "asset_id": record["asset_id"],
                "slug": slug,
                "stable_glb": record["stable_glb"],
                "prefab": record["stable_prefab"],
                "sha256": record["glb_sha256"],
                "triangles": record["triangle_count"],
                "bbox_min": record["local_bounds_blender"][0],
                "bbox_max": record["local_bounds_blender"][1],
            })

        source_blend = export_manifest["derived"]
        for slug, record in sorted(export_records.items()):
            prefab = root / record["stable_prefab"]
            layout_before, layout_after = update_scene_metadata(prefab, args.to_version, source_blend)
            scene_layout_hashes[rel(root, prefab)] = {
                "layout_sha256_before": layout_before,
                "layout_sha256_after": layout_after,
                "layout_unchanged": layout_before == layout_after,
                "full_sha256_before": hashlib.sha256(tscn_bytes_before[prefab]).hexdigest(),
                "full_sha256_after": sha256(prefab),
            }
            assert scene_layout_hashes[rel(root, prefab)]["layout_unchanged"]

        root_layout_before, root_layout_after = update_scene_metadata(root_scene, args.to_version, source_blend)
        root_layout = {
            "layout_sha256_before": root_layout_before,
            "layout_sha256_after": root_layout_after,
            "layout_unchanged": root_layout_before == root_layout_after,
            "full_sha256_before": hashlib.sha256(tscn_bytes_before[root_scene]).hexdigest(),
            "full_sha256_after": sha256(root_scene),
        }
        assert root_layout["layout_unchanged"]

        runtime_manifest = load_json(runtime_manifest_path)
        runtime_manifest["schema"] = f"shellstorm2.openworld.tower03.runtime.{args.to_version}"
        runtime_manifest["version"] = args.to_version
        runtime_manifest["source"] = export_manifest["source"]
        runtime_manifest["source_sha256"] = export_manifest["source_sha256"]
        runtime_manifest["reference_source"] = export_manifest["reference_source"]
        runtime_manifest["reference_source_sha256"] = export_manifest["reference_source_sha256"]
        runtime_manifest["derived"] = export_manifest["derived"]
        runtime_manifest["derived_sha256"] = export_manifest["derived_sha256"]
        runtime_manifest["palette"] = export_manifest["palette"]
        runtime_manifest["palette_sha256"] = export_manifest["palette_sha256"]
        runtime_manifest["prefab"] = export_manifest["runtime_prefab"]
        runtime_manifest["component_count"] = COMPONENT_COUNT
        runtime_manifest["runtime_integrated"] = False
        runtime_manifest["godot_reimport_pending"] = True
        runtime_manifest["state"] = PENDING_STATE
        runtime_manifest["role"] = "optimized_candidate"
        runtime_manifest["layout_owner"] = "Godot TSCN; promotion metadata-only"
        runtime_manifest["runtime_integration"] = {
            "stable_component_paths_preserved": True,
            "stable_packedscene_paths_preserved": True,
            "formal_layout_rewritten": False,
            "collision_or_gameplay_changed": False,
            "cross_tower_route_unchanged": True,
            "godot_reimport_pending": True,
            "state": PENDING_STATE,
        }
        runtime_records = []
        for slug, record in sorted(export_records.items()):
            item = dict(record)
            item["glb"] = record["stable_glb"]
            item["runtime_glb"] = record["stable_glb"]
            item["prefab"] = record["stable_prefab"]
            item["runtime_prefab"] = record["stable_prefab"]
            item["version"] = args.to_version
            item["source_blend"] = source_blend
            item["runtime_integrated"] = False
            item["godot_reimport_pending"] = True
            item["state"] = PENDING_STATE
            runtime_records.append(item)
        runtime_manifest["records"] = runtime_records
        runtime_manifest["backup_before_promotion"] = rel(root, backup)
        dump_json(runtime_manifest_path, runtime_manifest)

        catalog["schema"] = f"shellstorm2.openworld.tower03.catalog.{args.to_version}"
        catalog["version"] = args.to_version
        catalog["source_blend"] = export_manifest["source"]
        catalog["reference_source"] = export_manifest["reference_source"]
        catalog["reference_source_sha256"] = export_manifest["reference_source_sha256"]
        catalog["derived"] = export_manifest["derived"]
        catalog["derived_sha256"] = export_manifest["derived_sha256"]
        catalog["source_sha256"] = export_manifest["source_sha256"]
        catalog["palette_sha256"] = export_manifest["palette_sha256"]
        catalog["staged_component_root"] = export_manifest["staged_component_root"]
        catalog["runtime_prefab"] = export_manifest["runtime_prefab"]
        catalog["runtime_integrated"] = False
        catalog["godot_reimport_pending"] = True
        catalog["state"] = PENDING_STATE
        catalog["role"] = "optimized_candidate"
        catalog["ledger_status"] = f"待Godot重导入验收；{args.to_version}稳定路径提升完成"
        for slug, record in sorted(export_records.items()):
            package = catalog_packages[slug]
            package.update({
                "version": args.to_version,
                "source_blend": export_manifest["source"],
                "reference_source": export_manifest["reference_source"],
                "derived": export_manifest["derived"],
                "derived_sha256": export_manifest["derived_sha256"],
                "staged_glb": record["glb"],
                "triangle_count": record["triangle_count"],
                "triangle_count_blender": record["triangle_count_blender"],
                "triangle_count_glb": record["triangle_count_glb"],
                "bounds_min": record["bounds_blender"][0],
                "bounds_max": record["bounds_blender"][1],
                "dimensions": record["dimensions"],
                "position_godot": record["position_godot"],
                "prefab": record["stable_prefab"],
                "runtime_prefab": record["stable_prefab"],
                "stable_prefab": record["stable_prefab"],
                "runtime_glb": record["stable_glb"],
                "stable_glb": record["stable_glb"],
                "runtime_asset_id": record["asset_id"],
                "asset_id": record["asset_id"],
                "glb_sha256": record["glb_sha256"],
                "exported": True,
                "runtime_integrated": False,
                "godot_reimport_pending": True,
                "state": PENDING_STATE,
                "collision_status": record.get("collision_status", "none_visual_only"),
            })
        dump_json(catalog_path, catalog)

        for slug, record in sorted(export_records.items()):
            manifest_path = component_manifests[slug]
            component = load_json(manifest_path)
            component.update({
                "version": args.to_version,
                "source_blend": export_manifest["source"],
                "reference_source": export_manifest["reference_source"],
                "reference_source_sha256": export_manifest["reference_source_sha256"],
                "derived": export_manifest["derived"],
                "derived_sha256": export_manifest["derived_sha256"],
                "source_sha256": export_manifest["source_sha256"],
                "bounds_min": record["bounds_blender"][0],
                "bounds_max": record["bounds_blender"][1],
                "bounds_blender": record["bounds_blender"],
                "local_bounds_blender": record["local_bounds_blender"],
                "dimensions": record["dimensions"],
                "triangle_count": record["triangle_count"],
                "triangle_count_blender": record["triangle_count_blender"],
                "triangle_count_glb": record["triangle_count_glb"],
                "asset_id": record["asset_id"],
                "glb": record["stable_glb"],
                "stable_glb": record["stable_glb"],
                "runtime_glb": record["stable_glb"],
                "glb_sha256": record["glb_sha256"],
                "prefab": record["stable_prefab"],
                "stable_prefab": record["stable_prefab"],
                "runtime_prefab": record["stable_prefab"],
                "runtime_integrated": False,
                "godot_reimport_pending": True,
                "state": PENDING_STATE,
                "collision": record.get("collision_status", "none_visual_only"),
            })
            dump_json(manifest_path, component)

        export_manifest["runtime_integrated"] = False
        export_manifest["stable_paths_touched"] = True
        export_manifest["godot_modified"] = True
        export_manifest["godot_reimport_pending"] = True
        export_manifest["state"] = PENDING_STATE
        export_manifest["promotion_backup"] = rel(root, backup)
        for record in export_manifest["records"]:
            record["runtime_integrated"] = False
            record["godot_reimport_pending"] = True
            record["state"] = PENDING_STATE
        dump_json(export_manifest_path, export_manifest)

        assert sha256(route) == route_hash_before
        verify_tree_hashes(root, protected_other_towers)
        assert {path: sha256(path) for path in components.rglob("*.import")} == import_paths_before
        assert {path: sha256(path) for path in components.rglob("*.uid")} == uid_paths_before
        assert {path: sha256(path) for path in runtime_dir.rglob("*.import")} == runtime_import_paths_before
        assert {path: sha256(path) for path in runtime_dir.rglob("*.uid")} == runtime_uid_paths_before
        assert root_scene.is_file()
        assert len(promoted) == COMPONENT_COUNT

        report = {
            "passed": True,
            "asset_id": ASSET_ID,
            "promoted_version": args.to_version,
            "components_promoted": COMPONENT_COUNT,
            "triangles_blend": export_manifest["triangles_blend"],
            "triangles_glb_measured": sum(item["triangles"] for item in glb_measurements.values()),
            "source": export_manifest["source"],
            "source_sha256": export_manifest["source_sha256"],
            "reference_source": export_manifest["reference_source"],
            "reference_source_sha256": export_manifest["reference_source_sha256"],
            "derived": export_manifest["derived"],
            "derived_sha256": export_manifest["derived_sha256"],
            "palette": export_manifest["palette"],
            "palette_sha256": export_manifest["palette_sha256"],
            "stable_paths_preserved": True,
            "stable_glb_import_uid_unchanged": True,
            "formal_layout_rewritten": False,
            "layout_invariance": {
                "root": root_layout,
                "components": scene_layout_hashes,
                "all_passed": root_layout["layout_unchanged"] and all(item["layout_unchanged"] for item in scene_layout_hashes.values()),
                "metadata_only": True,
            },
            "runtime_integrated": False,
            "godot_reimport_pending": True,
            "state": PENDING_STATE,
            "candidate_final_manifest": rel(root, candidate_final_path),
            "candidate_final_manifest_present": True,
            "candidate_final_passed": candidate_final["passed"],
            "candidate_final_visual_acceptance": candidate_final["visual_acceptance"]["status"],
            "candidate_final_mesh_objects": candidate_final["mesh_objects"],
            "candidate_final_retention_evidence": {
                "rail_components": sorted(rail_slugs),
                "rail_retention_all_1_0": True,
                "floor_retention_all_1_0": all(item["retention"] == 1.0 for item in candidate_final["retention_details"] if item["category"] == "floor"),
                "non_floor_min_retention": min(item["retention"] for item in candidate_final["retention_details"] if item["category"] != "floor"),
            },
            "backup": rel(root, backup),
            "route_hash_protection": {"path": rel(root, route), "before": route_hash_before, "after": sha256(route), "unchanged": sha256(route) == route_hash_before},
            "other_towers_hash_protection": protected_other_towers,
            "glb_audit": glb_measurements,
            "mapping": promoted,
            "runtime_manifest": rel(root, runtime_manifest_path),
            "catalog": rel(root, catalog_path),
            "export_manifest": rel(root, export_manifest_path),
        }
        dump_json(output, report)
        print(json.dumps(report, ensure_ascii=False, indent=2))
        print(f"TOWER03_{args.to_version.upper()}_STABLE_PROMOTION_PENDING_IMPORT_OK")
    except Exception:
        for path, data in tscn_bytes_before.items():
            path.write_bytes(data)
        for path, data in component_manifest_bytes_before.items():
            path.write_bytes(data)
        runtime_manifest_path.write_bytes(root_manifest_before)
        catalog_path.write_bytes(catalog_before)
        export_manifest_path.write_bytes(export_manifest_before)
        for path in stable_glbs.values():
            backup_path = backup / "components" / "tower_03" / path.relative_to(components)
            path.write_bytes(backup_path.read_bytes())
        raise


if __name__ == "__main__":
    main()
