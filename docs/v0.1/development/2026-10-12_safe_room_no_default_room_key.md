# 2026-10-12｜入口安全房不再默认掉一把房间钥匙

业主原话：

> 「我安全房里头会默认刷一把钥匙出来，这个去掉。」

## 一、现象

远征关卡01 的入口安全房（`room_id = "start"`，`room_type = "STAIR_LOBBY"`）**一进房就掉一把
`item_room_key`**。链路：

`_on_room_entered()` → 房型不在 `HOSTILE_ROOM_TYPES` → `_mark_room_cleared(room, true)`
（`STAIR_LOBBY` 不在 `["START","EXTRACTION","ELEVATOR"]` 排除表里）→ `_ensure_room_key_reward()`
→ `_room_produces_room_key() == true` → `_spawn_room_key()`。

## 二、根因：判据把「退出战局门」也算成了消耗钥匙的门

只读探针实测（seed `77001199`，`ExpeditionLevel01_3D`）：

```
start  type=STAIR_LOBBY  peaceful=false  produces_key=true
   targets = { "east": "", "north": "room_01" }
   policies: east[clear=true,key=true,fate=true]   north[clear=false,key=false,fate=false]
```

- `north`（→ `room_01`）：**免费通行门**，`requires_key = false`；
- `east`：`door_targets` 该侧为**空字符串** = 安全房壳体的「封闭抵达门 / `[E] 退出战局`门」
  （口径见 `verify_expedition_level01_flow._verify_safe_room`：`open_target_count == 1`、
  `closed_target_count == 1`、`retreat_door_count == 1`）。它**从不经 `_try_open_room_door()`**，
  不吃钥匙，也不消耗 `_open_edges`。

但 `_door_policies_for_record()` 是按 `record["door_targets"]` 的 **key 集合**逐方向发策略的，
于是连这扇空目标门也拿到了 `requires_key: true`。`_room_produces_room_key()` 只看
`door_policies[direction].requires_key`，因此把整间安全房判成「产钥匙房」。

**这间房里钥匙无处可用** —— 前门免费、退出门不吃钥匙。与 `_room_produces_room_key()`
自己的注释口径（「钥匙的唯一用途是开下一扇门；用不掉的垃圾道具必须一并不发」）直接冲突，
属判据漏洞，不是设计。

## 三、改法

`src/world3d/Dungeon3D.gd::_room_produces_room_key()`：迭代方向时**跳过 `door_targets`
该侧为空的门**，只认「有实际去向」的门。

```gdscript
for direction in declared.keys():
    if str(targets.get(direction, "")).is_empty():
        continue
    if bool((declared[direction] as Dictionary).get("requires_key", true)):
        return true
```

覆盖面（同探针实测）：

| | 改前 | 改后 |
| --- | --- | --- |
| 产钥匙房间数 | 13 / 13 | **12 / 13** |
| 入口安全房 `start` | `true` | **`false`** |

其余 12 间房的门都有实际目标且 `requires_key = true`，判定**逐房不变**。塔楼 / 随机地牢里
若某房确实存在需钥匙的门，判据照旧；只有「门全是空目标」的房才会被判成不产钥匙。

## 四、存档与恢复

| 路径 | 行为 |
| --- | --- |
| `_restore_room_runtime_state()` | `_room_produces_room_key == false` ⇒ 走既有的 `queue_free` 分支，**旧档里已掉在安全房地上的那把钥匙会被自动清掉** |
| `_capture_room_runtime_state()` | 不再把安全房的 `room_keys` 写进快照 |
| `_room_key_count` / `inventory.item_room_key` | **不动** —— 玩家已拾起的钥匙不回收，不会凭空扣减 |

没有 schema 变更，旧档可直接读。

## 五、门禁同步

`tests/verification/verify_expedition_level01_flow.gd::_verify_safe_room()` 新增一条断言：

```gdscript
if bool(tower.call("_room_produces_room_key", start_room)):
    failures.append("入口安全房不得产出房间钥匙（其两扇门均不消耗钥匙）")
```

反向对照必红：删掉 `Dungeon3D` 里「跳过空 target 门」那两行 ⇒ 本断言报错。

## 六、验收记录

| 环节 | 命令 | 结果 |
| --- | --- | --- |
| 只读探针（临时，已删） | `godot --headless --path . --scene res://tests/verification/probe_safe_room_key_audit.tscn` | `PROBE_SAFE_ROOM_KEY_AUDIT_OK`；`start produces_key` `true → false`，产钥匙房 13 → 12 |
| 远征主流程门禁 | `godot --headless --path . --scene res://tests/verification/verify_expedition_level01_flow.tscn` | `EXPEDITION_LEVEL01_FLOW_OK`（含新断言） |
| 3D 战斗推进门禁 | `... verify_3d_combat_progression_flow.tscn` | `3D_COMBAT_PROGRESSION_FLOW_OK` |
| 98F 区块00 装配 | `... verify_block00_floor98_assembly.tscn` | `BLOCK00_ASSEMBLY_OK checks=228` |
| 存档往返 | `... probe_expedition_connection_ports.tscn` | `EXPEDITION_CONNECTION_PORTS_OK checks=368888 seeds=64` |
| 塔楼下行 | `... verify_tower_descent_flow.tscn` | `TOWER_DESCENT_FLOW_MIGRATED`（该场景已迁走，退出码 0） |

**与本次无关的既存红项**（改动前后逐行一致，已用「临时反转改动」对照确认）：
`verify_door_passability` 通过 10 / 失败 4（含「找不到 EVENT 测试房」）、
`verify_3d_parity_core` 两条 `ERROR`（`Opened adjacent room was not streamed in` /
`Streamed parity slice exceeds node budget: 2562/2200`）。

## 七、没有动的东西

- **没有**把 `STAIR_LOBBY` 加进 `_ensure_room_key_reward()` 的排除表（`["START","EXTRACTION","FACILITY","ELEVATOR"]`）。
  理由：塔楼里的安全房门**有实际目标且确实要求钥匙**，一律不发会造成「进安全房拿不到钥匙 ⇒
  出门卡死」。本次修的是判据漏洞，不是给房型加特例。
- 没有改 `_door_policies_for_record()` 的策略生成（退出门仍带 `requires_key: true`，但它本来
  就不走 `_try_open_room_door()`，改它属于另一件事）。
- 没有动车体壳体、门扇、美术资产、`RoomKeyPickup3D`。
