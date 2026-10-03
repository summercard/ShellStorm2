import json
from pathlib import Path
p=Path(__file__).parent;root=p.parents[1];record='docs/v0.1/development/2026-10-03_fat_zombie03_rig_and_action_design.md'
f=root/'docs/v0.1/feature_registry.json'; lines=f.read_text(encoding='utf-8').splitlines(keepends=True)
for i,line in enumerate(lines):
 if '"feature_id":"ENEMY-AI"' not in line and '"feature_id":"ASSET-PIPELINE"' not in line:continue
 payload=line.strip().rstrip(',');data=json.loads(payload)
 for d in ['docs/v0.1/design/怪物设计.md','docs/v0.1/design/胖子僵尸03动作设计.md']:
  if d not in data['design_docs']:data['design_docs'].append(d)
 if record not in data['development_records']:data['development_records'].append(record)
 lines[i]='    '+json.dumps(data,ensure_ascii=False,separators=(',',':'))+',\n'
f.write_text(''.join(lines),encoding='utf-8')
f=root/'docs/v0.1/development/CHANGELOG.md';s=f.read_text(encoding='utf-8');entry='- 2026-10-03：胖子僵尸03 v002从原始FBX修正骨骼/蒙皮比例及Root，512贴图、游戏内2.2m；13段动作时间轴设计4213字符已登记，动画待制作。见[修正记录](2026-10-03_fat_zombie03_rig_and_action_design.md)。\n'
if entry not in s:f.write_text(s+'\n'+entry,encoding='utf-8')
print('FAT_ZOMBIE03_DESIGN_INDEXED')
