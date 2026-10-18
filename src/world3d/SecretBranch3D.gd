extends Node3D
class_name SecretBranch3D

## 远征关卡传送支线管理器（设计：docs/v0.1/design/支线秘密房间设计.md）。
##
## 职责边界（刻意的）：
##   · **只**负责位点解析、板体装配、**按 E 触发的传送**、子图真房型、撤离门、
##     以及「玩家踏进子图房间」这一件事的上报。
##   · 刷怪**不在这里实现**：子图的编成由 `MonsterInjector.build_secret_branch_encounter`
##     出，实例化/掉落/击杀账走 `Dungeon3D` 既有那条链（`_spawn_enemy_batch`）。
##     本节点只把「玩家进了哪一间」告诉上层（`_room_enter_handler`），
##     由 `Dungeon3D` 决定刷什么、什么时候刷 —— 子图不另立一套战斗系统。
##   · **不**把子图房间写进 `_records`、不写进全层地图、不参与流送与拓扑校验。
##     子图是一个孤立的 Node3D 分支，挂在主图外 1000 m。
##
## 为什么独立成节点而不是塞进 Dungeon3D：
##   Dungeon3D 已 470 KB，且房间装配/流送/存档三条链都极其敏感。支线是一块
##   与主链正交的内容，独立节点让「删掉它」等于「删掉一个 add_child」。
##
## 传送为什么直接改坐标而不是切场景：
##   子图与主图在同一个场景里，只隔 1000 m。切场景会牵动存档、流送与相机重建，
##   而这里只需要「玩家瞬移到另一个位置」。
##
## 传送怎么触发（业主 2026-10-18 定稿）：
##   **不是**踩进 Area3D 就走，而是门口出现与「搜索容器」同一个白点，按 E 才过去。
##   门板本身**一直在**（装配时就有，不等清房）—— 清房只决定能不能打穿它。

const SECRET_DOOR_SCRIPT := preload("res://src/world3d/SecretDoor3D.gd")
## 门槽的唯一实现（与生成器/校验器同一份）。子图**不复制**「墙长→lane」公式。
const ROOM_DOOR_LANE := preload("res://src/map/RoomDoorLane.gd")

## 子图区原点相对主图 site 的 X 偏移。两对分开放，互不干扰。
const BRANCH_ORIGIN_X_M := 1000.0
const BRANCH_ORIGIN_X_STRIDE_M := 300.0
## 子图房间之间的走道长度（m）。与主路同一口径：5 m 整数段（05.2 §3.7）。
const ROOM_GAP_M := 5.0
## 子图房型池（设计 §3.5）：复用关卡 `content_template_pool` 的三种房型。
##
## 取值顺序：先 `LevelPlanLoader.load_room_templates()`（L3 真值），取不到才用这份兜底。
## 兜底尺寸与 L3 文件**同值**，只是数据缺失时让子图仍可走通，不是第二套真源。
## 桥房写的是**转置后的占位尺寸**：`bridge_60x50` 实际 30×60、桥沿 z 跨，
## 转置后 60×30、桥沿 x 跨，才能在东西向串联链里两门同轴（05.2 §3.6 第 4/8 条）。
const BRANCH_TEMPLATE_FALLBACK := {
	"corridor_45x40": Vector2(45.0, 40.0),
	"office_60x70": Vector2(30.0, 40.0),
	"bridge_60x50": Vector2(60.0, 30.0),
}
## 桥房模板 id（判定键 = 模板带 `sunken_pit`，这里只用于兜底数据）。
const BRIDGE_TEMPLATE_ID := "bridge_60x50"
## 子图房借用的**共享房壳**（模板 id → 文件名）。
##
## 为什么要壳：`DungeonRoom3D._build_shell` 会比对布局根的 `metadata/room_id`
## 与房间自己的 id，不一致直接 push_error；而子图房 id 是 `secret_<pair>_<i>`，
## 每一局都可能抽到不同模板。壳根**刻意不写 room_id**（空值跳过该比对），
## 由这里按模板显式下发路径 —— 不靠「同名猜测」。
const SHARED_LAYOUT_FILES := {
	"corridor_45x40": "f00_secret_shared_corridor_45x40_static_layout.tscn",
	"office_60x70": "f00_secret_shared_office_60x70_static_layout.tscn",
	"bridge_60x50": "f00_secret_shared_bridge_60x50_static_layout.tscn",
	"extraction_25x25": "f00_secret_shared_extraction_25x25_static_layout.tscn",
}
## 房间静态布局目录。与 `TowerDescent3D.expedition_static_layout_path()` 同一约定；
## 不做第二份推导 —— 文件名由 `SHARED_LAYOUT_FILES` 显式给出，只拼目录。
const ROOM_LAYOUT_ROOT := (
	"res://assets/art/environments/tower_zones/expedition/runtime/room_instances/%s/"
)
## 板体血量基数与每清房增量，见设计 §4.1：`HP = 60 + 20 × 已清内容房数`。
const DOOR_HP_BASE := 60
const DOOR_HP_PER_CLEARED := 20
## 撤离门解锁阈值（占内容房比例），见设计 §6.2。
const EXTRACTION_UNLOCK_RATIO := 0.4
## 传送落点相对地面的高度（m）。玩家胶囊原点在地面上。
const TELEPORT_Y := 0.05
## 进支线 / 回主路的按键牌动词。只在这里各写一份：
## 圆点按键牌由 `InteractionDot3D.extract_action_verb` 从 prompt 里抽，不再另立动词表。
const VERB_ENTER := "进入暗门"
const VERB_RETURN := "返回主路"
const VERB_EXTRACTION := "进入撤离房"
const VERB_LEAVE_EXTRACTION := "返回支线"
## 子图房间门（`RoomDoor3D`）的交互距离（m）。与主路 `DungeonRoom3D.get_nearest_door`
## 的缺省一致：站在门前能按 E，站远一点就不再给候选。
const DOOR_INTERACT_RANGE_M := 3.4

