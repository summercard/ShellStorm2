"""正式五房双种子净空与表演验收，Autoload前隔离。"""
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
    parser.add_argument("--render", action="store_true")
    parser.add_argument("--godot", default="I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe")
    parser.add_argument("--seed", type=int)
    parser.add_argument("--safe-threads", action="store_true", help="诊断时使用引擎单线程场景和安全渲染线程，不修改生产配置")
    args = parser.parse_args()
    relative = "sessions/2026-11-16_exp01_combat/last_clearance/" + str(time.time_ns())
    base = wp.work_path(relative + "/result.json").parent
    env = os.environ.copy()
    for key in ["APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME"]:
        env[key] = str(wp.work_path(relative + "/" + key.lower() + "/marker").parent)
    if args.seed is not None:
        env["VFX_CLEARANCE_SEED"] = str(args.seed)
    env["VFX_CLEARANCE_REPORT"] = str(base / "report.json")
    env["VFX_CLEARANCE_OUTPUT"] = str(base)
    scene = wp.work_path(relative + "/probe.tscn")
    scene.write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://tests/verification/verify_spawn_vfx_clearance.gd" id="1"]\n[node name="Clearance" type="Node3D"]\nscript = ExtResource("1")\n', encoding="utf-8")
    command = [args.godot, "--path", str(ROOT), "--audio-driver", "Dummy"]
    command += ["--rendering-method", "forward_plus", "--rendering-driver", "vulkan", "--resolution", "1280x720", "--fixed-fps", "60"] if args.render else ["--headless"]
    if args.safe_threads:
        command += ["--single-threaded-scene", "--render-thread", "safe"]
    command += [str(scene)]
    import re
    textures = list((ROOT / "assets/art/vfx/textures").glob("projectile_enchant_*.png"))
    missing_imports = []
    for path in textures:
        remap = path.with_suffix(path.suffix + ".import")
        caches = re.findall(r'res://([^"\n]+\.ctex)', remap.read_text(encoding="utf-8")) if remap.exists() else []
        if not caches or not all((ROOT / name).is_file() for name in caches):
            missing_imports.append(str(path.relative_to(ROOT)))
    if len(textures) != 7:
        missing_imports.append("projectile_enchant贴图总数应为7")
    if missing_imports:
        summary = {"passed": False, "exit_code": None, "runner_exit_code": 2, "blocked": "主工程Autoload依赖贴图尚未导入；未启动正式验收，不修改其它会话资源", "missing_imports": missing_imports, "work": str(base)}
        (base / "result.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        return 2
    print("WORK", base, flush=True)
    with (base / "run.log").open("w", encoding="utf-8") as log:
        try:
            result = subprocess.run(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=1200)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code = 124
    text = (base / "run.log").read_text(encoding="utf-8", errors="replace")
    errors = [line for line in text.splitlines() if line.startswith(("SCRIPT ERROR:", "ERROR:"))]
    path = base / "report.json"
    report = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    passed = code == 0 and not errors and report.get("completed") and not report.get("failures")
    summary = {"passed": bool(passed), "exit_code": code, "engine_errors": errors, "work": str(base), "isolated_before_autoload": True,
               "command": command, "completed": bool(report.get("completed")), "rows": len(report.get("rows", [])),
               "renderer": report.get("renderer"), "captures": len(list(base.glob("*.png")))}
    (base / "result.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    for line in text.splitlines():
        if any(tag in line for tag in ["VFX_CLEARANCE", "SCRIPT ERROR", "ERROR:"]):
            print(line)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0 if passed else 1
if __name__ == "__main__":
    raise SystemExit(main())
