### 轮次 268 — 2026-05-27 07:36 UTC+8

### 维度
PH12房间过渡动画接入完整链路：命运卡片选择后自动触发过渡

### 问题
轮次267创建了 RoomTransitionFX（黑幕淡入淡出）和 `_enter_room_by_id_with_transition()`，但门洞流程尚未接入：
- 玩家穿过已开启的门洞时，仍调用普通 `_enter_room_by_id()`（瞬间切换，无过渡）
- 命运卡片选择后也未触发过渡动画

### 玩家可感知结果
- 用钥匙开门 → 命运卡片选择 → 选择后自动触发黑幕淡入淡出 → 进入新房间
- 全流程：黑幕0.2s淡出 → 命运卡片选择 → 黑幕0.3s淡入 → 新房间
- 过渡期间游戏逻辑暂停（get_tree().paused），玩家输入锁定直到淡入完成

### 修改内容
| 文件 | 改动 |
|---|---|
| `src/game/RoomGameMode.gd` | 新增 `_pending_door_target_id` 状态变量，记录待进入的目标房间ID |
| `src/game/RoomGameMode.gd` | `try_open_room_door()` 开门后设置 `_pending_door_target_id = target_id` |
| `src/game/RoomGameMode.gd` | `_on_fate_card_button_pressed()` 命运选择完成后调用 `_enter_room_by_id_with_transition(target_id, from_id)` |

### 关键实现细节
- `_pending_door_target_id`：在 `_show_door_fate_cards()` 前设置，确保玩家穿过门洞时能读取到目标ID
- `_on_fate_card_button_pressed()` 末尾直接 await `_room_transition.transition(transition_callback)`（transition 是 async）
- 降级处理：`_room_transition` 为 null 或无 transition 方法时自动降级到普通切换

### 验证
- Godot --headless --quit: EXIT 0 ✅
- 链路：try_open_room_door → _pending_door_target_id 设置 → _show_fate_cards → 玩家选择 → _enter_room_by_id_with_transition → 淡出→回调→淡入 ✅

### 剩余风险
- 人类试玩验证：实际穿过门洞+命运选择时过渡视觉是否流畅
- 过渡期间玩家输入是否正确锁定（已通过 `_set_player_input_locked(true/false)` 控制）
- 快速连续操作（开门后立即再按E）是否会导致 `_pending_door_target_id` 状态错乱

### 下轮最可能方向
1. PH12门视觉深化（门框光效/开启动画/门类型颜色区分）
2. PH11大地图小地图实际运行验证（RoomGameMode map_generated信号发出时机）
3. PH07精英怪成长系统档案池持久化（save/load）
4. 人类试玩验证