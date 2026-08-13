#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"
duration_seconds="${SHELLSTORM_SOAK_SECONDS:-3600}"
report_dir="${SHELLSTORM_GPU_REPORT_DIR:-${project_root}/outputs/verification}"
timestamp="$(date +%Y%m%d_%H%M%S)"
report_path="${report_dir}/target_device_gpu_profiler_${timestamp}.log"

printf 'NOTICE: target-device GPU profiling is a deferred release/CI job, not an interactive acceptance step.\n'

mkdir -p "${report_dir}"
{
	printf 'TARGET_DEVICE_GPU_PROFILER_BEGIN timestamp=%s duration_s=%s\n' "${timestamp}" "${duration_seconds}"
	printf 'os=%s\n' "$(uname -a)"
	if command -v system_profiler >/dev/null 2>&1; then
		system_profiler SPDisplaysDataType 2>/dev/null || true
	elif command -v lspci >/dev/null 2>&1; then
		lspci 2>/dev/null | grep -Ei 'vga|3d|display' || true
	fi
	SHELLSTORM_SOAK_SECONDS="${duration_seconds}" \
	SHELLSTORM_REQUIRE_GPU_TIMING=1 \
	GODOT_TEST_TIMEOUT_SECONDS="$((duration_seconds + 120))" \
		"${project_root}/scripts/run_verification_suite.sh" scene verify_ai_performance_soak
	printf 'TARGET_DEVICE_GPU_PROFILER_PASS report=%s\n' "${report_path}"
} 2>&1 | tee "${report_path}"
