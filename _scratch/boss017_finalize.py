from pathlib import Path
p=Path('_scratch/boss014_finalize.py');t=p.read_text(encoding='utf-8-sig').split("entry='''")[0].replace('boss014_ledger','boss017_ledger');exec(t)
B=Path('assets/art/enemies/bosses/enm_boss_monitor002')
entry='''## 当前交付 v017（惯性跟随与重砸节奏深化）

动作 `source/enm_boss_monitor002_animation_v017.blend`，模型 `source/enm_boss_monitor002_model_v017.blend`。默认heavy_spin_slam，1—97帧/30fps。原idle/move/melee_keyboard保持，v016留作回退。

双手不再固定在世界坐标：跟随后轴的位移与速度，左手滞后3帧、右手5帧，触地后继续向前甩出，再衰减回摆；手腕、键盘和线尾有后续摆动。旋转专门使用6条渐细环形弧带，绕屏幕前后轴连续旋转，旋转期间不出现打击爆点图集。

49—55帧轻微后仰19°、抬高蓄势，55—59帧保持，59—65帧加速前扑砸地；触地后小幅回弹、再次压稳，随后重心回升与手部滞后收回。旋转弧带在停顿前消失，地面爆点仅命中时触发。

21项源级专项通过，385个细分帧检查；保留连续1080°、正向五官、固定底座、双母版同签名及关键几何不穿地。证据与整段预览 `previews/heavy_v017/`。测试检查运动契约，视觉品质仍以实际预览评审；未执行Godot接入、玩法伤害或完整网格间碰撞求解。

'''
p=B/'README.md';t=p.read_text(encoding='utf-8').replace('## 当前交付 v016','## 历史交付 v016');i=t.index('\n\n')+2;p.write_text(t[:i]+entry+t[i:],encoding='utf-8')
p=Path('docs/v0.1/design/Boss002显示器动画设计.md');t=p.read_text(encoding='utf-8').replace('设计修订r10','设计修订r11').replace('v016动作母版','v017动作母版');t=t.replace('F48—54屏幕完成三圈后停在可读朝向，保持六帧明确停顿形成前砸预警；F54—64转','F48—54屏幕完成三圈后后仰约19°并抬高，F54—58保持蓄力，F58—64加速前扑；F54—64转')
# Replace the actual existing timing clause independently of the old prose continuation.
t=t.replace('F48—54屏幕完成三圈后停在可读朝向，保持六帧明确停顿形成前砸预警；F54—64后支撑由下到上弯曲','F48—54屏幕完成三圈后后仰约19°并抬高，F54—58保持蓄力；F58—64后支撑由下到上快速弯曲')
t=t.replace('F64—68压实、支撑再弯少量，双臂和道具在侧面避让','F64—66压实，F66—68小幅回弹，F68—71再次压稳；双臂随身体惯性滞后甩出、再回摆，道具跟随手腕').replace('旋转时有蓝色/玫红笔触','旋转时使用专用蓝色/玫红渐细环形弧带，不复用打击爆点；手臂随位移和加速变化，左右错拍、手腕和线尾延迟，不能固定世界落点')
p.write_text(t,encoding='utf-8')
p=Path('docs/v0.1/MODULE_INDEX.md');t=p.read_text(encoding='utf-8').replace('v016已制作idle、move、身前平拍melee_keyboard及屏幕三圈旋转前扑heavy_spin_slam','v017已制作idle、move、身前平拍melee_keyboard及惯性双手/后仰重砸heavy_spin_slam（专用旋转弧带）');p.write_text(t,encoding='utf-8')
entry='''## 2026-10-05 v017 惯性手臂与专用旋转特效

BOSS-STAGES / ASSET-PIPELINE，设计r11。按用户指出的双手钉住、旋转特效像打击、下砸乏力问题，手部改为跟随后轴位移/速度、左右3/5帧延迟，触地后前甩回摆并加入腕部/线尾摆动。旋转特效新建6条渐细环形弧带，绕前后轴旋转，不使用爆点图集。动作后仰19°、55—59帧保持、59—65帧加速前扑，接地反弹后再次压稳。

21项源级检查通过，385个细分帧覆盖旋转/惯性/后仰停顿/加速下砸/地面；旧三个动作不变。真实Cycles预览见previews/heavy_v017。更新同一AssetID和独立制作账本，其他资产单元格保持；未做Godot/伤害/全网格间互穿验证。数值通过不替代视觉品质评审。

'''
for rel,e in [('docs/v0.1/development/2026-10-03_boss002_monitor_source.md',entry),('docs/v0.1/development/CHANGELOG.md','## 2026-10-05｜Boss002重击惯性深化v017\n\n- BOSS-STAGES / ASSET-PIPELINE：惯性双手、专用旋转弧带、后仰停顿与加速砸地，源级21项通过；见[记录](2026-10-03_boss002_monitor_source.md)。\n\n')]:
 p=Path(rel);t=p.read_text(encoding='utf-8');i=t.index('\n\n')+2;p.write_text(t[:i]+e+t[i:],encoding='utf-8')
