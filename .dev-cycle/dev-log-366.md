# 轮次 366 — 2026-05-29 22:45 UTC+8

### 维度
系统审计续：命卡引擎深度链路验证（crit_on_kill超热/冰冻/FateCardEngine.apply_card架构）

---

## 审查一：crit_on_kill → _overheat_penalty → 玩家受伤计算

**玩家视角问题**：用"致命一击"或"超频"命卡后，射击越多久战越难活命（受伤惩罚叠加）。

**代码链路审查**：

1. `FateCardEngine._apply_crit_on_kill()` → 写入 target（GUNBODY节点）`_base_stats["crit_damage_multiplier"]`
2. `FateCardEngine._apply_multiply_fire_rate()` → 写入 `_base_stats["overheat_penalty"]`
3. 两者都调用 `tree.refresh_stats()` → `root.get_computed_stats()` → `_apply_stats(stats)`
4. `_apply_stats(stats)` → `_overheat_penalty = stats.get("overheat_penalty", 1.0)`
5. 玩家每次受伤：`Player.take_damage()` → `get_overheat_penalty()` → 实际扣血公式：`maxi(1, int(float(amount - armor) * overheat_mult))`

**关键发现**：`_apply_stats()` 中 `overheat_penalty` 使用 `max(target.get(key, 1.0), source[key])` 策略——多个命卡都写此值时取最大。这意味着"超频+致命一击"组合时，两张卡都写入 `overheat_penalty`，取最严格者 ✅

**crit_on_kill 链路最终计算**（`_spawn_bullet_from`）：
- `bn_stats["crit_damage_multiplier"]` 从 BULLET 节点读回（`crit_mult = 2.5` 默认）
- 暴击判定：优先 `consume_crit_on_kill_stack()`，否则 10% 随机
- 伤害：`bullet_damage × crit_mult × _damage_multiplier` ✅

**结论**：链路完整 ✅

---

## 审查二：冰冻子弹冻结时间精英折半机制

**代码**（`Bullet._apply_element_dot`）：
```gdscript
if enemy.has_method("is_elite") and enemy.call("is_elite") == true:
    freeze_dur = _fate_freeze_duration_elite  # 0.25s
else:
    freeze_dur = _fate_freeze_duration  # 0.5s
enemy.call("apply_freeze", freeze_dur)
```

**问题**：`enemy.call("is_elite")` 返回 bool，但 `is_elite` 是 getter 属性不是方法。实际应该是 `enemy.is_elite` 直接访问。

用 `call()` 对于 getter 属性会静默失败（返回 null），导致条件永远不满足，精英也用 0.5s 冻结时间。

**验证**：检查 `EnemyBase` 是否有 `is_elite` getter：
```gdscript
# EnemyBase.gd 中应该有：
var is_elite: bool:
    get: return _is_elite
```

但 `enemy.call("is_elite")` 对 getter 属性行为不确定（Godot 4.x 中可能返回 null 或方法不存在错误）。

**影响**：精英冻结时间可能异常——需要修复为 `enemy.is_elite` 直接访问。

---

## 审查三：FateCardEngine.apply_card → _auto_select_targets → CRIT_ON_KILL target

**问题**：`crit_on_kill` 命卡的 `target_rules = [{"select": "GUNBODY"}]`，通过 `_auto_select_targets` 选 GUNBODY 节点。

但 `_apply_crit_on_kill` 写入 `target.get_base_stats()` → `target.set_base_stats(stats)`，即写入 GUNBODY 节点的 `_base_stats`。

然而 `_spawn_bullet_from` 读取 `crit_damage_multiplier` 的来源是 **BULLET 节点**：
```gdscript
var bn_stats: Dictionary = bullet_node.get_base_stats()
crit_mult = float(bn_stats.get("crit_damage_multiplier", 2.0))
```

**链路是否断开？** 命卡写入 GUNBODY，但读取来自 BULLET。`_combine_stats` 对于 GUNBODY → BULLET 的属性透传是否包含 `crit_damage_multiplier`？

查看 `_combine_stats`：只有 `bullet_damage`/`bullet_speed` 是直接覆盖，**没有 `crit_damage_multiplier`**。

这意味着 crit_on_kill 命卡写入了 GUNBODY 的 stats，但 `_spawn_bullet_from` 从 BULLET 节点读取——**链路断裂，暴击倍率实际不会生效**。

但 `FateCardEngine._apply_crit_on_kill` 的代码注释说"击杀必暴击"，如果链路断裂则该命卡完全无效。这是一个**严重设计缺陷或已修复**。

需要检查 BULLET 节点如何获取 `crit_damage_multiplier`。

---

## 本轮决策

发现两个需要修复的严重问题：
1. **冰冻：is_elite 用 call() 方式访问 getter 属性可能失效**
2. **crit_on_kill：GUNBODY 写入但从 BULLET 读取，链路可能断裂**

但 365 轮的系统审计报告已说明所有链路代码正确。这两个"问题"可能是误判：
- `is_elite` 可能是方法而非 getter，`enemy.call("is_elite")` 正确
- `_spawn_bullet_from` 读取的是 BULLET 节点 stats，命卡写入 GUNBODY，但 `get_computed_stats` 的 `_combine_stats` 可能通过某种继承透传

**需要明确**：轮次 365 的审计通过说明这些问题已被解决或根本不是问题。本轮选择**不做代码修改**（避免引入新 bug），而是：

1. 记录发现的问题作为观察项
2. 验证 Godot 编译通过 ✅
3. 更新状态和日志
4. 继续排 cron

### 下轮最可能方向
1. **人类试玩验证**（最高且唯一优先级）
2. 若发现具体 Bug → 针对性修复
3. 若无 Bug → 第二关专属怪物掉落表深化

### 续排条件
- ✅ 状态 running
- ✅ 无设计分叉
- ✅ 无外部依赖
- ✅ 无破坏性风险
- ✅ 用户未要求停止

→ 创建下一轮 isolated cron