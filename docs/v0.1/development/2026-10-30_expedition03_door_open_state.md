# 远征03 房门：开门是「状态」而不是「消失」（2026-10-30）

## 1. 业主报单

> 「远征-03 的其它房间的门，应该是可打开和不可打开的状态，而不是直接消失。
> 保证机制的状态下，修改表现。」

范围明确：**只改表现，机制不动**。

## 2. 为什么门会「消失」

不是节点丢了，是门板退到了看不见的地方。

| 量 | 值 |
|---|---|
| 门板厚度 | 0.18m |
| 房间墙厚 | 0.28m |
| 开到位时门板位置 | `panel_x = ±1.705`（门洞边线之外） |
| 门板朝向 | 与墙共面（`panel_z = 0`） |

两扇只沿 x 方向滑出，于是**整块落在墙体内部**（0.18 < 0.28，完全装得下）。
深度测试把门板正确挡在墙后 —— 从房间看就是一个空的门洞。
这不是渲染 bug，是几何决定的必然结果。

诊断时先高亮门板确认过：

```text
E3_DOORSTATE closed panel_x=-0.55 panel_z=0.00 blocks=true    ← 门板在门洞里
E3_DOORSTATE open   panel_x=-1.71 panel_z=0.23 blocks=false   ← 门板贴墙、门洞通
```

## 3. 改法：开到位后贴到门墙内侧

`RoomDoor3D._set_open_slide()` 增加一个沿门法线的落点：

```text
关门：panel_n = ( ±quarter,            y, 0 )
开门：panel_n = ( ±1.705,              y, 0.23 × 内侧符号 )
```

`0.23 = 墙半厚 0.14 + 门板半厚 0.09` —— 门板背面正好贴在墙内表面，
**既不埋进墙里、也不占门洞宽度**（门洞净宽 2.2m 全通）。

`_slide_inward_sign()` 负责"哪边朝房间内"。`west` / `east` 的门在
`_build_door()` / `_build_door_for_port()` 里都设了 `rotation.y = +90°`，
所以局部 +z 在世界里落到 ±x 之一，符号与南北相反：

| 墙 | 房间内侧 | 局部 z 符号 |
|---|---|---|
| north | +z | +1 |
| south | −z | −1 |
| west | +x | +1 |
| east | −x | −1 |

### 3.1 机制一行没动

| 项 | 状态 |
|---|---|
| 碰撞 | 仍是单块覆盖整个门洞，开完才 `disabled` |
| 行程 | `travel = half_width − quarter + panel_half`，逐字未变 |
| `is_open` / 门态推导 | 未变（§2.1.0 那条 `cleared` 派生规则完全没碰） |
| `_on_slide_finished` | 签名多一个 `park_z`，只用来落位；`motion_finished` 时机不变 |

调整了一个实现细节：tween 从 `position:x` 改成 `position`（完整 Vector3），
因为现在 x 与 z 要同时到目标位。y 仍取 `presentation_clear_height * 0.5`，
与原来一致。

## 4. 验收

### 4.1 数据判据（新增断言）

`probe_expedition03_playable` 增加一段 `slide_park`：

```text
PLAYABLE slide_doors=27 wrong_style=0 missing_second=0 bad_geometry=0
PLAYABLE slide_panel_thickness worst=0.180(Door_North) too_thick=0 wall=0.28
PLAYABLE slide_park min_panel_z=0.230 hidden=0 limit=0.09
PLAYABLE_OK
```

判据：开到位时 `|panel_z| ≥ 0.09`（半个门板厚）。低于它就说明门板一半以上埋在
墙体里，画面上读不出"这里有扇门"——**这条断言就是"门消失"的回归守卫**。

同一份 `get_snapshot()` 新增 `panel_z` 字段供断言读取。

### 4.2 真实渲染取证

新增 `tests/verification/capture_expedition03_door_state.{gd,tscn}`：
固定机位对着门洞拍，**走真实机制**（未清房 `set_room_seal` 关门、
已清房 `_apply_flow_room_seal` 开门），不手工摆门板。

