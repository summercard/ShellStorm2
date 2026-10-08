from pathlib import Path
import json
R=Path.cwd();B=R/'assets/art/enemies/bosses/enm_boss_monitor002';dev='docs/v0.1/development/2026-10-08_boss002_activation.md'
p=R/'docs/v0.1/MODULE_INDEX.md';s=p.read_text(encoding='utf-8').replace('v031正式Prefab（原版侧翘横移move）、16剪辑/64骨','v034正式Prefab（activate出场、原版侧翘横移move）、17剪辑/64骨').replace(' | 新增首次激活activate 6.4s；原走路曲线保留。',' |');p.write_text(s,encoding='utf-8')
p=R/'docs/v0.1/development/CHANGELOG.md';s=p.read_text(encoding='utf-8');p.write_text('## 2026-10-08 Boss002 激活出场\n\nv034新增activate6.4秒，17剪辑；原动作曲线保留，首次进房激活、续播与存档已接入。[交付与验收](2026-10-08_boss002_activation.md)。\n\n'+s,encoding='utf-8')
p=R/'docs/v0.1/feature_registry.json';v=json.loads(p.read_text(encoding='utf-8'))
for feature in v['features']:
 if feature['feature_id']=='BOSS-STAGES':
  for key,value in feature.items():
   if isinstance(value,list) and any(isinstance(x,str) and 'development/' in x for x in value):
    if dev not in value:value.append(dev)
p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
p=B/'source/rig_contract_v034.json';v=json.loads(p.read_text(encoding='utf-8'));v['formal_animations_authored']=list(json.loads((B/'components/enm_boss_monitor002/monitor_motion.json').read_text())['clips']);v['export_note']='Pure visual GLB plus evaluated 30Hz motion JSON; 17 clips. Static keyboard grip corrected; legacy action curves preserved. Enemy3D owns activation and gameplay.';p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for folder in [B/'previews/runtime/activation_frames',B/'previews/activate_v034']:(folder/'.gdignore').touch()
print('Final document references and 17-clip contract synchronized')
