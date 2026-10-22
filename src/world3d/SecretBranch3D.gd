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
## 整樘暗门的预制体（门叶 + 木板 + 碰撞 + 透光 + 安装箱）。
## 与房间 TSCN 里手动摆放的是**同一个资源**：编辑器里看到的就是游戏里的。
const SECRET_DOOR_SCENE: PackedScene = preload(
	"res://assets/art/environments/tower_zones/expedition/runtime/common_components/secret_door/secret_door_root_top3d.tscn"
)
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
## 门必须从墙面凸出多少（m）。
##
## 3cm 只能保证「不穿模」，但玩家实测站在墙前开手电也看不出这里有门 ——
## 塔内是夜间光，齐平的一块板在暗房里读作「墙」。业主要的是
## 「墙壁凸出来一块，一眼看得见」（2026-10-19 第二次反馈），
## 所以这里取一个**肉眼可辨**的凸出量：门框前表面离墙面 0.40m。
const WALL_FACE_CLEARANCE_M := 0.40
## 门前净空检测：射线高度（m）与往房间内量的深度（m）。
const SITE_CLEAR_EYE_Y_M := 1.2
const SITE_CLEAR_DEPTH_M := 2.4
## 「看得见」判据的取样框（米）：门宽收窄后的一半、往房间里量的深度、
## 门高区间。碰撞射线查不出「美术面挡住但碰撞代理盒没挡住」——
## room_06 的东墙被一个 5.15×5.15 的转角壳体整块盖住，射线照样能打到门，
## 玩家却只看到一面平墙。所以必须再按**可视包围盒**查一遍。
const SITE_COVER_HALF_W_M := 0.9
const SITE_COVER_DEPTH_M := 1.2
const SITE_COVER_BOTTOM_Y_M := 0.2
const SITE_COVER_TOP_Y_M := 2.6
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
## 子图**承重地板**（见 `_ensure_floor_support()`）。
##
## 厚度与主路 `TowerFloorStage3D.FLOOR_THICKNESS` 同值：主路 `FloorSupport` 的盒心
## 下移半个厚度、顶面贴 y=0；子图照抄这个口径，玩家胶囊落点因此不需要任何偏移。
const BRANCH_FLOOR_SUPPORT_THICKNESS_M := 0.30
## 每块承重盒向外放的量（m）：吃掉相邻地砖之间那点建模缝，避免胶囊卡在缝上。
const BRANCH_FLOOR_SUPPORT_OVERLAP_M := 0.06
const BRANCH_FLOOR_SUPPORT_NAME := "SecretFloorSupport"
## 壳足迹与本间尺寸的允许误差（m）。
##
## 取 1.5 而不是 1.0：`office_60x70` 的壳里有一件伸出房间 0.8 m 的装饰件，离树量足迹
## 时量到 41.1（进树后会被裁掉一层，实测 40.3）。而**转错 90° 的候选至少差 4 m**
## （45×40 ↔ 40×45、30×60 ↔ 60×30），1.5 不会把错朝向放进来。
const SHELL_FIT_TOLERANCE_M := 1.5
## —— 壳的「真砖格」量法（见 `_shared_shell_footprint()`）——
## 判「这是地砖」用：网格件厚度上限（m）。墙 11.9 m、家具更厚，都进不来。
const SHELL_TILE_MAX_THICKNESS_M := 0.8
## 判「这是地砖」用：顶面离壳地面（y=0）的允许偏差（m）。
const SHELL_TILE_MAX_TOP_OFFSET_M := 0.4
## 砖格归整粒度（m），与模板 `grid_unit_m` 同值。
const SHELL_TILE_GRID_M := 5.0
## 判「这个点在某块砖上」用：半个砖格 + 容差（m）。
const SHELL_TILE_HALF_M := 2.5
const SHELL_TILE_HIT_TOLERANCE_M := 0.05
## 判「这是地砖」用：面积下限（㎡）。5×5 砖是 25，压条/缝条远小于它。
## 不筛掉这些窄片，一块砖会被切成好几片，承重盒数暴涨（实测 7288 块）。
const SHELL_TILE_MIN_AREA_M2 := 4.0

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
## room_id -> 主图房间节点。只在 `_collect_sites()` 前建一次：
## 位点要按**实测墙面外沿**外推，光有房间记录（center/dimensions）不够。
var _room_nodes: Dictionary = {}
## `_collect_sites()` 的产物，供 `debug_snapshot()` 与验收读取
## （要看「推了多少米」「门前被什么挡住」，不能只看门节点坐标）。
var _sites_debug: Array = []
## site_id -> { room_local: Transform3D, room_id: String }
## 房间 TSCN 里**手动摆放**的暗门节点。有就用手摆的位置（业主在编辑器里拖的就是它），
## 没有才退回数据位点 + 自动外推。
var _authored_doors: Dictionary = {}
## 房间副本清道夫是否已挂上（只挂一次）。
var _room_copy_watch_armed := false
## 本次装配一共清掉了几扇「房间 TSCN 带来的摆位锚点副本」（诊断用）。
var _pruned_room_copies := 0
## 共享房壳足迹缓存：壳路径 -> {size: Vector2, door_sides: Array}。
## 同一份壳在一次装配里只会被不同房间重复用到，量一次就够。
var _shell_footprints: Dictionary = {}


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
	_sites_debug = sites.duplicate(true)
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
	# 这里房间节点多半还没进树（远征 bootstrap 先于房间装配，实测房间索引只有 1 个），
	# 拿不到墙体几何。等这一帧结束、房间齐了再补做一次外推；`settle_sites()` 幂等。
	#
	# 同时挂上「房间副本清道夫」：房间 TSCN 里那扇门此刻还没被实例化（房间本体都在
	# 这一步之后才建），所以接管一定落空；等壳体建好它才冒出来，必须按事件盯住。
	_arm_room_copy_watch()
	call_deferred("settle_sites")


## 房间齐了之后补做「位点外推」。
##
## 两处触发：`build()` 末尾的 deferred（同帧兜底），以及 `Dungeon3D._create_secret_branches`
## 的幂等分支（`_finish_layout_connections()` 那条链，此时房间已全部装配完）。
## 幂等：推过的位点带着 `wall_push_m`，再进来直接跳过，不会越推越远。
func settle_sites() -> void:
	_build_room_index()
	if _room_nodes.is_empty():
		return
	# 房间索引这时才齐（bootstrap 阶段只有 1 间）。手动摆位可能刚才没读到，
	# 所以重读一次；新命中的位点要把已经建好的门搬过去。
	_read_authored_doors()
	for value in _sites_debug:
		var site := value as Dictionary
		if bool(site.get("manual_site", false)):
			continue
		if _apply_authored_door(site):
			_rebase_door(site)
	var shifted := 0
	for value in _sites_debug:
		var site := value as Dictionary
		if bool(site.get("manual_site", false)):
			# 手动摆位重扫一遍「墙面在哪」：`_collect_sites()` 那一刻房间往往还没装配完
			# （bootstrap 先于房间），凸出量是空的。这里补齐数值，但仍然不动位置。
			_push_site_out_of_wall(site, false)
			var manual_door := _doors.get(str(site.get("site_id", ""))) as Node3D
			if manual_door != null:
				_apply_site_mount(manual_door, site)
			continue
		if float(site.get("wall_push_m", 0.0)) > 0.0:
			continue
		if not _room_nodes.has(str(site.get("room_id", ""))):
			continue
		_push_site_out_of_wall(site)
		_measure_site_blocker(site)
		if float(site.get("wall_push_m", 0.0)) > 0.0:
			_shift_door(site)
			shifted += 1
	if shifted > 0:
		for value in _sites_debug:
			var site := value as Dictionary
			if site.has("blocker"):
				push_warning(
					"[SecretBranch3D] 位点 %s（%s）门前 2.4m 被 %s 挡住 —— 玩家看不到也走不到，请改 lane"
					% [
						str(site.get("site_id", "")), str(site.get("room_id", "")),
						str(site.get("blocker", "")),
					]
				)
	# 视觉遮挡必须**每次都查**，且与 `shifted` 无关：外推救不了 5m 厚的转角壳，
	# 而这一条恰恰是射线判据查不出来的盲区（ray 能穿过去，玩家只看到墙）。
	for value in _sites_debug:
		_measure_visual_cover(value as Dictionary)
	# 房间齐了这一轮，把还没被认领的「摆位锚点门」清一遍。
	# `node_added` 那条路已经能兜住按需出现的副本，这里是同帧兜底 + 幂等扫尾。
	_sweep_room_copies()


