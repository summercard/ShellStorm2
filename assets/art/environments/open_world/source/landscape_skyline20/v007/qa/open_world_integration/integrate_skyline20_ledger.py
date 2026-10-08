import argparse
import importlib.util
import json
from io import BytesIO
import re
import shutil
import sys
import traceback
from copy import deepcopy
from datetime import datetime
from pathlib import Path
from zipfile import ZipFile
from xml.etree import ElementTree as ET

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
OLD_PATH = ROOT / 'assets/art/environments/open_world/source/landscape_skyline20/v007/qa/ledger_transaction/register_skyline20.py'
spec = importlib.util.spec_from_file_location('skyline20_ledger_helpers', OLD_PATH)
old = importlib.util.module_from_spec(spec)
spec.loader.exec_module(old)
# 只载入辅助函数，禁止调用旧事务的 prepare/apply/main；所有新证据写本阶段目录。
old.WORK = OUT
PAGE = old.PAGE
BASELINE = ROOT / 'assets/registry/ledger_split_baseline.json'
ROUTE = 'assets/art/environments/open_world/runtime/cross_tower_route/env_cross_tower_route_root_top3d.tscn'
PLACEMENT = 'assets/art/environments/open_world/runtime/landscape_skyline20/env_landscape_skyline20_placement_root_top3d.tscn'
EDITORS = ['scenes/open_world_layout_edit/open_world_layout_edit.tscn',
           'scenes/open_world_layout_edit/open_world_chunk_layout_edit.tscn']
USAGE = ('开放世界塔3东侧；正式route=res://' + ROUTE + '；共享摆位=res://' + PLACEMENT
         + '；编辑场景=' + ' / '.join('res://' + p for p in EDITORS))
NEW_NOTE = ('技术通过、美术待审；reference_art_approved=false；runtime_integrated=true；'
            '用户授权v007正式导入并投放塔3东侧，授权不等同逐项参考图美术验收；'
            '已正式接入route/共享摆位/编辑场景；无碰撞，不制作底层室内。')
REPORT_PATH = OUT / 'ledger_integration.json'
NS = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}


def runtime_evidence():
    p = OUT / 'placement_runtime.json'
    data = old.read_json(p)
    assert data.get('failures') == [], '运行报告未通过或尚未准备好'
    assert data.get('live_instance_count') == 1, '正式运行实例数不为1'
    delta = data.get('roof_delta_m')
    assert isinstance(delta, (int, float)) and abs(delta - 10.0) <= 0.01, '屋面高差不满足10m'
    for name in ('import.log', 'placement_runtime.log'):
        text = (OUT / name).read_text(encoding='utf-8-sig')
        assert text.strip() and 'Godot Engine' in text, '日志缺少引擎执行证据：' + name
        assert not re.search(r'\bERROR\b', text, re.I), '正式日志存在ERROR：' + name
        clean = re.sub(r'\x1b\[[0-9;]*m', '', text)
        if name == 'import.log':
            assert '[ DONE ] loading_editor_layout' in clean, '正式导入日志尚未完成'
        else:
            match = re.search(r'^SKYLINE20_PLACEMENT (.+)$', text, re.M)
            assert match and json.loads(match.group(1)) == data, '日志与运行JSON不一致'
    for pth in (ROUTE, EDITORS[0]):
        assert 'res://' + PLACEMENT in (ROOT / pth).read_text(encoding='utf-8'), '场景未引用共享摆位：' + pth
    chunk = (ROOT / EDITORS[1]).read_text(encoding='utf-8')
    assert 'res://' + EDITORS[0] in chunk and 'instance=ExtResource("reference")' in chunk, '区块编辑场景未继承共享摆位参考场景'
    placement = (ROOT / PLACEMENT).read_text(encoding='utf-8')
    assert 'position = Vector3(75, -86.36, -195)' in placement, '共享摆位与本阶段实测不符'
    assert data['formal']['position'] == data['live']['position'] == data['editor']['position']
    assert data['formal']['min'][0] > data['tower3']['max'][0], '景观不在塔3东侧'
    return {'json': old.relative(OUT / 'placement_runtime.json'), 'failures': [],
            'live_instance_count': 1, 'roof_delta_m': delta, 'import_error_count': 0,
            'reference_art_approved': False, 'user_authorized_placement': True}


