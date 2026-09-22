#!/usr/bin/env python3
"""Ensure every verify_*.tscn has one explicit suite ownership."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "scripts" / "run_verification_suite.sh"
SCENE_DIR = ROOT / "tests" / "verification"
CATEGORIES = ("smoke_scenes", "core_scenes", "visual_scenes", "manual_scenes", "retired_scenes")


def read_array(source: str, name: str) -> list[str]:
    match = re.search(rf"^{name}=\(\n(?P<body>.*?)^\)$", source, re.MULTILINE | re.DOTALL)
    if match is None:
        raise SystemExit(f"missing verification category: {name}")
    return re.findall(r"^\s+(verify_[A-Za-z0-9_]+)\s*$", match.group("body"), re.MULTILINE)


def main() -> int:
    source = RUNNER.read_text(encoding="utf-8")
    categories = {name: read_array(source, name) for name in CATEGORIES}
    categories["core_scenes"] = [name for name in categories["core_scenes"] if name not in categories["smoke_scenes"]]
    owners: dict[str, list[str]] = {}
    errors: list[str] = []
    for category, names in categories.items():
        for name in sorted({name for name in names if names.count(name) > 1}):
            errors.append(f"duplicate in {category}: {name}")
        for name in set(names):
            owners.setdefault(name, []).append(category.removesuffix("_scenes"))
    scenes = {path.stem for path in SCENE_DIR.glob("verify_*.tscn")}
    for name in sorted(scenes - owners.keys()):
        errors.append(f"unregistered: {name}")
    for name in sorted(owners.keys() - scenes):
        errors.append(f"missing scene: {name} ({','.join(owners[name])})")
    for name, assigned in sorted(owners.items()):
        if len(assigned) != 1:
            errors.append(f"multiple owners: {name} ({','.join(assigned)})")
    if errors:
        print("VERIFICATION_REGISTRY_FAILED")
        for error in errors:
            print(f"- {error}")
        return 1
    counts = {key.removesuffix("_scenes"): len(value) for key, value in categories.items()}
    print(f"VERIFICATION_REGISTRY_OK scenes={len(scenes)} categories={counts}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
