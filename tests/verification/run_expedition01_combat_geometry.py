"""隔离运行无独立scene的正式几何专项；可选用指定历史报告做路径覆盖比较。"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import workspace_paths as wp


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seed', type=int, default=77001199)
    parser.add_argument('--baseline', type=Path)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe'))
    args = parser.parse_args()
    base = f'sessions/2026-11-16_exp01_combat/docs/shellstorm-verification/{time.time_ns()}_{args.seed}_geometry'
    work = wp.work_path(base + '/result.json').parent
    env = os.environ.copy()
    for key in ('APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME'):
        env[key] = str(wp.work_path(base + '/' + key.lower() + '/marker').parent)
    env['EXP01_SEED'] = str(args.seed)
    env['EXP01_REPORT'] = str(work / 'geometry.json')
    scene = work / 'probe.tscn'
    scene.write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://tests/verification/verify_expedition01_combat_geometry.gd" id="1"]\n[node name="CombatGeometry" type="Node"]\nscript = ExtResource("1")\n', encoding='utf-8')
    command = [args.godot, '--headless', '--path', str(ROOT), '--audio-driver', 'Dummy', str(scene)]
    print('WORK', work, flush=True)
    with (work / 'run.log').open('w', encoding='utf-8') as handle:
        try:
            code = subprocess.run(command, cwd=ROOT, env=env, stdout=handle, stderr=subprocess.STDOUT, timeout=300).returncode
        except subprocess.TimeoutExpired:
            code = 124
    text = (work / 'run.log').read_text(encoding='utf-8', errors='replace')
    errors = [line for line in text.splitlines() if any(tag in line for tag in ('SCRIPT ERROR', 'Parse Error', 'ERROR:'))]
    report_path = work / 'geometry.json'
    report = json.loads(report_path.read_text(encoding='utf-8')) if report_path.is_file() else {}
    passed = code == 0 and not errors and report.get('seed') == args.seed and len(report.get('rooms', [])) == 5 and report.get('failures') == []
    result = {'passed': bool(passed), 'exit_code': code, 'engine_errors': errors, 'seed': args.seed,
              'appdata_isolated_before_autoload': True, 'command': command, 'work': str(work), 'path_coverage': '未执行，需--baseline指定独立历史报告'}
    if args.baseline and passed:
        path_command = [sys.executable, str(ROOT / 'tests/verification/verify_expedition01_path_coverage.py'), '--baseline', str(args.baseline.resolve()), '--current', str(report_path), '--output', base + '/path_coverage.json']
        with (work / 'path.log').open('w', encoding='utf-8') as handle:
            path_code = subprocess.run(path_command, cwd=ROOT, stdout=handle, stderr=subprocess.STDOUT, timeout=60).returncode
        result.update(path_exit_code=path_code, baseline=str(args.baseline.resolve()), path_coverage='已执行')
        result['passed'] = passed and path_code == 0
    (work / 'result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