def snapshot(index, asset_hashes):
    paths = {d.relative_path for d in index.domains}
    paths.update(asset_hashes)
    paths.update((index.master_relative_path, old.relative(BASELINE), 'assets/registry/ledger_index.json',
                  old.relative(OLD_PATH), old.relative(Path(__file__)),
                  old.relative(old.SOURCE / 'qa/ledger_registration.json'),
                  old.relative(OLD_PATH.parent / 'prepared.json'), ROUTE, PLACEMENT, *EDITORS))
    paths.update(old.relative(OUT / p) for p in ('placement_runtime.json', 'import.log', 'placement_runtime.log'))
    paths.update(old.relative(ROOT / p) for p in ('scripts/check_asset_registry.py',
                 'scripts/check_asset_runtime_naming.py', 'scripts/check_ledger_refs.py',
                 'scripts/ledger_registry.py', 'tools/asset_pipeline/verify_ledger_split.py',
                 'tools/asset_pipeline/split_asset_ledger.py'))
    return {p: old.sha(ROOT / p) for p in sorted(paths)}


def checkpoint(index, asset_hashes, expected):
    actual = snapshot(index, asset_hashes)
    assert actual == expected, '全域或冻结资产/布局/运行证据发生并发变化，禁止覆盖'
    old.check_hashes(expected)


def save_candidate(book, before, candidate, sheet):
    original_book = old.load_workbook(before)
    for ws in book:
        if ws.title != sheet:
            assert old.sheet_digest(ws) == old.sheet_digest(original_book[ws.title]), '保存前非授权表内容改变'
    book.save(candidate)
    # openpyxl会更新修改时间及丢掉空行XML；非授权包成员逐字节沿用原件。
    target = f'xl/worksheets/sheet{book.sheetnames.index(sheet) + 1}.xml'
    content = BytesIO()
    with ZipFile(before) as original, ZipFile(candidate) as generated, ZipFile(content, 'w') as result:
        assert set(original.namelist()) == set(generated.namelist())
        for member in original.infolist():
            data = generated.read(member.filename) if member.filename == target else original.read(member.filename)
            if not member.filename.startswith('xl/worksheets/') and member.filename != 'docProps/core.xml':
                assert generated.read(member.filename) == original.read(member.filename), '样式或工作簿结构发生变化'
            result.writestr(member, data)
    candidate.write_bytes(content.getvalue())


def protected_workbook_diff(before, candidate, allowed, tag):
    changes = old.workbook_diff(before, candidate, OUT / (tag + '_cell_diff.json'))
    assert {(c['sheet'], c['cell']) for c in changes} == allowed, '逐格差异不等于授权白名单'
    a, b = old.load_workbook(before), old.load_workbook(candidate)
    assert a.sheetnames == b.sheetnames
    for wa, wb in zip(a, b):
        assert (wa.max_row, wa.max_column) == (wb.max_row, wb.max_column), '工作表尺寸改变'
        for pos in wa._cells.keys() | wb._cells.keys():
            ca, cb = wa.cell(*pos), wb.cell(*pos)
            assert ca._style == cb._style, '样式变化：' + wa.title + '/' + ca.coordinate
            assert ca.data_type == cb.data_type, '单元格类型变化'
            if ca.data_type == 'f':
                assert ca.value == cb.value, '公式变化'
    # ZIP/XML级保护：除授权文本格的值外，其他页、样式、DV、公式和包成员必须完全一致。
    with ZipFile(before) as za, ZipFile(candidate) as zb:
        assert set(za.namelist()) == set(zb.namelist()), 'XLSX包成员变化'
        titles = {f'xl/worksheets/sheet{i}.xml': title for i, title in enumerate(a.sheetnames, 1)}
        for name in za.namelist():
            ba, bb = za.read(name), zb.read(name)
            if ba == bb:
                continue
            title = titles.get(name)
            assert title and any(s == title for s, _ in allowed), '非授权包成员改变：' + name
            ta, tb = ET.fromstring(ba), ET.fromstring(bb)
            for tree in (ta, tb):
                for cell in tree.findall('.//m:sheetData/m:row/m:c', NS):
                    if (title, cell.get('r')) in allowed:
                        for child in list(cell):
                            cell.remove(child)
            assert ET.tostring(ta) == ET.tostring(tb), '授权页非文本值结构变化：' + name
    return changes


