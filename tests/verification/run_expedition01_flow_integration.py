"""在工程外隔离用户目录运行集成专项，不读取真实用户存档。"""
import os
from pathlib import Path
import subprocess
import sys
import time
import psutil

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import workspace_paths as wp

name = sys.argv[1] if len(sys.argv) > 1 else "verify_expedition01_flow_integration"
assert name in {"verify_expedition01_flow_integration", "verify_encounter_trigger_room_flow", "verify_expedition01_reward_flow", "verify_encounter_event_flow", "verify_boss_reinforcement_airdrop"}
suffix = "_partial" if "--partial-delivery-only" in sys.argv[2:] else ""
base = f"sessions/2026-11-11_expedition01_flow/flow_integration/{name}{suffix}"
if "--standard-isolation" in sys.argv[2:]:
    base = f"verification/shellstorm-verification.flow_integration_{name}"

env = os.environ.copy()
for key, folder in [("APPDATA", "appdata"), ("LOCALAPPDATA", "localappdata")]:
    env[key] = str(wp.work_path(f"{base}/{folder}/marker").parent)
log = wp.work_path(f"{base}/run.log")
command = ["I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe", "--headless", "--path", str(ROOT), f"res://tests/verification/{name}.tscn"]
if "--partial-delivery-only" in sys.argv[2:]:
    command.extend(["--", "--partial-delivery-only"])
print("隔离目录", env["APPDATA"], env["LOCALAPPDATA"], flush=True)
print("运行命令", subprocess.list2cmdline(command), flush=True)
tracked = {}
code = 124
with log.open("w", encoding="utf-8") as output:
    process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT)
    root = psutil.Process(process.pid)
    tracked[root.pid] = root
    deadline = time.monotonic() + 600
    try:
        while time.monotonic() < deadline:
            for parent in list(tracked.values()):
                try:
                    for child in parent.children(recursive=True):
                        tracked[child.pid] = child
                except psutil.NoSuchProcess:
                    pass
            status = process.poll()
            living = [p for p in tracked.values() if p.pid != process.pid and p.is_running()]
            if status is not None and not living:
                code = status
                break
            try:
                process.wait(timeout=0.2)
            except subprocess.TimeoutExpired:
                continue
            if living:
                psutil.wait_procs(living, timeout=0.2)
    finally:
        # 仅清理本次 Popen 根进程及已观察到的后代，绝不按名称扫描其他 Godot。
        for parent in list(tracked.values()):
            try:
                for child in parent.children(recursive=True):
                    tracked[child.pid] = child
            except psutil.NoSuchProcess:
                pass
        targets = [p for p in tracked.values() if p.is_running()]
        for target in reversed(targets):
            try:
                target.terminate()
            except psutil.NoSuchProcess:
                pass
        _, alive = psutil.wait_procs(targets, timeout=3)
        for target in alive:
            try:
                target.kill()
            except psutil.NoSuchProcess:
                pass
        _, residual = psutil.wait_procs(alive, timeout=3)
        process.wait(timeout=5)
text = log.read_text(encoding="utf-8", errors="replace")
lines = text.splitlines()
shown = set()
for index, line in enumerate(lines):
    if any(marker in line for marker in ["SCRIPT ERROR", "Parse Error", "ERROR:", "FLOW_INTEGRATION", "ENCOUNTER_TRIGGER", "EXPEDITION01_REWARD_FLOW", "BOSS_AIRDROP", "BOSS_REINFORCEMENT_AIRDROP", "远征启动失败"]):
        end = index + 7 if "ERROR" in line else index + 1
        for row in range(index, min(end, len(lines))):
            if row not in shown:
                print(lines[row])
                shown.add(row)
summary = {"verify_expedition01_flow_integration": "FLOW_INTEGRATION_OK", "verify_encounter_trigger_room_flow": "ENCOUNTER_TRIGGER_ROOM_OK", "verify_expedition01_reward_flow": "failures=0", "verify_encounter_event_flow": "ENCOUNTER_EVENT_FLOW_OK", "verify_boss_reinforcement_airdrop": "BOSS_REINFORCEMENT_AIRDROP_OK"}[name]
if code == 0 and (summary not in text or "SCRIPT ERROR" in text or "ERROR:" in text or residual):
    code = 1
print("实际进程退出码", process.returncode, "验收退出码", code, "本次进程树残留", [p.pid for p in residual])
print("日志", log)
sys.exit(code)
