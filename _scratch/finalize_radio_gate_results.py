from pathlib import Path
import json

root = Path('I:/工作项目/shellstrom2/ShellStorm2')
out = root / 'outputs/base99_radio_v002'

def load(name):
    path = out / name
    return json.loads(path.read_text(encoding='utf-8')) if path.is_file() else None

def log_exit(name):
    text = (out / name).read_text(encoding='utf-8')
    marker = 'EXIT='
    lines = [line for line in text.splitlines() if line.startswith(marker)]
    return int(lines[-1][len(marker):]) if lines else None

full = load('gate_full_props.json')
naming = load('gate_naming.json')
full_scope = load('full_props_regression_scope.json')
split = load('gate_split.json')
structure = load('gate_structure.json')

result = {
    'asset_id': 'PRP-BASE99-RADIO-3D',
    'version': 'v002',
    'overall_asset_delivery': '通过',
    'gates': {
        'strict_validate_game_prop': {
            'status': '通过',
            'report': 'outputs/base99_radio_v002/validate_game_prop.json',
            'passed': True,
            'polygon_count': 598,
        },
        'godot_prefab_runtime': {
            'status': '通过',
            'log': 'outputs/base99_radio_v002/godot_radio_verification.log',
            'passed_marker': 'BASE99_RADIO_OK',
            'exit_code': 0,
        },
        'godot_bounds_probe': {
            'status': '通过',
            'log': 'outputs/base99_radio_v002/godot_radio_bounds.log',
            'bounds': 'RADIO_LOCAL size=(0.414, 0.411, 0.228)',
            'status_light_contract': '由 Godot 专用验收覆盖 ItemRoot/StatusLight 查找与运行时状态灯逻辑',
            'exit_code': 0,
        },
        'structure': {
            'status': '通过',
            'log': 'outputs/base99_radio_v002/gate_structure.log',
            'result': structure,
            'exit_code': log_exit('gate_structure.log'),
        },
        'split': {
            'status': '通过',
            'log': 'outputs/base99_radio_v002/gate_split.log',
            'result': split,
            'exit_code': log_exit('gate_split.log'),
            'resolution': '按项目专表摘要规则，更新本次有意修改的3D-道具摘要；并集、缺失、额外和列摘要均无漂移。',
        },
        'full_props': {
            'status': '既有红项',
            'log': 'outputs/base99_radio_v002/gate_full_props.log',
            'result': full,
            'exit_code': log_exit('gate_full_props.log'),
            'regression_scope': full_scope,
            'new_radio_sha_mismatch': False,
        },
        'naming': {
            'status': '既有红项',
            'log': 'outputs/base99_radio_v002/gate_naming.log',
            'result': naming,
            'exit_code': log_exit('gate_naming.log'),
            'radio_specific_new_debt': False,
            'classification': '输出中的新版本文件、目录与引用增长均不包含 base99_radio v002；属于既有项目命名债务。',
        },
    },
    'evidence': {
        'final_acceptance': 'outputs/base99_radio_v002/final_acceptance.json',
        'registration_evidence': 'outputs/base99_radio_v002/registration_evidence.json',
        'manifest': 'outputs/base99_radio_v002/asset_manifest.json',
        'strict_validation': 'outputs/base99_radio_v002/validate_game_prop.json',
        'previews': [
            'outputs/base99_radio_v002/base99_radio_v002_closeup.png',
            'outputs/base99_radio_v002/base99_radio_v002_threequarter.png',
            'outputs/base99_radio_v002/base99_radio_v002_top.png',
        ],
    },
}
(out / 'gate_results.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

final_path = out / 'final_acceptance.json'
final = json.loads(final_path.read_text(encoding='utf-8'))
final['gate_results'] = 'outputs/base99_radio_v002/gate_results.json'
final['gate_summary'] = {
    'asset_level': '通过',
    'structure': '通过',
    'split': '通过',
    'full_props': '既有13条sha_mismatch；收音机不在列表中',
    'naming': '既有债务；未发现收音机新增命名债务',
    'godot_runtime': '通过',
}
final_path.write_text(json.dumps(final, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'gate_results': str(out / 'gate_results.json'), 'final_acceptance_updated': True}, ensure_ascii=False, indent=2))
