from pathlib import Path
import json,hashlib
B=Path('assets/art/enemies/bosses/enm_boss_monitor002');P=B/'previews/expressions_v030';prompt='精确修改3x2六表情图集：仅底右表情的小眼睛改为黑色螺旋，保留小眼尺寸、白底黑边、三根睫毛和原嘴型，透明背景；其他五表情布局保持。';(P/'generation_notes.json').write_text(json.dumps({'tool':'built-in image_gen','prompt':prompt,'source':'source/textures_v004/expressions_atlas.png','generated_image':'source/textures_v030/expressions_atlas.png','resolution':[1536,1024],'alpha':True},ensure_ascii=False,indent=2),encoding='utf-8')
entry='''## 当前交付 v030（受击叉眼吐舌、坐地双螺旋眼）

图1叉眼吐舌使用已有状态4：hurt F1—10，stun_enter F1—4；图2的坐地眩晕改为双螺旋眼状态5，stun_enter F5起及stun_loop持续，stun_exit F20恢复默认。

透明1536×1024图集 `source/textures_v030/expressions_atlas.png` 由内置imagegen编辑，已内嵌模型/动画双母版v030。原嘴型、睫毛和六格布局保留。实际渲染及切换检查见 `previews/expressions_v030/`。仅Blender源交付，未导出或接入Godot。

'''
p=B/'README.md';t=p.read_text(encoding='utf-8').replace('## 当前交付 v029','## 历史交付 v029');i=t.index('\n\n')+2;p.write_text(t[:i]+entry+t[i:],encoding='utf-8')
p=Path('docs/v0.1/design/Boss002显示器动画设计.md');t=p.read_text(encoding='utf-8').replace('设计修订r23','设计修订r24').replace('已完成Blender源制作于v029','已完成Blender源制作于v030');t=t.replace('六种表情仍是一张图集的离散状态。','六种表情仍是一张图集的离散状态。状态4叉眼吐舌用于受击；状态5双螺旋眼与原开口嘴用于击晕坐地。受击F1—10显示状态4，击晕进入F1—4显示状态4、F5起切状态5，起身F20恢复默认。');p.write_text(t,encoding='utf-8')
p=Path('docs/v0.1/MODULE_INDEX.md');t=p.read_text(encoding='utf-8').replace('v029击晕坐地双手摊地','v030增加受击叉眼吐舌及坐地双螺旋眼，保留击晕坐地双手摊地');p.write_text(t,encoding='utf-8')
for rel in ['docs/v0.1/development/2026-10-03_boss002_monitor_source.md','docs/v0.1/development/CHANGELOG.md']:
 p=Path(rel);t=p.read_text(encoding='utf-8');i=t.index('\n\n')+2;e='## 2026-10-06｜Boss002 v030 表情分配与双螺旋眼\n\nBOSS-STAGES / ASSET-PIPELINE，设计r24。按用户图1分配叉眼吐舌至受击，图2小眼改螺旋并用于坐地；内置imagegen编辑透明图集、内嵌双母版。五个实际渲染表情时点检查通过；见资产previews/expressions_v030/audit.json。未导出或接入Godot。\n\n';p.write_text(t[:i]+e+t[i:],encoding='utf-8')
text=Path('_scratch/boss014_finalize.py').read_text(encoding='utf-8').split("entry='''")[0].replace('_scratch/boss014_ledger/baseline_before.json','_scratch/boss030_ledger/baseline_before.json');exec(compile(text,'baseline_update','exec'))
p=B/'asset_manifest.json';m=json.loads(p.read_text(encoding='utf-8'));m.update(version='v030',source='source/enm_boss_monitor002_model_v030.blend',animation_source='source/enm_boss_monitor002_animation_v030.blend',rig_contract='source/rig_contract_v030.json');m['verification']['expression']='previews/expressions_v030/audit.json';m['expression_atlas']='source/textures_v030/expressions_atlas.png'
for f in B.rglob('*'):
 if f.is_file() and f.name!='asset_manifest.json' and f.suffix not in ['.blend1','.import'] and ('v030' in f.as_posix() or f.name in ['README.md','boss002_production_ledger.xlsx']):m['files'][f.relative_to(B).as_posix()]=hashlib.sha256(f.read_bytes()).hexdigest()
p.write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8');print('v030 documented')
