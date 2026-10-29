"""Isolated launcher for the editor's real-level room capture job."""
from pathlib import Path
import argparse
import json
import os
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from workspace_paths import work_path


def write(path, value):
    temporary = path.with_suffix(".writing")
    temporary.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
    os.replace(temporary, path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--locate", action="store_true")
    parser.add_argument("--engine")
    parser.add_argument("--scene", default="res://scenes/ExpeditionLevel03_3D.tscn")
    parser.add_argument("--seed", type=int, default=77003244)
    parser.add_argument("--job", default="current")
    args = parser.parse_args()
    if args.locate:
        print(json.dumps({"root": str(work_path("probes/scene_builder_runtime/jobs"))}))
        return 0
    if not re.fullmatch(r"[a-zA-Z0-9_-]+", args.job):
        raise ValueError("invalid job identifier")
    job = work_path("probes/scene_builder_runtime/jobs/" + args.job)
    if (job / "status.json").exists():
        raise ValueError("capture job already exists")
    job.mkdir(parents=True, exist_ok=True)
    status, index, log = (job / name for name in ("status.json", "index.json", "capture.log"))
    write(status, {"state": "running", "label": "启动隔离关卡进程…"})
    env = os.environ.copy()
    env["APPDATA"] = env["LOCALAPPDATA"] = str(job / "user_data")
    env["PYTHONUTF8"] = "1"
    command = [args.engine, "--headless", "--path", str(ROOT), "--script",
               "res://tools/scene_builder/capture_runtime.gd", "--",
               "scene=" + args.scene, "seed=" + str(args.seed),
               "status=" + str(status), "index=" + str(index)]
    start = time.monotonic()
    with log.open("w", encoding="utf-8") as output:
        try:
            process = subprocess.Popen(command, env=env, stdout=output, stderr=subprocess.STDOUT,
                                       creationflags=0x08000000 if os.name == "nt" else 0)
        except OSError as error:
            write(status, {"state": "failed", "label": "Godot进程启动失败：" + str(error), "log": str(log)})
            return 1
        reason = ""
        while process.poll() is None:
            if (job / "cancel.request").exists():
                reason = "已取消读取，当前编辑场景保留。"
            elif time.monotonic() - start > 120:
                reason = "读取超过120秒，请查看日志并重试。"
            if reason:
                if os.name == "nt":
                    subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
                else:
                    process.kill()
                process.wait()
                break
            time.sleep(0.15)
    text = log.read_text(encoding="utf-8", errors="replace")
    errors = [line for line in text.splitlines() if line.startswith(("SCRIPT ERROR:", "ERROR:"))]
    result = {"state": "failed", "label": reason or "关卡读取失败", "log": str(log),
              "exit_code": process.returncode, "engine_errors": len(errors)}
    if not reason and process.returncode == 0 and not errors and index.exists():
        data = json.loads(index.read_text(encoding="utf-8"))
        if data.get("rows"):
            cache = ROOT / ".godot/editor/scene_builder_runtime/latest.json"
            cache.parent.mkdir(parents=True, exist_ok=True)
            write(cache, data)
            result.update(state="complete", label="已读取%d个真实房间" % len(data["rows"]), index=str(index))
    elif errors and not reason:
        result["label"] = "正式关卡脚本读取失败：" + errors[0][:220]
    write(status, result)
    return 0 if result["state"] == "complete" else 1


if __name__ == "__main__":
    raise SystemExit(main())