## 主图 site 原点，子图按它偏移。由 `configure` 注入。
var _origin := Vector3.ZERO
var _run_seed := 0
var _rooms_source: Array = []
var _cleared_provider: Callable = Callable()
## 按 room_id 查房间是否已清（入口板解锁条件，设计 §5.2）。
var _room_cleared_provider: Callable = Callable()
## 内容房总数（撤离门阈值分母，设计 §6.2）。
var _content_total_provider: Callable = Callable()
## L3 房型表（`LevelPlanLoader.load_room_templates`），子图摆位取它的尺寸与门契约。
var _room_templates: Dictionary = {}
## 走廊构建器（`Dungeon3D._build_corridor`）。子图与主路**共用同一条**走廊实现，
## 不另写一份 —— 两份几何迟早会分叉。
var _corridor_builder: Callable = Callable()
## 房间主题。子图房是 `DungeonRoom3D`，没有主题会退回默认色。
var _room_theme: Resource = null
## 撤离信标工厂（`Dungeon3D._create_extraction_beacon`）。
## 子图撤离房用的是**同一套信标**，不新建第二套撤离系统 —— 结算走现成的
## `extraction_completed → _finish_run(true)`（设计 §6.3「结算规则与主撤离房完全一致」）。
var _beacon_factory: Callable = Callable()
## 本关 id（拼共享房壳路径用）。由 `Dungeon3D` 解析后注入。
var _level_id := ""
## 玩家踏进子图房间的上报口：`(room: DungeonRoom3D, with_encounter: bool) -> void`。
## 由 `Dungeon3D` 注入，负责「切当前房间 + 按编成刷怪」。本节点不自己刷怪。
var _room_enter_handler: Callable = Callable()
## 状态栏文案上报口（`Dungeon3D.status_label`）。缺省时静默。
var _status_reporter: Callable = Callable()

## pair_id -> { entry: {site, door}, exit: {...}, rooms: Array, branch_root, return_door }
var _pairs: Dictionary = {}
## site_id -> SecretDoor3D。含谜题门（S1–S4、X0/X1）与常开返程门（R0/R1、B0/B1）。
var _doors: Dictionary = {}
## 已建好的子图房中心点，pair_id -> Array[Vector3]（入口 → 出口顺序）
var _branch_points: Dictionary = {}
## 撤离门：pair_id -> { door: SecretDoor3D, unlocked: bool }
var _extraction_doors: Dictionary = {}
## room_id -> { room: DungeonRoom3D, combat: bool, entered: bool }。
## `combat = false` 的是撤离房：它是安全间（信标所在），不刷怪 —— 与「子图撤离房
## 跳过防线遭遇」同一条口径，不能让人一边读条一边被 5 只强化怪围住。
var _branch_rooms: Dictionary = {}


## `rooms_source` 是 `Dungeon3D._records` 的拷贝（只读用途：读房间 center/size/secret_site）。
## `cleared_provider` 返回「已清内容房数」，用于板体血量与撤离门解锁判定。
## `room_cleared_provider(room_id)` 返回该房间是否已清 —— 入口板只在入口房清完后可破。
## `content_total_provider()` 返回内容房总数 —— 撤离门阈值的分母。
func configure(
	origin: Vector3,
	run_seed: int,
	rooms_source: Array,
	cleared_provider: Callable,
	room_cleared_provider: Callable = Callable(),
	content_total_provider: Callable = Callable(),
	room_templates: Dictionary = {},
	corridor_builder: Callable = Callable(),
	room_theme: Resource = null,
	beacon_factory: Callable = Callable(),
	level_id: String = "",
	room_enter_handler: Callable = Callable(),
	status_reporter: Callable = Callable()
) -> void:
	_origin = origin
	_run_seed = run_seed
	_rooms_source = rooms_source
	_cleared_provider = cleared_provider
	_room_cleared_provider = room_cleared_provider
	_content_total_provider = content_total_provider
	_room_templates = room_templates
	_corridor_builder = corridor_builder
	_room_theme = room_theme
	_beacon_factory = beacon_factory
	_level_id = level_id
	# 运行期回调**只在拿到有效 Callable 时覆盖**。
	# 原因：`configure` 也被验收/工具用来改「已清数 / 撤离阈值」那几个 provider
	# （`verify_secret_branch_flow` 的 A11 就只传前 6 个参数重配一次）。若这里无条件
	# 赋值，那次重配会把上报口清成空 Callable —— 表现是「之后进的子图房间不刷怪、
	# `_current_room_id` 也不跟着变」，而房间自己那一侧的 `entered` 已经置真，
	# 两本账对不上，极难从现象反推原因。
	if room_enter_handler.is_valid():
		_room_enter_handler = room_enter_handler
	if status_reporter.is_valid():
		_status_reporter = status_reporter


## 主入口：解析位点 → 决定刷哪几对 → 建板体 → 建子图。
func build() -> void:
	var sites := _collect_sites()
	if sites.is_empty():
		return
	for pair_id in [0, 1]:
		if not _pair_spawned(pair_id):
			continue
		var entry := _find_site(sites, pair_id, "entry")
		var exit_site := _find_site(sites, pair_id, "exit")
		if entry.is_empty() or exit_site.is_empty():
			# 配对不完整只告警不崩：缺一半的支线没有意义，跳过即可。
			push_warning("[SecretBranch3D] 配对 %d 缺入口或出口位点，已跳过" % pair_id)
			continue
		_build_pair(pair_id, entry, exit_site)


## —— 位点解析 ——

