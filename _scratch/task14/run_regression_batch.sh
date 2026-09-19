#!/usr/bin/env bash
# 天台女儿墙破损变体改动后的回归批跑（本机 run_verification_suite.sh 跑不动，用替身组合：
# 逐场景直跑取退出码 + 打印 OK/ERROR 摘要，日志落在 _scratch/task14/reg/）。
export PATH="/c/Program Files/Git/usr/bin:$PATH"
cd "I:/工作项目/shellstrom2/ShellStorm2" || exit 1

GODOT="I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe"
OUT="_scratch/task14/reg"
mkdir -p "$OUT"

SCENES="
verify_rooftop_32x32_contract
verify_rooftop_railing
verify_rooftop_door
verify_tower_grid_component_alignment
verify_tower_level_blocks
verify_verification_runner_contract
verify_tower_descent_flow
verify_full_3d_game_flow
verify_3d_only_project_structure
probe_rooftop_parapet_alignment
probe_rooftop_parapet_components
probe_rooftop_parapet_damage_prefabs
probe_rooftop_parapet_damage_layout
verify_base_world_flow
verify_3d_performance_budget
verify_expedition_level01_flow
verify_test_level_99_flow
"

for scene in $SCENES; do
  log="$OUT/$scene.txt"
  "$GODOT" --headless --path . "res://tests/verification/$scene.tscn" > "$log" 2>&1
  code=$?
  ok=$(grep -cE "_OK|_PASS|_DONE" "$log" 2>/dev/null)
  err=$(grep -cE "^ERROR:|ERROR: |_FAIL|FAILED" "$log" 2>/dev/null)
  script_err=$(grep -cE "SCRIPT ERROR|Parse Error" "$log" 2>/dev/null)
  printf "%-46s exit=%-3s ok_lines=%-3s err_lines=%-3s script_err=%s\n" "$scene" "$code" "$ok" "$err" "$script_err"
done

echo "---- 详情：每个场景最后一行 OK/PASS/DONE ----"
for scene in $SCENES; do
  log="$OUT/$scene.txt"
  last=$(grep -E "_OK|_PASS|_DONE|FAILED|_FAIL" "$log" 2>/dev/null | tail -1)
  printf "%-46s %s\n" "$scene" "${last:0:150}"
done
