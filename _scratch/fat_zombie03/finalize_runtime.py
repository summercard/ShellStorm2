import json,subprocess,sys
from pathlib import Path
root=Path.cwd();p=root/'_scratch/fat_zombie03';out=root/'outputs/fat_zombie03_integration';record='docs/v0.1/development/2026-10-03_fat_zombie03_runtime_binding.md';design='docs/v0.1/design/胖子僵尸03运行配置.md'
def replace(path,old,new):
 f=root/path;s=f.read_text(encoding='utf-8');assert old in s,(path,old);f.write_text(s.replace(old,new),encoding='utf-8')
replace('docs/v0.1/design/怪物设计.md','03当前完成模型骨架修正、512贴图、自然张手的3.2秒待机、2秒行走与1.2秒跑步循环、2.5秒抱扑攻击，独立Prefab默认播放idle；13段动作源齐全，完整AI状态绑定与投放尚未完成。属性数值以设计页的首版建议为待接入配置，不覆盖现有怪物原型。','03现为v011正式可调用怪物：2.2米、512贴图、13段动作绑定Enemy3D共用12态；生命696、伤害19、巡逻0.30/追击0.60m/s，拍合单次命中、上半身轻击与2.6秒死亡形变已验收。调用ID `fat_zombie03`，固定波次/触发盒及独立实体可用；见[运行配置](胖子僵尸03运行配置.md)，未加入既有随机池。')
replace('docs/v0.1/06_技术施工_怪物精英与Boss.md','模型骨架与512贴图已修正，idle、walking、running与attack已制作并验收，13段动作源齐全、完整状态绑定待完成，设计属性尚未投放。','v011已完成13动画/12态绑定、厚血慢速属性、碰撞与刷怪ID，专项与真实渲染通过；见[运行配置](design/胖子僵尸03运行配置.md)。可显式投放，既有随机池未改变。')
replace('docs/v0.1/design/README.md','13段动作中idle、walking、running与attack已制作并验收，13段动作源齐全；资产事实同步敌人账本。','13段动作和12态绑定已完成，参见[运行配置](胖子僵尸03运行配置.md)；资产事实同步敌人账本。')
f=root/'docs/v0.1/MODULE_INDEX.md';s=f.read_text(encoding='utf-8');lines=s.splitlines();lines=[('ASSET-PIPELINE / ENEMY-AI [胖子僵尸03](design/胖子僵尸03动作设计.md)：v011，2.2m/512贴图、13动画/12态绑定；独立kind `fat_zombie03`可在实体场景、固定波次和触发盒调用，厚血慢速/拍合/局部轻击/死亡已验收。见[运行配置](design/胖子僵尸03运行配置.md)及[运行交付](development/2026-10-03_fat_zombie03_runtime_binding.md)。' if line.startswith('ASSET-PIPELINE / ENEMY-AI [胖子僵尸03]') else line) for line in lines];f.write_text('\n'.join(lines)+'\n',encoding='utf-8')
f=root/'docs/v0.1/feature_registry.json';lines=f.read_text(encoding='utf-8').splitlines(keepends=True)
for i,line in enumerate(lines):
 if '"feature_id":"ENEMY-AI"' not in line and '"feature_id":"ASSET-PIPELINE"' not in line:continue
 data=json.loads(line.strip().rstrip(','))
 for key,val in [('development_records',record),('design_docs',design)]:
  if val not in data[key]:data[key].append(val)
 verification={'kind':'scene','id':'verify_fat_zombie03'}
 if verification not in data['verification']:data['verification'].append(verification)
 lines[i]='    '+json.dumps(data,ensure_ascii=False,separators=(',',':'))+',\n'
