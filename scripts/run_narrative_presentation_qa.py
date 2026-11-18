"""本轮剧情 A/B、贩卖机、主线集成和 Boss 真渲染的隔离 QA runner。"""
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
    'narrative_timeline': 'res://tests/verification/verify_narrative_timeline.tscn',
    'run_vending_tutorial': 'res://tests/verification/verify_run_vending_tutorial.tscn',
    'main_story_integration': 'res://tests/verification/verify_main_story_integration.tscn',
    'main_story_performance': 'res://tests/verification/verify_main_story_performance.tscn',
    'capture_main_story_chapter': 'res://tests/verification/capture_main_story_chapter.tscn',
    'story_safe_beacon': 'res://tests/verification/verify_story_safe_beacon.tscn',
}
ERROR = re.compile(r'SCRIPT ERROR:|(?:^|\n)\s*ERROR:|Parse Error:|Compile Error:|Failed to load', re.I)
KNOWN_TIMELINE = re.compile(r'^\s*ERROR: \[NarrativeDirector\] cue『player\.teleport』执行失败.*$')
EXPLICIT_FILES = [
    'scenes/TowerDescent3D.tscn', 'scenes/ExpeditionLevel01_3D.tscn', 'scenes/Dungeon3D.tscn',
    'scenes/BaseNpc3D.tscn', 'src/world3d/TowerDescent3D.gd', 'src/world3d/Dungeon3D.gd',
    'src/world3d/DungeonRoom3D.gd', 'src/world3d/ExtractionBeacon3D.gd',
    'src/world3d/ServiceStation3D.gd', 'src/narrative/MainStoryChapter3D.gd',
    'src/narrative/MainStoryProgress.gd', 'src/narrative/RunVendingTutorial3D.gd',
    'src/narrative/NarrativeDirector3D.gd', 'src/narrative/NarrativeAdapter3D.gd',
    'src/enemy3d/Enemy3D.gd', 'src/enemy3d/MonitorBossCombat.gd',
    'src/enemy3d/MonitorBossPresentation.gd', 'src/enemy3d/BossContentCatalog.gd',
    'src/map/LevelPlanLoader.gd', 'src/map/FloorPlanGenerator.gd',
    'assets/art/props/dungeon_3d/prp_extraction_safe_beacon_root_top3d.tscn',
    'assets/art/props/dungeon_3d/components/prp_extraction_safe_beacon/prp_extraction_safe_beacon_visual_top3d.glb',
    'assets/art/props/dungeon_3d/prp_extraction_beacon_root_top3d.tscn',
    'assets/art/props/main_story/runtime/rare_earth_key.tscn',
    'assets/art/props/main_story/runtime/main_story_pedestal.tscn',
    'assets/art/props/main_story/runtime/key_insert/prp_base99_main_story_key_insert_root_top3d.tscn',
    'assets/art/props/main_story/components/key_insert/prp_base99_main_story_key_insert_visual_top3d.glb',
    'assets/art/enemies/bosses/enm_boss_monitor002/runtime/enm_boss_monitor002/enm_boss_monitor002_root_top3d.tscn',
    'assets/art/enemies/bosses/enm_boss_monitor002/components/enm_boss_monitor002/enm_boss_monitor002_visual_top3d.glb',
    'assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01/f00_boss_room_02_static_layout.tscn',
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_copy(project):
    project = project.resolve()
    root = wp.PROJECT_ROOT.resolve()
    if project == root or project.is_relative_to(root):
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
    files = {Path(path) for path in EXPLICIT_FILES}
    files.update(Path(p).relative_to(wp.PROJECT_ROOT) for p in wp.PROJECT_ROOT.glob('src/narrative/*.gd'))
    files.update(Path(p).relative_to(wp.PROJECT_ROOT) for p in wp.PROJECT_ROOT.glob('src/ui/dialogue/*.gd'))
    files.update(Path(p).relative_to(wp.PROJECT_ROOT) for p in wp.PROJECT_ROOT.glob('data/narrative/*.json'))
    files.update(Path(p).relative_to(wp.PROJECT_ROOT) for p in (wp.PROJECT_ROOT / 'data/level_plans/expedition_01').rglob('*') if p.is_file())
    project_config = (wp.PROJECT_ROOT / 'project.godot').read_text(encoding='utf-8')
    files.update(Path(ref) for ref in re.findall(r'\*?res://([^"\s]+\.gd)', project_config))
    for scene in scenes:
        path = Path(scene.removeprefix('res://'))
        files.update([path, path.with_suffix('.gd')])
    pending = list(files)
    while pending:
        relative = pending.pop()
        source = wp.PROJECT_ROOT / relative
        if not source.is_file():
            raise ValueError('缺少专项依赖：' + str(source))
        if source.suffix.lower() not in {'.gd', '.tscn', '.tres', '.json', '.cfg'}:
            continue
        text = source.read_text(encoding='utf-8', errors='replace')
        for reference in re.findall(r'res://([^"\s\)]+)', text):
            dependency = Path(reference)
            if '%' in dependency.as_posix() or '{' in dependency.as_posix() or '}' in dependency.as_posix():
                continue
            if not (wp.PROJECT_ROOT / dependency).is_file():
                continue
            if dependency.suffix.lower() in {'.gd', '.tscn', '.tres', '.res', '.png', '.webp', '.jpg', '.jpeg', '.glb', '.wav', '.ogg', '.ttf', '.gdshader', '.json'} and dependency not in files:
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
    copied_relative = []
    for relative in required_files(scenes):
        source, target = wp.PROJECT_ROOT / relative, project / relative
        old_hash = digest(target) if target.exists() else None
        new_hash = digest(source)
        row = {'path': relative.as_posix(), 'source_sha256': new_hash, 'previous_sha256': old_hash, 'changed': old_hash != new_hash}
        if row['changed']:
            if target.exists():
                backup = root / 'copy_before_sync' / relative
                backup.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, backup)
                row['backup'] = str(backup)
            target.parent.mkdir(parents=True, exist_ok=True)
            staging = target.with_name(target.name + '.qa_' + uuid.uuid4().hex)
            shutil.copy2(source, staging)
            os.replace(staging, target)
        copied_relative.append(relative)
        rows.append(row)

    # .import 只描述导入结果，正式工程副本还需要对应的 Godot 导入缓存。
    # 不重导整份工程：只按本次同步文件的 path=... 精确补齐 .godot/imported 下的
    # PackedScene/材质缓存。否则真实场景可能把“缺缓存”误报成业务脚本失败。
    # GLB 外置纹理路径藏在二进制文件里，文本依赖扫描不一定发现。
    # 同步同目录纹理及其 .import，避免既有资产缺依赖污染本轮业务验收。
    existing = set(copied_relative)
    for relative in list(copied_relative):
        if relative.suffix.lower() != '.glb':
            continue
        for sibling in (wp.PROJECT_ROOT / relative).parent.iterdir():
            if not sibling.is_file() or sibling.suffix.lower() not in {'.jpg', '.jpeg', '.png', '.webp'}:
                continue
            sibling_relative = sibling.relative_to(wp.PROJECT_ROOT)
            sidecar = sibling.with_name(sibling.name + '.import')
            extras = [sibling_relative]
            if sidecar.is_file():
                extras.append(sidecar.relative_to(wp.PROJECT_ROOT))
            for extra in extras:
                if extra in existing:
                    continue
                target = project / extra
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(wp.PROJECT_ROOT / extra, target)
                existing.add(extra)
                copied_relative.append(extra)
                rows.append({'path': extra.as_posix(), 'source_sha256': digest(wp.PROJECT_ROOT / extra), 'previous_sha256': None, 'changed': True, 'reason': 'glb_external_texture_dependency'})

    # GLB 还可能引用跨目录的外置贴图。解析其 JSON chunk 中的相对 URI，
    # 只同步工程根内的图片及 .import；不运行导入器、不接受越界路径。
    existing = set(copied_relative)
    uri_pattern = re.compile(rb'"uri"\s*:\s*"([^"\r\n]+\.(?:png|jpg|jpeg|webp))"', re.I)
    for relative in list(copied_relative):
        if relative.suffix.lower() != '.glb':
            continue
        binary = (wp.PROJECT_ROOT / relative).read_bytes()
        for match in uri_pattern.finditer(binary):
            uri = match.group(1).decode('utf-8', 'replace').replace('\\\\', '/')
            source_texture = ((wp.PROJECT_ROOT / relative).parent / Path(uri)).resolve()
            if not source_texture.is_file() or not source_texture.is_relative_to(wp.PROJECT_ROOT):
                continue
            texture_relative = source_texture.relative_to(wp.PROJECT_ROOT)
            sidecar = source_texture.with_name(source_texture.name + '.import')
            extras = [texture_relative]
            if sidecar.is_file():
                extras.append(sidecar.relative_to(wp.PROJECT_ROOT))
            for extra in extras:
                if extra in existing:
                    continue
                target = project / extra
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(wp.PROJECT_ROOT / extra, target)
                existing.add(extra)
                copied_relative.append(extra)
                rows.append({'path': extra.as_posix(), 'source_sha256': digest(wp.PROJECT_ROOT / extra), 'previous_sha256': None, 'changed': True, 'reason': 'glb_uri_texture_dependency'})

    imported_root = project / '.godot/imported'
    imported_root.mkdir(parents=True, exist_ok=True)
    cache_rows = []
    for relative in copied_relative:
        if relative.suffix != '.import':
            continue
        import_file = project / relative
        import_text = import_file.read_text(encoding='utf-8', errors='replace')
        cache_values = re.findall(r'^path(?:\.[A-Za-z0-9_]+)?="res://([^"\r\n]+)"', import_text, re.M)
        for cache_value in cache_values:
            cache_path = Path(cache_value)
            cache_relative = cache_path if cache_path.parts[:2] == ('.godot', 'imported') else Path('.godot/imported') / cache_path
            source_cache, target_cache = wp.PROJECT_ROOT / cache_relative, project / cache_relative
            if not source_cache.is_file():
                cache_rows.append({'path': cache_relative.as_posix(), 'copied': False, 'reason': 'source_cache_missing'})
                continue
            target_cache.parent.mkdir(parents=True, exist_ok=True)
            old_hash = digest(target_cache) if target_cache.exists() else None
            new_hash = digest(source_cache)
            if old_hash != new_hash:
                shutil.copy2(source_cache, target_cache)
            cache_rows.append({'path': cache_relative.as_posix(), 'copied': old_hash != new_hash, 'source_sha256': new_hash})
    (root / 'sync_manifest.json').write_text(json.dumps({'files': rows, 'imported_cache': cache_rows}, ensure_ascii=False, indent=2), encoding='utf-8')
    return rows


