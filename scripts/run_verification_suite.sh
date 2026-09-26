#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
suite="${1:-smoke}"
aggregate_mode=false
verification_tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/shellstorm-verification.XXXXXX")"

# Windows / Git Bash：Godot 是原生 exe，只认 Windows 路径。MSYS 的虚拟路径
# （/tmp/...、/i/...）传给它会被判成 "Invalid project path" 并直接中止，
# 而 python3 也会把 /i/... 解析成 I:\i\...。能拿到 cygpath 时统一转成
# drive-letter 形式（I:/...），MSYS 与原生 exe 都能接受。
# 在 macOS/Linux 上 cygpath 不存在，本段整体跳过，行为与原来完全一致。
if command -v cygpath >/dev/null 2>&1; then
  project_root="$(cygpath -m "${project_root}")"
  verification_tmp_root="$(cygpath -m "${verification_tmp_root}")"
fi

isolated_project_root="${verification_tmp_root}/project"
verification_log_dir="${verification_tmp_root}/logs"
verification_user_dir_name="ShellStorm2Verification_$$_$(date +%s)"
verification_user_dir_names=("${verification_user_dir_name}")
verification_scene_sequence=0
mkdir -p "${isolated_project_root}" "${verification_log_dir}"

seed_isolated_import_cache() {
  local source_cache="${project_root}/.godot"
  local target_cache="${isolated_project_root}/.godot"
  local cache_entry
  [[ -d "${source_cache}/imported" ]] || return 0
  mkdir -p "${target_cache}"
  for cache_entry in .gdignore global_script_class_cache.cfg uid_cache.bin imported; do
    [[ -e "${source_cache}/${cache_entry}" ]] || continue
    if [[ "$(uname -s)" == "Darwin" ]]; then
      cp -cR "${source_cache}/${cache_entry}" "${target_cache}/"
    elif cp -a --reflink=auto "${source_cache}/${cache_entry}" "${target_cache}/" 2>/dev/null; then
      :
    else
      cp -a "${source_cache}/${cache_entry}" "${target_cache}/"
    fi
  done
}

while IFS= read -r entry; do
  ln -s "${entry}" "${isolated_project_root}/$(basename "${entry}")"
done < <(
  find "${project_root}" -mindepth 1 -maxdepth 1 \
    ! -name project.godot \
    ! -name .git \
    ! -name .godot \
    ! -name .codex-tmp \
    ! -name _scratch \
    ! -name Godot \
    -print
)
seed_isolated_import_cache
if [[ "${SHELLSTORM_VERIFICATION_FORCE_COLD_CLASS_CACHE:-0}" == "1" ]]; then
  rm -f "${isolated_project_root}/.godot/global_script_class_cache.cfg"
fi
write_isolated_project_settings() {
  local isolated_name="$1"
  awk -v isolated_name="${isolated_name}" '
  /^\[application\]$/ {
    print
    print "config/use_custom_user_dir=true"
    print "config/custom_user_dir_name=\"" isolated_name "\""
    next
  }
  { print }
  ' "${project_root}/project.godot" > "${isolated_project_root}/project.godot"
}
write_isolated_project_settings "${verification_user_dir_name}"
export SHELLSTORM_VERIFICATION_USER_DIR_NAME="${verification_user_dir_name}"
verification_import_log="${verification_log_dir}/project_import.log"
if ! "${godot_bin}" --headless --path "${isolated_project_root}" --import \
  >"${verification_import_log}" 2>&1; then
  cat "${verification_import_log}"
  printf 'VERIFICATION_IMPORT_FAILED\n' >&2
  exit 2
fi
if ! python3 "${project_root}/scripts/check_verification_log.py" \
  "${verification_import_log}" /dev/null; then
  cat "${verification_import_log}"
  printf 'VERIFICATION_IMPORT_LOG_FAILED\n' >&2
  exit 3
fi
if [[ ! -d "${isolated_project_root}/.godot" || -L "${isolated_project_root}/.godot" ]]; then
  printf 'VERIFICATION_CACHE_ISOLATION_FAILED path=%s\n' \
    "${isolated_project_root}/.godot" >&2
  exit 2
