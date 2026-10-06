import hashlib
import json
import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path
from PIL import Image, ImageChops

P = Path('I:/工作项目/shellstrom2/ShellStorm2')
O = P / 'outputs/base99_radio_v003'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
def text(path):
    data = path.read_bytes()
    try:
        return data.decode('utf-8')
    except UnicodeDecodeError:
        return data.decode('gb18030')

load = lambda name: json.loads(text(O / name))
write = lambda name, data: (O / name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def git(*args):
    return subprocess.run(['git', '-C', str(P), *args], capture_output=True, check=True).stdout

opt = load('optimization_evidence.json')
fidelity = load('fidelity_evidence.json')
assert 'RADIO_REEXPORT_BYTE_IDENTICAL_OK' in (O / 'reexport_verified.log').read_text(encoding='utf-8')
assert load('validate_game_prop.json')['passed']
assert all(v['passed'] for v in fidelity['scale_checks'].values())
assert fidelity['component_output_normalization']['normalized_vertex_sets_match']
comparisons = {}
for view in fidelity['fixed_views']:
    before = Image.open(O / f'fidelity_source_{view}.png').convert('RGB')
    after = Image.open(O / f'fidelity_optimized_{view}.png').convert('RGB')
    diff = ImageChops.difference(before, after)
    maximum = max(v[1] for v in diff.getextrema())
    assert maximum <= 1
    comparisons[view] = {'max_channel_delta_8bit': maximum, 'changed_pixels': sum(pixel != (0, 0, 0) for pixel in diff.getdata()), 'pixels': before.width * before.height}
fidelity['fixed_render_comparison'] = comparisons
fidelity['render_comparison_pending_pixel_audit'] = False
fidelity['render_review'] = '正/背/侧/游戏视角轮廓、阴影及细节已读取复核；源与优化几何/UV输出保持一致，Eevee差异最大1/255，未宣称像素逐字节相同。'
write('fidelity_evidence.json', fidelity)

manifest = load('asset_manifest.json')
glb = Path(manifest['component_glb'])
blob = glb.read_bytes()
magic, version, size = struct.unpack_from('<III', blob)
assert magic == 0x46546C67 and version == 2 and size == len(blob)
length, chunk_type = struct.unpack_from('<II', blob, 12)
assert chunk_type == 0x4E4F534A
scene = json.loads(blob[20:20 + length])
assert not scene.get('images') and not scene.get('textures')
assert not scene.get('animations') and not scene.get('skins') and not scene.get('cameras')
assert sorted(n['name'] for n in scene['nodes']) == ['ItemRoot', 'StatusLight', 'Visual']
triangles = sum(scene['accessors'][x['indices']]['count'] // 3 for m in scene['meshes'] for x in m['primitives'])
assert triangles == 1116
for mesh in scene['meshes']:
    for primitive in mesh['primitives']:
        assert primitive.get('mode', 4) == 4
        assert 'NORMAL' in primitive['attributes'] and 'TEXCOORD_0' in primitive['attributes']
        assert 'TEXCOORD_1' not in primitive['attributes']
assert all(n.get('scale', [1, 1, 1]) == [1, 1, 1] for n in scene['nodes'])
import_path = glb.with_suffix(glb.suffix + '.import')
assert git('ls-files', '--', str(import_path.relative_to(P)))
palette_import = P / 'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png.import'
assert git('ls-files', '--', str(palette_import.relative_to(P)))
assert 'compress/mode=0' in palette_import.read_text(encoding='utf-8') and 'mipmaps/generate=false' in palette_import.read_text(encoding='utf-8')
assert 'gltf/embedded_image_handling=0' in import_path.read_text(encoding='utf-8')
glb_report = {'passed': True, 'sha256': sha(glb), 'images': 0, 'textures': 0, 'triangles': triangles, 'nodes': scene['nodes'], 'meshes': len(scene['meshes']), 'materials': len(scene['materials']), 'single_uv_channel': True, 'root_scale_one': True, 'import_contract_tracked': True, 'shared_palette_import_tracked_lossless_no_mipmaps': True}
write('glb_structure_evidence.json', glb_report)

before_text = text(O / 'gate_full_props_before.log')
after_text = text(O / 'gate_full_props.log')
before = json.loads(before_text[before_text.index('{'):])['issues']['sha_mismatch']
after = json.loads(after_text[after_text.index('{'):])['issues']['sha_mismatch']
assert [row for row in before if row['asset_id'] != manifest['asset_id']] == after
registration = load('registration_evidence.json')
old_baseline = json.loads((O / 'backup_before_registration/ledger_split_baseline.json').read_text(encoding='utf-8'))
new_baseline = json.loads((P / 'assets/registry/ledger_split_baseline.json').read_text(encoding='utf-8'))
assert registration['other_props_row_digests_unchanged'] and registration['other_baseline_asset_fingerprints_unchanged'] and registration['data_validations_unchanged']
for key in old_baseline:
    if isinstance(old_baseline[key], dict) and manifest['asset_id'] in old_baseline[key]:
        assert {k:v for k,v in old_baseline[key].items() if k != manifest['asset_id']} == {k:v for k,v in new_baseline[key].items() if k != manifest['asset_id']}
ledger_evidence = {'radio_sha_issue_removed': True, 'before_issue_count': len(before), 'after_issue_count': len(after), 'remaining_13_issue_records_exactly_unchanged': True, 'remaining_issues': after, 'other_row_digests_and_baseline_asset_fingerprints_unchanged': True, 'formula_and_data_validation_evidence': 'registration_evidence.json', 'ledger_sha256_current': sha(Path(registration['ledger'])), 'registration_ledger_hash_still_matches': sha(Path(registration['ledger'])) == registration['ledger_sha256']}
assert ledger_evidence['registration_ledger_hash_still_matches']
write('ledger_evidence.json', ledger_evidence)

# 两个正式布局只允许收音机节点块发生变化；其余家具、墙和灯光逐字保持。
layouts = ['assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d.tscn', 'assets/art/environments/tower_zones/base/runtime/zone_base.tscn']
def remove_radio_block(text):
    return re.sub(r'\[node name="99F床边桌独立收音机"[^\n]*\n.*?(?=\n\[node|\Z)', '', text, flags=re.S).replace('\r\n', '\n')
for path in layouts:
    original = git('show', f'HEAD:{path}').decode('utf-8')
    current = (P / path).read_text(encoding='utf-8')
    assert remove_radio_block(original) == remove_radio_block(current)

checks = []
for name, marker in [('placement_acceptance_final.log', 'PLACEMENT_ACCEPTED=true'), ('radio_window_registered_final.log', 'BASE99_RADIO_OK'), ('facility_floor_regression.log', 'TOWER_BASE_FACILITY_PERSISTENT_OK'), ('native_visual.log', 'emission_enabled=false energy=0.0')]:
    assert marker in (O / name).read_text(encoding='utf-8')
    result = subprocess.run([sys.executable, '-I', str(P / 'scripts/check_verification_log.py'), str(O / name)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    checks.append({'log': name, 'success_marker': marker, 'engine_error_and_leak_gate_exit': result.returncode})
write('runtime_log_audit.json', checks)

for key in ['source_blend', 'input_source_preserved', 'component_glb']:
    manifest[key] = Path(manifest[key]).as_posix()
manifest['optimized_blend'] = Path(opt['optimized_path']).as_posix()
manifest['hashes_sha256'] = {'source': sha(Path(opt['source_path'])), 'optimized': sha(Path(opt['optimized_path'])), 'glb': sha(glb), 'prefab': sha(P / manifest['runtime_prefab_target'])}
assert manifest['hashes_sha256']['source'] == opt['source_sha256_after_optimization']
assert manifest['hashes_sha256']['optimized'] == opt['optimized_sha256']
manifest['palette']['path'] = Path(manifest['palette']['path']).as_posix()
manifest['palette'].update({'body_cell': [1,4], 'metal_cell': [1,6], 'accent_cell': [2,7], 'status_cell': [5,5], 'cell_origin': '左下起算，0-based'})
manifest['placement'] = {'reference_image': 'C:/Users/zhuangmenghong/.workbuddy/clipboard-images/clipboard-2026-10-06T03-20-26-932Z-6a664213.png', 'support_furniture': '46_BATTERY模块收纳箱_资产包', 'layout_local_position_m': [-1.95,6.97,-13.87143], 'tower_world_position_m': [-1.95,-5.03,-8.87143], 'yaw_degrees': 10, 'root_scale': [1,1,1], 'support_samples': {'covered': 121, 'total': 121, 'height_tolerance_m': .01, 'surface_y_range_m': [-5.036883,-5.03]}, 'obstacle_check_scope': 'facility/Art可见MeshInstance3D，三角形/局部包络盒SAT；非全域物理体或MultiMesh穷举', 'non_radio_layout_text_unchanged_vs_head': True, 'formal_layouts': layouts}
manifest['scope'] = {'included': ['v003原始源与独立optimized文件', '稳定GLB与导入配置', '两个正式layout的收音机摆位', '独立碰撞、点击区、音源、Tooltip及交互锚点', 'StatusLight自身状态反馈', '真实鼠标/E和楼层隔离验收', '道具账本、专表、baseline最小事务', '原生PNG与JSON验收证据'], 'excluded': ['家具/墙/灯光/公共色盘/全场曝光修改', '音乐内容或状态循环规则修改', '其他资产红项修复', '操作用户已有Blender/Godot会话']}
manifest['status_light_node_path'] = 'GLB接口ItemRoot/StatusLight；Prefab通过find_child("StatusLight", true, false)解析导入层级'
manifest['palette']['sha256'] = sha(Path(manifest['palette']['path']))
manifest['evidence'] = ['optimization_evidence.json','fidelity_evidence.json','glb_structure_evidence.json','ledger_evidence.json','registration_evidence.json','final_acceptance.json','testlogs.json']
write('asset_manifest.json', manifest)

naming = load('gate_naming_details.json')
assert not any('base99_radio' in path for key in ['new_versioned_files','new_versioned_dirs','new_backup_residue'] for path in naming[key])
doc = load('documentation_gate_after.log')
assert not any('unregistered: verify_base99_radio' in issue for issue in doc['issues'])
commands = [
 {'name':'最终正式导入','command':'APPDATA=C:/tmp/ss2_appdata_base99_target_probe godot --headless --path <project> --import','log':'godot_import_final.log','exit_code':0},
 {'name':'最终源几何与固定四视角','command':'blender --background --factory-startup --python _scratch/audit_base99_radio_v003_fidelity.py','log':'fidelity_render_final.log','result':'通过，逐顶点2倍与四视角差异≤1/255'},
 {'name':'重开优化文件重导出','command':'blender --background --factory-startup --python _scratch/reexport_base99_radio_v003_verified.py','log':'reexport_verified.log','result':'通过，GLB逐字节不变'},
 {'name':'摆位独立探针','command':'APPDATA=C:/tmp/ss2_appdata_base99_target_probe godot --headless --path <project> --scene res://tests/verification/probe_base99_radio_v003_placement.tscn','log':'placement_acceptance_final.log','result':'通过，PLACEMENT_ACCEPTED=true'},
 {'name':'真实窗口鼠标/E','command':'APPDATA=C:/tmp/ss2_appdata_base99_target_probe godot --path <project> --scene res://tests/verification/verify_base99_radio.tscn','log':'radio_window_registered_final.log','exit_code':0},
 {'name':'设施楼层回归','command':'APPDATA=C:/tmp/ss2_appdata_base99_target_probe godot --headless --path <project> --scene res://tests/verification/verify_tower_base_facility_persistent_flow.tscn','log':'facility_floor_regression.log','result':'通过，TOWER_BASE_FACILITY_PERSISTENT_OK'},
 {'name':'严格模型验收','command':'blender --background --factory-startup <source_v003> --python <skill>/scripts/validate_game_prop.py -- --max-materials 4 --shared-palette <palette> --json <output>','log':'strict_validate_clean.log','result':'通过，factory-startup禁用用户插件，validate_game_prop.json passed=true'},
 {'name':'结构门禁','command':'python -I scripts/check_asset_registry.py --project-root <project> --scope structure','log':'gate_structure.log','exit_code':0},
 {'name':'道具全量门禁','command':'python -I scripts/check_asset_registry.py --project-root <project> --scope full --ledger props','log':'gate_full_props.log','exit_code':1,'result':'13个非radio既有SHA红项，逐记录未变'},
 {'name':'分账本基线门禁','command':'python -I tools/asset_pipeline/verify_ledger_split.py --project-root <project>','log':'gate_split.log','exit_code':0},
 {'name':'命名门禁','command':'python -I scripts/check_asset_runtime_naming.py --json','log':'gate_naming_details.json','exit_code':1,'result':'非radio既有文件/目录和引用红项，未扩表接受'},
 {'name':'文档门禁','command':'python -I scripts/check_documentation_contracts.py','log':'documentation_gate_after.log','exit_code':1,'result':'radio已登记visual组，剩余4个非radio未登记测试'},
 {'name':'headless鼠标诊断','command':'godot --headless --path <project> --scene res://tests/verification/verify_base99_radio.tscn','log':'radio_headless_final.log','exit_code':1,'result':'headless鼠标派发不执行；保留失败证据，正式登记visual_scenes并以带窗口测试验收'},
]
write('testlogs.json', {'project_root':P.as_posix(),'python':sys.executable,'tests':commands,'runtime_log_audit':checks,'full_project_suite_executed':False})
acceptance = {'asset_id':manifest['asset_id'],'version':'v003','overall':'收音机专项通过；全项目门禁存在非本次资产红项','radio_acceptance_passed':True,'project_all_gates_passed':False,'faces':598,'triangles':1116,'dimensions_width_depth_height_m':[.828,.456,.822],'hashes_sha256':manifest['hashes_sha256'],'placement':manifest['placement'],'passed_checks':['v002游戏输出及制作组件各轴2倍逐顶点验证','根与输出scale=1','制作组件按既有归一化与输出双向顶点吻合','598/598逐面PaletteUV合规、四材质外链Closest','独立optimized另存、重开、源保护、最终重导GLB逐字节不变','固定四视角优化前后保真','GLB零图片/纹理且稳定接口与1116三角形','正式Godot公共色盘导入契约已追踪','121/121柜顶采样及可见美术三角形净空','两个正式layout仅收音机块改变','真实窗口鼠标与E状态循环、遮挡/距离/战斗限制','离开99F停止收音机与恢复天台音乐','设施楼层回归','原生off/A/B状态截图、机身不自发光、off能量0','道具账本与baseline非授权资产指纹不变','结构与split门禁'],'warnings':['柜顶略倾斜，121点支撑判据使用0.01m高度容差；不声明平底与倾斜面零高差贴合。','净空检查覆盖facility/Art可见MeshInstance3D，不代表全域物理体或MultiMesh穷举。','四个其他基地组件存在公共色盘UID失效警告，仍按文本路径加载；未修改这些组件。','headless鼠标诊断失败已保留，radio测试登记为真实渲染器visual组。'],'remaining_project_issues':{'props_sha_mismatch':13,'naming_new_files_vs_debt':len(naming['new_versioned_files']),'naming_new_directories_vs_debt':len(naming['new_versioned_dirs']),'documentation_unregistered_non_radio_tests':4},'not_executed':['全项目core/full/visual套件；本次仅运行收音机相关专项及列明门禁','人工硬件鼠标键盘操作（本次为Input.parse_input_event真实引擎事件派发）'],'deliverables':['attic_full.png','radio_off_closeup.png','radio_a_closeup.png','radio_b_closeup.png','asset_manifest.json','final_acceptance.json','testlogs.json','ledger_evidence.json'],'no_markdown_created':True}
write('final_acceptance.json', acceptance)
print('RADIO_V003_ACCEPTANCE_PACKAGED_OK')
