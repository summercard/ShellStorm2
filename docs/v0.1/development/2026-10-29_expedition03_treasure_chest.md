# 远征03 宝箱房：放宝箱 + 开箱给掉落与命运卡

**日期**：2026-10-29
**范围**：远征03 的 2 间 `REWARD` 房、`TreasureChest3D`、开箱结算
**起因**：业主「宝箱房也需要放宝箱，还有宝箱房的宝箱开启后除了会掉落外，会出现一张命运卡。」

## 1. 为什么这件事必须做

上一轮把普通怪装备掉落砍掉之后（见[怪物掉落对齐](2026-10-29_egt_monster_drops.md)），
远征03 的装备来源只剩怪物掉落 —— 而普通怪已经不掉了。当时在
[怪物设计 §T8.5](../design/怪物设计.md) 里明确记了这个断层：

> 远征03 的 `REWARD` 房在运行时没有任何处理，这一层**没有第二个装备来源**。

所以这次不是"加一个玩法"，是**补一条断掉的经济链**。

## 2. 五段链路

```
level_plan.json → treasure_chests              ① 配置
  → FloorPlanGenerator._chest_placements_for() ② 生成期算位置/品质/参数
  → room_from_source() 白名单                  ③ 字段透传（最容易漏）
  → DungeonRoom3D._build_treasure_chests()     ④ 进房实例化
  → Dungeon3D._on_chest_open_requested()       ⑤ 扣钥匙→形态→掉落→命运卡
```

### 2.1 ③ 字段白名单：这次真正卡住我的地方

`FloorPlanGenerator.room_from_source()` 是一份**出口白名单** —— 只透传它认识的字段，
其余全部丢弃，**没有任何报错**。

现象：生成期 `print` 明明有 `chest_placements`（2 间 reward 房各 1 条），
运行时房间却是 0 只箱子。排查顺序是：

1. 打印生成器 → 有；
2. 打印 `TowerDescent3D._append_plan_room_record()` → **`has_chest_placements=false`，27 个键**；
3. 回头找"谁把字段吃掉了" → `room_from_source()` 的白名单。

补一行 `"chest_placements": (src.get("chest_placements", []) as Array).duplicate(true)` 后立即通过。

同一个函数里 `spawn_placements` / `reward_plan` / `interactive_clutter` 的注释都写着
"不在这里登记就会被静默丢弃" —— 我读到了那句话，但直到自己踩上去才真正理解它的分量。
**这条已写进 §T9.1 的表格，位置就是"③ 白名单"。**

### 2.2 ④ 房间细节是"进房才建"的

第二版探针在进入房间**之前**数箱子实例，恒得 0。真实行为是：
flow 房间的细节（家具 / 摆件 / 宝箱）在 `_build_content()` 里建，
而那一步要等玩家进房才跑。开局只有入口房有内容。

⇒ 探针必须先 `_enter_room()` 再数实例。这类"顺序错了就测不到"的坑，
比代码错误更难发现 —— 因为它看起来像功能没做。

### 2.3 ⑤ 开箱顺序：扣钥匙 → 收口形态 → 掉落 → 命运卡

四条理由写在 `Dungeon3D._on_chest_open_requested()` 的注释里，摘要：

| 顺序 | 换一下会怎样 |
|---|---|
| 钥匙最前 | 没钥匙也"开了"一次，玩家白看到箱盖打开、地上什么都没有 |
| 形态第二 | 扣了钥匙却不标已开 ⇒ 能反复按 E 刷掉落 |
| 掉落第三 | 命运卡若改掉落品质（`fate_lucky_chest`），先发卡再抽会变成时序竞态 |
| 命运卡最后 | 它可能弹"选择来源"窗口，放在中间会让玩家在弹窗期间看不清掉了什么 |

`TreasureChest3D.perform_interaction()` **故意不置 `_opened`**，状态由上层
`commit_opened()` 收口。先置位再判定就是"没钥匙也把箱子标成已开"。

## 3. 加了什么

### 3.1 新实体 `src/world3d/TreasureChest3D.gd`

- 复用 `PlayerInteractionController3D` 的交互协议（6 个方法 + 加入 `PROVIDER_GROUP`），
  **不实现新的交互系统**；
- 视觉全程序化（箱体 + 盖 + 金属包边 + 锁扣 + 内部发光面），不依赖美术资产；
  品质决定描边色与发光强度 —— 玩家在门口就能读出"这箱值不值得花钥匙"；
- 开箱 = 盖子绕**后缘**上翻 104°（pivot 在后侧，与真实合页一致），0.42s；
- `priority = 60` > 家具的 40：箱子与家具挨着时优先开箱。

### 3.2 配置 `level_plan.json` → `treasure_chests`

| 键 | 值 |
|---|---|
| `chest_per_room` | 1 |
| `requires_key` | true |
| `quality_weights` | common 62 / uncommon 26 / rare 10 / epic 2 |
| `reward_pool_id` | `loot_floor_1_2` |
| `drop_count` | 2 |
| `fate_card_per_open` | 1 |

**品质用确定性轮转而不是抽签**：抽签在改配置后会让"同 seed 同房间"整体位移，
流送重建后箱子品质可能变，探针也没法复算。

**`drop_count = 2`** 是"除了掉落"的下限：花了 1 把钥匙只拿到 1 个电池会让人觉得亏。

### 3.3 摆件避让