def patch_note(text):
    assert isinstance(text, str) and text.startswith(old.NOTE), '旧阶段备注不符合冻结口径'
    result = NEW_NOTE + text[len(old.NOTE):]
    assert 'runtime_integrated=false' not in result and '未正式接入' not in result
    assert 'reference_art_approved=false' in result
    assert re.findall(r'[0-9a-f]{64}', text) == re.findall(r'[0-9a-f]{64}', result), '历史哈希被改动'
    return result + ' 本阶段证据=outputs/skyline20_placement/placement_runtime.json；live_instance_count=1；roof_delta_m=10；原阶段QA/登记报告保留为历史证据。'


def validate_rows(index, domain, records):
    ids = [x['asset_id'] for x in records]
    assert len(ids) == len(set(ids)) == 9
    seen = []
    for d in index.domains:
        book = old.load_workbook(d.path)
        seen.extend((d.key, r, v[0]) for r, v in old.read_source_rows(book['资产主表']) if v[0] in ids)
    assert seen == [('scenes', 826 + i, aid) for i, aid in enumerate(ids)], '主表ID归属/行号不符'
    book = old.load_workbook(domain.path)
    base = old.read_json(BASELINE)
    values = dict(old.read_source_rows(book['资产主表']))
    for i, record in enumerate(records):
        r, pr = 826 + i, 718 + i
        assert book['资产主表'].cell(r, 11).value == book[PAGE].cell(pr, 14).value == 'validated'
        assert book['资产主表'].cell(r, 13).value == book[PAGE].cell(pr, 15).value == 'v007'
        assert book[PAGE].cell(pr, 1).value == record['asset_id']
        assert book['资产主表'].cell(r, 15).value == book[PAGE].cell(pr, 3).value == record['prefab']
        assert book['资产主表'].cell(r, 20).value == record['prefab_sha256']
        assert base['assets'][record['asset_id']]['v'] == old._row_digest(values[r]), '授权行有历史指纹漂移'
        assert 'prefab_sha256=' + record['prefab_sha256'] in book[PAGE].cell(pr, 16).value
    assert base['sheet_digests'][PAGE] == old.sheet_digest(book[PAGE]), '专表有历史指纹漂移'


