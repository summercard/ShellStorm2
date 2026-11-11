"""Collect event-aligned frame times on the real renderer in a fresh disposable profile."""
import argparse
import hashlib
import json
import os
import subprocess
import tempfile
from pathlib import Path

from workspace_paths import PROJECT_ROOT, work_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("level", choices=["expedition_01", "expedition_02"])
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--timeout", type=int, default=360, help="Whole-process wall clock limit in seconds")
    args = parser.parse_args()
    if args.timeout < 1:
        parser.error("--timeout must be positive")
    parent = work_path("probes/expedition_events/placeholder").parent
    folder = Path(tempfile.mkdtemp(prefix=args.level + "_", dir=parent))
    user_root = folder / "profile"
    user_root.mkdir()
    tracked_inputs = ["project.godot", "src/world3d/Dungeon3D.gd", "src/world3d/DungeonRoom3D.gd",
                      "src/world3d/TowerDescent3D.gd", "src/world3d/TreasureChest3D.gd",
                      "src/base/BaseManager.gd", "src/base/ProfileSaveService.gd", "src/world3d/WastelandLight3D.gd",
                      "src/combat3d/ProjectilePool3D.gd", "src/vfx/VfxPool3D.gd", "scenes/ExpeditionLoadingScreen.gd",
                      "src/core/AudioManager.gd", "src/combat3d/Projectile3D.gd", "src/enemy3d/Enemy3D.gd",
                      "src/world3d/SecretBranch3D.gd", "assets/shaders/chest_spotlight_beam.gdshader",
                      "assets/shaders/chest_spotlight_pool.gdshader", "tools/expedition_event_profile.gd"]
    def source_fingerprints():
        return {path: hashlib.sha256((PROJECT_ROOT / path).read_bytes()).hexdigest()
                for path in tracked_inputs if (PROJECT_ROOT / path).is_file()}
    revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=PROJECT_ROOT,
                              capture_output=True, text=True)
    metadata = {"git_head": revision.stdout.strip() if revision.returncode == 0 else None,
                "before": source_fingerprints()}
    metadata_path = folder / "run.json"
    metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    env = dict(os.environ, APPDATA=str(user_root), LOCALAPPDATA=str(user_root),
               XDG_DATA_HOME=str(user_root), XDG_CONFIG_HOME=str(user_root),
               PROFILE_ROOT=str(user_root), PROFILE_LEVEL=args.level,
               PROFILE_LOADING_TIMEOUT_MS=str(max(1, args.timeout - 120) * 1000),
               PROFILE_OUTPUT=str(folder / "frames.json"))
    print(folder, flush=True)
    with (folder / "console.txt").open("wb") as log:
        process = subprocess.Popen(
            [args.godot, "--path", str(PROJECT_ROOT), "--rendering-method", "forward_plus",
             "--resolution", "1280x720", "--windowed", "--disable-vsync", "--log-file",
             str(folder / "engine.log"), "res://tools/expedition_event_profile.tscn"],
            env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            code = process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], check=False)
            else:
                process.kill()
            process.wait()
            code = 124
    code = code or (0 if (folder / "frames.json").exists() else 3)
    with (folder / "console.txt").open(encoding="utf-8", errors="replace") as log:
        errors = sum(line.startswith(("SCRIPT ERROR:", "ERROR:")) for line in log)
    if errors and not code:
        code = 6
    metadata.update({"after": source_fingerprints(), "exit_code": code, "engine_errors": errors})
    metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
