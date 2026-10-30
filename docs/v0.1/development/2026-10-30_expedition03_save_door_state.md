# 远征03 安全屋出口门「下线再上线就没了」+ 房间级状态存档补全（2026-10-30）

## 1. 业主报单

> 「远征03 的安全屋，下线再上线这个出口的门就不见了。看一下远征03 的是不是大部分
> 存档相关的都缺失了。」

截图：入口安全屋东墙，红框里只剩门洞 + 红色 EXIT 牌，双扇门板不在。

## 2. 先定性：门「不见了」= 门被开到位

`RoomDoor3D` 的远征03 门是 `slide` 双扇对开。开到位时两扇滑进 0.28m 厚的墙体内部
（`_set_open_slide` 目标位 `panel_x=±1.71`，门板整块落在墙里），深度测试把门板挡在
墙后 —— 观感就是「门消失」。关着时 `panel_x=±0.55`（安全屋 15m 房的门洞净宽）。

所以这不是「门节点丢了」，是**这扇门被设成了 open**。

## 3. 实测取证

新增 `tests/verification/probe_expedition03_save_doors.{gd,tscn}`：真实加载
`ExpeditionLevel03_3D.tscn`，逐帧盯门态，再模拟一次存档恢复与装配收尾。

修复前的关键输出：

```text
SAVE_DOOR_PROBE door_opened_at_frame=1 start_cleared=true spawned=true
SAVE_DOOR_PROBE A_after_bootstrap room=start dir=east target=      open=true  panel_x=-1.71
SAVE_DOOR_PROBE neighbors[start]=["cr00_entry_n01"]
SAVE_DOOR_PROBE saved_edge_states_count=27
                 keys=[..., "cr00_entry_n01|room_01", "cr00_entry_n01|start", ...]
                 ← 27 条边里**没有** "start|room_01"
```

三条硬事实：

| 事实 | 证据 |
|---|---|
| 安全屋的门在**装配第 1 帧**就被打开 | `door_opened_at_frame=1`，此时 `start.cleared=true` |
| 门扇 `target` 与拓扑边**不是同一套键** | 门写 `start→room_01`；边是 `cr00_entry_n01\|start`（中间夹了连接件房） |
| 存档只管边、不管门扇 | `edge_states` 27 条；`merge_known_edge_states()` 只合已存在的键，`start\|room_01` 被整条丢弃 |

## 4. 根因：**门态没有唯一真相**

安全屋没有怪、开局即 `cleared=true`，清房回调 `_on_room_unsealed()` 被触发，遍历
`door_targets` 时把**包括 `target=""` 那扇**（退局气闸）也一起推开。
而 `_open_all_flow_doors()` 明确规定封闭抵达门必须关 —— 两条规则互相打架。

更深一层：`_open_all_flow_doors()` 只挂在 `_complete_expedition_loading()` 里，
而它要求 `_expedition_loading_active`（有加载圈）。续局不跑收尾，于是门停在第 1 帧
那个「全开」态。

**机制上的病根**：flow 关卡的门态同时被三处各写一次（装配收尾 / 落门 / 清房开门），
却没有任何一处是权威。而 `edge_states` 在 flow 里管的是**路线连通性**（开局恒 true），
不是门扇开关 —— 用它驱动门扇必然错。

## 5. 修法：门态 = `cleared` 的派生量

不新增存档字段、不改拓扑、不改 `edge_states`。把门态收敛成**一个推导点**：

```gdscript
TowerDescent3D._sync_flow_room_doors(room, immediate) -> {opened, closed}
    连通门（target 非空）→ 开
    封闭抵达门（target 空串）→ 恒关
```

四个时机全部走它：

| 时机 | 路径 |
|---|---|
| 装配收尾 | `_open_all_flow_doors()` → 对每房跑一次（原有"全开"语义不变） |
| 清空敌人 | `_on_room_unsealed()` → 本房连通门开（气闸门不再被误开） |
| 进已清房 / 和平房 | `_apply_flow_room_seal()` 的 `cleared` 分支 ← **新增，修续局** |
| 进未清战斗房 | `_stage_flow_room_entry()` 保留原有的延迟落门时序，未动 |

`_apply_flow_room_seal()` 原来是 `if room.cleared: return`（啥也不做）。续局时没人
把已清房的门开回来 —— 这就是「下线重进后回头路的门全关着」的成因。现在这条分支
改为调用 `_sync_flow_room_doors(room, true)`。

**为什么不存一份门态**：存了就会与 `cleared` 分叉，两个真相必然打架。EGT 的机制本来
就是「清完就开」，没有第二种真相。

## 6. 房间级状态：宝箱与易碎杂物

这两个是真正缺的存档项（门态是机制错，这两个是**采集缺失**）：

| 状态 | 修复前 | 后果 |
|---|---|---|
| 宝箱开启 | `TreasureChest3D` 在 `treasure_chest_3d` 组，采集只认 `room_prop_3d` + `RoomFurniture3D`；`restore_opened_state()` 写好了但**正式链路无人调用** | 下线重进后开过的箱子恢复未开，可反复开箱刷掉落与命运卡；钥匙每轮重扣 |
| 易碎杂物 | `breakable_clutter` 只活在房间内存 `_pending_detail_runtime_state`，`_capture_room_runtime_state()` 不采集 | 砸碎的罐子复活，可反复砸 |

### 6.1 修法：沿用「房间持有细节账」这条既有机制

`RoomFurniture3D` 的搜索状态早就走这条路（`containers` → `apply_runtime_detail_state()`）。
宝箱与杂物只是把它补齐，**没有新系统**：

