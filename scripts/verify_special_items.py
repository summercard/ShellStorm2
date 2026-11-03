"""Run selected Godot scenes with user data isolated before Autoload initialization."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
from special_items_workspace import ROOT, work_path

parser = argparse.ArgumentParser()
parser.add_argument('scenes', nargs='*', default=['verify_special_items_system'])
parser.add_argument('--visual', action='store_true')
parser.add_argument('--import-only', action='store_true')
args = parser.parse_args()
godot = os.environ.get('GODOT_BIN', 'I:/下载/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe')
base = work_path('sessions/2026-11-03_special_items/session.json').parent
environment = os.environ.copy()
environment['APPDATA'] = str(base / 'isolated_appdata')
environment['LOCALAPPDATA'] = str(base / 'isolated_localappdata')
environment['SHELLSTORM_VERIFICATION_OUTPUT'] = str(base / 'visual')
(base / 'visual').mkdir(parents=True, exist_ok=True)
failed = False
for name in (['import'] if args.import_only else args.scenes):
    if name == 'verify_lamp_furniture_chain':
        environment['LAMP_QA_DIR'] = str(base)
        environment['APPDATA'] = str(base / 'userdata')
    command = [godot, '--path', str(ROOT)]
    if not args.visual:
        command.append('--headless')
    if args.import_only:
        command += ['--editor', '--import']
    else:
        command += [f'res://tests/verification/{name}.tscn']
        if args.visual:
            command += ['--resolution', '1280x720', '--position', '40,40']
    log = base / f'{name}.log'
    try:
        with log.open('wb') as stream:
            run = subprocess.run(command, cwd=ROOT, env=environment, stdout=stream, stderr=subprocess.STDOUT, timeout=240 if args.import_only else 120)
        code = run.returncode
    except subprocess.TimeoutExpired:
        code = 124
    lines = log.read_text(encoding='utf-8', errors='replace').splitlines()
    errors = [line for line in lines if 'SCRIPT ERROR:' in line or line.startswith('ERROR:') or 'Parse Error:' in line]
    expected_file=ROOT/f'tests/verification/expected_errors/{name}.txt'
    expected_patterns=[line.strip() for line in expected_file.read_text(encoding='utf-8').splitlines() if line.strip() and not line.startswith('#')] if expected_file.exists() else []
    unexpected=[line for line in errors if not any(pattern in line for pattern in expected_patterns)]
    markers = [line for line in lines if '_OK' in line or '_FAIL' in line or 'VERIFICATION_FAILED' in line]
    result = {'scene':name, 'exit_code':code, 'errors':errors, 'unexpected_errors':unexpected, 'markers':markers[-15:], 'log':str(log)}
    (base / f'{name}.result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({**result, 'error_count':len(errors), 'errors':errors[:12]}, ensure_ascii=False), flush=True)
    failed = failed or code != 0 or bool(unexpected)
sys.exit(1 if failed else 0)
