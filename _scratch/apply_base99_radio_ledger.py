from __future__ import annotations

from collections import Counter
from copy import copy
from datetime import datetime
import hashlib
import json
import re
import shutil
from pathlib import Path

import openpyxl
from openpyxl.worksheet.datavalidation import DataValidation

ROOT = Path('I:/工作项目/shellstrom2/ShellStorm2')
BOOKS = ROOT / 'assets/registry/ledgers'
PROP_BOOK = BOOKS / 'ShellStorm2_道具账本_v001.xlsx'
MASTER_BOOK = ROOT / 'assets/registry/ShellStorm2_美术资产台账_v001.xlsx'
BASELINE = ROOT / 'assets/registry/ledger_split_baseline.json'
OUTPUT = ROOT / 'outputs/base99_radio_v001'
BACKUP = OUTPUT / 'backup_20261005'
ASSET_ID = 'PRP-BASE99-RADIO-3D'
TODAY = datetime(2026, 10, 5)

SOURCE = 'assets/art/props/base_world_3d/source/base99_radio/prp_base99_radio_source_v001.blend'
GLB = 'assets/art/props/base_world_3d/components/base99_radio/prp_base99_radio_visual_top3d.glb'
RUNTIME = 'assets/art/props/base_world_3d/runtime/base99_radio/prp_base99_radio_root_top3d.tscn'
SCRIPT = 'src/base3d/Base99Radio3D.gd'
LAYOUT = 'assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d.tscn'


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def row_digest(values: list[object]) -> str:
    content_cols = [c for c in range(25) if c not in (17, 18)]
    text = '\x1f'.join('' if values[c] is None else str(values[c]).strip() for c in content_cols)
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def col_digest(rows: list[tuple[str, list[object]]], col: int) -> str:
    ordered = sorted(rows, key=lambda item: (str(item[1][0] or '').strip(), str(item[1][col] or '').strip()))
    text = '\x1e'.join('' if values[col] is None else str(values[col]).strip() for _asset_id, values in ordered)
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def read_rows(ws) -> list[tuple[int, list[object]]]:
    return [(r, [ws.cell(r, c).value for c in range(1, 26)]) for r in range(6, ws.max_row + 1) if ws.cell(r, 1).value]


def dedupe_key(row: int) -> str:
    return f'=LOWER(TRIM(C{row})&"|"&TRIM(D{row})&"|"&TRIM(E{row})&"|"&TRIM(F{row})&"|"&TRIM(H{row})&"|"&TRIM(I{row}))'


def dedupe_result(row: int, last: int) -> str:
    return f'=IF(COUNTIF($R$6:$R${last},R{row})>1,"重复","唯一")'


def copy_dv_with_extended_range(ws, new_last: int) -> None:
    old_validations = list(ws.data_validations.dataValidation)
    ws.data_validations.dataValidation = []
    for validation in old_validations:
        new_validation = DataValidation(
            type=validation.type,
            formula1=validation.formula1,
            formula2=validation.formula2,
            allow_blank=validation.allow_blank,
            showErrorMessage=validation.showErrorMessage,
            showInputMessage=validation.showInputMessage,
            error=validation.error,
            errorTitle=validation.errorTitle,
            prompt=validation.prompt,
            promptTitle=validation.promptTitle,
        )
        for cell_range in validation.sqref.ranges:
            text = str(cell_range)
            text = re.sub(r'([A-Z]+)\d+$', rf'\g<1>{new_last}', text)
            new_validation.add(text)
        ws.add_data_validation(new_validation)


