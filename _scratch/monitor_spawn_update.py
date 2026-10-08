from pathlib import Path
import json,shutil
from openpyxl import load_workbook
R=Path.cwd();D=R/'_scratch/monitor_spawn_ledger';D.mkdir(exist_ok=True)
note='显示器Boss由正式触发盒生成于房间中心（局部X/Z=0），初始面向南方（世界+Z）。移动速度由1.204提高至3.612米/秒（3倍；内容speed=123.84）。10米激活及6.4秒出场规则保持。'
for name in ['Boss002显示器技能设计.md','远征关卡01设计.md']:
 p=R/'docs/v0.1/design'/name;s=p.read_text(encoding='utf-8');s=s.replace('移动1.204m/s','移动3.612m/s');s+='\n\n### Boss出生位置与移动速度\n\n'+note+'\n';p.write_text(s,encoding='utf-8')
p=R/'docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx';w=load_workbook(p)
assert w['怪物与Boss']['A17'].value=='boss_monitor002'
jobs=[{'path':str(p),'sheets':{'怪物与Boss':{'E17':3.612,'O17':str(w['怪物与Boss']['O17'].value)+'；'+note}}}]
(D/'changes.json').write_text(json.dumps(jobs,ensure_ascii=False),encoding='utf-8')
for name in ['edit.mjs','merge.py']:
 (D/name).write_text((R/'_scratch/monitor035_ledger'/name).read_text(encoding='utf-8').replace('_scratch/monitor035_ledger','_scratch/monitor_spawn_ledger'),encoding='utf-8')
p=R/'docs/v0.1/development/CHANGELOG.md';p.write_text('## 2026-10-08 Boss002出生与移速\n\n'+note+' [验收记录](2026-10-08_boss002_spawn_speed.md)。\n\n'+p.read_text(encoding='utf-8'),encoding='utf-8')
