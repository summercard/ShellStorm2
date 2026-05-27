# 轮次295：MULTIPLY_FIRE_RATE 引擎键名不匹配 Bug 修复

## 本轮选维度：设计缺口修复（MULTIPLY_FIRE_RATE 引擎读取错误 effect key）

**原因：** 超频命卡描述说"射速提升 80%"，但引擎实际只提升 50%（默认值 1.5 而非预设的 1.8）。FateCardPresets 使用 `fire_rate_scale` 键，但 FateCardEngine._apply_multiply_fire_rate() 读取 `multiplier` 键，导致预设的 1.8 完全未使用。

---

## 一、问题分析

### Bug 定位
**文件：** `src/weapons/FateCardEngine.gd`，方法 `_apply_multiply_fire_rate()`

**现状：**
- FateCardPresets.overclock() 写入 `effect["fire_rate_scale"] = 1.8`
- _apply_multiply_fire_rate() 读取 `card.effect.get("multiplier", 1.5)` — `multiplier` 键不存在，走默认值 **1.5**
- 结果：超频命卡实际只提升 50% 而非描述的 80%

**链路：**
```
FateCardEngine._apply_multiply_fire_rate()
→ card.effect.get("multiplier", 1.5)  ← 读取了错误的键！
→ stats["fire_rate"] = 4.0 * 1.5 = 6.0  ← 实际效果
而不是
→ stats["fire_rate"] = 4.0 * 1.8 = 7.2  ← 预期效果
```

**影响范围：** 所有使用 MULTIPLY_FIRE_RATE 动作的命卡（超频）
**影响程度：** 数值偏低 20%（1.5x vs 1.8x）

---

## 二、代码改动

### 改动：FateCardEngine.gd — _apply_multiply_fire_rate() 修正键名

**文件：** `src/weapons/FateCardEngine.gd`，行 ~468

将：
```gdscript
var multiplier: float = card.effect.get("multiplier", 1.5)
var overheat_penalty: float = card.effect.get("overheat_penalty", 1.0)
var stats: Dictionary = target.get_base_stats()
stats["fire_rate_multiplier"] = multiplier
stats["fire_rate"] = stats.get("fire_rate", 4.0) * multiplier
stats["overheat_penalty"] = overheat_penalty
```

改为：
```gdscript
# 读取 fire_rate_scale（与 FateCardPresets 中 overclock/fuse_fire 等卡片的 effect 键一致）
var fire_rate_scale: float = card.effect.get("fire_rate_scale", 1.5)
var overheat_penalty: float = card.effect.get("overheat_penalty", 1.0)
var stats: Dictionary = target.get_base_stats()
stats["fire_rate"] = stats.get("fire_rate", 4.0) * fire_rate_scale
stats["overheat_penalty"] = overheat_penalty
```

**同时**修正 Message：
```gdscript
result.message = "Applied %.1fx fire rate to %s" % [fire_rate_scale, target.node_name]
result.effect_value = fire_rate_scale
```

**移除**：`stats["fire_rate_multiplier"] = multiplier`（该键从未被任何代码读取）

---

## 三、验收标准

- [x] FateCardEngine._apply_multiply_fire_rate() 读取 `fire_rate_scale` 而非 `multiplier`
- [x] 超频命卡应用后，枪械射速 = 原射速 × 1.8（而非 1.5）
- [x] `fire_rate_multiplier` 冗余键不再写入 base_stats
- [x] Godot headless --quit 验证编译通过（EXIT 0）
- [ ] **人类试玩验证**：超频命卡实际射速提升幅度是否符合描述

---

## 四、完整超频命卡链路（修复后）

```
玩家应用"超频"命卡（PH04）
→ FateCardEngine._apply_multiply_fire_rate()
→ card.effect.get("fire_rate_scale", 1.5) → 1.8 ✓（不再走默认值）
→ stats["fire_rate"] = 4.0 * 1.8 = 7.2
→ stats["overheat_penalty"] = 1.5
→ target.set_base_stats(stats) → base_stats["fire_rate"]=7.2, base_stats["overheat_penalty"]=1.5
→ tree.refresh_stats() → WeaponAssemblyTree._apply_stats() → _overheat_penalty = 1.5
→ 玩家受伤时 Player.take_damage()
→ weapon_tree.get_overheat_penalty() 返回 1.5
→ final_damage *= 1.5（受到 1.5 倍伤害）✓
```

---

## 五、剩余风险（不变）

**人类试玩验证项：**
1. 超频命卡实际射速提升 80% **← 本轮已修复键名**
2. 超频命卡实际受击惩罚 1.5x **← 轮次294已修复链路**
3. 冰霜子弹命中冻结效果（0.5s/0.25s for elite）
4. 火焰子弹命中后 DOT 视觉（橙红色敌人）
5. 剧毒子弹叠加5层视觉（绿色加深）
6. 子弹背枪实际射击（🔫挂枪视觉 + 子弹飞行中开火）
7. 活子弹追踪敌人（👁视觉）
8. 落地炮台实际生成（🏰）
9. crit_on_kill 暴击必暴击（2.5x）
10. 开门命运选卡后通知是否正确显示
11. MapFateTriggers 环境命运触发器实际触发与效果
12. 撤离守点敌潮强度缩放实际效果

---

## 六、续排判断

**继续排 cron** — 状态维持 `running`。overheat_penalty 链路已通，键名不匹配已修复，但人类试玩验证仍未完成。继续以孤立 cron 推进。

### 下轮最可能方向
1. 人类试玩验证（最高且唯一优先级）
2. 若发现更多 Bug → 针对性修复
3. 若未发现 Bug → 战斗视觉反馈或关卡内容扩展