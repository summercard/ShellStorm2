# 轮次302 — 2026-05-28 05:42 UTC+8

### 维度
`_complete_extraction()` 撤离积分未执行 Bug 修复

### 当前玩家问题
撤离成功时 `extraction_points` 计算被遗漏 — 本次修改前，`_complete_extraction()` 逻辑中新加入的 `add_vault_item` 代码块覆盖了原有的 `add_extraction_points(points)` 调用，导致撤离积分不再写入。保险柜物品存入功能正常，但魂币积分未赋予。

### 修复内容
**`src/game/CoreCombatMode.gd` — `_complete_extraction()` 函数**

将 `add_extraction_points` 重新加入，与 `add_vault_item` 共存：
```gdscript
# 计算撤离积分（魂币折半）
if _base_manager.has_method("add_extraction_points"):
    points = currency / 2
    _base_manager.call("add_extraction_points", points)
```
确保撤离积分和保险柜物品存入两条链路并行执行，不再互相覆盖。

### 玩家体验的前后变化
- **修复前**：撤离成功 → 面板显示 `points=0`（无积分）→ 基地 Workshop 蓝图解锁无法消耗积分
- **修复后**：撤离成功 → 面板显示 `points=currency/2` → 基地可消费 extraction_points 解锁蓝图

### 涉及代码
- `src/game/CoreCombatMode.gd` — `_complete_extraction()` 函数

### 验收标准
- [x] Godot headless --check-only --quit: EXIT 0 ✅
- [ ] 人类试玩：撤离成功后，基地 Workshop 解锁蓝图时 extraction_points 正确扣减
- [ ] 人类试玩：撤离面板正确显示 `points > 0`（魂币/2）

### 剩余风险
- **人类试玩验证**（最高且唯一优先级）：
  1. 撤离成功 → 积分正确入库 → 基地 Workshop 解锁蓝图消耗积分
  2. 保险柜物品在基地 VaultMenu 中正确显示（带 from_inventory/from_insurance 标记）
  3. 精英冰冻时间对精英减半（Bullet.gd _apply_element_dot）

### 续排判断
**不续排** — 循环状态为 `stopped`，用户已要求停止自动化循环，本轮只做必要 Bug 修复。人类试玩验证是唯一下一步。