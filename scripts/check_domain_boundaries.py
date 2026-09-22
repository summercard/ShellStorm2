#!/usr/bin/env python3
"""Reject known cross-domain reads of private runtime state in production scripts."""

from pathlib import Path
import json
import re


FORBIDDEN = {
    r"\bBaseManager\.data\b": "use a BaseManager command or read-only snapshot",
    r"\bBaseManager\.call\(\s*[\"']_ensure_data[\"']": "do not call BaseManager private initialization",
    r"\bVfxPool3D\._REGISTRY\b": "use VfxPool3D.has_effect/create_unpooled/acquire",
}


def check(root: Path) -> dict:
    violations: list[dict] = []
    for path in sorted((root / "src").rglob("*.gd")):
        relative = path.relative_to(root).as_posix()
        if relative in {"src/base/BaseManager.gd", "src/vfx/VfxPool3D.gd"}:
            continue
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            for pattern, replacement in FORBIDDEN.items():
                if re.search(pattern, line):
                    violations.append({
                        "file": relative,
                        "line": line_number,
                        "replacement": replacement,
                    })
    return {"checked_root": "src", "violations": violations}


if __name__ == "__main__":
    result = check(Path(__file__).resolve().parents[1])
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(1 if result["violations"] else 0)