## 把已经建好的门搬到 TSCN 给的手摆位置。
##
## 与 `_shift_door()` 的区别：那个是「沿法线外推一小段」，这个是「换到另一个位点」，
## 方向和距离都不一定沿法线。
##
## **落点不跟着门走**（2026-10-19 修正，业主「按 E 传送到空房间」）。
## 曾经这里写的是「落点同样要跟着走」，理由是「出口侧落点就定在门前面」。那个理由
## 在改版后已经不成立：入口/出口门的落点都是**子图房间中心**（`points[0]` /
## `points[last]`，世界 x≈1015），跟门在主图哪个墙角毫无关系。手摆把门挪了 39m，
## 落点被同一个 delta 推出去 39m —— 人直接落在子图房间外 39m 的空中往下掉，
## 看上去就是「传送到一个空房间，支线没装配」。门挪多少，落点一寸都不该动。
func _rebase_door(site: Dictionary) -> void:
	var door := _doors.get(str(site.get("site_id", ""))) as Node3D
	if door == null or not is_instance_valid(door):
		return
	# 房间 TSCN 里那扇手动门此刻也在场（房间是实例化 TSCN 的）。
	# 位点是晚一步才读到的（bootstrap 时房间还没装配），所以刚才已经建了一扇 ——
	# 把房间里那扇摘掉，免得同一处叠两樘门。位置已经读到 `site` 里，不会丢。
	_drop_room_duplicate_door(site)
	var target := site.get("position", Vector3.ZERO) as Vector3
	door.global_position = target
	var normal := site.get("normal", Vector3.FORWARD) as Vector3
	if normal != Vector3.ZERO:
		door.rotation.y = atan2(normal.x, normal.z)
	# 落点保持原值：它指向子图房间中心，与这扇门在主图的哪个位置无关。


## 位点外推后，把门节点推离墙面。
##
## **只挪门，不挪落点**（同 `_rebase_door` 的理由）。外推量最大 0.4m，对子图落点
## 来说同样是错误位移；宁可让落点纹丝不动，也不要把「门贴在墙上」这件事
## 传染给「人落在哪里」。
func _shift_door(site: Dictionary) -> void:
	var door := _doors.get(str(site.get("site_id", ""))) as Node3D
	if door == null or not is_instance_valid(door):
		return
	var offset := float(site.get("wall_push_m", 0.0))
	if offset <= 0.0:
		return
	var normal := site.get("normal", Vector3.FORWARD) as Vector3
	door.global_position -= normal * offset
	# 门被推离墙面后，背后会留出一段空当。让门自己补一个「安装箱」填住，
	# 否则从侧面看会像一块悬空的板（门叶原点契约是 wall_face_bottom_center）。
	door.call("set_mount_depth", offset)


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
	_build_room_index()
	_read_authored_doors()
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
		var entry := {
			"site_id": str(site.get("site_id", "")),
			"pair_id": int(site.get("pair_id", -1)),
			"role": str(site.get("role", "")),
			"wall": wall,
			"lane": lane,
			"normal": normal,
			"position": point,
			"authored_position": point,
			"room_id": str(record.get("id", "")),
		}
		# 房间 TSCN 里如果已经手动摆好了这扇门（业主在编辑器里拖的），
		# 就用他的手摆位置与朝向 —— 不再按数据推算，也不再自动外推。
		# 「数据位点」于是退回成**没摆过时的兜底**，两套真源不会打架。
		var manual := _apply_authored_door(entry)
		# 位点解析出来的只是「房间包围盒边界」，那不是墙面 —— 墙件原点虽坐在
		# ±dimensions/2 上，但墙厚是**向房间外侧**展开的，可视面还会再往房间里
		# 探出 0.3~0.6m。木板只有 0.142m 厚，直接装在这个点上会被墙体包住：
		# 远征 01 的 S1 实测墙体可视面凸出 0.465m，玩家看到的是一整面平墙，
		# 业主连续两局「打到第 4 间完全找不到入口」就是这个原因。
		# ⇒ 装配前先按实测墙面外沿把整樘门（门叶 + 木板）推到墙外面。
		# 手动摆的只**量**不推：位置是业主要的，动它等于把手调抹掉。
		_push_site_out_of_wall(entry, not manual)
		_measure_site_blocker(entry)
		_measure_visual_cover(entry)
		result.append(entry)
	return result


## 把 TSCN 里手动摆的暗门变换写进位点。返回是否命中。
##
## 门节点在 TSCN 里是预制体实例，其 `transform` 是**房间局部**；位点要的是**世界坐标**，
## 所以必须乘一次房间自己的 `global_transform` —— 少这一步，门会落在房间原点附近
## （远征 01 实测差 98~256m，正好是各房间的世界平移量）。
##
## 朝向取门节点的 +Z：`SecretDoor3D` 装配时约定
## `rotation.y = atan2(normal.x, normal.z)`，即 +Z 轴对准朝外法线。
func _apply_authored_door(site: Dictionary) -> bool:
	var site_id := str(site.get("site_id", ""))
	var room_id := str(site.get("room_id", ""))
	var authored_value: Variant = _authored_doors.get(site_id)
	if authored_value == null:
		return false
	var authored := authored_value as Dictionary
	# 同名位点只认自己房间那一扇：`S1` 这种短名跨楼重名时不会张冠李戴。
	if str(authored.get("room_id", "")) != room_id:
		return false
	var room := _room_nodes.get(room_id) as Node3D
	if room == null:
		return false
	var local := authored.get("room_local", Transform3D.IDENTITY) as Transform3D
	var world_xform := room.global_transform * local
	var normal := world_xform.basis.z
	normal.y = 0.0
	if normal.length() > 0.001:
		site["normal"] = normal.normalized()
	site["position"] = world_xform.origin
	site["authored_position"] = world_xform.origin
	site["manual_site"] = true
	return true


## 从房间 TSCN 里读手动摆放的暗门节点。
##
## 为什么读 TSCN 而不是读运行时节点：房间在运行时是**按 `authored_layout_instances`
## 现搭**的，TSCN 只是导出快照 —— 所以这一层读取是「把编辑器的意图带回运行时」的
## 唯一通道。`static_layout_scene_path` 已在 `DungeonRoom3D` 上，直接 load 即可
## （导出时它本来就在缓存里）。
##
## 只认根层子节点（`parent = "."`）：门的 `DoorLeaf` / `Boards` 也是 `Node3D`，
## 往下递归会把它们当成两扇门。
func _read_authored_doors() -> void:
	_authored_doors.clear()
	for room_id_value in _room_nodes:
		var room_id := str(room_id_value)
		var room := _room_nodes[room_id] as Node3D
		if room == null:
			continue
		var path := str(room.get("static_layout_scene_path"))
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var state := packed.get_state()
		if state == null:
			continue
		var root_xform := Transform3D.IDENTITY
		for property_index in range(state.get_node_property_count(0)):
			if str(state.get_node_property_name(0, property_index)) == "transform":
				root_xform = state.get_node_property_value(0, property_index) as Transform3D
		for index in range(state.get_node_count()):
			var node_name := str(state.get_node_name(index))
			if not node_name.begins_with("SecretDoor"):
				continue
			# 只认根层：`get_node_path()` 给的是**节点自己的完整路径**（`./SecretDoor_S1`），
			# 所以「根层」= 只有一段名字（斜杠恰好 1 个）。
			var node_path := str(state.get_node_path(index))
			if node_path.count("/") != 1:
				continue
			var xform := Transform3D.IDENTITY
			for property_index in range(state.get_node_property_count(index)):
				if str(state.get_node_property_name(index, property_index)) == "transform":
					xform = state.get_node_property_value(index, property_index) as Transform3D
			var site_id := node_name.trim_prefix("SecretDoor_")
			if site_id == node_name:
				continue
			_authored_doors[site_id] = {
				"room_local": root_xform * xform,
				"room_id": room_id,
			}


