from pathlib import Path
import json,shutil,sys
root=Path.cwd();backup=root/'_scratch/fat_zombie03/shielded_retirement_backup';backup.mkdir(exist_ok=True)
# 备份目录在 Godot 工程内，若被编辑器扫描会与 src/ 抢注同名全局类（Enemy3D 等）而报
# "Class hides a global script class"。放 .gdignore 让引擎整目录跳过。
(backup/'.gdignore').touch(exist_ok=True)
def save(path,s):
 p=root/path;b=backup/path;b.parent.mkdir(parents=True,exist_ok=True)
 if not b.exists():shutil.copy2(p,b)
 p.write_text(s,encoding='utf-8')
# 先冻结现行规则，再改实际出怪入口。数量、时序与权重不变。
design='docs/v0.1/design/胖子僵尸03运行配置.md';s=(root/design).read_text(encoding='utf-8')
s=s.replace('不会擅自加入已有随机关卡池。','按用户最新指令，胖子僵尸接替壳甲卫兵：远征纵列与桥心盒、默认随机池、锈炉与深渊主题池、守卫缺省类型均使用fat_zombie03，原数量、延迟和权重保留。shielded退出新刷怪白名单及编辑器选项，旧存档兼容代码保留；未实装的壳甲精英设计继续保留，不作为现行普通怪投放。')
save(design,s)
for path in ['data/spawn_boxes/box_corridor_column.json','data/spawn_boxes/box_bridge_center.json']:
 s=(root/path).read_text(encoding='utf-8').replace('"shielded"','"fat_zombie03"').replace('壳甲','胖子僵尸');save(path,s)
for path in ['data/map_themes/rust_foundry.tres','data/map_themes/abyss_archive.tres']:
 save(path,(root/path).read_text(encoding='utf-8').replace('"shielded"','"fat_zombie03"'))
path='src/map/MonsterInjector.gd';s=(root/path).read_text(encoding='utf-8')
s='\n'.join(line for line in s.split('\n') if not line.startswith('\t"shielded":'))
s=s.replace('"shielded"','"fat_zombie03"');save(path,s)
path='src/map/SpawnBoxCatalog.gd';s=(root/path).read_text(encoding='utf-8').replace('普通怪 7 种','普通怪 6 种').replace('\t"shielded", "exploder", "ambusher",','\t"exploder", "ambusher",').replace('壳甲','胖子僵尸');save(path,s)
path='src/enemy3d/Enemy3D.gd';s=(root/path).read_text(encoding='utf-8');old='@export_enum("fat_zombie03", "melee_chaser", "ranged_caster", "summoner", "shielded", "exploder", "ambusher", "boss")';assert old in s;s=s.replace(old,old.replace(', "shielded"',''))
s=s.replace('const PROFILES := {','# shielded仅为旧存档/历史行为测试保留，现行MonsterInjector与编辑器不再投放。\nconst PROFILES := {');save(path,s)
path='src/player3d/Player3DStateGallery.gd';s=(root/path).read_text(encoding='utf-8').replace('"shielded"','"fat_zombie03"').replace('护盾重装体','胖子僵尸');save(path,s)
path='docs/v0.1/design/触发器刷怪设计.md';s=(root/path).read_text(encoding='utf-8').replace('7 类普通怪','6 类普通怪').replace('/`shielded`','').replace('壳甲','胖子僵尸');save(path,s)
path='assets/art/enemies/normal_enemy_3d/fat_zombie03/README.md';s=(root/path).read_text(encoding='utf-8').replace('此怪未加入既有关卡随机池，可显式投放','此怪已按用户指令接替壳甲卫兵的远征盒、随机池及主题池');save(path,s)
path='docs/v0.1/design/怪物设计.md';s=(root/path).read_text(encoding='utf-8').replace('未加入既有随机池','已接替壳甲卫兵的远征盒、默认随机池及主题池');save(path,s)
path='docs/v0.1/06_技术施工_怪物精英与Boss.md';s=(root/path).read_text(encoding='utf-8').replace('可显式投放，既有随机池未改变','已接替壳甲卫兵的远征盒、默认随机池及主题池');save(path,s)
print('SHIELDED_RETIRED_FROM_ACTIVE_SPAWN')
