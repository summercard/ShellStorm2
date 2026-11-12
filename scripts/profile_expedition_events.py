"""Collect event-aligned frame times on the real renderer in a fresh disposable profile."""
import argparse
import hashlib
import json
import math
import os
import re
import subprocess
import tempfile
from pathlib import Path

from workspace_paths import PROJECT_ROOT, work_path


def summarize_run(data):
    phases = {}
    events = {event["phase"]: event for event in data["events"]}
    for label, wall_ms, *_ in data["samples"]:
        if label.startswith("component_"):
            continue
        phases.setdefault(label, []).append(wall_ms)
    summary = {}
    for label, times in phases.items():
        times.sort()
        summary[label] = {
            "frames": len(times), "p95_ms": times[math.ceil(.95 * len(times)) - 1],
            "p99_ms": times[math.ceil(.99 * len(times)) - 1], "max_ms": times[-1],
            "over_50_ms": sum(value > 50 for value in times),
            "sync_ms": events.get(label, {}).get("sync_ms"),
        }
    warm = data["warm_b"]
    complete = (data["warm_a"]["completed"] and not data["warm_a"]["skipped"]
                and not warm["skipped"] and warm["rooms"] == warm["total"] and warm["rooms"] > 0)
    confirmed = any(e["phase"].startswith("fixture_flight/")
                    and e["details"].get("confirmed")
                    and "hp_after" in e["details"]
                    and e["details"]["hp_after"] < e["details"]["hp_before"]
                    for e in data["events"])
    chest = events.get("chest/0", {}).get("details", {}).get("created", False)
    violations = [label for label, values in summary.items()
                  if values["max_ms"] > 50 or values["p99_ms"] > 33.3]
    return {"phases": summary, "warm_complete": complete, "confirmed_pooled_hit": confirmed,
            "chest_created": chest, "violations": violations,
            "passed": bool(summary and complete and confirmed and chest and not violations)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("level", help="Level ID registered in GameDesignConfig.EXPEDITION_LEVELS")
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--timeout", type=int, default=360, help="Whole-process wall clock limit in seconds")
    parser.add_argument("--gate", action="store_true", help="Use a BaseWorld3D dungeon entrance ID")
    parser.add_argument("--seed", type=int, default=41021)
    parser.add_argument("--rooms", type=int, default=4, help="Maximum distinct rooms to visit after the start")
    parser.add_argument("--check-budget", action="store_true", help="Exit 7 for incomplete coverage or frame-budget violations")
    args = parser.parse_args()
    if args.rooms < 1:
        parser.error("--rooms must be positive")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", args.level):
        parser.error("level must be a single level ID")
    if args.timeout < 1:
        parser.error("--timeout must be positive")
    parent = work_path("probes/expedition_events/placeholder").parent
    folder = Path(tempfile.mkdtemp(prefix=args.level + "_", dir=parent))
    user_root = folder / "profile"
    user_root.mkdir()
    tracked_inputs = ["project.godot", "src/base3d/BaseWorld3D.gd", "src/world3d/RunPersistenceService.gd",
                      "scripts/profile_expedition_events.py", "src/world3d/Dungeon3D.gd", "src/world3d/DungeonRoom3D.gd",
                      "src/world3d/TowerDescent3D.gd", "src/world3d/TreasureChest3D.gd",
                      "src/base/BaseManager.gd", "src/base/ProfileSaveService.gd", "src/core/AtomicJsonStore.gd", "src/world3d/WastelandLight3D.gd",
                      "src/combat3d/ProjectilePool3D.gd", "src/vfx/VfxPool3D.gd", "scenes/ExpeditionLoadingScreen.gd",
                      "src/core/AudioManager.gd", "src/combat3d/Projectile3D.gd", "src/enemy3d/Enemy3D.gd",
                      "src/enemy3d/EnemyAvatar3D.gd", "src/enemy3d/EliteContentCatalog.gd",
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
               PROFILE_ROOT=str(user_root), PROFILE_LEVEL=args.level, PROFILE_SEED=str(args.seed),
               PROFILE_ROOMS=str(args.rooms), PROFILE_GATE="1" if args.gate else "0",
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
    frames_path = folder / "frames.json"
    after = source_fingerprints()
    if frames_path.is_file():
        summary = summarize_run(json.loads(frames_path.read_text(encoding="utf-8")))
        summary["sources_stable"] = after == metadata["before"]
        summary["passed"] = summary["passed"] and summary["sources_stable"]
        (folder / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
        if args.check_budget and not summary["passed"] and not code:
            code = 7
    metadata.update({"after": after, "exit_code": code, "engine_errors": errors})
    metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
