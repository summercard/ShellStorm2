# 暗门做成房间 TSCN 里的可手摆预制体

> 2026-10-19 · 业主：**「把这个预制体加到场景房间的预制体里，让我可以在房间的预制体 tscn 里头
> 看到、可以手动摆放。这样既不影响功能，我也可以直观地去调整它。」**

之前要调一个暗门位置，得改 `floor_00.json` 的 `wall` / `lane`，再重跑关卡看效果。
门本身是 `SecretBranch3D` 在运行时 `SecretDoor3D.new()` 拼出来的，编辑器里根本不存在 ——
看不见，也拖不动。这一轮把它做成**房间 TSCN 里的一个节点**。

---

## 1. 之前为什么拖不动

三层原因，缺一条这件事都做不成：

| 层 | 事实 |
|---|---|
| **门是代码拼的** | `SecretBranch3D._build_door()` 里 `SECRET_DOOR_SCRIPT.new()`，门叶/木板/灯/碰撞全靠 `configure()` 现场实例化 |
| **位点由数据算** | `_collect_sites()` 从房间记录 + `secret_site.lane` 推坐标，再按实测墙面外推 0.40m |
| **编辑器里没有门** | 房间 TSCN 里只有墙件、地砖、灯、家具，没有暗门这个节点 |

## 2. 做了什么

### 2.1 暗门整樘预制体

新建 `assets/art/environments/tower_zones/expedition/runtime/common_components/secret_door/secret_door_root_top3d.tscn`：

```
SecretDoor (StaticBody3D, SecretDoor3D.gd)
├─ DoorLeaf      门框 + 门腔 + 半掩门（常驻）
├─ Boards        5 横板 + 2 斜撑 + 19 钉（可打掉）
├─ BoardsShape   木板层碰撞
├─ LeakLight     板缝透光
└─ MountBox      安装箱（默认隐藏，按外推量显形）
```

`SecretDoor3D` 改成**先找子节点、找到就复用**，找不到才按老路实例化资产：

```gdscript
func _build_visual(with_boards: bool = true) -> void:
	if _door_leaf == null:
		_door_leaf = get_node_or_null("DoorLeaf") as Node3D
	if _boards == null:
		_boards = get_node_or_null("Boards") as Node3D
	...
```

这样同一份脚本既能跑预制体实例、也能跑 `new()` 出来的空节点，两种用法互不干扰。
`_build_leak_light()` / `_build_collision()` / `set_mount_depth()` 同样处理。

常开门（返程/撤离）多了 `_drop_boards_layer()`：木板层是**不存在**，不是"藏起来"——
不然 `debug_snapshot().has_boards` 还是真，A15 会报「返程门还带着木板层」。

### 2.2 房间 TSCN 里写入门节点

`scripts/generate_expedition01_room_static_scenes.gd` 新增 `_emit_authored_secret_doors()`：
从运行时 `SecretBranches.debug_snapshot()["sites"]` 取本房间的位点，实例化预制体，挂在
`ExpeditionRoomStaticLayout` 下：

```
[node name="SecretDoor_S1" type="StaticBody3D" parent="." instance=ExtResource("31_35a3r")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 2.5, 0, 19.135002)
metadata/secret_site_id = "S1"
metadata/secret_pair_id = 0
metadata/secret_role = "entry"
metadata/secret_door_position_source = "authored"
```

**节点名就是契约**：`SecretDoor_<site_id>`。改名等于告诉运行时「这个位点没手摆过，走自动」。

位置真源分两层：

1. 已有 TSCN 里那扇门的 `transform` —— 业主拖过的，**原样留住**；
2. 没有才用运行时位点（已按实测墙面外推到墙外 0.40m）。

所以**重跑生成器不会把手调抹回自动值**：

```
AUTHORED_SECRET_DOORS room=room_03 doors=1 kept_manual=1
```

### 2.3 运行时接管，而不是再建一扇

关键发现：**运行时房间本来就是实例化房间 TSCN 的**（`DungeonRoom3D._build_shell()`
里 `static_scene.instantiate()` → 挂成 `AuthoredLayoutArtRoot`）。所以 TSCN 里那扇门
在游戏里本来就在场——再建一扇只会两扇叠在同一处。

于是 `_build_door()` 先尝试 `_adopt_authored_door(site)`：房间子树里找到
`SecretDoor_<site_id>` 就直接 `configure()` 接管，**不动它的 transform**、不 `add_child()`。

晚一步的情况（bootstrap 时房间还没装配完、位点读不到 TSCN）走 `settle_sites()`：
读到手摆位置后把自建那扇搬过去，同时 `_drop_room_duplicate_door()` 把房间里那扇摘掉
（`remove_child` + `queue_free`，不能只 `queue_free`——同帧 A22 还会扫到它）。

