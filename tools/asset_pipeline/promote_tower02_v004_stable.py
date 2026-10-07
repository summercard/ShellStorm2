"""Promote the accepted Tower 02 v004 optimized visuals to stable Godot paths.

This is a visual-asset replacement only. It preserves the stable PackedScene
paths and all authored Tower02 layout transforms. The v003 source is never
modified; a rollback backup is created before any stable asset is replaced.
"""
from __future__ import annotations

import hashlib
import json
import re
import shutil
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "assets/art/environments/open_world"
SRC_V003 = BASE / "source/tower_02/export/v003/env_tower_02-v003-runtime.blend"
OPT_BLEND = BASE / "source/tower_02/export/v004/tower02_game_output_optimized_v004.blend"
V004_MANIFEST = BASE / "source/tower_02/export/v004/export_manifest.json"
V004_CATALOG = BASE / "source/tower_02/v004/catalog.json"
STABLE_COMPONENTS = BASE / "components/tower_02"
STABLE_RUNTIME = BASE / "runtime/tower_02"
STABLE_ROOT = STABLE_RUNTIME / "env_tower_02_root_top3d.tscn"
STABLE_MANIFEST = STABLE_RUNTIME / "asset_manifest.json"
GATE = ROOT / "outputs/tower02_optimization_v004_gate.json"


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def stable_glb_from_prefab(prefab: Path) -> Path:
    text = prefab.read_text(encoding="utf-8")
    match = re.search(r'path="res://([^\"]+\.glb)"', text)
    if not match:
        raise AssertionError(f"PackedScene has no visual GLB: {prefab}")
    path = ROOT / match.group(1)
    if not path.is_file() or not str(path).startswith(str(STABLE_COMPONENTS)):
        raise AssertionError(f"PackedScene points outside stable Tower02 components: {path}")
    return path


def replace_metadata(text: str, key: str, value: str) -> str:
    pattern = rf"(metadata/{re.escape(key)} = )\"[^\"]*\""
    updated, count = re.subn(pattern, rf'\1"{value}"', text, count=1)
    if count != 1:
        raise AssertionError(f"Missing metadata/{key}")
    return updated


