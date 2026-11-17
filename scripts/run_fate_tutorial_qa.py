"""命运教程与真实对白渲染专项；仅复用工程外已导入副本，绝不启动主工程编辑器。"""
import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time
import uuid

import workspace_paths as wp
from run_weapon_hologram_qa import GODOT

DEFAULT_COPY = wp.work_root() / 'verification/weapon_hologram/20261116_173024_0f0e06/project'
SCENES = {
    'fate_tutorial_dialogue': 'res://tests/verification/verify_fate_tutorial_dialogue.tscn',
    'weapon_hologram_ui': 'res://tests/verification/verify_weapon_hologram_ui.tscn',
    'narrative_timeline': 'res://tests/verification/verify_narrative_timeline.tscn',
}
ERROR = re.compile(r'SCRIPT ERROR:|\bERROR:|\bParse Error:|\bCompile Error:|Failed to load', re.I)
KNOWN_TIMELINE = re.compile(r'^\s*ERROR: \[NarrativeDirector\] cue『player\.teleport』执行失败.*$')
CAPTURES = ['drop_hologram_duo', 'drop_exit', 'offer_tutorial_duo', 'offer_released',
            'normal_green_duo', 'portrait_detail', 'assembled_hologram_duo',
            'assembled_k_hint', 'assembled_released']


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_copy(project):
    project = project.resolve()
    if project == wp.PROJECT_ROOT.resolve() or project.is_relative_to(wp.PROJECT_ROOT.resolve()):
        raise ValueError('禁止在主工程或工程内部执行')
    if not project.is_relative_to(wp.work_root()) or project.name != 'project':
        raise ValueError('必须复用 work_root 下的既有隔离 project')
    config = (project / 'project.godot').read_text(encoding='utf-8')
    if not re.search(r'^config/use_custom_user_dir=true\s*$', config, re.M):
        raise ValueError('副本未启用 custom_user_dir')
    if not re.search(r'^config/custom_user_dir_name="weapon_hologram_qa"\s*$', config, re.M):
        raise ValueError('副本 custom_user_dir 不是已授权的 weapon_hologram_qa')
    if (project / 'override.cfg').exists():
        raise ValueError('副本存在 override.cfg，须先人工核实隔离与渲染设置')
    evidence = project.parent / 'result.json'
    prior = json.loads(evidence.read_text(encoding='utf-8'))
    if not prior.get('import', {}).get('passed') or not (project / '.godot/imported').is_dir():
        raise ValueError('缺少完整导入证据或 imported 缓存；本 runner 不重导全项目')
    return project, prior['import']


def required_files(scenes):
    roots = ['src/narrative/*.gd', 'src/ui/dialogue/*.gd', 'src/ui/weapon_build/*.gd',
             'src/i18n/*.gd', 'data/narrative/*.json', 'assets/art/ui/dialogue/*.tscn',
             'assets/art/ui/weapon_build/*.tscn']
    files = {p.relative_to(wp.PROJECT_ROOT) for pattern in roots for p in wp.PROJECT_ROOT.glob(pattern)}
    files.update(Path(p) for p in ['src/world3d/Dungeon3D.gd', 'src/world3d/DungeonRoom3D.gd',
                                  'src/npc/NpcCharacter3D.gd', 'src/base3d/Base99Rescue3D.gd',
                                  'src/weapons/FateCardView.gd', 'src/base/ItemRegistry.gd',
                                  'src/weapons/WeaponInstance.gd', 'src/weapons/WeaponDropGrade.gd',
                                  'src/rewards/RewardService.gd',
                                  'assets/art/vfx/combat_3d/vfx_fat_zombie_slam_root_top3d.tscn',
                                  'assets/art/vfx/combat_3d/vfx_fat_zombie_slam_root_top3d.gd',
                                  'assets/art/vfx/combat_3d/vfx_fat_zombie_slam_root_top3d.gd.uid',
                                  'assets/art/vfx/combat_3d/textures/enm_normal_fat_zombie21_slam_dust.png',
                                  'assets/art/vfx/combat_3d/textures/enm_normal_fat_zombie21_slam_ripple.png',
                                  'assets/art/shared/textures/enemies/tex_color_85eaa809e59fa600fe6c.png'])
    for scene in scenes:
        path = Path(scene.removeprefix('res://'))
        files.update([path, path.with_suffix('.gd')])
    # 代码依赖递归；资源仅收齐专项UI/VFX小型场景，不展开整屋/敌人模型资源树。
    pending = list(files)
    while pending:
        relative = pending.pop()
        source = wp.PROJECT_ROOT / relative
        if not source.is_file():
            raise ValueError('缺少专项依赖：' + str(source))
        source_text = source.read_text(encoding='utf-8') if source.suffix in ['.gd', '.tscn', '.json'] else ''
        for reference in re.findall(r'res://([^"\s\)]+\.[A-Za-z0-9]+)', source_text):
            dependency = Path(reference)
            scoped_resource = reference.startswith(('assets/art/ui/', 'assets/art/vfx/combat_3d/'))
            code_dependency = dependency.parts[0] == 'src' and dependency.suffix == '.gd'
            scene_dependency = source.suffix == '.tscn' and relative.as_posix().startswith(('assets/art/ui/', 'assets/art/vfx/combat_3d/'))
            if (code_dependency or scoped_resource or scene_dependency) and dependency not in files:
                if dependency.suffix in ['.gd', '.tscn', '.tres', '.png', '.webp', '.jpg', '.gdshader']:
                    files.add(dependency)
                    pending.append(dependency)
    for relative in list(files):
        for suffix in ['.uid', '.import']:
            sidecar = relative.with_name(relative.name + suffix)
            if (wp.PROJECT_ROOT / sidecar).is_file():
                files.add(sidecar)
    return sorted(files)


