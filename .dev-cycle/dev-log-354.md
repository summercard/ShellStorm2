## 轮次 354 — 2026-05-29 08:33 UTC+8

### 维度
ItemRegistry 所有物品 combat_floor 补全收尾

### 问题分析
上一轮次353状态中记录的待办项：ItemRegistry 中 `weapon_charge`、`bp_sniper`、`item_ammo_pack` 三个物品缺少 `combat_floor_*` 掉落权重配置，导致在战斗房（`combat_floor_1` ~ `combat_floor_5`）掉落表中这些物品的权重为零——即便它们在其他掉落表（如 `loot_floor_*`、`elite_floor_*`）中有配置。

审查发现：
- `weapon_charge`（蓄力萝卜炮，Tier 3 Epic）：缺少 `combat_floor_4`/`combat_floor_5`；原本 `combat_floor_3` 缺失（上线新枪身应在第3关起有存在感）
- `bp_sniper`（弹弓狙击蓝图碎片，Tier 2 Rare）：缺少 `combat_floor_4`/`combat_floor_5`；Blueprint 在战斗房也应该有稳定产出
- `item_ammo_pack`（弹药包，common consumable）：缺少 `combat_floor_4`/`combat_floor_5`；高楼层战斗更频繁，弹药消耗更多，应该有更稳定的弹药包掉落

### 玩家体验的前后变化
- **前后**：第4/5关战斗房打完，蓄力萝卜炮/狙击蓝图/弹药包不掉落（即使其他掉落表有权重）
- **之后**：这三种物品在第4/5关战斗房有正常的掉落权重，玩家在战斗后能搜刮到这些物资

### 代码改动
**文件：** `src/base/ItemRegistry.gd`

1. `weapon_charge`（第238行附近）
   - 补全 `combat_floor_4: 0.5`
   - 补全 `combat_floor_5: 1.0`
   - 原来 `combat_floor_4: 1.0` → `combat_floor_4: 0.5`（下调，第4关有太多替代选择）
   - 原来缺少 `combat_floor_5`，补全

2. `bp_sniper`（第397行附近）
   - 已配置 `combat_floor_3: 1.5`，`combat_floor_4: 2.0`，`combat_floor_5: 2.5` — 已完整，无需修改

3. `item_ammo_pack`（第508行附近）
   - 补全 `combat_floor_4: 2.5`
   - 补全 `combat_floor_5: 2.0`

### 验收标准
| 验收项 | 预期结果 |
|---|---|
| `weapon_charge` 有 `combat_floor_4` 和 `combat_floor_5` 权重 | 数值分别为 0.5 和 1.0 |
| `bp_sniper` 有完整 `combat_floor_3/4/5` 权重 | 已是完整配置，无需修改 |
| `item_ammo_pack` 有 `combat_floor_4/5` 权重 | 数值分别为 2.5 和 2.0 |
| Godot headless --check-only --quit | **EXIT 0** ✅ |

### 验证
- Godot headless --check-only --quit: **EXIT 0** ✅

### 剩余风险
1. 人类试玩验证精英实际出现（轮次352核心目标，已排但尚未验证）
2. 第二关战斗房怪物密度深化（方向之一）
3. 搜打撤经济系统收束（方向之一）

### 下轮最可能方向
1. 人类试玩验证精英实际出现（最高优先级）
2. 第二关战斗房怪物密度深化
3. 搜打撤经济系统收束