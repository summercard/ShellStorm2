# 远征03 通道房宝箱：清房掉落把无怪房算成内容房

时间：15:36。业主报障 → 定位 → 修复 → 验收。

## 结论

通道房里的宝箱**不是**宝箱房占位、也**不是**作者美术标记（11-08 撤 `GalleryCache` 是另一处）。
是 `clear_drops.content_room.chest_chance = 1.0` 把 `authored_layout_peaceful` 的无怪房
判成了内容房：无怪房进房即 `_mark_room_cleared(room, false)`，`was_cleared=false` 分支
deferred 一次 `_ensure_room_clear_drop()`，而后者只排除 `NON_CONTENT_ROOM_TYPES`
（`START/EXTRACTION/ELEVATOR/FACILITY/STAIR_LOBBY/SAFE_ROOM`）—— flow 关卡的走廊
运行时 `room_type` 是**空串**、商店 `MERCHANT`、前厅 `UPGRADE`、宝箱房 `STORAGE`，全都不在表里。

同种子实测 9 间被塞箱：4 条走廊 + `conn_01` + `shop` + `boss_foyer` + `secret_room_inj1`
+ `fireplace_room_inj2`。`chest_chance=1.0` ⇒ 每间必中，落点是 `_clear_drop_offset()`
的"玩家身前"（与截图里箱子就在脚下一致）。

## 改动

- `src/world3d/Dungeon3D.gd` `_ensure_room_clear_drop()`：`room.authored_layout_peaceful` ⇒ 早退。
  判据用和平区标志而不是房型名 —— 走廊空 room_type 这种形态按房型排除必漏。
- 新增 `tests/verification/verify_expedition03_clear_drop_rooms.{gd,tscn}`，注册进 `core`。
- 设计《远征关卡03设计》掉落行改 2026-11-09 口径；开发记录 + CHANGELOG + README 索引三处同步。

## 验收

| 项 | 结果 |
|---|---|
| 新专项 | 31 检查 / 0 失败，退出 0 |
| 反向对照（`if false and …`） | 18 条精准变红（9 间 × 2 条：掉箱 + 场上仍有箱），退出 1 |
| `verify_expedition03_room_interactions` | 1164 / 0，退出 0 |
| `verify_flow_floor_generation` | 333 OK，退出 0 |
| `check_verification_registry` / `check_level_decoupling` / `check_documentation_contracts` | 0 / 0 / 0（文档门禁只剩既有断链与 openpyxl 缺失） |

## 未执行 / 已知红

- 整关实机战斗回归未做（只动清房入口早退）。
- `verify_expedition03_workshop_layouts` 未跑到底：套件 preflight
  `sync_runtime_design_data --check` 报 `projection manifest drift`
  （`RUNTIME_DESIGN_DATA_PROJECTION_FAILED`，退出 2）。该漂移在本轮之前就有，与本次无关。
- 「战斗房清房必掉箱」的 2026-11-07 配比未评估，本页只修无怪房边界。

## 业主追问（15:47）：用和平区标志会不会让我经过时不能开枪？

不会。`src/player3d/` 对 `authored_layout_peaceful` 与 `room.cleared` **零引用**；开火只受
`input_locked`（仅叙事演出 `NarrativeAdapter3D` 与基地开局 `BaseWorld3D` 置真）、`current_hp > 0`、
状态机 `idle/moving` 管。标志的五个消费点全是「本房没有敌群」的派生后果：
不刷怪 / 不落门封锁 / 门按普通门办 / 滑升门扇 / 不清房结算。
「通道里没仗打」是 EGT `enemyless` 口径，与枪无关；要给通道加战斗得动 `FLOW_PEACEFUL_KINDS`。

**设计文档已补全（15:51）**：《远征关卡03设计》§2.1 加五个消费点表 + 边界段 + 「判据必须用标志
不能用房型名」；《关卡接入规范》§3.1.2 加清房边界行；《怪物设计》§T8.6 接线表加一行。

## 踩坑

`_is_content_room()` 用 `room_type` 判内容房，而 flow 关卡的走廊 `room_type` 是空串 ⇒
**任何按房型排除的名单都会漏走廊**。写排除逻辑前先确认"这个关卡里该房型到底叫什么"。