def baseline_candidate(before, workbook, index, records, stage):
    after = deepcopy(before)
    wb = old.load_workbook(workbook)
    ids = {x['asset_id'] for x in records}
    if stage == 'asset':
        for _, values in old.read_source_rows(wb['资产主表']):
            if values[0] in ids:
                after['assets'][values[0]]['v'] = old._row_digest(values)
        old.refresh_aggregate(after, index, workbook)
        assert after.keys() == before.keys() and after['assets'].keys() == before['assets'].keys()
        for aid in before['assets']:
            expected = deepcopy(before['assets'][aid])
            if aid in ids:
                expected['v'] = after['assets'][aid]['v']
            assert after['assets'][aid] == expected, '非授权资产字段变化'
        assert all(after[k] == before[k] for k in before if k not in ('assets', 'column_digests'))
        changed_columns = {k for k in before['column_digests'] if before['column_digests'][k] != after['column_digests'][k]}
        assert changed_columns == {'10', '25'}, '聚合摘要变化不止J/Y'
    else:
        after['sheet_digests'][PAGE] = old.sheet_digest(wb[PAGE])
        expected = deepcopy(before)
        expected['sheet_digests'][PAGE] = after['sheet_digests'][PAGE]
        assert after == expected
    path = OUT / ('integration_' + stage + '_baseline_candidate.json')
    old.write_json(path, after)
    old.write_json(OUT / ('integration_' + stage + '_baseline_diff.json'), {
        'authorized_row_digests': {aid: [before['assets'][aid]['v'], after['assets'][aid]['v']] for aid in sorted(ids)},
        'column_digests': {k: [before['column_digests'][k], after['column_digests'][k]] for k in before['column_digests'] if before['column_digests'][k] != after['column_digests'][k]},
        'sheet_digests': {k: [before['sheet_digests'][k], after['sheet_digests'][k]] for k in before['sheet_digests'] if before['sheet_digests'][k] != after['sheet_digests'][k]},
        'other_assets_and_sheet_digests_unchanged': True})
    return path


def checked_gates(tag, index, asset_hashes, hashes, mapping=None, baseline=None):
    checkpoint(index, asset_hashes, hashes)
    result = old.gates_with_baseline(tag, mapping, baseline) if mapping else old.gates(tag)
    checkpoint(index, asset_hashes, hashes)
    assert all(v['exit'] in (0, 1) and (v['exit'] == 0 or v['errors']) for v in result.values()), '门禁执行异常或错误未完整捕获'
    return result


