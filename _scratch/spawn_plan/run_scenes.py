"""Headless Godot 场景批量跑手（本机 bash 缺 coreutils，套件脚本跑不了）。

用法：
    python _scratch/spawn_plan/run_scenes.py <场景1.tscn> [场景2.tscn ...] [--extra-args]

做法与项目既有约定一致：
  * 临时把 `config/use_custom_user_dir` 注入 project.godot 的 [application] 段，
    做用户目录隔离；finally 还原并删掉临时 userdata。
  * project.godot 是 **LF**（其余 .gd/.tscn/.md 才是 CRLF），改动要保 LF。
返回：0 = 全部场景退出码为 0，否则 1。日志落 _scratch/spawn_plan/<scene>.log。
"""

import os
import re
import shutil
import subprocess
import sys

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
GODOT = r"I:\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe"
PROJECT_GODOT = os.path.join(ROOT, "project.godot")
USER_DIR_NAME = "shellstorm2_scratch_probe"
LOG_DIR = os.path.join(ROOT, "_scratch", "spawn_plan")
INJECT_LINE = "config/use_custom_user_dir=true"


def inject_user_dir(text):
    """在 [application] 段首行后插入隔离用户目录开关（保持 LF）。"""
    lines = text.split("\n")
    out = []
    done = False
    for line in lines:
        out.append(line)
        if not done and line.strip() == "[application]":
            out.append(INJECT_LINE)
            done = True
    if not done:
        raise SystemExit("找不到 [application] 段，无法注入用户目录开关")
    return "\n".join(out)


def main():
    args = sys.argv[1:]
    extra = []
    if "--extra-args" in args:
        i = args.index("--extra-args")
        extra = args[i + 1:]
        args = args[:i]
    scenes = args
    if not scenes:
        raise SystemExit("至少要给一个场景路径")

    os.makedirs(LOG_DIR, exist_ok=True)
    with open(PROJECT_GODOT, "r", encoding="utf-8", newline="") as fh:
        original = fh.read()
    already = INJECT_LINE in original
    failed = []
    try:
        if not already:
            with open(PROJECT_GODOT, "w", encoding="utf-8", newline="") as fh:
                fh.write(inject_user_dir(original))
        for scene in scenes:
            name = re.sub(r"[^A-Za-z0-9_.-]", "_", scene.replace("res://", ""))
            log_path = os.path.join(LOG_DIR, name + ".log")
            cmd = [GODOT, "--headless", "--path", ROOT, scene] + extra
            with open(log_path, "wb") as log:
                proc = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
            print("EXIT=%d %s -> %s" % (proc.returncode, scene, log_path))
            if proc.returncode != 0:
                failed.append(scene)
    finally:
        if not already:
            with open(PROJECT_GODOT, "w", encoding="utf-8", newline="") as fh:
                fh.write(original)
        userdata = os.path.join(
            os.environ.get("APPDATA", ""), "Godot", "app_userdata", USER_DIR_NAME
        )
        shutil.rmtree(userdata, ignore_errors=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