@contextmanager
def own_copy_lock(project):
    lock = project.parent / 'narrative_presentation_qa.lock'
    descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    try:
        os.write(descriptor, str(os.getpid()).encode('ascii'))
        os.close(descriptor)
        yield
    finally:
        if lock.exists():
            lock.unlink()


def isolated_env(root, scene):
    env = os.environ.copy()
    for key in ['APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'TEMP', 'TMP', 'TMPDIR']:
        path = root / key.lower()
        path.mkdir(parents=True, exist_ok=True)
        env[key] = str(path)
    env['SHELLSTORM_MAIN_STORY_ISOLATED'] = '1'
    env['SHELLSTORM_RUN_VENDING_TUTORIAL_ISOLATED'] = '1'
    env['NARRATIVE_PRESENTATION_QA_ISOLATED'] = '1'
    env['SHELLSTORM_VERIFICATION_OUTPUT'] = str(root / 'output')
    if scene == SCENES['main_story_integration']:
        env['SHELLSTORM_QA_CUSTOM_USER_DIR'] = 'main_story_integration'
    elif scene in [SCENES['main_story_performance'], SCENES['capture_main_story_chapter']]:
        env['SHELLSTORM_QA_CUSTOM_USER_DIR'] = 'main_story_performance'
    elif scene == SCENES['run_vending_tutorial']:
        env['SHELLSTORM_QA_CUSTOM_USER_DIR'] = 'run_vending_tutorial_qa'
    else:
        env['SHELLSTORM_QA_CUSTOM_USER_DIR'] = 'narrative_timeline_qa'
    return env


def set_custom_user_dir(project, name):
    config = (project / 'project.godot').read_text(encoding='utf-8')
    config = re.sub(r'^config/use_custom_user_dir=.*\n?', '', config, flags=re.M)
    config = re.sub(r'^config/custom_user_dir_name=.*\n?', '', config, flags=re.M)
    if '[application]' not in config:
        raise ValueError('副本 project.godot 缺少 [application]')
    config = config.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="%s"' % name, 1)
    (project / 'project.godot').write_text(config, encoding='utf-8')


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
        process = subprocess.Popen(command, env=env, cwd=directory, stdout=stream, stderr=subprocess.STDOUT, start_new_session=os.name != 'nt')
        print(f'{label} 自有PID={process.pid} 日志={console}', flush=True)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            if os.name == 'nt':
                subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True, check=False)
            else:
                os.killpg(process.pid, signal.SIGKILL)
            code = process.wait()
        except BaseException:
            if process.poll() is None:
                if os.name == 'nt':
                    subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True, check=False)
                else:
                    os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise
    text = console.read_text(encoding='utf-8', errors='replace')
    merged = text + '\n' + (engine.read_text(encoding='utf-8', errors='replace') if engine.exists() else '')
    errors, known = classify_errors(merged, scene)
    return {
        'command': command, 'pid': process.pid, 'exit_code': code, 'timed_out': timed_out,
        'elapsed_seconds': round(time.monotonic() - started, 3), 'console': str(console), 'engine_log': str(engine),
        'engine_errors': errors, 'known_expected_errors': known,
        'expected_failure_markers': [line for line in merged.splitlines() if 'MAIN_STORY_EXPECTED_FAILURE_' in line],
        'renderer_verified': bool(re.search(r'Forward\+', merged) and re.search(r'Vulkan', merged)),
        'passed': code == 0 and not timed_out and not errors,
    }, text