## 把房间记录里的 `secret_site` 解析成世界坐标位点。
## 位置 = 房间包围盒在该墙上的中点 + 沿墙偏移 `lane`；坐标由几何推导，
## **不读设计源世界坐标** —— 改版图时位点自动跟随，不会两处不同步。
##
## `lane` 让位点落在**固定槽位**上（业主 2026-10-18：暗门入口/出口位置固定，
## 只由数据决定哪条是入口、哪条是出口）。缺省 0 = 墙中点，与旧行为逐字一致。
## 为什么不能只取中点：墙中点经常正是主路门洞的位置，2.2m 木板会把主路钉死
## （远征01 S3 曾与 `room_06 → room_07` 的 `Door_North` 重合 0.00m）。
func _collect_sites() -> Array:
	var result: Array = []
	for value in _rooms_source:
		var record := value as Dictionary
		var site := record.get("secret_site", {}) as Dictionary
		if site.is_empty():
			continue
		var wall := str(site.get("wall", ""))
		var center := record.get("position", Vector3.ZERO) as Vector3
		var dims := _record_dimensions(record)
		if dims.x <= 0.0 or dims.y <= 0.0:
			continue
		var normal := _wall_normal(wall)
		if normal == Vector3.ZERO:
			push_warning("[SecretBranch3D] 位点墙面非法: %s" % wall)
			continue
		var lane := float(site.get("lane", 0.0))
		var half := Vector3(dims.x * 0.5, 0.0, dims.y * 0.5)
		var point := (
			center
			+ Vector3(normal.x * half.x, 0.0, normal.z * half.z)
			+ _wall_tangent(wall) * lane
		)
		result.append({
			"site_id": str(site.get("site_id", "")),
			"pair_id": int(site.get("pair_id", -1)),
			"role": str(site.get("role", "")),
			"wall": wall,
			"lane": lane,
			"normal": normal,
			"position": point,
			"room_id": str(record.get("id", "")),
		})
	return result


func _record_dimensions(record: Dictionary) -> Vector2:
	var custom := record.get("custom_dimensions", Vector2.ZERO) as Vector2
	if custom.x > 0.0 and custom.y > 0.0:
		return custom
	return record.get("dimensions", Vector2.ZERO) as Vector2


## Godot 约定：-Z 为北，+Z 为南，+X 为东。
func _wall_normal(wall: String) -> Vector3:
	match wall:
		"north": return Vector3(0, 0, -1)
		"south": return Vector3(0, 0, 1)
		"east": return Vector3(1, 0, 0)
		"west": return Vector3(-1, 0, 0)
	return Vector3.ZERO


## 沿墙方向：南北墙沿 +X，东西墙沿 +Z。`secret_site.lane` 的正负与设计源
## `connection_ports.position_m` 的沿墙分量同一符号（南墙的 lane 就是它的 x）。
func _wall_tangent(wall: String) -> Vector3:
	match wall:
		"north", "south": return Vector3(1, 0, 0)
		"east", "west": return Vector3(0, 0, 1)
	return Vector3.ZERO


func _find_site(sites: Array, pair_id: int, role: String) -> Dictionary:
	for value in sites:
		var site := value as Dictionary
		if int(site.get("pair_id", -1)) == pair_id and str(site.get("role", "")) == role:
			return site
	return {}


## —— 刷出规则（设计 §3.3）——

## pair 0 恒定刷出；pair 1 按种子 50%。
func _pair_spawned(pair_id: int) -> bool:
	if pair_id == 0:
		return true
	return absi(hash("%d|secret_pair|%d" % [_run_seed, pair_id])) % 100 < 50


## 子图房间数：2 或 3（设计 §3.4）。
func _branch_room_count(pair_id: int) -> int:
	return 2 + absi(hash("%d|secret_len|%d" % [_run_seed, pair_id])) % 2


## —— 装配 ——

func _build_pair(pair_id: int, entry: Dictionary, exit_site: Dictionary) -> void:
	var branch_root := Node3D.new()
	branch_root.name = "SecretBranch_%d" % pair_id
	add_child(branch_root)

	var room_count := _branch_room_count(pair_id)
	var room_states := _build_branch_rooms(branch_root, pair_id, room_count)
	var points: Array = []
	for value in room_states:
		points.append((value as Dictionary).get("center", Vector3.ZERO))
	_branch_points[pair_id] = points
	if room_states.is_empty():
		return

	# 入口门只在入口房清完后可破（设计 §5.2）。出口门不锁 —— 玩家从子图回来时
	# 必须能立刻落地，不能因为出口房还在战斗而被关在墙里。
	var entry_door := _build_door(pair_id, entry, not _site_room_cleared(entry))
	var exit_door := _build_door(pair_id, exit_site, false)

	# 主图 ↔ 子图这一跳仍是传送（设计 §1：物理不相连），但**触发方式是按 E**：
	# 门板一直在，破板后门口出现圆点，按 E 才过去（设计 §4.3）。
	# 双向（§5.4）：从入口门进去落在子图首间，从出口门进去落在末间 —— 两端都能进。
	var last_center := points[points.size() - 1] as Vector3
	entry_door.call("set_teleport_target", points[0], VERB_ENTER)
	exit_door.call("set_teleport_target", last_center, VERB_ENTER)
	# 子图末端 → 主图出口房间内侧：末间东墙上一扇常开门（没有木板，不用再打破一次）。
	# 它是「进了能出来」的唯一保证（A15）。
	var return_door := _build_return_door(pair_id, room_states, exit_site)

	_pairs[pair_id] = {
		"entry": entry,
		"exit": exit_site,
		"rooms": points,
		"branch_root": branch_root,
		"entry_door": entry_door,
		"exit_door": exit_door,
		"return_door": return_door,
	}

	# 撤离门：子图中途的第二道隐藏门（设计 §6.1），到第 2 间房之后才有意义。
	if room_count >= 2:
		_build_extraction_room(branch_root, pair_id, room_states)


