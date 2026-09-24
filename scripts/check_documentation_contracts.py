#!/usr/bin/env python3
"""Check current documentation navigation and feature references, without writes.

This checks structure, not design approval, gameplay correctness or test success.
Run from any directory: python3 scripts/check_documentation_contracts.py
"""
from pathlib import Path
import json
import re
import subprocess
from urllib.parse import unquote


def check(root: Path) -> dict:
    issues = []
    required = [
        "docs/README.md", "docs/DOCUMENTATION_STANDARD.md",
        "docs/v0.1/README.md", "docs/v0.1/MODULE_INDEX.md",
        "docs/v0.1/design/README.md", "docs/v0.1/development/README.md",
        "docs/v0.1/development/CHANGELOG.md",
    ]
    for relative in required:
        if not (root / relative).is_file():
            issues.append(f"Missing required document: {relative}")
    project = (root / "project.godot").read_text(encoding="utf-8")
    version_match = re.search(r'^config/version="([^"]+)"', project, re.M)
    version = version_match[1] if version_match else ""
    for relative in ["docs/README.md", "docs/v0.1/README.md", "docs/v0.1/MODULE_INDEX.md"]:
        path = root / relative
        if path.is_file() and version not in path.read_text(encoding="utf-8"):
            issues.append(f"Missing engine version {version}: {relative}")
    paths = sorted(
        set((root / "docs").glob("*.md"))
        | set((root / "docs/v0.1").rglob("*.md"))
        | set((root / "docs/v0.2").rglob("*.md"))
    )
    links = 0
    for path in paths:
        in_fence = False
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if line.lstrip().startswith("```"):
                in_fence = not in_fence
            if in_fence:
                continue
            for target in re.findall(r'\]\(([^)]+)\)', line):
                target = unquote(target.strip("<> ").split("#", 1)[0])
                if not target or re.match(r'\w+://', target):
                    continue
                links += 1
                if not (path.parent / target).exists():
                    issues.append(f"Broken link {path.relative_to(root)}:{line_number}: {target}")
    index = root / "docs/v0.1/MODULE_INDEX.md"
    features = []
    test_references = set()
    if index.is_file():
        for line_number, line in enumerate(index.read_text(encoding="utf-8").splitlines(), 1):
            match = re.match(r'^\| ([A-Z]+-[A-Z]+) \|', line)
            if not match:
                continue
            feature_id = match[1]
            if feature_id in features:
                issues.append(f"Duplicate feature ID: {feature_id}")
            features.append(feature_id)
            cells = [c.strip() for c in line.strip("|").split("|")]
            if len(cells) != 6 or any(not c for c in cells):
                issues.append(f"Incomplete feature row at line {line_number}: {feature_id}")
            for name in re.findall(r'`(verify_\w+)`', line):
                test_references.add(name)
                gd = root / f"tests/verification/{name}.gd"
                scene = root / f"tests/verification/{name}.tscn"
                if not gd.is_file():
                    issues.append(f"Missing test script: {name}")
                elif not scene.is_file() and "仅脚本" not in line:
                    issues.append(f"Test scene absent; explicitly mark 仅脚本 in index: {name}")
        if not features:
            issues.append("No feature rows found")
    registry_check = subprocess.run(
        ["python3", str(root / "scripts/check_verification_registry.py")],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    if registry_check.returncode != 0:
        detail = (registry_check.stdout + registry_check.stderr).strip()
        issues.append(f"Verification registry invalid: {detail}")
    boundary_check = subprocess.run(
        ["python3", str(root / "scripts/check_domain_boundaries.py")],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    if boundary_check.returncode != 0:
        detail = (boundary_check.stdout + boundary_check.stderr).strip()
        issues.append(f"Domain boundary invalid: {detail}")
    traceability_check = subprocess.run(
        ["python3", str(root / "scripts/check_feature_traceability.py")],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    if traceability_check.returncode != 0:
        detail = (traceability_check.stdout + traceability_check.stderr).strip()
        issues.append(f"Feature traceability invalid: {detail}")
    media_check = subprocess.run(
        ["python3", str(root / "scripts/check_media_asset_domains.py")],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    if media_check.returncode != 0:
        detail = (media_check.stdout + media_check.stderr).strip()
        issues.append(f"Media asset domains invalid: {detail}")
    return {
        "engine_version": version, "documents": len(paths), "local_links": links,
        "features": len(features), "test_references": len(test_references),
        "issues": issues,
        "limits": "Does not validate design semantics, Markdown anchors, runtime behavior, or test results. Not installed as a CI/hook gate.",
    }


if __name__ == "__main__":
    result = check(Path(__file__).resolve().parents[1])
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(1 if result["issues"] else 0)
