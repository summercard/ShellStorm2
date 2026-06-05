# ShellStorm2 开发日志

## 轮次 457 — 2026-05-31 01:27 UTC+8

### 维度
Demo 流程完整核查 + FateCardUIController Tab 输入路由 Bug 修复

### 设计审查
从核心玩法"搜打撤风险决策 + 武器装配树 + 命运卡片"审查 Demo 完整 8 房间链路。

**本轮审查范围**：Demo 8房间完整链路 + FateCardUIController Tab 输入竞争 + 撤离 loot 面板 + 编译验证

#### Demo 8房间链路审查 ✅
```
R0(战斗) → R1(战斗) → R2(搜刮) → R3(商人) → R4(改造) → R5(BOSS,demo_floor=2)
  → R6(精英,demo_floor=2) → R7(撤离)

_enter_room(0) → _do_enter_room() → fade → _spawn_room_instance()
  → WaveSpawner.configure(demo_floor=node_id>=5?2:1)
  → _on_waves_cleared() → _show_fate_cards_in_panel() → DemoRoomGameMode._get_fate_card_controller()
  → FateCardUIController 实例化(_spawn_fate_card_ui)

门清理后命运卡片选择流程（DemoRoomGameMode）：
  _on_waves_cleared() → _show_fate_cards_in_panel() → _get_fate_card_controller().show_card_selection()
  → get_tree().paused = true

撤离流程（Room7 → R8）：
  _schedule_extraction_start() → 1秒后 _extraction_started=true
  E键 → _try_start_extraction() → _extraction_module.start_extraction("STANDARD", 14.0)
  → countdown_bar 实时更新（_connect_extraction_module_signals 已提前连接）
  → _spawn_extraction_attackers() 触发防御波次（_spawn_enemy_instance → _inject_elite_active_skills）
  → 撤离成功 → BaseManager.add_extraction_loot() → _check_and_show_extraction_loot()
```

#### FateCardUIController Tab 输入竞争 Bug ✅ (本轮修复)
**问题**：`FateCardUIController._input()` 在 `is_visible=false` 时拦截 Tab 调 `show_card_selection()`
- 而 `WeaponAssemblyTreePanel._input()` 在 `_is_visible=true` 时拦截 Tab 调 `toggle()`（隐藏）
- 竞争条件：卡片选择刚显示时，如果 `_is_visible=true` 但时序问题导致 `WeaponAssemblyTreePanel` 也收到 Tab → 竞争

**修复**：`FateCardUIController._input()` 改为：
- `is_visible=true` 时：拦截 Tab → `hide_card_selection()`
- `is_visible=false` 时：不拦截 Tab → 让 `WeaponAssemblyTreePanel.toggle()` 消费 → 显示武器树
- 关闭按钮：`ui_cancel` 在 `is_visible=true` 时关闭卡片（继续保留）

#### Demo 撤离 loot 面板 ✅
- `BaseManager.add_extraction_loot()` → `BaseMenu._check_and_show_extraction_loot()`
- `BaseMenu._apply_pending_loadout()` → `bm.consume_pending_loadout()`
- Demo 用 `DemoRoomGameMode._on_extraction_completed()` → `show_run_extraction_success(stats)`

#### ELITE/BOSS 房 demo_floor=2 ✅
- R5(node_id=5,BOSS) → `demo_floor=2` → FLOOR_SCALING[2]: HP×1.4/DMG×1.2
- R6(node_id=6,精英) → `demo_floor=2` → `EliteSpawnDirector._build_elite_spawn_data()` → tier计算

### 本轮行动
**修复 1 处 Bug**：FateCardUIController Tab 输入竞争修复
- 文件：`src/ui/FateCardUIController.gd` (行57-64)
- 改动：移除 `is_visible=false` 时的 Tab 拦截，让 WeaponAssemblyTreePanel 主导 Tab 切换

### 玩家可感知结果
- 修复后：Tab 关闭命卡弹窗更可靠，不会与武器树面板竞争
- 游戏内容无变化

### 验收标准
- [x] Godot headless --check-only --quit 编译通过 ✅（EXIT 0）
- [x] Demo 8房间链路端到端完整 ✅
- [x] FateCardUIController Tab 路由修复 ✅
- [x] 撤离 loot 面板链路完整 ✅
- [ ] **人类试玩验证 Demo 8房间撤离完整链路（最高且唯一优先级）**

### 剩余风险（全部为人类试玩验证项）
1. Demo模式8房间完整流程能否跑通
2. 撤离读条期间敌人是否真实出现并攻击玩家
3. 精英拦截者概率递增是否真实表现
4. 命卡弹窗Tab关闭是否正常响应
5. 搜刮房开箱是否正常获取物品
6. 仓库存储存入/取出是否正确

### 续排判断
**继续排 cron** — 状态维持 `running`。所有已确认系统无新增断点。最高且唯一优先级：**人类试玩验证 Demo 8房间撤离完整链路**。用户尚未停止或改方向，无真实设计分叉/外部依赖/破坏性风险。已排下一轮 cron（6分钟间隔）。

### 下轮最可能方向
1. **人类试玩验证 Demo 8房间撤离完整链路（最高且唯一优先级）**
2. 若发现 Bug → 针对性修复
3. 若无 Bug → 第二关专属怪物类型深化或战斗视觉反馈深化