## 子图房间：**真房型 + 门 + 走廊**（05.2 §3.6 第 7 条 / §3.5.2）。
##
## 为什么不再手搓「四面实墙的盒子」（2026-10-18 修正）：
##   盒子没有门洞，房与房只能靠传送推进 —— 那不是子图的做法，是绕开生成规范。
##   规范要求支线房**从锁定模板集合里取**（`role = "branch"` 只是标注，不是新房型），
##   门位取模板 `wall_lane_table` 的合法槽位，走不通就是缺陷、不是「设计如此」。
##   所以这里按模板尺寸放**真 `DungeonRoom3D`**，房间自己按 `doors` 开洞并建
##   `RoomDoor3D`，房与房之间用与主路**同一条**走廊构建器接起来。
##
## 为什么用「方向 + lane」而不是 `connection_ports`：
##   §3.5.1 的显式端口与「共墙唯一所有权」是给**共墙**（净距 0）那类连接用的 ——
##   一条边只允许一端生成门墙与门扇，另一端登记引用。子图相邻两间隔着 5 m 走廊，
##   各自在自己墙上开门、各持自己的门扇，不存在共享边，所以走**方向粒度 + lane**
##   这条（§3.5.2）路径；门位仍必须落在模板 lane 上。
##
## 返回 `{room, center, size, index, lane, template_id}`：撤离门与末端返回门都要按
## 这一间自己的尺寸贴墙，写死半深会在 45×40 的房上把门放到墙外。
func _build_branch_rooms(root: Node3D, pair_id: int, count: int) -> Array:
	var picked := _pick_branch_templates(pair_id, count)
	var rooms: Array = []
	var origin := _branch_origin(pair_id)
	var cursor_x := origin.x
	for index in range(picked.size()):
		var entry := picked[index] as Dictionary
		var size := entry.get("size", BRANCH_TEMPLATE_FALLBACK[BRIDGE_TEMPLATE_ID]) as Vector2
		var room_id := "secret_%d_%d" % [pair_id, index]
		var center := Vector3(cursor_x + size.x * 0.5, 0.0, origin.y)
		# 端口的**唯一权威**是本间的邻居：首间只有东门，末间只有西门。
		# 这条同时保证「未连接的候选端口维持实体封墙」—— 少开一个门就少一条路，
		# 不会留下通往空地的洞。
		var doors: Array = []
		var door_targets: Dictionary = {}
		if index > 0:
			doors.append("west")
			door_targets["west"] = "secret_%d_%d" % [pair_id, index - 1]
		if index < picked.size() - 1:
			doors.append("east")
			door_targets["east"] = "secret_%d_%d" % [pair_id, index + 1]
		var lane := _branch_door_lane(size)
		var template_id := str(entry.get("template_id", ""))
		var room := _spawn_branch_room(
			root, room_id, center, size, doors, door_targets, index, lane, template_id
		)
		rooms.append({
			"room": room,
			"center": center,
			"size": size,
			"index": index,
			"lane": lane,
			"template_id": str(entry.get("template_id", "")),
		})
		# 下一间从本间东侧 + 走廊段处开始（5 m 整数段，与主路同一口径）。
		cursor_x += size.x + ROOM_GAP_M
	_build_branch_corridors(pair_id, rooms)
	return rooms


func _branch_origin(pair_id: int) -> Vector2:
	return Vector2(
		_origin.x + BRANCH_ORIGIN_X_M + BRANCH_ORIGIN_X_STRIDE_M * pair_id,
		_origin.z
	)


## 子图房型：从 L3 模板表取三种（设计 §3.5），按种子无放回抽取。
##
## 桥房的硬约束（05.2 §3.6 第 8 条）：桥只能**两门同轴**、且只落在桥的跨向两端，
## 因此它只允许排在链中间；排首尾会缺一个门，等于把路堵死。
## 桥沿 x 跨靠**转置姿态**表达（占位尺寸写交换后的实际尺寸），不新建模板 id。
func _pick_branch_templates(pair_id: int, count: int) -> Array:
	var pool := _branch_template_pool()
	var bridge: Dictionary = {}
	var straight: Array = []
	for value in pool:
		var entry := value as Dictionary
		if bool(entry.get("bridge", false)):
			bridge = entry
		else:
			straight.append(entry)
	if straight.is_empty():
		straight = pool.duplicate()
	var unused := straight.duplicate()
	var picked: Array = []
	for index in range(count):
		var use_bridge := not bridge.is_empty() and index > 0 and index < count - 1
		if use_bridge:
			picked.append(bridge.duplicate())
			continue
		if unused.is_empty():
			unused = straight.duplicate()
		var pick_index := absi(
			hash("%d|secret_room|%d|%d" % [_run_seed, pair_id, index])
		) % unused.size()
		picked.append((unused[pick_index] as Dictionary).duplicate())
		unused.remove_at(pick_index)
	return picked


func _branch_template_pool() -> Array:
	var result: Array = []
	for template_value in BRANCH_TEMPLATE_FALLBACK:
		var template_id := str(template_value)
		if _room_templates.is_empty() or not _room_templates.has(template_id):
			result.append({
				"template_id": template_id,
				"size": BRANCH_TEMPLATE_FALLBACK[template_id] as Vector2,
				"bridge": template_id == BRIDGE_TEMPLATE_ID,
			})
			continue
		var template := _room_templates[template_id] as Dictionary
		var raw_size := template.get("size_m", []) as Array
		if raw_size.size() < 2:
			continue
		var size := Vector2(float(raw_size[0]), float(raw_size[1]))
		# 判定键 = 模板带 `sunken_pit`（与校验器同口径），不是名字。
		var bridge := template.has("sunken_pit")
		if bridge:
			# 转置姿态：桥沿 x 跨，占位尺寸交换（05.2 §3.6 第 4 条）。
			size = Vector2(size.y, size.x)
		result.append({"template_id": template_id, "size": size, "bridge": bridge})
	return result


