# 远征03 程序化随机家具：整段关闭（2026-10-30 晚）

## 1. 业主的原话与现场

> 「我的远征03 的房间里面那个可以搜索的那个程序化的那个箱子，是不是现在还都有在，
> 每个房间里面是不是还都有在？我看好像走廊的去掉了，但是房间里面都还在。」
>
> 逐房实测回答后：
>
> 「把程序生成的这些箱子每个房间都去掉。」

实测（seed 100990，29 个房间）：走廊 0 件（被 §3.2 的 8m 短边下限滤掉），
15 间普通房每间 2~6 件可搜容器，合计 **103 件家具 / 52 件可搜索容器**。

## 2. 改法：一条数据段，不是关卡判断

`data/level_plans/expedition_03/level_plan.json` 顶层新增：

```json
"furnishing": {
  "schema": "shellstorm2.battle.room_furnishing",
  "schema_version": 1,
  "enabled": false
}
```

与 `interactive_clutter` / `monster_rules` 同级别：**能力段**，`DungeonRoom3D` 只认这段数据、
不认识关卡 ID（`check_level_decoupling.py` violations 0）。别的关卡不写 ⇒ 缺省 `true` ⇒
塔楼与远征01/02 行为逐字不变。

透传链（四跳，缺一跳设计源就白写）：

```text
level_plan.json  furnishing.enabled=false
  → FloorPlanGenerator  plan["furnishing"]                     （顶层透传）
  → TowerDescent3D._append_plan_room_record()                  （plan → record）
  → Dungeon3D / TowerDescent3D  configure()                    （record → 房间配置）
  → DungeonRoom3D._build_content()  prop_count = 0             （真正归零）
```

`DungeonRoom3D` 新增 `procedural_furniture_enabled`（缺省 `true`），与既有的
`search_facilities_enabled` 分工明确：

| 变量 | 语义 | 后果 |
|---|---|---|
| `search_facilities_enabled` | 家具照摆，但不可搜 | 房间里仍有一堆柜子箱子 |
| `procedural_furniture_enabled` | **整批不生成** | 房间里没有那些柜子箱子 |

业主这次要的是后者。

## 3. 两个坑

### 3.1 `+2` 抵掉了关闭

`prop_count` 的算式末尾有：

```gdscript
if room_type in ["STORAGE", "SCAVENGE", "BASEMENT"]:
    prop_count += 2
```

第一版把 `if not procedural_furniture_enabled: prop_count = 0` 写在这行**之前**，
结果 `reward_01`（SCAVENGE）与 `fireplace_room_inj2`（STORAGE）各剩 2 件 —— 探针一眼看到：

```text
PROBE_ROOM reward_01         furniture=2 searchable=1
PROBE_ROOM fireplace_room_inj2 furniture=2 searchable=0
PROBE_SEARCHABLE total_furniture=4 searchable=1   ← 应为 0 / 0
```

关闭判据必须在所有 `+=` 之后，代码里留了注释盯着。

### 3.2 易碎小物件数量会跟着变（不是 bug）

撒点洗牌的消耗与**候选点数**绑死：

```gdscript
for index in range(candidates.size() - 1, 0, -1):
    var swap := rng.randi_range(0, index)      # 次数 = 候选数 - 1
```

家具不在了 ⇒ `_interactive_clutter_blocked_centers()` 少一批点 ⇒ 候选变多 ⇒
洗牌多消耗随机数 ⇒ `wanted = randi_range(3, 6)` 抽到的值也跟着变。

实测：易碎件 **75 → 68 件**，位置也不同。`E3_CLUTTER_DRIFT = 0`，确定性没破。

## 4. 实测对照（seed 100990）

| 项 | 关闭前 | 关闭后 |
|---|---|---|
| 程序化家具 | 103 | **0** |
| 可搜索容器 | 52 | **0** |
| 易碎小物件 | 75（不含安全房固定 5 件） | 68 |
| 宝箱 | reward_01 1 只 | 1 只（不受影响） |
| 走廊（10 间 5×5 / 15×5） | 0 | 0 |

## 5. 回归

| 套件 | 结果 |
|---|---|
| `probe_expedition03_furnishing` | `FURNISH_PROBE OK`（三条断言全 PASS，props 全 0） |
| `probe_expedition03_clutter` | `E3_CLUTTER_OK`（placed=17 / total_items=68 / drift 0） |
| `probe_expedition03_playable` | `PLAYABLE_OK` |
| `probe_expedition03_save_roundtrip` | `STATE_PROBE OK`（A1~D2 全 PASS） |
| `tools/_egt_chest_probe` | `EGT_CHEST_PROBE_OK` |
| `scripts/check_level_decoupling.py` | `violations 0` |

顺手修了 `probe_expedition03_save_roundtrip.gd:135` 的既有报错 ——
`bool(ledger.get(chest_id, false))` 的账值是 **Dictionary**，Godot 4.6 起
`bool(Dictionary)` 无构造函数（`Nonexistent 'bool' constructor`），改为显式判"记录在且非空"。
这个错与本轮改动无关，之前一直在拦 B3 之后的断言。

## 6. 改动清单

| 文件 | 改动 |
|---|---|
| `data/level_plans/expedition_03/level_plan.json` | 新增顶层 `furnishing` 段，`enabled=false` |
| `src/map/FloorPlanGenerator.gd` | plan 顶层透传 `furnishing`（不进 canonical，不影响存档匹配） |
| `src/world3d/TowerDescent3D.gd` | `_append_plan_room_record()` 读段 → record；`configure()` 透传 |
| `src/world3d/Dungeon3D.gd` | `configure()` 透传（入口房 / 塔楼路径一致性） |
| `src/world3d/DungeonRoom3D.gd` | 新增 `procedural_furniture_enabled` + `prop_count` 归零判据 + 快照字段 |
| `tools/_exp03_clutter_room_probe.{gd,tscn}` | 新增：逐房清点家具 / 可搜 / 易碎件 |
| `tests/verification/probe_expedition03_save_roundtrip.gd` | 修 B3 的 `bool(Dictionary)` |
| `docs/v0.1/design/远征关卡03设计.md` | 新增 §7.5.1 |

## 7. 未做 / 需要业主定的

1. **补给缺口**：52 件可搜容器是资源来源之一（`loot_value = 4 + rank×2 + size bonus`）。
   关掉之后远征03 的可搜补给只剩怪物掉落 / 宝箱 / 通关奖励。要不要在
   `clear_rewards` 或掉落表里补回来，需要业主定口径 —— 本轮只执行"去掉"，没动经济。
2. **房间可能显得空**：程序化家具原本兼作掩体。若实际打起来觉得过于空旷，
   更合适的做法是走美术静态布局补固定陈设，而不是把随机家具开回来。
3. 家具数量 / 密度仍未数据化（`per_room_min/max` 之类），现在只有"全开 / 全关"两档。
