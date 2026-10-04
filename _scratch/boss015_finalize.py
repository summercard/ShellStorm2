from pathlib import Path
p=Path('_scratch/boss014_finalize.py');t=p.read_text(encoding='utf-8-sig').split("entry='''")[0].replace('boss014_ledger','boss015_ledger');exec(t)
B=Path('assets/art/enemies/bosses/enm_boss_monitor002')
entry='''## 当前交付 v015（夸张特效与持线手后摆）

动作 `source/enm_boss_monitor002_animation_v015.blend`，模型 `source/enm_boss_monitor002_model_v015.blend`。默认BOSS002_STUDIO场景，1—55帧播放。手绘爆点、冲击环及蓝/玫红干扰统一放大至v014的1.65倍。持线右手蓄力向后上方拉开，下砸后继续后摆、稍滞后达到极值，再收回；前后行程约1.95m、上下约0.94m。数据线增加逐节延迟摆动。

身前平拍、五官22%放大、idle/move曲线保留。动作23项与表现8项通过，217个细分帧检查双手、键盘、数据线与插头不穿地，收招无特效残留。证据与视频 `previews/keyboard_v015/`。复用v014的image-2贴图，未导出或接入Godot。v014保留回退。

'''
p=B/'README.md';t=p.read_text(encoding='utf-8').replace('## 当前交付 v014','## 历史交付 v014');i=t.index('\n\n')+2;p.write_text(t[:i]+entry+t[i:],encoding='utf-8')
p=Path('docs/v0.1/design/Boss002显示器动画设计.md');t=p.read_text(encoding='utf-8').replace('设计修订r8','设计修订r9').replace('v014动作母版','v015动作母版').replace('右手持线置侧避让','右手持线向后上方大幅拉开，命中后滞后继续后摆再回收').replace('挥击和命中短促点缀蓝色/玫红电子干扰','挥击和命中短促点缀蓝色/玫红电子干扰；手绘特效尺寸为v014的1.65倍');p.write_text(t,encoding='utf-8')
p=Path('docs/v0.1/MODULE_INDEX.md');t=p.read_text(encoding='utf-8').replace('v014已制作idle、move与身前平拍melee_keyboard','v015已制作idle、move与身前平拍melee_keyboard（右手大幅后摆、特效放大1.65倍）');p.write_text(t,encoding='utf-8')
entry='''## 2026-10-05 v015 特效放大与右手反向后摆

BOSS-STAGES / ASSET-PIPELINE，设计r9。按用户要求，手绘爆点/冲击环/蓝玫红干扰放大1.65倍；持线右手增加后上方蓄势、下砸反向后摆、滞后回收，实测前后1.95m/上下0.94m。数据线逐节延迟摆动。左手平拍与idle/move保持。

Blender专项23+8项通过，217个四分之一帧采样检查双手、键盘、数据线、插头无穿地，首尾无特效残留。Cycles整段预览见previews/keyboard_v015，模型/动画双母版同签名。当前资产行与制作账本升级v015，其余单元格保持；未执行Godot/伤害接入，全项目历史门禁问题仍单列。

'''
for rel,e in [('docs/v0.1/development/2026-10-03_boss002_monitor_source.md',entry),('docs/v0.1/development/CHANGELOG.md','## 2026-10-05｜Boss002夸张攻击v015\n\n- BOSS-STAGES / ASSET-PIPELINE：特效放大1.65倍与持线右手反向大幅后摆，源级31项通过；见[记录](2026-10-03_boss002_monitor_source.md)。\n\n')]:
 p=Path(rel);t=p.read_text(encoding='utf-8');i=t.index('\n\n')+2;p.write_text(t[:i]+e+t[i:],encoding='utf-8')
