"""按用户授权恢复塔2原始几何；不运行Godot，不重建任何场景。"""
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess

ROOT = Path('I:/工作项目/shellstrom2/ShellStorm2')
BASE = ROOT / 'assets/art/environments/open_world'
COMP = BASE / 'components/tower_02'
RUN = BASE / 'runtime/tower_02'
OLD = ROOT / '_scratch/tower02_v003_stable_backup_before_v004_20261006_184418'
BACK = ROOT / '_scratch/towers_restore_full_20261007/tower02_before'
REPORT = ROOT / 'outputs/towers_restore_full_20261007/tower02_restore.json'
EXPORT = BASE / 'source/tower_02/export/v003/export_manifest.json'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def rel(path):
    return path.relative_to(ROOT).as_posix()


def encode(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def git_blob(commit, path):
    return subprocess.check_output(['git', '-C', str(ROOT), 'show', commit + ':' + rel(path)])


def glb_stats(data):
    magic, version, length = struct.unpack_from('<III', data)
    assert magic == 0x46546C67 and version == 2 and length == len(data)
    chunks = {}
    offset = 12
    while offset < length:
        size, kind = struct.unpack_from('<II', data, offset)
        chunks[kind] = data[offset + 8:offset + 8 + size]
        offset += 8 + size
    assert offset == length
    doc = json.loads(chunks[0x4E4F534A])
    binary = chunks[0x004E4942]
    assert not doc.get('images') and not doc.get('textures')
    # 当前全部导出件使用局部几何、无节点变换；不把局部bbox冒充世界bbox。
    for node in doc['nodes']:
        assert 'matrix' not in node
        assert node.get('translation', [0, 0, 0]) == [0, 0, 0]
        assert node.get('rotation', [0, 0, 0, 1]) == [0, 0, 0, 1]
        assert node.get('scale', [1, 1, 1]) == [1, 1, 1]
    lower, upper = [float('inf')] * 3, [float('-inf')] * 3
    primitives = []
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            assert primitive.get('mode', 4) == 4
            position = doc['accessors'][primitive['attributes']['POSITION']]
            assert position['type'] == 'VEC3' and position['componentType'] == 5126
            assert 'sparse' not in position
            view = doc['bufferViews'][position['bufferView']]
            assert view['buffer'] == 0
            start = view.get('byteOffset', 0) + position.get('byteOffset', 0)
            stride = view.get('byteStride', 12)
            assert start + (position['count'] - 1) * stride + 12 <= len(binary)
            for i in range(position['count']):
                vertex = struct.unpack_from('<3f', binary, start + i * stride)
                lower = [min(lower[a], vertex[a]) for a in range(3)]
                upper = [max(upper[a], vertex[a]) for a in range(3)]
            index = doc['accessors'][primitive['indices']] if 'indices' in primitive else position
            assert index['count'] % 3 == 0
            primitives.append({'accessor_count': index['count'], 'triangles': index['count'] // 3})
    return {'triangles': sum(p['triangles'] for p in primitives), 'primitives': primitives,
            'bbox_godot_local': [lower, upper], 'node_count': len(doc['nodes'])}


def without_metadata(data, only_allowed=False):
    pattern = rb'^metadata/(?:asset_version|source_blend) = .*\r?\n' if only_allowed else rb'^metadata/[^\r\n]*\r?\n'
    return re.sub(pattern, b'', data, flags=re.M)


def atomic_write(path, data):
    temp = path.with_name(path.name + '.tower02_restore_tmp')
    assert not temp.exists()
    try:
        temp.write_bytes(data)
        os.replace(temp, path)
    finally:
        if temp.exists():
            temp.unlink()


def main():
    assert not BACK.exists(), '已有备份：拒绝覆盖或重复应用'
    assert not REPORT.exists(), '已有恢复报告：拒绝覆盖'
    commit = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    original = json.loads(EXPORT.read_bytes())
    assert original == json.loads(git_blob(commit, EXPORT))
    assert original['version'] == 'v003' and len(original['records']) == 92
    assert sha(ROOT / original['source']) == original['source_sha256']
    assert sha(ROOT / original['derived']) == original['derived_sha256']
    stable_files = sorted(p for folder in [COMP, RUN] for p in folder.rglob('*') if p.is_file())
    stable_before = {rel(p): sha(p) for p in stable_files}
    scenes = sorted(RUN.rglob('*.tscn'))
    manifests = sorted(RUN.rglob('*.json'))
    assert len(scenes) == 96 and len(manifests) == 93
    assert len(list(COMP.rglob('*.glb'))) == 92
    assert {rel(p) for p in COMP.rglob('*.glb')} == {x['glb'] for x in original['records']}
    protected = sorted(p for p in (BASE / 'source/tower_02').rglob('*') if p.is_file())
    protected += sorted(p for p in (BASE / 'components/tower_02_v004').rglob('*') if p.is_file())
    protected += sorted(p for p in (BASE / 'runtime/cross_tower_route').rglob('*') if p.is_file())
    protected += [ROOT / 'tools/asset_pipeline/promote_tower02_v004_stable.py',
                  ROOT / 'tools/asset_pipeline/verify_tower02_v004_stable_import.py']
    protected_before = {rel(p): sha(p) for p in protected}
    planned = {}
    components = []
    for record in original['records']:
        target = ROOT / record['glb']
        backup_original = OLD / target.relative_to(BASE)
        data = git_blob(commit, target)
        assert digest(data) == sha(backup_original) == record['glb_sha256']
        stats = glb_stats(data)
        before_stats = glb_stats(target.read_bytes())
        assert stats['triangles'] == record['triangle_count']
        assert before_stats['triangles'] >= 0
        delta = [[stats['bbox_godot_local'][i][a] - before_stats['bbox_godot_local'][i][a]
                  for a in range(3)] for i in range(2)]
        components.append({'asset_id': record['asset_id'], 'slug': record['slug'],
                           'stable_glb': record['glb'], 'prefab': record['prefab'],
                           'version': original['version'], 'original_sha256': digest(data),
                           'git_commit': commit, 'backup_original': rel(backup_original),
                           'before_sha256': stable_before[rel(target)], 'before_stats': before_stats,
                           'restored_stats': stats, 'bbox_delta_min_max': delta,
                           'bbox_changed': any(v != 0 for row in delta for v in row)})
        planned[target] = data
    assert sum(c['restored_stats']['triangles'] for c in components) == 406088
    assert sum(c['before_stats']['triangles'] for c in components) == 80952
    scene_checks = []
    for scene in scenes:
        data = scene.read_bytes()
        old_data = (OLD / scene.relative_to(BASE)).read_bytes()
        for key in [b'asset_version', b'source_blend']:
            pattern = rb'(?m)^metadata/' + key + rb' = "([^"\r\n]*)"'
            matches = list(re.finditer(pattern, data))
            old_matches = list(re.finditer(pattern, old_data))
            assert len(matches) == len(old_matches) == 1, scene
            expected = original['version'].encode() if key == b'asset_version' else original['source'].encode('utf-8')
            assert old_matches[0].group(1) == expected
            data = re.sub(pattern, lambda match: b'metadata/' + key + b' = "' + expected + b'"', data)
        before = scene.read_bytes()
        assert without_metadata(before) == without_metadata(data)
        assert without_metadata(before, True) == without_metadata(data, True)
        scene_checks.append({'path': rel(scene), 'before_sha256': digest(before),
                             'after_sha256': digest(data),
                             'metadata_stripped_sha256_before': digest(without_metadata(before)),
                             'metadata_stripped_sha256_after': digest(without_metadata(data)),
                             'non_source_version_bytes_sha256': digest(without_metadata(data, True)),
                             'changed': before != data})
        planned[scene] = data
    by_slug = {c['slug']: c for c in components}
    for path in manifests:
        current = json.loads(path.read_bytes())
        result = copy.deepcopy(current)
        result.setdefault('restore_history', []).append({'event': 'before_full_detail_restore_20261007',
                                                        'manifest_before': copy.deepcopy(current)})
        # 优化和既有验收仍留在历史快照，但不再冒充当前活动几何/验收。
        for key in ['optimization', 'runtime_integration', 'promoted_components',
                    'runtime_verification', 'verification', 'godot_reimport_completed',
                    'backup_before_promotion']:
            result.pop(key, None)
        result.update({'version': original['version'], 'source': original['source'],
                       'source_blend': original['source'], 'source_sha256': original['source_sha256'],
                       'source_original': original['source'], 'source_original_sha256': original['source_sha256'],
                       'export_source': original['derived'], 'export_source_sha256': original['derived_sha256'],
                       'export_manifest': rel(EXPORT), 'active_geometry': 'full_detail_unreduced',
                       'runtime_integrated': False, 'runtime_verified': False, 'godot_reimport_pending': True,
                       'ledger_status': 'pending', 'ledger_sync_pending': True,
                       'restore_backup': rel(BACK),
                       'runtime_integration': {'stable_component_paths_preserved': True,
                                               'stable_packedscene_paths_preserved': True,
                                               'formal_layout_rewritten': False,
                                               'collision_or_gameplay_changed': False,
                                               'runtime_verified': False, 'godot_reimport_pending': True}})
        if path.parent == RUN:
            result['component_count'] = 92
            result['triangle_count'] = 406088
            result['actual_glb_triangles'] = 406088
            result['source_blend_triangles'] = 406088
            result['components'] = [{'asset_id': c['asset_id'], 'slug': c['slug'], 'version': c['version'],
                                     'glb': c['stable_glb'], 'glb_sha256': c['original_sha256'],
                                     'triangle_count': c['restored_stats']['triangles'], 'prefab': c['prefab'],
                                     'bbox_godot_local': c['restored_stats']['bbox_godot_local']} for c in components]
        else:
            component = by_slug[path.parent.name]
            result.update({'glb': component['stable_glb'], 'glb_sha256': component['original_sha256'],
                           'triangle_count': component['restored_stats']['triangles'],
                           'actual_glb_triangles': component['restored_stats']['triangles'],
                           'bbox_godot_local': component['restored_stats']['bbox_godot_local'],
                           'exported': True, 'prefab': component['prefab']})
        planned[path] = encode(result)
    changes = {p: data for p, data in planned.items() if sha(p) != digest(data)}
    assert set(rel(p) for p in changes).issubset(stable_before)
    # 全预检结束后，完整复制当前稳定目录，包括所有导入侧文件。
    BACK.mkdir(parents=True, exist_ok=False)
    (BACK / '.gdignore').write_bytes(b'')
    for folder in [COMP, RUN]:
        shutil.copytree(folder, BACK / folder.relative_to(BASE), copy_function=shutil.copy2)
    assert {rel(p): sha(BACK / p.relative_to(BASE)) for p in stable_files} == stable_before
    (BACK / 'backup_manifest.json').write_bytes(encode({'files': stable_before, 'protected': protected_before}))
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    written = []
    try:
        assert all(sha(ROOT / p) == value for p, value in stable_before.items())
        assert all(sha(ROOT / p) == value for p, value in protected_before.items())
        for path, data in changes.items():
            assert sha(path) == stable_before[rel(path)]
            written.append(path)
            atomic_write(path, data)
        for path, data in planned.items():
            assert sha(path) == digest(data)
        for path, expected in stable_before.items():
            if ROOT / path not in changes:
                assert sha(ROOT / path) == expected
        assert all(sha(ROOT / path) == value for path, value in protected_before.items())
        for component in components:
            data = (ROOT / component['stable_glb']).read_bytes()
            assert digest(data) == component['original_sha256']
            assert glb_stats(data) == component['restored_stats']
        for check in scene_checks:
            assert digest(without_metadata((ROOT / check['path']).read_bytes())) == check['metadata_stripped_sha256_before']
        file_changes = [{'path': rel(p), 'before_sha256': stable_before[rel(p)],
                         'after_sha256': sha(p)} for p in changes]
        report = {'passed': True, 'static_restore_verified': True, 'asset_id': original['asset_id'],
                  'restored_version': original['version'], 'source': original['source'],
                  'source_sha256': original['source_sha256'], 'export_source': original['derived'],
                  'export_source_sha256': original['derived_sha256'], 'export_manifest': rel(EXPORT),
                  'export_manifest_sha256': sha(EXPORT), 'git_commit': commit,
                  'original_backup': rel(OLD), 'backup_before_restore': rel(BACK),
                  'components_count': 92, 'scenes_count': 96, 'scene_metadata_changed': sum(c['changed'] for c in scene_checks),
                  'runtime_manifests_count': 93, 'actual_triangles_before': 80952,
                  'actual_triangles_restored': 406088, 'source_blend_triangles': 406088,
                  'active_geometry': 'full_detail_unreduced', 'runtime_verified': False,
                  'godot_reimport_pending': True, 'ledger_status': 'pending', 'xlsx_or_baseline_written': False,
                  'godot_executed': False, 'collision_modified': False, 'formal_layout_rewritten': False,
                  'original_sha_matches_git_backup_manifest': 92,
                  'bbox_changed_components': sum(c['bbox_changed'] for c in components),
                  'bbox_interface_risk': '恢复完整细节使包络可能扩展，现有碰撞与挂点未修改；需主助手重导入并核验视觉净空/接缝/吊车路线。',
                  'components': components, 'scene_protection_hashes': scene_checks,
                  'unchanged_stable_files': {p: h for p, h in stable_before.items() if ROOT / p not in changes},
                  'protected_files_sha256_before': protected_before, 'protected_files_sha256_after': protected_before,
                  'protected_hashes_verified': True, 'files_changed_count': len(file_changes), 'files_changed': file_changes}
        atomic_write(REPORT, encode(report))
        print(json.dumps({k: report[k] for k in ['passed', 'restored_version', 'actual_triangles_restored',
                                               'components_count', 'scenes_count', 'scene_metadata_changed',
                                               'runtime_manifests_count', 'bbox_changed_components', 'files_changed_count']}, ensure_ascii=False))
    except BaseException:
        for path in reversed(written):
            atomic_write(path, (BACK / path.relative_to(BASE)).read_bytes())
        assert all(sha(path) == stable_before[rel(path)] for path in written)
        raise


if __name__ == '__main__':
    main()
