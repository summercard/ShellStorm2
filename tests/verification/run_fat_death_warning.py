"""胖子死亡预警专项：Autoload前隔离，持久入口不依赖工程外临时脚本。"""
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
    parser.add_argument('mode', choices=('headless', 'integration', 'render'), nargs='?', default='headless')
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe'))
    args = parser.parse_args()
    base = f'sessions/2026-11-16_exp01_combat/final_regression/2026-11-16_exp01_combat/fat_warning/{args.mode}/{time.time_ns()}'
    work = wp.work_path(base + '/result.json').parent
    env = os.environ.copy()
    for key in ('APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME'):
        env[key] = str(wp.work_path(base + '/' + key.lower() + '/marker').parent)
    env['FAT_WARNING_EVIDENCE'] = str(work)
    command = [args.godot, '--path', str(ROOT), '--quit-after', '7200']
    command += ['--resolution', '960x720', '--rendering-method', 'gl_compatibility'] if args.mode == 'render' else ['--headless']
    command += ['res://tests/verification/verify_fat_death_warning.tscn', '--', '--' + args.mode]
    print('WORK', work, flush=True)
    with (work / 'run.log').open('w', encoding='utf-8') as handle:
        try:
            code = subprocess.run(command, cwd=ROOT, env=env, stdout=handle, stderr=subprocess.STDOUT, timeout=240).returncode
        except subprocess.TimeoutExpired:
            code = 124
    text = (work / 'run.log').read_text(encoding='utf-8', errors='replace')
    errors = [line for line in text.splitlines() if any(tag in line for tag in ('SCRIPT ERROR', 'Parse Error', 'ERROR:'))]
    summaries = [line for line in text.splitlines() if line.startswith('FAT_DEATH_WARNING checks=')]
    passed = code == 0 and not errors and bool(summaries) and summaries[-1].endswith('failures=0')
    captures = sorted(path.name for path in work.glob('warning_*.png'))
    if args.mode == 'render':
        passed = passed and 'OpenGL' in text and {'warning_025.png', 'warning_075.png'}.issubset(captures)
    result = {'passed': bool(passed), 'exit_code': code, 'engine_errors': errors, 'summary': summaries, 'mode': args.mode,
              'captures': captures, 'appdata_isolated_before_autoload': True, 'command': command, 'work': str(work)}
    (work / 'result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    for line in text.splitlines():
        if any(tag in line for tag in ('SCRIPT ERROR', 'ERROR:', 'FAT_', 'FAILED')):
            print(line)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