def scene_report(scene, text):
    if scene == SCENES['narrative_timeline']:
        marker = 'verify_narrative_timeline_OK checks='
        return {'completed': marker in text, 'passed': marker in text}
    if scene == SCENES['story_safe_beacon']:
        marker = 'STORY_SAFE_BEACON_REPORT '
        rows = [line.split(marker, 1)[1] for line in text.splitlines() if marker in line]
        if rows:
            try:
                payload = json.loads(rows[-1])
                # 单元测试只对自身 scope 签字；正式主线链由 integration 独立签字。
                payload['passed'] = bool(payload.get('completed', False) and payload.get('passed', False) and not payload.get('failures', []))
                return payload
            except json.JSONDecodeError:
                return {}
        return {'completed': False, 'passed': False, 'failures': ['缺少 STORY_SAFE_BEACON_REPORT']}
    markers = {
        SCENES['run_vending_tutorial']: 'RUN_VENDING_TUTORIAL_RESULT ',
        SCENES['main_story_integration']: 'MAIN_STORY_INTEGRATION_REPORT ',
    }
    marker = markers.get(scene)
    if marker:
        rows = [line.split(marker, 1)[1] for line in text.splitlines() if marker in line]
        if rows:
            try:
                payload = json.loads(rows[-1])
                if scene == SCENES['main_story_integration']:
                    payload['passed'] = not payload.get('failures', [])
                return payload
            except json.JSONDecodeError:
                return {}
    if scene == SCENES['main_story_performance']:
        rows = [line for line in text.splitlines() if 'MAIN_STORY_PERFORMANCE_RESULT ' in line]
        return {'completed': bool(rows), 'passed': bool(rows) and 'failures=0' in rows[-1]}
    if scene == SCENES['capture_main_story_chapter']:
        rows = [line for line in text.splitlines() if 'MAIN_STORY_VISUAL_RESULT ' in line]
        return {'completed': bool(rows), 'passed': bool(rows) and re.search(r'failures=(?:0|\[\])(?:\s|$)', rows[-1]) is not None}
    return {}


