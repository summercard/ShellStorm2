# 远征03：过门镜头不再弹 / 幕墙门洞留口（2026-10-29）

## 1. 业主报单（原文）

1. 「过房间的时候黑色区块硬切太难受了。首先要把墙壁上会导致角色摄像机拉起的那个脚本去掉。
   不然摄像机会弹一下上去。不舒服。」
2. 附图红框圈出门洞里的纯黑方块：「过门的时候这个黑色可以不用，直接看到下一个房间的东西即可。」

## 2. 排查：两条都不是"脚本还挂在墙上"

### 2.1 "摄像机会弹一下上去"

先确认墙上没有任何相机相关脚本 —— `grep camera_lower_wall` 命中的全是**碰撞体 meta**
（`DungeonRoom3D` 给墙/门框/过梁打的标记），没有挂脚本。而"墙碰撞抬升"这条路径
在上一轮就已经被 `_flow_rules_active` 短路掉了（`_update_camera_lower_wall_lift()` 把目标锁死 0）。

真正的位移源是**上一轮自己加的边界夹取** `_clamp_flow_camera_into_room()`：

| 量 | 值 |
|---|---|
| 镜头跟随距离 | `CAMERA_DEFAULT_TRAILING_M = 4.914m` |
| 夹取范围 | 当前房间足迹内缩 `FLOW_CAMERA_ROOM_INSET_M = 0.55m` |
| 触发时机 | 跨门槛那一帧 `_current_room_id` 换房 ⇒ 夹取边界整块搬家 |
| 单帧位移上限 | ≈ 4.9m |

一帧内平移 4.9m，玩家感知就是"弹一下"。房间越小、贴墙越近，弹得越狠 —— 与业主描述完全对齐
（他说的是"过房间的时候"，不是"贴墙的时候"）。

### 2.2 门洞里的黑方块

射线实测（`capture_expedition03_curtain` 里的 `_dump_pixels`）：

```
E3_PX (545,260) color=0.00/0.00/0.00 hit=WallDoorSegmentBody  at=(158.9, 2.7, -10.1)
E3_PX (545,305) color=0.07/0.14/0.21 hit=WallDoorSegmentBody  at=(159.0, 1.5, -10.1)
```

两块原因叠在一起：

1. **幕墙在门洞处没开洞** —— `FlowViewWalls` 是密闭的四面环，门洞后面永远是一片黑；
2. 门洞边上的**墙垛/过梁是背光实体墙**（射线落在 `WallDoorSegmentBody` 上），
   本来就该暗。这一条不是缺陷。

## 3. 修法

### 3.1 镜头：位置修正归零

删掉 `_clamp_flow_camera_into_room()` 与 `FLOW_CAMERA_ROOM_INSET_M`，`_apply_indoor_camera_pose()`
不再调它。flow 关卡的镜头此后只有一条规则：**角色位置 + 固定后方偏移**，逐帧连续。

"镜头别跑出房间"改由幕墙让路承担（见 3.2），镜头本身零修正。

### 3.2 幕墙：门洞留口 + 镜头出门整圈收起

- `_build_flow_view_walls()` 改成**四面各一个节点**（`FlowViewWallsNorth/South/West/East`），
  每面按 `DungeonRoom3D.get_wall_door_lanes(side)` 切门洞：
  - 洞宽 = `DOOR_CLEAR_WIDTH_M (2.2) + 2 × 0.35m` 视差余量（`FLOW_VIEW_DOOR_HOLE_BLEED_M`）；
  - 洞高 = `DOOR_CLEAR_HEIGHT_M (2.5)`，**过梁以上照挡**。
- 新增 `DungeonRoom3D.get_wall_door_lanes(side)`：与 `_build_wall()` 读同一份
  `wall_door_openings_<side>` 声明（EGT 枢纽有同侧双门）。
- 新增 `_update_flow_view_visibility()`：每帧比较镜头是否落在幕墙矩形内，**离开即整圈隐藏**，
  回来即恢复。判据只比坐标，无射线、无平滑。
- `FLOW_VIEW_WALL_TOP_M` 由 26m 降到 12m：`dir.y < 0` 的视线在墙平面上的高度必然
  ≤ 相机高度（10.26m），12m 足够；26m 那面黑墙在镜头掠到墙外时会吃掉半个屏幕。

