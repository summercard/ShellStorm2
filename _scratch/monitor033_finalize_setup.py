from pathlib import Path
import json
R=Path.cwd();B=R/'assets/art/enemies/bosses/enm_boss_monitor002'
s=(R/'_scratch/finalize_monitor032.py').read_text(encoding='utf-8').replace('032','033').replace('Grounded move revision; only target master, prefab and state records updated.','v031 move restored, pedestal roll only reduced 23 to 10 degrees; other motion retained.')
s=s.replace("'preview':'previews/move_v033/monitor_walk.mp4'","'preview':'previews/move_v033/monitor_walk.mp4','baseline_version':'v031','other_move_tracks_unchanged':True")
(R/'_scratch/finalize_monitor033.py').write_text(s,encoding='utf-8')
for fn in ['docs/v0.1/MODULE_INDEX.md','docs/v0.1/design/远征关卡01设计.md']:
 p=R/fn;s=p.read_text(encoding='utf-8').replace('v032','v033').replace('move贴地横移与机身扭转','move沿用老版，仅侧翘由23°减至10°').replace('底座贴地横移、机身左右扭转','老版move，仅减小底座侧翘幅度');p.write_text(s,encoding='utf-8')
p=B/'README.md';s=p.read_text(encoding='utf-8');s='## 当前走路微调 v033\n\n以v031为基础，仅底座侧翘峰值23°减至10°并重算接地高度。其余move轨道及另外15个剪辑完全保留。正式双母版/契约/中转清单为v033；稳定运行时路径不变。预览：`previews/move_v033/monitor_walk.mp4`。v032为前次试改，已被本次替代。\n\n'+s.replace('当前v032','历史v032');p.write_text(s,encoding='utf-8')
p=R/'docs/v0.1/feature_registry.json';v=json.loads(p.read_text(encoding='utf-8'))
# Maintain serialized structure, append evidence only to the existing Boss record.
def walk(x):
 if isinstance(x,dict):
  if x.get('feature_id',x.get('id'))=='BOSS-STAGES':
   for k,val in x.items():
    if isinstance(val,list) and any(isinstance(z,str) and '2026-10-08_boss002_grounded_move' in z for z in val):val.append('docs/v0.1/development/2026-10-08_boss002_reduced_lift.md')
  for val in x.values():walk(val)
 elif isinstance(x,list):
  for val in x:walk(val)
walk(v);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
p=R/'docs/v0.1/development/2026-10-08_boss002_reduced_lift.md';p.write_text('''# Boss002 老版走路幅度微调

FeatureID：BOSS-STAGES / ASSET-PIPELINE。日期：2026-10-08。设计r27，资产v033，游戏版本仍0.1.0。

用户要求回到老版，仅减小参考姿态的底座抬起幅度，不改其它动作。基于v031双母版，通过已打开的Blender MCP制作v033，撤销v032整套走路重做。move仅pedestal_motion位置/旋转曲线变化：侧翘23°→10°，重新计算底面接地高度；原横移、水平旋转、支撑、手臂、手腕、五官和时长保持。哈希逐项验证其余move轨道与另外15个Action不变，运行时其它15剪辑逐值相等。保留v031/v032源文件；静态GLB、状态机、四技能、数值、远征01投放均无改变。

97个整帧/半帧采样：底面Z 0.004961—0.005000米，横移0.460000米，循环闭合误差0；双母版骨架签名一致。基于最新用户要求，将旧贴地零旋转测试替换为10°峰值与底面接地检查，并非为通过放宽旧要求。

独立隔离Godot验收verify_monitor_boss_flow退出0、509项通过；verify_monitor_boss_visual --walk退出0、48帧真实渲染；两者无预期故障和非预期脚本错误。另输出48帧Blender同机位循环预览。未重跑整场远征清房或全项目套件，本次不改该链路。早期接地检查发现原辅助底座网格比主体底面低，改按正式Crescent pedestal实际网格计算后重跑通过。

同步正式Prefab版本、manifest、中转JSON、敌人分账本、制作账本与目标无损基线。复用asset_guard对规范中转文件名的支持；该兼容修复已在前次v032实现。
''',encoding='utf-8')
p=R/'docs/v0.1/development/CHANGELOG.md';s=p.read_text(encoding='utf-8');p.write_text('## 2026-10-08 Boss002 老版走路小改\n\nv033基于v031仅侧翘23°→10°、保持其余动作；[交付与验收](2026-10-08_boss002_reduced_lift.md)。\n\n'+s,encoding='utf-8')
