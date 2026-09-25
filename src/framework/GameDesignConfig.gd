class_name GameDesignConfig
extends RefCounted
## 游戏设计文档 v0.1 对应的运行时公共契约。
## 这里只放跨系统稳定值；具体玩法参数仍归各自数据资源或系统所有。

const VERSION := "0.1.0"

const MAIN_SCENE := "res://scenes/TowerDescent3D.tscn"
const BASE_SCENE_3D := "res://scenes/BaseWorld3D.tscn"
const TRAINING_SCENE_3D := "res://scenes/TrainingRange3D.tscn"
## 远征关卡的**唯一清单**。每一条 =「一份可以直接进的单层独立关卡」，
## 记录它的关卡 id（= 设计源目录名 = LevelPlanLoader 的 level_id）、
## 运行时标识 run_id（进存档、也是续局路由的键）、显示名与到达场景。
##
## 「99F 远征情报室 → 选关菜单 → 读取界面 → 到达关卡」这条传送链的**唯一终点真源**：
## 基地设施目录（mission_operations 的下一跳）、RogueMapSelectMenu、
## ExpeditionLoadingScreen 与续局路由都必须由它取值，不允许任何一处再各写一份路径字符串
## （否则改场景会漏改某一跳，见 05.1 §3.0）。
##
## **新增一张远征关卡 = 往这里加一条 + 建一个场景文件 + 建一份设计源，不必改任何游戏逻辑。**
const EXPEDITION_LEVELS: Array[Dictionary] = [
	{
		"level_id": "expedition_01",
		"run_id": "expedition_01",
		"display_name": "远征关卡01",
		"setting_name": "远征前哨站",
		"subtitle": "单层独立行动 · 入口安全屋 → 01—10 号房 → 撤离点",
		"objective_line": "肃清 01—10 号房，穿过命运之门，抵达终点撤离点。",
		"scene_3d": "res://scenes/ExpeditionLevel01_3D.tscn",
	},
	{
		"level_id": "99",
		"run_id": "99",
		"display_name": "测试关卡99",
		"setting_name": "远征试验场",
		"subtitle": "单层独立行动 · 入口安全屋 → 2 间内容房 → 撤离点",
		"objective_line": "肃清两间内容房，穿过命运之门，抵达终点撤离点。",
		"scene_3d": "res://scenes/ExpeditionLevel99_3D.tscn",
	},
]

## 远征关卡01 的正式场景。保留为**默认终点**：未指定关卡（或指定了未登记的关卡 id）时，
## 传送链一律落到它，行为与引入关卡清单之前一字不变。
const EXPEDITION_LEVEL_SCENE_3D := "res://scenes/ExpeditionLevel01_3D.tscn"

## 当前待进入的远征关卡 id。由选关菜单在切场景前写入，读取界面在切关卡前读取。
## 为什么用「待定态」而不是给读取界面各做一个场景：读取界面是一段过场，
## 它只需要知道终点，多做一个副本就意味着多一处要同步维护的路径字符串。
static var pending_expedition_level_id := ""


## 远征关卡清单里的全部关卡 id（按声明顺序）。
static func expedition_level_ids() -> Array[String]:
	var result: Array[String] = []
	for entry in EXPEDITION_LEVELS:
		result.append(str((entry as Dictionary).get("level_id", "")))
	return result


## 默认远征关卡 id（清单首条）。
## 未登记的关卡 id 会被各处悄悄收敛成默认关卡 —— 因此清单为空属于**配置级错误**，
## 必须显式报出来，否则整条传送链会退化成「永远进第一关」而无人察觉。
static func default_expedition_level_id() -> String:
	if EXPEDITION_LEVELS.is_empty():
		push_error("[GameDesignConfig] 远征关卡清单为空，传送链将失去终点真源")
		return ""
	return str((EXPEDITION_LEVELS[0] as Dictionary).get("level_id", ""))


## 查一条关卡登记。未登记返回空字典。
static func expedition_level(level_id: String) -> Dictionary:
	for entry in EXPEDITION_LEVELS:
		var dict := entry as Dictionary
		if str(dict.get("level_id", "")) == level_id:
			return dict.duplicate(true)
	return {}


## 关卡 id → 到达场景路径。未登记回退到远征关卡01，保证任何跳转都有落点。
static func expedition_level_scene(level_id: String) -> String:
	var entry := expedition_level(level_id)
	if entry.is_empty():
		return EXPEDITION_LEVEL_SCENE_3D
	return str(entry.get("scene_3d", EXPEDITION_LEVEL_SCENE_3D))


## 关卡 id → 玩家可见的关卡名。未登记回退到清单首条的显示名。
static func expedition_level_display_name(level_id: String) -> String:
	var entry := expedition_level(level_id)
	if entry.is_empty():
		var fallback := expedition_level(default_expedition_level_id())
		return str(fallback.get("display_name", "远征关卡"))
	return str(entry.get("display_name", "远征关卡"))


## 关卡 id → 读取界面副标题。
static func expedition_level_subtitle(level_id: String) -> String:
	var entry := expedition_level(level_id)
	if entry.is_empty():
		return ""
	return str(entry.get("subtitle", ""))


## 关卡 id → HUD 里的行动目标文案。
static func expedition_level_objective(level_id: String) -> String:
	var entry := expedition_level(level_id)
	if entry.is_empty():
		return ""
	return str(entry.get("objective_line", ""))


## 关卡 id → 运行时标识。它同时是存档里的隔离标识、也是续局路由的键。
## 未登记回退到关卡 id 本身，保证「设计源目录名 == 运行时标识」这条口径不被破坏。
static func expedition_run_id(level_id: String) -> String:
	var entry := expedition_level(level_id)
	if entry.is_empty():
		return level_id
	var run_id := str(entry.get("run_id", ""))
	return run_id if not run_id.is_empty() else level_id


