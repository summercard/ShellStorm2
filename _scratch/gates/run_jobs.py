"""Headless Godot 作业跑手（本机 bash 装齐 PortableGit 后可直跑套件，但本脚本用于
临时探针 / 单场景复跑，沿用项目既有的用户目录隔离约定）。

用法：
    python _scratch/gates/run_jobs.py [--nonheadless] <规格> [<规格> ...]

规格格式：
    script:res://路径.gd      -> godot --headless --path ROOT --script <路径>
    scene:res://路径.tscn     -> godot --headless --path ROOT --scene <路径>
    res://路径.tscn           -> 等价 scene:

做法与 `_scratch/spawn_plan/run_scenes.py` 一致：
  * 临时把 `config/use_custom_user_dir` 注入 project.godot 的 [application] 段；
  * project.godot 是 **LF**（其余 .gd/.tscn/.md 才是 CRLF），读写都保 LF；
  * finally 还原原文件并删掉临时 userdata。
日志落 _scratch/gates/<名字>.log。返回 0 = 全部退出码 0。
"""

import os
import re
import shutil
import subprocess
import sys

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
GODOT = r"I:\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe"
PROJECT_GODOT = os.path.join(ROOT, "project.godot")
USER_DIR_NAME = "shellstorm2_gates_probe"
LOG_DIR = os.path.join(ROOT, "_scratch", "gates")
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


def parse(spec):
    """规格 -> (kind, res_path)。"""
    if spec.startswith("script:"):
        return "script", spec[len("script:"):]
    if spec.startswith("scene:"):
        return "scene", spec[len("scene:"):]
    return "scene", spec


def main():
    args = sys.argv[1:]
    nonheadless = False
    if "--nonheadless" in args:
        args.remove("--nonheadless")
        nonheadless = True
    if not args:
        raise SystemExit("至少要给一个规格，例如 scene:res://tests/verification/foo.tscn")

    os.makedirs(LOG_DIR, exist_ok=True)
    with open(PROJECT_GODOT, "r", encoding="utf-8", newline="") as fh:
        original = fh.read()
    already = INJECT_LINE in original
    failed = []
    try:
        if not already:
            with open(PROJECT_GODOT, "w", encoding="utf-8", newline="") as fh:
                fh.write(inject_user_dir(original))
        for spec in args:
            kind, res_path = parse(spec)
            name = re.sub(r"[^A-Za-z0-9_.-]", "_", spec.replace(":", "_").replace("res://", ""))
            log_path = os.path.join(LOG_DIR, name + ".log")
            cmd = [GODOT, "--path", ROOT]
            if not nonheadless:
                cmd.insert(1, "--headless")
            if kind == "script":
                cmd += ["--script", res_path]
            else:
                cmd += ["--scene", res_path]
            with open(log_path, "wb") as log:
                proc = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
            print("EXIT=%d %s -> %s" % (proc.returncode, spec, log_path))
            if proc.returncode != 0:
                failed.append(spec)
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
