from pathlib import Path
import shutil,subprocess
root=Path.cwd();dest=root/'_scratch/fat_zombie03/baseline_project';dest.mkdir(exist_ok=True)
shutil.copy2(root/'project.godot',dest/'project.godot')
shutil.copytree(root/'src',dest/'src',dirs_exist_ok=True)
for name in ['src/enemy3d/Enemy3D.gd','src/enemy3d/EnemyAvatar3D.gd','src/enemy3d/MonsterAIManager.gd','src/map/MonsterInjector.gd']:
 result=subprocess.run(['git','show','HEAD:'+name],cwd=root,capture_output=True,check=True)
 (dest/name).write_bytes(result.stdout)
cache=dest/'.godot';cache.mkdir(exist_ok=True)
for name in ['global_script_class_cache.cfg','uid_cache.bin']:
 if (root/'.godot'/name).exists():shutil.copy2(root/'.godot'/name,cache/name)
for name in ['assets','scenes','tests','resources','data','addons','.godot/imported']:
 source=root/name;target=dest/name
 if source.exists() and not target.exists():
  target.parent.mkdir(exist_ok=True)
  # 测试源码复制，资源目录只读复用；不改正式工作区或他人的文件。
  command=f"New-Item -ItemType Junction -Path '{str(target)}' -Target '{str(source)}' | Out-Null"
  subprocess.run(['powershell','-NoProfile','-Command',command],check=True,capture_output=True)
print(dest)
