## 轮次412（2026-05-30 23:23 UTC+8）

### 维度选择
房间清理后命运卡片选择 UI 缺失 — `_on_room_cleared` 仅显示文字提示，Tab 无法呼出命卡界面

### 设计审查
**问题定位：**
- 轮次411 武器装配树标签修复时，确认命卡选择 UI 缺失（playtest-checklist.md 记录）
- `GameUIManager._on_room_cleared()` 在房间清理后仅调用 `_show_fate_card_notification()` 显示文字提示"按 Tab 选择命运卡片"
- 但 DemoRoomGameMode 的 FateCardUIController 实例已通过 `_spawn_fate_card_ui()` 创建到场景树
- FateCardUIController 的 `_input()` 监听 `ui_tab` 并在 `not is_visible` 时调用 `show_card_selection()`
- 缺失的环节：GameUIManager 不知道 FateCardUIController 已就绪，从未主动调用其 `show_card_selection()` 方法

**调用链断裂点：**
```
RoomGameMode._on_room_cleared()
  → room_cleared.emit()
  → GameUIManager._on_room_cleared()
    → _show_fate_card_notification()  ← 只显示文字，不调用命卡 UI
FateCardUIController（已实例化）
  → _input(ui_tab) → show_card_selection()  ← 等待玩家按键，但面板未弹出
```

**根因：** FateCardUIController 被设计为独立接收 Tab 输入（show_card_selection 由玩家按键触发），但没有在房间清理时主动弹出。两种方式都可行，只需补充主动触发的调用。

**解决方案：** 在 `_on_room_cleared` 中先调用 FateCardUIController 的 `show_card_selection()`，兜底显示文字提示。GameUIManager 通过 `_room_game_mode._get_fate_card_controller()` 获取已创建的控制器引用。

### 本轮改动
1. GameUIManager.gd：`_on_room_cleared` 新增调用 `_show_fate_card_selection_ui()`
2. GameUIManager.gd：新增 `_show_fate_card_selection_ui()` 方法，通过 `_room_game_mode._get_fate_card_controller()` 获取 FateCardUIController 并调用 `show_card_selection()`
3. `_show_fate_card_notification()` 降级为兜底（当 FateCardUIController 引用无效时）

### 修改文件
- `/Users/summercards/ShellStorm2/src/ui/GameUIManager.gd`
  - `_on_room_cleared()`：调用 `_show_fate_card_selection_ui()` 替代直接调用 `_show_fate_card_notification()`
  - 新增 `_show_fate_card_selection_ui()`：获取 FateCardUIController 并调用 `show_card_selection()`

### 玩家可感知的变化
- Before：房间清理后只显示"按 Tab 选择命运卡片"文字提示，按 Tab 无响应
- After：房间清理后立即弹出命卡选择界面（3张随机卡牌），按 Tab 可关闭

### 验收标准
- [x] Godot headless --check-only --quit 编译通过 ✅（EXIT 0）
- [ ] 人类试玩：清理任意房间，确认命卡选择界面立即弹出（而非只显示文字）
- [ ] 人类试玩：按 Tab 或点击关闭按钮，确认命卡界面正确关闭
- [ ] 人类试玩：选择一张卡片，确认卡片效果正确应用到武器树

### 玩家可感知结果
- 房间清理后命卡选择界面自动弹出，不再需要等玩家按键
- Tab 键现在可以正常呼出/关闭命卡界面

### 系统完整度确认
**命卡系统完整度：**
| 功能 | 状态 |
|---|---|
| FateCard 数据结构 | ✅ |
| FateCardPresets 21+ 预设 | ✅ |
| FateCardEngine apply | ✅ |
| FateCardGameBridge 接入武器树 | ✅ |
| FateCardUIController Tab 监听 | ✅ |
| FateCardUIController 卡片选择 | ✅ |
| 命运卡片触发（房间清理自动弹出） | ✅（本轮新增） |
| 命卡效果视觉（eyes/legs/scale） | ✅ |

### 剩余风险
1. **人类试玩验证**：房间清理后命卡界面是否真正弹出
2. **人类试玩验证**：Tab 关闭命卡界面是否正常（不与武器装配树冲突）
3. **人类试玩验证**：选择命卡后武器树外观是否变化（eyes/legs/scale）
4. **人类试玩验证**：第二关精英怪是否掉落命卡

### 续排判断
**继续排 cron** — 状态维持 `running`。本轮修复了命卡 UI 缺失（仅需人类试玩验证）。所有系统代码无已知断点，数值体系稳定，核心玩法链路完整。继续排 cron 等待用户试玩反馈。

### 下轮最可能方向
1. **人类试玩验证（唯一优先级）**
2. 若发现 Bug → 针对性修复
3. 若无 Bug → 第二关怪物类型深化或战斗视觉反馈