## 一个子图房间节点。门洞、门扇、碰撞、墙体全部交给 `DungeonRoom3D` ——
## 与主路房间走同一条壳体构建路径，子图不再有自己的几何实现。
##
## `template_id` 决定借哪一份**正式美术**（`SHARED_LAYOUT_FILES` 里的共享房壳）。
## 找不到壳（或壳里引用的源房间缺文件）时 `DungeonRoom3D` 会回退程序化壳体并告警，
## 也就是**灰盒** —— 那是缺陷，A18 会把它抓出来。
func _spawn_branch_room(
	root: Node3D,
	room_id: String,
	center: Vector3,
	size: Vector2,
	doors: Array,
	door_targets: Dictionary,
	index: int,
	lane: float = 0.0,
	template_id: String = "",
	encounter: bool = true
) -> DungeonRoom3D:
	var room := DungeonRoom3D.new()
	room.name = "SecretRoom_%s" % room_id
	# 子图房的门是**普通通道门**，不是主路那种消耗钥匙、触发命运卡、要求清房的关卡门：
	#   ① 子图里没有钥匙产出，`requires_key = true` 会让门永远打不开（死路）；
	#   ② 命运三选一属于主路推进节奏，在可选的支线里插一张卡只会打断战斗；
	#   ③ `requires_clear = true` 会把玩家锁在一间 5 强化 + 2 普通的房里 ——
	#      支线是可选内容，绝不能因为打不过就永远出不去。
	# 三项都关掉，门就回到「按 E 开、纯通行」。
	var free_door_policy := {"requires_key": false, "requires_clear": false, "triggers_fate": false}
	var policies := {}
	for direction in doors:
		policies[str(direction)] = free_door_policy.duplicate()
	room.configure({
		"room_id": room_id,
		"room_type": "COMBAT",
		"size_class": "medium",
		"custom_dimensions": size,
		"doors": doors,
		"door_targets": door_targets,
		"door_policies": policies,
		"theme": _room_theme,
		"seed": _run_seed + index * 104729,
		"is_main_path": false,
		"static_layout_scene_path": _shared_layout_path(template_id),
	})
	# 门洞与门扇读同一个 lane：`DungeonRoom3D._build_wall` 切口、
	# `_build_door` 门扇位置都取 `wall_door_lane_<side>`。只设一头会得到
	# 「洞在一边、门扇在另一边」——那条边就永远走不过去。
	for direction in doors:
		room.set_meta("wall_door_lane_%s" % direction, lane)
	room.position = center
	root.add_child(room)
	room.ensure_shell_built()
	room.set_stream_state(DungeonRoom3D.STREAM_SHELL_READY)
	# 进房上报：子图房间不在 `_records` 里，`Dungeon3D._on_room_entered` 那条链
	# 收不到它们。挂到房间自带的 `player_entered`（由 `RoomTrigger` 的 Area3D 发），
	# 上层据此切「当前房间」并按编成刷怪。
	_branch_rooms[room_id] = {"room": room, "combat": encounter, "entered": false}
	room.player_entered.connect(_on_branch_room_player_entered)
	return room


## 玩家踏进子图房间（房间自带 `RoomTrigger` 的 Area3D 触发）。
##
## **只上报，不刷怪。** 刷怪要接 6 个信号、挂 `$ActiveEnemies`、写 `_alive_by_room`
## 与 `_enemy_nodes_by_room` —— 那是 `Dungeon3D` 的私事（同一条理由见剧情刷怪的
## 「正门」注释）。子图另写一套就是两套战斗账：补刷、召唤、掉落、清房判定全会分叉。
func _on_branch_room_player_entered(room: DungeonRoom3D) -> void:
	if room == null or not is_instance_valid(room) or room.room_id.is_empty():
		return
	var row := _branch_rooms.get(room.room_id, {}) as Dictionary
	if row.is_empty():
		return
	var first_visit := not bool(row.get("entered", false))
	row["entered"] = true
	_branch_rooms[room.room_id] = row
	if not _room_enter_handler.is_valid():
		return
	# 编成只在**首次**进房时报一次；撤离房（`combat = false`）永远不带编成。
	_room_enter_handler.call(room, bool(row.get("combat", false)) and first_visit)


## 子图里最近的一扇**关着的**房间门。供 `Dungeon3D` 的门交互路由调用。
##
## 为什么需要它：子图房间不在 `_room_by_id` 里，`Dungeon3D.get_interaction_candidate`
## 按 `_current_room_id` 取房会取到 null。不补这条，子图的房间门永远按不开 ——
## 玩家会卡在第二间门外，而房间里那 7 只怪也永远打不到。
func nearest_closed_door(world_position: Vector3) -> Dictionary:
	var best: Dictionary = {}
	for room_id in _branch_rooms:
		var room := (_branch_rooms[room_id] as Dictionary).get("room") as DungeonRoom3D
		if room == null or not is_instance_valid(room) or room.is_queued_for_deletion():
			continue
		var info := room.get_nearest_door(world_position, DOOR_INTERACT_RANGE_M)
		if info.is_empty() or bool(info.get("is_open", false)):
			continue
		if best.is_empty() or float(info.get("distance", INF)) < float(best.get("distance", INF)):
			best = info
	return best


## 状态栏文案上报（由 `Dungeon3D` 注入）。缺省静默，不阻断流程。
func _report_status(text: String) -> void:
	if _status_reporter.is_valid():
		_status_reporter.call(text)