fi
export SHELLSTORM_VERIFICATION_CACHE_ISOLATED="1"
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

cleanup_verification_workspace() {
  cleanup_active_test
  rm -rf "${verification_tmp_root}"
  local isolated_name
  for isolated_name in "${verification_user_dir_names[@]}"; do
    rm -rf "${HOME}/Library/Application Support/Godot/app_userdata/${isolated_name}"
    rm -rf "${HOME}/.local/share/godot/app_userdata/${isolated_name}"
    # Windows：Godot 把自定义用户目录落在 %APPDATA%\Godot\app_userdata 下。
    if [[ -n "${APPDATA:-}" ]]; then
      rm -rf "${APPDATA}/Godot/app_userdata/${isolated_name}"
    fi
  done
}

trap cleanup_verification_workspace EXIT
trap 'cleanup_verification_workspace; exit 130' INT
trap 'cleanup_verification_workspace; exit 143' TERM

smoke_scenes=(
  verify_3d_only_project_structure
  verify_player3d_avatar_bounds
  verify_tower_grid_component_alignment
  verify_tower_level_blocks
  verify_tower_lighting_wall_combat_regressions
  verify_full_3d_game_flow
)

core_scenes=(
  "${smoke_scenes[@]}"
  verify_floor_plan_generator
  verify_level_plan_design_source
  verify_reward_service_flow
  verify_reward_ground_handoff
  verify_run_merchant_transaction
  verify_run_merchant_integration
  verify_room_graph_persistence_services
  verify_verification_runner_contract
  verify_hud_presenter_3d
  verify_postfx_overlay_runtime
  verify_speech_bubble_3d
  verify_dialogue_ui_flow
  verify_narrative_timeline
  verify_opening_script_runtime
  verify_new_save_handoff
  verify_tower_journey_polish
  verify_arrival_gate_floor_bundle_flow
  verify_common_floor_tile_components_v004
  verify_common_wall_door_components_v004
  verify_battle_wall_floor_facility_kit
  verify_central_expedition_hologram_facility
  verify_expedition_level01_flow
  verify_test_level_99_flow
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
  verify_vfx_pool_lifecycle
  verify_combat_vfx_toon_v002
  verify_unique_elite_roster_flow
  verify_unique_boss_content_flow
  verify_three_segment_tower_generation_flow
  verify_3d_melee_combat_flow
  verify_3d_melee_feedback_flow
  verify_training_range_3d_flow
  verify_3d_fate_weapon_flow
  verify_3d_inventory_weapon_flow
  verify_weapon_instance_contract_matrix
  verify_starting_weapon_contract
  verify_equipment_transaction_service
  verify_weapon_attachment_inventory_flow
  verify_weapon_instance_fate_ownership_flow
  verify_celestial_fate_scope_flow
  verify_finite_ammo_flow
  verify_guaranteed_loadout_ammo_flow
  verify_avatar_return_persistence_flow
  verify_tactical_inventory_minimap_flow
  verify_backpack_equipment_flow
  verify_scene_facility_shared_palette
  verify_base_fixture_glow
  verify_base_facility_framework
  verify_base_shop_save_flow
  verify_workshop_transaction_flow
  verify_extraction_points_spend_transaction
  verify_run_settlement_transaction
  verify_revival_policy_contract
  verify_tower_facility_inventory_binding
  verify_tower_base_facility_persistent_flow
  verify_tower_extraction_return_flow
  verify_expedition_extraction_carry_return
  verify_expedition_departure_carry
  verify_death_during_extraction_flow
  verify_game_entry_flow
  verify_base_world_flow
  verify_dual_weapon_quick_map_fate_flow
  verify_tarot_fate_runtime
  verify_door_passability
  verify_tower_descent_flow
  verify_base99_floor_player_collision_flow
  verify_base99_structural_asset_integration
  verify_base99_wall_content_v021
  verify_base99_remaining_facilities_v021
  verify_3d_performance_budget
  verify_performance_runtime_complete
  verify_graphics_settings_ui_flow
  verify_gamepad_input_flow
  verify_pause_game_save_reset_flow
  verify_3d_flashlight_charge_flow
  verify_3d_combat_progression_flow
  verify_dungeon_wave_intermission
  verify_expedition_wave_chain
  verify_3d_parity_core
  verify_3d_reload_state_flow
  verify_3d_vision_input_flow
  verify_base99_loft_guardrail_collision
  verify_base99_loft_layout_v021
  verify_base99_optimized_packages_v021
  verify_base99_stair_walkable_v021
  verify_base99_wall_visual_replacement
  verify_base_facility_interaction_zones
  verify_base_optional_facilities_removed
  verify_base_overhaul_flow
  verify_block00_floor98_assembly
  verify_character_authoring_bundle
  verify_door_function_check
  verify_enemy_stimulus_activation
  verify_first_elite_deployment_flow
  verify_first_elite_growth_flow
  verify_formal_3d_asset_import
  verify_main_entry_cinematic_flow
  verify_main_entry_realtime_sun_flow
  verify_melee_zombie_presentation
  verify_music_system
  verify_player3d_diy_flow
  verify_player3d_head_accessory_flow
  verify_player3d_idle_animation_flow
  verify_player3d_lower_body_socket_flow
  verify_player3d_state_gallery_flow
  verify_postfx_autopersist
  verify_requested_experience_upgrade_flow
  verify_rooftop_32x32_contract
  verify_rooftop_door
  verify_rooftop_floor_facade_components
  verify_rooftop_railing
  verify_runtime_autosave_flow
  verify_security_zombie_presentation
  verify_stair_entry_clearance
  verify_stair_unified_support
  verify_state_machine_safety
  verify_tower_camera_occlusion_flow
  verify_tower_runtime_restart_restore
  verify_wardrobe_preview_fill_flow
)