## 3. 四个坑

### 3.1 `SceneState.get_node_path()` 给的是节点自己的路径，不是父路径

一开始按「父路径 == `"."` 就是根层子节点」写，结果一个都读不到。实测输出：

```
[110] name=SecretDoor_S1 parent='./SecretDoor_S1' type=StaticBody3D props=13 transform=true
```

正确判断是**斜杠恰好 1 个**：`./SecretDoor_S1` = 根层，`./SecretDoor_S1/DoorLeaf` = 子节点。

### 3.2 TSCN 存房间局部，位点是世界坐标

第一版把 `sites[].position`（世界）直接写进 `transform`，桌面上一看门在 `(154.6, -152.5)`——
那是世界坐标。运行时乘一次房间 `global_transform` 才回到世界，结果差 98~256m，
正好是各房间自己的平移量。

两头都要换算：

```gdscript
# 写：世界 → 房间局部
room_local = dungeon_room.global_transform.affine_inverse() * _site_transform(site)
# 读：房间局部 → 世界
world_xform = room.global_transform * local
```

### 3.3 A22 把门自己当成「挡住门的墙」

门进了房间子树之后，`_measure_visual_cover()` 扫到的第一件就是**木板本身**，
报「整樘门被 ImportedModel 的外壳盖住（凸出 0.14m）」——那 0.14m 是板厚。
加 `_is_secret_door_part()`：往上 4 层找名字以 `SecretDoor` 开头的祖先，命中就跳过。

### 3.4 S2/S4 的墙是转角壳体，认不出「凸出量」

`_is_wall_mesh()` 只认名字/路径含 `wall` 的件。S2（room_06 东墙）、S4（room_10 西墙）
所在位置是 `ENV_TOWER_CORNER_L_5M` 这类转角壳，名字里没有 `wall`，实测 `face == INF`。

自动外推走「认不到墙 → 按装配常量 0.40m 前推」；手动位点不能推，只能记数值。
于是给它记 `protrude_m = 0.40` 并打 `protrude_estimated = true`，NOTE 里用 `~` 标出来，
和实测的 `*` 区分：

```
[NOTE] A21/A22/A23 实测 4 个位点（* = 手摆且实测凸出，~ = 手摆但墙件认不出、按装配常量估）：
       凸出 S1=0.40m* S2=0.40m~ S3=0.40m* S4=0.40m~
```

这意味着 S2/S4 在编辑器里拖进墙里，A23 不会变红。**已知限制**，要根治得让
`_is_wall_mesh()` 认转角件（会牵连外推逻辑，另开一次改动）。

## 4. 新增断言 A24

```
A24 位点 S1（room_03）TSCN 里手摆的门与运行时门不重合：差 0.003m，朝向点积 1.000
```

判据：`房间.global_transform × (静态根 transform × 门 transform)` 与 `sites[].position`
差 ≤ 1cm、朝向点积 ≥ 0.99。这条盯住「拖完游戏里没跟着走」这类问题——
单元测试里最容易出现，人眼看图看不出来。

## 5. 怎么用（给业主）

1. 用 Godot 打开 `assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01/f00_room_03_static_layout.tscn`；
2. 场景树里就有 `SecretDoor_S1`（room_06 是 `S2`、room_07 是 `S3`、room_10 是 `S4`），
   选中直接拖、转、改 Inspector 里的参数（灯能量、安装箱材质都能改）；
3. 保存，进游戏 —— **位置就是拖到的位置**，不需要重跑任何脚本。

要重新生成房间场景时：

```
SS_STATIC_ROOMS=room_03 godot --headless --path . --scene res://scripts/generate_expedition01_room_static_scenes.tscn
```

生成器会 `kept_manual=1` 保留你拖过的位置，不会覆盖回自动值。

## 6. 验证

```
✔ S1 room_03 TSCN局部=(2.50,0.00,19.14) → 世界=(92.50,0.00,-20.86) 运行时=(92.50,0.00,-20.86) 差=0.000m 朝向=1.000
✔ S2 room_06 TSCN局部=(14.60,0.00,7.50)  → 世界=(154.60,0.00,-152.50) 运行时=同上 差=0.000m
✔ S3 room_07 TSCN局部=(-11.78,0.00,-5.00) → 世界=(125.72,0.00,-197.50) 运行时=同上 差=0.000m
✔ S4 room_10 TSCN局部=(-14.60,0.00,-7.50) → 世界=(40.40,0.00,-257.50) 运行时=同上 差=0.000m
AUTHORED_DOOR_PROBE_OK 位点=4
```

