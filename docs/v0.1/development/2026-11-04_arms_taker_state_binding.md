# 精英02收租人状态接线r2与专项验收

FeatureID：ELITE-ROSTER / ENEMY-AI / ASSET-PIPELINE。工程版本：0.1.0。日期：2026-11-04。依据：[精英02收租人状态与动作契约](../design/精英02收租人状态与动作契约.md)，用户要求按显示器Boss的方式正式调整并解决瞬移、反向行走。

## 原因与修改

源GLB实际正面为+Z，正式包装却声明-Z且没有坐标转换；walk/run 的Hip每轮前进约3.285/3.610米，再叠加Enemy3D物理移动，循环末端出现数米回跳。旧表现采样同时advance和seek、状态切换清步态相位，外层还叠加程序bob。原攻击只占一个物理帧，套普通怪短前后摇；独立精英又按小僵尸基类即时销毁，死亡动作不可达。

- 新增 `src/enemy3d/EliteArmsTakerCombat.gd`，由Enemy3D持有，提供begin/cancel/tick/presentation_context，与显示器Boss同样单向输出行动上下文。三段攻击连续采样attack_light：40/30秒判定一次，44/30秒进入收招，80/30秒结束；保留原伤害、弹幕数量/成长与夺械规则。背对目标时先完成转身再起手，命中帧复核遮挡、距离和前方扇区。
- VisualGLB固定绕Y转180度；实例独立动画库对walk/run曲线去首尾线性漂移，保留源姿势、侧摆和接地曲线，不修改源GLB或全局共享库。真实速度、角色缩放、实测步幅共同控制相位；唯一play+seek采样，移除advance争用；骨骼精英退出外壳程序姿势。
- 硬直、休眠、逃脱、死亡、丢目标和读档均收口旧行动；hit保留2秒，death保留4.6秒。死亡立即退出战斗与碰撞，动画结束再回收；首只精英、普通怪和显示器Boss仍走各自既有接线。
- 行动内外部速度直接施加，消除逐帧重复相加造成的加速；2秒受击动作不延长基类短击退时窗。新增5项牵引/击退/过期检查，确认既不会吞外力，也不会产生额外冲刺。
- 修正旧 `probe_second_elite_motion` 漏await导致提前退出的问题。采样延长到1秒、测全部骨骼角变化；保留原阈值，不以三个骨骼的欧拉长度求和代替姿势变化。

## 验收结果

Godot 4.7.2；工程外隔离项目和导入缓存；Autoload启动前独立APPDATA。逻辑场景直跑并单独执行日志门禁；视觉场景使用Windows真实渲染器NVIDIA GeForce RTX 4060 Ti，运行实际SceneTree物理和表现回调。不是全量套件验收。

| 入口 | 引擎退出码 / 日志门禁 | 证据 |
|---|---|---|
| verify_second_elite_state_flow | 0 / 0 | 802检查；连续行动时钟、一次判定/完整后摇、硬直/休眠/冻结/丢目标/逃脱、遮挡、恢复、循环与死亡回收 |
| verify_second_elite_state_visual | 0 / 0 | 1184检查、590连续真实帧；慢走7秒、跑步3.5秒，跨多个步态循环 |
| verify_second_elite_arms_taker | 0 / 0 | 目录/41骨/18剪辑/十二态映射/碰撞与投放窗口 |
| probe_second_elite_motion | 0 / 0 | 修正异步等待后，逐态全部骨骼采样通过 |
| verify_unique_elite_roster_flow | 0 / 0 | 唯一名册与行为、预约、成长、转译、迁移 |
| verify_first_elite_growth_flow | 0 / 0 | 首只精英逃脱/成长回归 |
| verify_3d_enemy_behavior_flow | 0 / 0 | 普通怪行为/生命/重力/碰撞/分离回归 |
| verify_monitor_boss_flow | 0 / 0 | 591检查，显示器Boss回归 |
| verify_expedition99_pre_boss_elite | 0 / 0 | 99前置房点名配置、生成链和投放窗口回归 |

真实渲染实测：慢走Hip最大逐物理帧位移0.018286m，奔跑0.065620m；身体正面与实际移动方向的最小点积均为1.0。攻击在1.33秒命中一次，判定帧物理速度0；受击与死亡均由相应状态选择源剪辑。

预期故障注入：无。最终上述场景非预期脚本错误：0；资源泄漏：0。开发中一次新增测试的WeakRef类型推断导致编译失败，已修正重跑；旧动画探针在补await后暴露短采样不足，改为全骨骼1秒采样后通过，未降低阈值。新增源/实例资源隔离断言初版误取了待释放默认Avatar的AnimationPlayer，引擎虽退出0但日志门禁拒绝；修正为正式精英根后重跑，原GLB走跑位移保留、实例曲线原地化且资源对象独立，日志错误与泄漏清零。

## 证据、登记与限制

全部日志、原始帧、report.json、约19.7秒MP4、改前哈希与台账逐格差异位于工程外 `ShellStorm2-work/sessions/2026-11-04_arms_taker_state_binding/`。视频为 `arms_taker_r2.mp4`，原始图在 `visual/frames/`。改前文件保存在 `ShellStorm2-backup/2026-11-04_arms_taker_state_binding/before_edits/`。

敌人分账本仅本资产主表5格、3D-敌人3格、敌人动画与状态2格更新，并追加域日志；基线仅接受本资产行及两张已核对分页，其他资产行指纹不变。Prefab SHA-256：`5e11849d37cb2c4d0a4abbcf5d9f2f5ee7a648be0ccd92ce0a6b6f5dbefb0710`；源GLB仍为 `074fac37e635d6d4b73c5e274b5ec61e1611a5ed07f3c38d8436d5b0abf91449`。清单与中转只更新本轮修改的表现脚本、包装和状态接线凭据。

未执行：全量套件、全关卡长时/目标设备性能、全部存档矩阵。其余12条源动作没有新造专属玩法；当前灰色无贴图材质来自原GLB，本轮没有重做美术。文档与资产门禁结果在本记录收尾段单独列明，不用专项通过替代全局门禁。

## 收尾门禁

敌人域资产full、台账拆分无损基线、运行资产命名、账本引用、关卡解耦均通过（退出0）。正式目录原有4份`.bak`脚本已按SHA-256保留到本轮备份的original_tree，迁移清单在management/runtime_backup_moves.json，内容未删。

全局文档契约退出1：15条既有断链，以及4个既有未登记用例（verify_base_lamp_dynamics、verify_base_lamp_visual、verify_enemy_action_recovery、verify_stairwell_turn_rail）；本轮新增两项已登记。工作区卫生退出1：工程原有outputs、_scratch、Godot目录；未对其他会话产物做批量清理。这些结果单列保留，不把专项通过写成全局验收通过。