## 运行时标识 → 到达场景。续局/断线重连按存档里的 runtime_map_id 回到原关卡，
## 未登记的标识返回空串（调用方按「不是独立关卡」处理，留在主场景，避免坏档循环跳转）。
static func expedition_scene_for_run_id(run_id: String) -> String:
	for entry in EXPEDITION_LEVELS:
		var dict := entry as Dictionary
		if str(dict.get("run_id", "")) == run_id:
			return str(dict.get("scene_3d", ""))
	return ""


## 登记一次待进入的关卡。返回 false 表示该关卡未登记（调用方应据此拒绝传送，
## 而不是把玩家丢进默认关卡 —— 静默改道比报错更难排查）。
static func select_expedition_level(level_id: String) -> bool:
	if expedition_level(level_id).is_empty():
		push_error("[GameDesignConfig] 未登记的远征关卡 id: %s" % level_id)
		return false
	pending_expedition_level_id = level_id
	return true


## 消费待进入的关卡 id：取值即清空，避免上一次的选择泄漏到下一次传送。
static func consume_pending_expedition_level_id() -> String:
	var level_id := pending_expedition_level_id
	pending_expedition_level_id = ""
	if level_id.is_empty() or expedition_level(level_id).is_empty():
		return default_expedition_level_id()
	return level_id


## 只读地看待进入的关卡 id（不清空），供界面在构建时取文案。
static func peek_pending_expedition_level_id() -> String:
	if pending_expedition_level_id.is_empty() or expedition_level(pending_expedition_level_id).is_empty():
		return default_expedition_level_id()
	return pending_expedition_level_id

const RENDER_LAYER_WORLD := 1
const RENDER_LAYER_PLAYER := 2
const LIGHT_MASK_WORLD_ONLY := RENDER_LAYER_WORLD
const LIGHT_MASK_WORLD_AND_PLAYER := RENDER_LAYER_WORLD | RENDER_LAYER_PLAYER
const SHADOW_MASK_WORLD_ONLY := RENDER_LAYER_WORLD
const SHADOW_MASK_WORLD_AND_PLAYER := RENDER_LAYER_WORLD | RENDER_LAYER_PLAYER
const COLLISION_LAYER_CAMERA_ONLY := 16

const ROOM_TYPES_WITH_HOSTILES: Array[String] = [
	"COMBAT",
	"ELITE",
	"BOSS",
	"TRAP",
	"BASEMENT",
	"STORAGE",
	"SCAVENGE",
]

## Boss 房型。Boss 的**出场与结算**归生成工具：`BossContentCatalog` 是首领名册，
## `MonsterInjector._generate_boss` / `EnemyAvatar3D` 是装配端。设计源只做两件事：
##   ① 声明本房是 Boss 房（`role: "boss"` / `content_type: "BOSS"`）；
##   ② **可选**地用 `boss_content_id` 指定本房出场的是名册里的哪一个首领。
## 设计源**不参与编成**（不写波次/数量/技能袋/竞技场）——那些由名册条目决定。
const BOSS_ROOM_TYPE := "BOSS"

## Boss 房角色名。`FloorPlanGenerator._assign_content_types_data_driven` 依据它把房间
## **钉成** `type = "BOSS"`，所以 role 与 content_type 是同一件事的两种写法，都要认。
const BOSS_ROOM_ROLE := "boss"


## 房间级刷怪计划能否写在该房型上 —— **唯一口径**。
## 消费方共两处，都必须走本函数，禁止各自复刻列表（否则会出现两套口径互相冲突）：
##   ① `LevelPlanValidator._validate_enemy_spawn_plan` —— 静态校验，写错即报错；
##   ② `Dungeon3D._authored_spawn_waves` —— 运行时兜底，数据绕过校验也不接管。
## 判据 = 会刷怪的房型（否则永不调用刷怪入口，写了等于静默失效）且不是 BOSS。
## 为什么 BOSS 房必须排除：`_authored_spawn_waves` 会先于 `match room.room_type` 返回，
## boss + elite 整段被跳过，表现为「Boss 房没有 Boss」并可能锁死下楼门。
static func is_spawn_plan_authorable_room(content_type: String) -> bool:
	return (
		ROOM_TYPES_WITH_HOSTILES.has(content_type)
		and content_type != BOSS_ROOM_TYPE
	)


## 本房是不是 Boss 房 —— **唯一口径**，两个消费方都必须走本函数：
##   ① `LevelPlanValidator._validate_enemy_spawn_plan`（Boss 房禁写刷怪计划）；
##   ② `LevelPlanValidator._validate_boss_content_id`（只有 Boss 房可指派首领身份）。
## 为什么 content_type 与 role 都要看：`FloorPlanGenerator._assign_content_types_data_driven`
## 会把 `role == "boss"` 的房间**钉成** `type = "BOSS"`（玩法不变量），因此即便设计源
## 没显式写 content_type，运行时它照样是 Boss 房 —— 只看 content_type 会让这种房间
## 绕过静态校验（运行时兜底虽在，但报错点应当前移，别让作者靠猜）。
## 禁止在别处复刻这条判据。
static func is_boss_room(content_type: String, role: String) -> bool:
	return content_type == BOSS_ROOM_TYPE or role == BOSS_ROOM_ROLE


static func scene_exists(scene_path: String) -> bool:
	return not scene_path.is_empty() and ResourceLoader.exists(scene_path, "PackedScene")
