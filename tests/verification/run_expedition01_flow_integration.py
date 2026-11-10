"""在工程外隔离用户目录运行集成专项，不读取真实用户存档。"""
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import workspace_paths as wp

name = sys.argv[1] if len(sys.argv) > 1 else "verify_expedition01_flow_integration"
assert name in {"verify_expedition01_flow_integration", "verify_encounter_trigger_room_flow", "verify_expedition01_reward_flow", "verify_encounter_event_flow"}
suffix = "_partial" if "--partial-delivery-only" in sys.argv[2:] else ""
base = f"sessions/2026-11-11_expedition01_flow/flow_integration/{name}{suffix}"
env = os.environ.copy()
for key, folder in [("APPDATA", "appdata"), ("LOCALAPPDATA", "localappdata")]:
    env[key] = str(wp.work_path(f"{base}/{folder}/marker").parent)
log = wp.work_path(f"{base}/run.log")
command = ["I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe", "--headless", "--path", str(ROOT), f"res://tests/verification/{name}.tscn"]
if "--partial-delivery-only" in sys.argv[2:]:
    command.extend(["--", "--partial-delivery-only"])
print("隔离目录", env["APPDATA"], env["LOCALAPPDATA"], flush=True)
print("运行命令", subprocess.list2cmdline(command), flush=True)
with log.open("w", encoding="utf-8") as output:
    try:
        result = subprocess.run(command, cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=240)
        code = result.returncode
    except subprocess.TimeoutExpired:
        code = 124
text = log.read_text(encoding="utf-8", errors="replace")
lines = text.splitlines()
for index, line in enumerate(lines):
    if any(marker in line for marker in ["SCRIPT ERROR", "Parse Error", "ERROR:", "_OK", "FLOW_INTEGRATION_", "EXPEDITION01_REWARD_FLOW", "远征启动失败"]):
        print("\n".join(lines[index:index + 7]))
print("日志", log)
if "SCRIPT ERROR" in text or "Parse Error" in text:
    code = 1
sys.exit(code)
