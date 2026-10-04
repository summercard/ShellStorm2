from pathlib import Path
import shutil
root=Path(__file__).resolve().parents[2];pkg=root/'assets/art/enemies/normal_enemy_3d/fat_zombie03';backup=Path(__file__).parent/'idle_v001_backup'
imp=pkg/'components/enm_normal_fat_zombie03_visual_top3d.glb.import'
if not (backup/imp.name).exists():shutil.copy2(imp,backup/imp.name)
s=(backup/imp.name).read_text(encoding='utf-8');assert '_subresources={}' in s
s=s.replace('_subresources={}','_subresources={\n"animations": {\n"idle": {\n"settings/loop_mode": 1\n}\n}\n}')
imp.write_text(s,encoding='utf-8')
print('IDLE_LOOP_IMPORT_CONFIGURED')
