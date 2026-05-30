# 轮次 344 — 2026-05-28 22:42 UTC+8

## 本轮维度
第二关武器掉落覆盖补全（weapon_machinegun/sniper/launcher/charge 补全 scavenge_floor_1~4 权重）

## 问题分析

审查 ItemRegistry.gd 枪身掉落权重时发现：

1. `weapon_machinegun`（蜂窝机枪）在 `scavenge_floor_1~3`、`combat_floor_1` 上完全缺失，导致玩家在第一关和第二关搜刮/战斗时无法从正常途径获得机枪，机枪掉落严重滞后于玩家进度。

2. `weapon_sniper`（弹弓狙击）缺少 `scavenge_floor_3~4`、`combat_floor_2~3`，狙击枪获取同样滞后。

3. `weapon_launcher`（反胃榴弹筒）缺少 `scavenge_floor_3~4`、`combat_floor_3`，榴弹筒更是几乎只能通过 Boss/精英掉落。

4. `weapon_charge`（蓄力萝卜炮）缺少 `scavenge_floor_4`，作为顶级武器也应该有少量第四关之前获取机会。

## 代码改动

**文件：** `src/base/ItemRegistry.gd`

### weapon_machinegun 补全
```gdscript
"floor_loot_weights": {
    "scavenge_floor_1": 0.5,   // 新增
    "scavenge_floor_2": 1.0,   // 新增
    "scavenge_floor_3": 1.2,   // 新增
    "combat_floor_1": 0.3,     // 新增
    // ... 原有的 loot_floor_*/boss_*/scavenge_floor_4~5/combat/elite 保留
},
```

### weapon_sniper 补全
```gdscript
"floor_loot_weights": {
    "scavenge_floor_3": 0.5,   // 新增（第三关开始有少量狙击枪）
    "scavenge_floor_4": 1.0,  // 新增
    "combat_floor_2": 0.3,     // 新增
    "combat_floor_3": 0.8,    // 新增
    // ... 保留原有的 loot_floor_3_4~5/abyss/boss/scavenge_floor_5/elite
},
```

### weapon_launcher 补全
```gdscript
"floor_loot_weights": {
    "scavenge_floor_3": 0.3,   // 新增（第三关开始少量榴弹筒）
    "scavenge_floor_4": 0.8,   // 新增
    "combat_floor_3": 0.5,     // 新增
    // ... 保留原有的 loot_floor_5~abyss/boss_floor_1~2/scavenge_floor_5/elite
},
```

### weapon_charge 补全
```gdscript
"floor_loot_weights": {
    "scavenge_floor_4": 0.4,   // 新增（第四关开始有蓄力炮获取机会）
    // ... 保留原有的 loot_floor_5/abyss/boss_floor_2/scavenge_floor_5/elite_floor_2
},
```

## 验收标准
| 验收项 | 预期结果 |
|---|---|
| weapon_machinegun | 拥有 `scavenge_floor_1/2/3` 和 `combat_floor_1` 权重 |
| weapon_sniper | 拥有 `scavenge_floor_3/4` 和 `combat_floor_2/3` 权重 |
| weapon_launcher | 拥有 `scavenge_floor_3/4` 和 `combat_floor_3` 权重 |
| weapon_charge | 拥有 `scavenge_floor_4` 权重 |
| Godot headless --check-only --quit | EXIT 0 ✅ |

## 验证
- Godot headless --check-only --quit: **EXIT 0** ✅

## 剩余风险
1. **人类试玩验证**：进入第二关（floor=2）实际验证机枪/步枪/霰弹枪在搜刮房和战斗房的实际掉落率是否合理
2. 各枪械在不同掉落表中的实际权重值是否需要根据试玩反馈调整（如机枪在 floor_2 的 1.0 权重是否足够或过多）
3. 蓝图掉落的 blueprint_loot_tier 与掉落表层级的匹配关系需要同步审查（部分蓝图缺 tier 时会导致低层无法掉落）

## 续排判断
**继续排 cron** — 状态维持 `running`，本轮完善了第二关枪械掉落覆盖。下轮可继续深化：第二关怪物密度/Boss战内容，或子弹/配件模块的掉落覆盖补全。

## 下轮最可能方向
1. 子弹模块（bullet）掉落覆盖审查 — 确保第二关及以后有足够子弹类型选择
2. 第二关战斗房怪物密度深化（波次配置、Boss战机制）
3. 配件（attachment）模块掉落覆盖审查
4. 命运卡片在第二关的刷新频率和种类覆盖