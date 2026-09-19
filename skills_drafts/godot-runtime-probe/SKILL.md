---
name: godot-runtime-probe
description: 用 Godot headless 探针实测「游戏运行时实际装配成什么」——节点树、Transform、局部/世界坐标、尺寸、碰撞套数、Godot 分组。当问题涉及"游戏内实际用的标准 / 运行时基准坐标 / 组件几个 / 是否打组 / 换资产会不会错位"，且必须排除 Blender 源文件与设计文档口径时使用。不用于制作或导出资产。
agent_created: true
---

# Godot 运行时探针

## 何时用

问的是**运行时事实**，不是资产源文件、也不是设计文档里的口径：

- "游戏内的标准是哪套？"
- "这个房间里的门有几个组件？有没有打组？"
- "换资产能不能定位到基准坐标？"
- "碰撞是谁生成的？尺寸多少？"

**铁律：主人说"看游戏内的"时，禁止用 Blender headless 或读 `.blend` / `.glb` 源文件作答。** 一律跑 Godot headless 探针。

## 环境（本机）

- Godot：`I:\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64.exe`（注意 `...exe\` 是目录名）
- 项目：`I:\工作项目\shellstrom2\ShellStorm2`
- Python（后处理/删文件）：`C:\Users\zhuangmenghong\.workbuddy\binaries\python\versions\3.13.12\python.exe`

### Bash 工具缺陷（必踩，先避开）

PortableGit shim 缺 coreutils：`dirname` / `cd` / `head` / `tail` / `wc` / `ls` / `rm` 全部 `command not found`。

**绝对不要用管道**：`... | tail -n 200` 会 `Exit 127`，什么都拿不到。

正确做法 —— 重定向到文件，再用 Read / Grep 读：

```bash
"<godot>" --headless --path "<project>" res://tests/verification/<probe>.tscn > "<out>.txt" 2>&1; echo "exit=$?"
```

stderr 里的 `dirname: command not found` / `cd: null directory` 是 shim 噪音，**可忽略**，看 `exit=` 和输出文件即可。删临时文件用 Python，不要用 `rm`。

## 探针模板

两个文件，放 `tests/verification/`：

`<probe>.gd`
```gdscript
extends Node

const TARGET_ROOM := "floor_01_entry"

func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await _settle()
	tower.force_enter_room_for_test(TARGET_ROOM)
	await _settle()
	var room := (tower.get("_room_by_id") as Dictionary).get(TARGET_ROOM) as DungeonRoom3D
	room.ensure_shell_built()
	await _settle()
	_dump(room, 0)
	get_tree().quit(0)

func _settle() -> void:
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout
```

`<probe>.tscn`
```
[gd_scene format=3]

[ext_resource type="Script" path="res://tests/verification/<probe>.gd" id="1_probe"]

[node name="Probe" type="Node"]
script = ExtResource("1_probe")
```

### 已验证可用的入口 API

| API | 作用 |
|---|---|
| `tower.test_mode = true` | 关掉真实开局流程 |
| `tower.run_seed_override = 990095` | 固定随机种子，结果可复现 |
| `tower.force_enter_room_for_test(room_id)` | 强制构建指定房间的壳体 |
| `room.ensure_shell_built()` | 补一次壳体构建 |
| `tower.get("_room_by_id")` | 拿房间字典（GDScript 私有成员靠 `get()` 访问） |

### dump 必须打印的字段

- `position` / `rotation.y` / `global_position` / `global_rotation.y`
- 所有 `get_meta(...)`
- `MeshInstance3D` 的 `BoxMesh.size`、`CollisionShape3D` 的 `BoxShape3D.size`、`StaticBody3D` 的 `collision_layer/mask`
- 递归父链 `get_parent().name` —— 用来判断"父子"还是"兄弟"
- `get_groups()` 全树扫描 —— 回答"有没有打组"

### 局部 AABB 配方（判断原点契约）

```gdscript
func _local_mesh_aabb(root: Node) -> AABB:
	var acc := AABB()
	var found := false
	for value in root.find_children("*", "MeshInstance3D", true, false):
		var mi := value as MeshInstance3D
		if mi.mesh == null: continue
		var b := mi.transform * mi.mesh.get_aabb()
		acc = b if not found else acc.merge(b)
		found = true
	return acc