def main(mode):
    assert not any((OUT / (s + '_commit.json')).exists() for s in ('integration_asset', 'integration_prefab')), '本阶段已有提交记录，禁止重复事务；需人工核查报告'
    report = {'asset_id': 'ENV-OPENWORLD-LANDSCAPE-SKYLINE20', 'version': 'v007', 'status': 'validated',
              'reference_art_approved': False, 'user_authorized_placement': True,
              'runtime_integrated': False, 'transaction_status': 'PREPARING', 'transactions': [], 'mode': mode}
    try:
        report['runtime_evidence'] = runtime_evidence()
        index, domain, catalog, records, asset_hashes = old.facts()
        hashes = snapshot(index, asset_hashes)
        validate_rows(index, domain, records)
        checkpoint(index, asset_hashes, hashes)
        report.update({'paths': {'ledger': domain.relative_path, 'baseline': old.relative(BASELINE),
                       'route': ROUTE, 'shared_placement': PLACEMENT, 'editors': EDITORS},
                       'frozen_hashes': dict(hashes), 'geometry_hashes': asset_hashes, 'backups': {},
                       'historical_registration': old.relative(old.SOURCE / 'qa/ledger_registration.json'),
                       'note': '用户授权投放不等于逐项美术验收；包装是布局资源，不新增几何资产/AssetID；总目录不修改。'})
        before = checked_gates('integration_before', index, asset_hashes, hashes)
        report['before_gates'] = before
        prior = before
        for stage in ('asset', 'prefab'):
            checkpoint(index, asset_hashes, hashes)
            runtime_evidence()
            backups = {}
            for label, path in (('scenes', domain.path), ('baseline', BASELINE)):
                backup = OUT / ('integration_' + stage + '_before' + path.suffix)
                assert not backup.exists(), '备份已存在，禁止覆盖；检查之前运行结果'
                shutil.copy2(path, backup)
                assert old.sha(backup) == hashes[old.relative(path)]
                backups[label] = old.relative(backup)
            report['backups'][stage] = backups
            checkpoint(index, asset_hashes, hashes)
            book = old.load_workbook(domain.path)
            sheet, rows, cols = ('资产主表', range(826, 835), (10, 25)) if stage == 'asset' else (PAGE, range(718, 727), (13, 16))
            allowed = set()
            for row in rows:
                assert book[sheet].cell(row, 1).value in {r['asset_id'] for r in records}
                book[sheet].cell(row, cols[0]).value = USAGE
                book[sheet].cell(row, cols[1]).value = patch_note(book[sheet].cell(row, cols[1]).value)
                allowed.update((sheet, book[sheet].cell(row, c).coordinate) for c in cols)
            candidate = OUT / ('integration_' + stage + '_scenes_candidate.xlsx')
            save_candidate(book, domain.path, candidate, sheet)
            changes = protected_workbook_diff(domain.path, candidate, allowed, 'integration_' + stage)
            base_candidate = baseline_candidate(old.read_json(BASELINE), candidate, index, records, stage)
            checkpoint(index, asset_hashes, hashes)
            mapping = {str(domain.path.resolve()): str(candidate), str(BASELINE.resolve()): str(base_candidate)}
            candidate_gates = checked_gates('integration_candidate_' + stage, index, asset_hashes, hashes, mapping, base_candidate)
            gate_diff = old.compare(prior, candidate_gates)
            old.write_json(OUT / ('integration_' + stage + '_gate_diff.json'), gate_diff)
            old.assert_no_new(gate_diff)
            item = {'stage': stage, 'cell_diff_count': len(changes), 'whitelist': sorted(allowed),
                    'candidate_gates': candidate_gates, 'gate_diff': gate_diff, 'committed': False}
            report['transactions'].append(item)
            old.write_json(REPORT_PATH, report)
            if mode == 'check':
                report['transaction_status'] = 'ASSET_CANDIDATE_VERIFIED_NOT_COMMITTED'
                report['next'] = 'check只验证主表候选；专表依赖主表提交，apply将分别执行两次事务。保留证据，不覆盖已有备份。'
                break
            runtime_evidence()
            checkpoint(index, asset_hashes, hashes)
            candidate_hashes = {str(p): old.sha(p) for p in (candidate, base_candidate)}
            item['candidate_hashes'] = candidate_hashes
            old.commit_candidates({domain.relative_path: candidate, old.relative(BASELINE): base_candidate}, hashes, 'integration_' + stage)
            item['committed'] = True
            checkpoint(index, asset_hashes, hashes)
            after = checked_gates('integration_after_' + stage, index, asset_hashes, hashes)
            old.assert_no_new(old.compare(prior, after))
            old.assert_no_new(old.compare(before, after))
            item['after_gates'] = after
            prior = after
            report['transaction_status'] = 'ASSET_COMMITTED_PREFAB_PENDING' if stage == 'asset' else 'INTEGRATED_ART_REVIEW_PENDING'
            old.write_json(REPORT_PATH, report)
        checkpoint(index, asset_hashes, hashes)
        report['after_hashes'] = hashes
        report['runtime_integrated'] = len(report['transactions']) == 2 and all(t['committed'] for t in report['transactions'])
        report['finished_at'] = datetime.now().isoformat()
        report['preservation'] = {'prefab_source_glb_hashes_unchanged': all(hashes[p] == h for p, h in asset_hashes.items()),
                                 'master_unchanged': hashes[index.master_relative_path] == report['frozen_hashes'][index.master_relative_path],
                                 'formulas_styles_dv_and_other_sheets_unchanged': True,
                                 'other_asset_v_and_sheet_digest_unchanged': True}
        report['remaining'] = 'reference_art_approved=false；美术逐项验收未完成；既有门禁红项见完整before/after，不宣称全绿。'
        old.write_json(REPORT_PATH, report)
        print(report['transaction_status'], flush=True)
    except BaseException as exc:
        report.update({'transaction_status': 'BLOCKED', 'error': str(exc), 'traceback': traceback.format_exc()})
        old.write_json(REPORT_PATH, report)
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Skyline20正式接入账本，两次独立受保护事务，不执行旧登记main。')
    parser.add_argument('mode', choices=('check', 'apply'))
    main(parser.parse_args().mode)
