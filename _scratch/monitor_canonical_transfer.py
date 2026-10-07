from pathlib import Path
R=Path.cwd();B=R/'assets/art/enemies/bosses/enm_boss_monitor002'
for name in ['character_transfer_ledger_v031.json','character_transfer_ledger.json']:
 p=B/name;target=B/name.replace('character_transfer_ledger','enm_boss_monitor002_transfer_ledger')
 if p.exists():p.rename(target)
for name in ['_scratch/monitor_finalize.py','_scratch/monitor_prepare_qa.py','_scratch/monitor_ledger/changes.json','_scratch/monitor_ledger_prepare.py','assets/art/enemies/bosses/enm_boss_monitor002/README.md']:
 p=R/name;p.write_text(p.read_text(encoding='utf-8').replace('character_transfer_ledger','enm_boss_monitor002_transfer_ledger'),encoding='utf-8')
print('Transfer filenames now follow the character pipeline slug convention')