| 环节 | 改动 |
|---|---|
| 记账 | `DungeonRoom3D._on_treasure_chest_opened()` 接 `TreasureChest3D.opened` → 写 `_pending_detail_runtime_state["treasure_chests"]`；杂物原本就有 `_on_interactive_clutter_broken()` |
| 采集 | `Dungeon3D._capture_room_runtime_state()` 增加 `treasure_chests` / `breakable_clutter` 两字段，**读房间账**（`get_persistent_detail_state()`），不扫场景组 |
| 回灌 | `DungeonRoom3D._restore_treasure_chests()` 新增；杂物原本就有 `_restore_interactive_clutter()`。两者都由 `_apply_pending_detail_runtime_state()` 在 detail 建完时调 |

**为什么不能扫场景组**：`RuntimeDetail`（家具 / 摆件 / 宝箱）会随流送整棵卸载重建。
detail 已卸载时组里一件实例都没有，扫出来是空表 —— 一保存就把「开过的箱子」洗回未开。
房间账跟着房间节点走，与 `visited` / `cleared` 同一权威层级。

**`apply_runtime_detail_state()` 改为合并语义**：原来是整体替换。旧存档没有这两个键，
替换会把房间内存里的账盖成空。改成逐键合并后，缺席即"这局没有记录"，不动内存账。
主链路的 `containers` / `room_light_on` 每次恢复都完整传，合并与替换对它们等价。

## 7. 验收

新增 `tests/verification/probe_expedition03_save_roundtrip.{gd,tscn}`：用
`_unload_runtime_detail()` + `ensure_detail_built()` 模拟**流送卸载重建**（与"走远再
走回来"同一条路径），新旧实例是不同对象，能真正验证回灌有没有生效。

```text
STATE_PROBE PASS 安全屋东墙必须有退局气闸门扇
STATE_PROBE PASS A1 退局气闸门必须是关的（门板留在门洞里）
STATE_PROBE PASS A2 退局气闸关着时必须挡路
STATE_PROBE PASS A3 安全屋→01 号的连通门应开
STATE_PROBE PASS A4 前置：已把 room_01 的门全部关上（closed=2）
STATE_PROBE PASS A5 进已清房后连通门必须全开（before=2 after=0）
STATE_PROBE PASS B1 宝箱房进房后必须建出箱子（actual=1）
STATE_PROBE PASS B2 宝箱必须有稳定 chest_id
STATE_PROBE PASS B3 开箱后房间账必须记下（ledger={ "chest_00": true }）
STATE_PROBE PASS B4 detail 重建后箱子必须重新建出
STATE_PROBE PASS B5 重建后必须是新实例（旧实例已卸载）
STATE_PROBE PASS B6 重建后宝箱必须仍是已开（不能复原成可再开）
STATE_PROBE PASS C1 杂物必须有 clutter_id
STATE_PROBE PASS C2 砸碎后房间账必须记下（ledger_keys=["breakable_jar_00"]）
STATE_PROBE PASS C3 重建后必须重新建出同一 clutter_id 的物件
STATE_PROBE PASS C4 重建后必须是新实例
STATE_PROBE PASS C5 重建后杂物必须仍是已碎
STATE_PROBE PASS D1 快照里必须有 treasure_chests 账
STATE_PROBE PASS D2 快照里必须有 breakable_clutter 账
STATE_PROBE OK
```

回归：

| 套件 | 结果 |
|---|---|
| `probe_expedition03_playable` | `PLAYABLE_OK`（`retreat_door side=east has_leaf=true`、`slide_doors=27 wrong_style=0`、`seal/unseal` 时序不变） |
| `probe_expedition03_clutter` | `E3_CLUTTER_OK`（placed=17 / total_items=78 / drift 0） |
| `tools/_egt_chest_probe` | `EGT_CHEST_PROBE_OK` |
| `scripts/check_level_decoupling.py` | violations 0 |

## 8. 改动清单

| 文件 | 改动 |
|---|---|
| `src/world3d/TowerDescent3D.gd` | 新增 `_sync_flow_room_doors()`（门态唯一推导点）；`_open_all_flow_doors()` 改为复用它；`_on_room_unsealed()` 改为复用它（气闸门不再被误开）；`_apply_flow_room_seal()` 的 `cleared`/和平分支补门态收敛 |
| `src/world3d/DungeonRoom3D.gd` | 新增 `get_persistent_detail_state()`、`_restore_treasure_chests()`、`_on_treasure_chest_opened()`；`apply_runtime_detail_state()` 改合并语义；`_apply_pending_detail_runtime_state()` 增调宝箱回灌 |
| `src/world3d/Dungeon3D.gd` | `_capture_room_runtime_state()` 增采 `treasure_chests` / `breakable_clutter`；`_restore_room_runtime_state()` 只在存档有该键时才下发 |
| `docs/v0.1/design/远征关卡03设计.md` | §2.1 落点表 + 新增 §2.1.0「门态是 cleared 的派生量」 |
| `docs/v0.1/09_技术施工_存档结算与复活.md` | §3 房间级明细字段与"不扫组"约束 |
| `tests/verification/probe_expedition03_save_doors.*` | 新增：门态逐帧取证 |
| `tests/verification/probe_expedition03_save_roundtrip.*` | 新增：门态规则 + 宝箱/杂物往返验收 |

## 9. 已知残留

- **远征03 以外的 flow 关卡**（目前只有 03）如果将来也有封闭抵达门，同样受 §2.1.0 规则
  保护；规则按"target 为空串"判，不认关卡 ID。
- `containers`（家具搜索状态）仍按原样扫场景组，detail 卸载时会写空表。这是既有行为，
  本次未改 —— 它不在业主报单范围内，且改动会碰所有关卡的容器存档。
- 装配期校验偶发 `spawn_boxes_missing_for_hostile_room:boss`（2026-10-29 已记录的遗留）。