# These scenes read the viewport texture and therefore require a real renderer.
# Keep them out of headless logic suites so CI does not report dummy-renderer
# texture failures as gameplay regressions.
visual_scenes=(
  verify_base99_modular_room_visual
  verify_base99_floor_visuals_v021
  verify_graphics_settings_visual
  verify_facility_light_retoggle_visual
  verify_3d_melee_combat_visual
  verify_base_vending_visual
  verify_base_world_3d_visual
  verify_full_3d_visual
  verify_player3d_state_gallery_visual
  verify_player3d_weapon_grip_visual
  verify_tower_descent_visual
  verify_test_level_99_visual
  verify_tower_stair_fall_visual
  verify_training_range_3d_visual
  verify_tactical_inventory_minimap_visual
  verify_reference_hud_fate_visual
  verify_wall_alignment_overlay
  verify_wall_alignment_pure
  verify_wall_alignment_visual
  verify_ai_performance_soak
  verify_base99_door_visuals_v021
  verify_first_elite_visual
  verify_player3d_head_accessory_visual
  verify_wardrobe_layout_visual
  verify_formal_3d_asset_gallery_visual
  verify_formal_asset_placement_visual
)

# 必须由人工操控/观察才能得出可靠结论；登记但不进入自动套件。
manual_scenes=(
  verify_debug_camera_hotkeys
)

# 退役入口保留显式清单，避免“未注册”与“已退役”混为一谈。
retired_scenes=(
)