## 供验收：子图逐间的编成登记（是不是战斗间、进没进过、是否已清）。
func room_encounter_snapshot() -> Array:
	var rows: Array = []
	for room_id in _branch_rooms:
		var row := _branch_rooms[room_id] as Dictionary
		var room := row.get("room") as DungeonRoom3D
		rows.append({
			"room_id": room_id,
			"combat": bool(row.get("combat", false)),
			"entered": bool(row.get("entered", false)),
			"cleared": room.cleared if room != null and is_instance_valid(room) else false,
		})
	rows.sort_custom(func(a, b): return str(a["room_id"]) < str(b["room_id"]))
	return rows


## 子图门位：东西墙的合法门槽（05.2 §3.5.2 公式），由 `RoomDoorLane` 唯一实现给出。
## 子图链沿 X 串联 ⇒ 门只落在东西墙，墙长 = 房间深度 `size.y`。
func _branch_door_lane(size: Vector2) -> float:
	return ROOM_DOOR_LANE.nearest_offset(size.y)


## 模板 → 共享房壳的完整路径。缺 id 或缺文件返回空串（调用方回退程序化）。
func _shared_layout_path(template_id: String) -> String:
	if template_id.is_empty() or _level_id.is_empty():
		return ""
	if not SHARED_LAYOUT_FILES.has(template_id):
		return ""
	var path := (ROOM_LAYOUT_ROOT % _level_id) + str(SHARED_LAYOUT_FILES[template_id])
	if not ResourceLoader.exists(path):
		push_warning(
			"[SecretBranch3D] 模板 `%s` 的共享房壳不存在：%s —— 该间会退回灰盒" % [template_id, path]
		)
		return ""
	return path


## 相邻两间之间的走廊：**复用 `Dungeon3D._build_corridor`**。
## 子图不另写一份走廊几何 —— 两份实现迟早会在宽度、材质、碰撞高度上分叉。
func _build_branch_corridors(pair_id: int, rooms: Array) -> void:
	if not _corridor_builder.is_valid():
		push_warning("[SecretBranch3D] 未注入走廊构建器，子图房间之间将不可通行")
		return
	for index in range(rooms.size() - 1):
		var from_room := (rooms[index] as Dictionary).get("room") as DungeonRoom3D
		var to_room := (rooms[index + 1] as Dictionary).get("room") as DungeonRoom3D
		if from_room == null or to_room == null:
			continue
		# 走廊中心线跟着门位走；两端 lane 不同就取前一间的（子图链同轴，
		# 现实里两者恒相等 —— 模板三种尺寸的东西墙最近槽都是 -2.5）。
		var lane := float((rooms[index] as Dictionary).get("lane", 0.0))
		_corridor_builder.call(from_room, to_room, 100 + pair_id * 10 + index, lane)


func _build_door(pair_id: int, site: Dictionary, locked: bool = false) -> Node3D:
	var door_node := SECRET_DOOR_SCRIPT.new()
	door_node.name = "SecretDoor_%s" % str(site.get("site_id", ""))
	var position := site.get("position", Vector3.ZERO) as Vector3
	# 资产装配系原点在**地面、门洞中心**（不是板体中心）：门叶与木板共用这一原点，
	# 木板朝资产 -Z 凸向房间、门腔朝 +Z 凹进墙里。所以这里直接落地面点。
	door_node.position = position
	var normal := site.get("normal", Vector3.FORWARD) as Vector3
	# 让资产的 **-Z 对齐「指向房间内」**（木板那面朝向房间、门腔朝墙内凹）。
	# 绕 Y 转 θ 后资产 -Z 轴 = (-sinθ, 0, -cosθ)；要它等于 -normal：
	#   -sinθ = -n.x, -cosθ = -n.z  ⇒  θ = atan2(n.x, n.z)
	# ⚠️ 早先写成 atan2(-n.x, -n.z)，结果木板朝**墙外**凸、门腔反而插进房间，
	# 玩家在房里看到的是那扇门叶而不是钉死的木板。资产包围盒看不出这个错，
	# 因为它只报尺寸不报朝向，只有进游戏看才发现。
	door_node.rotation.y = atan2(normal.x, normal.z)
	door_node.call("configure", site, _door_hp())
	door_node.call("set_locked", locked)
	# 传送由门自己按 E 触发（`teleport_requested`），不再有踩上去就走的 Area3D。
	door_node.connect("teleport_requested", _on_door_teleport_requested)
	add_child(door_node)
	_doors[str(site.get("site_id", ""))] = door_node
	return door_node


## 入口板能否破：入口所在房间必须已清（设计 §5.2）。
## provider 缺失即返回 false —— 宁可锁着，也不要放玩家进状态未知的支线。
func _site_room_cleared(site: Dictionary) -> bool:
	if not _room_cleared_provider.is_valid():
		return false
	var room_id := str(site.get("room_id", ""))
	if room_id.is_empty():
		return false
	var value: Variant = _room_cleared_provider.call(room_id)
	return bool(value) if value != null else false


func _door_hp() -> int:
	return DOOR_HP_BASE + DOOR_HP_PER_CLEARED * _cleared_count()


## 一扇**常开门**（没有木板层）：装在某段墙面中点，按 E 去别处。
##
## 与谜题门的差别只有两点：没有木板（不用打），state 一开始就是 BROKEN。
## 其余（门叶资产、装配系、圆点协议、按 E 触发）完全相同 —— 不给支线另起一套传送表现。
func _build_portal_door(site: Dictionary, verb: String, target: Vector3) -> Node3D:
	var door_node := SECRET_DOOR_SCRIPT.new()
	door_node.name = "SecretDoor_%s" % str(site.get("site_id", ""))
	door_node.position = site.get("position", Vector3.ZERO) as Vector3
	var normal := site.get("normal", Vector3.FORWARD) as Vector3
	door_node.rotation.y = atan2(normal.x, normal.z)
	door_node.call("configure_portal", site, verb, target)
	door_node.connect("teleport_requested", _on_door_teleport_requested)
	add_child(door_node)
	_doors[str(site.get("site_id", ""))] = door_node
	return door_node


