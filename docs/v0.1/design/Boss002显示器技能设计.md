# Boss002 显示器技能与运行契约

FeatureID：BOSS-STAGES / ENEMY-AI / ASSET-PIPELINE；游戏版本0.1.0；设计r4。来源：用户2026-10-06要求正式导入、完成状态机与技能；2026-10-07要求按正式流程投放远征01 Boss房。以下数值为初始平衡设计，可独立调整。

内容ID `boss_monitor002`，资产ID `ENM-BOSS-MONITOR002-3D`。在怪物设计表独立登记，远征 expedition_01 Boss房指派此ID；不替换95/90/85层既有Boss。生命、碰撞、AI状态、伤害、死亡和掉落唯一所有者为Enemy3D；MonitorBossCombat为该控制器持有的技能策略，Prefab仅采样动作并显示特效。

## 战斗设计

### 远征01正式投放

`floor_00.json` 的 `boss` 房间通过 `boss_content_id=boss_monitor002` 指派身份。沿用 `spawn_placements` 与 `encounter.stages` 三波：首波 `box_boss_arena` 的 boss 条目经 MonsterInjector 生成一个显示器 Boss，随从按盒子延迟入场；后两波沿用原房间编成，不额外手工生成 Boss。身份、数值和技能仍取唯一内容目录。未进入不提前激活，死亡走 Enemy3D.killed 及房间存活账；Boss死亡不跳过后续波次，全部清完才结算清房奖励并允许按既有门策略离开。重进已清房不得重复刷新或重复发奖。

远征为单层行动，清 Boss 房不增加塔楼下行权限，也不生成 BOSS_KILL 信标；终点继续使用 STANDARD 撤离。独立验收入口 `verify_expedition_monitor_boss_flow` 使用正式远征场景、进房生命周期、触发盒、死亡信号及自动续波；不得以直接实例化 Boss 替代投放验收。

初始生命52000、基础伤害24、移动3.612m/s、根尺寸倍率1.05（沿用Enemy3D Boss口径），碰撞沿用Boss圆柱1.92m半径、2.30m高度并受根倍率影响。攻击朝向在前摇结束前锁定；命中要求同一地面、无遮挡，不能穿墙或跨楼板。

| 技能ID | 动作 | 前摇/命中/恢复（秒） | 范围与伤害 | 规则 |
|---|---|---|---|---|
| monitor_keyboard | melee_keyboard | 0–1.067 / 1.067 / 1.067–1.8 | 身前3.2m处半径1.65m；24 | 平拍地面；单次结算 |
| monitor_cable | melee_cable | 0–0.8 / 0.8–0.967 / 0.967–2.0 | 前方160°、半径6.0m；20 | 螺旋前摇、平滑横甩；每目标每次攻击至多一次 |
| monitor_spin_slam | heavy_spin_slam | 0–2.133 / 2.133 / 2.133–3.2 | 前方1.4m处半径5.2m；36 | 屏幕自身三圈旋转；后仰、停顿、重砸；命中黄色高亮仅1/30秒 |
| monitor_ground_current | special四段 | 准备1.2+插入0.6 / 持续2.4、3.2或4.0 / 收回0.9 | 插线点半径7.0m；每0.8秒12 | 插入接触在1.667秒；接地线电流与分段地面脉冲；持续中可重击打断 |

判定单位为世界米，不额外乘根尺寸。范围提示在前摇期间可见，结束后消失。蓝色色块为主、少量玫红数据碎片；无描边/涂鸦；旋转只使用旋转弧带；命中才使用冲击形状。VFX不写生命值。

三阶段阈值为HP≤66%、≤33%，主体不更换。阶段1循环键盘、数据线、键盘、重击；阶段2加入插线；阶段3提高重击/插线权重，通电时长4秒。不压缩动作关键帧或伤害前摇。下一次攻击使用新阶段技能袋。

每次攻击结束后0.65秒决策冷却。近距离优先键盘/数据线；目标超过6m且插线冷却未到时先追近，插线冷却10秒。不能在远距离原地砸空无限循环。

## 首次激活出场

新实例必须在房间运行已启用且存活玩家与Boss根节点的世界距离≤10米时，才首次激活。10米外保持黑屏首帧，不追逐、不攻击；远程非致死受击不替代距离条件。触发后锁定已开始标记，即使玩家退出10米范围也继续完整播放 `activate` 6.4秒：黑屏0.6秒、代码上刷、后方牵制线迸火、两次前拽与回弹、双臂弹出、抓起地上键盘、五官依次出现。动画结束后才进入战斗。属于出场表现，不增加第五个伤害技能。

唯一计时者为Enemy3D持有的MonitorBossCombat，沿用alert承载。tick_activation在AI决策之前推进，期间禁止进入追逐或技能状态；结束接idle并保留0.65秒决策冷却。休眠暂停，重新激活续播；monitor_activation_started、monitor_activation_completed与monitor_activation_elapsed进入实例续档；旧档缺started时按已播进度或完成标记推导，更旧档缺完成字段视为已完成。非致死受击照常扣血但不打断出场；死亡优先，停止出场并显示死亡。未首次激活的dormant采样黑屏首帧，已完成则保持原映射。

## 状态与打断

沿用Enemy3D十二态：首次出场特例之外，dormant/idle→idle；patrol/chase/search/return→move（原地转向时使用左右转）；alert→idle；telegraph/attack/recovery由技能真实时间采样；stagger为hurt或stun_enter→stun_loop→stun_exit；dead为正式dead剪辑，禁止程序压扁根。

普通受击在非技能期播放hurt0.5秒；技能期普通子弹只显示受击表情，不重置攻击时间轴。积累实际伤害达到最大HP8%，或单次达到8%，进入击晕：坐地1.4秒→保持2.4秒→起身1.0秒。击晕期间保持摊地双手，不因连射反复重播坐下。没有无敌；仍接受伤害。通电期暴击或击退≥0.8m/s也可触发击晕。击晕清空攻击判定和电流，释放攻击令牌；恢复后重置韧性累计。死亡优先于全部状态。

转向由控制器推进逻辑yaw；左右转动作里的90°视觉yaw在表现根反向抵消，避免逻辑和美术双转。根骨原地。表情图集、向上滚动代码由表现材质适配；姿态由Blender采样。

## 接口、失败与验收

命令 `Enemy3D.configure_from_enemy_data` 接收catalog投影；`transition_to`仍只接受十二态。查询 `MonitorBossCombat.presentation_context` 返回schema1的 `{action_id,time,skill_id,phase,contact_point,hit_flash,telegraph_radius,electric_active}`；时间单位秒，表情由采样剪辑决定。只读表现接口不可发动攻击。未知技能拒绝并返回chase；资源加载失败报错，不能静默换成其他Boss。死亡/失活/场景卸载取消技能与电流；读档沿用Enemy3D把危险状态退回alert，不恢复残留命中。

正式链：怪物表→BossContentCatalog→MonsterInjector→Enemy3D→MonitorBossCombat→表现适配。独立验收 `verify_monitor_boss_flow` 与真实渲染 `verify_monitor_boss_visual`：全部动作/循环/骨架、十二态、三阶段、伤害时刻、范围拒绝、重复伤害、墙体、打断、电流关停、死亡、读档、导入骨姿态与源采样一致。产物与结果记入独立开发记录和敌人账本。


### Boss出生位置与移动速度

显示器Boss由正式触发盒生成于房间中心（局部X/Z=0），初始面向南方（世界+Z）。移动速度由1.204提高至3.612米/秒（3倍；内容speed=123.84）。10米激活及6.4秒出场规则保持。
