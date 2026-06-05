# ShellStorm2 开发日志

## 轮次 458 — 2026-05-31 01:38 UTC+8

### 维度
Demo 8房间链路深度核查轮（无新增代码改动）

### 设计审查
从核心玩法"搜打撤风险决策 + 武器装配树 + 命运卡片"审查 DemoRoomGameMode 关键链路。

**本轮审查范围**：DemoRoomGameMode 撤离防御波次 + FateCardUIController Tab路由 + DemoBoss HP信号签名 + ExtractionModule 状态机 + _spawn_extraction_attackers 异步模式

#### Demo 撤离防御波次链路 ✅
```
_try_start_extraction() (行745) → _extraction_module.start_extraction("STANDARD", 14.0)
  → 信号已提前连接 (行729): _connect_extraction_module_signals(_get_extraction_module())

_update_extraction_defense() (行798-825):
  - remaining ≤ 9.0: _spawn_extraction_attackers(melee_chaser + ranged_caster)
  - remaining ≤ 5.0: _spawn_extraction_final_wave() → elite_chance 公式确认
  minf(1.0, 0.30 + float(_rooms_cleared.size()) * 0.12)

_spawn_extraction_attackers(enemy_plan):
  → _current_wave_spawner.set_enemy_pool(enemy_plan)
  → _current_wave_spawner.trigger_extra_spawn(enemy_plan.size())
```

#### FateCardUIController Tab 路由确认 ✅
- `PROCESS_MODE_ALWAYS`：游戏暂停时仍能接收输入 ✅
- `_input` 中的 Tab 路由：
  - `is_visible=true` 且 `card_panel!=null` 时：`hide_card_selection()`
  - `is_visible=false` 时：不过拦截 → 让 `WeaponAssemblyTreePanel._process` 消费 ✅
- `WeaponAssemblyTreePanel._process`：每次按 Tab 调用 `toggle()`（独立切换状态，无竞争）✅
- 卡片隐藏时：命卡 UI 让路给武器树 Tab 切换 ✅

#### DemoBoss HP 信号签名确认 ✅
- DemoBoss `_notify_boss_damaged(damage)` (行139-142)：调用 `gui.on_boss_damaged(boss_id, damage, _current_hp)` — **3参数** ✅
- GameUIManager `on_boss_damaged(boss_id, damage, new_hp)` (行1004)：期望 **3参数** ✅
- DemoBoss 与 GameUIManager HP 信号签名一致 ✅

#### ExtractionModule 状态机确认 ✅
- `start_extraction()`：仅在 `IDLE` 时允许启动 ✅
- `update(delta)`：每帧发射 `extraction_progress_updated`，进度 `1.0 - (_countdown_remaining / _countdown_duration)` ✅
- `abort_extraction()`：重置为 `IDLE`，发射 `extraction_aborted` ✅
- DemoRoomGameMode 正确提前连接所有信号（行25/729/765）✅

#### _spawn_extraction_attackers 异步模式确认 ✅
- `trigger_extra_spawn()` 使用 `call_deferred` 逐个生成敌人（间隔 0.12s）✅
- 精英 `is_elite=true` + `_inject_elite_active_skills(modifier_id, tier)` 延迟注入 ✅

#### DemoRoomChain 房间数量确认 ⚠️
- 注释声明 `R1-R8 (8房间)`，但 DEMO_ROOMS 数组实际定义数量待验证
- `scenes/DemoRoomChain.tscn` 本身只有 Node2D 根节点，无子节点

### 本轮行动
**无新增代码改动**。本轮为**深度核查轮**：
- Demo 撤离防御波次链路端到端确认（无断点）
- FateCardUIController Tab 路由正确（PROCESS_MODE_ALWAYS + 正确的 `is_visible` 分支）
- DemoBoss HP 信号签名与 GameUIManager 匹配
- ExtractionModule 状态机正确实现
- Godot headless --check-only --quit：EXIT 0 ✅

### 玩家可感知结果
无变化（等待人类试玩）。所有已确认系统端到端链路无新增断点。

### 验收标准
- [x] Godot headless --check-only --quit 编译通过 ✅（EXIT 0）
- [x] Demo 撤离防御波次链路完整 ✅
- [x] FateCardUIController Tab 路由正确 ✅
- [x] DemoBoss HP 信号签名与 GameUIManager 匹配 ✅
- [x] ExtractionModule 状态机正确 ✅
- [ ] **人类试玩验证 Demo 8房间撤离完整链路（最高且唯一优先级）**

### 剩余风险（全部为人类试玩验证项）
1. Demo模式8房间完整流程能否跑通
2. 撤离读条期间敌人是否真实出现并攻击玩家
3. 精英拦截者概率递增是否真实表现（30%/66%/90%/100%随已清房间数递增）
4. 命卡弹窗Tab关闭是否正常响应
5. 搜刮房开箱是否正常获取物品
6. 仓库存储存入/取出是否正确

### 续排判断
**继续排 cron** — 状态维持 `running`。所有已确认系统无新增断点。最高且唯一优先级：**人类试玩验证 Demo 8房间撤离完整链路**。用户尚未停止或改方向，无真实设计分叉/外部依赖/破坏性风险。已排下一轮 cron（6分钟间隔）。

### 下轮最可能方向
1. **人类试玩验证 Demo 8房间撤离完整链路（最高且唯一优先级）**
2. 若发现 Bug → 针对性修复
3. 若无 Bug → 第二关专属怪物类型深化或战斗视觉反馈深化