from pathlib import Path
import shutil,subprocess
root=Path.cwd();dest=root/'_scratch/fat_zombie03/retirement_baseline';dest.mkdir(exist_ok=True);backup=root/'_scratch/fat_zombie03/shielded_retirement_backup'
shutil.copy2(root/'project.godot',dest/'project.godot')
for folder in ['src','data']:
 shutil.copytree(root/folder,dest/folder,dirs_exist_ok=True)
 if (backup/folder).exists():shutil.copytree(backup/folder,dest/folder,dirs_exist_ok=True)
cache=dest/'.godot';cache.mkdir(exist_ok=True)
for name in ['global_script_class_cache.cfg','uid_cache.bin']:
 if (root/'.godot'/name).exists():shutil.copy2(root/'.godot'/name,cache/name)
for name in ['assets','scenes','tests','resources','source','addons','.godot/imported']:
 source=root/name;target=dest/name
 if source.exists() and not target.exists():
  target.parent.mkdir(exist_ok=True)
  subprocess.run(['powershell','-NoProfile','-Command',f"New-Item -ItemType Junction -Path '{target}' -Target '{source}' | Out-Null"],check=True,capture_output=True)
print('RETIREMENT_BASELINE_READY')
