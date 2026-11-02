# 远征01–03怪物技能恢复与状态衔接

日期：2026-11-02。FeatureID：ENEMY-AI；工程0.1.0，设计修订r4。状态：本项实现与定向验收完成，ENEMY-AI整体保持partial。

> ⚠ **实现状态（2026-11-02 23:30 复核：未落地）**：本文描述的实现与验收在当前工作区**不存在**。
> 判据：`grep -c '_tick_action_state' src/enemy3d/Enemy3D.gd` = **0**（文中称它是技能与恢复的统一所有者）；
> `src/enemy3d/` 下无对应改动。配套 `tests/verification/verify_enemy_action_recovery.*` 已入库，
> 但它测的实现不在 ⇒ 该验收当前必红，属"孤儿验收器"，不要当成回归基线跑。
> 疑似被当日 17:07 的 `git pull --rebase` 洗掉。重做时按本文复跑并复验，**不要凭本文的"完成"判定完成**。

## 来源与基线

用户要求全部近战、瞬移怪在技能后停顿约0.2–0.5秒，并检查状态机的不自然衔接，覆盖远征01–03且同步设计。代码基线为`6258c13c3d921fca1985ff9f0a71f862ce20c7fd`加本次开始时既有工作区变更；其他会话已有地图、美术、武器和UI修改保留。改动前文件副本位于工程外`ShellStorm2-backup/2026-11-02_enemy_recovery/before_edits/`。

主契约见[AI设计§6.2.1](../06A_怪物AI系统完整设计_评审稿.md#621-技能完成与恢复窗口enemy-ai-r42026-11-02)，已同步[怪物设计](../design/怪物设计.md)、技术施工与远征01/02/03设计页。规则按能力共用，未添加关卡ID条件；01/02及后续生成的强化怪自然继承原型规则。

## 实施与行为

- `Enemy3D._tick_action_state()`在失目标分支之前统一拥有技能与恢复。`attack`只派发一次，并等完整连射、短突进、绕链、抓握或自爆生效段结束再转`recovery`。冷却独立计时，不能跨过恢复。
- 普通接触/小僵尸恢复0.34秒、伏击0.40秒、护盾近战0.48秒、绕链0.35秒、随机借招0.30秒。瞬移怪普通出手恢复至少0.30秒，瞬移落地恢复0.40秒。原胖子1.30秒、抓握复位1.20秒及显示器Boss各技能长收招保留；不额外叠加短暂停顿。
- 修复瞬移前摇被同帧追击覆盖；前摇独占行动，周期闪现只在有目标的追击段开始，攻击后闪现等完整攻击和恢复，落点合法性与2.5秒冷却沿用原规则。只是真正离场的vanish不追加恢复。
- 修复丢目标跳过收招；恢复结束才按目标是否有效转追击/搜索。前摇丢失目标则取消攻击并释放令牌。死亡、休眠和有效硬直清理未完成连射/绕链/瞬移；普通非打断伤害不重置恢复。
- 修复短突进外推逐帧累加：在生效段直接消费技能速度，结束后停止。玩家击退、拉扯、重力、碰撞与冻结继续生效；冻结不消耗恢复窗口。
- 小僵尸、伏击与通用近战命中帧补视线复核，避免前摇后关闭的门仍被穿透。挥空后同样恢复。
- 抓握大师由主攻击入口启动，不再由悬停计时器平行开招；保留清场自死、躲过三次后离场、原位移与冷却。
- 查询快照新增生效是否未完、恢复已过/目标时长及瞬移前摇剩余秒数。未新增存档schema或布局指纹；沿用旧存档恢复时取消战斗瞬态的机制。未改血量、伤害、怪物编成与奖励。

## 定向验收

运行Godot4.7.2；各进程启动前已通过独立APPDATA隔离正式存档，逐场景直跑并调用`check_verification_log.py`，未使用历史通过替代本次结果。

| 用例 | 场景退出/日志门禁 | 结果与预期故障 |
|---|---|---|
| verify_enemy_action_recovery | 0 / 0 | 2978检查；41原型与三种强化派生、30/60/120Hz、有/无目标、受光、非打断受击、击退与冻结、完整突进后静止、完整连射/绕链/抓握、瞬移前摇/落地/攻击后请求、近战墙体复核、硬直/休眠/死亡清理；无预期故障、无非预期脚本或引擎错误 |
| verify_3d_enemy_behavior_flow | 0 / 0 | 原有怪物行为、视线、召唤、自爆碎片、重力/分离/坠落回归通过 |
| verify_enemy_light_motion_regression | 0 / 0 | 受光、导航、低速移动、骨动画回归通过 |
| verify_monitor_boss_flow | 0 / 0 | 显示器Boss原时间轴回归通过 |
| verify_strong_variant_monsters | 0 / 0 | 强化派生回归通过 |
| verify_monster_startup_roar | 0 / 0 | 原启动吼叫窗口回归通过 |
| verify_fat_zombie03 | 1 / 3 | 两条非预期旧失败：world radius、full death retained；使用改前Enemy3D的独立目录映射对照同样失败，未删除断言或缩短专用动作 |
| verify_monster_ai_system_complete | 1 / 3 | 两条非预期旧失败：Attack token budget is not exactly 2 melee + 2 ranged: 1/0、Released melee token was not reusable；改前同场景已复现同样两条，与原有470ms房间节拍规则冲突 |

最终新增专项以`recovery_final.log`为准。初轮测试中的即时模型热切换会触发材质空引用，移除这段与本次AI规则无关的夹具操作后同一专项2978检查与日志门禁均通过；未加错误白名单。胖子基线对照保留旧场景完整断言，独立映射目录不改动正式代码。

## 原生渲染采样

Forward+真实渲染，`native_visual.log`场景退出0、无脚本/引擎错误。采样图`native_00.png`至`native_05.png`位于`ShellStorm2-work/verification/2026-11-02_enemy_recovery/`，已目视检查。小僵尸突进后连续两帧XZ位置相同；瞬移怪落点连续三帧XZ位置相同，随后恢复追击。首次GPU着色器编译使墙钟第一采样约2.11秒，因此不把这些墙钟时间当作精确技能时长；精确时长以专项物理delta检查为准。

## 门禁与边界

静态检查结果见同批`static_results.json`：

- `check_level_decoupling.py`：exit0，0违规。
- `check_asset_runtime_naming.py --quiet`：exit0，未新增带版本运行资产。
- `check_documentation_contracts.py`：exit1，17项均已出现在本轮初次检查：15条既有断链、3个其他场景未登记构成的一项registry错误、默认Python缺openpyxl构成的一项媒体域检查错误。本次新增文档及引用无新错误。
- `check_verification_registry.py`：exit1，仍是`verify_base_lamp_dynamics`、`verify_base_lamp_visual`、`verify_stairwell_turn_rail`三项未登记；本次`verify_enemy_action_recovery`已登记。
- `check_workspace_hygiene.py`：exit1，现有工程内`outputs`/`_scratch`及本次未写入的远征01设计投影不一致，均在本次修改范围外；没有清理其他会话目录或改其关卡数据。
- 本次源文件、测试与文档无CRCRLF，`git diff --check`通过。

没有为了全绿修改其他功能或接受资产/设计源哈希漂移。

未执行全量core/full、Android、多人长时间压力、远征01–03完整通关与主观手感长测；专项与短时渲染不代表整关已验收。已运行的游戏需重新运行以载入更新。

过程日志统一位于工程外`ShellStorm2-work/sessions/2026-11-02_enemy_recovery/`。回滚须按本次文件差异逐项比对，不整树覆盖并行成果。
