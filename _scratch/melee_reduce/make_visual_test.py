from pathlib import Path
root=Path(__file__).resolve().parents[2]
source=(root/'tests/verification/verify_fat_zombie03_death_visibility.gd').read_text(encoding='utf-8')
source=source.replace('fat_zombie03_death_fix','melee_zombie_reduction').replace('FAT_ZOMBIE03_DEATH_VISIBILITY','MELEE_ZOMBIE_DEATH_VISIBILITY')
source=source.replace('load("res://scenes/enemies/fat_zombie03.tscn").instantiate() as Enemy3D','load("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn").instantiate() as Enemy3D')
source=source.replace('\tadd_child(enemy)\n','\tadd_child(enemy)\n\tenemy.configure_from_enemy_data({"enemy_type":"melee_chaser", "name":"小僵尸"})\n')
source=source.replace('camera.size = 4.7','camera.size = 3.4').replace('Vector3(0, 0.8, 0)','Vector3(0, 0.55, 0)')
start=source.index('\tvar visual = enemy.avatar._formal_normal_root\n')
end=source.index('\tawait shot("settled")',start)
source=source[:start]+source[end:]
(root/'tests/verification/verify_melee_zombie_death_visibility.gd').write_text(source,encoding='utf-8')
scene=(root/'tests/verification/verify_fat_zombie03_death_visibility.tscn').read_text(encoding='utf-8').replace('verify_fat_zombie03_death_visibility','verify_melee_zombie_death_visibility')
(root/'tests/verification/verify_melee_zombie_death_visibility.tscn').write_text(scene,encoding='utf-8')
f=root/'scripts/run_verification_suite.sh';s=f.read_text(encoding='utf-8');s=s.replace('  verify_fat_zombie03_death_visibility\n','  verify_fat_zombie03_death_visibility\n  verify_melee_zombie_death_visibility\n');f.write_text(s,encoding='utf-8')
