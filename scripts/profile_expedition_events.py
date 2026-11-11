"""Collect event-aligned frame times on the real renderer in a fresh disposable profile."""
import argparse
import os
import subprocess
import tempfile
from pathlib import Path

from workspace_paths import PROJECT_ROOT, work_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("level", choices=["expedition_01", "expedition_02"])
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    args = parser.parse_args()
    parent = work_path("probes/expedition_events/placeholder").parent
    folder = Path(tempfile.mkdtemp(prefix=args.level + "_", dir=parent))
    user_root = folder / "profile"
    user_root.mkdir()
    env = dict(os.environ, APPDATA=str(user_root), LOCALAPPDATA=str(user_root),
               XDG_DATA_HOME=str(user_root), XDG_CONFIG_HOME=str(user_root),
               PROFILE_ROOT=str(user_root), PROFILE_LEVEL=args.level,
               PROFILE_OUTPUT=str(folder / "frames.json"))
    print(folder, flush=True)
    with (folder / "console.txt").open("wb") as log:
        process = subprocess.Popen(
            [args.godot, "--path", str(PROJECT_ROOT), "--rendering-method", "forward_plus",
             "--resolution", "1280x720", "--windowed", "--disable-vsync", "--log-file",
             str(folder / "engine.log"), "res://tools/expedition_event_profile.tscn"],
            env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            code = process.wait(timeout=360)
        except subprocess.TimeoutExpired:
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], check=False)
            else:
                process.kill()
            process.wait()
            return 124
    return code or (0 if (folder / "frames.json").exists() else 3)


if __name__ == "__main__":
    raise SystemExit(main())
