#!/usr/bin/env python3
"""Validate FeatureID -> design -> owner -> development -> verification traceability."""

from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.parse import unquote


FEATURE_PATTERN = re.compile(r"^[A-Z0-9]+(?:-[A-Z0-9]+)+$")
ALLOWED_STATUS = {"complete", "partial", "development", "contract_only", "source_only", "design_only"}


def _module_rows(index_path: Path, root: Path) -> tuple[dict[str, set[str]], list[str]]:
    rows: dict[str, set[str]] = {}
    issues: list[str] = []
    for line_number, line in enumerate(index_path.read_text(encoding="utf-8").splitlines(), 1):
        match = re.match(r"^\| ([A-Z0-9]+(?:-[A-Z0-9]+)+) \|", line)
        if match is None:
            continue
        feature_id = match.group(1)
        cells = [cell.strip() for cell in line.strip("|").split("|")]
        if len(cells) != 6:
            issues.append(f"MODULE_INDEX row {line_number} has {len(cells)} cells: {feature_id}")
            continue
        design_paths: set[str] = set()
        for target in re.findall(r"\]\(([^)]+)\)", cells[2]):
            target = unquote(target.split("#", 1)[0].strip("<> "))
            if not target or re.match(r"[a-z]+://", target):
                continue
            resolved = (index_path.parent / target).resolve()
            try:
                # Windows 上 relative_to() 给的是反斜杠，而 feature_registry.json 里一律写正斜杠；
                # 不归一会让下面 index_design - set(design_docs) 恒不相等 ⇒ 37 项恒红、约束失效。
                design_paths.add(str(resolved.relative_to(root)).replace("\\", "/"))
            except ValueError:
                issues.append(f"Design path escapes repository at line {line_number}: {target}")
        rows[feature_id] = design_paths
    return rows, issues


def check(root: Path) -> dict:
    issues: list[str] = []
    registry_path = root / "docs/v0.1/feature_registry.json"
    index_path = root / "docs/v0.1/MODULE_INDEX.md"
    if not registry_path.is_file():
        return {"features": 0, "issues": ["Missing docs/v0.1/feature_registry.json"]}
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
    module_rows, module_issues = _module_rows(index_path, root)
    issues.extend(module_issues)
    entries = registry.get("features", [])
    by_id: dict[str, dict] = {}
    runner = (root / "scripts/run_verification_suite.sh").read_text(encoding="utf-8")
    registered_scenes = set(re.findall(r"^\s+(verify_[A-Za-z0-9_]+)\s*$", runner, re.MULTILINE))
    scene_links = 0
    command_links = 0

    for entry in entries:
        feature_id = str(entry.get("feature_id", ""))
        if not FEATURE_PATTERN.fullmatch(feature_id):
            issues.append(f"Invalid feature_id: {feature_id!r}")
            continue
        if feature_id in by_id:
            issues.append(f"Duplicate feature registry entry: {feature_id}")
        by_id[feature_id] = entry
        owner = str(entry.get("owner", "")).strip()
        if not owner or re.search(r"待分配|待定|TODO", owner, re.IGNORECASE):
            issues.append(f"{feature_id}: owner is unresolved")
        if entry.get("status") not in ALLOWED_STATUS:
            issues.append(f"{feature_id}: invalid status {entry.get('status')!r}")

        design_docs = entry.get("design_docs", [])
        development_records = entry.get("development_records", [])
        verification = entry.get("verification", [])
        if not design_docs:
            issues.append(f"{feature_id}: no design_docs")
        if not development_records:
            issues.append(f"{feature_id}: no development_records")
        if not verification:
            issues.append(f"{feature_id}: no verification")
        for relative in [*design_docs, *development_records]:
            if not isinstance(relative, str) or not (root / relative).is_file():
                issues.append(f"{feature_id}: missing trace document {relative!r}")

        index_design = module_rows.get(feature_id, set())
        missing_from_registry = sorted(index_design - set(design_docs))
        if missing_from_registry:
            issues.append(f"{feature_id}: MODULE_INDEX design links absent from registry: {missing_from_registry}")

        for item in verification:
            kind = item.get("kind")
            if kind == "scene":
                scene_id = str(item.get("id", ""))
                scene_links += 1
                if scene_id not in registered_scenes:
                    issues.append(f"{feature_id}: verification scene is not registered: {scene_id}")
                for suffix in (".gd", ".tscn"):
                    if not (root / f"tests/verification/{scene_id}{suffix}").is_file():
                        issues.append(f"{feature_id}: missing verification file {scene_id}{suffix}")
            elif kind == "command":
                command_links += 1
                relative = str(item.get("path", ""))
                if not relative or not (root / relative).is_file():
                    issues.append(f"{feature_id}: missing verification command {relative!r}")
                if not isinstance(item.get("args", []), list):
                    issues.append(f"{feature_id}: command args must be a list")
            else:
                issues.append(f"{feature_id}: unsupported verification kind {kind!r}")

    missing = sorted(set(module_rows) - set(by_id))
    extra = sorted(set(by_id) - set(module_rows))
    if missing:
        issues.append(f"Features missing from registry: {missing}")
    if extra:
        issues.append(f"Registry features absent from MODULE_INDEX: {extra}")
    if len(module_rows) != 37:
        issues.append(f"Expected 37 MODULE_INDEX features, got {len(module_rows)}")

    return {
        "module_index_features": len(module_rows),
        "registry_features": len(by_id),
        "scene_links": scene_links,
        "command_links": command_links,
        "issues": issues,
    }


if __name__ == "__main__":
    result = check(Path(__file__).resolve().parents[1])
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if result["issues"]:
        print(f"FEATURE_TRACEABILITY_FAILED issues={len(result['issues'])}")
        raise SystemExit(1)
    print("FEATURE_TRACEABILITY_OK features=37")
