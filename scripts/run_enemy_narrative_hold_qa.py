"""Run the production-tower enemy/narrative probe with a fresh user directory."""
import argparse
import os
from pathlib import Path
import subprocess
from uuid import uuid4

from workspace_paths import work_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    log = work_path(f"verification/enemy_narrative/{uuid4().hex}/tower.log")
    isolated = log.parent / "user"
    isolated.mkdir()
    env = dict(os.environ, APPDATA=str(isolated), LOCALAPPDATA=str(isolated),
               XDG_DATA_HOME=str(isolated), XDG_CONFIG_HOME=str(isolated),
               SS2_ENEMY_NARRATIVE_ISOLATED="1")
    print(log, flush=True)
    try:
        with log.open("wb") as output:
            result = subprocess.run([args.godot, "--headless", "--path", str(project),
                                     "res://tests/verification/verify_enemy_narrative_hold.tscn"],
                                    env=env, stdout=output, stderr=subprocess.STDOUT, timeout=180)
    except subprocess.TimeoutExpired:
        return 124
    log_text = log.read_text(encoding="utf-8", errors="replace")
    if result.returncode != 0:
        return result.returncode
    return int("ENEMY_NARRATIVE_OK " not in log_text or "SCRIPT ERROR:" in log_text or "\nERROR:" in log_text)


if __name__ == "__main__":
    raise SystemExit(main())