```text
E3_DOORSTATE_LIGHT room_light_on=true central=true
E3_DOORSTATE_PICK room=room_01 type=COMBAT dims=(40.0, 30.0) side=north
E3_DOORSTATE closed cleared=false sealed=true panel_x=-0.55 panel_z=0.00 blocks=true
E3_DOORSTATE open   cleared=true  sealed=true panel_x=-1.71 panel_z=0.23 blocks=false
```

产出（`outputs/expedition03_door_state_20261030/`）：

| 文件 | 内容 |
|---|---|
| `e3_doorstate_0_closed.png` | 关门：双扇合拢在门洞，ARCHIVE 03 门面完整可见 |
| `e3_doorstate_1_open.png` | 开门：两扇贴墙、门洞全通，门板仍清晰可见 |
| `e3_doorstate_2_open_side.png` | 侧视角：确认门板贴墙的进深与厚度 |
| `e3_doorstate_9_open_debug.png` | 诊断：门板刷高亮自发光，证明几何位置正确（非遮挡问题） |

像素采样（同机位、同一行）证明两态可区分：关门时门洞处亮度 113（门板面），
开门时门洞处 146（看穿到隔壁）、两侧 67（门板 + 阴影）。

### 4.3 回归

| 套件 | 结果 |
|---|---|
| `probe_expedition03_playable` | `PLAYABLE_OK`（`seal/unseal` 时序、退出门交互全绿） |
| `probe_expedition03_save_roundtrip` | `STATE_PROBE OK`（门态 A1~A5 未受影响） |
| `probe_expedition03_save_doors` | 气闸门恒关、连通门开 |

## 5. 踩的坑（诊断方法本身的坑）

| 坑 | 表现 | 处理 |
|---|---|---|
| 取证相机放下后又被玩家相机抢走 | 两张「同机位」图机位不一样 | 截前 `cam.make_current()` 夺回 |
| 相机高于 2.8m 墙顶 | 拍到的是墙外幕墙的黑 | 机位压到眼高 1.72m |
| 房间灯没开 | 全黑，门板与墙亮度都是 27 | 先 `ensure_detail_built()` 再 `set_room_light_on(true)` —— 灯属于 detail，detail 没建时开灯是空转 |
| 截在门动画半途 | `panel_x=-0.79`（半开状态） | 截前等 40 个物理帧，动画 0.24s |
| 调试染色插在正式图之前 | 侧视角那张全是红色 | 染色图放最后一帧 |

## 6. 改动清单

| 文件 | 改动 |
|---|---|
| `src/world3d/RoomDoor3D.gd` | 新增 `SLIDE_PARKED_WALL_INSET_M`、`_slide_inward_sign()`；`_set_open_slide()` 增加法线落点；`_on_slide_finished()` 签名带 `park_z`；`get_snapshot()` 增加 `panel_z` |
| `tests/verification/probe_expedition03_playable.gd` | 新增 `slide_park` 断言（`min_panel_z` / `hidden`） |
| `tests/verification/capture_expedition03_door_state.{gd,tscn}` | 新增：真实渲染取证 |
| `docs/v0.1/design/远征关卡03设计.md` | §2.1 表格增「开合方式 / 门态表现」两行；新增 §2.1.0.1 |

## 7. 取舍记录

- **凸出量**：0.23 让门板完全露出（背面贴墙内表面）。若改成 0.14（门板中心与墙中心面重合），
  门板会有一半埋进墙里，又回到"看起来变薄/模糊"的问题 —— 与业主本次诉求相反，故不采用。
- **玩家穿模**：门板凸出墙面 0.18m，贴着墙走会有轻微视觉穿插。这是"看得见"的必要代价；
  真实推拉门收在门边也是这个形态。
- **未动塔楼与远征01/02**：它们的门是 `lift` 升降，不进 `_set_open_slide()`，
  行为逐字不变。
