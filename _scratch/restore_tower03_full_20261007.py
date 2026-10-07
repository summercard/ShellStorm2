import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import tempfile
from datetime import datetime

ROOT = Path('I:/工作项目/shellstrom2/ShellStorm2')
ART = ROOT / 'assets/art/environments/open_world'
COMP = ART / 'components/tower_03'
RUN = ART / 'runtime/tower_03'
SOURCE = ART / 'source/tower_03'
ORIGINAL = ROOT / '_scratch/tower03_v001_stable_backup_before_v002_20261006_2045'
BACKUP = ROOT / '_scratch/towers_restore_full_20261007/tower03_before'
OUTPUT = ROOT / 'outputs/towers_restore_full_20261007/tower03_restore.json'
EXPORT = SOURCE / 'export/v001/export_manifest.json'
META = re.compile(rb'^metadata/(?:asset_version|source_blend) = [^\r\n]*(?:\r?\n|$)', re.M)
STATUS = dict(runtime_verified=False, runtime_integrated=False,
              godot_reimport_pending=True, ledger_pending=True,
              state='restored_unoptimized_v001_reimport_runtime_verification_ledger_pending')


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def filehash(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def rel(path):
    return path.relative_to(ROOT).as_posix()


def load(path):
    return json.loads(path.read_bytes().decode('utf-8-sig'))


def encoded(obj, prior=b''):
    data = (json.dumps(obj, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    if b'\r\n' in prior and b'\n' not in prior.replace(b'\r\n', b''):
        data = data.replace(b'\n', b'\r\n')
    if prior.startswith(b'\xef\xbb\xbf'):
        data = b'\xef\xbb\xbf' + data
    return data


def glb_stats(data):
    require(len(data) >= 20, 'GLB长度无效')
    magic, version, length = struct.unpack_from('<4sII', data)
    require((magic, version, length) == (b'glTF', 2, len(data)), 'GLB头无效')
    size, kind = struct.unpack_from('<II', data, 12)
    require(kind == 0x4e4f534a and size + 20 <= len(data), 'GLB JSON块无效')
    doc = json.loads(data[20:20 + size])
    total = primitives = 0
    require(not doc.get('images') and not doc.get('textures'), '原件含内嵌图片或纹理')
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            require(primitive.get('mode', 4) == 4, 'GLB不是TRIANGLES模式')
            accessor = doc['accessors'][primitive['indices']] if 'indices' in primitive else doc['accessors'][primitive['attributes']['POSITION']]
            count = accessor['count']
            require(count % 3 == 0, 'GLB三角面accessor数量不整除3')
            total += count // 3
            primitives += 1
    return dict(triangles=total, meshes=len(doc['meshes']), primitives=primitives)


def files(directory):
    return sorted(p for p in directory.rglob('*') if p.is_file())


def snapshot(paths):
    return {rel(p): filehash(p) for p in paths}


def verify_snapshot(expected):
    for name, h in expected.items():
        require((ROOT / name).is_file() and filehash(ROOT / name) == h, '受保护文件变化: ' + name)


def atomic(path, data):
    fd, name = tempfile.mkstemp(prefix='.' + path.name + '.tower03_restore_', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def preflight():
    if BACKUP.exists():
        require((BACKUP / 'backup_inventory.json').is_file() and (BACKUP / '.gdignore').is_file(), '已有备份不完整，禁止覆盖')
    require(not OUTPUT.exists(), '报告已存在，禁止覆盖: ' + str(OUTPUT))
    export = load(EXPORT)
    require(export['version'] == 'v001' and len(export['records']) == 217, '原导出清单版本/数量不符')
    require(export['source_sha256'] == '91b2f8f7d7ccfd483e76799e4b0a7573492b1741021eb3f7b34e5bfc24ec631e', '制作源登记hash不符')
    require(export['derived_sha256'] == 'a5eb1a4429fdb9ccbbf1de3a6ae11a4f2b1edcac3deb02878f455ecf99b3f744', '导出源登记hash不符')
    for key in ('source', 'derived'):
        require(filehash(ROOT / export[key]) == export[key + '_sha256'], '源hash不符: ' + key)
    root_manifest = RUN / 'asset_manifest.json'
    old_root = load(root_manifest)
    require(old_root['version'] == 'v005', '当前运行版本并非v005')
    require(len(old_root['records']) == 217, '当前根清单记录数不符')
    old_by_id = {r['asset_id']: r for r in old_root['records']}
    records = export['records']
    require(len({r['asset_id'] for r in records}) == len({r['slug'] for r in records}) == 217, '原件标识不唯一')
    expected_glbs = {ROOT / r['glb'] for r in records}
    expected_scenes = {ROOT / r['prefab'] for r in records} | {ROOT / old_root['prefab']}
    expected_manifests = {p.parent / 'asset_manifest.json' for p in expected_scenes}
    require(set(COMP.rglob('*.glb')) == expected_glbs, '稳定GLB路径集合不符')
    require(set(RUN.rglob('*.tscn')) == expected_scenes and len(expected_scenes) == 218, '场景路径集合不符')
    require(set(RUN.rglob('asset_manifest.json')) == expected_manifests and len(expected_manifests) == 218, '清单路径集合不符')
    require(len(list((ORIGINAL / 'components').rglob('*.glb'))) == 217, '原始备份GLB数不符')
    plan = {}
    details = []
    new_records = []
    totals = dict(before_triangles=0, restored_triangles=0, before_meshes=0, restored_meshes=0,
                  restored_primitives=0, glb_count=217, scene_count=218, manifest_count=218)
    for r in records:
        current = ROOT / r['glb']
        require(current.is_relative_to(COMP), 'GLB超出授权范围')
        prefab = ROOT / r['prefab']
        require(prefab.is_relative_to(RUN), 'Prefab超出授权范围')
        prior = old_by_id[r['asset_id']]
        require(prior['glb'] == r['glb'] and prior['prefab'] == r['prefab'], '稳定引用路径漂移')
        original = ORIGINAL / 'components' / r['slug'] / current.name
        data = original.read_bytes()
        require(digest(data) == r['glb_sha256'], '原件hash不符: ' + r['slug'])
        stats = glb_stats(data)
        require(stats['triangles'] == r['triangle_count'], '原清单三角面不符: ' + r['slug'])
        before = current.read_bytes()
        before_stats = glb_stats(before)
        require(digest(before) == prior['glb_sha256'] and before_stats['triangles'] == prior['triangle_count_glb'], '当前根记录不符: ' + r['slug'])
        manifest_path = prefab.parent / 'asset_manifest.json'
        component_old = load(manifest_path)
        require(component_old['asset_id'] == r['asset_id'] and component_old['version'] == 'v005', '当前组件身份或版本不符')
        require(component_old['glb_sha256'] == digest(before), '当前组件清单hash不符')
        restored = copy.deepcopy(r)
        restored.update(version='v001', source=export['source'], source_blend=export['source'],
                        source_sha256=export['source_sha256'], derived=export['derived'],
                        derived_sha256=export['derived_sha256'], reference_source=export['derived'],
                        reference_source_sha256=export['derived_sha256'], triangle_count=stats['triangles'],
                        triangle_count_glb=stats['triangles'], triangle_count_blender=r['triangle_count'],
                        triangle_count_basis='GLB mesh primitive index/POSITION accessor count / 3; 不乘实例数',
                        mesh_count_glb=stats['meshes'], primitive_count_glb=stats['primitives'],
                        stable_glb=r['glb'], runtime_glb=r['glb'], stable_prefab=r['prefab'],
                        runtime_prefab=r['prefab'], collision='none_visual_only',
                        collision_status='none_visual_only', role='unoptimized_v001_restored',
                        exported=True, formal_layout_rewritten=False, optimization_performed=False,
                        decimate_performed=False, triangle_budget=None, triangle_budget_revoked=100000,
                        historical_runtime=dict(active=False, version='v005',
                            manifest=rel(BACKUP / 'runtime' / manifest_path.relative_to(RUN)),
                            manifest_sha256=filehash(manifest_path)),
                        delivery_status_path=rel(OUTPUT))
        restored.update(STATUS)
        plan[current] = (before, data)
        plan[manifest_path] = (manifest_path.read_bytes(), encoded(restored, manifest_path.read_bytes()))
        new_records.append(restored)
        totals['before_triangles'] += before_stats['triangles']
        totals['restored_triangles'] += stats['triangles']
        totals['before_meshes'] += before_stats['meshes']
        totals['restored_meshes'] += stats['meshes']
        totals['restored_primitives'] += stats['primitives']
        details.append(dict(asset_id=r['asset_id'], current_path=current.as_posix(),
            stable_path=r['glb'], restored_from=original.as_posix(),
            backup_path=(BACKUP / 'components' / current.relative_to(COMP)).as_posix(),
            before_sha256=digest(before), v001_manifest_sha256=r['glb_sha256'],
            restored_sha256=digest(data), original_hash_matches=True,
            triangles_before=before_stats['triangles'], accessor_triangles=stats['triangles'],
            meshes=stats['meshes'], primitives=stats['primitives']))
    require(totals['before_triangles'] == 99169 and totals['before_meshes'] == 228, '当前总几何不符')
    require(totals['restored_triangles'] == 212967 and totals['restored_meshes'] == 228, '原件总几何不符')
    scene_details = []
    for scene in sorted(expected_scenes):
        before = scene.read_bytes()
        require(len(META.findall(before)) == 2, '场景metadata数量不符: ' + rel(scene))
        version_match = re.findall(rb'^metadata/asset_version = "([^"]+)"', before, re.M)
        require(version_match == [b'v005'], '场景当前版本不符: ' + rel(scene))
        after, count = re.subn(rb'^(metadata/asset_version = )"[^"\r\n]*"', rb'\1"v001"', before, flags=re.M)
        require(count == 1, '场景版本替换数量不符')
        after, count = re.subn(rb'^(metadata/source_blend = )"[^"\r\n]*"',
            lambda m: m.group(1) + b'"' + export['source'].encode('utf-8') + b'"', after, flags=re.M)
        require(count == 1, '场景源替换数量不符')
        require(META.sub(b'', before) == META.sub(b'', after), '场景非metadata内容发生变化')
        plan[scene] = (before, after)
        scene_details.append(dict(path=rel(scene), before_sha256=digest(before), after_sha256=digest(after),
            stripped_before_sha256=digest(META.sub(b'', before)),
            stripped_after_sha256=digest(META.sub(b'', after)),
            metadata_only=True, layout_transform_extresource_preserved=True))
    restored_root = load(ORIGINAL / 'asset_manifest.json')
    for k in ('source', 'source_sha256', 'derived', 'derived_sha256', 'coordinate_map', 'collision'):
        restored_root[k] = export[k]
    restored_root.update(schema='shellstorm2.openworld.tower03.runtime.v001', version='v001',
        source_blend=export['source'], records=new_records, component_count=217,
        reference_source=export['derived'], reference_source_sha256=export['derived_sha256'],
        triangle_count=totals['restored_triangles'], triangle_count_glb=totals['restored_triangles'],
        triangle_count_basis='217 GLB真实accessor三角面求和；不乘房间实例数', mesh_count_glb=228,
        role='unoptimized_v001_restored', layout_owner=old_root['layout_owner'],
        backup_before_restore=rel(BACKUP), delivery_status_path=rel(OUTPUT),
        optimization=dict(active=False, performed=False, decimate_performed=False,
            triangle_budget=None, revoked_triangle_budget=100000,
            reason='用户最新授权撤销低于10万预算；恢复原未减面v001，不执行优化',
            v001_export_preprocessing=export['optimization']),
        historical_runtime=dict(active=False, version='v005',
            manifest=rel(BACKUP / 'runtime/asset_manifest.json'), manifest_sha256=filehash(root_manifest),
            optimization=old_root.get('optimization'), legacy_optimization_v002=old_root.get('legacy_optimization_v002')),
        runtime_integration=dict(**STATUS, stable_component_paths_preserved=True,
            stable_packedscene_paths_preserved=True, formal_layout_rewritten=False,
            collision_or_gameplay_changed=False, godot_executed=False))
    restored_root.update(STATUS)
    for k in ('palette', 'palette_sha256'):
        if k in old_root:
            restored_root[k] = old_root[k]
    plan[root_manifest] = (root_manifest.read_bytes(), encoded(restored_root, root_manifest.read_bytes()))
    require(len(plan) == 653, '事务文件数不符')
    full_paths = files(COMP) + files(RUN) + files(SOURCE)
    full_snapshot = snapshot(full_paths)
    protected_paths = [p for p in full_paths if p not in plan] + files(ORIGINAL)
    for kind in ('components', 'runtime', 'source'):
        protected_paths.extend(files(ART / kind / 'cross_tower_route'))
    tower02_snapshot = snapshot([p for kind in ('components', 'runtime', 'source')
                                 for p in files(ART / kind / 'tower_02')])
    protected_paths.extend(p for p in files(ROOT / 'assets/registry') if p.suffix.lower() == '.xlsx' or 'baseline' in p.name.lower())
    protected = snapshot(sorted(set(protected_paths)))
    backup_bytes = sum(p.stat().st_size for p in full_paths)
    require(shutil.disk_usage(ROOT).free > backup_bytes * 2 + 100_000_000, '备份空间不足')
    report = dict(schema='shellstorm2.tower03.full_restore.v001', asset_id='ENV-OPENWORLD-TOWER03',
        target_version='v001', project=ROOT.as_posix(), status=STATUS['state'], **STATUS,
        godot_executed=False, blender_executed=False, decimate_performed=False, optimization_performed=False,
        triangle_budget=None, revoked_triangle_budget=100000, counts=totals,
        stable_components=COMP.as_posix(), stable_runtime=RUN.as_posix(), backup=BACKUP.as_posix(),
        original_backup=ORIGINAL.as_posix(), source_hashes={k: dict(path=export[k],
            before=export[k + '_sha256'], after=export[k + '_sha256'], unchanged=True) for k in ('source', 'derived')},
        original_manifest=dict(path=rel(EXPORT), sha256=filehash(EXPORT), unchanged=True),
        original_hash_matches=217, mismatch_count=0, scenes_metadata_only=218,
        layout_transform_extresource_preserved=True, import_uid_preserved=True,
        preserved_import_count=sum(p.name.endswith('.import') for p in full_paths),
        preserved_uid_count=sum(p.name.endswith('.uid') for p in full_paths),
        source_export_candidate_catalog_unchanged=True, tower02_modified_by_this_transaction=False,
        tower02_protection_scope='塔2由另一恢复任务处理；本事务不写塔2，不以并行任务的变化触发回滚',
        tower02_snapshot_before=tower02_snapshot,
        cross_tower_route_unchanged=True, ledger_baseline_unchanged=True,
        historical_v005_active=False, historical_v005_manifest=rel(BACKUP / 'runtime/asset_manifest.json'),
        full_backup_files=len(full_paths), full_backup_bytes=backup_bytes,
        protected_files=protected, components=details, scenes=scene_details,
        written_files=[rel(p) for p in sorted(plan)],
        verification_scope='静态逐字节/哈希及GLB accessor核验；未启动Godot，未运行通用验收器，未写账本或baseline')
    return plan, full_snapshot, protected, report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    plan, full_snapshot, protected, report = preflight()
    print(json.dumps(dict(preflight='passed', counts=report['counts'], transaction_files=len(plan),
        full_backup_files=report['full_backup_files'], full_backup_bytes=report['full_backup_bytes'],
        protected_files=len(protected)), ensure_ascii=False), flush=True)
    if not args.apply:
        return
    backup_reused = BACKUP.exists()
    if backup_reused:
        require(load(BACKUP / 'backup_inventory.json')['files'] == full_snapshot, '已有备份与当前文件不一致，禁止覆盖或复用')
    else:
        BACKUP.mkdir(parents=True, exist_ok=False)
        (BACKUP / '.gdignore').write_bytes(b'')
        for directory in (COMP, RUN, SOURCE):
            shutil.copytree(directory, BACKUP / directory.parent.name)
    for name, h in full_snapshot.items():
        path = ROOT / name
        section = next(d for d in (COMP, RUN, SOURCE) if path.is_relative_to(d))
        backup_path = BACKUP / section.parent.name / path.relative_to(section)
        require(filehash(backup_path) == h, '全备份核验失败: ' + name)
    verify_snapshot(full_snapshot)
    verify_snapshot(protected)
    if not backup_reused:
        (BACKUP / 'backup_inventory.json').write_bytes(encoded(dict(files=full_snapshot,
            verified=True, transaction_file_count=len(plan))))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    created_output_ignore = not (OUTPUT.parent / '.gdignore').exists()
    if created_output_ignore:
        (OUTPUT.parent / '.gdignore').write_bytes(b'')
    written = []
    report_written = False
    try:
        for path, (before, after) in plan.items():
            require(path.read_bytes() == before, '事务前文件被外部更改: ' + rel(path))
            atomic(path, after)
            written.append(path)
        for path, (_, after) in plan.items():
            require(path.read_bytes() == after, '事务后字节核验失败: ' + rel(path))
        verify_snapshot(protected)
        require(set(COMP.rglob('*.glb')) == {p for p in plan if p.suffix == '.glb'}, '恢复后GLB路径集合变化')
        require(set(RUN.rglob('*.tscn')) == {p for p in plan if p.suffix == '.tscn'}, '恢复后TSCN路径集合变化')
        for detail in report['components']:
            current = Path(detail['current_path'])
            require(filehash(current) == detail['v001_manifest_sha256'], '恢复后原件hash不符')
            stats = glb_stats(current.read_bytes())
            require(stats['triangles'] == detail['accessor_triangles'], '恢复后真实三角面不符')
        for detail in report['scenes']:
            path = ROOT / detail['path']
            require(META.sub(b'', plan[path][0]) == META.sub(b'', path.read_bytes()), '恢复后场景布局保护失败')
        for path in (p for p in plan if p.name == 'asset_manifest.json'):
            manifest = load(path)
            require(manifest['version'] == 'v001' and all(manifest[k] == v for k, v in STATUS.items()), '清单状态不准确')
            require(manifest['source_sha256'] == report['source_hashes']['source']['before'], '清单源hash错误')
            require(manifest['derived_sha256'] == report['source_hashes']['derived']['before'], '清单导出源hash错误')
        tower02_after = snapshot([p for kind in ('components', 'runtime', 'source')
                                  for p in files(ART / kind / 'tower_02')])
        report.update(tower02_snapshot_after=tower02_after,
            tower02_observed_unchanged=report['tower02_snapshot_before'] == tower02_after,
            transaction_committed=True, transaction_files_written=len(written),
            rollback_required=False, completed_at=datetime.now().astimezone().isoformat())
        atomic(OUTPUT, encoded(report))
        report_written = True
        require(load(OUTPUT)['transaction_committed'], '报告回读失败')
        print(json.dumps(dict(result='restored', report=OUTPUT.as_posix(), backup=BACKUP.as_posix(),
            counts=report['counts'], transaction_files_written=len(written), **STATUS), ensure_ascii=False), flush=True)
    except BaseException:
        rollback_errors = []
        for path in reversed(written):
            try:
                require(path.read_bytes() == plan[path][1], '回滚检测到外部改动，拒绝覆盖: ' + rel(path))
                atomic(path, plan[path][0])
                require(path.read_bytes() == plan[path][0], '回滚字节核验失败')
            except BaseException as exc:
                rollback_errors.append(str(exc))
        if report_written:
            OUTPUT.unlink()
        if created_output_ignore:
            (OUTPUT.parent / '.gdignore').unlink()
        print(json.dumps(dict(result='rolled_back' if not rollback_errors else 'rollback_blocked',
            own_files_attempted=len(written), errors=rollback_errors), ensure_ascii=False), flush=True)
        raise


if __name__ == '__main__':
    main()