def synchronize(project, root, scenes):
    rows = []
    for relative in required_files(scenes):
        source, target = wp.PROJECT_ROOT / relative, project / relative
        old_hash = digest(target) if target.exists() else None
        row = {'path': relative.as_posix(), 'source_sha256': digest(source), 'previous_sha256': old_hash,
               'changed': old_hash != digest(source)}
        if row['changed']:
            if target.exists():
                backup = root / 'copy_before_sync' / relative
                backup.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, backup)
                row['backup'] = str(backup)
            target.parent.mkdir(parents=True, exist_ok=True)
            # replace 避免继承旧副本可能存在的硬链接后原位覆盖源资源。
            staging = target.with_name(target.name + '.qa_' + uuid.uuid4().hex)
            shutil.copy2(source, staging)
            os.replace(staging, target)
        rows.append(row)
    (root / 'sync_manifest.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding='utf-8')
    return rows


@contextmanager
def own_copy_lock(project):
    lock = project.parent / 'fate_tutorial_qa.lock'
    descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    try:
        os.write(descriptor, str(os.getpid()).encode('ascii'))
        os.close(descriptor)
        yield
    finally:
        lock.unlink()


def isolated_env(root):
    env = os.environ.copy()
    for key in ['APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME',
                'TEMP', 'TMP', 'TMPDIR']:
        path = root / key.lower()
        path.mkdir(parents=True, exist_ok=True)
        env[key] = str(path)
    env['SHELLSTORM_FATE_TUTORIAL_ISOLATED'] = '1'
    env['WEAPON_HOLOGRAM_VERIFY_ISOLATED'] = '1'
    return env


def classify_errors(text, scene):
    errors, known = [], []
    for line in text.splitlines():
        if ERROR.search(line):
            if scene == SCENES['narrative_timeline'] and KNOWN_TIMELINE.fullmatch(line):
                known.append(line)
            else:
                errors.append(line)
    return list(dict.fromkeys(errors)), list(dict.fromkeys(known))


def execute(command, env, directory, label, timeout, scene=''):
    console, engine = directory / (label + '_console.log'), directory / (label + '_godot.log')
    split = command.index('--') if '--' in command else len(command)
    command = command[:split] + ['--log-file', str(engine)] + command[split:]
    started = time.monotonic()
    timed_out = False
    with console.open('wb') as stream:
        process = subprocess.Popen(command, env=env, cwd=directory, stdout=stream,
                                   stderr=subprocess.STDOUT, start_new_session=os.name != 'nt')
        print(f'{label} 自有PID={process.pid} 日志={console}', flush=True)
        try:
            code = process.wait(timeout=timeout)
        except BaseException as exc:
            if process.poll() is None:
                if os.name == 'nt':
                    subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True, check=False)
                else:
                    os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            if not isinstance(exc, subprocess.TimeoutExpired):
                raise
            timed_out, code = True, process.returncode
    text = console.read_text(encoding='utf-8', errors='replace')
    merged = text + '\n' + (engine.read_text(encoding='utf-8', errors='replace') if engine.exists() else '')
    errors, known = classify_errors(merged, scene)
    return {'command': command, 'pid': process.pid, 'exit_code': code, 'timed_out': timed_out,
            'elapsed_seconds': round(time.monotonic() - started, 3), 'console': str(console),
            'engine_log': str(engine), 'engine_errors': errors, 'known_expected_errors': known,
            'renderer_verified': bool(re.search(r'Forward\+', merged) and re.search(r'Vulkan', merged)),
            'passed': code == 0 and not timed_out and not errors}, text


