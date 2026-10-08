from pathlib import Path
import json
R=Path.cwd();p=R/'docs/v0.1/MODULE_INDEX.md';s=p.read_text(encoding='utf-8');s='\n'.join(line.replace('v033','v032') if 'PLAYER-STATE / ASSET-PIPELINE / SAVE-PROFILE' in line else line for line in s.split('\n'));p.write_text(s,encoding='utf-8')
B=R/'assets/art/enemies/bosses/enm_boss_monitor002';p=B/'README.md';s=p.read_text(encoding='utf-8').replace('## 当前交付 v032','## 历史试改 v032');p.write_text(s,encoding='utf-8')
g=json.loads((R/'outputs/asset_guard/ENM-BOSS-MONITOR002-3D_enm_boss_monitor002.json').read_text(encoding='utf-8'))
for fn in ['enm_boss_monitor002_transfer_ledger.json','enm_boss_monitor002_transfer_ledger_v033.json']:
 p=B/fn;t=json.loads(p.read_text(encoding='utf-8'));t['duplicate_gate']=g;p.write_text(json.dumps(t,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