f.write_text(''.join(lines),encoding='utf-8')
f=root/'docs/v0.1/development/CHANGELOG.md';s=f.read_text(encoding='utf-8');s=s.replace('# 游戏设计文档 v0.1 变更记录','# 游戏设计文档 v0.1 变更记录\n\n## 2026-10-03｜胖子僵尸03正式运行绑定v011\n\n- 全面源/导入检查后新增fat_zombie03，共用12态绑定13动画、厚血慢速数值、拍合时序/方向锁定、局部轻击和2.6秒死亡回收。\n- 专项150项、攻击循环负向对照及Forward+四图通过，既有普通怪/AI/光照回归通过；敌人账本与内容库更新。见[运行交付](2026-10-03_fat_zombie03_runtime_binding.md)。',1);f.write_text(s,encoding='utf-8')
f=root/'assets/art/enemies/normal_enemy_3d/fat_zombie03/README.md';f.write_text('''# 胖子僵尸03

AssetID `ENM-NORMAL-FAT-ZOMBIE03`，源编号03，调用ID `fat_zombie03`。当前v011，模型/骨架/512贴图、13动画与Enemy3D共用12态正式接入。

模型母版 `source/model/enm_normal_fat_zombie03_model_v003.blend`；动作母版 `source/animation/enm_normal_fat_zombie03_animation_v008.blend`。2867顶点、5690三角、1材质、66骨（36核心+30附加）；Root无父级、Hip挂Root，对象Scale=1。源高3.142857米×0.7=游戏高2.2米。独立骨架签名，不直接共享其他怪物Action。v001骨架有尺寸缺陷，只保留历史。

纯视觉包 `runtime/enm_normal_fat_zombie03_root_top3d.tscn`无碰撞/AI/伤害；`fat_zombie03_formal_visual.gd`仅采样导入动作。实体 `res://scenes/enemies/fat_zombie03.tscn`继承共用Enemy3D。MonsterInjector固定波次/触发盒按ID调用，掉落与倍率沿用共用路径。

基准生命696、伤害19，巡逻0.30/追击0.60米每秒。前摇1.2秒、拍合一次结算、收势1.3秒；F30锁朝向，F36命中须1.55米内、前向半角60度且无墙阻挡。轻击上半身混合，重击硬直0.8秒。死亡立即清碰撞/AI组，原缩放播放2.6秒后回收。

idle/walking/running循环；其他10段单次。巡逻走路，追击/搜索/归位跑步；苏醒、起停、原地转身按状态和朝向触发。状态切换0.1秒导入姿势混合，攻击连续采样。玩法根位移/yaw归Enemy3D。腹部BellyGroundCompression死亡接地时压扁/展开，回弹时部分恢复，非死亡复位零；是离线表现，不是软体物理。hit_light经post_import去除默认下半身轨道，局部替换，不是加法差量。

设计主源 `docs/v0.1/design/胖子僵尸03动作设计.md`及`胖子僵尸03运行配置.md`；源审计、专项150项、负向对照、真实Forward+四图在`outputs/fat_zombie03_integration/`。验收 `tests/verification/verify_fat_zombie03.tscn`；可玩预览 `tests/verification/preview_fat_zombie03.tscn`（R重生/K死亡）。

历史预览 `previews/locomotion_v003/`、`attack_v005/`、`complete_v006/`、`death_v007/`、`belly_v008/`只代表当时版本。此怪未加入既有关卡随机池，可显式投放；专属脚步/拍合新音效未制作。
''',encoding='utf-8')
commands={'structure':['scripts/check_asset_registry.py','--scope','structure'],'full':['scripts/check_asset_registry.py','--scope','full','--ledger','enemies','--json-output',str(out/'ledger_after.json')],'split':['tools/asset_pipeline/verify_ledger_split.py'],'guard':['scripts/asset_guard.py','assets/art/enemies/normal_enemy_3d/fat_zombie03','--classify','version_increment'],'naming':['scripts/check_asset_runtime_naming.py'],'docs':['scripts/check_documentation_contracts.py'],'refs':['scripts/check_ledger_refs.py']}
results={}
for name,args in commands.items():
 r=subprocess.run([sys.executable,*args],cwd=root,capture_output=True);results[name]=r.returncode;(out/f'gate_{name}.log').write_text(r.stdout.decode('utf-8',errors='replace')+r.stderr.decode('utf-8',errors='replace'),encoding='utf-8');print(name,r.returncode,flush=True)
before=json.loads((p/'integration_ledger_before.json').read_text(encoding='utf-8'));after=json.loads((out/'ledger_after.json').read_text(encoding='utf-8'))
def external(d):return {k:[v for v in rows if v.get('asset_id')!='ENM-NORMAL-FAT-ZOMBIE03'] for k,rows in d['issues'].items()}
results['other_ledger_issues_unchanged']=external(before)==external(after)
results['target_has_ledger_issues']=any(v.get('asset_id')=='ENM-NORMAL-FAT-ZOMBIE03' for rows in after['issues'].values() for v in rows)
(out/'gates.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
assert all(results[k]==0 for k in ['structure','split','guard']) and results['other_ledger_issues_unchanged'] and not results['target_has_ledger_issues']
print('FAT_ZOMBIE03_RUNTIME_FINALIZED')
