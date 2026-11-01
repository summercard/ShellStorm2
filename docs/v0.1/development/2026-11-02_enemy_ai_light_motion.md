# 远征03：受光抽搐、寻路和接触攻击修正

日期：2026-11-02；FeatureID：`ENEMY-AI`、`ASSET-PIPELINE`；工程版本：0.1.0；交付：当前工作区，未提交。

## 用户要求与契约

检查远征03怪物寻路与攻击，追查手电照射后的单帧变形；先试行仅行动减速。追加要求移除用于区分变种的程序化球、方块等附加件。

当前规则见[AI主契约§8.0](../06A_怪物AI系统完整设计_评审稿.md#80-当前试行照射仅降低行动速度enemy-ai-r32026-11-02)、[受光施工契约](../06_技术施工_怪物精英与Boss.md#77-三态战斗效果与临时头顶标识)、[怪物外观约束](../design/怪物设计.md)。人工光自主移动倍率0.40，攻击频率倍率1.00；伤害、攻击前后摇、射程、弹速、连发间隔等不变。攻击位移技能仍按原攻击参数执行，太阳与感知策略沿用既有契约。Owner仍是Enemy3D，表现只消费状态与速度，不写回玩法。

## 确认的问题与改动

1. **慢走被误判卡住**：旧判据要求单帧位移超过0.025m，60Hz相当于1.5m/s；受光慢走会每0.8秒触发恢复侧推。改为水平实际进度至少达到期望进度20%，与帧率及减速倍率无关；真实堵死仍在0.8秒触发恢复。
2. **避障侧逐帧翻转**：`_stuck_time>0.38`时每次射线避障都翻侧，形成左右抖动。现在只在完整卡住恢复时翻侧。
3. **远程绕障方向被覆盖**：`_navigation_direction`已给出(0.707,0,-0.707)，远程逼近却覆盖成(1,0,0)。现在保留导航方向；射程内但隔墙时也继续绕行。
4. **布洛布接触攻击隔墙扣血**：攻击入口有LOS，但前摇期间门/障碍变化后，最终接触结算未复核。结算时补LOS，无遮挡命中仍受测。
5. **胖子模型未覆盖旧受光修复**：手电阶跃时满速分母突变，walking↔running两次硬切。补同口径平滑、迟滞，并让速度选段/启动事件结束也从当前骨姿势过渡。三种模型单帧最大骨旋转分别4.092°、5.157°、10.382°；胖子旧版77.234°/两次换段，修后零换段。
6. **移动淡化遮住战斗动作**：小僵尸/保安在0.16秒淡化内改变到攻击时，快照段名变了但播放器仍在跑步。现在当帧取消移动淡化、采样攻击进度；淡化相位直接读取引擎播放位置，消除结束帧两条时钟不同步。
7. **移除33只变种附加件**：删除EnemyAvatar3D的Distinction挂载入口，快照不再报告历史shape/anchor。保留体型、染色、既有本体和武器。历史Distinction表留作追溯；生产路径不再建球、方块、冠、罐等标识件。`_egt_presentation_probe`按最新用户契约改验零附加件，原受击/步态/站位断言保留。

不涉及GLB、Blender、资产路径/版本/哈希、内容ID、存档schema或怪物基础数值表；无需重导或批量接受账本哈希。照射倍率的唯一运行真源是Enemy3D，设计与测试同步；未修改关卡专属生成规则。

## 验收与反向对照

所有Godot进程在启动前分别隔离APPDATA、LOCALAPPDATA、XDG_DATA_HOME、XDG_CONFIG_HOME，产物通过workspace_paths定位至工程外`ShellStorm2-work/sessions/2026-11-02_enemy_ai/`。没有依赖场景内test_mode保护正式档。

| 用例 | 退出码/结果 | 预期故障 | 非预期错误 |
|---|---|---|---|
| 新增verify_enemy_light_motion_regression | exit0；33种×4次光照往返、30/60/120Hz慢走、真实堵死、导航障碍、遮挡命中、三套动画 | 无 | 最终clean日志0条 |
| 工程外original方法/原动画对照 | exit1，确认慢走误报/翻侧/覆盖导航/隔墙扣血/攻击淡化/胖子77.234°等均被检出 | 这些断言失败为预期 | 无脚本编译错误 |
| verify_enemy_illumination_states | exit0，真实手电锥体/墙遮挡/太阳/迟滞 | 无 | 0条 |
| verify_monster_ai_light_effects | exit0，40%移速/100%攻击计时及原感知策略 | 无 | 0条 |
| _egt_presentation_probe | exit0，33只无附加几何，受击与站位断言保留 | 无 | 0条 |
| _egt_variant_visual_probe | exit0，现有体型/染色仍可区分 | 无 | 0条 |
| _egt_facing_probe | exit0 | 无 | 0条 |
| verify_3d_enemy_behavior_flow | exit0，原寻敌/物理/分离/攻击基础链 | 无 | 0条 |
| verify_monster_startup_roar | exit0，229项 | 无 | 0条 |
| _egt_enemy_motion_probe | exit0，两个种子真实进房战斗，未出房/穿地 | 无 | 0条；现有资源UID警告保留 |
| verify_monster_ai_system_complete | 改前改后均exit1 | 无 | 同两条旧失败：同帧2近战+2远程令牌、释放立即复用；与已有房间470ms攻击节拍器相冲突。本次不删断言/不改玩法消红 |

探针修正：旧`_egt_ai_flow_probe`直接erase常量Profile，触发read-only并导致抓握大师在单怪场地自杀，现改为先复制Profile再删除仅用于探针的`die_when_others_dead`。同时去掉入树后两次多余Profile重建（ready已应用指定怪种），避免material null干扰。最终`roster_clean__egt_ai_flow_probe`全33只体检完成、exit0、日志门禁exit0、无SCRIPT ERROR/ERROR；三只怪27次房间窗口轮转无相邻重复。单怪6秒观察窗口不能证明抓取等长周期技能全程正常，不能把观察报告当成每种机制全部验收。

新测试早期曾原地把保安切为布洛布，产生material null错误；改为各怪独立实例后最终clean日志无ERROR，不列为通过的早期结果。真实渲染最终结果与静态门禁如下。

### 真实渲染与工程门禁

- Compatibility / NVIDIA RTX3060真实渲染`--visual`：exit0、日志门禁exit0、无非预期ERROR，三模型各保存暗处/照射中/离光后3帧，共9张；位于本次工程外产物的`visual_final/`。独立6种怪画廊`gallery/egt_no_attachments.png`亦exit0且日志门禁exit0，确认原模型上无变种标识附加件。画廊中的炸弹/召唤师原有程序化本体仍在，本次移除的是额外挂件。
- `check_level_decoupling.py`：exit0，7个共享容器零违规。
- `check_feature_traceability.py`：exit0，43功能追溯通过；新增专项已进core清单。
- `check_documentation_contracts.py`：exit1，45项现有问题（历史图片/备份链接、3个不相关未登记测试、Python环境缺openpyxl等）；新记录与测试无缺失引用。不以文档检查代替运行结果。
- `check_asset_runtime_naming.py --quiet`：exit1，8个既有带版本GLB.import及11个既有脚本引用组；本次无新增资源路径。
- `check_workspace_hygiene.py`：exit1，现有outputs/output/_scratch/Godot目录及缺export_presets.cfg；本次所有临时产物均在工程外，未清理其他会话目录。
- `git diff --check`：exit0。完整结果与日志见本次工程外`static_checks.json`、`check_results.json`，未给上述非本次范围红项新增白名单。

## 边界与未执行项

未运行全量core/full、Android及长时间多人压力；完整关卡仍partial，专项通过不能提升整个ENEMY-AI/ASSET-PIPELINE完成状态。房间导航仍采用既有轻量面+局部射线，未新增运行时家具烘焙；复杂U形死角的全局路径规划仍需要专门覆盖。已打开的游戏需重新运行以加载脚本。

改动前逐文件副本位于`ShellStorm2-backup/2026-11-02_enemy_ai/before_edits/`；回滚按文件比对，禁止整树覆盖其他会话成果。
