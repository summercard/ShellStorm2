#!/usr/bin/env python3
"""Check this one skill's repository mirrors, optionally including local installations."""
import argparse
import hashlib
import json
from pathlib import Path

NAME = "11-expedition03-scene-workshop-layout"


def digest_tree(root):
    return {
        path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in root.rglob("*")
        if path.is_file() and "__pycache__" not in path.parts
    }


def check(root, installed=False):
    copies = [root / ".codex/skills" / NAME, root / ".workbuddy/skills" / NAME, root / "skills_drafts" / NAME]
    if installed:
        copies = [Path.home() / ".workbuddy/skills" / NAME, *copies, Path.home() / ".codex/skills" / NAME]
    errors = []
    expected = digest_tree(copies[0])
    if "SKILL.md" not in expected:
        errors.append(f"missing canonical SKILL.md: {copies[0]}")
    for copy in copies:
        current = digest_tree(copy)
        if current != expected:
            errors.append({"path": str(copy), "missing": sorted(expected.keys() - current.keys()),
                           "extra": sorted(current.keys() - expected.keys()),
                           "changed": sorted(k for k in expected.keys() & current.keys() if expected[k] != current[k])})
        for key in current:
            raw = (copy / key).read_bytes().replace(b"\r\n", b"")
            if b"\n" in raw or b"\r" in raw:
                errors.append(f"non-CRLF text: {copy / key}")
    return {"skill": NAME, "copies": len(copies), "files_per_copy": len(expected), "errors": errors}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--installed", action="store_true", help="also require both user-level installations")
    args = parser.parse_args()
    result = check(args.project_root.resolve(), args.installed)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 1 if result["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