renderer_scenes=(
  "${visual_scenes[@]}"
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
  local log_result=0
  local preflight_log="${verification_log_dir}/${scene_name}.preflight.log"
  local scene_log="${verification_log_dir}/${scene_name}.scene.log"
  local expected_errors="${project_root}/tests/verification/expected_errors/${scene_name}.txt"
  # 每个场景共用导入缓存，但必须拥有独立 user://；预检与正片共用同一目录。
  # 这样前一场景写下的长期档案不会改变后一场景的开局条件。
  verification_scene_sequence=$((verification_scene_sequence + 1))
  verification_user_dir_name="${verification_user_dir_names[0]}_${verification_scene_sequence}"
  verification_user_dir_names+=("${verification_user_dir_name}")
  write_isolated_project_settings "${verification_user_dir_name}"
  export SHELLSTORM_VERIFICATION_USER_DIR_NAME="${verification_user_dir_name}"
  printf '\n[%s] %s\n' "${suite}" "${scene_name}"
  if ! "${godot_bin}" --headless --path "${isolated_project_root}" \
    --script res://scripts/verify_scene_preflight.gd -- "${scene_path}" >"${preflight_log}" 2>&1; then
    cat "${preflight_log}"
    printf 'LOAD_FAILURE %s\n' "${scene_name}" >&2
    return 2
  fi
  cat "${preflight_log}"
  if ! python3 "${project_root}/scripts/check_verification_log.py" "${preflight_log}" "${expected_errors}"; then
    printf 'PREFLIGHT_LOG_FAILURE %s\n' "${scene_name}" >&2
    return 3
  fi
  if is_renderer_scene "${scene_name}"; then
    "${godot_bin}" --path "${isolated_project_root}" --scene "${scene_path}" >"${scene_log}" 2>&1 &
  else
    "${godot_bin}" --headless --path "${isolated_project_root}" --scene "${scene_path}" >"${scene_log}" 2>&1 &
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
  cat "${scene_log}"
  if python3 "${project_root}/scripts/check_verification_log.py" "${scene_log}" "${expected_errors}"; then
    log_result=0
  else
    log_result=$?
  fi
  if (( scene_result == 0 && log_result != 0 )); then
    return "${log_result}"
  fi
  return "${scene_result}"
}

case "${suite}" in
  smoke)
    scenes=("${smoke_scenes[@]}")
    ;;
  core)
    scenes=("${core_scenes[@]}")
    ;;
  aggregate)
    aggregate_mode=true
    aggregate_target="${2:-core}"
    case "${aggregate_target}" in
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
      *)
        echo "unknown aggregate target: ${aggregate_target}; expected smoke, core, or full" >&2
        exit 2
        ;;
    esac
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
  batch)
    if [[ $# -lt 2 ]]; then
      echo "usage: $0 batch verify_scene_name [verify_scene_name ...]" >&2
      exit 2
    fi
    aggregate_mode=true
    scenes=()
    for requested_scene in "${@:2}"; do
      scenes+=("${requested_scene%.tscn}")
    done
    ;;
  *)
    echo "unknown suite: ${suite}; expected smoke, core, aggregate, full, visual, soak, scene, or batch" >&2
    exit 2
    ;;
esac

failed_scenes=()
for scene_name in "${scenes[@]}"; do
  if run_scene "${scene_name}"; then
    continue
  else
    scene_result=$?
  fi
  if [[ "${aggregate_mode}" != "true" ]]; then
    exit "${scene_result}"
  fi
  failed_scenes+=("${scene_name}:${scene_result}")
done

if (( ${#failed_scenes[@]} > 0 )); then
  printf '\nVERIFICATION_SUITE_FAILED suite=%s count=%d failed=%d\n' \
    "${suite}" "${#scenes[@]}" "${#failed_scenes[@]}" >&2
  printf 'FAILED_SCENE %s\n' "${failed_scenes[@]}" >&2
  exit 1
fi

# 静态门禁：Godot 运行资产命名（去版本化执行计划 P4）。
# 存量欠账未清零前只拦「新增」带版本资产；快照陈旧（欠账已还却没缩表）返回 2。
# 退出码 1 = 新增违规，2 = 欠账快照陈旧。
case "${suite}" in
  core|aggregate|full)
    naming_status=0
    python3 "${project_root}/scripts/check_asset_runtime_naming.py" --quiet || naming_status=$?
    if (( naming_status != 0 )); then
      if (( naming_status == 2 )); then
        printf '\nVERIFICATION_SUITE_FAILED suite=%s reason=asset_runtime_naming_debt_stale\n' \
          "${suite}" >&2
      else
        printf '\nVERIFICATION_SUITE_FAILED suite=%s reason=asset_runtime_naming\n' \
          "${suite}" >&2
      fi
      exit 1
    fi
    ;;
esac

printf '\nVERIFICATION_SUITE_OK suite=%s count=%d\n' "${suite}" "${#scenes[@]}"
