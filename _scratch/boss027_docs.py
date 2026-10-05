from pathlib import Path
import json
R=Path.cwd();B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/impact_electric_v027'
(P/'clips.json').write_text(json.dumps({'stun_enter':42,'stun_loop':48,'stun_exit':30,'special_prepare':36,'special_insert':18,'special_channel':24,'special_recover':27},indent=2))
entry='''## 当前交付 v027（受击坐地反弹、眩晕与线缆电流）

模型/动画双母版 `source/enm_boss_monitor002_model_v027.blend`、`source/enm_boss_monitor002_animation_v027.blend`；打开动画默认播放 `stun_enter`，1—43帧，30fps。保留v026及更早版本。

`stun_enter`：受击后仰、单帧黄色闪形（F4）、F5切换螺旋眼与环绕星星，F19首次坐地，F25反弹最高点（0.48米），F31第二次坐地后稳定；双臂和手腕在反弹时错拍摆动。`stun_loop`保持眩晕；`stun_exit`在F20恢复表情并关闭星星。特效采用纯色块，无勾线。

特殊攻击电流继承数据线骨骼，蓝色细电弧配流动亮芯；`special_insert` F15通电、`special_channel`持续、`special_recover` F9断电。所有正式动作显式重置特效开关，避免切换残留。`BOSS002_DIZZY_ELECTRIC_PREVIEW`为独立预览集合，不属于角色导出几何。

七段动作以半帧采样检查地面、线缆骨链、锁点、分段衔接与循环，通过；真实Cycles预览和报告见 `previews/impact_electric_v027/`。仍为Blender源级交付，未导出GLB或接入Godot。

'''
p=B/'README.md';t=p.read_text(encoding='utf-8').replace('## 当前交付 v026','## 历史交付 v026');i=t.index('\n\n')+2;p.write_text(t[:i]+entry+t[i:],encoding='utf-8')
p=R/'docs/v0.1/design/Boss002显示器动画设计.md';t=p.read_text(encoding='utf-8').replace('设计修订r20','设计修订r21').replace('已完成Blender源制作于v026','已完成Blender源制作于v027');t+='\n\n### v027 受击及接地电流修订\n\n'+entry.split('\n\n',2)[2];p.write_text(t,encoding='utf-8')
p=R/'docs/v0.1/MODULE_INDEX.md';t=p.read_text(encoding='utf-8');lines=t.splitlines();lines=[('BOSS-STAGES / ASSET-PIPELINE：[Boss002动画设计](design/Boss002显示器动画设计.md)，15个正式剪辑已完成Blender源制作；v027增加受击坐地单次反弹、螺旋眼/星星眩晕、单帧黄色闪形和特殊攻击接地线缆电流。肩部带动双手、纯色块赛博特效；未导出或接入Godot。' if l.startswith('BOSS-STAGES / ASSET-PIPELINE：') else l) for l in lines];p.write_text('\n'.join(lines)+'\n',encoding='utf-8')
for rel in ['docs/v0.1/development/2026-10-03_boss002_monitor_source.md','docs/v0.1/development/CHANGELOG.md']:
 p=R/rel;t=p.read_text(encoding='utf-8');i=t.index('\n\n')+2;e='## 2026-10-05｜Boss002 v027 坐地眩晕与接地电流\n\nBOSS-STAGES / ASSET-PIPELINE：设计r21，受击—坐地—单次反弹—坐地眩晕，螺旋眼及纯色星星，F4黄色闪形；特殊攻击线缆随骨骼电流与接触开关。七段半帧采样通过地面、骨链、锁点与接续检查；GUI工程和MCP已打开。真实渲染见资产previews/impact_electric_v027。仅源级交付，未接入Godot。\n\n';p.write_text(t[:i]+e+t[i:],encoding='utf-8')
# Only accept the intended row into the lossless baseline; do not accept unrelated new IDs.
t=Path('_scratch/boss014_finalize.py').read_text(encoding='utf-8').split("entry='''")[0].replace('_scratch/boss014_ledger/baseline_before.json','_scratch/boss027_ledger/baseline_before.json');exec(compile(t,'baseline_update','exec'))
print('v027 documentation and intended ledger baseline updated')