**拖动闭环实测**：把 S1 的 `transform` 的 x 从 `2.5` 改成 `6.5`（模拟拖 4m），
运行时 `sites[].position` 立刻变成 `96.50`；重跑生成器后 `kept_manual=1`，位置仍是 `6.5`。

```
[NOTE] A24 手摆门与运行时一致：4 扇
SECRET_BRANCH_FLOW_OK 位点=4 槽位固定 门洞不重合 门板可见 … 存档=往返一致
```

新增探针 `tests/verification/probe_secret_door_authored.gd`（核对 TSCN ↔ 运行时），
可随时手跑。

## 7. 接着爆出来的问题：按 E 传送到空房间

业主：「我可以看到了，也可以打破墙，但是我点击 E 后，传送会传送到空房间，
好像没有装配支线的房间。」

**不是房间没装配。** 子图 7 间房全都在、壳体全是正式美术、可视件 1333～1910 件。
问题在落点：

```
[传送] 落点=(1020.0, 0.0, 39.135)      ← 门给的
        secret_0_0 中心=(1015.0, 0.0, 0.0)   dims=30x40  → 房间 z 只到 ±20
[传送] 落点后 玩家=(1020.0,0.0,39.1)  on_floor=false  velocity=(0,-0.41,0)
```

落点在子图首间**南墙外 19m 的空中**，人一直往下掉。房间本身好得很。

### 根因

`_rebase_door()` 把手摆的位移也加到了传送落点上：

```gdscript
var delta := target - door.global_position   # 门从自动位点搬到 TSCN 位点的位移
door.global_position = target
...
door.call("set_teleport_target", (teleport as Vector3) + delta, verb)   # ← 这一行
```

那句老注释写的是「出口侧落点就定在门前面」。**改版后这句话不成立了**：
入口/出口门的落点都是**子图房间中心**（`points[0]` / `points[last]`，世界 `x≈1015`），
跟门在 `room_03` 哪个墙角一点关系都没有。S1 的数据位点与手摆位分别在房间的**两侧墙**上
（房间局部 `z=-20.13` 与 `z=+19.135`，房深 40m），差 **39.135m**，落点被同一个 delta
推出 39m —— 正好甩出房间。

`_shift_door()` 里同样的两行（外推量 ≤0.4m）也一并删了。

**判据为什么全绿**：A9 比的是「玩家位置 vs 落点」，两边被同一个 delta 推歪，
距离仍是 0.000m —— 一条典型的自证式断言。

### 修法与验证

- `_rebase_door()` / `_shift_door()` 只挪门，**落点一寸不动**；
- 新增断言 **A25**：落点必须落在某一间子图房间的 `get_dimensions()` 平面范围内
  （高度容差 1.5m），用几何判据，不看碰撞、不看 Area3D；
- 新探针 `tests/verification/probe_secret_branch_landing.gd`：真实流程破板 → 按 E →
  打印落点、落点与每间房的距离、落点 40m 内可视件数。

修前 / 修后（种子 `1122239949`，真实流程）：

| | 修前 | 修后 |
|---|---|---|
| 落点 | `(1020.0, 0.0, 39.135)` | `(1015.0, 0.0, 0.0)` |
| 距首间中心 | 39.5m（房外） | 0.0m（房内正中） |
| `on_floor` | **false**（下坠 `velocity.y=-0.41`） | true（`velocity=0`） |
| 落点 40m 内可视件 | 785 | 1789（全场景 25656） |

**反向对照**：把「落点 += delta」那行临时加回去，真实流程立刻复现
`落点=(1020.0,0.0,39.135)`、`on_floor=false`、距首间 39.5m —— 与业主看到的现象逐项一致；
按 A25 的几何判据，`dz=39.1 > 半深 20` ⇒ 判为「不在任何子图房间」，会报红。

⚠️ **注意验收套件的盲区**：`verify_secret_branch_flow` 跑在 `test_mode` 下，房间在
`_collect_sites()` 之前就建好了，`_read_authored_doors()` 一次就读到 → `delta = 0` →
**套件复现不出这个时序**（反向对照在套件里仍是绿的）。这个 bug 只在真实 bootstrap
（先建门、后建房间）里出现。所以真实流程的探针是这条的唯一有效对照，别只看套件绿。

## 8. 没做的事

- **没让门洞开在墙上**：这轮只解决「摆与看得见」，破板后背后仍是实墙。
- **S2/S4 凸出量是估计值**：墙件认不出（见 §3.4）。
- **其他关卡没有门节点**：只有远征 01 的 4 间写了 `secret_site` 的房间有；
  别的关卡仍走「数据位点 + 自动外推」，不受影响。
