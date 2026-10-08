"""背包验收入口；在Autoload启动前隔离所有用户目录，保留独立退出码。"""
from pathlib import Path
import os, sys, subprocess, json
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'outputs/backpacks_20261008'
GODOT=Path('I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe')
PY=Path('C:/Users/zhuangmenghong/.workbuddy/binaries/python/envs/default/Scripts/python.exe')
mode=sys.argv[1]
commands={
    'import':[str(GODOT),'--headless','--editor','--import','--path',str(ROOT)],
    'equipment':[str(GODOT),'--headless','--path',str(ROOT),'res://tests/verification/verify_backpack_equipment_flow.tscn'],
    'render':[str(GODOT),'--path',str(ROOT),'--rendering-method','forward_plus','--resolution','1440x900','res://tools/asset_pipeline/render_backpack_acceptance.tscn'],
    'icons':[str(GODOT),'--path',str(ROOT),'--rendering-method','forward_plus','res://tests/verification/verify_item_model_icon_framing_visual.tscn'],
    'structure':[str(PY),'-I','-X','utf8',str(ROOT/'scripts/check_asset_registry.py'),'--project-root',str(ROOT),'--scope','structure','--ledger','props'],
    'full':[str(PY),'-I','-X','utf8',str(ROOT/'scripts/check_asset_registry.py'),'--project-root',str(ROOT),'--scope','full','--ledger','props'],
    'split':[str(PY),'-I','-X','utf8',str(ROOT/'tools/asset_pipeline/verify_ledger_split.py'),'--project-root',str(ROOT)],
    'naming':[str(PY),'-I','-X','utf8',str(ROOT/'scripts/check_asset_runtime_naming.py')],
    'docs':[str(PY),'-I','-X','utf8',str(ROOT/'scripts/check_documentation_contracts.py')],
}
OUT.mkdir(parents=True,exist_ok=True)
env=os.environ.copy()
for variable in ['APPDATA','LOCALAPPDATA','USERPROFILE','HOME','XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:
    path=OUT/'isolated_userdata'/mode/variable.lower()
    path.mkdir(parents=True,exist_ok=True)
    env[variable]=str(path)
env['PYTHONUTF8']='1'
env['PATH']=str(PY.parent)+os.pathsep+env['PATH']
try:
    with (OUT/(mode+'.log')).open('w',encoding='utf-8') as log:
        process=subprocess.run(commands[mode],cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=100)
    text=(OUT/(mode+'.log')).read_text('utf-8',errors='replace')
    errors=[line for line in text.splitlines() if 'ERROR:' in line or 'SCRIPT ERROR:' in line or 'leaked at exit' in line]
    result={'command':commands[mode],'exit_code':process.returncode,'errors':errors,'user_data_isolated_before_autoload':True}
except subprocess.TimeoutExpired as exc:
    text=(OUT/(mode+'.log')).read_text('utf-8',errors='replace')
    result={'command':commands[mode],'exit_code':124,'errors':['进程超过验收上限，已终止'],'user_data_isolated_before_autoload':True}
(OUT/(mode+'_result.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False,indent=2))
print(text[-6000:])
sys.exit(result['exit_code'] or (3 if result['errors'] else 0))
