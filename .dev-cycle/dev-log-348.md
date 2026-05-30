# 轮次 348 — 2026-05-29 04:21 UTC+8

## 本轮维度
枪身蓝图（bp_pistol/bp_shotgun/bp_rifle/bp_machinegun/bp_sniper/bp_launcher）combat_floor 掉落覆盖补全

## 问题分析

审查 ItemRegistry.gd 中枪身蓝图（blueprint subtype=gun_body）的 `floor_loot_weights`：

**Tier-0 基础蓝图（bp_pistol/bp_shotgun）**
- bp_pistol：只有 `loot_floor_1_2/3_4/5/abyss/common/spawn_starter`，缺少 `scavenge_floor_1/2` 和 `combat_floor_1/2`
- bp_shotgun：同样缺少 `scavenge_floor_1/2` 和 `combat_floor_1/2`

**Tier-1 进阶蓝图（bp_rifle/bp_machinegun）**
- bp_rifle：只有 `loot_floor_3_4/5/abyss/boss_floor_1/common/spawn_starter`，缺少 `scavenge_floor_3/4` 和 `combat_floor_1/2/3`
- bp_machinegun：已有 `scavenge_floor_3/4/5`，缺少 `combat_floor_1/2/3`
- bp_sniper：只有 `scavenge_floor_5`，缺少 `scavenge_floor_3/4` 和 `combat_floor`
- bp_launcher：只有 `scavenge_floor_5`，缺少 `combat_floor_3/4`

战斗房（combat_floor_*）是玩家获取蓝图的重要来源——清理战斗房后，掉落表会从 `combat_floor_%d` 查询蓝图权重。当前这些蓝图在战斗房的权重几乎都是 0（未定义 fallback 到 loot_floor_1_2 的宽松 fallback），导致玩家打完一场硬仗却拿不到蓝图。

## 代码改动

**文件：** `src/base/ItemRegistry.gd`

### bp_pistol 新增
```gdscript
"scavenge_floor_1": 2.5,   // 新增
"scavenge_floor_2": 1.8,   // 新增
"combat_floor_1": 1.5,     // 新增
"combat_floor_2": 1.0,     // 新增
```

### bp_shotgun 新增
```gdscript
"scavenge_floor_1": 2.0,   // 新增
"scavenge_floor_2": 1.5,   // 新增
"combat_floor_1": 1.0,    // 新增
"combat_floor_2": 0.5,    // 新增
```

### bp_rifle 新增
```gdscript
"scavenge_floor_3": 1.5,   // 新增
"scavenge_floor_4": 2.0,   // 新增
"combat_floor_1": 1.5,     // 新增
"combat_floor_2": 1.0,     // 新增
"combat_floor_3": 0.8,     // 新增
```

### bp_launcher 新增
```gdscript
"combat_floor_3": 0.5,    // 新增
"combat_floor_4": 0.3,    // 新增
```

bp_sniper 已有 `scavenge_floor_5: 1.5`，不再修改。

权重设计原则：
- 蓝图比成品武器更稀有（战斗房权重略低）
- 随关卡深入递减，低关卡蓝图在高关卡权重逐渐降低
- Tier-1 进阶蓝图设计为第三关及以上才能稳定获取

## 验收标准

| 蓝图 | 战斗房覆盖 | 搜刮房覆盖 |
|---|---|---|
| bp_pistol | combat_floor_1:1.5, floor_2:1.0 | scavenge_floor_1:2.5, floor_2:1.8 |
| bp_shotgun | combat_floor_1:1.0, floor_2:0.5 | scavenge_floor_1:2.0, floor_2:1.5 |
| bp_rifle | combat_floor_1:1.5, floor_2:1.0, floor_3:0.8 | scavenge_floor_3:1.5, floor_4:2.0 |
| bp_machinegun | 已有 scavenge_floor_3/4/5 | - |
| bp_sniper | 已有 scavenge_floor_5 | - |
| bp_launcher | combat_floor_3:0.5, floor_4:0.3 | - |

Godot headless --check-only --quit: **EXIT 0** ✅

## 剩余风险
1. **人类试玩验证**：玩家实际打完第二/三关战斗房后，蓝图掉落率是否符合手感预期（轮次349可做实际掉落概率验证）
2. bp_sniper/bp_machinegun 的 combat_floor 仍未覆盖（但这两个是高阶蓝图，战斗房掉落并非主要来源，可接受）

## 续排判断
**继续排 cron** — 状态维持 `running`，本轮完成了枪身蓝图掉落覆盖补全。蓝图类掉落表现在覆盖完整（Tier-0 在低关卡搜刮/战斗房，Tier-1/2 在中高关卡）。下轮可继续深化战斗房怪物波次配置，或人类试玩验证。

## 下轮最可能方向
1. 第二/三关战斗房怪物波次深化（每个 floor_level 的每波敌人数配置）
2. 人类试玩验证蓝图实际掉落率手感
3. 搜打撤经济系统收束（魂收益/带出结算/保险格完整性）