def update_baseline() -> None:
    baseline = json.loads(BASELINE.read_text(encoding='utf-8'))
    index = json.loads((ROOT / 'assets/registry/ledger_index.json').read_text(encoding='utf-8'))
    all_rows: list[tuple[str, list[object]]] = []
    for domain in index['domains']:
        workbook = openpyxl.load_workbook(ROOT / 'assets/registry/ledgers' / domain['file'], read_only=True)
        ws = workbook['资产主表']
        for _row, values in read_rows(ws):
            all_rows.append((str(values[0]), values))
    assert ASSET_ID in {asset_id for asset_id, _values in all_rows}
    for asset_id, values in all_rows:
        if asset_id == ASSET_ID:
            baseline['assets'][asset_id] = {'v': row_digest(values), 'c': str(values[2]), 'd': 'props'}
    baseline['asset_count'] = len(baseline['assets'])
    baseline['captured_at'] = '2026-10-05'
    baseline['column_digests'] = {str(col + 1): col_digest(all_rows, col) for col in range(25) if col not in (17, 18)}
    baseline['category_counts'] = dict(sorted(Counter(str(values[2]) for _asset_id, values in all_rows).items()))
    BASELINE.write_text(json.dumps(baseline, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    BACKUP.mkdir(parents=True, exist_ok=True)
    for path in [PROP_BOOK, MASTER_BOOK, BASELINE]:
        shutil.copy2(path, BACKUP / path.name)

    for relative in [SOURCE, GLB, RUNTIME, SCRIPT, LAYOUT]:
        assert (ROOT / relative).is_file(), relative

    workbook = openpyxl.load_workbook(PROP_BOOK)
    main = workbook['资产主表']
    assert not any(main.cell(r, 1).value == ASSET_ID for r in range(6, main.max_row + 1))
    old_last = max(r for r, _values in read_rows(main))
    new_row = old_last + 1
    template_row = 18
    for col in range(1, 26):
        main.cell(new_row, col)._style = copy(main.cell(template_row, col)._style)
    main.row_dimensions[new_row].height = main.row_dimensions[template_row].height
    values = {
        1: ASSET_ID,
        2: '99F阁楼收音机',
        3: '道具',
        4: 'decor_prop',
        5: 'base99_radio',
        6: 'root',
        7: None,
        8: 'Top3D / local -Z 正面',
        9: 'off / music_a / music_b',
        10: '基地99层美术布置层 / env_base_facility_art_layout_top3d',
        11: '正式美术已接入',
        12: 'P1',
        13: 'v001',
        14: '0.414m × 0.228m × 0.411m；独立视觉GLB/PackedScene；WorldCollision与点击区域分离；AudioStreamPlayer3D走Music总线；左键/E循环关→基地音乐A→基地音乐B→关',
        15: RUNTIME,
        16: '; '.join([SOURCE, GLB, SCRIPT, LAYOUT]),
        17: 'base99_radio; 99F阁楼收音机; 收音机; 可交互道具; 基地音乐A; 基地音乐B; Music',
        20: sha(ROOT / RUNTIME),
        21: 'Codex',
        22: TODAY,
        23: '用户指定Blender资产',
        24: 'BASE99-RADIO-INTERACTIVE',
        25: '2026-10-05：按椅子/梯子既有“道具 / decor_prop / 3D-道具”口径登记；正式Prefab自持碰撞、点击区域、Music总线与左键/E交互；状态循环为关→基地音乐A→基地音乐B→关。模型验收保留 StatusLight 节点命名误报，未宣称模型门禁全过。',
    }
    for col, value in values.items():
        main.cell(new_row, col).value = value
    for row in range(6, new_row + 1):
        main.cell(row, 18).value = dedupe_key(row)
        main.cell(row, 19).value = dedupe_result(row, new_row)
    overview = workbook['总览']
    for ref in ('A6', 'C6', 'E6', 'G6', 'B10', 'C10', 'B11', 'C11'):
        formula = overview[ref].value
        assert isinstance(formula, str) and f'$26' in formula, (ref, formula)
        overview[ref].value = formula.replace('$26', f'${new_row}')
    copy_dv_with_extended_range(main, new_row)
    main.auto_filter.ref = f'A5:X{new_row}'

    prefab = workbook['3D-道具']
    prefab_row = prefab.max_row + 1
    for col in range(1, 17):
        prefab.cell(prefab_row, col)._style = copy(prefab.cell(6, col)._style)
    prefab.row_dimensions[prefab_row].height = prefab.row_dimensions[6].height
    prefab_values = [ASSET_ID, '99F阁楼收音机', RUNTIME, GLB, SOURCE, '可复用摆放道具Prefab；左键/E循环关→基地音乐A→基地音乐B→关；AudioStreamPlayer3D走Music总线', SCRIPT, '开', 'Prefab自身', '独立WorldCollision + InteractionHitArea', '0.414m × 0.228m × 0.411m', '-Z', '基地99层美术布置层 / env_base_facility_art_layout_top3d', '正式美术已接入', 'v001', '根节点=ItemRoot(Node3D)；StatusLight命名保留运行时契约；模型验收有StatusLight命名误报，未宣称全过']
    for col, value in enumerate(prefab_values, 1):
        prefab.cell(prefab_row, col).value = value
    prefab.auto_filter.ref = f'A4:P{prefab_row}'
    prefab['A2'] = '桌椅、家具、容器、收音机和摆放装饰物；本次扫描 4 个独立Prefab。'

    log = workbook['域变更日志']
    log_row = log.max_row + 1
    for col in range(1, 8):
        log.cell(log_row, col)._style = copy(log.cell(log_row - 1, col)._style)
    log_values = ['v0.1.5', '2026-10-05', '99F阁楼收音机正式接入', '道具 / 场景可交互道具', '新增 PRP-BASE99-RADIO-3D；独立GLB/PackedScene、Music总线双曲目循环、左键/E交互及正式基地布局接入。', '更新资产主表、3D-道具分页、总览公式、DV和无损基线；既有椅子/梯子行保持不变。模型StatusLight命名误报单独保留，未宣称模型门禁全过。', 'Codex']
    for col, value in enumerate(log_values, 1):
        log.cell(log_row, col).value = value
    workbook.save(PROP_BOOK)

    master = openpyxl.load_workbook(MASTER_BOOK)
    master_overview = master['总览']
    master_prefab = master['3D Prefab总控']
    master_prefab['C7'] = 4
    master_prefab['E7'] = 2
    master_prefab['F7'] = 2
    master_prefab['G7'] = '桌椅、家具、收音机、容器和摆放装饰物'
    # 道具账本的条数在总目录索引表的道具行（总览第17行）。
    master_overview['D18'] = 21
    master.save(MASTER_BOOK)

    update_baseline()
    evidence = {
        'asset_id': ASSET_ID,
        'ledger': str(PROP_BOOK),
        'asset_sheet_row': new_row,
        'category': '道具',
        'subcategory': 'decor_prop',
        'prefab_sheet': '3D-道具',
        'prefab_sheet_row': prefab_row,
        'log_sheet_row': log_row,
        'master_prefab_control_row': 7,
        'master_overview_category_row': 17,
        'status': '正式美术已接入',
        'model_gate_status': '未全过：保留 StatusLight 命名误报；final_acceptance.json 的其余模型验收通过，不将模型门禁写成全过。',
        'backup_dir': str(BACKUP),
        'backup_files': [str(BACKUP / path.name) for path in [PROP_BOOK, MASTER_BOOK, BASELINE]],
        'paths': {key: value for key, value in [('source_blend', SOURCE), ('glb', GLB), ('stable_prefab', RUNTIME), ('script', SCRIPT), ('formal_scene', LAYOUT)]},
        'runtime_contract': {'state_cycle': ['off', 'music_a', 'music_b', 'off'], 'bus': 'Music', 'input': ['鼠标左键', 'E']},
        'baseline': {'path': str(BASELINE), 'asset_count': json.loads(BASELINE.read_text(encoding='utf-8'))['asset_count'], 'captured_at': json.loads(BASELINE.read_text(encoding='utf-8'))['captured_at']},
    }
    (OUTPUT / 'registration_evidence.json').write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (OUTPUT / 'registration_evidence.txt').write_text('\n'.join([
        f'AssetID: {ASSET_ID}',
        f'账本: {PROP_BOOK}',
        f'资产主表行: {new_row}',
        '分类: 道具 / decor_prop / 3D-道具',
        f'Prefab分页行: {prefab_row}',
        f'域变更日志行: {log_row}',
        '正式状态: 正式美术已接入',
        '模型门禁: 未全过；StatusLight 命名误报保留，未宣称全过',
        f'备份目录: {BACKUP}',
        '备份文件: ShellStorm2_道具账本_v001.xlsx, ShellStorm2_美术资产台账_v001.xlsx, ledger_split_baseline.json',
        f'无损基线: {BASELINE}',
    ]) + '\n', encoding='utf-8')
    print(json.dumps(evidence, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
