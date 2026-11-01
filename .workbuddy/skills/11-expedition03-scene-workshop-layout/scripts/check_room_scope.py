#!/usr/bin/env python3
"""Read-only scope check; does not reproduce runtime art-key resolution."""
import argparse
import hashlib
import json
from pathlib import Path
import re


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", required=True, type=Path)
    parser.add_argument("rooms", nargs="+")
    args = parser.parse_args()
    root = args.project_root.resolve()
    allowed = root / "assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_03/runtime_rooms"
    checked, errors = [], []
    for value in args.rooms:
        candidate = Path(value.removeprefix("res://"))
        path = (candidate if candidate.is_absolute() else root / candidate).resolve()
        try:
            path.relative_to(allowed.resolve())
            if path.suffix != ".tscn":
                raise ValueError("expected .tscn")
            raw = path.read_bytes()
            text = raw.decode("utf-8-sig")
            root_block = re.search(r"^\[node [^\n]+\]\r?\n(.*?)(?=^\[node|\Z)", text, re.M | re.S)
            if not root_block or not re.search(r'^metadata/level_id\s*=\s*"expedition_03"\s*$', root_block[1], re.M):
                raise ValueError("root metadata does not identify expedition_03")
            if not re.search(r"^\[gd_scene[^\n]*format=3", text):
                raise ValueError("expected Godot TSCN format=3")
            checked.append({"path": path.relative_to(root).as_posix(), "sha256": hashlib.sha256(raw).hexdigest()})
        except (ValueError, OSError, UnicodeError) as exc:
            errors.append({"input": value, "reason": str(exc)})
    print(json.dumps({"level_id": "expedition_03", "checked": checked, "errors": errors}, ensure_ascii=False, indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
