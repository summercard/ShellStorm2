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

> ⚠️ **headless 只对「结构 / 数值 / 坐标」类结论有效。** 一切与**输入派发**有关的结论（焦点有没有建立、按键有没有触发按钮、方向键有没有挪焦点）**都不能用 headless 下结论** —— 见文末「第十一条关键陷阱」。焦点锚点可以 headless 断言，但「按下去有没有反应」必须带窗口跑。

## 环境（本机）

- Godot：`I:\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe`（注意 `...exe\` 是目录名；**必须用 `_console.exe` 那个** —— 非 console 版在 Windows 下不挂 stdout，`> out.txt` 会拿到空文件，容易误判成「探针没跑」）
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

通用结论：**尺寸、位置由代码常量决定，不由资产决定**；**碰撞归谁所有则随承载路径而变**（见下条）——别一概而论。改资产主要换外观。若新资产原点契约或尺寸与老的差一点，会静默错位——必须加 AABB 断言，不能靠肉眼验收。

### 换资产前必查第三条：碰撞归属（`collision_owner` / `visual_only`）＋ 承载路径有没有兜底（2026-09-25 实测）

「改一行 prefab 路径就换掉外观」这个想法有一个**静默致命**的前提：**新资产的碰撞归属必须与承载路径的兜底机制匹配**。两件事分开查，缺一不可。

**① 看两件 prefab 的 meta，不看目录名、不看家族名：**

| meta | 含义 | 换过去会发生什么 |
|---|---|---|
| `collision_owner = "self"`（包内自带 StaticBody3D） | 挡人靠 prefab 自己 | 承载路径**不**代生成代理时才安全 |
| `visual_only = true` / `collision_owner = "<脚本名>"`（包内 **0** 碰撞） | 挡人靠某条代码路径按常量生成代理 | 承载路径**必须**有那条代理生成代码，否则**整片区域直接没有挡人碰撞** |

**② 再查承载路径有没有调用代理生成器 —— 这一步最容易漏。**

实测案例：`DungeonRoom3D` 有两条装配路径 ——
- **程序化路径**（`_build_tower_wall_run()`）会调 `_add_tower_wall_collision()` / `_add_tower_solid_run_collision()` 补 0.30m 代理；
- **授权布局路径**（`_build_authored_layout_shell()`，读摆位源实例清单的那条）**一次都没调用这两个函数**。

于是同一个 `ENV-TOWER-WALL-SOLID-5M`（`visual_only=true`）：走程序化路径有代理、正常；若把走授权布局的那批墙换成它，**12 个房间的墙体全部失去挡人碰撞、玩家可穿墙出界**，而**编辑器与几何校验都不会报错**。

排查手法（三条，都是只读）：

```bash
# 1) 代理生成器到底被谁调用（别只看定义存在）
grep -n "_add_tower_wall_collision\|_add_tower_solid_run_collision\|TowerWallCollision" src/world3d/DungeonRoom3D.gd
#    → 若全部调用点都在你不关心的那条路径里，就是「这条路径没兜底」

# 2) 写个 headless 探针逐件清点：按 prefab 根 meta 归组，数 collision_layer==1 的实体
#    输出「实体碰撞体合计」+「按 asset_id 汇总」+「全房 layer=1 总数 vs 墙件归属数」三张表
#    判据：body.collision_layer == <物理墙层> 才算实体；其余层（camera-only 等）不算挡人

