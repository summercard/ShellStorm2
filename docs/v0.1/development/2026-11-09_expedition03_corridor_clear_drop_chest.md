# 远征03 通道房清房宝箱修复

日期：2026-11-09。FeatureID：`WORLD-PLAN` / `WORLD-LOOT`。按业主要求执行：**通道房不应该出现宝箱**。

## 问题与根因

业主 2026-11-09 截图：远征03 走进通道房（`connector_10x30`），房间已肃清，地上摆着一只宝箱。

根因**不是**宝箱房占位、也不是作者美术标记（11-08 撤 `GalleryCache` 那条是另一处独立问题），
而是**清房掉落把无怪房算成了内容房**：

1. `data/level_plans/expedition_03/level_plan.json` 的 `clear_drops.content_room.chest_chance = 1.0`
   （2026-11-07 与远征01 共用同一能力段）。
2. 无怪房（`authored_layout_peaceful`：走廊 / 商店 / Boss 前厅 / 宝箱房 / 两间隐藏注入房）
   进房走 `Dungeon3D._spawn_room_enemies()` 的和平区分支，直接 `_mark_room_cleared(room, false)`。
3. `_mark_room_cleared()` 里 `was_cleared` 此时为假 ⇒ `call_deferred("_ensure_room_clear_drop", room)`。
4. `_ensure_room_clear_drop()` 只排除 `BOSS` 与 `NON_CONTENT_ROOM_TYPES`
   （`START / EXTRACTION / ELEVATOR / FACILITY / STAIR_LOBBY / SAFE_ROOM`）。而 flow 关卡里：
   - 走廊运行时 `room_type` 是**空串**（`content_type = ""` 经 `room_from_source` 的 `type` 透传），
   - 商店是 `MERCHANT`，Boss 前厅是 `UPGRADE`，宝箱房是 `STORAGE`，

   四个都不在排除表里 ⇒ 判成内容房 ⇒ 掷骰（`chest_chance = 1.0` 必中）⇒ 每间通道房固定白送
   一只 `drop_<room_id>` 箱子。箱子由 `_apply_clear_drop()` 用 `_clear_drop_offset()` 摆在
   **玩家身前**，与业主截图里「箱子就在脚下」的落点一致。

影响面（负测实测，同种子 `77003244`，共 9 间）：4 条走廊（`cr00_entry_n01` / `cr01_n03_reward_01` /
`cr02_hub_01_shop` / `cr03_boss_exit`）、1 间独立连接房（`conn_01`）、商店（`shop`）、
Boss 前厅（`boss_foyer`）、以及两间隐藏注入房（`secret_room_inj1` / `fireplace_room_inj2`）——
每间一只，全部是白送。

## 改动

- `src/world3d/Dungeon3D.gd` `_ensure_room_clear_drop()` 增加一条前置判据：
  `room.authored_layout_peaceful` ⇒ 直接返回，不掷骰、不建箱、不记 `_clear_drop_settled`。
  **判据用 `authored_layout_peaceful` 而不是房型名**：它是「本房没有敌群」的唯一事实所有者
  （与 `_room_produces_room_key()` 同判据），走廊空 `room_type` 这种形态按房型排除必然漏。
- 新增独立验收入口 `tests/verification/verify_expedition03_clear_drop_rooms.{gd,tscn}`，
  注册进 `run_verification_suite.sh` 的 `core`。两段断言：
  - A 无怪房：逼出细节树后跑一遍清房入口，`find_chest_by_id("drop_<room_id>")` 必须为空，
    且 `get_treasure_chests()` 必须为空（两处都扫，防止箱子挂在 detail 根或房间根时漏检）；
  - B 战斗房：清房仍必须掉箱，期望值与 `ClearDropService.roll_room_drop()` 逐房比对
    （防止用「谁都不掉箱」换绿）。
- 设计文档《远征关卡03设计》掉落行更新为 2026-11-09 口径，写明无怪房不参与清房掉落及其判据。
- 生成器、`clear_drops` 数据、宝箱屋配置、`TreasureChest3D`、开箱协议、存档账均未改动；
  两间 `REWARD` 宝箱房与 Boss 保底箱照旧。

