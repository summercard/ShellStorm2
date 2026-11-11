"""隔离运行生产刷怪验收，保存真实退出码与完整日志；不修改生产文件。"""
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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-only", action="store_true")
    parser.add_argument("--negative-bonus", action="store_true")
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()
    executable = Path("I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe")
    if not executable.is_file():
        raise FileNotFoundError(executable)
    mode = "parse" if args.check_only else "negative_bonus" if args.negative_bonus else "production"
    base = f"verification/shellstorm-verification.spawn_ramp/{time.time_ns()}_{mode}"
    env = os.environ.copy()
    for key, folder in (("APPDATA", "appdata"), ("LOCALAPPDATA", "localappdata")):
        env[key] = str(wp.work_path(f"{base}/{folder}/marker").parent)
    log = wp.work_path(f"{base}/run.log")
    result_path = wp.work_path(f"{base}/result.json")
    command = [str(executable), "--headless", "--path", str(ROOT)]
    if args.check_only:
        command += ["--script", "res://tests/verification/verify_expedition01_spawn_ramp.gd", "--check-only"]
    else:
        command += ["res://tests/verification/verify_expedition01_spawn_ramp.tscn"]
    if args.negative_bonus:
        command += ["--", "--negative-bonus"]
    print("隔离目录", env["APPDATA"], env["LOCALAPPDATA"], flush=True)
    print("日志", log, flush=True)
    timed_out = False
    started = time.monotonic()
    with log.open("x", encoding="utf-8") as output:
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT)
        try:
            code = process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)
            code = 124
    text = log.read_text(encoding="utf-8", errors="replace")
    engine_errors = any(token in text for token in ("SCRIPT ERROR", "Parse Error", "ERROR:"))
    marker = "EXPEDITION01_SPAWN_RAMP_DONE" in text
    if args.check_only:
        accepted = code == 0 and not engine_errors
    elif args.negative_bonus:
        accepted = code == 1 and marker and "SPAWN_RAMP_NEGATIVE bonus_mapping_removed" in text and "故障注入：缺bonus映射" in text and "endpoint_boxes=0 failures=1" in text and not engine_errors
    else:
        accepted = code == 0 and "EXPEDITION01_SPAWN_RAMP_OK" in text and not engine_errors
    result = {
        "mode": mode, "process_exit_code": process.returncode,
        "verification_exit_code": code, "accepted": accepted,
        "timed_out": timed_out, "engine_errors": engine_errors,
        "elapsed_sec": round(time.monotonic() - started, 3),
        "log": str(log), "APPDATA": env["APPDATA"], "LOCALAPPDATA": env["LOCALAPPDATA"],
        "command": command,
    }
    result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for line in text.splitlines():
        if any(token in line for token in ("SPAWN_RAMP", "SCRIPT ERROR", "ERROR:", "Parse Error", "远征启动失败")):
            print(line)
    print(json.dumps(result, ensure_ascii=False), flush=True)
    print("结果", result_path, flush=True)
    return 0 if accepted else code if code != 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