def self_test():
    assert classify_errors('SCRIPT ERROR: bad\nParse Error: bad', '')[0]
    expected = 'ERROR: [NarrativeDirector] cue『player.teleport』执行失败（degraded=false）：缺参数'
    assert classify_errors(expected, SCENES['narrative_timeline']) == ([], [expected])
    assert classify_errors(expected, SCENES['main_story_integration'])[0] == [expected]
    assert len(required_files([SCENES['main_story_integration']])) > 20
    print('RUNNER_SELF_TEST_OK：错误分类、隔离入口、主线/贩卖机依赖存在性；未启动Godot', flush=True)
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', GODOT))
    parser.add_argument('--reuse-isolated-project', type=Path, default=DEFAULT_COPY)
    parser.add_argument('--scene', nargs='+', default=['suite'], help='专项简称、suite 或 tests/verification/*.tscn')
    parser.add_argument('--logic', action='store_true', help='只运行逻辑 headless；capture_main_story_chapter 不在此模式运行')
    parser.add_argument('--resolution', nargs='+', choices=['1280x720', '1920x1080'], default=['1280x720'])
    parser.add_argument('--chapter', choices=['031', '032', '033'], help='capture_main_story_chapter 的真实章节')
    parser.add_argument('--timeout', type=int, default=600)
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    scenes = []
    for value in args.scene:
        if value in ['suite', 'all']:
            scenes += [SCENES['narrative_timeline'], SCENES['run_vending_tutorial'], SCENES['main_story_integration'], SCENES['main_story_performance']]
        elif value in SCENES:
            scenes.append(SCENES[value])
        else:
            path = value.removeprefix('res://').replace('\\', '/')
            if not path.startswith('tests/verification/') or not path.endswith('.tscn') or '..' in Path(path).parts:
                parser.error('场景必须是专项简称或 tests/verification/*.tscn')
            scenes.append('res://' + path)
    if args.chapter and SCENES['capture_main_story_chapter'] not in scenes:
        scenes.append(SCENES['capture_main_story_chapter'])
    if SCENES['capture_main_story_chapter'] in scenes and not args.chapter:
        parser.error('capture_main_story_chapter 必须指定 --chapter 031/032/033')
    if args.logic and SCENES['capture_main_story_chapter'] in scenes:
        parser.error('capture_main_story_chapter 需要真实 Forward+，不能与 --logic 同用')
    root = wp.work_path('verification/narrative_presentation/' + time.strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:6])
    root.mkdir(parents=True, exist_ok=True)
    report_path = root / 'result.json'
    report = {'passed': False, 'executed': False, 'root': str(root), 'logic': args.logic, 'chapter': args.chapter, 'runs': []}
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print('JSON路径=' + str(report_path), flush=True)
    original_project_config = None
    try:
        project, prior_import = validate_copy(args.reuse_isolated_project)
        with own_copy_lock(project):
            original_project_config = project / 'project.godot'
            original_bytes = original_project_config.read_bytes()
            rows = synchronize(project, root, scenes)
            report.update(project=str(project), synchronization=rows, prior_import_evidence=prior_import,
                          isolation={'before_autoload': True, 'independent_cache': True, 'full_import': False,
                                     'custom_user_dirs': ['main_story_integration', 'main_story_performance', 'run_vending_tutorial_qa']})
            report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
            if args.prepare_only:
                report.update(prepared=True, passed=True)
                report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
                return 0
            for scene in dict.fromkeys(scenes):
                if args.logic and scene == SCENES['capture_main_story_chapter']:
                    continue
                resolutions = ['1280x720'] if args.logic else list(dict.fromkeys(args.resolution))
                if scene == SCENES['main_story_integration'] or scene == SCENES['main_story_performance'] or scene == SCENES['narrative_timeline']:
                    resolutions = ['1280x720']
                for resolution in resolutions:
                    label = Path(scene).stem + '_' + ('logic' if args.logic else resolution)
                    directory = root / label
                    output = directory / 'output'
                    output.mkdir(parents=True, exist_ok=True)
                    set_custom_user_dir(project, isolated_env(directory, scene)['SHELLSTORM_QA_CUSTOM_USER_DIR'])
                    env = isolated_env(directory, scene)
                    if scene == SCENES['capture_main_story_chapter']:
                        env['SHELLSTORM_MAIN_STORY_CHAPTER'] = args.chapter
                        env['SHELLSTORM_MAIN_STORY_CAPTURE_DIR'] = str(output)
                    command = [args.godot, '--path', str(project), '--audio-driver', 'Dummy', '--resolution', resolution]
                    command += ['--headless'] if args.logic else ['--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan']
                    command.append(scene)
                    run, text = execute(command, env, directory, 'scene', args.timeout, scene)
                    payload = scene_report(scene, text)
                    images = [str(p) for p in sorted(output.glob('*.png'))]
                    run.update(scene=scene, resolution=resolution, report=payload, output=str(output), images=images)
                    run['passed'] = bool(run['passed'] and payload.get('passed', False) and (args.logic or run['renderer_verified']))
                    if scene == SCENES['run_vending_tutorial'] and not args.logic:
                        run['passed'] = bool(run['passed'] and len(images) >= 3)
                    if scene == SCENES['capture_main_story_chapter'] and not args.logic:
                        run['passed'] = bool(run['passed'] and len(images) >= 30 and (output / 'frame_trace.json').exists() and (output / 'report.json').exists())
                    report['runs'].append(run)
                    report['executed'] = True
                    report['passed'] = bool(report['runs'] and all(item['passed'] for item in report['runs']))
                    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
                    print(f"场景={scene} 退出={run['exit_code']} 错误={len(run['engine_errors'])} 截图={len(images)} 通过={run['passed']}", flush=True)
                    if args.logic:
                        break
            report['passed'] = bool(report['runs'] and all(item['passed'] for item in report['runs']))
    except Exception as exc:
        report['failure'] = str(exc)
        print('RUNNER_FAIL ' + str(exc), file=sys.stderr, flush=True)
    finally:
        if original_project_config is not None and 'original_bytes' in locals():
            original_project_config.write_bytes(original_bytes)
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