## 扫一遍宿主树，建 `room_id -> 房间节点`。
##
## 只在 `build()` 之前调用一次：那时主图房间已装配完、子图还没建，
## 所以不会把 `secret_*` 混进来。**必须从场景根往下扫**：本节点挂在
## `Dungeon3D`（`SecretBranches`），而远征的房间在 `Blocks/Expedition/` 下，
## 既不是本节点的子节点，也不一定是 `Dungeon3D` 的子节点。
func _build_room_index() -> void:
	_room_nodes.clear()
	var host: Node = self
	while host.get_parent() != null:
		host = host.get_parent()
	_index_rooms(host)


func _index_rooms(node: Node) -> void:
	for child in node.get_children():
		var room_id_value: Variant = child.get("room_id")
		if room_id_value != null:
			var room_id := str(room_id_value)
			if not room_id.is_empty() and not room_id.begins_with("secret_") and not _room_nodes.has(room_id):
				_room_nodes[room_id] = child
		_index_rooms(child)


## 把位点从「房间边界」推到「墙面可视外沿之外」。
##
## 为什么必须实测而不是写死一个偏移：每间房的墙厚不一样（远征 01 里
## room_03 凸 0.465m，room_07 几乎不凸）。写死小了照样被埋，写死大了
## 整樘门会浮在房间当中。
##
## 只认名字/来源里带 `wall` 的网格，**不认家具**：工作台、货架也贴墙摆，
## 但它们不是「看得见门」的基准面；把它们算进来会把门推到家具外面。
##
## `apply = false` 时**只量不推**（手动摆位走这条）：仍然算出墙面在哪、
## 门凸出多少，让 A23 与 `debug_snapshot()` 能看到「这一摆是不是埋进墙里」，
## 但绝不改业主亲手放的位置。
func _push_site_out_of_wall(site: Dictionary, apply: bool = true) -> void:
	var room := _room_nodes.get(str(site.get("room_id", ""))) as Node3D
	if room == null:
		return
	var point := site.get("position", Vector3.ZERO) as Vector3
	var normal := site.get("normal", Vector3.FORWARD) as Vector3
	if normal == Vector3.ZERO:
		return
	var base := point.dot(normal)
	# `normal` 是**朝房间外**的法线（`_wall_normal("south") = +Z`），房间内部在 -normal 侧。
	# 所以「墙面挡在门前面」看的是**最小**投影，不是最大：
	# 远征 01 S1 的墙体区间 -20.465 ~ -19.850，-20.465 才是拦住玩家的那一面。
	var face := INF
	# 必须用 `VisualInstance3D` + `_visual_world_box()`：远征的墙件有一部分是用
	# `MultiMeshInstance3D` 铺出来的，只扫 `MeshInstance3D` 会漏掉整面墙，
	# 于是位点以为「没找到墙」而不外推（S2/S4 就是这样只凸了最小量）。
	for node in room.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		if visual == null or not _is_wall_mesh(visual):
			continue
		var box := _visual_world_box(visual)
		if box.size == Vector3.ZERO:
			continue
		if not _box_near_point(box, point):
			continue
		for index in range(8):
			face = minf(face, box.get_endpoint(index).dot(normal))
	if face == INF:
		if not apply:
			# 手动摆位 + 认不出墙件（S2/S4 所在的东/西墙是转角壳体，名字里没有
			# wall，`_is_wall_mesh()` 认不出来）。位置本身来自装配时的外推，
			# 按装配常量记一笔，并标记成**估计值** —— A23 照常判，但 NOTE 会说明
			# 这个数不是实测的。
			site["protrude_m"] = WALL_FACE_CLEARANCE_M
			site["protrude_estimated"] = true
			return
		# 没认到墙件（房型用别的方式拼墙）：不能当「已就位」放过。
		# 按正式凸出量整体前推，宁可多凸一点，也不要再留一扇齐平的隐形门。
		site["wall_push_m"] = WALL_FACE_CLEARANCE_M
		site["protrude_m"] = WALL_FACE_CLEARANCE_M
		site["position"] = point - normal * WALL_FACE_CLEARANCE_M
		return
	# 凸出量固定 = WALL_FACE_CLEARANCE_M。算出负数说明门本来就在墙面前 ≥0.40m，
	# 那就不动它（offset 夹到 0），绝不为了「统一数值」把门往墙里推。
	var offset := maxf(base - face + WALL_FACE_CLEARANCE_M, 0.0)
	site["wall_face_m"] = face
	if not apply:
		# 手动摆位：只记录「门心比墙面外凸多少」，一个毫米都不挪。
		# `normal` 朝房间外、房间内部在 -normal 侧 ⇒ 墙面最凸进房间的那一层是
		# **最小**投影，门心投影比它更小才叫「露在墙外」，两者相减即凸出量。
		site["wall_push_m"] = 0.0
		site["protrude_m"] = face - base
		return
	var protrude := face - (base - offset)
	site["wall_push_m"] = offset
	site["protrude_m"] = protrude
	site["position"] = point - normal * offset


