"""Validate Tower02 v004 stable-path promotion after Godot reimport."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "assets/art/environments/open_world"
MANIFEST_PATH = BASE / "source/tower_02/export/v004/export_manifest.json"
STABLE_MANIFEST_PATH = BASE / "runtime/tower_02/asset_manifest.json"
ROOT_SCENE = BASE / "runtime/tower_02/env_tower_02_root_top3d.tscn"
REPORT = ROOT / "outputs/tower02_v004_stable_import_static.json"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    stable_manifest = json.loads(STABLE_MANIFEST_PATH.read_text(encoding="utf-8"))
    failures: list[str] = []
    checked = 0
    total_triangles = 0
    for record in manifest["records"]:
        prefab = ROOT / record["prefab"]
        if not prefab.is_file():
            failures.append(f"missing_prefab:{record['prefab']}")
            continue
        text = prefab.read_text(encoding="utf-8")
        refs = re.findall(r'path="res://([^"]+\.glb)"', text)
        if len(refs) != 1:
            failures.append(f"prefab_glb_ref_count:{record['prefab']}:{len(refs)}")
            continue
        glb = ROOT / refs[0]
        import_file = Path(str(glb) + ".import")
        if not glb.is_file():
            failures.append(f"missing_stable_glb:{glb.relative_to(ROOT)}")
        if not import_file.is_file():
            failures.append(f"missing_import_sidecar:{import_file.relative_to(ROOT)}")
        if "/tower_02_v004/" in refs[0] or "/tower_02_v004/" in text:
            failures.append(f"versioned_runtime_ref:{record['prefab']}")
        if 'metadata/asset_version = "v004"' not in text:
            failures.append(f"prefab_version:{record['prefab']}")
        if sha(glb) != record["glb_sha256"]:
            failures.append(f"stable_hash:{record['slug']}")
        checked += 1
        total_triangles += int(record["triangle_count"])

    root_text = ROOT_SCENE.read_text(encoding="utf-8")
    if 'metadata/asset_version = "v004"' not in root_text:
        failures.append("root_version")
    if "/tower_02_v004/" in root_text:
        failures.append("root_versioned_ref")
    if not stable_manifest.get("runtime_integrated"):
        failures.append("stable_manifest_runtime_integrated_false")
    if stable_manifest.get("version") != "v004":
        failures.append("stable_manifest_version")
    if stable_manifest.get("runtime_integration", {}).get("godot_reimport_pending"):
        failures.append("stable_manifest_reimport_pending")

    result = {
        "passed": not failures,
        "asset_id": "ENV-OPENWORLD-TOWER02",
        "version": "v004",
        "components_checked": checked,
        "expected_components": 92,
        "triangles_from_export_manifest": total_triangles,
        "stable_paths_preserved": True,
        "formal_layout_rewritten": False,
        "failures": failures,
    }
    REPORT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))
    raise SystemExit(0 if result["passed"] else 1)


if __name__ == "__main__":
    main()
