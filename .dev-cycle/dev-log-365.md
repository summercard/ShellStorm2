# 轮次 365 — 2026-05-29 18:33 UTC+8

### 维度
系统审计：命卡/精英/视觉反馈链路连通性验证

---

### 审查结果（自由设计开发循环 — 轮次365）

从核心玩法出发，扫描了三个高优先级"人类试玩验证项"的实际代码链路。

---

## 审查一：冰冻子弹 → apply_freeze 冰冻敌人

**玩家视角问题**：冰霜子弹命中后，精英怪应该冻结0.25秒，普通怪冻结0.5秒。

**代码链路审查**：
- `Bullet.gd`：`apply_fate_stats_from_node()` 从 bullet node 读取 `_fate_freeze_duration = 0.5`、`_fate_freeze_duration_elite = 0.25`
- `Bullet.gd`：`apply_fate_stats_from_node()` 读取 `_fate_fuse_dot_*` 相关字段用于 DOT
- `Bullet.gd`：`_apply_element_dot()` 中，当 `_fate_freeze_duration > 0.0` 时：
  - 调用 `enemy.call("apply_freeze", freeze_dur)`
  - 对精英：`freeze_dur = _fate_freeze_duration_elite`（0.25s）
  - 对普通怪：使用 `_fate_freeze_duration`（0.5s）
  - 调用后立即重置 `freeze_dur = 0`
- `EnemyBase.gd`：`_frozen = true` 时停止 AI 移动，`_freeze_timer` 倒计时到0后恢复
- `EnemyBase.gd`：冰冻视觉通过 `shape.modulate = Color(0.5, 0.8, 1.0, 0.85)` 实现（淡蓝色）

**结论**：链路完整且正确 ✅

---

## 审查二：暴击堆栈（crit_on_kill）→ HUD CritLabel 更新

**玩家视角问题**：用"击杀必暴击"命卡后，每次击杀累积暴击堆栈，暴击计数应显示在 HUD 右上角。

**代码链路审查**：
- `FateCardEngine._apply_crit_on_kill()`：
  - 写入 `target.stats["crit_on_kill"] = true`
  - 写入 `target.stats["crit_damage_multiplier"] = crit_mult`（默认2.5）
  - `set_base_stats(stats)` 持久化到 bullet node
  - `tree.refresh_stats()` 更新树
- `WeaponAssemblyTree._spawn_bullet_from()`：
  - 读取 `bullet_node.stats["crit_damage_multiplier"]` → `crit_mult`（用于最终伤害计算）
  - 优先消费 `consume_crit_on_kill_stack()`（击杀堆栈），否则 10% 随机暴击
  - `_crit_on_kill_stack` 通过 `crit_stacks_changed` 信号广播变化
- `RoomGameMode._on_kill_for_crit_on_kill()`：
  - 监听 `kill_recorded` 信号
  - 每击杀一次调用 `weapon_tree.add_crit_on_kill_stack(1)`
- `RoomGameMode._on_crit_stacks_changed()`：
  - 调用 `_ui_manager.update_crit_stacks(new_count)`
- `GameUIManager.update_crit_stacks()`：
  - 更新 `$GameHUD/CritLabel` 文本和颜色

**问题发现**：`crit_stacks_changed` 信号连接逻辑在 `RoomGameMode._ready()` 的 `_setup_signals()` 中，而不是 `notify_player_ready()` 中。但由于 `Player.weapon_tree` 在 `Player._ready()` 时已创建，信号连接时机是正确的 ✅

**结论**：链路完整 ✅（但需要在实际游戏中验证 crit_on_kill 命卡是否正确注入到 bullet node stats）

---

## 审查三：精英名字 + 挂枪视觉标签

**玩家视角问题**：精英怪物头顶显示生成名字（如"背枪的孢子射手"），并显示枪械标记🔫。

**代码链路审查**：
- `EliteArchiveModule.generate_elite_name()`：
  - "背枪的"来自 `stolen_modules` 中有 GunBody
  - "孢子射手"是基础怪物名
  - "吞弹者·"来自特定词缀
- `EnemyBase._set_elite_name_label()`：
  - 读取 `data.name`
  - 设置 `_state_marker_label` 金黄色文字
- `EnemyBase._set_elite_equipment_visual()`：
  - 检查 `stolen_modules` 中是否有 GunBody 类型
  - 有则在名字上方创建 Label 显示 `🔫`
  - 缩放比例与 `_state_marker_offset_y` 配合放在名字上方

**问题**：GunBadge Label 的 Y 偏移基于 `_state_marker_offset_y`，如果精英名字很长可能导致重叠。

**结论**：链路完整 ✅（实际表现依赖精英偷到枪械模块）

---

## 验收标准（对应人类试玩验证项）

| 验证项 | 预期结果 | 当前状态 |
|---|---|---|
| 冰霜子弹命中冻结效果 | 普通怪0.5s/精英怪0.25s冰冻，敌人蓝色+停止移动 | 代码逻辑正确 ✅ |
| 暴击堆栈显示 | HUD右上角 CritLabel 显示"暴击:N"，0层灰色"暴击:0" | 代码逻辑正确 ✅ |
| 精英名字+🔫视觉 | 精英头顶显示金黄色名字，有枪时显示🔫标记 | 代码逻辑正确 ✅ |

---

### 系统完整性（六维度）

| 系统 | 状态 | 备注 |
|---|---|---|
| 搜打撤全链路 | ✅ | 轮次362修复后撤离波次顺序正确 |
| 命卡系统 | ✅ | crit_on_kill/冻结/DOT 链路审计通过 |
| 精英成长档案池 | ✅ | 命名系统+挂枪视觉链路完整 |
| Boss框架 | ✅ | 不受影响 |
| 武器装配树 | ✅ | crit_mult 正确传递到子弹伤害计算 |
| 元素子弹视觉 | ✅ | DOT 颜色反馈（fire橙红/poison绿/ice蓝）已实现 |

---

### 剩余人类试玩验证项

1. **冰霜子弹命中冻结效果** — 代码逻辑已验证，需人类试玩确认（0.5s冻结+蓝色视觉）
2. **火焰子弹命中后 DOT 视觉** — EnemyBase 橙红色渐变已实现
3. **剧毒子弹叠加 5 层视觉** — EnemyBase 绿色加深逻辑已实现
4. **精英名字+🔫挂枪+活子弹追踪+落地炮台+crit×2.5暴击** — 链路代码正确，实际表现需试玩
5. **FateCardEngine._apply_grant_random_card()** — 随机命卡实际效果
6. **开门命运选卡后通知显示** — show_fate_card_notification 已实现
7. **撤离成功面板楼层显示** — 轮次364已修复 ✅
8. **基地 VaultMenu 正确显示 vault_items** — 需人类试玩验证
9. **超频命卡（overheat_penalty）受击惩罚** — 已实现，需试玩确认数值
10. **撤离成功后台保险柜物品带入下局** — 需人类试玩验证
11. **精英怪掉落 rifle/machinegun/launcher/charge** — ItemRegistry 有配置，需实际掉落验证
12. **撤离守点敌潮强度** — 轮次362修复后波次顺序正确
13. **MobileInput 移动端触控** — 需真机测试

---

### 本轮决策

继续排 cron → 状态 `running`，无设计分叉，无外部依赖，无破坏性风险，用户未要求停止。

### 下轮最可能方向
1. **人类试玩验证最高且唯一优先级**
2. 若发现 Bug → 针对性修复
3. 若无 Bug → 第二关专属怪物掉落表深化或战斗视觉反馈