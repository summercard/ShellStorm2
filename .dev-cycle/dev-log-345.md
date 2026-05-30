# 轮次 345 — 2026-05-29 04:07 UTC+8

## 本轮维度
配件（Attachment）模块掉落覆盖补全 — 补全 `scavenge_floor_3/4` 和 `combat_floor_1/2` 权重

## 问题分析

审查 ItemRegistry.gd 中 `_register_attachment_tier0()` 的两个基础配件：

**attach_triple_muzzle（三叉枪口）** 和 **attach_rubber_stock（橡皮枪托）** 的 `floor_loot_weights` 只覆盖到 `scavenge_floor_2`，缺少 `scavenge_floor_3/4` 和 `combat_floor_1/2`，导致：
- 玩家在第三/四关搜刮房无法获取这些基础配件
- 战斗房（combat）掉落表完全不覆盖这两种配件
- 作为基础（tier0）配件，应该在各关卡都有获取机会，权重随层数递减

## 代码改动

**文件：** `src/base/ItemRegistry.gd`

### attach_triple_muzzle 补全
```gdscript
"floor_loot_weights": {
    // ... 原有的 scavenge_floor_1/2 保留
    "scavenge_floor_3": 1.5,   // 新增
    "scavenge_floor_4": 1.0,   // 新增
    "combat_floor_1": 2.0,     // 新增
    "combat_floor_2": 1.5,     // 新增
    // ... 原有的 loot_floor_*/boss_*/elite/spawn_starter 保留
},
```

### attach_rubber_stock 补全
```gdscript
"floor_loot_weights": {
    // ... 原有的 scavenge_floor_1/2 保留
    "scavenge_floor_3": 2.0,   // 新增
    "scavenge_floor_4": 1.5,   // 新增
    "combat_floor_1": 2.5,     // 新增
    "combat_floor_2": 2.0,     // 新增
    // ... 原有的 loot_floor_*/boss_*/elite/spawn_starter 保留
},
```

权重设计原则：
- 基础配件随关卡推进递减（floor_3 > floor_4），避免低级配件在高关卡过度泛滥
- 战斗房权重略低于同等搜刮房（战斗房还有武器和子弹掉落，配件不是主要掉落物）

## 验收标准
| 验收项 | 预期结果 |
|---|---|
| attach_triple_muzzle | 拥有 `scavenge_floor_3:1.5`、`scavenge_floor_4:1.0`、`combat_floor_1:2.0`、`combat_floor_2:1.5` |
| attach_rubber_stock | 拥有 `scavenge_floor_3:2.0`、`scavenge_floor_4:1.5`、`combat_floor_1:2.5`、`combat_floor_2:2.0` |
| Godot headless --check-only --quit | EXIT 0 ✅ |

## 验证
- Godot headless --check-only --quit: **EXIT 0** ✅

## 剩余风险
1. **人类试玩验证**：实际进入第二/三关后，配件在搜刮房和战斗房的掉落率是否符合手感预期
2. attach_fan（风扇）和 attach_copy_sticker（复制贴纸）作为 epic 稀有度配件，当前只覆盖 `scavenge_floor_4+`，是否需要补充下层覆盖（待下轮审查）
3. 各掉落表在房间生成时实际调用的权重 key 是否与 ItemRegistry 字段完全对应（需要与 LootModule 交叉验证）

## 续排判断
**继续排 cron** — 状态维持 `running`，本轮完成了基础配件掉落覆盖补全。下轮可继续深化子弹模块（bullet tier1+）掉落覆盖，或第二关战斗房怪物密度/Boss战内容。

## 下轮最可能方向
1. 子弹模块 tier1+（mod_bullet_piercing/explosive/homing/blackhole/balloon）的 `scavenge_floor_3/4` 和 `combat_floor_1~3` 权重补全
2. attach_fan / attach_copy_sticker 等高级配件的低关卡覆盖审查
3. 第二关战斗房怪物波次配置深化
4. 第二关Boss战机制验证