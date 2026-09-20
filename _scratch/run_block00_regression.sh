#!/usr/bin/env bash
export PATH="/c/Program Files/Git/usr/bin:$PATH"
cd "I:/工作项目/shellstrom2/ShellStorm2"
GODOT="/i/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe"
declare -a SCENES=(
  "tests/verification/verify_block00_floor98_assembly.tscn"
  "tests/verification/verify_tower_grid_component_alignment.tscn"
  "tests/verification/verify_rooftop_32x32_contract.tscn"
  "tests/verification/verify_rooftop_floor_facade_components.tscn"
  "tests/verification/probe_rooftop_parapet_alignment.tscn"
  "tests/verification/verify_stair_entry_clearance.tscn"
)
for s in "${SCENES[@]}"; do
  name=$(basename "$s" .tscn)
  log="_scratch/reg_${name}.log"
  "$GODOT" --headless --path . "res://$s" > "$log" 2>&1
  code=$?
  marker=$(grep -a -o -E "(BLOCK00_ASSEMBLY_OK|BLOCK00_ASSEMBLY_FAIL|TOWER_GRID_COMPONENT_ALIGNMENT_OK|ROOFTOP_WEST_EXPANSION_CONTRACT_PASS|ROOFTOP_FLOOR_FACADE_OK|PROBE_ALIGN_DONE|STAIR_ENTRY_CLEARANCE failures=[0-9]+)" "$log" | head -3 | tr '\n' '|')
  echo "RESULT $name exit=$code markers=[$marker]"
done