def missing_classes(project, rows):
    cache_path = project / '.godot/global_script_class_cache.cfg'
    cache = cache_path.read_text(encoding='utf-8') if cache_path.exists() else ''
    result = []
    for row in rows:
        if row['path'].endswith('.gd'):
            text = (project / row['path']).read_text(encoding='utf-8')
            for name in re.findall(r'^class_name\s+(\w+)', text, re.M):
                if not re.search(r'"class":\s*&?"' + re.escape(name) + '"', cache):
                    result.append(name)
    return result


def self_test():
    # 无 Godot、无 Popen、无工程写入的 runner 自测。
    assert classify_errors('SCRIPT ERROR: bad\nParse Error: bad\nERROR: bad', '')[0]
    expected = 'ERROR: [NarrativeDirector] cue『player.teleport』执行失败（degraded=false）：缺参数'
    assert classify_errors(expected, SCENES['narrative_timeline']) == ([], [expected])
    assert classify_errors(expected, SCENES['fate_tutorial_dialogue'])[0] == [expected]
    assert classify_errors(expected + '\nERROR: another', SCENES['narrative_timeline'])[0] == ['ERROR: another']
    assert classify_errors('Compile Error: nope', '')[0]
    assert len(required_files([SCENES['fate_tutorial_dialogue']])) > 10
    print('RUNNER_SELF_TEST_OK：错误分类、负测边界、依赖存在性；未启动Godot', flush=True)
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', GODOT))
    parser.add_argument('--reuse-isolated-project', type=Path, default=DEFAULT_COPY)
    parser.add_argument('--scene', nargs='+', default=['fate_tutorial_dialogue'], help='专项简称、suite 或 tests/verification/*.tscn')
    parser.add_argument('--logic', action='store_true')
    parser.add_argument('--resolution', nargs='+', choices=['1280x720', '1920x1080'], default=['1280x720'])
    parser.add_argument('--record-motion', action='store_true', help='真实时间至少0.1秒采一帧，不编码')
    parser.add_argument('--class-scan', choices=['auto', 'always', 'never'], default='auto')
    parser.add_argument('--timeout', type=int, default=240)
    parser.add_argument('--scan-timeout', type=int, default=120)
    parser.add_argument('--prepare-only', action='store_true', help='只检查隔离并备份/同步，不启动Godot')
    parser.add_argument('--self-test', action='store_true', help='仅执行不启动Godot的runner自测')
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.logic and args.record_motion:
        parser.error('连续帧必须真实渲染，不能与 --logic 同用')
    scenes = []
    for value in args.scene:
        if value in ['suite', 'all']:
            scenes += [SCENES['fate_tutorial_dialogue'], SCENES['weapon_hologram_ui']]
        elif value in SCENES:
            scenes.append(SCENES[value])
        else:
            path = value.removeprefix('res://').replace('\\', '/')
            if not path.startswith('tests/verification/') or not path.endswith('.tscn') or '..' in Path(path).parts:
                parser.error('场景必须是专项简称或 tests/verification/*.tscn')
            scenes.append('res://' + path)
    root = wp.work_path('verification/fate_tutorial/' + time.strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:6] + '/result.json').parent
    report = {'passed': False, 'executed': False, 'runs': [], 'root': str(root), 'logic': args.logic}
    def save():
        (root / 'result.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    save()
    print('JSON路径=' + str(root / 'result.json'), flush=True)
    try:
        project, prior_import = validate_copy(args.reuse_isolated_project)
        with own_copy_lock(project):
            rows = synchronize(project, root, scenes)
            env = isolated_env(root / 'scan_user')
            report.update(project=str(project), synchronization=rows, prior_import_evidence=prior_import,
                          isolation={'before_autoload': True, 'custom_user_dir': 'weapon_hologram_qa',
                                     'per_scene_user_roots': True, 'full_import': False})
            missing = missing_classes(project, rows)
            report['missing_classes_before_scan'] = missing
            save()
            if args.prepare_only:
                report['prepared'] = True
                save()
                return 0
            if args.class_scan == 'always' or (missing and args.class_scan == 'auto'):
                scan, _ = execute([args.godot, '--headless', '--editor', '--quit', '--path', str(project),
                                   '--audio-driver', 'Dummy'], env, root, 'class_scan', args.scan_timeout)
                report['class_scan'] = scan
                save()
                if not scan['passed'] or missing_classes(project, rows):
                    raise ValueError('副本短扫描失败或仍缺global class；不运行专项，不回退主工程')
            elif missing:
                raise ValueError('副本缺global class且禁止扫描：' + ', '.join(missing))
            for scene in dict.fromkeys(scenes):
                for resolution in dict.fromkeys(args.resolution):
                    directory = root / (Path(scene).stem + '_' + ('logic' if args.logic else resolution))
                    directory.mkdir()
                    output = directory / 'output'
                    output.mkdir()
                    run_env = isolated_env(directory / 'isolated_user')
                    run_env['SHELLSTORM_VERIFICATION_OUTPUT'] = str(output)
                    command = [args.godot, '--path', str(project), '--audio-driver', 'Dummy', '--resolution', resolution]
                    command += ['--headless'] if args.logic else ['--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan']
                    command.append(scene)
                    recording = args.record_motion and scene == SCENES['fate_tutorial_dialogue']
                    if recording:
                        command += ['--', '--record-motion']
                    run, text = execute(command, run_env, directory, 'scene', args.timeout, scene)
                    marker = Path(scene).stem.removeprefix('verify_').upper() + '_RESULT '
                    reports = [line.split(marker, 1)[1] for line in text.splitlines() if marker in line]
                    payload = json.loads(reports[-1]) if reports else {}
                    if scene == SCENES['narrative_timeline']:
                        payload = {'completed': 'verify_narrative_timeline_OK checks=' in text,
                                   'passed': 'verify_narrative_timeline_OK checks=' in text}
                    run.update(scene=scene, resolution=resolution, report=payload, output=str(output),
                               images=[str(p) for p in sorted(output.glob('*.png'))])
                    run['passed'] = bool(run['passed'] and payload.get('completed') and payload.get('passed')
                                         and (args.logic or run['renderer_verified']))
                    if not args.logic and scene == SCENES['fate_tutorial_dialogue']:
                        run['passed'] = bool(run['passed'] and all((output / (name + '.png')).exists() for name in CAPTURES))
                    frames = sorted((output / 'motion').glob('frame_*.png'))
                    run.update(video_frame_count=len(frames), motion_interval_seconds=0.1 if recording else None,
                               motion_frame_pattern=str(output / 'motion/frame_%05d.png') if recording else None)
                    if recording:
                        motion = payload.get('motion', {})
                        run['passed'] = bool(run['passed'] and frames and motion.get('video_frames') == len(frames)
                                             and not motion.get('recording', True))
                    report['runs'].append(run)
                    report['executed'] = True
                    save()
                    print(f"场景={scene} 退出={run['exit_code']} 错误={len(run['engine_errors'])} 通过={run['passed']}", flush=True)
                    if args.logic:
                        break
            report['passed'] = bool(report['runs'] and all(run['passed'] for run in report['runs']))
    except Exception as exc:
        report['failure'] = str(exc)
        print('RUNNER_FAIL ' + str(exc), file=sys.stderr, flush=True)
    finally:
        save()
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
