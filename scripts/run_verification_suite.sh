#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
suite="${1:-smoke}"
test_timeout_seconds="${GODOT_TEST_TIMEOUT_SECONDS:-180}"
if [[ "${suite}" == "soak" && -z "${GODOT_TEST_TIMEOUT_SECONDS+x}" ]]; then
	test_timeout_seconds=3700
fi
active_godot_pid=""
active_watchdog_pid=""

cleanup_active_test() {
  if [[ -n "${active_watchdog_pid}" ]] && kill -0 "${active_watchdog_pid}" 2>/dev/null; then
    kill -TERM "${active_watchdog_pid}" 2>/dev/null || true
    wait "${active_watchdog_pid}" 2>/dev/null || true
  fi
  active_watchdog_pid=""
  if [[ -n "${active_godot_pid}" ]] && kill -0 "${active_godot_pid}" 2>/dev/null; then
    kill -TERM "${active_godot_pid}" 2>/dev/null || true
    wait "${active_godot_pid}" 2>/dev/null || true
  fi
  active_godot_pid=""
}

trap cleanup_active_test EXIT
trap 'cleanup_active_test; exit 130' INT
trap 'cleanup_active_test; exit 143' TERM

smoke_scenes=(
  verify_3d_only_project_structure
  verify_player3d_avatar_bounds
  verify_tower_grid_component_alignment
  verify_tower_lighting_wall_combat_regressions
  verify_full_3d_game_flow
)

core_scenes=(
  "${smoke_scenes[@]}"
  verify_floor_plan_generator
  verify_arrival_gate_floor_bundle_flow
  verify_unified_player_interaction_flow
  verify_tower_floor_room_authority
  verify_base_rooftop_transit_door_motion
  verify_floor_visibility_shadow_patch
  verify_player3d_animation_flow
  verify_player3d_debug_scale_flow
  verify_player3d_vertical_physics_flow
  verify_player3d_weapon_pose_collision_flow
  verify_3d_enemy_behavior_flow
  verify_enemy_illumination_states
  verify_monster_ai_light_effects
  verify_monster_ai_system_complete
  verify_unique_elite_roster_flow
  verify_unique_boss_content_flow
  verify_three_segment_tower_generation_flow
  verify_3d_melee_combat_flow
  verify_3d_melee_feedback_flow
  verify_training_range_3d_flow
  verify_3d_fate_weapon_flow
  verify_3d_inventory_weapon_flow
  verify_weapon_attachment_inventory_flow
  verify_weapon_instance_fate_ownership_flow
  verify_celestial_fate_scope_flow
  verify_tactical_inventory_minimap_flow
  verify_backpack_equipment_flow
  verify_scene_facility_shared_palette
  verify_base_facility_framework
  verify_base_shop_save_flow
  verify_tower_facility_inventory_binding
  verify_tower_base_facility_persistent_flow
  verify_tower_extraction_return_flow
  verify_game_entry_flow
  verify_base_world_flow
  verify_dual_weapon_quick_map_fate_flow
  verify_tarot_fate_runtime
  verify_door_passability
  verify_tower_descent_flow
  verify_base99_floor_player_collision_flow
  verify_base99_mezzanine_underdeck_blocker
  verify_3d_performance_budget
  verify_performance_runtime_complete
  verify_graphics_settings_ui_flow
  verify_pause_game_save_reset_flow
  verify_3d_flashlight_charge_flow
)

# These scenes read the viewport texture and therefore require a real renderer.
# Keep them out of headless logic suites so CI does not report dummy-renderer
# texture failures as gameplay regressions.
visual_scenes=(
  verify_base99_modular_room_visual
  verify_graphics_settings_visual
  verify_facility_light_retoggle_visual
  verify_3d_melee_combat_visual
  verify_base_vending_visual
  verify_base_world_3d_visual
  verify_full_3d_visual
  verify_player3d_state_gallery_visual
  verify_player3d_weapon_grip_visual
  verify_tower_descent_visual
  verify_tower_stair_fall_visual
  verify_training_range_3d_visual
  verify_tactical_inventory_minimap_visual
  verify_reference_hud_fate_visual
  verify_wall_alignment_overlay
  verify_wall_alignment_pure
  verify_wall_alignment_visual
  verify_ai_performance_soak
)

