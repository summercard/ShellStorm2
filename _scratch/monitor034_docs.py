from pathlib import Path
R=Path.cwd();B=R/'assets/art/enemies/bosses/enm_boss_monitor002'
p=R/'docs/v0.1/design/Boss002显示器动画设计.md';s=p.read_text(encoding='utf-8').replace('设计修订r26','设计修订r28').replace('状态：v031双母版与正式Godot表现资产含16个剪辑','状态：v034双母版与正式Godot表现资产含17个剪辑').replace('共11类动作，特殊攻击拆4段、击晕拆3段，共16个正式剪辑','共12类动作，特殊攻击拆4段、击晕拆3段，共17个正式剪辑')
s=s.replace('| 待机 |','| 激活出场 | activate | 6.4s / 192帧 | 首次激活单次，支持续播 | 末段依次出现五官 |\n| 待机 |',1)
s=s.replace('原16剪辑保留，新增后共17剪辑。','原16剪辑曲线及骨矩阵采样保留，新增后共17剪辑。静态键盘握持挂点校正至指下，源双母版与GLB保持同一位置；不改原走路或攻击曲线。')
p.write_text(s,encoding='utf-8')
p=R/'docs/v0.1/design/Boss002显示器技能设计.md';s=p.read_text(encoding='utf-8').replace('设计r2','设计r3')
s=s.replace('## 状态与打断','''## 首次激活出场

新实例首次激活先播放 `activate` 6.4秒：黑屏0.6秒、代码上刷、后方牵制线迸火、两次前拽与回弹、双臂弹出、抓起地上键盘、五官依次出现。属于出场表现，不增加第五个伤害技能。

唯一计时者为Enemy3D持有的MonitorBossCombat，沿用alert承载。tick_activation在AI决策之前推进，期间禁止进入追逐或技能状态；结束接idle并保留0.65秒决策冷却。休眠暂停，重新激活续播；monitor_activation_completed与monitor_activation_elapsed进入实例续档；旧档缺字段视为已完成。非致死受击照常扣血但不打断出场；死亡优先，停止出场并显示死亡。未首次激活的dormant采样黑屏首帧，已完成则保持原映射。

## 状态与打断''')
s=s.replace('dormant/idle→idle','首次出场特例之外，dormant/idle→idle')
p.write_text(s,encoding='utf-8')
p=R/'docs/v0.1/design/远征关卡01设计.md';s=p.read_text(encoding='utf-8');s+='\n### 显示器Boss首次激活演出\n\n2026-10-08当前契约：首波显示器Boss沿既有进房激活流程播放activate 6.4秒，依次黑屏、上刷代码、断线火花、挣扎两次、伸手取键盘和五官出现。出场由Enemy3D内部策略计时，使用alert状态，完成后进入正常四技能战斗。休眠暂停与重进续播、实例续档、死亡优先；不新增刷怪、伤害技能、无敌或房间波次。资产v034共17剪辑，走路保持v031曲线。见[技能契约](Boss002显示器技能设计.md)与[验收记录](../development/2026-10-08_boss002_activation.md)。\n';p.write_text(s,encoding='utf-8')
p=R/'docs/v0.1/MODULE_INDEX.md';s=p.read_text(encoding='utf-8');lines=s.splitlines();lines=[line.replace('v031','v034').replace('16剪辑','17剪辑')+' 新增首次激活activate 6.4s；原走路曲线保留。' if 'BOSS-STAGES' in line and '|' in line else line for line in lines];p.write_text('\n'.join(lines)+'\n',encoding='utf-8')
p=B/'README.md';s=p.read_text(encoding='utf-8');p.write_text('## 当前激活出场 v034\n\n新增activate 6.4秒/192帧：黑屏→代码上刷→断线火花→奋力挣扎两次→双臂伸出抓键盘→五官出现。旧16剪辑骨矩阵和曲线不变，键盘静态握持挂点校正。源和契约为v034；稳定Godot路径不变。出场显隐、代码与牵制线火花由正式表现脚本按同一时间采样。预览：`previews/activate_v034/monitor_activation.mp4`。\n\n'+s,encoding='utf-8')
print('Updated current design contracts')