### 3.3 过渡小间补光（最终方案：窄范围常驻灯）

门洞留口解决了"被遮挡"，但**门后那间 5×5 连通房本身没有灯**（实测 9 间 `cr*`
里 8 间 `WastelandLight3D` 计数为 0），所以看到的是一个没光的盒子。

最终方案（`_ensure_flow_passage_lighting()`，按几何判据 `max(x,y) ≤ 8m` + flow 开关，
不认 room_id）：

| 项 | 值 | 依据 |
|---|---|---|
| 范围 | 4.5m | 5×5 小间半对角 3.54m，4.5 刚好照满自身、**不外溢到隔壁大房** |
| 能量 | 3.0 | 小间 25㎡，比战斗房小一个数量级 |
| 高度 | 2.35m | 低于门洞净高 2.5m，从隔壁看进来是一层平铺环境光 |

**坑**：第一版用 9m + 2.4，范围外溢到隔壁战斗房 ⇒ 九盏灯占满 `gl_compatibility`
的每物体 8 盏灯预算，把房间自己的顶灯挤出去 —— 表现是"房间反而比改之前更暗"。
范围压到自身尺寸后不再影响隔壁。

### 3.4 试过但否掉的

| 方案 | 为什么否 |
|---|---|
| 按侧隐藏（镜头在墙外就藏那一片） | 玩家过门时**垂直于视线**的两片墙同样扫进画面，投影成对顶黑三角，比整块黑还难看 |
| 给过渡小间（5×5 `cr*`）加 9m / 2.4 能量的常驻灯 | 范围外溢到隔壁战斗房，占满 `gl_compatibility` 的**每物体 8 盏灯**预算，把房间自己的顶灯挤出去 ⇒ 房间整体变暗 |
| 走廊中点加一盏补光 | 远征03 的走廊全部 `module_count = 0`（房间自带静态墙体），该分支是死代码 ⇒ 删除 |
| 幕墙上沿保持 26m | 无功能收益，只有可见代价（半个屏幕的黑） |

## 4. 验收

```
PLAYABLE rooms=27 ready=true
PLAYABLE camera lift=0.000 trailing=4.914 base=4.914 wall_detected=false
PLAYABLE camera_room_switch pairs=27 worst_jump=0.000 pair=
PLAYABLE curtain rect=[P:(-5.16,-5.16) S:(15.32,15.32)] y=[-1.00..12.00] cam_y=10.26 room=start doors=2
PLAYABLE curtain_drift=0.160 (expect=[P:(-5.0,-5.0) S:(15.0,15.0)])
PLAYABLE curtain_door_holes=2 lanes=2
PLAYABLE curtain_area=793.0 expect=793.0
PLAYABLE curtain_side_hide outside=hidden inside=shown
PLAYABLE wall_leak=77 limit=500
PLAYABLE_OK
```

新增/改写的断言（`probe_expedition03_playable`）：

| 断言 | 守的是什么 |
|---|---|
| `camera_room_switch` 27 对相邻房、最差位移 0.000m | 换房不许挪镜头（弹一下就红） |
| `curtain_door_holes == lanes` | 幕墙门洞数与墙体门洞数一致（门洞里不能是黑） |
| `curtain_area` 与「整面 − 门洞」差 ≤ 2㎡ | 网格**真的切了**（只看 meta 计数是自证） |
| `curtain_side_hide outside=hidden inside=shown` | 镜头出门收起、回房恢复 |

真实渲染取证：`tests/verification/capture_expedition03_curtain.tscn`
（房里远端 / 房中部 / 站在门洞 / 已跨过 四档 + 关幕墙对照图）。

## 5. 已知遗留

- **装配期校验会随机失败**：部分 flow 骨架给 Boss 房漏生成 `spawn_boxes`
  （`spawn_boxes_missing_for_hostile_room:boss`），偶尔还出现
  `spawn_placement_on_non_hostile_room:fireplace_room_inj2`。这与本轮改动无关
  （改前改后同样概率），取证脚本因此改为"失败就重开进程"。**该缺陷未修，另开单。**
- 门洞边上墙垛/过梁的暗面是实体背光，不属遮挡缺失。
