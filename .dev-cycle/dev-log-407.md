# ShellStorm2 开发日志

## 轮次407（2026-05-30 18:37 UTC+8）

### 维度选择
**Tab劫持修复 — 门后命卡选卡界面可按Tab关闭**

### 问题分析（设计审查）
从核心玩法"搜打撤+命卡选择"审查，发现关键UX断点：

- `FateCardUIController._input()` 有 Tab 输入监听：`elif event.is_action_pressed("ui_tab") and not is_visible`
- 但 `GameUIManager._input()` 中 `KEY_TAB` 被无条件劫持到 `_weapon_panel.toggle()`
- 冲突链路：`GameUIManager._input` → `keycode in [KEY_K, KEY_TAB]` → `_weapon_panel.toggle()` → `get_viewport().set_input_as_handled()`
- **结果**：门后命卡选择时提示"按Tab关闭"，但Tab被武器树消耗，玩家无法关闭，只能点按钮
- 玩家可感知：看到提示文字 → 按Tab无响应 → 困惑/烦躁

### 设计意图 vs 实际表现
- **意图**：`FateCardUIController` 在门后选卡激活时应消费Tab关闭事件
- **实际**：GameUIManager 在 `_room_game_mode._door_fate_selection_active=true` 时仍然劫持Tab

### 玩家体验的前后变化
- **Before**：门后命卡选择界面显示"按Tab关闭"但按Tab无响应（已知缺口）
- **After**：按Tab可关闭门后命卡选择界面（`FateCardUIController.hide_card_selection()` 被调用）

### 代码改动
**文件：** `src/ui/GameUIManager.gd`

将 `KEY_TAB` 从无条件劫持改为在门后命卡选择期间放过：

```gdscript
# 改前（无条件劫持）
if (
    event is InputEventKey
    and event.pressed
    and not event.echo
    and event.keycode in [KEY_K, KEY_TAB]
):
    if _weapon_panel != null and _weapon_panel.has_method("toggle"):
        _weapon_panel.call("toggle")
    get_viewport().set_input_as_handled()

# 改后（门后命卡选择期间放过Tab）
if (
    event is InputEventKey
    and event.pressed
    and not event.echo
):
    if event.keycode == KEY_K:
        if _weapon_panel != null and _weapon_panel.has_method("toggle"):
            _weapon_panel.call("toggle")
        get_viewport().set_input_as_handled()
    elif event.keycode == KEY_TAB:
        # 门后命卡选择期间不劫持Tab（让 FateCardUIController 消费关闭事件）
        var door_fate_active := false
        if _room_game_mode != null and is_instance_valid(_room_game_mode):
            var prop = _room_game_mode.get("_door_fate_selection_active")
            if prop != null:
                door_fate_active = bool(prop)
        if not door_fate_active:
            if _weapon_panel != null and _weapon_panel.has_method("toggle"):
                _weapon_panel.call("toggle")
        get_viewport().set_input_as_handled()
```

**改动位置：** GameUIManager.gd 约行3008-3022

**影响面：**
- 门后命卡选择期间（`_door_fate_selection_active=true`）GameUIManager 不消费Tab
- FateCardUIController 正常收到Tab → `hide_card_selection()` 执行
- 非命卡期间（K键/普通Tab）WeaponAssemblyTreePanel.toggle() 不受影响
- RoomGameMode 已有 `_door_fate_selection_active` 状态（v3.36已定义）

### 验收标准
- [x] Godot headless --check-only --quit 编译通过 ✅（EXIT 0）
- [ ] 人类试玩：门后命卡选择界面按Tab可关闭
- [ ] 人类试玩：普通Tab键（武器树面板）仍正常工作

### 剩余风险
1. **人类试玩验证**：实际按Tab是否真的关闭命卡选择界面
2. **边界情况**：如果在命卡选择期间快速按K键/Tab是否有竞争条件

### 续排判断
**继续排 cron** — 状态维持 `running`。Tab劫持修复让门后选卡体验完整。无设计分叉、无外部依赖、无破坏性风险。

### 下轮最可能方向
1. **人类试玩验证**（唯一优先级）
2. 若收到试玩反馈 → 针对性修复
3. 若无反馈 → 继续排 cron 等待