## 门前 2.4m 内有没有实体家具挡着（工作台、货架…）。
##
## 位点是**固定数据**，这里不换槽也不挪家具 —— 只把挡路件的名字带回去，
## 由验收/探针报红，让人回去改 `secret_site.lane`。静默通过会让「门在那里，
## 但被工作台挡住」这种问题一路漏到玩家手里（room_06 的 S2 就是这样）。
func _measure_site_blocker(site: Dictionary) -> void:
	var point := site.get("position", Vector3.ZERO) as Vector3
	var normal := site.get("normal", Vector3.FORWARD) as Vector3
	if normal == Vector3.ZERO:
		return
	var world := get_world_3d()
	if world == null:
		return
	var space := world.direct_space_state
	if space == null:
		return
	var from := point + Vector3(0.0, SITE_CLEAR_EYE_Y_M, 0.0)
	# 从门前 0.5m 往里量到 2.4m：这个区间正好是玩家站着看门的位置。
	var query := PhysicsRayQueryParameters3D.create(
		from - normal * 0.5, from - normal * SITE_CLEAR_DEPTH_M
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	site["blocker"] = _node_label(hit.get("collider") as Node)


## 门前**肉眼**是否被盖住 —— 与 `_measure_site_blocker()` 的碰撞射线互补。
##
## 为什么射线不够：墙体/装饰的**碰撞代理盒**往往比美术面薄得多（有的甚至只在
## 墙平面留一层壳）。`room_06` 东墙上一个 5.15×5.15×11.9 的转角壳体把整樘门
## 包在肚子里，射线照样一路穿到门板 → A21 判"可见"，玩家却只看到一面平墙。
##
## 外推也救不了它：要推出这个壳得挪 5m，门就飘在房间当中了。所以这类位点
## **不修正、只报错** —— 槽位本身不合法，必须回数据里换 `lane`。
func _measure_visual_cover(site: Dictionary) -> void:
	var room := _room_nodes.get(str(site.get("room_id", ""))) as Node3D
	if room == null:
		return
	var point := site.get("position", Vector3.ZERO) as Vector3
	var normal := site.get("normal", Vector3.FORWARD) as Vector3
	if normal == Vector3.ZERO:
		return
	var tangent := _wall_tangent(str(site.get("wall", "")))
	if tangent == Vector3.ZERO:
		return
	var base := point.dot(normal)
	var along := point.dot(tangent)

	var cover_name := ""
	var cover_m := 0.0
	for node in room.find_children("*", "VisualInstance3D", true, false):
		# 门自己也是「墙面前凸出的一坨」，不排除的话 A22 会一直报
		# 「整樘门被 ImportedModel 盖住（凸出 0.14m）」—— 那 0.14m 是木板厚度本身。
		if _is_secret_door_part(node):
			continue
		var box := _visual_world_box(node as VisualInstance3D)
		if box.size == Vector3.ZERO:
			continue
		# 竖直方向必须是"门高主体"：地脚线、屋檐这类件不算覆盖。
		if box.end.y < 1.2 or box.position.y > 2.0:
			continue
		if Vector2(box.get_center().x - point.x, box.get_center().z - point.z).length() > 4.0:
			continue
		var lo := INF
		var hi := -INF
		var t_lo := INF
		var t_hi := -INF
		for index in range(8):
			var corner := box.get_endpoint(index)
			var proj := corner.dot(normal)
			lo = minf(lo, proj)
			hi = maxf(hi, proj)
			var along_proj := corner.dot(tangent)
			t_lo = minf(t_lo, along_proj)
			t_hi = maxf(t_hi, along_proj)
		# 只"擦到门边"不算盖住：沿墙方向必须真的压过门宽的大部分。
		var overlap := minf(t_hi, along + SITE_COVER_HALF_W_M) - maxf(t_lo, along - SITE_COVER_HALF_W_M)
		if overlap < SITE_COVER_HALF_W_M * 1.2:
			continue
		# 往房间内**凸到门前面**多少（normal 朝房间外，所以越小越靠房间内）。
		var front := base - lo
		if front <= 0.05:
			continue
		if front > cover_m:
			cover_m = front
			cover_name = _node_label(node)

	if cover_name.is_empty():
		site.erase("covered_by")
		site.erase("cover_m")
		return
	site["covered_by"] = cover_name
	site["cover_m"] = cover_m
	# 只在第一次发现时告警，`settle_sites()` 会被调多次，别刷屏。
	if not bool(site.get("_cover_warned", false)):
		site["_cover_warned"] = true
		push_warning(
			"[SecretBranch3D] 位点 %s（%s）整樘门被 %s 的实心外壳盖住（凸出 %.2fm）—— 这个槽位不合法，必须换 lane"
			% [
				str(site.get("site_id", "")), str(site.get("room_id", "")),
				cover_name, cover_m,
			]
		)


## 绘制件的世界包围盒：`MultiMeshInstance3D` 也要认 —— 只扫 `MeshInstance3D`
## 会把整片用 MultiMesh 铺出来的墙漏掉（漏一片就等于判"门前没东西"）。
func _visual_world_box(node: VisualInstance3D) -> AABB:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			return AABB()
		return mesh_node.global_transform * mesh_node.get_aabb()
	if node is MultiMeshInstance3D:
		var multi := node as MultiMeshInstance3D
		if multi.multimesh == null or multi.multimesh.mesh == null:
			return AABB()
		return multi.global_transform * multi.multimesh.get_aabb()
	return AABB()


## 一层层往上找，认出「这是墙」。
func _is_wall_mesh(node: Node) -> bool:
	var cursor := node
	for _i in range(4):
		if cursor == null:
			break
		if str(cursor.name).to_lower().contains("wall"):
			return true
		if cursor is Node3D and (cursor as Node3D).scene_file_path.to_lower().contains("wall"):
			return true
		cursor = cursor.get_parent()
	return false


## 这块可视件是不是**暗门自己**的一部分（门叶 / 木板 / 安装箱）。
##
## 房间 TSCN 里现在直接摆着暗门（业主可手调），运行时房间又是实例化这个 TSCN 的，
## 所以门口那几件几何确实在房间子树里。它们是「门」，不是「挡住门的墙」。
func _is_secret_door_part(node: Node) -> bool:
	var cursor := node
	for _i in range(4):
		if cursor == null:
			return false
		if str(cursor.name).begins_with("SecretDoor"):
			return true
		cursor = cursor.get_parent()
	return false


## 墙件长 5m，位点可能落在段的端头：中心距放宽到 3.2m 才不漏。
func _box_near_point(box: AABB, point: Vector3) -> bool:
	var center := box.get_center()
	if Vector2(center.x - point.x, center.z - point.z).length() > 3.2:
		return false
	# 门洞高度区间：把只有地脚、屋檐之类的件排除掉。
	return box.end.y > 0.8 and box.position.y < 2.4


## 碰撞体 → 祖先生成件名，便于人眼认出「是哪个工作台挡的」。
## 命名前缀两种都认：`ENV-`/`DB-`（装配件）与 `ENV_`/`Imported_`（美术导入件）——
## 只认横杠那版会把 `ENV_TOWER_CORNER_L_5M` 报成它爹 `ImportedModel`，等于没说。
func _node_label(node: Node) -> String:
	var cursor := node
	for _i in range(4):
		if cursor == null:
			break
		var name_text := str(cursor.name)
		if (
			name_text.begins_with("ENV-") or name_text.begins_with("DB-")
			or name_text.begins_with("ENV_") or name_text.begins_with("Imported_")
		):
			return name_text
		cursor = cursor.get_parent()
	if node == null:
		return ""
	return str(node.get_parent().name if node.get_parent() != null else node.name)



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
		var state := value as Dictionary
		# 落点用 `landing`（可走面上的点），**不是** `center`（包围盒几何中心）。
		# L 形房的几何中心会落在凹口里 —— 那块刻意没有承重板，人一落下去就掉出关卡。
		points.append(state.get("landing", state.get("center", Vector3.ZERO)))
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
##
## 分两趟走：**先算全链的门位槽，再逐间建房**。
## 为什么不能边建边算：`lane` 必须整条链共用一个（走廊是直线、门要同轴），
## 而槽的合法性要同时看**每一间**的壳（L 形凹口没有砖也没有外墙）。
## 逐间各算一个的话，`corridor_45x40`（L 形）会把门算到凹口上 ——
## 玩家从走廊走进来直接站在房间外（业主 2026-10-22「角色会跑到房间外面去」）。
func _build_branch_rooms(root: Node3D, pair_id: int, count: int) -> Array:
	var picked := _pick_branch_templates(pair_id, count)
	var origin := _branch_origin(pair_id)
	# —— 第一趟：只算几何与门位，不建节点 ——
	var plans: Array = []
	var cursor_x := origin.x
	for index in range(picked.size()):
		var entry := picked[index] as Dictionary
		var size := entry.get("size", BRANCH_TEMPLATE_FALLBACK[BRIDGE_TEMPLATE_ID]) as Vector2
		var template_id := str(entry.get("template_id", ""))
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
		var path := _shared_layout_path(template_id)
		plans.append({
			"index": index,
			"size": size,
			"template_id": template_id,
			"path": path,
			"doors": doors,
			"door_targets": door_targets,
			"center": Vector3(cursor_x + size.x * 0.5, 0.0, origin.y),
			"layout_deg": _shared_shell_alignment_deg(path, size, doors),
		})
		cursor_x += size.x + ROOM_GAP_M
	# —— 全链一个门位槽 ——
	var lane := _solve_chain_lane(plans)
	# —— 第二趟：建房 ——
	var rooms: Array = []
	for value in plans:
		var plan := value as Dictionary
		var index := int(plan["index"])
		var size := plan["size"] as Vector2
		var center := plan["center"] as Vector3
		var room := _spawn_branch_room(
			root, "secret_%d_%d" % [pair_id, index], center, size,
			plan["doors"] as Array, plan["door_targets"] as Dictionary,
			index, lane, str(plan["template_id"])
		)
		rooms.append({
			"room": room,
			"center": center,
		# 传送落点 = 可走面上离中心最近的点（L 形的几何中心会落在凹口里）。
		# 由 `_spawn_branch_room()` 算好并登记在 `_branch_rooms` 里 —— 那里撤离房也走同一条，
		# 落点只有一处口径。这里只取，不重算（重算会多遍历一遍全部网格件）。
		"landing": ((_branch_rooms.get(room.room_id, {}) as Dictionary).get("landing", center) as Vector3),
			"size": size,
			"index": index,
			"lane": lane,
			"template_id": str(plan["template_id"]),
		})
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
	# 壳的朝向必须**先**下发：`_align_static_layout_to_room()` 在 `_build_shell()`
	# 里按这条 meta 整体转壳，门洞与门扇是它之后才建的。晚一步就会「墙转过去了、
	# 门还按旧方位开」。
	var layout_deg := _shared_shell_alignment_deg(
		str(room.static_layout_scene_path), size, doors
	)
	if not is_zero_approx(layout_deg):
		room.set_meta("template_rotation_deg", layout_deg)
		room.set_meta("shared_shell_alignment_deg", layout_deg)
	room.position = center
	root.add_child(room)
	room.ensure_shell_built()
	# 脚下必须是实的（2026-10-21 业主「支线的装配有问题，会掉下去」），
	# 且只盖在**真实地砖**上（2026-10-22 业主「角色会跑到房间外面去」）。
	_ensure_floor_support(root, room)
	# 落点必须落在**可走面**上：包围盒几何中心对 L 形房会落在凹口里（那里刻意没板）。
	# 算在这里而不是调用方，是因为**撤离房也走这个函数**（它不走 `_build_branch_rooms`），
	# 落点只在一处算才不会两套口径。
	var landing := _branch_landing_point(room)
	room.set_stream_state(DungeonRoom3D.STREAM_SHELL_READY)
	# 进房上报：子图房间不在 `_records` 里，`Dungeon3D._on_room_entered` 那条链
	# 收不到它们。挂到房间自带的 `player_entered`（由 `RoomTrigger` 的 Area3D 发），
	# 上层据此切「当前房间」并按编成刷怪。
	_branch_rooms[room_id] = {
		"room": room, "combat": encounter, "entered": false, "landing": landing,
	}
	room.player_entered.connect(_on_branch_room_player_entered)
	return room


## 共享房壳的**摆放朝向**（0 / 90 / 180 / 270）。
##
## 为什么子图必须自己算这个角度：主路房间的壳朝向由
## `DungeonRoom3D._static_layout_alignment_delta_deg()` 拿「布局实例清单 × 关卡房表」
## 做几何配准得出；子图房**不在 `_records` 里、没有清单**，那条路会直接回落到
## `template_rotation_deg`（子图从来没设过 ⇒ 恒 0）。结果是壳按烘焙朝向原样摆进
## 房间：`corridor_45x40` 的壳烘焙成 40×45、房间是 45×40 ⇒ 四面墙整体偏出 2.5 m、
## 门墙落在北墙而房间的门在东/西墙（实测墙探针 155/170 打空）。
##
## 判据只有两条，都能量，不靠猜：
##   ① **足迹**：壳美术在自身局部系里的 AABB 必须与本间 `size` 吻合；
##      转置了就只能靠 90°/270°（两个角度足迹相同，所以还要 ②）；
##   ② **门侧**：壳里烘焙的门墙（`snapshot_tower_wall_door_offset_<side>`）
##      转过去之后要落在本间真的开门的那些边上，重合越多越好。
##
## 两条都不成立时返回 0（**保守：不转**）。宁可维持烘焙朝向，也不瞎转。
func _shared_shell_alignment_deg(path: String, size: Vector2, doors: Array) -> float:
	if path.is_empty() or size.x <= 0.1 or size.y <= 0.1:
		return 0.0
	var footprint: Dictionary = _shared_shell_footprint(path)
	var art_size := footprint.get("size", Vector2.ZERO) as Vector2
	if art_size.x <= 0.1 or art_size.y <= 0.1:
		return 0.0
	var baked_door_sides: Array = footprint.get("door_sides", []) as Array
	var candidates: Array[float] = []
	for deg in [0.0, 90.0, 180.0, 270.0]:
		var rotated := art_size
		if not is_zero_approx(fposmod(deg, 180.0)):
			rotated = Vector2(art_size.y, art_size.x)
		if (
			absf(rotated.x - size.x) <= SHELL_FIT_TOLERANCE_M
			and absf(rotated.y - size.y) <= SHELL_FIT_TOLERANCE_M
		):
			candidates.append(deg)
	if candidates.is_empty():
		push_warning(
			"[SecretBranch3D] 房壳 %s 的足迹 %.1fx%.1f 与房间 %.1fx%.1f 对不上，维持烘焙朝向"
			% [path.get_file(), art_size.x, art_size.y, size.x, size.y]
		)
		return 0.0
	if candidates.size() == 1:
		return candidates[0]
	# ② 门侧：把烘焙门墙按候选角转过去，数有几个落在本间要开的边上。
	var wanted: Array = []
	for direction in doors:
		wanted.append(str(direction))
	var best_deg := candidates[0]
	var best_hits := -1
	for deg in candidates:
		var hits := 0
		for side_value in baked_door_sides:
			var mapped := _rotate_wall_side(str(side_value), deg)
			if wanted.has(mapped):
				hits += 1
		if hits > best_hits:
			best_hits = hits
			best_deg = deg
	return best_deg


## 壳美术的足迹、**烘焙门墙朝向**与**真砖格**（同一份壳只量一次）。
##
## 量法：实例化后把每件 `MeshInstance3D` 的局部变换沿父链乘到壳原点，取 AABB。
## 不依赖入树、不跑物理，代价是一次实例化 —— 每种模板只做一次（缓存）。
##
## `tiles` 是**地砖格心**（壳局部，5 m 格）：判「某处地面上有没有砖」用。
## 为什么需要它：`corridor_45x40` 是 L 形，凹口那 30×25 没有砖也没有外墙；
## 门位若按房间中线取，就会开在凹口上（那一段没有墙），玩家从走廊走进来
## 直接落在房间外（业主 2026-10-22「角色会跑到房间外面去」）。
func _shared_shell_footprint(path: String) -> Dictionary:
	if _shell_footprints.has(path):
		return _shell_footprints[path] as Dictionary
	var result := {"size": Vector2.ZERO, "door_sides": [] as Array, "tiles": [] as Array}
	var packed := load(path) as PackedScene
	if packed == null:
		_shell_footprints[path] = result
		return result
	var instance := packed.instantiate()
	if instance == null:
		_shell_footprints[path] = result
		return result
	var box := AABB()
	var started := false
	var tiles: Array = []
	for node in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		if _hidden_in_shell(mesh, instance):
			continue
		var local := Transform3D.IDENTITY
		var probe: Node = mesh
		while probe != null and probe != instance:
			if probe is Node3D:
				local = (probe as Node3D).transform * local
			probe = probe.get_parent()
		var part: AABB = local * mesh.mesh.get_aabb()
		if not started:
			box = part
			started = true
		else:
			box = box.merge(part)
		# 地砖 = **水平薄片且顶面贴 y=0** 的件（几何判据，不认名字：共享壳是嵌套
		# 子场景，`TILE_R00_C00` 在更深的层级，按名字一律拿不到）。
		if part.size.y <= SHELL_TILE_MAX_THICKNESS_M and absf(part.end.y) <= SHELL_TILE_MAX_TOP_OFFSET_M:
			# ⚠️ 存**原始砖心**，不归整。实测 `corridor_45x40` 的砖心是
			# `-17.5 / -12.5 / … / +17.5`（= 2.5 + 5n），**不是** 5 的整数倍 ——
			# 拿 `roundf(c/5)*5` 归整会把 2.5→0、7.5→10，格心整体漂 2.5 m，
			# 门位判据于是在「有砖 / 没砖」之间给出反向答案（实测把凹口边上的 +2.5 判成合法）。
			# 不去重也无所谓：一块砖最多几片网格，判 4 个门点的开销可以忽略。
			var center := part.get_center()
			tiles.append(Vector2(center.x, center.z))
	var door_sides: Array = []
	for node in instance.find_children("*", "", true, false):
		for meta_name in node.get_meta_list():
			var key := str(meta_name)
			if not key.begins_with("snapshot_tower_wall_door_offset_"):
				continue
			var side := key.trim_prefix("snapshot_tower_wall_door_offset_")
			if not door_sides.has(side):
				door_sides.append(side)
	if started:
		result["size"] = Vector2(box.size.x, box.size.z)
	result["door_sides"] = door_sides
	result["tiles"] = tiles
	instance.free()
	_shell_footprints[path] = result
	return result


## 壳里**不会出现在游戏里**的件：`editor_preview_only` 子树（`_build_shell` 会把它们
## 置 `visible = false`）与自身隐藏的节点。量足迹时必须剔掉，否则量出来比房间大
## 一圈（实测 office 壳 40.3 → 41.1，正是差了一件预览件）。
func _hidden_in_shell(node: Node, shell_root: Node) -> bool:
	var probe: Node = node
	while probe != null and probe != shell_root:
		if probe is Node3D and not (probe as Node3D).visible:
			return true
		if bool(probe.get_meta("editor_preview_only", false)):
			return true
		probe = probe.get_parent()
	return false


## 绕 Y 转 `deg` 之后，某一面墙的朝向变成哪一面（轴约定与 `DungeonRoom3D` 同一套：
## 北 = -Z、南 = +Z、东 = +X、西 = -X）。
func _rotate_wall_side(side: String, deg: float) -> String:
	var normal := Vector3.ZERO
	match side:
		"north":
			normal = Vector3(0, 0, -1)
		"south":
			normal = Vector3(0, 0, 1)
		"east":
			normal = Vector3(1, 0, 0)
		"west":
			normal = Vector3(-1, 0, 0)
		_:
			return side
	var rotated := Basis(Vector3.UP, deg_to_rad(deg)) * normal
	if absf(rotated.x) >= absf(rotated.z):
		return "east" if rotated.x > 0.0 else "west"
	return "south" if rotated.z > 0.0 else "north"


## 子图房间的**承重地板**：顶面贴 `y = 0` 的静态盒，逐块盖在**真实地砖**上。
##
## 为什么必须补（业主 2026-10-21：「装配的房间有问题，会掉落。支线的」）：
##   主路房间脚下之所以踩得实，靠的**不是**房间自带的地砖，而是
##   `TowerFloorStage3D._build_support()` 按整层范围铺的 `FloorSupport` 大板 ——
##   实测 room_01 的 440 个俯视采样点里 **330 格踩的是 FloorSupport**、只有 102 格
##   踩到美术件。共享房壳只带来**美术地砖**：`corridor_45x40` 42 块 5m 砖 = 1050 ㎡，
##   而房间是 45×40 = 1800 ㎡；`bridge_60x50` 更少。
##   子图整条链挂在主图外 +1000 m（`BRANCH_ORIGIN_X_M`），`FloorSupport` 够不着 ⇒
##   玩家按 E 落在子图房里，脚下 66%~78% 的位置是虚空，一路掉出关卡。
##
## 🔴 **按砖铺、不按包围盒铺**（业主 2026-10-22：「角色会跑到房间外面去」）。
##   第一版按 `size` 铺了一整块矩形 —— 对 L 形 `corridor_45x40` 等于把 30×25 的**凹口**
##   也填成了实心，实测 720 ㎡「能站但已经在房间外」：玩家从凹口那侧的门走出去，
##   脚下居然有地板，一路走到房间外面还是不掉，看上去就是「场景漂了、人跑出房间」。
##   现在只盖真正有地砖的位置（地砖就是房间的可走区）。
##
## 口径与主路逐项对齐（不另立一套）：
##   · 层 1 / 掩码 0 —— 与 `FloorSupport` 同层，射线与角色落地判定都看得见；
##   · `PROCESS_MODE_ALWAYS` —— 承重板不能随流送窗口退出物理空间（同主路口径）；
##   · 厚度 `FLOOR_THICKNESS`（0.30）、盒心下移半个厚度 ⇒ **顶面正好在 y = 0**，
##     与地砖顶面共面，玩家胶囊落点不需要为它加任何偏移。
##   · 每块向外放 `BRANCH_FLOOR_SUPPORT_OVERLAP_M`，吃掉相邻砖之间的建模缝。
##
## 一件砖都量不到时（美术缺失 / 回退程序化灰盒）**退回整矩形**：宁可退化，
## 也不能让玩家掉出关卡。
func _ensure_floor_support(root: Node3D, room: DungeonRoom3D) -> void:
	if root == null or not is_instance_valid(root) or room == null:
		return
	var body := root.get_node_or_null(BRANCH_FLOOR_SUPPORT_NAME) as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = BRANCH_FLOOR_SUPPORT_NAME
		# 承重板与主路 `FloorSupport` 同一个理由：跨流送窗口常驻。
		body.process_mode = Node.PROCESS_MODE_ALWAYS
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("branch_floor_support", true)
		root.add_child(body)
	var boxes := _branch_floor_boxes(room)
	for box in boxes:
		var shape := BoxShape3D.new()
		shape.size = Vector3(box.size.x, BRANCH_FLOOR_SUPPORT_THICKNESS_M, box.size.z)
		var collision := CollisionShape3D.new()
		collision.name = "%s_Support_%02d" % [str(room.room_id), body.get_child_count()]
		collision.shape = shape
		var center := box.get_center()
		collision.position = Vector3(center.x, -BRANCH_FLOOR_SUPPORT_THICKNESS_M * 0.5, center.z)
		body.add_child(collision)
	if OS.get_environment("SS2_BRANCH_DEBUG") == "1":
		print("[SecretBranch3D] 承重盒 %s：%d 格" % [str(room.room_id), boxes.size()])


## 该房间的**传送落点**：真实可走面上、离房间几何中心最近的那个砖格心。
##
## 为什么不能直接用 `room.global_position`：那是**包围盒几何中心**，
## 而 `corridor_45x40` 是 L 形 —— 45×40 的包围盒中心 (0,0) 正落在凹口里
## （实测 `secret_0_0` 的中心就在凹口内）。玩家按 E 落下去等于落在房间外，
## 凹口又刻意没有承重板 ⇒ 直接掉出关卡，看上去就是「场景漂了、人飘在房间外」。
##
## 口径：**无条件**取「有砖的格心」里离中心最近的一个。
## 不做「中心若压在砖上就原样用中心」那支 —— 那种模糊判定会在砖块边界上
## 给出不确定答案（中心离砖边 0.0 m，差一个容差就翻脸），实测正是它让
## `secret_0_2` 的落点判成「在房间外」。矩形房的中心本来就落在格心上，位移为 0。
## 一块砖都量不到时（美术缺失）退回中心（兜底，见 `_ensure_floor_support()`）。
func _branch_landing_point(room: DungeonRoom3D) -> Vector3:
	var center := room.global_position
	var boxes := _branch_floor_boxes(room)
	if boxes.size() <= 1:
		return center
	var best := center
	var best_distance := INF
	for box in boxes:
		var box_center := box.get_center()
		var candidate := Vector3(box_center.x, center.y, box_center.z)
		var distance := Vector2(candidate.x - center.x, candidate.z - center.z).length()
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


## 该房间**真实可走面**的世界 AABB 列表（按 5 m 格聚合，一格一个盒）。
##
## 只认「水平薄片 + 顶面贴 y = 0」的网格件 —— 不认名字：子图的共享壳是**嵌套子场景**，
## `TILE_R00_C00` 在更深的层级，按实例根名字一律拿不到（实测一件都量不到）。
## 墙 11.9 m 高、家具更厚，都被这两个判据挡在外面。
##
## ⚠️ **必须按格聚合，不能一件网格一个盒**：一块地砖在美术里由好几片网格组成
## （面板 + 缝条 + 压条），实测 7 间房会铺出 **7288 块**承重盒，物理广相每帧都在扫。
## 归格口径与砖心一致：格心 = `-half + (k + 0.5) × 5`。
## 为什么是这个式子而不是「5 的整数倍」：砖心随该轴**块数奇偶**变 ——
## 40 宽（偶数块）砖心是 2.5 + 5n（-17.5 / -12.5 / …），
## 45 深（奇数块）砖心是 5n（-20 / -15 / …）。
## 统一写成 `-half + (k+0.5)×5` 两种都落得准。
##
## 量不到任何砖时返回**整块包围盒**（兜底，见 `_ensure_floor_support()` 头注释）。
func _branch_floor_boxes(room: DungeonRoom3D) -> Array[AABB]:
	var dims := room.get_dimensions()
	var center := room.global_position
	var half_x := dims.x * 0.5
	var half_z := dims.y * 0.5
	var overlap := BRANCH_FLOOR_SUPPORT_OVERLAP_M
	# 格索引 → 该格是否真有砖。
	var tiles: Array[AABB] = []
	for node in room.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		# ⚠️ 不能用 `is_visible_in_tree()`：建房那一刻整棵支线树**通常还没入树**
		# （`build()` 早于父场景挂载），`is_visible_in_tree()` 会一律返回 false ⇒
		# 一块砖都量不到 ⇒ 兜底成整矩形 ⇒ 传送落点退回几何中心 ⇒ L 形的中心
		# 正好落在凹口里，玩家按 E 掉出关卡。只沿父链看 `visible` 就够了。
		if _hidden_in_shell(mesh, room):
			continue
		var world := _mesh_world_aabb(mesh)
		if world.size.y > SHELL_TILE_MAX_THICKNESS_M:
			continue
		# 只认**顶面贴本间地面**的片：桥房的坑底砖在 y=-12 一带，被这条挡掉。
		if absf(world.position.y + world.size.y - center.y) > SHELL_TILE_MAX_TOP_OFFSET_M:
			continue
		# 只留**够大**的片：一块 5×5 砖还挂着压条/缝条（很窄），按面积筛掉它们，
		# 一砖就只剩一片。不筛的话承重盒会涨到 7288 块。
		if world.size.x * world.size.z < SHELL_TILE_MIN_AREA_M2:
			continue
		tiles.append(world)
	if tiles.is_empty():
		return [AABB(
			Vector3(center.x - half_x, 0.0, center.z - half_z),
			Vector3(dims.x, 1.0, dims.y)
		)]
	# 🔴 格原点取**地砖自身的最小角**，不取房间包围盒。
	# 为什么：砖心随该轴的**块数奇偶**变（40 宽是 2.5+5n、45 深是 5n），
	# 还夹着 -7.49 这种浮点砖心。拿房间边界推格心，会在某些壳上把整列砖
	# 挪到隔壁格 —— 于是凭空出现「有砖没板」（掉下去）或「有板没砖」（走出房间）。
	# 以地砖最小角为基准、按 `round` 求格索引，浮点噪声被并掉，与砖的真实位置零假设。
	var origin_x := INF
	var origin_z := INF
	for tile in tiles:
		origin_x = minf(origin_x, tile.position.x)
		origin_z = minf(origin_z, tile.position.z)
	var cells := {}
	for tile in tiles:
		var index := Vector2i(
			roundi((tile.position.x - origin_x) / SHELL_TILE_GRID_M),
			roundi((tile.position.z - origin_z) / SHELL_TILE_GRID_M)
		)
		cells[index] = true
	var out: Array[AABB] = []
	for key in cells.keys():
		var index := key as Vector2i
		out.append(AABB(
			Vector3(
				origin_x + float(index.x) * SHELL_TILE_GRID_M - overlap, 0.0,
				origin_z + float(index.y) * SHELL_TILE_GRID_M - overlap
			),
			Vector3(
				SHELL_TILE_GRID_M + overlap * 2.0, 1.0,
				SHELL_TILE_GRID_M + overlap * 2.0
			)
		))
	return out


## 网格件的世界 AABB（8 角点变换后取包围）。
func _mesh_world_aabb(mesh: MeshInstance3D) -> AABB:
	var local := mesh.get_aabb()
	var xform := mesh.global_transform
	var box := AABB()
	var first := true
	for index in range(8):
		var corner := local.position + Vector3(
			local.size.x if (index & 1) else 0.0,
			local.size.y if (index & 2) else 0.0,
			local.size.z if (index & 4) else 0.0,
		)
		var point := xform * corner
		if first:
			box = AABB(point, Vector3.ZERO)
			first = false
		else:
			box = box.expand(point)
	return box


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


## 一条子图链**共用**的门位槽（所有房间同值）。
##
## 为什么必须整条链共用一个：相邻两间隔 5 m 走廊、沿 X 直连，走廊是**直线**
## ⇒ 两端门必须同轴（`lane` 相同）。每间各算一个只在「各房型 `size.y` 相同」时
## 才碰巧相等，混入 `bridge_60x50`（深度 30）就会错位。
##
## 三道筛选，全部可量、不靠猜：
##   ① **模板合法槽**：`RoomDoorLane.lane_offsets(size.y)`，与白盒校验同一份实现；
##   ② **链内交集**：深度不同的房型槽集不同，取所有房间都有的那些；
##   ③ **真实砖格命中**：门洞点（房间帧 `(±半宽, lane)`）必须落在壳的**地砖格**上。
##      `corridor_45x40` 是 L 形，凹口那 30×25 既没有砖也没有外墙 ——
##      门按中线开就会落在凹口上，玩家从走廊走进来直接站在房间外
##      （业主 2026-10-22「角色会跑到房间外面去」）。
##
## 通过者里取**离中线最近**的；一个都没有才退回 `nearest_offset`（行为与旧版一致）。
func _solve_chain_lane(entries: Array) -> float:
	if entries.is_empty():
		return 0.0
	# ① + ②：链内合法槽交集。
	var shared: Array[float] = []
	for index in range(entries.size()):
		var size := (entries[index] as Dictionary).get("size", Vector2.ZERO) as Vector2
		var offsets := ROOM_DOOR_LANE.lane_offsets(size.y)
		if index == 0:
			shared.assign(offsets)
			continue
		var kept: Array[float] = []
		for offset in shared:
			for candidate in offsets:
				if is_equal_approx(offset, candidate):
					kept.append(offset)
					break
		shared.assign(kept)
	if shared.is_empty():
		var fallback := (entries[0] as Dictionary).get("size", Vector2.ZERO) as Vector2
		return ROOM_DOOR_LANE.nearest_offset(fallback.y)
	# 按「离中线由近及远」试，取第一个全链通过者。
	shared.sort_custom(func(a: float, b: float) -> bool: return absf(a) < absf(b))
	for lane in shared:
		if _chain_lane_clears_footprints(entries, lane):
			return lane
	push_warning(
		"[SecretBranch3D] 子图链没有「所有门都落在真实地砖上」的门位槽 —— 退回最近槽 %.1f，"
		% ROOM_DOOR_LANE.nearest_offset(
			((entries[0] as Dictionary).get("size", Vector2.ZERO) as Vector2).y
		)
		+ "可能出现「门开在凹口上」。"
	)
	return ROOM_DOOR_LANE.nearest_offset(
		((entries[0] as Dictionary).get("size", Vector2.ZERO) as Vector2).y
	)


## 该 lane 下，链里每间房的每扇门是否都落在壳的真砖格上。
func _chain_lane_clears_footprints(entries: Array, lane: float) -> bool:
	for value in entries:
		var entry := value as Dictionary
		var size := entry.get("size", Vector2.ZERO) as Vector2
		var path := str(entry.get("path", ""))
		var deg := float(entry.get("layout_deg", 0.0))
		var doors := entry.get("doors", []) as Array
		if path.is_empty() or doors.is_empty():
			continue
		var footprint := _shared_shell_footprint(path)
		var tiles := footprint.get("tiles", []) as Array
		if tiles.is_empty():
			# 量不到砖格（矩形壳的砖可能被别的判据吃掉了）⇒ 不做否决，
			# 否则一个量法意外会把整条链的门位判死。
			continue
		var half_x := size.x * 0.5
		# 房间帧 → 壳局部（壳只绕原点转过 `deg`）。
		var basis := Basis(Vector3.UP, deg_to_rad(-deg))
		for door_value in doors:
			var side := str(door_value)
			var point := Vector3.ZERO
			match side:
				"east":
					point = Vector3(half_x, 0.0, lane)
				"west":
					point = Vector3(-half_x, 0.0, lane)
				_:
					# 子图链只开东西门；出现南北门说明上游写错了，不在这里否决。
					continue
			var local := basis * point
			if not _tiles_contain(tiles, Vector2(local.x, local.z)):
				return false
	return true


## `(x, z)` 是否落在某个砖格内（±半格 + 容差）。
func _tiles_contain(tiles: Array, point: Vector2) -> bool:
	for value in tiles:
		var cell := value as Vector2
		var inside_x := absf(point.x - cell.x) <= SHELL_TILE_HALF_M + SHELL_TILE_HIT_TOLERANCE_M
		var inside_z := absf(point.y - cell.y) <= SHELL_TILE_HALF_M + SHELL_TILE_HIT_TOLERANCE_M
		if inside_x and inside_z:
			return true
	return false


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


## 取一樘门节点。预制体缺失时退回纯脚本节点（资产缺失不该让关卡打不开）。
func _instantiate_door() -> Node3D:
	if SECRET_DOOR_SCENE != null:
		var scene_node := SECRET_DOOR_SCENE.instantiate()
		if scene_node != null:
			return scene_node as Node3D
	return SECRET_DOOR_SCRIPT.new() as Node3D


func _build_door(pair_id: int, site: Dictionary, locked: bool = false) -> Node3D:
	# 房间 TSCN 里已经有一扇**业主手摆**的门时，接管它 —— 不再新建第二扇。
	# 运行时房间是直接实例化房间 TSCN 的（`DungeonRoom3D._build_shell`），
	# 编辑器里那扇门在游戏里本来就在场；再建一扇只会两扇叠在同一处。
	var door_node := _adopt_authored_door(site)
	var adopted := door_node != null
	if not adopted:
		door_node = _instantiate_door()
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
	if not door_node.is_connected("teleport_requested", _on_door_teleport_requested):
		door_node.connect("teleport_requested", _on_door_teleport_requested)
	if not adopted:
		add_child(door_node)
	_apply_site_mount(door_node, site)
	_doors[str(site.get("site_id", ""))] = door_node
	return door_node


## 摘掉房间里那扇「手摆但没被接管」的门（同 site_id）。
##
## 只在晚一步读到 TSCN 位点时才有活干：`_collect_sites()` 那刻房间还没装配，
## 我们按数据位点先建了一扇；等房间齐了才发现 TSCN 里也有一扇 —— 同一处两樘门。
## 用 `remove_child` 而不是只 `queue_free`：后者要到帧末才生效，
## 同帧的 A22 可视遮挡检查还会扫到它，报一条假红。
func _drop_room_duplicate_door(site: Dictionary) -> void:
	var room := _room_nodes.get(str(site.get("room_id", ""))) as Node3D
	if room == null:
		return
	var site_id := str(site.get("site_id", ""))
	var duplicate := room.find_child("SecretDoor_%s" % site_id, true, false)
	if duplicate == null:
		return
	if duplicate == _doors.get(site_id):
		return
	var host := duplicate.get_parent()
	if host != null:
		host.remove_child(duplicate)
	duplicate.queue_free()


## 房间 TSCN 里那扇「摆位锚点门」的清道夫（业主 2026-10-21）。
##
## 为什么必须按事件盯，而不是装配时清一次就完：
##   `_create_secret_branches()` 跑在 `_prepare_floor_bundle()` 里 —— 那一刻房间
##   **记录**齐了，但房间节点和壳体都还没建（`_instantiate_dynamic_room` 与
##   `_ensure_structural_shells_resident` 都在它之后）。所以装配时 `find_child`
##   一定落空，等壳体建好，TSCN 里那扇门才冒出来。
##
## 玩家打到的如果是这扇副本，三个症状会一次出现（业主实测原话
## 「有木板破碎的动画，但是木板没有消失，也不能点击进入支线」）：
##   · `_boards` 为 null（没 configure）⇒ 缩放到 0.01 与 `visible = false`
##     全打在 null 上 —— **木板永远不消失**；
##   · `_has_teleport` 为 false ⇒ `can_teleport()` 恒假 —— **按 E 无候选**；
##   · `_spawn_board_debris()` 不依赖这两者 ⇒ **碎块照样飞**。
## 所以修补点不在动画，而在「不该存在的第二扇门」。
func _arm_room_copy_watch() -> void:
	if _room_copy_watch_armed:
		return
	_room_copy_watch_armed = true
	var tree := get_tree()
	if tree == null:
		return
	if not tree.node_added.is_connected(_on_tree_node_added):
		tree.node_added.connect(_on_tree_node_added)


func _on_tree_node_added(node: Node) -> void:
	if not (node is SecretDoor3D):
		return
	# 装配自己建的门也走这条信号（`_build_door()` 里 `add_child` 在前、登记在后），
	# 所以延迟到帧末再判 —— 那时 `_doors` 已经写好，不会误杀正主。
	call_deferred("_prune_room_copy_door", node)


## 只删「没被装配认领」的那一份。
##
## 判据用 `site_id`：它由 `configure()` / `configure_portal()` 写入，而房间副本
## 从来没人 configure 过 ⇒ 空。这比「在不在 `_doors` 里」更早成立（登记发生在
## `add_child` 之后），也顺带挡住任何将来漏网的裸门。
func _prune_room_copy_door(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var door := node as SecretDoor3D
	if door == null:
		return
	if not str(door.site_id).is_empty():
		return
	for value in _doors.values():
		if value == door:
			return
	var host := door.get_parent()
	if host != null:
		# `remove_child` 而不是只 `queue_free`：后者要到帧末才生效，
		# 这一帧里玩家射线/可视遮挡检查还会扫到它（同 `_drop_room_duplicate_door` 的理由）。
		host.remove_child(door)
	door.queue_free()
	_pruned_room_copies += 1
	print("[SecretBranch3D] 清掉房间 TSCN 带来的摆位锚点门副本：%s" % str(door.name))


## 全场景扫一遍未认领的暗门。`settle_sites()` 每次收尾调用，幂等。
func _sweep_room_copies() -> void:
	var host: Node = self
	while host.get_parent() != null:
		host = host.get_parent()
	for node in host.find_children("*", "StaticBody3D", true, false):
		if node is SecretDoor3D:
			_prune_room_copy_door(node)


## 房间 TSCN 里手动摆放的那扇门（`SecretDoor_<site_id>`）。没有就返回 null。
func _adopt_authored_door(site: Dictionary) -> Node3D:
	if not bool(site.get("manual_site", false)):
		return null
	var room := _room_nodes.get(str(site.get("room_id", ""))) as Node3D
	if room == null:
		return null
	var door_name := "SecretDoor_%s" % str(site.get("site_id", ""))
	var door := room.find_child(door_name, true, false) as Node3D
	if door == null:
		return null
	# 位置/朝向就是业主在编辑器里摆的那个 transform，一个数都不改。
	return door


## 按「门比墙面凸出多少」补安装箱厚度。
##
## 自动外推的门由 `_shift_door()` 负责；手摆的门不经过那条路，但同样可能被推出墙面
## 0.4m —— 不填这一段，侧面看就是一块悬空的板。`protrude_m` 由 `_push_site_out_of_wall`
## 实测得出（`face - 门心投影`），两种来源共用同一份数值。
func _apply_site_mount(door: Node3D, site: Dictionary) -> void:
	var protrude := float(site.get("protrude_m", 0.0))
	if protrude > 0.02 and door.has_method("set_mount_depth"):
		door.call("set_mount_depth", protrude)


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
	var door_node := _instantiate_door()
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
		"sites": _sites_debug.duplicate(true),
	}