## 玩家在门前按 E。落点由门自己存着（装配时下发），这里只做「瞬移」这一件事。
func _on_door_teleport_requested(site_id: String, player: Node3D) -> void:
	var door: Node3D = _doors.get(site_id)
	if door == null or not is_instance_valid(door):
		return
	if not bool(door.call("can_teleport")):
		return
	_open_source_exit_door(door)
	_release_player(player, door.call("get_teleport_target") as Vector3)


## 从子图末端穿回主图时，把主图出口房间那扇**同源的木板门**一起打开。
##
## 不这么做，玩家会在出口房间内侧落地、正对着那扇钉死的门 —— 人刚从里面出来，
## 门却还是封着的。只对 `return_door` 生效：撤离房的返程门（`B*`）没有对应的主图门。
func _open_source_exit_door(door: Node3D) -> void:
	for pair_id in _pairs:
		var pair := _pairs[pair_id] as Dictionary
		if pair.get("return_door") != door:
			continue
		var exit_door: Node3D = pair.get("exit_door")
		if exit_door != null and is_instance_valid(exit_door):
			exit_door.call("open_silently")
		return


## 玩家瞬移。为什么用 deferred：交互可能在物理查询/输入回调期间触发，
## 此时直接改 transform 会被物理服务器拒绝或产生一帧穿透。
## 速度也要清 —— 带着跑动速度落地会被同一帧的积分拉回门里。
func _release_player(player: Node3D, target: Vector3) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	player.set_deferred("global_position", target + Vector3(0, TELEPORT_Y, 0))


## 出口落点：从墙面往房间内侧退 1.2 m，避免落在墙体内。
func _inside_point(site: Dictionary) -> Vector3:
	var normal := site.get("normal", Vector3.FORWARD) as Vector3
	var position := site.get("position", Vector3.ZERO) as Vector3
	return position - normal * 1.2


## 子图末端 → 主图出口房间内侧的那扇门。
##
## 装在最后一间房的**东墙中点**（位置按该房自己的尺寸算，不写死 12.5）。
## 为什么仍然用传送：主图与子图按设计是**物理不相连**的两块（§1），
## 出口这一跳没有物理通道可走；子图**内部**已经是门 + 走廊走通的了。
##
## 这扇门**不开木板**：玩家已经在子图里，不该为了出去再打一块 60+ 血的板。
## 它是 A15 的唯一保证 —— 没有它，玩家进了子图就出不来。
func _build_return_door(
	pair_id: int, room_states: Array, exit_site: Dictionary
) -> Node3D:
	var last := room_states[room_states.size() - 1] as Dictionary
	var last_center := last.get("center", Vector3.ZERO) as Vector3
	var last_size := last.get("size", Vector2(25.0, 25.0)) as Vector2
	var site := {
		"site_id": "R%d" % pair_id,
		"pair_id": pair_id,
		"role": "return",
		"wall": "east",
		"normal": Vector3(1, 0, 0),
		"position": Vector3(last_center.x + last_size.x * 0.5, 0.0, last_center.z),
		"room_id": "",
	}
	return _build_portal_door(site, VERB_RETURN, _inside_point(exit_site))

## —— 撤离房（设计 §6）——

## 撤离房尺寸：优先取 L3 的 `extraction_25x25` 模板，缺数据时退回 25×25。
func _extraction_room_size() -> Vector2:
	if _room_templates.has("extraction_25x25"):
		var template := _room_templates["extraction_25x25"] as Dictionary
		var raw_size := template.get("size_m", []) as Array
		if raw_size.size() >= 2:
			return Vector2(float(raw_size[0]), float(raw_size[1]))
	return Vector2(25.0, 25.0)


## 撤离房是子图中途**第二道隐藏门**后的单间，不是子图串联链里的一间房。
##
## 结构（与入口同一套语义）：第一间房北墙上钉一块木板 → 打破 → 墙后是撤离房。
## 解锁条件 `已清内容房数 ≥ ceil(内容房总数 × 0.4)`（设计 §6.2），未达标时
## 木板存在但打不动。
##
## 撤离房**内含一个 `STANDARD` 撤离信标（非锁定）**（设计 §6.1）。信标不新建一套：
## 走 `Dungeon3D._create_extraction_beacon`，与主撤离房同一份实现、同一条结算链
## （`extraction_completed → _finish_run(true)`，设计 §6.3）。
func _build_extraction_room(root: Node3D, pair_id: int, room_states: Array) -> void:
	if room_states.size() < 2:
		return
	var first := room_states[0] as Dictionary
	var first_center := first.get("center", Vector3.ZERO) as Vector3
	var first_size := first.get("size", Vector2(25.0, 25.0)) as Vector2

	# 第一间房北墙（-Z 一侧）的墙面点，门洞居中。
	var wall_z := first_center.z - first_size.y * 0.5
	var door_site := {
		"site_id": "X%d" % pair_id,
		"pair_id": pair_id,
		"role": "extraction",
		"wall": "north",
		"normal": Vector3(0, 0, -1),
		"position": Vector3(first_center.x, 0.0, wall_z),
		"room_id": "",
	}

	# 撤离房：门后 5 m 走道 + 单间。房间同样是真房型（`extraction_25x25` 模板），
	# 只是**不开门** —— 它是隐藏门后的独立单间，进出只走那道隐藏门。
	var extraction_size := _extraction_room_size()
	var extraction_center := Vector3(
		first_center.x, 0.0, wall_z - ROOM_GAP_M - extraction_size.y * 0.5
	)
	var extraction_room := _spawn_branch_room(
		root, "secret_extraction_%d" % pair_id, extraction_center, extraction_size,
		[], {}, 90 + pair_id, 0.0, "extraction_25x25", false
	)
	# 信标：`STANDARD`、非锁定（设计 §6.1）。放在房间中心，与主撤离房同一口径。
	if _beacon_factory.is_valid():
		_beacon_factory.call(extraction_room)
	else:
		push_warning("[SecretBranch3D] 未注入信标工厂，撤离房将没有撤离信标")

	var unlocked := _extraction_unlocked()
	var door := _build_door(pair_id, door_site, not unlocked)
	# 破板后按 E 进入撤离房（落点：房内、离南墙 6.5 m 处，不在墙里）。
	door.call("set_teleport_target", extraction_center + Vector3(0, 0, 6.0), VERB_EXTRACTION)

	# 撤离房 → 回支线第一间房的返程门（南墙中点，常开）。
	# 没有它，玩家进了撤离房就只能「撤离或卡死」—— 想回去看看就没路了。
	var back_site := {
		"site_id": "B%d" % pair_id,
		"pair_id": pair_id,
		"role": "return",
		"wall": "south",
		"normal": Vector3(0, 0, 1),
		"position": Vector3(first_center.x, 0.0, extraction_center.z + extraction_size.y * 0.5),
		"room_id": "",
	}
	_build_portal_door(back_site, VERB_LEAVE_EXTRACTION, Vector3(first_center.x, 0.0, wall_z + 1.6))

	_extraction_doors[pair_id] = {"door": door, "unlocked": unlocked}


