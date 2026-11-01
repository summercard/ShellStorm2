# 光标前视、受伤震屏与战败滤镜

日期：2026-11-02。工程0.1.0；FeatureID：PLAYER-STATE / RUN-SETTLE / GRAPHICS-POSTFX。来源：用户要求参考《逃离鸭科夫》《挺进地牢》的前视/震屏，以及2秒蓝白干扰后降饱和50%、提高对比20%再开放结算。改动起点以会话开始文件备份为准；收尾HEAD为`7f05821806611ec552e434d6cb3e9cc70ee89f80`，含会话开始时的已有工作区；不覆盖其他在途改动。

设计主源：[玩家与操作§6.1](../03_技术施工_玩家与操作.md)、[结算设计](../design/基地经济与存档结算设计.md)、[画质设计](../design/时间日夜与画质设计.md)。参数是本项目适配值，不冒称参考作品内部参数。

## 实现

`PlayerCameraFeedback3D`拥有前视与受伤投影偏移。身体附近约65px（720p短边）稳定区，外移平滑增强至最多1.25m；指数速率7.5/s，回中也平滑。塔楼/远征相机装配器在原有机位上叠加前视，并继续执行房间夹取、墙体与楼板约束；移动端/手柄、模态输入锁、失焦/出视口或死亡时不响应光标。剧情/设施接管清除反馈。独立Player场景复用同一状态与相机，不创建第二套跟随器。

有效战斗伤害穿透护盾后产生`damage_received`，触发0.24s双频短促震屏；幅度0.065～0.11m、平方包络衰减。拒绝伤害、治疗与生命消耗不震屏，重复命中不累积永久偏移；瞄准射线排除震屏偏移，HUD不跟着抖。

致命受击在原`hp_changed`接线中启动场景所有的`DefeatTransition`；2秒蓝白扫描带/噪点/水平撕裂渐退，最终饱和度系数0.50、对比度1.20。滤镜在HUD下，原低血量红晕在死亡时退出，避免覆盖蓝白干扰。倒地与滤镜并行，两者均完成才开放原结算框和按钮；提前返回拒绝，代际守卫阻断过期回调，新行动复位/卸载清除滤镜。存档、保险、奖励与事务幂等不变。

活动输入源以`InputDevice`的当前设备为准，不能以虚拟摇杆Autoload存在与否判断桌面输入；两者在PC也存在。真实鼠标注入使用Viewport坐标，兼容1280逻辑视口→960窗口缩放。

UI沿用`UIStyleFactory.make_prism_confirm_modal`及既有按钮，没有新增图片/模型或替换账本所指资产；新增Shader是代码表现资源，不新增媒体资产ID或接受旧哈希漂移。设计、技术施工、功能索引、机器登记、manual专项与开发入口同步。

## 隔离与验收

工程外`workspace_paths.work_path()`创建独立项目；目录Junction复用运行资源，单独`project.godot`设置custom_user_dir。Autoload之前实测guard退出0，用户目录和BaseManager.save_path均为`ShellStorm2CameraFeedback20261102`，正式project.godot与用户档未改。原生Forward+使用RTX3060/Vulkan、960×640；已亲眼检查两场景0.5s干扰与2.15s结算截图。

| 项目 | 退出码 / 非预期脚本错误 | 结果 |
|---|---|---|
| 改前`verify_death_during_extraction_flow` | 0 / 0 | 原结算时序基线通过 |
| 改前`verify_tower_camera_occlusion_flow` | 1 / 0 | 既有镜头失败，保留日志供逐项对照 |
| `verify_player_camera_defeat_feedback` headless最终 | 0 / 0 | 52项、0失败；包含活动输入设备与瞄准稳定性 |
| `verify_player_camera_defeat_feedback`真实Forward+ | 0 / 0 | 72项、0失败；塔楼与03正式场景，实际鼠标/键鼠-手柄-触屏切换/瞄准不受震屏影响/前视/上限/回中/伤害门槛/震屏衰减/2秒双门闩/代际与清理，12张截图 |
| 最终调色像素及UI分层 | 0 / 0 | 测试色(0.2000,0.6000,0.2980)→(0.3137,0.5569,0.3765)，理论(0.3159,0.5559,0.3747)，误差<0.004；HUD校准色不变。测量临时隐藏HUD遮罩后恢复，正式画面保留原结算压暗 |
| `verify_hud_presenter_3d` / `verify_postfx_overlay_runtime` | 0 / 0 | 既有HUD映射与颗粒参数专项通过 |
| `verify_death_during_extraction_flow`最终 | 0 / 0 | 四时序与成功/死亡/新行动/返航保护反向对照通过；等待标准随用户设计更新为2秒并行表现，而非放宽原事务断言 |
| `verify_run_settlement_transaction` | 0 / 0 | 原子写盘、失败回滚、重试、跨重载与幂等通过 |
| `verify_debug_camera_hotkeys` | 0 / 0 | 拉远/偏航/复位通过 |
| `verify_tower_camera_occlusion_flow`最终 | 1 / 0 | 10条ERROR与改前逐字相同，集中在旧98F门墙/枢纽/楼梯围护标签及夹镜判据；没有新增错误、未改阈值 |
| `python3 scripts/check_documentation_contracts.py` | 1 | 43处已有断链和3个旧场景未登记（合为1项），共44项；本专项已登记，不新增断链 |
| 功能追溯 / 媒体域检查 | 0 / 0 | 43个FeatureID追溯与3个媒体域205资产通过 |
| `check_asset_registry.py --ledger ui` | 1 | 18资产中7条已有sha_mismatch（HUD场景、选关、保险、背包、暂停、贩卖、命运来源）；均非本次修改文件，未回填掩盖漂移 |
| `check_level_decoupling.py` | 0 | 7个共享机制容器、0违规 |
| 运行资产命名 / 工作区卫生 | 1 / 1 | 已有带版本运行路径/生产引用，以及outputs/output/_scratch/Godot目录和缺失export_presets；本批未新增此类路径/目录 |

预期故障：无产品故障注入；开发途中编译类型检查和校准时混入HUD遮罩的失败均已修正，不计最终通过。UID路径回退WARNING单列于日志，正式路径成功加载；最终专项0非预期ERROR/0脚本ERROR。

未执行：完整smoke/core/full、移动端/手柄设备、长时间性能与全流程人工手感验收。未提升PLAYER/RUN/GRAPHICS整体partial状态。

证据：`ShellStorm2-work/sessions/20261102_camera_feedback/`（guard、前后日志、像素记录、captures）；改前备份：`ShellStorm2-backup/2026-11-02_camera_feedback/before_edits/`。所有产物位于工程外；未提交或推送。
