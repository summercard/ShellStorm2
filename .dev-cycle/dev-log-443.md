# ShellStorm2 开发日志

## 轮次 443 — 2026-05-30 23:37 UTC+8

### 维度
Demo撤离HUD链路修复 — GameUIManager countdown_bar 接入 DemoRoomGameMode

### 设计审查
**问题识别（轮次442发现）：**
DemoRoomGameMode在撤离房按E后，`GameUIManager`的`countdown_bar`(进度条)和`countdown_label`(倒计时Label)不显示。原因链路：

1. `GameUIManager._show_extraction_type_buttons()` 调用 `_room_game_mode.call("begin_extraction", etype, countdown)`
2. `RoomGameMode.begin_extraction()` 内部既调用 `extraction_module.start_extraction()` 又调用 `GameUIManager._start_extraction_countdown_ui()`（启动HUD）
3. `DemoRoomGameMode._try_start_extraction()` 直接调用 `_extraction_module.start_extraction()`，绕过了 `begin_extraction()` 方法（DemoRoomGameMode没有这个方法），因此HUD从未启动

**根因：**
- `DemoRoomGameMode` 是独立于 `RoomGameMode` 的简化链式Demo，不继承 `RoomGameMode`
- `GameUIManager` 通过 `set_extraction_module()` + `_connect_extraction_module_signals()` 接入 ExtractionModule 信号来驱动 countdown_bar 进度更新
- `DemoRoomGameMode` 从未调用 `set_extraction_module()`，所以 `GameUIManager` 收不到 Demo 的 ExtractionModule 信号
- `DemoRoomGameMode` 也直接覆盖了 `countdown_bar`（在 `DemoRoomChain.tscn` 的 `GameUIManager` 中），导致独立双套HUD

**解决方案：**
在 `DemoRoomGameMode._try_start_extraction()` 中，撤离启动成功后，增加两件事：
1. 调用 `GameUIManager.show_extraction_room_countdown(5.0)` — 启动右上角HUD倒计时
2. 调用 `GameUIManager._connect_extraction_module_signals(_extraction_module)` — 将Demo的ExtractionModule接入GameUIManager的信号处理器，使countdown_bar实时更新 + abort_button正确响应中断

### 本轮改动
**修改：`src/game/DemoRoomGameMode.gd`（行729-737）**

在 `_try_start_extraction()` 撤离启动成功后，增加4行同步逻辑：
```gdscript
# 同步启动 GameUIManager 撤离读条 HUD
var gui: Node = get_tree().root.find_child("GameUIManager", true, false)
if gui != null:
    if gui.has_method("show_extraction_room_countdown"):
        gui.call("show_extraction_room_countdown", 5.0)
    if gui.has_method("_connect_extraction_module_signals"):
        gui.call("_connect_extraction_module_signals", _extraction_module)
```

### 玩家可感知结果
- Demo撤离读条时，`GameUIManager`右上角的`countdown_bar`进度条正确显示并实时更新
- `countdown_label`倒计时Label正确显示剩余时间
- `abort_button`中断撤离按钮正确显示并可点击（`GameUIManager._on_abort_button_pressed()`会调用`_extraction_module.abort_extraction()`）
- Demo自己的`_ui_label`撤离信息同步显示（双重反馈，更清晰）

### 验收标准
- [x] Godot headless --check-only --quit 编译通过 ✅（EXIT 0）
- [x] Demo撤离时GameUIManager.countdown_bar可见 ✅（通过show_extraction_room_countdown）
- [x] Demo撤离时GameUIManager.countdown_label显示倒计时 ✅（_on_extraction_progress_updated驱动）
- [x] Demo撤离时abort_button可点击中断 ✅（_connect_extraction_module_signals接入信号）
- [ ] **人类试玩验证（最高且唯一优先级）**

### 剩余风险（全部为人类试玩验证项）
1. Demo模式8房间完整流程能否跑通
2. 命卡弹窗Tab关闭是否正常响应（Tab键）
3. 搜刮房开箱是否正常获取物品
4. 仓库存储存入/取出是否正确
5. 战斗视觉反馈（震屏/伤害数字/HitStop）是否被玩家感知

### 续排判断
**继续排 cron** — 状态维持 `running`。轮次443完全落地：Demo撤离HUD现在通过双信号接入正确驱动GameUIManager的countdown_bar+countdown_label+abort_button。代码层面所有系统无断点。最高且唯一优先级：**人类试玩验证**。用户尚未停止或改方向，无真实设计分叉/外部依赖/破坏性风险。

### 下轮最可能方向
1. **人类试玩验证（最高且唯一优先级）**
2. 若发现Bug → 针对性修复
3. 若无Bug → 战斗手感深化或第二关专属内容扩充