```

`pos=(-2.5, 0, -0.15) ~ end=(2.5, 11.9, 0.15)` 这样的结果直接给出原点定义，比读 `.tscn` 注释可靠。

## 判读要点

1. **先看房间自身锚点**：`global_position` / `rotation.y`，所有子节点坐标都相对它。
2. **局部与世界都要给**：结论里两个都给，主人要的是能落到场景里的世界坐标。
3. **父子 vs 兄弟**：`get_parent().name` 决定"是不是墙带的门"这类判断，别靠命名猜。
4. **碰撞要数几套**：prefab 自带的 + 代码现场生成的 + camera-only 代理，常常同时存在三套。
5. **别信自己上一轮的结论**：`meta` 值、槽位 index 这类要实测复算 —— 本 skill 的诞生就是因为上一轮把门槽位置记反了 2.5m，靠重跑探针才发现。

## 实例化方式三分类（"是 prefab 引用还是代码生成"必查）

问"这个资产是 prefab 引用还是程序生成的"时，**答案常常是第三种**。必须查实例化代码：

| 方式 | 判别标志 | 运行时节点形态 |
|---|---|---|
| **prefab 逐实例** | `PREFAB.instantiate()` 后 `add_child` | 每个实例一个独立节点 |
| **prefab 取 mesh + 批量** | `instantiate()` → `_find_first_mesh()` → `source.free()` → `MultiMesh.mesh = mesh` | 1 个 `MultiMeshInstance3D` 承载 N 个 |
| **纯程序化** | 现场 `BoxMesh.new()` / `shape.size = ...` | 无对应资产文件 |

**关键陷阱（已实测）**：`_find_first_mesh()` 只返回**第一个** `MeshInstance3D` 的 mesh（`DungeonRoom3D.gd:1032-1039`），且 `source.free()` 丢掉实例。所以走 MultiMesh 路径的资产（塔楼实墙、地板），**prefab 里多个 MeshInstance / 多材质只会保留第一个，其余静默丢弃**。换这类 prefab 前必须先确认它是单 mesh 单材质，否则外观会缺件且不报错。

**第二条关键陷阱：prefab 文件里有碰撞 ≠ 运行时用了那个碰撞。** 走 MultiMesh 路径时 prefab 从未被实例化，其 `StaticBody3D` / `CollisionShape3D` **完全不进场景**，碰撞由代码另建。所以回答"这资产的碰撞是哪来的"，**不能只看 prefab 文件**，必须同时查实例化代码。两者经常不一致：

| 资产 | prefab 内声明 | 运行时真正生效 |
|---|---|---|
| 通用实墙 | 1 mesh + 1 碰撞 | mesh 来自 prefab；**碰撞由代码建**（prefab 碰撞被丢） |
| 地板 | 1 mesh + 1 碰撞 | mesh 来自 prefab；**碰撞由代码建**（prefab 碰撞被丢） |
| L 型转角 | 2 mesh + 2 碰撞 | **prefab 原样实例化，自带碰撞生效** |
| 带门墙 | 3 mesh + 1 碰撞(3 shape) | **双份，但分居两处**：模块子树内是 prefab 自带那一套（实测 3 CS / 1 SB）；**代码另建的一套挂在房间根**，不在模块下。只 dump 模块子树会误判成"单套" |
| 门扇 | **空壳**（仅 StaticBody3D + 脚本） | **模型与碰撞全部由代码生成** |

本项目现状（战局区块 / 98 层，非 FACILITY）：
- 通用实墙 `prp_tower_wall_solid_5m_v001.tscn` → **prefab 抽 mesh + MultiMesh**（A/B 交替两个 MultiMesh）
- 地板 `prp_tower_floor_tile_5m_v001.tscn` → **prefab 抽 mesh + MultiMesh**（6×6=36 实例）
- L 型转角 `prp_corner_l_5m_v001.tscn` → **prefab 逐实例**（每角 1 节点 `Imported_CornerL5M_<ID>`）
- 门墙 `prp_tower_wall_door_5m_v001.tscn` → **prefab 逐实例**（`Imported_DoorWall5M_<Dir>_I<NN>`）
- 门扇 `prp_room_door_3d_v001.tscn` → **空壳 prefab + 纯代码生成**（`RoomDoor3D._build_procedural_panel()`）

### 回答"换资产该学哪种做法"的判断规则

- 数量大、可共享同一 mesh → MultiMesh 路径（但替换不友好：单 mesh 单材质限制）
- 要精细、要逐件不同、要好替换 → **逐实例化 prefab**（转角/门墙范式）。这是推荐做法。
- 无论走哪种，新 prefab 必须满足原点契约，并**加 AABB 断言**堵住静默错位。

## 探深层前必须先 commit 楼层（必踩）

`TowerDescent3D` 的楼层**懒加载**：初始 `_floor_room_ids` 只有 `[0, 1, 2]`，即只有 100F / 99F / 98F 有场景壳体；**更深的层连房间计划节点都不存在**。直接探 97/96/95 会得到 `stage: MISSING` + `rooms count=0`，很容易误判成"这几层没做"。

正确做法：按抵达闸门逐层提交后再 dump。

```gdscript
for fi in [2, 3, 4, 5]:
    print("COMMIT floor_index=%d -> %s" % [fi, str(tower.call("_commit_floor_bundle", fi, "probe"))])
    await _settle()
