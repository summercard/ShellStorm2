"""枪械全息 UI 专项；运行与导入均使用工程外独立工程和用户档。"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import uuid

import workspace_paths as wp

GODOT = 'I:/下载/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
SCENES = {
    'weapon_hologram_ui': 'res://tests/verification/verify_weapon_hologram_ui.tscn',
    'projectile_enchant_visuals': 'res://tests/verification/verify_projectile_enchant_visuals.tscn',
}
ERROR = re.compile(r'SCRIPT ERROR:|(?:^|\n)\s*ERROR:|Parse Error:|Compile Error:|Failed to load', re.I)


def execute(command, env, directory, label, timeout):
    console = directory / (label + '_console.log')
    engine = directory / (label + '_godot.log')
    # 用户参数必须留在 -- 后，log-file 属于引擎参数。
    split = command.index('--') if '--' in command else len(command)
    command = command[:split] + ['--log-file', str(engine)] + command[split:]
    start = time.monotonic()
    timed_out = False
    with console.open('wb') as stream:
        process = subprocess.Popen(command, env=env, stdout=stream, stderr=subprocess.STDOUT)
        print(f'{label} PID={process.pid} 日志={console}', flush=True)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            # 绝不按进程名称清理其他会话，只回收本次 Popen 创建的 PID。
            if os.name == 'nt':
                # Console wrappers spawn the real engine; stop only this owned tree.
                subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
            else:
                process.kill()
            code = process.wait()
        except BaseException:
            if process.poll() is None:
                if os.name == 'nt':
                    subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
                else:
                    process.kill()
                process.wait()
            raise
    text = console.read_text(encoding='utf-8', errors='replace')
    engine_text = engine.read_text(encoding='utf-8', errors='replace') if engine.exists() else ''
    errors = list(dict.fromkeys(line for line in (text + '\n' + engine_text).splitlines() if ERROR.search(line)))
    result = {'command': command, 'pid': process.pid, 'exit_code': code, 'timed_out': timed_out,
              'elapsed_seconds': round(time.monotonic() - start, 2), 'console': str(console),
              'engine_log': str(engine), 'engine_errors': errors,
              'engine_error_occurrences': len(ERROR.findall(text)),
              'renderer_verified': 'Forward+' in text and 'Vulkan' in text,
              'passed': code == 0 and not timed_out and not errors}
    for line in text.splitlines():
        if ERROR.search(line) or any(key in line for key in ['RESULT ', 'FAIL:', 'CAPTURE ', 'QA_STAGE ']):
            print(line, flush=True)
    return result, text


def copy_resource(source, destination):
    # 源资源只读硬链接；导入可能改写的文本、sidecar 和脚本必须是真副本。
    if Path(source).suffix.lower() in {'.png', '.jpg', '.jpeg', '.webp', '.glb', '.ogg', '.wav', '.ttf', '.otf'}:
        try:
            os.link(source, destination)
            return destination
        except OSError:
            pass
    return shutil.copy2(source, destination)


def isolate(root):
    project = root / 'project'
    project.mkdir()
    for name in ['src', 'scenes', 'assets', 'data', 'tests', 'addons']:
        source = wp.PROJECT_ROOT / name
        if source.exists():
            shutil.copytree(source, project / name, copy_function=copy_resource,
                            ignore=shutil.ignore_patterns('__pycache__', '.git', '.godot'))
    # 部分工作区有顶层 runtime；它属于只读运行投影，不复制到工程内。
    runtime = wp.PROJECT_ROOT / 'runtime'
    if runtime.exists():
        if os.name == 'nt':
            subprocess.run(['cmd', '/c', 'mklink', '/J', str(project / 'runtime'), str(runtime)],
                           capture_output=True, check=True)
        else:
            (project / 'runtime').symlink_to(runtime, target_is_directory=True)
    for name in ['icon.svg', 'icon.svg.import']:
        if (wp.PROJECT_ROOT / name).exists():
            shutil.copy2(wp.PROJECT_ROOT / name, project / name)
    settings = (wp.PROJECT_ROOT / 'project.godot').read_text(encoding='utf-8')
    settings = re.sub(r'^config/(?:use_custom_user_dir|custom_user_dir_name)=.*\n?', '', settings, flags=re.M)
    settings = settings.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="weapon_hologram_qa"', 1)
    settings = re.sub(r'^enabled=PackedStringArray\(.*\)$', 'enabled=PackedStringArray()', settings, flags=re.M)
    (project / 'project.godot').write_text(settings, encoding='utf-8')
    cache = project / '.godot'
    cache.mkdir()
    for name in ['global_script_class_cache.cfg', 'uid_cache.bin']:
        source = wp.PROJECT_ROOT / '.godot' / name
        if source.exists():
            shutil.copy2(source, cache / name)
    imported = wp.PROJECT_ROOT / '.godot/imported'
    if imported.exists():
        shutil.copytree(imported, cache / 'imported')
    return project


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', GODOT))
    parser.add_argument('--logic', action='store_true')
    parser.add_argument('--record-motion', action='store_true', help='仅真实渲染UI专项采集0.09秒间隔PNG帧，不编码视频')
    parser.add_argument('--flight-only', action='store_true', help='projectile专项仅采集真实飞行，不初始化静态grid/mix/light_cast')
    parser.add_argument('--resolution', nargs='+', choices=['1280x720', '1920x1080'], default=['1280x720'])
    parser.add_argument('--scene', nargs='+', default=['weapon_hologram_ui'], help='专项简称、all 或 tests/verification 下的 tscn 路径')
    parser.add_argument('--timeout', type=int, default=240)
    parser.add_argument('--reuse-isolated-project', type=Path, help='仅复用本runner生成的工程外副本，仍重新导入')
    parser.add_argument('--import-timeout', type=int, default=600)
    parser.add_argument('--skip-import', action='store_true', help='仅复用已有完整导入记录的隔离副本；保留原导入证据')
    args = parser.parse_args()
    if args.logic and args.record_motion:
        parser.error('--record-motion 需要真实渲染，不能与 --logic 同用')
    if args.logic and args.flight_only:
        parser.error('--flight-only 需要真实渲染，不能与 --logic 同用')
    scenes = []
    for value in args.scene:
        if value == 'all':
            scenes.extend(SCENES.values())
        elif value in SCENES:
            scenes.append(SCENES[value])
        else:
            path = value.removeprefix('res://').replace('\\', '/')
            if path.startswith('tests/verification/') and path.endswith('.tscn') and '..' not in Path(path).parts:
                scenes.append('res://' + path)
            else:
                parser.error('场景必须为专项简称或 tests/verification/*.tscn')
    root = wp.work_path('verification/weapon_hologram/' + time.strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:6] + '/result.json').parent
    report_path = root / 'result.json'
    print('JSON路径=' + str(report_path), flush=True)
    summary = {'passed': False, 'root': str(root), 'logic': args.logic, 'record_motion': args.record_motion,
               'flight_only': args.flight_only, 'runs': [],
               'isolation': {'appdata_before_autoload': True, 'independent_project_and_cache': True,
                             'custom_user_dir': 'weapon_hologram_qa', 'runtime_present': (wp.PROJECT_ROOT / 'runtime').exists()}}
    report_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
    env = os.environ.copy()
    for key in ['APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'TEMP', 'TMP']:
        directory = root / key.lower()
        directory.mkdir()
        env[key] = str(directory)
    env['WEAPON_HOLOGRAM_VERIFY_ISOLATED'] = '1'
    env['PROJECTILE_ENCHANT_VERIFY_ISOLATED'] = '1'
    if args.reuse_isolated_project:
        project = args.reuse_isolated_project.resolve()
        if project.is_relative_to(wp.PROJECT_ROOT.resolve()) or not project.is_relative_to(wp.work_root()) or not (project.parent / 'result.json').exists():
            parser.error('只能复用本runner生成的工程外隔离副本')
        # 仅同步专项文件，不覆盖副本中正在验收的业务代码版本。
        for scene in scenes:
            relative = scene.removeprefix('res://')
            for suffix in ['.gd', '.tscn']:
                source = (wp.PROJECT_ROOT / relative).with_suffix(suffix)
                if source.exists():
                    shutil.copy2(source, (project / relative).with_suffix(suffix))
    else:
        project = isolate(root)
    summary['project'] = str(project)
    if args.skip_import:
        if not args.reuse_isolated_project:
            parser.error('--skip-import 只允许复用此前已完整导入的隔离副本')
        prior = json.loads((project.parent / 'result.json').read_text(encoding='utf-8'))
        prior_import = prior.get('import', {})
        if not prior_import.get('passed'):
            parser.error('该隔离副本没有完整通过的导入记录，禁止跳过')
        imported = {'passed': True, 'skipped': True, 'prior_evidence': prior_import,
                    'note': '复用已完成导入缓存；本次不代签冷导入'}
    else:
        imported, _ = execute([args.godot, '--headless', '--import', '--quit', '--path', str(project), '--audio-driver', 'Dummy'], env, root, 'import', args.import_timeout)
    summary['import'] = imported
    report_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
    # 导入报错也记录后继续启动专项，以便把实际入口的 parse/runtime 错误交回主代理。
    for scene in dict.fromkeys(scenes):
        for resolution in dict.fromkeys(args.resolution):
            label = Path(scene).stem + '_' + ('logic' if args.logic else resolution)
            run_dir = root / label
            run_dir.mkdir(exist_ok=True)
            output = run_dir / 'output'
            output.mkdir(exist_ok=True)
            run_env = env.copy()
            run_env['SHELLSTORM_VERIFICATION_OUTPUT'] = str(output)
            command = [args.godot, '--path', str(project), '--audio-driver', 'Dummy', '--resolution', resolution]
            command += ['--headless'] if args.logic else ['--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan']
            # log-file 必须置于用户参数之前；execute 追加的位置仍属于引擎选项。
            command.append(scene)
            user_args = []
            if not args.logic and scene == SCENES['projectile_enchant_visuals']:
                user_args.append('--flight-only' if args.flight_only else '--render-grid')
            if args.record_motion and scene == SCENES['weapon_hologram_ui']:
                user_args.append('--record-motion')
            if user_args:
                command += ['--'] + user_args
            enchant_render = not args.logic and scene == SCENES['projectile_enchant_visuals']
            run, text = execute(command, run_env, run_dir, 'scene', min(args.timeout, 60) if enchant_render else args.timeout)
            marker = 'WEAPON_HOLOGRAM_UI_RESULT ' if 'weapon_hologram_ui' in scene else 'PROJECTILE_ENCHANT_VISUALS_RESULT '
            reports = [line.split(marker, 1)[1] for line in text.splitlines() if marker in line]
            try:
                run['report'] = json.loads(reports[-1]) if reports else {}
            except json.JSONDecodeError:
                run['report'] = {}
            run['scene'] = scene
            run['resolution'] = resolution
            run['output'] = str(output)
            run['images'] = [str(p) for p in sorted(output.glob('*.png'))]
            run['video_frames'] = [str(p) for p in sorted((output / 'motion').glob('frame_*.png'))]
            run['video_frame_count'] = len(run['video_frames'])
            run['motion_output'] = str(output / 'motion') if enchant_render or '--record-motion' in user_args else None
            run['motion_frame_pattern'] = str(output / 'motion' / 'frame_%05d.png') if run['motion_output'] else None
            run['motion_interval_seconds'] = (0.045 if enchant_render else 0.09) if run['motion_output'] else None
            run['passed'] = bool(run['passed'] and run['report'].get('passed') and (args.logic or run['renderer_verified']))
            if not args.logic and 'weapon_hologram_ui' in scene:
                run['passed'] = run['passed'] and all((output / (stage + '.png')).exists() for stage in ['k_build', 'purchase_stable', 'confirmation', 'install_motion', 'assembled'])
                run['passed'] = run['passed'] and (output / 'install_impact.png').exists()
                if args.record_motion:
                    motion = run['report'].get('motion', {})
                    run['passed'] = bool(run['passed'] and run['video_frame_count'] > 0
                                         and motion.get('video_frames') == run['video_frame_count']
                                         and not motion.get('recording', True))
            if enchant_render:
                if args.flight_only:
                    required = ['projectile_enchant_flight']
                    run['primary_acceptance'] = 'flight-only非静止真实飞行；跳过静态grid/mix/light_cast'
                else:
                    required = ['projectile_enchant_grid', 'projectile_enchant_mix', 'projectile_enchant_flight',
                                'projectile_enchant_standard_seven', 'projectile_enchant_special_preserve',
                                'projectile_enchant_light_cast']
                    run['primary_acceptance'] = '非静止真实飞行；静态grid/mix仅补充'
                required += [f'projectile_enchant_moving_wrap_trail_{index:02d}' for index in range(3)]
                run['missing_images'] = [name + '.png' for name in required if not (output / (name + '.png')).is_file()]
                motion = run['report'].get('motion', {})
                run['flight_evidence'] = str(output / 'projectile_enchant_flight.json')
                statistics = motion.get('particle_frame_statistics', {})
                keys = ['fire', 'ice', 'poison', 'lightning', 'bounce', 'homing', 'return']
                run['passed'] = bool(run['passed'] and not run['missing_images']
                                     and run['video_frame_count'] > 0 and run['video_frame_count'] >= 60
                                     and motion.get('video_frames') == run['video_frame_count']
                                     and motion.get('video_frame_count') == run['video_frame_count']
                                     and motion.get('recording') is False
                                     and motion.get('pool_active_after') == 0
                                     and run['report'].get('pool', {}).get('active') == 0
                                     and motion.get('completed_flights')
                                     and Path(run['flight_evidence']).is_file()
                                     and all(statistics.get(key, {}).get('changed_frames', 0) > 0
                                             and statistics.get(key, {}).get('visible_frames', 0) > 0 for key in keys))
            summary['runs'].append(run)
            summary['passed'] = bool(imported['passed'] and all(item['passed'] for item in summary['runs']))
            report_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
            print(f"场景={scene} 退出={run['exit_code']} 错误={len(run['engine_errors'])} 通过={run['passed']}", flush=True)
            if args.logic:
                break
    print('JSON路径=' + str(report_path), flush=True)
    return 0 if summary['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
