#!/usr/bin/env python3
import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: check_verification_log.py LOG [EXPECTED_PATTERNS]", file=sys.stderr)
        return 2
    log_path = Path(sys.argv[1])
    expected_path = Path(sys.argv[2]) if len(sys.argv) > 2 else None
    patterns = []
    if expected_path and expected_path.is_file():
        patterns = [
            re.compile(line.strip())
            for line in expected_path.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
    unexpected = []
    leaks = []
    for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not ("SCRIPT ERROR:" in line or re.search(r"(^|\s)ERROR:", line)):
            continue
        if any(pattern.search(line) for pattern in patterns):
            continue
        if "resources still in use at exit" in line or "ObjectDB instances leaked at exit" in line:
            leaks.append(line)
        else:
            unexpected.append(line)
    for line in unexpected:
        print(f"UNEXPECTED_ENGINE_ERROR {line}", file=sys.stderr)
    for line in leaks:
        print(f"RESOURCE_LEAK {line}", file=sys.stderr)
    if unexpected:
        return 3
    if leaks:
        return 4
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
