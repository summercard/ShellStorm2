# 99F 基地西侧楼梯门改为不可开启

工程版本 0.1.0。依据 2026-10-30 业主口径：「我的 99 层基地的西边那个门，就是通往 100 层天台的那个门。能不能帮我做成不可开启的一个状态。过去点击后的话会显示无法开启，需要钥匙。」

## 门是哪一扇（不是猜的）

两侧都实测过，门板 `direction == "west"`、`target_room_id` 指向对端：

| 侧 | 房间 | 门节点 | 世界坐标 | target |
|---|---|---|---|---|
| 99F 基地 | `facility` | `Door_West` | `(-15, -12, 2.5)` | `start` |
| 100F 天台 | `start` | `Door_West` | `(-30, 0, 2.5)` | `facility` |

这两扇是同一条垂直边的两端门板，来自
`_declare_edge("start", "facility", "vertical", "west", "west", "west")`，
中间由 `Stair_A`（12m，`ENV-TOWER-STAIRWELL-ROOFTOP-12M`）连接。

⚠️ 与 `BaseRooftopTransitDoor`（100F **东侧**上层门墙、外梯接口，位于 `facility` 局部 `(15, 12, -7.5)`）不是同一扇，本次没有动它。

## 为什么锁两端

只锁 99F 一侧等于**单向放行**：玩家从天台推门下来照样能过，画面上的锁就只是装饰。
两端同锁才叫「这条路封了」。

## 实现

| 位置 | 改动 |
|---|---|
| `TowerDescent3D.gd` | 新增 `BASE99_ROOFTOP_STAIR_DOOR_LOCKED` / `..._REASON` 常量；`_apply_base99_rooftop_stair_door_lock()` 在普通交通门组件装完后执行；`_lock_base99_rooftop_stair_door()` 写锁定态；`_install_locked_door_sign()` 挂门顶常驻牌；`_flash_locked_door_sign()` 做按键反馈 |
| `TowerDescent3D._open_bound_simple_room_edge_door` | 入口处 `if not door.openable` → 写拒绝理由 + 门牌闪一下 + `return true`（交互被消费，不写 edge、不流送、不开门） |
| `TowerDescent3D._activate_stair_arrival` | 权限判定提到**所有门态/路线态写入之前**（连 `_vertical_arrival_open` 都不标） |
| `TowerDescent3D._activate_stair_return_interaction` | 兜底 `set_open(true)` 之前加 `openable` 检查 |
| `SimpleTransitDoor3D.request_open()` | `if not door.openable: return false`（如实汇报"没开"） |

门态本身用既有能力，没有新造状态机：`openable = false` + `set_open(false, true)`（门板当场落到底、碰撞保持启用）+ `set_prompt_override("[E] 无法开启 · 需要钥匙")`。

**兜底硬开门是这次最容易漏的坑**：`_activate_stair_arrival` 与 `_activate_stair_return_interaction` 原本都写着
`if not _request_simple_transit_door_open(door): door.set_open(true)`。
`request_open()` 返回 false 只表示"没开"，不等于"不许开" —— 不加权限前置，从天台一侧按 E 就能把锁绕过去。

## 文案为什么挂在门顶

项目里没有能显示这句话的通道，这是查过才定的：

- `status_label` 所在 `HUD/StatusPanel` 自 2026-10-17 起 `visible = false`，只剩数据载体作用；
- `RoomDoor3D` 自己的 `DoorPrompt` 在圆点接管后退役（`set_prompt_visible()` 是空实现），且位置正好落在圆点锚点上，硬打开会叠字；
- 圆点按键牌只显示 `(e) + 功能词`，`extract_action_verb()` 会砍掉「 · 说明」尾巴，装不下「需要钥匙」。

所以新增 `LockedDoorSign`（Label3D，字号 30、橙红、`no_depth_test`、**只挂在这两扇门**），常驻显示完整句子。按 E 时用**字号 + 颜色**闪一下（不用 `scale`：Label3D 开 billboard 时基向量被归一化，`scale` 会被吃掉 —— 同一个坑 `InteractionDot3D._apply_placement` 已记过）。

## 验收

新增 `tests/verification/probe_base99_rooftop_door_lock.tscn`，全部判据读运行时快照：

| 项 | 结果 |
|---|---|
| 两端门存在 / `openable == false` / 关闭 / 碰撞仍挡路 | 通过 |
| 文案含「需要钥匙」；`LockedDoorSign` 存在且同文案、`no_depth_test` | 通过 |
| 走 E 交互通道后门仍关闭、`openable` 未被篡改 | 通过 |
| 走楼梯返回通道（`_activate_stair_return_interaction`）后仍关闭 | 通过 |
| 对照：东侧 `BaseRooftopTransitDoor` 仍 `openable == true` | 通过 |

`RESULT: PASS`，退出 0。

配套改动与回归：

- `verify_door_passability` 测试 4 的样本门改为 `_pick_openable_door()` —— 锁定门的文案被 override 钉死，不再参与「按 `access_policy` 切文案」的状态机断言；
- 同文件测试 8 由「rooftop→facility 首次 E 要把门打开」改为反向口径「首次 E 被拒、门仍关、碰撞仍阻挡、`openable` 仍 false」；
- 重跑：通过 11 / 失败 1，唯一失败是**测试 9「找不到 EVENT 测试房」—— 与本次无关**。已验证：把 `BASE99_ROOFTOP_STAIR_DOOR_LOCKED` 临时置 false 后该项同样失败；
- `verify_door_function_check`、`verify_base_rooftop_transit_door_motion`（四扇交通门共用模型/动画/碰撞/E 开启）、`verify_interaction_dot_presentation` 全部退出 0。

## 未做 / 边界

- **东侧阁楼门没封**。玩家若已能上到 99F 阁楼，仍可走 `BaseRooftopTransitDoor` 到 100F 东侧。要彻底封掉 99F→100F 需要一并处理，本次按「只改主人指的那扇门」执行。
- **没有钥匙系统**。`requires_key = true` 只服务文案与快照语义，本局任何地方都不发放这把钥匙。以后接钥匙时，把 `_lock_base99_rooftop_stair_door()` 里的 `set_openable(false)` 改成按持有状态推导即可，门牌与交互协议不用动。
- 门态不存档（沿用既有口径：门只负责表现与阻挡，路线状态归 edge）。
- 鼠标点击门不会触发交互 —— 本作门交互统一走 `interact`（E / 手柄键）；`InteractionDot3D` 本身不监听鼠标。
