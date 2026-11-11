"""以正常CLI真实渲染远征仪式；所有可写数据在工程外，禁止editor导入。"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import workspace_paths as wp


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64.exe'))
    parser.add_argument('--logic', action='store_true')
    parser.add_argument('--loading-e2e', action='store_true')
    parser.add_argument('--base-menu-e2e', action='store_true')
    parser.add_argument('--official-hosts', action='store_true')
    parser.add_argument('--seeds', nargs='+', type=int, default=[20261110, 20261111])
    parser.add_argument('--timeout', type=int, default=300)
    args = parser.parse_args()
    if (args.loading_e2e or args.base_menu_e2e or args.official_hosts) and args.logic:
        parser.error('真实读取页/基地菜单/正式host E2E必须使用Forward+，不支持--logic')
    if args.loading_e2e and args.base_menu_e2e:
        parser.error('--loading-e2e 与 --base-menu-e2e 二选一')
    if args.official_hosts and (args.loading_e2e or args.base_menu_e2e):
        parser.error('--official-hosts 只跑正式host装配，不与读取页E2E同进程')
    root = wp.work_path('verification/expedition_entry/' + time.strftime('%Y%m%d_%H%M%S') + '/result.json').parent
    project = root / 'project'
    project.mkdir()
    # 只链接运行所需目录；缓存独立复制，运行不会改主工程导入缓存。
    for name in ['src', 'scenes', 'assets', 'data', 'tests', 'addons']:
        source = wp.PROJECT_ROOT / name
        dest = project / name
        if os.name == 'nt':
            subprocess.run(['cmd', '/c', 'mklink', '/J', str(dest), str(source)], capture_output=True, check=True)
        else:
            dest.symlink_to(source, target_is_directory=True)
    for name in ['icon.svg', 'icon.svg.import']:
        shutil.copy2(wp.PROJECT_ROOT / name, project / name)
    settings = (wp.PROJECT_ROOT / 'project.godot').read_text(encoding='utf-8')
    (project / 'project.godot').write_text(settings, encoding='utf-8')
    cache = project / '.godot'
    cache.mkdir()
    for name in ['global_script_class_cache.cfg', 'uid_cache.bin']:
        source = wp.PROJECT_ROOT / '.godot' / name
        if source.exists():
            shutil.copy2(source, cache / name)
    shutil.copytree(wp.PROJECT_ROOT / '.godot/imported', cache / 'imported')
    env = os.environ.copy()
    for key in ['APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME']:
        directory = root / key.lower()
        directory.mkdir()
        env[key] = str(directory)
    output = root / 'output'
    output.mkdir()
    env['SHELLSTORM_VERIFICATION_OUTPUT'] = str(output)
    runs = []
    print('证据目录: ' + str(root), flush=True)
    seeded = args.loading_e2e or args.base_menu_e2e
    prefix = 'basemenu_' if args.base_menu_e2e else 'loading_'
    for seed in args.seeds if seeded else [None]:
        label = prefix + str(seed) if seed is not None else ('hosts' if args.official_hosts else 'ceremonies')
        command = [args.godot, '--path', str(project), '--audio-driver', 'Dummy', '--resolution', '1280x720', '--fixed-fps', '60', '--log-file', str(root / (label + '_godot.log'))]
        if args.logic:
            command.append('--headless')
        else:
            command += ['--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan']
        command.append('res://tests/verification/verify_expedition_entry_hologram_ceremonies.tscn')
        if seed is not None:
            command += ['--', ('--base-menu-e2e-seed=' if args.base_menu_e2e else '--loading-e2e-seed=') + str(seed)]
        elif args.official_hosts:
            command += ['--', '--official-hosts']
        console = root / (label + '_console.log')
        started = time.monotonic()
        timed_out = False
        with console.open('wb') as log:
            process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT)
            try:
                exit_code = process.wait(timeout=args.timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                process.kill()
                exit_code = process.wait()
        text = console.read_text(encoding='utf-8', errors='replace')
        images = [str(p) for p in output.glob((label + '_*.png') if seed is not None else '*.png')]
        report_path = output / (label + '_result.json')
        report = json.loads(report_path.read_text(encoding='utf-8')) if seed is not None and report_path.exists() else {}
        errors = sum(1 for line in text.splitlines() if line.startswith(('SCRIPT ERROR:', 'ERROR:')))
        renderer_verified = 'Forward+' in text and 'Vulkan' in text
        passed = not timed_out and exit_code == 0 and errors == 0 and (args.logic or renderer_verified)
        if seed is not None:
            stages = ['select', 'solid_close', 'gameplay'] if args.base_menu_e2e else ['solid_close', 'gameplay']
            passed = passed and report.get('completed', False) and not report.get('failures') and all((output / (label + '_' + stage + '.png')).exists() for stage in stages)
        elif args.official_hosts:
            # 正式host组不出图；通过与否只看进程退出码、0 engine error 与 OFFICIAL_HOST_OK 行数。
            passed = passed and text.count('OFFICIAL_HOST_OK') == 4
        else:
            passed = passed and (args.logic or len(images) >= 6)
        run = {'seed': seed, 'command': command, 'exit_code': exit_code, 'timed_out': timed_out, 'elapsed_seconds': round(time.monotonic() - started, 2), 'engine_errors': errors, 'renderer_verified': renderer_verified, 'passed': bool(passed), 'console': str(console), 'images': images, 'report': report}
        runs.append(run)
        summary = {'passed': all(item['passed'] for item in runs), 'runs': runs, 'output': str(output)}
        (root / 'result.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
        print('\n'.join(line for line in text.splitlines() if any(key in line for key in ['SCRIPT ERROR', 'ERROR:', 'FAIL:', '_OK', 'CAPTURE', 'LOADING_E2E', 'EXPEDITION_ENTRY_RESULT', 'Parse Error'])), flush=True)
        print(json.dumps(run, ensure_ascii=False, indent=2), flush=True)
    return 0 if all(item['passed'] for item in runs) else 1


if __name__ == '__main__':
    raise SystemExit(main())
