"""在Autoload前隔离正式用户数据，运行生产接线与实际弹体命中专项。"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import workspace_paths as wp


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe")
    args = parser.parse_args()
    relative = "sessions/2026-11-16_exp01_combat/last_clearance/2026-11-16_exp01_combat/integration/" + str(time.time_ns())
    base = wp.work_path(relative + "/result.json").parent
    env = os.environ.copy()
    for key in ["APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME"]:
        env[key] = str(wp.work_path(relative + "/" + key.lower() + "/marker").parent)
    env["COMBAT_INTEGRATION_REPORT"] = str(base / "report.json")
    scene = base / "probe.tscn"
    scene.write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://tests/verification/verify_spawn_vfx_combat_integration.gd" id="1"]\n[node name="Integration" type="Node3D"]\nscript = ExtResource("1")\n', encoding="utf-8")
    command = [args.godot, "--headless", "--path", str(ROOT), "--audio-driver", "Dummy", str(scene)]
    print("WORK", base, flush=True)
    with (base / "run.log").open("w", encoding="utf-8") as log:
        try:
            result = subprocess.run(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=240)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code = 124
    text = (base / "run.log").read_text(encoding="utf-8", errors="replace")
    errors = [line for line in text.splitlines() if line.startswith(("SCRIPT ERROR:", "ERROR:"))]
    report_path = base / "report.json"
    report = json.loads(report_path.read_text(encoding="utf-8")) if report_path.exists() else {}
    passed = code == 0 and not errors and report.get("passed") and report.get("completed")
    summary = {"passed": bool(passed), "exit_code": code, "engine_errors": errors, "checks": report.get("checks", 0), "failures": report.get("failures", []), "appdata_isolated_before_autoload": True, "work": str(base), "command": command}
    (base / "result.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    for line in text.splitlines():
        if any(tag in line for tag in ["SCRIPT ERROR", "ERROR:", "SPAWN_VFX_COMBAT_INTEGRATION"]):
            print(line)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
