# 远征99测试入口迁至 Esc

日期：2026-11-19。FeatureID：WORLD-ENTRY / UI-HUD。仅迁移开发测试入口，不改远征01与99共用 Boss 房、关卡配置、发布预设或解锁规则。

## 接入与使用

用 Godot 编辑器运行项目，在正式 99F 基地地面安全区按 Esc（手柄 Start），选择「远征99（测试）」。沿用暂停页焦点及按钮样式，默认焦点仍为「继续行动」。按钮不在发布包、标题设置、天台、战斗区或独立远征中展示。存在其他暂停占用、剧情或未完成的场景交接时拒绝启动。

远征情报室原已按目录隐藏测试关，本次封住旧回调绕过路径，保留四个正式目标。新入口经 `ExpeditionDepartureService` 交接检查点、`GameEntryFlow` 登记请求，再由 `ExpeditionLoadingScreen` 读取目录目标；切场景前只解除手动暂停，失败时撤回请求及选关并尝试还原检查点，不清其他暂停占用。进入读取页后的重试/失败由原加载链负责。

## 实测与门禁

- Godot 4.6.3 Compatibility，1280×720，键盘与手柄各 10 项通过，退出码、日志审计均为 0。使用隔离档、真实游戏窗口和 Godot 键盘/手柄事件：Esc 或 Start 打开，方向键或十字键取得焦点，Enter 或 A 通过正式读条进入 99，目标场景不继承暂停和待选关。实际画面核对按钮可见性、焦点及其他主菜单项；没有接物理手柄。基地使用受控出生点，目标使用正式加载流程。
- `verify_test_level_99_flow` 退出 0、审计 0，确认四个正式目标保留、远征01仍可用、99 旧回调不产生出发意图。`verify_main_story_navigation`、`verify_hologram_unlock`、`verify_pause_game_save_reset_flow`、`verify_gamepad_input_flow` 均退出 0、审计 0。批量运行到最后一个 99 项时超时，该项已独立复跑通过。
- `verify_expedition_level01_flow` 出口 1、审计 3：其情报室检查未报错；全关仍有旧名称断言、墙体碰撞/元数据和宝箱相关失败。本轮未为整套宽回归建立改前对照，故不签署 01 全关通过。
- 仅更新现有 UI 账本 `UI-SCREEN-PAUSE-3D`（v002、场景 SHA）和 `UI-SCREEN-LEVEL-SELECT`（行为说明），同步对应基线；没有新图标、样式资源、Prefab 或资产编号。媒体域校验通过；UI 全量余 5 条未涉及资源 SHA 漂移，分账本校验余 24 项。
- 验收登记、关卡解耦及运行资产命名门禁通过。全局文档门禁仍为 exit 1，报告本次范围外的断链和前序 BOSS-STAGES 验收登记问题；没有本次 Esc 入口的新增登记错误。
- 未实测发布包、移动端或故障注入后的检查点回滚；发布限制使用引擎自带 `editor` 特性守卫，未改发布预设。

日志与截图：工程外 `ShellStorm2-work/sessions/2026-11-19_esc_expedition99/`（`keyboard-verified.log`、`pad-verified.log`、`99-flow-final.log`、`keyboard-final.png`）。