`_interactive_clutter_blocked_centers()` 的障碍类型清单加了 `TreasureChest3D`，
并把宝箱的构建顺序放在**家具之后、摆件之前** —— 否则易碎罐子会塞进箱子里，
挡住交互圆点。顺序反了不会报错，只是偶尔"箱子点不到"，属于最难查的那类。

## 4. 踩坑记录

**① 探针不能用 `room_type == "REWARD"` 找宝箱房。**
flow 的 kind 不写进运行时 `room_type` —— `_flow_room_type()` 只区分
SAFE_ROOM / EXTRACTION_ROOM / BOSS_ROOM / COMMON_ROOM，REWARD 房在运行时是 `COMMON_ROOM`。
第一版按 REWARD 找，结论是"0 张宝箱房"，而实际 `reward_01` / `reward_02` 都在。
正确判据是 **`chest_placements` 非空**（生成器只给 REWARD 房写这个字段）。

**② Bash heredoc 写 Python 会吃掉反斜杠。**
用 `<<'PY'` 传含 `\n` / `\"` 的替换串时，反斜杠被 shell 处理掉，
Python 收到的是 `/n`，直接 SyntaxError。改用文件或 Edit 工具。

**③ `--check-only` 报 `Identifier not found: AudioManager` 不是我的 bug。**
它不加载 autoload。`RoomFurniture3D`（既有文件）同样报这个错 ——
判断依据是"既有文件也报"，不是猜。

**④ 出图连错四版，全是取景问题，不是模型问题。**
`outputs/verification/egt_treasure_chest.png` 一共改了 4 次才对：

| 版 | 现象 | 根因 |
|---|---|---|
| 1 | 只拍到 4 只箱子 | `ORTHO_SIZE=1.65` 时横向可见宽只有 6.8m，而排布占 9.75m |
| 2 | 整幅全黑 | 相机 (0,3,9) + 固定 `rotation.x=-26°`，视线在 z=0 处落到 y≈-1.4，箱子在 y≈0.5，纵向半高只有 1.5m ⇒ 全在画面外 |
| 3 | 箱子被 32 号字的 `[E]` 提示牌糊住 | 提示牌是**交互态**表现，不该出现在"长什么样"的图里 |
| 4 | 6 只齐了，但开箱看不出 | 正对视角看不到盖子上翻与箱口发光 ⇒ 必须加俯角 |

**教训**：正交相机的横向可见宽 = `ORTHO_SIZE × (VIEW_W/VIEW_H)`，不是 `ORTHO_SIZE`。
排布宽度要按这个式子反推，不能凭"装得下一个箱子"填。
而俯角必须用 `look_at_from_position()` 由「相机点 − 目标点」算出来，手填角度必偏。

**⑤ 正交俯视图看开箱，别去看盖子。**
盖子绕后缘翻 104° 后几乎与箱体背面重合，俯视时被箱体自己挡住。
可靠的判据是 `_glow`（内部发光面）—— 它只在 `commit_opened()` / `restore_opened_state()`
之后才 `visible`。图里 epic·已开 那道亮粉色横线就是它。

## 5. 验证

| 探针 | 结果 |
|---|---|
| `_egt_chest_probe` | `EGT_CHEST_PROBE_OK` |
| `_egt_chest_render` | 出图 `outputs/verification/egt_treasure_chest.png`（6 格 = 4 档品质 × 开/未开） |
| `_egt_drop_probe` | `DROP_OK` + `CLEAR_REWARDS_OK` + `LEGACY_FALLBACK_OK` |
| `_egt_clear_rewards_wiring_probe` | OK |
| 怪物 7 个探针（注册 / 数值 / 进场 / 子弹 / 可躲性 / 区分 / 编成 / 进房） | 全 OK |
| `verify_3d_enemy_behavior_flow` | OK |
| `verify_3d_combat_progression_flow` | OK |
| `verify_reward_ground_handoff` | OK |
| `verify_strong_variant_monsters` | OK |

`_egt_chest_probe` 实测输出：

```
宝箱房数量：2 → ["reward_01", "reward_02"]
  reward_01 chest_placements=1 实例化=1
  reward_02 chest_placements=1 实例化=1
目标箱：chest_00 quality=common requires_key=true drop_count=2 fate=1
  无钥匙分支：箱子保持未开，无掉落 ✓
  开箱结果：掉落 +2 件，命运卡 +1 张，status=宝箱开启 · 2 件物资 · 命运卡「圣杯·王牌」
  重复开箱：无新增掉落、无新增命运卡 ✓
```

**一条存量红项（与本次无关）**：`verify_level_plan_design_source` 报
`expedition_01 room_overlap:room_10:boss` —— 改之前就红，且不涉及远征03。

## 6. 没做到的

| 项 | 说明 |
|---|---|
| **宝箱品质池没拆** | 原作五档品质各有独立池；我们现在四档只做 `quality_tier()` 加成，共用 `loot_floor_1_2` |
| **拟态没接** | 我们已有 `egt_mimic`（伪装成箱的怪），但它不在宝箱房 —— 开箱变拟态这条没打通 |
| **钥匙供给偏紧** | 可自由支配的钥匙约 1~1.5 把，宝箱 2 间。EGT 里也常年开不满，所以保留；但**再加箱子前必须先扩钥匙** |
| 炸箱 / 空箱 | 无 |

排序：**拟态 > 品质池 > 炸箱**。拟态排第一是因为它已经有一半了（怪做完了，只差"开箱触发"这一跳），
而它对手感的影响最大 —— 从此开箱有风险，而不是纯收益。