## 入口板解锁：入口所在房间清完后可破（设计 §5.2）。
## 每次清房后由 `Dungeon3D` 调一次，只解锁不重锁。
func refresh_entry_locks(room_cleared_provider: Callable) -> void:
	if room_cleared_provider.is_valid():
		_room_cleared_provider = room_cleared_provider
	for pair_id in _pairs:
		var pair := _pairs[pair_id] as Dictionary
		var door: Node3D = pair.get("entry_door")
		var site := pair.get("entry", {}) as Dictionary
		if door == null or not bool(door.call("is_locked")):
			continue
		if _site_room_cleared(site):
			door.call("set_locked", false)


## 撤离门解锁条件（设计 §6.2）：已清内容房数 ≥ ceil(内容房总数 × 0.4)。
## 远征 01 实测：总数 11（`room_01..10` + `boss`，已排除入口大厅与撤离房），
## 阈值 `ceil(11 × 0.4) = 5`。
func _extraction_unlocked() -> bool:
	var total := 0
	if _content_total_provider.is_valid():
		var value: Variant = _content_total_provider.call()
		total = int(value) if value != null else 0
	if total <= 0:
		# 拿不到总数就不解锁：宁可锁着，也不要让撤离门在错误的进度上开。
		return false
	var required := int(ceil(float(total) * EXTRACTION_UNLOCK_RATIO))
	return _cleared_count() >= required


## 撤离门阈值会在整局里跨过 —— 每次房间清理后由 `Dungeon3D` 调这个检查。
## 解锁只做一次，不重复触发。
func refresh_extraction_locks() -> void:
	if _extraction_doors.is_empty() or not _extraction_unlocked():
		return
	for pair_id in _extraction_doors:
		var row := _extraction_doors[pair_id] as Dictionary
		if bool(row.get("unlocked", false)):
			continue
		var door: Node3D = row.get("door")
		if door == null:
			continue
		door.call("set_locked", false)
		row["unlocked"] = true
		_extraction_doors[pair_id] = row


## 供验收与诊断：撤离门的锁定/破坏状态。
func extraction_snapshot() -> Dictionary:
	var rows: Array = []
	for pair_id in _extraction_doors:
		var row := _extraction_doors[pair_id] as Dictionary
		var door: Node3D = row.get("door")
		rows.append({
			"pair_id": pair_id,
			"unlocked": bool(row.get("unlocked", false)),
			"locked": bool(door.call("is_locked")) if door != null else true,
			"broken": bool(door.call("is_broken")) if door != null else false,
			# 可传送 ⟺ 木板已破。旧字段 `gate_monitoring` 随 Area3D 传送区一起退役。
			"teleport_ready": bool(door.call("can_teleport")) if door != null else false,
		})
	return {"threshold": _extraction_required(), "cleared": _cleared_count(), "rows": rows}


func _extraction_required() -> int:
	var total := 0
	if _content_total_provider.is_valid():
		var value: Variant = _content_total_provider.call()
		total = int(value) if value != null else 0
	if total <= 0:
		return -1
	return int(ceil(float(total) * EXTRACTION_UNLOCK_RATIO))


## —— 查询与存档 ——

func _cleared_count() -> int:
	if not _cleared_provider.is_valid():
		return 0
	var value: Variant = _cleared_provider.call()
	return int(value) if value != null else 0


func export_state() -> Dictionary:
	var doors: Array = []
	for site_id in _doors:
		doors.append((_doors[site_id] as Node3D).call("export_state"))
	var pairs: Array = []
	for pair_id in _pairs:
		pairs.append({
			"pair_id": pair_id,
			"spawned": true,
			"room_count": (_pairs[pair_id] as Dictionary).get("rooms", []).size(),
		})
	return {"doors": doors, "pairs": pairs}


func restore_state(snapshot: Dictionary) -> void:
	for value in snapshot.get("doors", []) as Array:
		var row := value as Dictionary
		var door: Node3D = _doors.get(str(row.get("site_id", "")))
		if door == null:
			continue
		door.call("restore_state", row)


## 诊断快照：给探针用，不参与存档。
func debug_snapshot() -> Dictionary:
	return {
		"pair_count": _pairs.size(),
		"pairs": _pairs.keys(),
		"doors": _doors.keys(),
		"branch_points": _branch_points.duplicate(true),
	}
