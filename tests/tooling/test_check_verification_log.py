#!/usr/bin/env python3
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CHECKER = ROOT / "scripts/check_verification_log.py"


def check(log_text: str, expected_text: str = "") -> int:
    with tempfile.TemporaryDirectory() as temp_dir:
        temp = Path(temp_dir)
        log = temp / "scene.log"
        expected = temp / "expected.txt"
        log.write_text(log_text, encoding="utf-8")
        expected.write_text(expected_text, encoding="utf-8")
        return subprocess.run(["python3", str(CHECKER), str(log), str(expected)]).returncode


assert check("OK\n") == 0
assert check("ERROR: unexpected callback\n") == 3
assert check("ERROR: injected failure\n", "injected failure\n") == 0
assert check("ERROR: 2 resources still in use at exit\n") == 4
print("VERIFICATION_LOG_CHECKER_OK: clean, expected, unexpected and leak classifications pass")
