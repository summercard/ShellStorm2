from pathlib import Path
import shutil, json, subprocess
R=Path.cwd();B=R/'assets/art/enemies/bosses/enm_boss_monitor002'
shutil.copy2(B/'enm_boss_monitor002_transfer_ledger_v031.json',B/'enm_boss_monitor002_transfer_ledger.json')
p=R/'source/art/whitebox/tower_zones/expedition_01/v001/data/floors/floor_00.json';t=p.read_text(encoding='utf-8')
if '"boss_content_id": "boss_monitor002"' not in t:
 assert '"key": "boss",' in t
 p.write_text(t.replace('"key": "boss",','"key": "boss",\n      "boss_content_id": "boss_monitor002",',1),encoding='utf-8')
p=R/'scripts/run_verification_suite.sh';t=p.read_text(encoding='utf-8')
for array,name in [('core_scenes','verify_monitor_boss_flow'),('visual_scenes','verify_monitor_boss_visual')]:
 if name not in t:t=t.replace(array+'=(\n',array+'=(\n  '+name+'\n',1)
p.write_text(t,encoding='utf-8')
D=R/'_scratch/monitor_qa_project';D.mkdir(exist_ok=True)
for p in R.iterdir():
 if p.is_dir() and p.name not in ['_scratch','.git']:
  dest=D/p.name
  if not dest.exists():
   command="New-Item -ItemType Junction -Path '"+str(dest).replace("'","''")+"' -Value '"+str(p).replace("'","''")+"' | Out-Null"
   subprocess.run(['powershell','-NoProfile','-Command',command],check=True)
t=(R/'project.godot').read_text(encoding='utf-8').replace('[application]','[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="ShellStorm2_monitor_qa_20261006"',1)
(D/'project.godot').write_text(t,encoding='utf-8')
shutil.copy2(R/'icon.svg',D/'icon.svg')
print('Isolated QA project configured before Autoload')
