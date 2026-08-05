#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
suite="${1:-smoke}"

smoke_scenes=(
  verify_framework_health_flow
  verify_player3d_avatar_bounds
  verify_tower_grid_component_alignment
  verify_tower_lighting_wall_combat_regressions
  verify_full_3d_game_flow
)

core_scenes=(
  "${smoke_scenes[@]}"
  verify_player3d_animation_flow
  verify_player3d_vertical_physics_flow
  verify_player3d_weapon_pose_collision_flow
  verify_3d_enemy_behavior_flow
  verify_3d_fate_weapon_flow
  verify_3d_inventory_weapon_flow
  verify_weapon_instance_fate_ownership_flow
  verify_celestial_fate_scope_flow
  verify_tactical_inventory_minimap_flow
  verify_door_passability
  verify_tower_descent_flow
  verify_3d_performance_budget
)

# These scenes read the viewport texture and therefore require a real renderer.
# Keep them out of headless logic suites so CI does not report dummy-renderer
# texture failures as gameplay regressions.
visual_scenes=(
  verify_base_world_3d_visual
  verify_full_3d_visual
  verify_player3d_state_gallery_visual
  verify_player3d_weapon_grip_visual
  verify_player_pixel_art_flow
  verify_tower_descent_visual
  verify_tower_stair_fall_visual
  verify_training_range_3d_visual
  verify_tactical_inventory_minimap_visual
  verify_wall_alignment_overlay
  verify_wall_alignment_pure
  verify_wall_alignment_visual
)

is_visual_scene() {
  local scene_name="$1"
  local visual_name
  for visual_name in "${visual_scenes[@]}"; do
    if [[ "${scene_name}" == "${visual_name}" ]]; then
      return 0
    fi
  done
  return 1
}

run_scene() {
  local scene_name="$1"
  local scene_path="res://tests/verification/${scene_name}.tscn"
  printf '\n[%s] %s\n' "${suite}" "${scene_name}"
  if is_visual_scene "${scene_name}"; then
    "${godot_bin}" --path "${project_root}" --scene "${scene_path}"
  else
    "${godot_bin}" --headless --path "${project_root}" --scene "${scene_path}"
  fi
}

case "${suite}" in
  smoke)
    scenes=("${smoke_scenes[@]}")
    ;;
  core)
    scenes=("${core_scenes[@]}")
    ;;
  full)
    scenes=()
    while IFS= read -r scene_file; do
      scene_name="$(basename "${scene_file}" .tscn)"
      if ! is_visual_scene "${scene_name}"; then
        scenes+=("${scene_name}")
      fi
    done < <(find "${project_root}/tests/verification" -maxdepth 1 -name 'verify_*.tscn' -print | sort)
    ;;
  visual)
    scenes=("${visual_scenes[@]}")
    ;;
  scene)
    if [[ $# -lt 2 ]]; then
      echo "usage: $0 scene verify_scene_name" >&2
      exit 2
    fi
    scenes=("${2%.tscn}")
    ;;
  *)
    echo "unknown suite: ${suite}; expected smoke, core, full, visual, or scene" >&2
    exit 2
    ;;
esac

for scene_name in "${scenes[@]}"; do
  run_scene "${scene_name}"
done

printf '\nVERIFICATION_SUITE_OK suite=%s count=%d\n' "${suite}" "${#scenes[@]}"
