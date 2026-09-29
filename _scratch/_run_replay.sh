#!/usr/bin/env bash
# 跑 verify_expedition_room_type_component_replay 并落盘日志（隔离 APPDATA）
set -u
GODOT="I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe"
mkdir -p /d/ssverif/appdata_authored_dev
export APPDATA="D:/ssverif/appdata_authored_dev"
OUT="$1"
cd "I:/工作项目/shellstrom2/ShellStorm2" || exit 9
"$GODOT" --headless --path . --scene res://tests/verification/verify_expedition_room_type_component_replay.tscn > "$OUT" 2>&1
echo "EXIT=$?"