# 3) 换前三方对齐：battle 件贡献的挡人碰撞数 = 换后必须 ≥ 的底线
```

**③ 家族标签不可信，逐件看 meta。** 实测反例：`ENV-TOWER-CORNER-L-5M` 同属「tower A 套」，却**自带**两个 StaticBody3D（`visual_only=false`，且节点名是镜头下压契约），而同套的直墙/门墙六件里五件 `visual_only=true`。**同一套美术家族里碰撞归属并不统一**——按家族批量判断会直接踩雷。

**④ 顺带记一条连带面：换组件往往要连「门墙 / 坑壁 / 支线件」一起切。** 案例里直墙的 `component_id` 还被 `FloorPlanGenerator._pit_wall_instance()` 复用给桥房下沉坑壁（靠 `module.scale.y` 纵向拉伸），换之前得先验新件能不能吃非等比纵向缩放（纹路会不会拉变形）。

### 第五条关键陷阱：`--headless` 下 `MultiMesh.instance_transform` 回读**不可信**

无头模式的假渲染器**不填充 MultiMesh 的实例缓冲**：`multimesh.get_instance_transform(i)` 对**所有**实例都返回 `origin=(0,0,0)`、`scale=(1,1,1)`。

实测反例：把 200 个外墙实例与 2500 块地砖全部读出来，每一块都是「原点零、缩放一」——**连必然有位置的楼板都是零**。显然不可能，属回读假象，不是真实装配结果。

**判断「缩放 / 位置对不对」只能靠：**

1. 读代码——`Basis.scaled()` 的语义本身是可靠的（`Basis.IDENTITY.scaled(Vector3(1,0.5,1))` 确实得到 Y=0.5），错的是回读；
2. 让被测代码把真实值**回填进 `get_snapshot()` 字段**再断言（例：`TowerFloorStage3D` 把外墙实际纵向缩放写进 `outer_visual_scale_y`，门禁从此有据可依）；
3. 或**把同一条命令的 `--headless` 直接去掉**，跑真渲染器（2026-09-19 实测有效，见下）。

**已有探针想拿真实实例位置时，优先用第 3 条**——不用改代码，把 `--headless` 删掉即可，实例变换立刻回读正常：

```bash
# ❌ 实例全变单位阵
"<godot-console>" --headless --path "<project>" --scene res://tests/verification/<probe>.tscn
# ✅ 回读正常；会短暂弹一个窗口，跑完自己退
"<godot-console>" --path "<project>" --scene res://tests/verification/<probe>.tscn
```

实测对照（`probe_rooftop_parapet_alignment`，同一份代码同一天）：headless 下 61 个直段实例**全部** `origin=(0,0,0)`，四条边一律误报「缺 80m 以上」；去掉 `--headless` 后同一批实例给出 `origin=(-45,0,-34.75)` 等真实值，四条边 `gap=0.000 / overlap=0.000`。
→ **headless 跑出的「大面积缺失 / 数量对不上」先怀疑这条回读限制，别急着改装配代码**；反过来，带窗口跑出来的覆盖/接缝结论才可作为验收证据。

> 探针自己写判据时另有一条：量「贴某条边界」的成员，必须用**垂直于该边**的轴判跨界。南北边（boundary 是 Z）看 Z，东西边（boundary 是 X）看 X；一律拿 Z 判会让竖边恒报「一个模块都没有」。

> ⚠️ 别用回读值下「资产没缩放 / 没定位」的结论——会得到一个看起来精确、实际纯属虚构的判据，并据此改错代码。

### 附：真渲染「出图探针」的三条纪律（2026-09-22）

当探针的目的不是回读数值，而是**出一张能给人判读的图**（外观 / 姿态 / 散布 / 贴地），除了上面「把 `--headless` 去掉」，还有三条：

1. **机位距离要按「目标占多少像素」反推，不能按「把场景装进画面」拍。**
   实测：弹壳长 `0.15 m`，相机放在落点上空 `2.6 m` / 后 `1.4 m`（fov 50、1280×720）时弹壳只有 `30px` 量级 —— 而「随机化到底生效没有」这种判读**全靠这张图**，机位太远等于白拍。拉近到 `1.8 m / 1.1 m`（镜头距 ≈ `2.1 m`）后约占 `55px`、姿态可辨，同时被测对象的散布（8 发落点最大间距实测 `0.45 ~ 1.15 m`）仍完整入画。
   ⇒ 定机位前先估：`投影像素 ≈ 目标尺寸 / 镜头距离 × (画高/2) / tan(fov/2)`，确认目标占 **≥ 40~50px** 再拍。
2. **必须留一条「取景判据」。** `Camera3D.unproject_position()` 对**屏幕外**的点照样返回数值 ⇒ 「投影比 / 尺寸比」这类断言能在画面里**什么都没有**的情况下通过（本仓已踩过两次：出图是空图、比值却「通过」）。
   ⇒ 断言每个目标的投影点落在视口的 `[0.05, 0.95]` 区间内；再加一条**画面亮度分层 ≥ N** 的防假绿（纯色空图只有 1 层）。
3. **俯视机位不能正上方 90°。** `look_at()` 的 up 向量与视线平行会直接报错；且垂直俯视下躺平的物件只剩一个圆点，姿态全被压掉。取 55°~65° 俯角（略微后上方）兼得「看得出贴地」与「看得出姿态」。

> 配套一条：手动步进模拟的探针，`_advance()` 推完必须把 `process_mode = Node.PROCESS_MODE_DISABLED` 冻结 —— 否则随后的 `await` 会让引擎继续替它跑，几个「不同时刻」的样本会全跑成同一状态（本仓实测：四个阶段里「下落中」那枚早已落地静止）。

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

## 第九条关键陷阱：读「姿态」时轴与欧拉序都会跟你想象的不一样（2026-09-21 实测）

判「件朝向对不对 / 有没有倾倒 / 落地没有」时，有三处会得到看起来精确、实际反了的结论：

1. **glTF Y-up 轴映射**：Blender 局部 **+Z** 经 glTF 导入 Godot 后是局部 **+Y**。
   - 例：天台墙挂空调的**出风风扇**在 Blender 局部 +Z ⇒ Godot 里判「风扇朝外」必须读 **`basis.y`**。原来读 `basis.z` 会**恒判「没朝外」**（假红报 `fan axis=(0,-1,0)`），而 Blender 侧独立探针同时证明几何是对的 ⇒ 是**判据错**。
   - 同一条：Godot 局部 **+Z** 是「原本朝下的那一面」（例：空调的进风格栅）。
2. **欧拉序不同**：Blender 默认 **XYZ** 序（矩阵 = `Rz@Rx@Ry`）、Godot 默认 **YXZ** 序（矩阵 = `Ry@Rx@Rz`）。布局源若同时给 `rotation_y` 与 `rotation_z`，两引擎的 Rx/Rz 次序就**不一致**，角度不能逐值搬运。
   - 本项目已定契约：布局源只用 `rotation_x_deg` + `rotation_y_deg`（`rz` 恒 0）⇒ `Rz@Rx` ≡ `Ry@Rx`，可 1:1 透传。
   - **别推公式，取真值矩阵**：Blender `Euler((rx,0,rz)).to_matrix()` / Godot `Basis.from_euler(Vector3(rx,ry,0), EULER_ORDER_YXZ)`，取局部轴列向量比对。
3. **「倒装件」的原点不在底面**：`rotation_x_deg=180` 的件（例：立管下段倒装）原点落在**上端**，`position.y` 读出来是「原点那截」的高度，**用它判落地会得到相反结论**。
   - 正确判法：按**实测可视包络** —— 遍历 `VisualInstance3D`，取 `global_transform * get_aabb().get_endpoint(i)`（i=0..7）求并集，看最低点。例：立管两段（下段倒装、两段 `h` 都写件高 4.945）并集应连成 `0 ~ 9.890m`、最低点 y=0。
   - ⚠️ 组件包络**不要读 `instance.location`**（那是摆放点）。Blender 侧同理：只认 `depsgraph.object_instances` 的 `io.matrix_world`。

> 通用教训：**「姿态」类判据先问「这个轴/这个分量的语义，在目标引擎里是什么」**，再写断言。判据本身错了，会稳定地报出一个假红（或假绿），比没有判据更有害。

## 第十条关键陷阱：读 `.tscn` 文本里的摆位（覆盖 vs 叠加 / 行主序 / 自嵌套）（2026-09-21 实测）

问「这个件在运行时被摆在哪 / 换个资产会不会错位」时，源侧 `.tscn` 有三个会**稳定读错**的地方：

1. **`Transform3D` 的 12 个数是行主序**：`(m00,m01,m02, m10,m11,m12, m20,m21,m22, ox,oy,oz)`。
   绕 Y 的偏航角 = `atan2(m02, m00)`。
   - 反证：`rotation_degrees.y = +90` 的 `basis.x` 是 `(0,0,-1)`，行主序首三位正是 `(0,0,1)`；
     按列主序会读成 `-90°`。
2. **父场景节点上的 `transform` 对实例根是「覆盖」，不是「叠加」**（这是判错位的头号来源）：
   - 普通包（`*_root_top3d.tscn`）：预制体根在原点保持 identity ⇒ **覆盖值就是纯位移量**。
   - facility 包装包（`*_facility_top3d.tscn`）：预制体根 `Area3D` **自带 pivot**（= 件心绝对坐标），
     子节点 `SourcePackage` 用 `−pivot` 抵消 ⇒ **覆盖值是新的绝对 pivot，实际位移 = 覆盖值 − 原 pivot**。
   - 反证：武器工作台原 pivot `z=3.4`、覆盖为 `5.3589`，探针实测几何中心 `z=5.3589`；若为叠加应是 `8.7589`。
   - ⚠️ 派生后果：**「覆盖值 == 原 pivot」的空操作覆盖**位移为 0、画面不变，但父场景从此**硬覆盖**该 pivot
     —— 以后改包装包预制体的 pivot 不会再传导到这一件。统计「这版动了哪些」时必须把它单列，不能算位移。
3. **自嵌套同名子节点会被顶层遍历整片漏掉**：`[node parent="X/X" name="X"]` 这种名字与祖先同名的结构，
   按 `parent == "."` 或只扫直接子节点都看不见它。全项目 257 个 `.tscn` 只有 1 个文件有 ⇒ 是编辑产物，
   不靠通用规则兜。判据：递归比较节点名与**任一祖先名**；同时报 `mesh_count` 与各份自己的件心。
4. **包络口径必须先问清是哪个空间、含不含后代**：同一份代码里
   - 顶层节点上求 AABB ⇒ 得到 **union**（把更深的自嵌套份并进去，5 个水缸会被并成 6 个那么宽）；
   - 子节点上求 AABB ⇒ 得到**父局部空间**的值，不是世界系。
   - 正确做法：单独写一个「从 scene_root 起链乘（含目标节点自身）」的求 AABB 函数，结果直接落在世界空间。
   - ⚠️ **脱离场景树时 `Node3D.global_transform` 不级联父链** —— 必须自己手工累乘。
5. **另一条真源：几何件心，不是节点原点**。部分包的 GLB 顶点**直接烘了绝对坐标**，
   节点原点与几何位置能差十几米（水箱 / 蓄电池都是这样）⇒ 报摆位一律给「实测件心」，节点原点只当参考。

### 坐标换算（Godot 平面 ←→ Blender 平面）

```text
Godot  (gx, gy, gz)  ←  Blender (bx, bz, -by)
Blender(bx, by, bz)  ←  Godot   (gx, -gz, gy)
Godot 绕 +Y 偏航角   ≡  Blender 绕 +Z 的同值欧拉角   （仅「只有偏航、无缩放」时成立）
```

⚠️ 只写 XZ 平面、漏掉 `by = −gz` 的那一步，会让整份布局**南北镜像 + 整体偏移**（本项目天台装饰案就是这么错的：
北侧溢出边界、南侧缺一段）。布局类脚本必须自带「换算后落点在目标矩形内」的断言。

### 探针纪律：场景正被编辑器打开时**不要**跑

Godot 编辑器打开某场景时，`.godot/editor/` 会写 `-editstate-*.cfg` / `-folding-*.cfg`；
headless 探针与编辑器**共享 `.godot/`**，于是：

- 源文件可能在探针运行的**同一秒**被重存 ⇒ 你钉的 sha 当场失效、结论与文件对不上；
- 判「是不是我改的」会被编辑器的写入污染（实测：会话内源文件被写入 5 次，`-editstate-*.cfg` 同秒落盘）。

**规矩**：让主人先停编辑 → 钉 sha → 回读确认 sha 未变 → 再出正式记录。
任何摆位记录必须显式写明「这是快照，不是活引用；文件再存一次即失效」。

## 第十一条关键陷阱：`--headless` 下 **GUI 输入派发不工作**（2026-09-22 实测）

与第五条的 `MultiMesh` 回读是同一类问题，但更隐蔽 —— 它**只污染「输入类」结论**，
而且会让你误判成「我的 UI 接线写错了」。

- headless 下 `Control.grab_focus()` **有效**：`get_viewport().gui_get_focus_owner()` 正常返回被聚焦的控件。
  ⇒ 「**焦点锚点**」（菜单打开后有没有焦点持有者、焦点落在哪个控件）**可以 headless 断言，这条可信**。
- 但 headless 下**合成输入事件永远走不到控件的 `pressed`**（GUI 输入派发循环不被驱动）。
  实测六种注入方式全部无效：`Input.parse_input_event()` + `Input.flush_buffered_events()`、
  `Viewport.push_input()`、`InputEventAction("ui_accept")`、`InputEventJoypadButton(JOY_BUTTON_A)`、
  物理回车 key —— 同一份代码**去掉 `--headless`** 后全部命中。

**规矩**：

| 要验的东西 | 怎么验 |
|---|---|
| 焦点锚点（有没有焦点持有者、在哪个控件） | headless 跑 + **反向对照**（把 `grab_focus()` 停掉，断言必须变红） |
| 确认键是否触发按钮 / 方向键是否挪焦点 | **必须带窗口跑**（去掉 `--headless`），别在 headless 里追，追不出来 |

反向对照的开关写法很好用：把 `grab_focus()` 那一行换成注释、备份原文件，
红一次 / 绿一次，就能证明断言真的会失败，而不是「本来就没跑到」。

### 附：`ui_accept` / `ui_cancel` 绑的是 `physical_keycode`，导航键绑 `keycode`

`project.godot` 的 `[input]` 段里两套键位用的是**不同字段**：
`ui_up/down/left/right` → **`keycode`**；`ui_accept` / `ui_cancel` → **`physical_keycode`**。
所以合成 `InputEventKey` **要按目标 action 选字段**，不是「两个都填更保险」——
实测两个字段同时填时 `is_action("ui_up") == false`（`physical` 那一半不匹配 `keycode` 绑定）。

实测对照（裸 `Control + Button`，`focus_mode = FOCUS_ALL` 且已 `grab_focus()`）：

| 注入方式 | `pressed` 命中 |
|---|---|
| `InputEventAction("ui_accept")` | 1 |
| `InputEventKey(physical_keycode = KEY_ENTER)` | 1 |
| `InputEventKey(keycode = KEY_ENTER)` | **0** |
| `InputEventJoypadButton(JOY_BUTTON_A)` | 1 |
| `Viewport.push_input(物理 Enter)` | 1 |
| `Viewport.push_input(InputEventAction("ui_accept"))` | 1 |

⇒ 引擎机制本身没问题。**GUI 类问题先查「有没有焦点持有者」，再查事件形状**，
最后才怀疑自己的接线 —— 顺序反了会白查半天。

## 已知噪音（不影响结论）

- 大量 `invalid UID: 'uid://...' - using text path instead` WARNING：base99 / tower 色盘 UID 既有问题，与探针无关。
- `core/io/resource_format_binary.cpp` 的 open 报错：GLB 导入缓存问题，探针仍正常输出。
