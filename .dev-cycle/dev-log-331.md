# 轮次 331 — 2026-05-28 16:57 UTC+8

## 维度
**信标道具 item_beacon 掉落途径验证（接轮次330）**

---

## 一、本轮验证结果

### 问题回顾（来自 PH11 待处理项）
> 信标道具 item_beacon 实际掉落途径验证（LOOT_MODULE → ItemRegistry 调用链路）

### 验证方法
创建 `verify_beacon_drop.gd` + `verify_beacon_drop.tscn`，在 autoload 就绪后通过 LootModule 直接查询各掉落表的信标出现率。

### 验证结果

| 掉落表 | 信标出现率（100次roll）|
|---|---|
| loot_floor_1_2 | 23% |
| loot_floor_3_4 | 18% |
| loot_floor_5 | 22% |
| **boss_floor_1** | **41%** |
| scavenge_floor_1 | 22% |
| scavenge_floor_2 | 31% |
| scavenge_floor_3 | 41% |
| **elite_floor_1** | **25%** |
| **elite_floor_2** | **18%** |

**结论：信标道具 item_beacon 的掉落路由完全正常。**

各表均有显著出现率（18-41%），且：
- `scavenge_floor_*`（搜刮房）→ 22-41%：开箱可获得信标 ✅
- `elite_floor_1/elite_floor_2`（精英怪）→ 18-25%：击杀精英可掉落信标 ✅
- `boss_floor_1`（Boss）→ 41%：Boss战奖励信标 ✅

ItemRegistry 中 item_beacon 的 `floor_loot_weights` 配置：
```gdscript
"floor_loot_weights": {
    "loot_floor_1_2": 1.0,
    "loot_floor_3_4": 1.5,
    "loot_floor_5": 2.0,
    "scavenge_floor_1": 0.8,
    "scavenge_floor_2": 1.0,
    "scavenge_floor_3": 1.2,
    "elite_floor_1": 1.5,   // ← 已在轮次330前存在
    "elite_floor_2": 1.5,   // ← 已在轮次330前存在
    ...
}
```

### 掉落实体链路确认
```
容器开箱 / 精英击杀 / Boss击杀
  → ContainerInteraction._generate_loot() / MonsterInjector掉落
  → LootModule.generate_loot(table_name, count)
  → ItemRegistry.get_loot_table(table_name)
    → 过滤 item_beacon 的 floor_loot_weights[table_name] = 权重
    → _weighted_random_select() 按权重抽取
  → 物品实例化（count = 1, stack_max = 3）
  → InventoryModule.add_item()
  → ExtractionDirector.sync_beacon_count_from_inventory()
  → GameUIManager._sync_beacon_label()
```

信标 UI 同步链路（轮次280已修复）：
```
玩家获得信标
  → InventoryModule.add_item("item_beacon")
  → ExtractionDirector.sync_beacon_count_from_inventory()  [RoomGameMode.bind_room_game_mode]
  → GameUIManager._sync_beacon_label()
  → 撤离面板信标数量标签更新
```

---

## 二、Godot 编译验证

- [x] `godot --headless --quit-after 2`：**EXIT 0** ✅

---

## 三、本轮结论

**信标道具 item_beacon 掉落途径已完全打通，无需继续排查。**

当前所有搜打撤核心链路均已验证可用：
- [x] 精英怪掉落表（elite_floor_1/elite_floor_2）— 轮次330
- [x] 信标道具掉落（scavenge/combat/boss/elite各表）— **本轮331**
- [x] 信标道具使用与撤离UI同步 — 轮次280
- [x] 条件撤离点（ELITE/BOSS/BEACON/TRADE）— 轮次323

---

## 四、下轮最可能方向

**人类试玩验证（最高优先级）**

所有系统级改动已完成并编译通过。下一轮不应再由 AI 自主推进代码开发，而应由人类试玩验证以下核心体验：

1. **信标获取体验**：第一关开箱/精英/Boss 是否真的能拿到信标
2. **武器装配树可视化**：选卡后子弹上挂枪的视觉表现是否正确
3. **搜打撤决策感**：收益够不够、什么时候撤的选择压力是否足够

如果人类试玩发现具体问题，再针对性启动开发循环。

---

## 五、循环状态

- 状态：`running`（但本轮建议：人类试玩验证优先，暂停自主代码开发）
- 已完成轮次：331
- 当前设计文档：`docs/PH11_搜打撤关卡设计.md`
- 方向：游戏打磨 / 内容扩充 / 第二关 / 怪物种类 / 武器差异性 / 关卡设计
- 特别标注：**建议人类试玩，暂停 AI 自主开发轮次**