def main() -> None:
    gate = json.loads(GATE.read_text(encoding="utf-8"))
    assert gate["passed"] is True
    assert gate["source_unchanged"] is True
    assert gate["triangles_after"] < gate["budget"]["target_max_triangles"]
    assert sha(SRC_V003) == gate["source_sha256"]
    assert sha(OPT_BLEND) == gate["optimized_sha256"]

    manifest = json.loads(V004_MANIFEST.read_text(encoding="utf-8"))
    assert manifest["asset_id"] == "ENV-OPENWORLD-TOWER02"
    assert manifest["version"] == "v004"
    assert len(manifest["records"]) == 92
    for record in manifest["records"]:
        staged = ROOT / record["glb"]
        assert staged.is_file(), staged
        assert sha(staged) == record["glb_sha256"], staged
        prefab = ROOT / record["prefab"]
        assert prefab.is_file(), prefab
        stable_glb_from_prefab(prefab)

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = ROOT / "_scratch" / f"tower02_v003_stable_backup_before_v004_{stamp}"
    backup_components = backup / "components"
    backup_runtime = backup / "runtime"
    backup_components.mkdir(parents=True, exist_ok=False)
    backup_runtime.mkdir(parents=True, exist_ok=False)

    # Snapshot all stable files that will be changed. No stable layout file is rewritten.
    stable_files: list[Path] = []
    stable_files.extend(sorted(STABLE_COMPONENTS.rglob("*.glb")))
    stable_files.extend(sorted(STABLE_RUNTIME.rglob("*.tscn")))
    stable_files.append(STABLE_MANIFEST)
    for path in stable_files:
        relative = path.relative_to(BASE)
        target = backup / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)

    promoted: list[dict[str, object]] = []
    for record in manifest["records"]:
        staged = ROOT / record["glb"]
        prefab = ROOT / record["prefab"]
        stable = stable_glb_from_prefab(prefab)
        before = sha(stable)
        shutil.copy2(staged, stable)
        after = sha(stable)
        assert after == record["glb_sha256"]

        text = prefab.read_text(encoding="utf-8")
        text = replace_metadata(text, "asset_version", "v004")
        text = replace_metadata(
            text,
            "source_blend",
            "assets/art/environments/open_world/source/tower_02/export/v004/tower02_game_output_optimized_v004.blend",
        )
        prefab.write_text(text, encoding="utf-8")
        promoted.append({
            "asset_id": record["asset_id"],
            "slug": record["slug"],
            "staged_glb": record["glb"],
            "stable_glb": stable.relative_to(ROOT).as_posix(),
            "prefab": record["prefab"],
            "triangles": record["triangle_count"],
            "before_sha256": before,
            "after_sha256": after,
        })

    root_text = STABLE_ROOT.read_text(encoding="utf-8")
    root_text = replace_metadata(root_text, "asset_version", "v004")
    root_text = replace_metadata(
        root_text,
        "source_blend",
        "assets/art/environments/open_world/source/tower_02/export/v004/tower02_game_output_optimized_v004.blend",
    )
    STABLE_ROOT.write_text(root_text, encoding="utf-8")

    stable_manifest = json.loads(STABLE_MANIFEST.read_text(encoding="utf-8"))
    stable_manifest.update({
        "version": "v004",
        "source": "assets/art/environments/open_world/source/tower_02/export/v004/tower02_game_output_optimized_v004.blend",
        "source_sha256": sha(OPT_BLEND),
        "source_original": "assets/art/environments/open_world/source/tower_02/export/v003/env_tower_02-v003-runtime.blend",
        "source_original_sha256": sha(SRC_V003),
        "prefab": "assets/art/environments/open_world/runtime/tower_02/env_tower_02_root_top3d.tscn",
        "component_count": 92,
        "optimization": {
            "method": "per-component COLLAPSE decimate",
            "ratio": 0.22,
            "triangles_before": 406088,
            "triangles_after_blend": 89264,
            "triangles_after_export": 80952,
            "target_max_triangles": 100000,
            "reduction_formula": "R=(T_before-T_after)/T_before",
            "reduction_ratio_blend": (406088 - 89264) / 406088,
            "reduction_ratio_export": (406088 - 80952) / 406088,
            "modular_boundaries_preserved": True,
        },
        "runtime_integrated": True,
        "runtime_integration": {
            "stable_component_paths_preserved": True,
            "stable_packedscene_paths_preserved": True,
            "formal_layout_rewritten": False,
            "collision_or_gameplay_changed": False,
            "godot_reimport_pending": True,
        },
        "backup_before_promotion": str(backup.relative_to(ROOT)).replace("\\", "/"),
        "promoted_components": promoted,
    })
    write_json(STABLE_MANIFEST, stable_manifest)

    catalog = json.loads(V004_CATALOG.read_text(encoding="utf-8"))
    catalog.update({
        "runtime_integrated": True,
        "ledger_status": "已导入；优化完成；v004已替换稳定运行路径",
        "runtime_prefab": "assets/art/environments/open_world/runtime/tower_02/env_tower_02_root_top3d.tscn",
        "runtime_glb_root": "",
    })
    for package in catalog.get("packages", []):
        package["runtime_glb"] = next(x["stable_glb"] for x in promoted if x["slug"] == package["slug"])
        package["runtime_prefab"] = next(x["prefab"] for x in promoted if x["slug"] == package["slug"])
        package["runtime_asset_id"] = package["runtime_asset_id"].replace("-V004", "")
        package["runtime_integrated"] = True
    write_json(V004_CATALOG, catalog)

    manifest["runtime_integrated"] = True
    manifest["runtime_integration"] = {
        "stable_component_paths_promoted": True,
        "stable_packedscene_paths_preserved": True,
        "formal_layout_rewritten": False,
        "backup": str(backup.relative_to(ROOT)).replace("\\", "/"),
        "godot_reimport_pending": True,
    }
    for record in manifest["records"]:
        match = next(x for x in promoted if x["slug"] == record["slug"])
        record["stable_glb"] = match["stable_glb"]
        record["runtime_glb"] = match["stable_glb"]
        record["runtime_prefab"] = match["prefab"]
    write_json(V004_MANIFEST, manifest)

    audit = {
        "passed": True,
        "asset_id": "ENV-OPENWORLD-TOWER02",
        "promoted_version": "v004",
        "components_promoted": len(promoted),
        "triangles_before": 406088,
        "triangles_after_blend": 89264,
        "triangles_after_export": 80952,
        "stable_paths_preserved": True,
        "formal_layout_rewritten": False,
        "source_v003_unchanged": sha(SRC_V003) == gate["source_sha256"],
        "optimized_blend": str(OPT_BLEND.relative_to(ROOT)).replace("\\", "/"),
        "optimized_blend_sha256": sha(OPT_BLEND),
        "backup": str(backup.relative_to(ROOT)).replace("\\", "/"),
        "stable_manifest": str(STABLE_MANIFEST.relative_to(ROOT)).replace("\\", "/"),
        "godot_reimport_pending": True,
    }
    report = ROOT / "outputs/tower02_v004_stable_promotion.json"
    write_json(report, audit)
    print(json.dumps(audit, ensure_ascii=False))


if __name__ == "__main__":
    main()
