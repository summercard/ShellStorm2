# 2026-11-10 远征01 保底枪恒不命中：候选房 ID 与运行时 room_id 不是同一套

> 业主报障：「远征01 的 room01 和 room02 其中一个箱子应该掉落保底枪械。目前我的情况是
> 两个都有掉落箱子，箱子都能打开，里头没有那把枪调出来。」

## 1. 结论

**配置里的候选房写的是设计源初值 `f00_room_01` / `f00_room_02`，而运行时 `room.room_id`
是 `room_01` / `room_02`。两个字符串永不相等，`guaranteed_items_for_room()` 恒返回空
⇒ 两只清房箱都不带保底条目。**

不是落地失败、不是拟态、不是旧存档、不是落点容量。箱子、开箱、普通奖励全部正常，
**只是保底这一段从来没被写进任何一只箱子**。

## 2. 根因链

```
level_plan.clear_drops.room_guarantees[0].candidate_rooms
  = ["f00_room_01", "f00_room_02"]            ← 设计源 floor_00.json 的 room_id
        ↓
FloorPlanGenerator.room_from_source() 第 237 行
  var runtime_id := str(src.get("legacy_room_id", ""))
  if runtime_id.is_empty(): runtime_id = str(src.get("room_id", ""))
        ↓
floor_00.json 的 legacy_room_id = "room_01" / "room_02"   ← 为兼容老存档房间进度索引
        ↓
运行时 room.room_id = "room_01" / "room_02"
        ↓
ClearDropService.guaranteed_items_for_room() 第 188 行
  if picked_room != room_id: continue        ← "f00_room_01" != "room_01"，恒 continue
        ↓
_build_chest() 不写 guaranteed_items ⇒ ChestRewardService 无保底可解析
```

`legacy_room_id` 的优先级是**刻意**的（既有存档的 `room_progress` 按它索引），
所以「设计源 room_id」与「运行时 room_id」本来就是两套值，配置必须写后者。

## 3. 证据（实测，非推断）

一次性探针 `generate_from_level_plan("expedition_01", 0, 2026, 180)` 后直接问服务：

```
PLAN valid=true rooms=13 mode=constrained
ROOM key=room_01  runtime_id=room_01  type=COMBAT
ROOM key=room_02  runtime_id=room_02  type=SCAVENGE
CONFIG ok=true errors=[]
RUNTIME_HITS=0                       ← 13 个真实 id 一个都不命中
HIT config_id=f00_room_01 [weapon_rifle ×1 grade=blue, item_ammo_pack ×100]
HIT config_id=f00_room_02 []
```

修复后同一探针：

```
HIT runtime_id=room_01  [weapon_rifle ×1 grade=blue, item_ammo_pack ×100]
RUNTIME_HITS=1
```

## 4. 为什么旧门禁是假绿（本轮一起补掉）

`verify_expedition01_room_guarantee.gd` 原来把候选房硬编码成
`const CANDIDATE_ROOMS = ["f00_room_01","f00_room_02"]`，然后**拿配置里的字串去问服务**
——自己跟自己对答案。它从来没跑过 `generate_from_level_plan()`，也就永远看不到
「运行时 id 是 `room_01`」这个事实。B 组「恰好命中一间」、C/D 组内容与解析在全错的前提下
照样全绿，`exit 0`。

## 5. 修改

| 文件 | 改动 |
|---|---|
| `art_source/design/whitebox/tower_zones/expedition_01/v001/data/level_plan.json` | `candidate_rooms` → `["room_01","room_02"]`；note 补一条 ID 口径警告 |
| `data/level_plans/expedition_01/level_plan.json` | 由 `sync_runtime_design_data.py` 重新投影（**不手改**，否则下次同步静默回退） |
| `tests/verification/verify_expedition01_room_guarantee.gd` | 新增 A2 组：候选房 ∈ `generate_from_level_plan()` 产出的运行时 id 集合；B/C/D 三组改用运行时 id；删掉硬编码 `CANDIDATE_ROOMS` 常量 |

A2 组是这次事故的**唯一有效防线**：只要有人再把配置写成 `f00_room_0N`，
它会红并直接打印「配置写成了设计源初值而不是 legacy_room_id」。

## 6. 验收

| 用例 | 结果 |
|---|---|
| `verify_expedition01_room_guarantee`（改后） | `EXPEDITION01_ROOM_GUARANTEE_OK: 候选房 ["room_01", "room_02"] 与运行时 id 对齐；…`，exit 0 |
| 反向注入（把 `data/` 投影临时改回 `f00_room_01/02`） | 两条 `ERROR: 候选房「f00_room_01」不在运行时房间 id 集合里 ["start","room_01",…]`，exit 1 —— 门禁确实会红，不是假绿 |
| `sync_runtime_design_data.py --check` | `{"files": 52, "issues": []}` |
| `check_level_decoupling.py` | violations 0 |
| `check_documentation_contracts.py` | 仍为既有 14 条历史断链（CHANGELOG/旧设计页），零新增 |

**未执行**：真实远征01 跑图开箱（本轮只到纯服务层 + 楼层计划生成）；真渲染；手感。

## 7. 残留风险

- **旧局不会自愈**：11-09 之后、本次修复之前开的局，房间账里 `treasure_chests.drop_<room_id>`
  已冻结那份**不带 `guaranteed_items`** 的 config，`_rebuild_runtime_chests()` 会照旧档重建。
  要拿到保底必须**新开一局**。
- 同批检查了 `expedition_02` / `expedition_03` 的 `clear_drops`：两关都没有
  `room_guarantees` 段，不受此 bug 影响。
- 落点容量那条隐患仍在（`Dungeon3D._build_chest_spawn_positions()` 某件找不到合法落点即
  `break`，而保底条目排在 grants 末尾，尾部会先被砍）。本项目前没有实测到它触发，
  仅记录，未改。