renderer_scenes=(
  "${visual_scenes[@]}"
  verify_formal_3d_asset_gallery_visual
  verify_formal_asset_placement_visual
)

is_renderer_scene() {
  local scene_name="$1"
  local renderer_name
  for renderer_name in "${renderer_scenes[@]}"; do
    if [[ "${scene_name}" == "${renderer_name}" ]]; then
      return 0
    fi
  done
  return 1
}

run_scene() {
  local scene_name="$1"
  local scene_path="res://tests/verification/${scene_name}.tscn"
  local scene_result=0
  printf '\n[%s] %s\n' "${suite}" "${scene_name}"
  if is_renderer_scene "${scene_name}"; then
    "${godot_bin}" --path "${project_root}" --scene "${scene_path}" &
  else
    "${godot_bin}" --headless --path "${project_root}" --scene "${scene_path}" &
  fi
  active_godot_pid="$!"
  (
    watchdog_sleep_pid=""
    cleanup_watchdog_sleep() {
      if [[ -n "${watchdog_sleep_pid}" ]] && kill -0 "${watchdog_sleep_pid}" 2>/dev/null; then
        kill -TERM "${watchdog_sleep_pid}" 2>/dev/null || true
        wait "${watchdog_sleep_pid}" 2>/dev/null || true
      fi
    }
    trap 'cleanup_watchdog_sleep; exit 0' TERM INT EXIT
    sleep "${test_timeout_seconds}" &
    watchdog_sleep_pid="$!"
    wait "${watchdog_sleep_pid}" || exit 0
    watchdog_sleep_pid=""
    if kill -0 "${active_godot_pid}" 2>/dev/null; then
      printf '\nTIMEOUT %s after %ss; terminating PID %s\n' \
        "${scene_name}" "${test_timeout_seconds}" "${active_godot_pid}" >&2
      kill -TERM "${active_godot_pid}" 2>/dev/null || true
      sleep 2
      kill -KILL "${active_godot_pid}" 2>/dev/null || true
    fi
  ) &
  active_watchdog_pid="$!"
  if wait "${active_godot_pid}"; then
    scene_result=0
  else
    scene_result=$?
  fi
  active_godot_pid=""
  if kill -0 "${active_watchdog_pid}" 2>/dev/null; then
    kill -TERM "${active_watchdog_pid}" 2>/dev/null || true
  fi
  wait "${active_watchdog_pid}" 2>/dev/null || true
  active_watchdog_pid=""
  return "${scene_result}"
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
      if ! is_renderer_scene "${scene_name}"; then
        scenes+=("${scene_name}")
      fi
    done < <(find "${project_root}/tests/verification" -maxdepth 1 -name 'verify_*.tscn' -print | sort)
    ;;
  visual)
    scenes=()
    for visual_name in "${visual_scenes[@]}"; do
      if [[ "${visual_name}" != "verify_ai_performance_soak" ]]; then
        scenes+=("${visual_name}")
      fi
    done
    ;;
  soak)
	printf 'NOTICE: soak is a deferred release/CI job. Do not run it during interactive development acceptance.\n'
    scenes=(verify_ai_performance_soak)
    ;;
  scene)
    if [[ $# -lt 2 ]]; then
      echo "usage: $0 scene verify_scene_name" >&2
      exit 2
    fi
    scenes=("${2%.tscn}")
    ;;
  *)
    echo "unknown suite: ${suite}; expected smoke, core, full, visual, soak, or scene" >&2
    exit 2
    ;;
esac

for scene_name in "${scenes[@]}"; do
  run_scene "${scene_name}"
done

printf '\nVERIFICATION_SUITE_OK suite=%s count=%d\n' "${suite}" "${#scenes[@]}"
