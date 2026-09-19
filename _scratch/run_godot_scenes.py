"""Direct Godot scene runner.

Why not run_scenes.sh: this machine's WorkBuddy bash shim dies before
coreutils are on PATH, and the console binary needs a real process spawn.

Usage:
    python run_godot_scenes.py [--import] <scene> [<scene> ...]
    python run_godot_scenes.py --only <scene> -- --level=99

Each scene is `res://tests/verification/<scene>.tscn`.
Logs go to `_scratch/reg_<scene>.log`; summary lines are printed at the end.
"""

import argparse
import os
import re
import subprocess
import sys

PROJECT = r"I:\工作项目\shellstrom2\ShellStorm2"
GODOT = r"I:\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe"
SCRATCH = os.path.join(PROJECT, "_scratch")

OK_RE = re.compile(r"^[A-Z][A-Z0-9_]*_OK\b")
BAD_RE = re.compile(r"ERROR|SCRIPT ERROR|FAILED|Traceback")


def run_scene(scene, scene_args, do_import):
    log_path = os.path.join(SCRATCH, "reg_%s.log" % scene)
    cmd = [GODOT, "--headless", "--path", PROJECT, "res://tests/verification/%s.tscn" % scene]
    if scene_args:
        cmd.append("--")
        cmd.extend(scene_args)
    if do_import:
        cmd = [GODOT, "--headless", "--path", PROJECT, "--import"]
    with open(log_path, "wb") as handle:
        proc = subprocess.run(cmd, stdout=handle, stderr=subprocess.STDOUT, cwd=PROJECT)
    with open(log_path, "r", encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    ok_lines = [line for line in text.splitlines() if OK_RE.match(line.strip())]
    bad_lines = []
    for line in text.splitlines():
        stripped = line.strip()
        if "ERROR" in stripped or "SCRIPT ERROR" in stripped or "Traceback" in stripped:
            bad_lines.append(stripped)
    return proc.returncode, ok_lines, bad_lines, log_path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("scenes", nargs="*")
    parser.add_argument("--import", dest="do_import", action="store_true")
    parser.add_argument("--level", dest="level", default="")
    parser.add_argument("--scene-args", dest="scene_args", default="")
    args = parser.parse_args()

    if args.do_import:
        code, ok, bad, path = run_scene(args.scenes[0] if args.scenes else "", [], True)
        print("IMPORT exit=%d log=%s" % (code, path))

    scene_args = []
    if args.level:
        scene_args.append("--level=%s" % args.level)
    if args.scene_args:
        scene_args.extend(args.scene_args.split())

    exit_code = 0
    for scene in args.scenes:
        code, ok, bad, path = run_scene(scene, scene_args, False)
        marker = ok[0] if ok else "(no *_OK marker)"
        print("RESULT %-46s exit=%d ok=%d %s" % (scene, code, len(ok), marker))
        for line in bad[:12]:
            print("   BAD  %s" % line)
        if code != 0 or not ok or bad:
            exit_code = 1
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
