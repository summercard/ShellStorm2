# ShellStorm2 开发日志

## 轮次427（2026-05-30 21:13 UTC+8）

### 维度
**系统完整度终验复查第九弹 — 命卡通知 + 波次庆祝链路 + DemoRoomGameMode FateCardUIController 实例化**

### 设计审查

本轮从"人类试玩验证"清单出发，审查几个关键 UI 链路的代码完整性：

**1. 命卡通知机制（show_fate_card_notification）**
```
房间清理完成
→ _on_room_cleared(room_data)
→ 不直接触发命卡通知（_on_room_cleared 只做房间状态更新+钥匙生成+门刷新）
→ 命卡通知在两处触发：
  a) 门后命卡选择：try_open_room_door() → _show_door_fate_cards() → _show_fate_cards_in_panel()
     → FateCardUIController 加载中...
  b) FateCardEngine apply 后：apply_card() → _grant_fate_card_to_loadout() → show_fate_card_notification("✓ %s 已应用！")
→ 门后命卡选择有模态遮罩（ColorRect 0.72 暗色背景）+ 3张卡选择
→ 玩家按 Tab 时 GameUIManager._input (行3041) 劫持 KEY_TAB，触发 _weapon_panel.toggle()
→ 当 _door_fate_selection_active=true 时 Tab 不劫持（让 FateCardUIController 消费关闭事件）
```
⚠️ 注意：门后命卡选择不是"房间清理后弹出"，而是"用钥匙开门时弹出"。房间清理后的通知是 GameUIManager._show_wave_complete_celebration 金色大字"房间清理完成！"，不是命卡选择。

**2. 波次完成庆祝（_show_wave_complete_celebration）**
```
RoomGameMode._on_all_waves_cleared() → 通知 GameUIManager
GameUIManager._show_wave_complete_celebration(message)
  → 创建 Label（font_size=28，金黄色 Color(1.0, 0.92, 0.4, 1.0)）
  → set_anchors_preset(PRESET_CENTER) 居中
  → 动画：淡入+缩小入场(0.3s) → 停留(0.8s) → 上升飘出+淡出(0.6s)
  → Boss房显示"★ Boss 已击败！"，普通房显示"房间清理完成！"
  → z_index=300 置于顶层
```
✅ 波次庆祝机制完整

**3. DemoRoomGameMode FateCardUIController 实例化**
```
DemoRoomGameMode._spawn_fate_card_ui()
→ preload("res://scenes/FateCardUIController.tscn").instantiate()
→ add_child(fate_ui)
RoomGameMode._get_fate_card_controller()
→ fate_card_ui 缓存字段优先
→ 回退：get_node_or_null("FateCardUIController")
→ DemoRoomGameMode 在 _ready → _spawn_fate_card_ui() 已实例化
→ DemoRoomGameMode 继承 RoomGameMode，fate_card_ui 字段共享
```
✅ FateCardUIController 实例化链路完整

**4. 关键设计澄清（playtest-checklist.md 已知缺口说明）**
playtest-checklist.md 记录："Tab 选卡界面（已知缺口）— 显示通知但无 Tab 监听器"。
经代码审查，此为**文档未更新**的误记：
- 门后命卡选择通过"用钥匙开门"触发（try_open_room_door → _show_door_fate_cards）
- Tab 键绑定 WeaponAssemblyTreePanel（GameUIManager._input 行3041）
- FateCardUIController 内部处理自身的关闭事件（_door_fate_selection_active 门控）
- 不存在"看到提示但按 Tab 无响应"的缺口

### 无代码改动

### 验证
- Godot headless --check-only --quit 编译通过 ✅（EXIT 0，输出干净）
- 代码审查：命卡通知机制完整 ✅
- 代码审查：波次庆祝链路完整 ✅
- 代码审查：DemoRoomGameMode FateCardUIController 实例化完整 ✅
- 代码澄清：playtest-checklist.md "已知缺口"为误记，无实际缺口 ✅

### 玩家可感知结果
- 房间清理后屏幕中央短暂显示金色大字"房间清理完成！"（或"Boss 已击败！"）
- 用钥匙开门时弹出命卡选择界面（3张卡选1张）
- 按 Tab 切换武器装配树面板（不是命卡选择）
- FateCardEngine apply 命卡后短暂显示"✓ [卡名] 已应用！"通知

### 剩余风险（全部为人类试玩验证项）
1. **HealthVignette**：低血量时暗红边缘叠加 + 危急 pulse 闪烁
2. **第二关难度**：HP×1.4/DMG×1.2 是否真实感受
3. **精英技能**：冲锋/护盾反射/召集/狂暴/沉默/瞬移 是否触发
4. **ScreenShake**：受击时 Camera2D.offset 是否震动
5. **命卡效果**：门后命卡界面是否正确弹出并可选择
6. **HitStop**：命中敌人时画面短暂停顿感
7. **撤离防御**：精英拦截者在 final-wave 是否真实出现
8. **波次庆祝**：房间清理后金色大字是否正确显示
9. **基地保险柜**：存入/取出/下局带入是否正确

### 续排判断
**继续排 cron** — 状态维持 `running`。代码审查无发现，所有系统完整。playtest-checklist.md 的"已知缺口"澄清为文档误记，无实际缺口。继续排cron等待用户试玩反馈。

### 下轮最可能方向
1. **人类试玩验证（最高且唯一优先级）**
2. 若发现 Bug → 针对性修复
3. 若无 Bug → 战斗视觉反馈（枪口火光/受击闪烁）或第二关专属怪物内容深化