from pathlib import Path
p=Path('_scratch/boss014_finalize.py');t=p.read_text(encoding='utf-8-sig').split("entry='''")[0].replace('boss014_ledger','boss016_ledger');exec(t)
B=Path('assets/art/enemies/bosses/enm_boss_monitor002')
entry='''## 当前交付 v016（屏幕三圈旋转后前扑砸地）

打开 `source/enm_boss_monitor002_animation_v016.blend`，默认 heavy_spin_slam，BOSS002_STUDIO，1—97帧/30fps/3.2秒单次。模型母版 `source/enm_boss_monitor002_model_v016.blend`。旧idle、move、melee_keyboard曲线完全保留；键盘攻击特效预览继续使用v015文件，v016的STUDIO专用于重击。

屏幕绕后轴的前后方向独立旋转三圈（19—49帧），后轴/底座不转，双臂张开拖曳；五官抵消屏幕滚转并保持正向。49—55帧停顿，55—65帧前扑到屏幕正面近乎平贴地面，65—81帧低位暴露，81—97帧支架弹性回升。root固定，动作不产生玩法移动。

复用image-2手绘图集，旋转笔触20—49帧、大范围双层地面环和放射爆点65—82帧，83帧后清除。18项源级验收通过，385个四分之一帧核验1080°连续旋转、后轴不转、五官正向、底座固定、八类关键几何无穿地。完整证据与视频 `previews/heavy_v016/`。未执行完整网格互穿求解、Godot导出/接入与伤害事件；v015留作回退。

'''
p=B/'README.md';t=p.read_text(encoding='utf-8').replace('## 当前交付 v015','## 历史交付 v015');i=t.index('\n\n')+2;p.write_text(t[:i]+entry+t[i:],encoding='utf-8')
p=Path('docs/v0.1/design/Boss002显示器动画设计.md');t=p.read_text(encoding='utf-8').replace('设计修订r9','设计修订r10').replace('idle待机、move移动与melee_keyboard键盘攻击已制作于v015动作母版','idle待机、move移动、melee_keyboard键盘攻击与heavy_spin_slam旋转砸地已制作于v016动作母版');t=t.replace('F48—54转回可读朝向，停顿并抬高主体形成前砸预警','F48—54屏幕完成三圈后停在可读朝向，保持六帧明确停顿形成前砸预警');t=t.replace('屏幕接地不是底座跳起跺地。','屏幕接地不是底座跳起跺地。重击复用image-2手绘图集，大范围双层冲击环与放射爆点在F64触发，旋转时有蓝色/玫红笔触；特效仅源级独立预览，正式事件同步待接入。');p.write_text(t,encoding='utf-8')
p=Path('docs/v0.1/MODULE_INDEX.md');t=p.read_text(encoding='utf-8').replace('v015已制作idle、move与身前平拍melee_keyboard（右手大幅后摆、特效放大1.65倍）','v016已制作idle、move、身前平拍melee_keyboard及屏幕三圈旋转前扑heavy_spin_slam');p.write_text(t,encoding='utf-8')
p=Path('docs/v0.1/design/README.md');t=p.read_text(encoding='utf-8').replace('idle/move/melee_keyboard已制作','idle/move/melee_keyboard/heavy_spin_slam已制作');p.write_text(t,encoding='utf-8')
entry='''## 2026-10-05 v016 屏幕独立三圈与前扑重击

BOSS-STAGES / ASSET-PIPELINE，设计r10。新增heavy_spin_slam：19—49帧屏幕绕后轴连续三圈，49—55帧保持，65帧屏幕正面前扑接地，81帧后回升到97帧。后轴/底座无自转，双臂张开避让，五官保持正向。复用v014手绘贴图，旋转笔触与大范围双层冲击波、放射爆点为独立STUDIO预览。

Blender专项18项通过，385个细分帧积分转数1080°；屏幕/支架/底座/双手/键盘/数据线/插头无穿地，原三个动作曲线保持，双母版同签名。修正四元数符号以避免帧间反转。真实Cycles整段与关键姿态见previews/heavy_v016。账本同AssetID升v016；未执行Godot/伤害接入或全网格互穿检测。旧键盘攻击含特效预览保留v015，v016默认重击。

'''
for rel,e in [('docs/v0.1/development/2026-10-03_boss002_monitor_source.md',entry),('docs/v0.1/development/CHANGELOG.md','## 2026-10-05｜Boss002屏幕旋转砸地v016\n\n- BOSS-STAGES / ASSET-PIPELINE：新增heavy_spin_slam，独立1080°旋转、停顿前扑及大范围手绘冲击；18项源级验收通过。见[记录](2026-10-03_boss002_monitor_source.md)。\n\n')]:
 p=Path(rel);t=p.read_text(encoding='utf-8');i=t.index('\n\n')+2;p.write_text(t[:i]+e+t[i:],encoding='utf-8')
