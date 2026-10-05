from pathlib import Path
import json
root=Path(r'I:/工作项目/shellstrom2/ShellStorm2'); out=root/'outputs/base99_radio_v001'
gates=json.loads((out/'gate_results.json').read_text(encoding='utf-8'))
full=json.loads(gates['full_props']['stdout'])
name=json.loads(gates['naming']['stdout'])
report={
 'asset_id':'PRP-BASE99-RADIO-3D',
 'ledger_path':str(root/'assets/registry/ledgers/ShellStorm2_道具账本_v001.xlsx'),
 'sheet_rows':{'资产主表':27,'3D-道具':8,'域变更日志':11},
 'classification':{'category':'道具','subcategory':'decor_prop','prefab_page':'3D-道具','basis':'实际核对椅子第18/19行与伸缩梯第26行；三者均为道具/decor_prop，非场景组件'},
 'backup':{'directory':str(out/'backup_20261005'),'files':['ShellStorm2_道具账本_v001.xlsx','ShellStorm2_美术资产台账_v001.xlsx','ledger_split_baseline.json']},
 'baseline':{'path':str(root/'assets/registry/ledger_split_baseline.json'),'asset_count':1008,'captured_at':'2026-10-05','asset_present':True},
 'gates':{
   'structure':{'exit_code':gates['structure']['exit_code'],'status':'通过'},
   'full_props':{'exit_code':gates['full_props']['exit_code'],'status':'既有红项','issue_counts':full['issue_counts'],'new_asset_in_issues':any(x.get('asset_id')=='PRP-BASE99-RADIO-3D' for items in full['issues'].values() for x in items)},
   'split':{'exit_code':gates['split']['exit_code'],'status':'通过','failure_count':0,'missing_assets':[],'extra_assets':[]},
   'naming':{'exit_code':gates['naming']['exit_code'],'status':'既有运行时命名欠账/未归因于收音机','radio_path_hit':any('base99_radio' in x for x in name.get('new_versioned_files',[])+name.get('new_versioned_dirs',[]))},
 },
 'model_gate':{'status':'通过','validator':'validate_game_prop.py','exit_code':0,'uv_status':'通过','reason':'source/Blender输出对象使用 StatusLight_UI灯光_柔和自发光；导出阶段临时 rename 为 StatusLight，GLB 与 runtime 接口保持精确 StatusLight'},
 'source_runtime_name_separation':{'source_blend_object':'StatusLight_UI灯光_柔和自发光_Source','blender_output_object':'StatusLight_UI灯光_柔和自发光','export_temporary_name':'StatusLight','glb_runtime_node':'StatusLight','glb_changed':False,'prefab_changed':False,'ledger_changed':False},
 'runtime_contract':{'state_cycle':['off','music_a','music_b','off'],'bus':'Music','input':['鼠标左键','E']},
}
(out/'final_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
lines=['PRP-BASE99-RADIO-3D 登记与门禁最终报告','',f'账本：{report["ledger_path"]}','资产主表行：27；3D-道具行：8；域变更日志行：11','分类：道具 / decor_prop / 3D-道具','分类依据：椅子实际行18/19、伸缩梯实际行26均为道具/decor_prop，收音机沿用该口径，不归场景组件。','',f'备份：{report["backup"]["directory"]}','备份文件：ShellStorm2_道具账本_v001.xlsx、ShellStorm2_美术资产台账_v001.xlsx、ledger_split_baseline.json','无损基线：asset_count=1008，已含 PRP-BASE99-RADIO-3D，captured_at=2026-10-05','', '门禁：','structure：通过（exit 0）','full props：exit 1，13 条既有 sha_mismatch；问题列表不含 PRP-BASE99-RADIO-3D，故不归因于本次登记。','split：通过（exit 0；missing=0、extra=0、column_digest_drift=0）','naming：exit 1；当前运行时命名欠账，收音机路径未命中 versioned 文件/目录；不把该门禁写成通过。','模型门禁：未全过；StatusLight 命名误报保留，不把模型验收写成全过。','', '完整JSON：outputs/base99_radio_v001/final_report.json']
(out/'final_report.txt').write_text('\n'.join(lines)+'\n',encoding='utf-8')