# 提交后 _floor_room_ids.keys() == [0,1,2,3,4,5,6]
```

层号换算：`floor_number = 100 - floor_index`。战斗层是 `COMBAT_FLOOR_COUNT = 4` → floor_index 2..5 → **98F / 97F / 96F / 95F**。
`_commit_floor_bundle` 会连带创建下一层的入口壳，所以按升序提交即可，不用单独处理。

## 三个易误判点（实测确认）

1. **地砖不同源**：98F 用 `env_tower_floor_tile_5m_top3d_v002.glb`（精装 GLB，`material_override` 为空）；97/96/95F 用 `prp_tower_floor_tile_5m_v001.tscn` 抽出的 **BoxMesh** + `material_override` 材质。**看 `material_override` 是否为 null 就能一眼分辨**，只看实例数（都是 1241×2）分辨不出来。
2. **实墙段/外墙抽出来的是程序化 `BoxMesh`，不是美术 GLB**：`prp_tower_wall_solid_5m_v001.tscn::BoxMesh_wall_solid_5m`。外观完全靠 `.tres` 材质，不要在探针报告里写成"美术网格"。
3. **stage 节点名不可信，层号只认 meta**：`_rebuild_floor_stage()` 先 `queue_free()` 旧 stage（延迟释放，旧节点仍在树上）再 `add_child()` 新 stage 并设名 `Floor_%(100-floor_index)`，新旧重名触发 Godot 尾号自增 → 节点名整体比层号大 1（98F 的节点名叫 `Floor_99`）。一律用 `meta floor_number` 判断层号。

### 第三条关键陷阱：`material_override` 会盖掉资产自身材质

抽 mesh 的 MultiMesh 路径常常额外套一层 `material_override`（`.tres`）。此时**换 GLB 不会改外观**，因为资产材质被覆盖了，看起来"改了没生效"，很容易误判成替换失败或没引用到。

判据：探针里 dump 每个 `MultiMeshInstance3D` 的 `material_override != null`。
- `material_override == null` → 用资产自带材质，换资产生效（例：98F 精装地砖、塔楼外墙）
- `material_override != null` → 资产材质被盖，换资产只换形状不换颜色（例：房间实墙段、97/96/95F 地砖）

### 第四条关键陷阱：同一种组件可能有**多个** prefab 常量

不要假设"改一个 prefab 就能全局替换"。实测：地砖有**两套**——98F 用 `env_tower_floor_tile_5m_top3d_v002.glb`，97/96/95F 用 `prp_tower_floor_tile_5m_v001.tscn`。改一个只影响一部分楼层，且两者外观差异要看 `material_override` 才能分辨。

排查方法：grep 所有候选常量名，逐个确认运行时实际取的是哪个分支（`_build_floor()` 里 `floor_index in [0, 2]` 这类条件常决定分支）。

### 回答"能只改资产替换吗"的判据

| 实例化方式 | 只改资产能换外观吗 | 碰撞会跟着变吗 |
|---|---|---|
| 逐实例化 prefab | ✅ 能 | ✅ prefab 自带碰撞生效（除非代码另建了一套） |
| 抽 mesh + MultiMesh | ⚠️ 仅在无 `material_override` 且单 mesh 时 | ❌ 碰撞由代码按常量建，与资产无关 |
| 纯程序化 | ❌ 根本没有资产可改 | ❌ 全部代码生成 |

通用结论：**尺寸、位置、碰撞由代码常量决定，不由资产决定。** 改资产只可能换外观。若新资产原点契约或尺寸与老的差一点，会静默错位——必须加 AABB 断言，不能靠肉眼验收。

### 第五条关键陷阱：`--headless` 下 `MultiMesh.instance_transform` 回读**不可信**

无头模式的假渲染器**不填充 MultiMesh 的实例缓冲**：`multimesh.get_instance_transform(i)` 对**所有**实例都返回 `origin=(0,0,0)`、`scale=(1,1,1)`。

实测反例：把 200 个外墙实例与 2500 块地砖全部读出来，每一块都是「原点零、缩放一」——**连必然有位置的楼板都是零**。显然不可能，属回读假象，不是真实装配结果。

**判断「缩放 / 位置对不对」只能靠：**

1. 读代码——`Basis.scaled()` 的语义本身是可靠的（`Basis.IDENTITY.scaled(Vector3(1,0.5,1))` 确实得到 Y=0.5），错的是回读；
2. 让被测代码把真实值**回填进 `get_snapshot()` 字段**再断言（例：`TowerFloorStage3D` 把外墙实际纵向缩放写进 `outer_visual_scale_y`，门禁从此有据可依）；
3. 或改跑**非 headless**（`visual/renderer` 类场景）。

> ⚠️ 别用回读值下「资产没缩放 / 没定位」的结论——会得到一个看起来精确、实际纯属虚构的判据，并据此改错代码。

### 第六条关键陷阱：动态实体挂在**专门的容器节点**下，不在业务对象子树里

敌人不是房间的子节点。`_spawn_enemy_batch()` 里写的是 `$ActiveEnemies.add_child(enemy)` —— 全场敌人挂在关卡根同级的一个 `ActiveEnemies` 容器下，只用 `room_id` 字段标明归属。

**踩法**：在房里 `room.find_children("*", "Enemy3D", true, false).size()` 得到 `0`，于是误判「没刷怪」。实测该房 `_alive_by_room[room_id]` 明明是 3。

**正确查法**：查容器节点本身（`tower.get_node_or_null("ActiveEnemies")` + `find_children`），或查运行时的归属表 `_enemy_nodes_by_room[room_id]`。

> 通用教训：节点树的「容器维度」与玩法的「归属维度」经常不是同一个。探针要找实体，先看生成代码里的 `add_child()` 目标，而不是猜它挂在哪个业务对象下。

### 第七条关键陷阱：状态标记 ≠ 玩家位置，房内实体会被 hibernate 释放

房间的流送状态是**按玩家实际所在位置**算的。只改标记（`_current_room_id = id`）或只调测试后门（`force_enter_room_for_test(id)`）而**不挪玩家**，房间会被判为离开 → 进 hibernate → `_hibernate_room_entities()` 当场 `queue_free()` 掉该房全部敌人。

**结果是最迷惑的一种**：`_alive_by_room[room_id]` 还留着生成时的首波数（释放时不回写），敌节点数却是 `0`。看着像「刷了怪但立刻消失」。

**修法**：探针在触发刷怪前先把玩家真放进房间正中央——

```gdscript
tower.force_enter_room_for_test(room_id)
tower.player.global_position = room.global_position + Vector3(0.0, 0.05, 0.0)
tower._on_room_entered(room)
```

顺带：多波次战斗房的 `_alive_by_room` 是**首波**存活数，不是该房敌人总数；待发波次在 `_room_wave_queues`，当前波号在 `_room_wave_numbers` / `_room_wave_totals`。只报 `_alive_by_room` 会把「3 只」说成全部。

### 第八条关键陷阱：`*_for_test` 后门会**污染**你要测的判定

为了进房方便而在探针开头把所有边 `force_open_edge_for_test()` 全开，会直接毁掉后面「未清房不能开门」那一段——`_try_open_room_door()` 对**已开启的边**第一条分支就是 `return true`（状态文案「通道已经开启」），于是「未清房」测出 `true` 的假阳性，而 `*_OK` 打印照样好看。

**规矩**：后门只在被测机制**确实需要**时开，且在进入该段之前把状态清回去；同一探针里「开边」与「验门禁判定」互斥。

### 附：类型化字段不是 Dictionary，别用 `get(k, default)` 摸字段

`Array[FateCard]` 的元素是 RefCounted 对象（不是 `Dictionary`）。写 `choice.get("label", choice)` 会同时炸两条 parse error：`Expression is of type "FateCard" so it can't be of type "Dictionary"` 与 `Too many arguments for "get()" call`（对象上的 `get()` 只收 1 参）。读字段用属性（`card.card_name`）。

同理，`var x := <Node>.get("prop")` 会因 Variant 推断而触发「warning treated as error」——**探针里尽量直接属性访问**（`tower._map_fate_triggers`），需要按名取时显式标注类型。

## 已知噪音（不影响结论）

- 大量 `invalid UID: 'uid://...' - using text path instead` WARNING：base99 / tower 色盘 UID 既有问题，与探针无关。
- `core/io/resource_format_binary.cpp` 的 open 报错：GLB 导入缓存问题，探针仍正常输出。
