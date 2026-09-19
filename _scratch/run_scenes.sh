#!/usr/bin/env bash
set -uo pipefail
GODOT="/i/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe"
cd "I:/工作项目/shellstrom2/ShellStorm2" || exit 1
for name in "$@"; do
  out="_scratch/reg_${name}.log"
  "$GODOT" --headless --path . "res://tests/verification/${name}.tscn" > "$out" 2>&1
  code=$?
  ok=$(grep -cE "[A-Z0-9_]+_OK" "$out" || true)
  echo "RESULT ${name} exit=${code} ok_markers=${ok}"
done
