#!/usr/bin/env python3
"""Run specific layout checks against the main project without a second checkout."""

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
from datetime import datetime

from workspace_paths import PROJECT_ROOT, work_path


CASES = {
    'fate': ('capture_expedition_purchase_layout', 'CAPTURE_FATE_PURCHASE_UI_OK'),
    'safe-room': ('verify_exp01_99_safe_room_clutter', 'EXP01_99_SAFE_ROOM_CLUTTER_OK'),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('case', choices=CASES)
    parser.add_argument('--godot', required=True, type=Path)
    parser.add_argument('--resolution', nargs='+', default=['1280x720', '1920x1080'])
    parser.add_argument('--renderer', choices=['forward_plus', 'gl_compatibility'], default='gl_compatibility')
    parser.add_argument('--timeout', type=int, default=240)
    args = parser.parse_args()
    if args.timeout <= 0 or not all(re.fullmatch(r'[1-9]\d*x[1-9]\d*', r) for r in args.resolution):
        parser.error('expected a positive timeout and resolutions in WIDTHxHEIGHT form')
    godot = args.godot.resolve(strict=True)
    scene, marker = CASES[args.case]
    stamp = datetime.now().strftime('%Y%m%d_%H%M%S_%f')
    failed = False
    geometrical = args.case == 'safe-room'
    for resolution in (['headless'] if geometrical else args.resolution):
        output = work_path(f'verification/expedition_layout/{stamp}/{args.case}_{resolution}/godot.log')
        user = output.parent / 'user'
        user.mkdir()
        env = dict(os.environ, **{name: str(user) for name in (
            'APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME',
        )}, SS2_UI_QA_ISOLATED='1', SS2_UI_QA_OUT=str(output.parent))
        flags = ['--headless'] if geometrical else [
            '--rendering-method', args.renderer, '--resolution', resolution, '--max-fps', '60',
        ]
        command = [str(godot), '--path', str(PROJECT_ROOT), *flags,
                   f'res://tests/verification/{scene}.tscn', '--', f'--res={resolution}']
        print(f'START {args.case} {resolution} {output}', flush=True)
        with output.open('wb') as log:
            with subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT) as process:
                try:
                    code = process.wait(timeout=args.timeout)
                except subprocess.TimeoutExpired:
                    if sys.platform == 'win32':
                        subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
                    if process.poll() is None:
                        process.kill()
                    process.wait()
                    code = 124
        lines = output.read_text(encoding='utf-8', errors='replace').splitlines()
        matches = [line for line in lines if line.startswith(marker)]
        errors = [line for line in lines if line.startswith(('SCRIPT ERROR:', 'ERROR:', 'WARNING: ObjectDB'))]
        print(f'END {args.case} {resolution} engine_exit={code} markers={len(matches)} errors={len(errors)}', flush=True)
        for line in matches + errors[:20]:
            print(line, flush=True)
        failed |= code != 0 or len(matches) != 1 or bool(errors)
    return int(failed)


if __name__ == '__main__':
    raise SystemExit(main())
