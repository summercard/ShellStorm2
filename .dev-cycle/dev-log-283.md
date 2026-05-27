# 开发日志 — 2026-05-28

## 轮次 283 — 2026-05-28 02:22 UTC+8

### 维度
EnemyBase._spawn_damage_number 死代码清理（GameUIManager.show_damage_popup 已完全接管）

### 问题发现
审查代码链路时发现 `_spawn_damage_number()` 中存在两层实现：
1. **第一层**：`get_tree().call_group("game_ui", "show_damage_popup", ...)` — 正确实现，委托给 GameUIManager
2. **第二层**（紧随其后的 `return` 之后）：一段约70行冗余代码，直接实例化 DamageNumber.tscn 并手动创建 Label+Tween 动画

第二层代码**永远无法被执行**（`return` 语句在它之前），属于遗留的死代码，且第一层已经通过 GameUIManager 的 `show_damage_popup()` 提供了完整实现。

### 修复内容
**`src/enemy/EnemyBase.gd`：**
- 删除 `_spawn_damage_number()` 中 `return` 之后的所有冗余代码（约73行）
- 函数简化为仅保留一行：`get_tree().call_group("game_ui", "show_damage_popup", world_pos, dmg, is_crit)`
- 函数体从约76行缩减至2行

### 验证
- Godot --headless --check-only --quit: EXIT 0 ✅
- verify_fate_card_pool.gd: PASS 28 playable cards ✅

### 玩家可感知结果
无功能变化（原有功能完全通过 GameUIManager.show_damage_popup 保留），仅代码去重。

### 剩余风险
全部为人类试玩验证项：
1. 冰霜/火焰/剧毒子弹视觉效果（DOT/冰冻/毒叠加）
2. 命运卡片系统终验
3. 精英名字+🔫挂枪+落地炮台实际体验
4. FateCardEngine 随机选卡效果（环境命运触发器）
5. 撤离守点强度缩放
6. 伤害飘字（GameUIManager.show_damage_popup 实际渲染）

### 续排判断
- 循环状态：`running`
- 本轮无真实设计分叉、无外部依赖、无破坏性风险
- 发现一个可清理的代码债务，立即清理
- **不续排**：轮次279结论"系统完整度已满足全面终态标准，后续工作应由人工主导"，轮次281/282结论"等待用户主导人类试玩验证"。本轮执行完毕后停止，等待用户指令。

### 下轮最可能方向
1. 人类试玩验证（唯一最高优先级）
2. 若发现 Bug 则修复；若未发现 Bug 则推进下一项内容丰富
3. 用户主导决定下一步方向