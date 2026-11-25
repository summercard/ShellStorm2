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


BASELINE_ENVIRONMENT = {"renderer": "forward_plus", "quality": "high", "viewport": "(1280.0, 720.0)"}
BASELINE_GODOT = "4.7.2"
ENGINE_ERROR = re.compile(r"^\s*(?:SCRIPT )?ERROR:")
EXIT_LEAK = re.compile(r"ObjectDB instances?(?: (?:was|were))? leaked at exit|resources? still in use at exit", re.I)


def classify_console(lines):
    errors = 0
    exit_warnings = []
    for line in lines:
        if EXIT_LEAK.search(line):
            exit_warnings.append(line.strip())
        elif ENGINE_ERROR.match(line):
            errors += 1
    return errors, exit_warnings


def summarize_run(data, requested_rooms):
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
            "frames": len(times), "p50_ms": times[math.ceil(.50 * len(times)) - 1],
            "p95_ms": times[math.ceil(.95 * len(times)) - 1],
            "p99_ms": times[math.ceil(.99 * len(times)) - 1], "max_ms": times[-1],
            "over_50_ms": sum(value > 50 for value in times),
            "sync_ms": events.get(label, {}).get("sync_ms"),
        }
    environment_mismatches = {
        field: {"expected": expected, "actual": data.get(field)}
        for field, expected in BASELINE_ENVIRONMENT.items() if data.get(field) != expected
    }
    version = data.get("godot")
    if not isinstance(version, str) or not re.match(rf"^{re.escape(BASELINE_GODOT)}[.-]stable\b", version):
        environment_mismatches["godot"] = {"expected": f"{BASELINE_GODOT} stable", "actual": version}
    warm_a = data["warm_a"]
    warm_b = data["warm_b"]
    complete_a = (warm_a.get("completed") is True and warm_a.get("skipped") is False
                  and warm_a.get("truncated") == "" and warm_a.get("kinds_total", 0) > 0
                  and warm_a.get("kinds_done") == warm_a["kinds_total"]
                  and warm_a.get("vfx_total", 0) > 0 and warm_a.get("vfx_pending") == 0)
    box_resources = warm_b.get("box_enemy_resources")
    box_entries = box_resources.get("entries") if isinstance(box_resources, dict) else None
    box_complete = (isinstance(box_entries, list) and box_resources.get("completed") is True
                    and all(isinstance(entry, dict) and entry.get("path") and entry.get("kinds")
                            and entry.get("state") in ("loaded", "reused") for entry in box_entries))
    roar_warm = warm_b.get("roar_icon", {})
    overlay_warm = warm_b.get("occlusion_overlay", {})
    complete_b = (warm_b.get("skipped") is False and warm_b.get("truncated") == "" and box_complete
                  and warm_b.get("rooms", 0) > 0 and warm_b["rooms"] == warm_b.get("total")
                  and roar_warm.get("completed", False) and roar_warm.get("retained", False)
                  and bool(overlay_warm)
                  and (not overlay_warm.get("applicable", True)
                       or (overlay_warm.get("completed", False) and overlay_warm.get("restored", False)
                           and overlay_warm.get("same_material", False))))
    confirmed = any(e["phase"].startswith("fixture_flight/")
                    and e["details"].get("confirmed")
                    and "hp_after" in e["details"]
                    and e["details"]["hp_after"] < e["details"]["hp_before"]
                    for e in data["events"])
    chest = events.get("chest/0", {}).get("details", {}).get("created", False)
    entries = [event["details"] for event in data["events"]
               if event["phase"].startswith(("enter/", "return_enter/"))]
    visited = {entry["room"] for entry in entries}
    visited.discard(data["visited"][0])
    route_complete = (len(visited) == min(requested_rooms, len(data["rooms"]) - 1)
                      and all(entry.get("current_room") == entry["room"] for entry in entries))
    violations = [label for label, values in summary.items()
                  if values["max_ms"] > 50 or values["p99_ms"] > 33.3]
    complete = complete_a and complete_b
    return {"phases": summary, "environment_mismatches": environment_mismatches,
            "warm_complete": complete, "warm_a_complete": complete_a, "warm_b_complete": complete_b,
            "box_enemy_resources_complete": box_complete, "confirmed_pooled_hit": confirmed,
            "chest_created": chest, "route_complete": route_complete,
            "violations": violations, "passed": bool(summary and not environment_mismatches and complete
                                                   and confirmed and chest and route_complete and not violations)}


def finalize_summary(summary, sources_stable, execution_ok, exit_warnings):
    # A valid frame sample can still fail the independent shutdown contract.
    frame_gate_passed = bool(summary["passed"] and sources_stable and execution_ok)
    shutdown_clean = not exit_warnings
    return {**summary, "sources_stable": sources_stable, "frame_gate_passed": frame_gate_passed,
            "shutdown_clean": shutdown_clean, "passed": frame_gate_passed and shutdown_clean}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("level", help="Level ID registered in GameDesignConfig.EXPEDITION_LEVELS")
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--timeout", type=int, default=360, help="Whole-process wall clock limit in seconds")
    parser.add_argument("--gate", action="store_true", help="Use a BaseWorld3D dungeon entrance ID")
    parser.add_argument("--seed", type=int, default=41021)
    parser.add_argument("--rooms", type=int, default=4, help="Maximum distinct rooms to visit after the start")
    parser.add_argument("--check-budget", action="store_true",
                        help="Exit 7 for baseline environment, coverage, frame-budget, or shutdown violations")
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
                      "assets/shaders/chest_spotlight_pool.gdshader", "tools/expedition_event_profile.gd",
                      "src/core/GraphicsSettingsManager.gd", "src/enemy3d/EliteArmsTakerEquipment.gd",
                      "src/combat3d/WeaponModel3D.gd", "src/map/SpawnBoxCatalog.gd",
                      "src/map/MonsterInjector.gd", "src/world3d/RuntimeCollisionIndex.gd",
                      "src/world3d/RoomFurnishingNavigation.gd", "src/core/GameplaySpatialRegistry3D.gd",
                      "src/enemy3d/EnemyIllumination3D.gd", "src/vfx/VfxMonsterRoarIcon3D.gd",
                      "src/enemy3d/EliteRosterService.gd", "src/enemy3d/RoamingEliteRunDirector.gd",
                      "src/enemy3d/EnemyWarmup.gd", "src/world3d/LoadingResourceWarmup.gd"]
    plan_dir = PROJECT_ROOT / "data" / "level_plans" / args.level
    tracked_inputs.extend(p.relative_to(PROJECT_ROOT).as_posix() for p in sorted(plan_dir.rglob("*.json")))
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
        errors, exit_warnings = classify_console(log)
    if errors and not code:
        code = 6
    frames_path = folder / "frames.json"
    after = source_fingerprints()
    if frames_path.is_file():
        summary = finalize_summary(
            summarize_run(json.loads(frames_path.read_text(encoding="utf-8")), args.rooms),
            after == metadata["before"], code == 0, exit_warnings,
        )
        (folder / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
        if args.check_budget and not summary["passed"] and not code:
            code = 7
    metadata.update({"after": after, "exit_code": code, "engine_errors": errors,
                     "exit_cleanup_warnings": exit_warnings})
    metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
