# ShellStorm2 开发日志

## 轮次 444 | 2026-05-30 23:41

### 本轮维度
**DemoRoomGameMode ExtractionModule 信号预连接**

### 问题识别
DemoRoomGameMode 的撤离 HUD countdown_bar 不显示，进度条没有实时更新。虽然 `show_extraction_room_countdown(5.0)` 会触发 `_start_extraction_countdown_ui`，但 `_on_extraction_progress_updated` 信号没有连接，所以 `countdown_bar` 的 `value` 永远是 0。

### 玩家可感知结果
- Demo 撤离读条时 countdown_bar 进度条能正确显示进度（而非静止不动）
- 中断按钮 abort_button 正确响应

### 修改文件
- `src/game/DemoRoomGameMode.gd`: 在 `_get_extraction_module()` 懒初始化时提前连接 `_connect_extraction_module_signals`，并移除 `_try_start_extraction` 中的重复连接逻辑

### 验收
- Demo 8房间链 R8撤离房按 E 后，countdown_bar 进度条从 0→1 实时更新
- abort_button 能正确中断撤离

### 风险
- 轻度代码清理，无破坏性风险
- ExtractionModule 信号连接时机更早，但只连一次（防重复连接）

### 下一轮方向
- 人类试玩验证 Demo 8房间链路（卡片弹窗+撤离+HUD+Boss HP条）
- 继续完善战斗视觉反馈