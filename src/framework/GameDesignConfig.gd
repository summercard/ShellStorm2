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
##
## `nav_order` 只决定它在 99F 远征情报室里的**排位**（小的在前），与解锁顺序、通关顺序无关。
## 缺这个字段时排在最后。它存在的理由：清单的声明顺序是"设计/发布顺序"，而情报室的
## 全息城站位是**视觉布局**，两者不该互相绑死（早期就是靠两张硬编码数组各写一份，加关就错位）。
##
## `nav_visibility` 决定它**要不要出现在情报室里**，缺省 `"always"`：
## - `"always"`：恒列出。适用于"玩家随时该看到"的关卡。远征03 从 2026-10-28 起
##   归这一档 —— 它此前是"占位未开放"，现在场景、设计源、生成链路都已就位，可真进。
## - `"on_unlock"`：玩家解锁后才列出（远征02 的口径：没过 01 之前它不该出现在城里）。
## 注意这与"能不能真的出发"是两件事 —— 后者由 `unlock_policy` + 到达场景是否存在决定。
##
## `unlock_policy` 决定**能不能真的出发**，缺省 `"always"`：
## - `"always"`：恒可进（远征01 / 99 / 目前的远征03）。
## - `"on_clear"`：通关 `unlock_required_clear` 指定关卡后解锁（远征02 ← 通关远征01）。
##
## 为什么把解锁规则写在这里，而不是继续写死在 `BaseManager` 里：
## 那一处原本是 `return level_id in ["expedition_01", "99"]` 的**硬编码白名单**，
## 于是「新增一张远征关卡」必须同时改清单和 BaseManager —— 漏改第二处的表现是
## **牌面写着"点击进入"、按下去却弹"尚未解锁"**，也就是远征03 从上线起就一直进不去的原因。
## 清单本来就声明"新增一张关卡 = 往这里加一条"，那解锁规则就必须跟着一起声明。
const EXPEDITION_LEVELS: Array[Dictionary] = [
	{
		"level_id": "expedition_01",
		"run_id": "expedition_01",
		"display_name": "远征关卡01",
		"setting_name": "远征前哨站",
		"subtitle": "单层独立行动 · 入口安全屋 → 01—10 号房 → 撤离点",
		"objective_line": "肃清 01—10 号房，穿过命运之门，抵达终点撤离点。",
		"scene_3d": "res://scenes/ExpeditionLevel01_3D.tscn",
		"nav_order": 10,
		"nav_badge": "01  /  EXPEDITION",
		"unlock_policy": "always",
	},
	{
		"level_id": "expedition_02",
		"run_id": "expedition_02",
		"display_name": "远征关卡02",
		"setting_name": "破败旅馆",
		"subtitle": "单层独立行动 · 阳台安全屋 → 挑高前厅 → 旅馆长廊 → T 字路口 → 两条支廊（第 1 层）",
		"objective_line": "穿过坍塌门洞进入旅馆长廊，沿主轴北进，在 T 字路口选择一条支廊深入。",
		"scene_3d": "res://scenes/ExpeditionLevel02_3D.tscn",
		"nav_order": 30,
		"nav_badge": "02  /  EXPEDITION",
		"nav_visibility": "on_unlock",
		"unlock_policy": "on_clear",
		"unlock_required_clear": "expedition_01",
	},
	{
		"level_id": "expedition_03",
		"run_id": "expedition_03",
		"display_name": "远征关卡03",
		"setting_name": "断链回廊",
		"subtitle": "单层独立行动 · 六张 flow 骨架每局抽一张 · 16~18 间房 + 0~3 间注入房",
		"objective_line": "沿本局抽中的骨架推进，肃清战斗房，取走两处宝箱，穿过命运之门抵达撤离点。",
		"scene_3d": "res://scenes/ExpeditionLevel03_3D.tscn",
		"nav_order": 40,
		"nav_badge": "03  /  EXPEDITION",
		# 白盒阶段暂时恒可进：现在要的是「能进去走一遍、看卡不卡墙」。
		# 等内容（刷怪 / 门扇 / 灯光）补齐、验收定稿后，改成
		# `"unlock_policy": "on_clear", "unlock_required_clear": "expedition_02"` 即可 ——
		# 只改这一行数据，不动任何代码。
		"unlock_policy": "always",
	},
	{
		"level_id": "99",
		"run_id": "99",
		"display_name": "测试关卡99",
		"setting_name": "远征试验场",
		"subtitle": "单层独立行动 · 入口安全屋 → 2 间内容房 → 撤离点",
		"objective_line": "肃清两间内容房，穿过命运之门，抵达终点撤离点。",
		"scene_3d": "res://scenes/ExpeditionLevel99_3D.tscn",
		"nav_order": 20,
		"nav_badge": "99  /  TEST SECTOR",
		"unlock_policy": "always",
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


## 情报室排位：按 `nav_order` 升序排好的关卡 id（缺字段的排最后，同值按声明顺序）。
## 只决定 99F 远征情报室里谁站前排，与解锁顺序、通关顺序无关。
static func expedition_nav_order() -> Array[String]:
	var entries: Array[Dictionary] = []
	for entry in EXPEDITION_LEVELS:
		entries.append(entry as Dictionary)
	var slots: Array = []
	for i in entries.size():
		slots.append({"index": i, "order": int(entries[i].get("nav_order", 0x7fffffff))})
	slots.sort_custom(func(a, b): return a["order"] < b["order"] if a["order"] != b["order"] else a["index"] < b["index"])
	var result: Array[String] = []
	for slot in slots:
		result.append(str(entries[slot["index"]].get("level_id", "")))
	return result


## 关卡 id → 情报室标记牌上的编号行。缺字段时回退到关卡 id，保证牌面永远不为空。
static func expedition_nav_badge(level_id: String) -> String:
	var entry := expedition_level(level_id)
	if entry.is_empty():
		return level_id
	var badge := str(entry.get("nav_badge", ""))
	return badge if not badge.is_empty() else level_id


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


## 关卡 id → 解锁规则。缺字段或未登记一律按 `"always"`（宁可多开放，也不要静默进不去）。
const UNLOCK_POLICY_ALWAYS := "always"
const UNLOCK_POLICY_ON_CLEAR := "on_clear"

static func expedition_unlock_policy(level_id: String) -> String:
	var entry := expedition_level(level_id)
	if entry.is_empty():
		return UNLOCK_POLICY_ALWAYS
	return str(entry.get("unlock_policy", UNLOCK_POLICY_ALWAYS))


## `on_clear` 关卡的前置通关关卡 id。非 `on_clear` 返回空串。
static func expedition_unlock_required_clear(level_id: String) -> String:
	if expedition_unlock_policy(level_id) != UNLOCK_POLICY_ON_CLEAR:
		return ""
	return str(expedition_level(level_id).get("unlock_required_clear", ""))


## 通关 `cleared_level_id` 之后应当解锁的关卡 id 列表。
##
## 由解锁规则**反查**得到，而不是在结算处写 `if level_id == "expedition_01"`。
## 后者就是「新增关卡要改两处」的来源：结算支路漏改时，牌面可进、按下说未解锁。
static func expedition_levels_unlocked_by_clearing(cleared_level_id: String) -> Array[String]:
	var result: Array[String] = []
	if cleared_level_id.is_empty():
		return result
	for entry_value in EXPEDITION_LEVELS:
		var entry := entry_value as Dictionary
		if str(entry.get("unlock_policy", UNLOCK_POLICY_ALWAYS)) != UNLOCK_POLICY_ON_CLEAR:
			continue
		if str(entry.get("unlock_required_clear", "")) != cleared_level_id:
			continue
		result.append(str(entry.get("level_id", "")))
	return result


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

## 事件房型。**不在** `ROOM_TYPES_WITH_HOSTILES` 里 —— 它走事件终端、不参与公式刷怪。
## 但**显式摆了触发盒**（`spawn_placements` 非空）时，本房变成「事件 + 战斗」双职房：
## 事件终端照常保留，同时按盒出波（业主裁定 2026-09-26，远征01 room_09）。
const EVENT_ROOM_TYPE := "EVENT"


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


## 触发盒刷怪（`docs/v0.1/design/触发器刷怪设计.md`）下的「本房型**是否可以摆触发盒**」
## —— **唯一口径**。判据 = 「会刷怪的房型」＋「事件房」。**不排除 BOSS**：触发盒是唯一
## 刷怪机制，Boss 房也用自己的盒子（`box_boss_arena`）出怪。
##
## 为什么把 EVENT 纳进来（业主裁定 2026-09-26）：事件房默认走事件终端、不刷怪，但只要
## **显式摆了触发盒**就允许它有战斗（远征01 room_09）。⚠️ EVENT 只进了**本判据**、**没有**
## 进 `ROOM_TYPES_WITH_HOSTILES` —— 后者是**公式刷怪**的入口门（`Dungeon3D := HOSTILE_ROOM_TYPES`）；
## 若把 EVENT 塞进去，无盒的程序化事件房会掉进通用 `_:` 分支刷随机怪（塔楼 / 主题池会被误伤）。
##
## 消费方：
##   ① `LevelPlanValidator._validate_spawn_boxes` —— 不在本判据里的房型摆盒即报错。
## ⚠️ 与「**必须**摆盒」的判据不同：`spawn_boxes_only` 层只对**真敌对房**
## （`ROOM_TYPES_WITH_HOSTILES`）强制要求盒子，EVENT 房**可以没有盒子**（保持纯事件房）。
## `authored_layout_peaceful`（和平区）由调用方另行排除，不写进本判据。
static func room_type_uses_spawn_boxes(content_type: String) -> bool:
	return (
		ROOM_TYPES_WITH_HOSTILES.has(content_type)
		or content_type == EVENT_ROOM_TYPE
	)


static func scene_exists(scene_path: String) -> bool:
	return not scene_path.is_empty() and ResourceLoader.exists(scene_path, "PackedScene")