## 验证

| 项目 | 结果 |
| --- | --- |
| 新专项 `verify_expedition03_clear_drop_rooms`（headless） | `EXP03_CLEAR_DROP checks=31 failures=0`，退出 0 |
| 反向对照：把新判据改成 `if false and …` 重跑 | `checks=31 failures=18`，退出 1；18 条精确落在 9 间无怪房（每间 2 条：掉箱 + 场上仍有箱） |
| `verify_expedition03_room_interactions` | `EXP03_ROOM_INTERACTIONS OK checks=1164 failures=0`，退出 0 |
| `verify_flow_floor_generation` | `FLOW_FLOOR_OK checks=333`，退出 0 |
| `verify_expedition_level01_flow`（同一能力段） | 清房段通过（`CLEAR_DROP_SAMPLE rooms=3 chests=3`）；整份用例退出 1，14 条红项与**临时关掉本判据后逐字相同**（墙碰撞 8 / 元数据 2 / 掉落表行数 13≠11 / 立体入口 / display_name），全部为既有红项，与本次无关 |

## 设计文档同步（2026-11-09 15:50 业主追问后补全）

业主追问：「用和平区标志会不会导致我经过的时候不能战斗开枪？」为此把这条标志的**完整**后果写进文档，
而不是只在代码注释里留一条判据。

| 文档 | 补了什么 |
| --- | --- |
| [`远征关卡03设计.md` §2.1](../design/远征关卡03设计.md) 无怪房段 | 五个消费点列表（不刷怪 / 不落门 / 普通门 / 滑升门扇 / **不清房结算**）+ 边界「只描述本房没有敌群，不描述玩家不能战斗」+ 为什么判据必须用标志不能用房型名 |
| [`关卡接入规范.md` §3.1.2](../关卡接入规范.md) | 清房掉落的房型边界行：Boss / 非内容房 / 无怪房一律早退，判据 `authored_layout_peaceful` |
| [`怪物设计.md` §T8.6](../design/怪物设计.md) | 接线表新增「清房结算的房型边界」一行，守门人写 `verify_expedition03_clear_drop_rooms` |

**边界结论（写进文档的那句）**：`src/player3d/` 对 `authored_layout_peaceful` 与 `room.cleared`
**零引用**；开火只受 `input_locked`（仅叙事演出与基地开局置真）、`current_hp > 0`、状态机 `idle/moving` 管。
⇒ 通道里照样能开枪、换弹、打车上的油桶。「经过通道没仗打」是 EGT 的 `enemyless` 口径，
不是把玩家手里的枪锁了。

## 未执行项

- 未做整关实机战斗回归（本改动只动清房入口的早退判据，战斗/开箱/存档链未变）。
- `verify_expedition_level01_flow` 的 14 条既有红项未修（墙碰撞体 8、远景元数据 2、掉落表期望 13 行而实际 11 行、
  「缺少两个立体入口」、display_name 为 `CloseAI数据库`）。判据只做「改前改后同一组红」的对照，未扩到别的问题。
- `verify_expedition03_workshop_layouts` **未执行到底**：套件 preflight 在
  `sync_runtime_design_data.py --check` 处报 `{"files": 52, "issues": ["projection manifest drift"]}` ⇒
  `RUNTIME_DESIGN_DATA_PROJECTION_FAILED`（退出 2）。该漂移在本轮改动之前就存在，与清房掉落无关，
  属工作区既有红项，未归因于本次交付。
- 未评估「战斗房清房必掉箱」这一 2026-11-07 口径对远征03 经济的影响（本关另有 2 只高级箱 + Boss 保底箱）；
  本页只修无怪房边界，不动配比。
- 11-08《远征03 大回廊撤除作者宝箱》记录的是**另一条**来源（作者 `Marker3D`），两条互不替代；
  本次修的是「即使没有任何作者标记，通道房也会被清房掉落塞箱」。
