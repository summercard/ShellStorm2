class_name TreasureChest3D
extends Area3D
## 宝箱（《挺进地牢》风格）。玩家靠近按 E 开启。
##
## **本类只做表现与交互协议，绝不自己发奖励。**
## 开箱后发 `open_requested` 信号，由 `Dungeon3D._on_chest_opened()` 统一处理
## 「扣钥匙 → 抽掉落 → 落地上 → 给命运卡」。理由：
##   · 掉落与命运卡都依赖 `RewardService` / `FateCardGameBridge` 这类**单例**，
##     让箱子自己去调会把「谁发奖」这件事散到房间层的子节点上；
##   · 探针要能在不建整个地牢的前提下验证开箱结果，信号 + 单一处理点更容易测。
##
## 与 `RoomFurniture3D`（搜索容器）的区别：
##   · 家具是「搜索」，可以搜索多次无关紧要；宝箱是「开启」，**只能开一次**；
##   · 家具掉落走 `scavenge_*` 池，宝箱走品质池且必定多件；
##   · 宝箱可能**需要钥匙**（原作 EGT），家具不需要。
## 因此不复用家具类，避免给它塞一堆 `if is_chest` 分支。

## 开箱成功时发。`Dungeon3D` 接这个信号做结算（扣钥匙 / 掉落 / 命运卡）。
signal open_requested(chest: TreasureChest3D)

## 开箱动作播完、箱子形态已切换时发。探针用它判断「视觉上真的开了」。
signal opened(chest: TreasureChest3D)

const CHEST_DIMENSIONS := Vector3(1.28, 1.02, 0.92)
## 开盖动画时长。取 0.42s 而不是 0.2 —— 开箱是这一层的「奖励时刻」，
## 太快会让玩家没看清里面出了什么就已经在跑了。
const LID_OPEN_SECONDS := 0.42
## 拟态的抖动时长。0.4s 是刻意的**预警窗口**：够玩家后撤半步，
## 又短到不会让人在箱子前面站着等它变。
const MIMIC_SHAKE_SECONDS := 0.40
## 品质 → 描边色。与 `Dungeon3D.FATE_RARITIES` 同序（common/uncommon/rare/epic/legendary），
## 但只用到前四档：宝箱品质在原作里是「棕/蓝/绿/红/黑」，不是五档品质。
const QUALITY_COLORS := {
	"common": Color(0.62, 0.46, 0.24),
	"uncommon": Color(0.30, 0.62, 0.92),
	"rare": Color(0.36, 0.84, 0.46),
	"epic": Color(0.78, 0.34, 0.86),
}

var chest_id := ""
var quality := "common"
## 是否需要房间钥匙。**只用于提示文案** —— 真正的扣钥匙判定在 `Dungeon3D`
## （钥匙存在 `InventoryModule` / `_room_key_count` 里，箱子够不着）。
var requires_key := false
## 开箱掉落用哪个池、抽几件、给几张命运卡。
## **由生成器从 `treasure_chests` 配置里逐箱抄下来**，箱子不自己去读 level_plan ——
## 那样 `Dungeon3D` 就得为了一个数字去解析整份关卡数据，且解耦检查会判它关卡分支。
var reward_pool_id := "loot_floor_1_2"
var drop_count := 1
var fate_card_per_open := 0
## 这只箱子是不是**拟态**（开箱变怪）。由生成器掷骰后写进 `chest_placements`。
## **箱子自己不知道也管不着结算** —— 它只负责「开箱时表现成被咬了一口再消失」，
## 刷什么怪、掉什么全在 `Dungeon3D`。
var mimic := false
## 拟态变什么怪。同 `chest_placements.mimic_monster_kind`，缺省 `egt_mimic`。
var mimic_monster_kind := "egt_mimic"

var _opened := false
var _player_in_range := false
var _visual_root: Node3D
var _lid_pivot: Node3D
var _prompt: Label3D
var _body_material: StandardMaterial3D
var _trim_material: StandardMaterial3D
var _glow: MeshInstance3D
var _collision: CollisionShape3D


func configure(config: Dictionary) -> void:
	chest_id = str(config.get("id", chest_id))
	quality = str(config.get("quality", quality))
	requires_key = bool(config.get("requires_key", requires_key))
	reward_pool_id = str(config.get("reward_pool_id", reward_pool_id))
	drop_count = maxi(1, int(config.get("drop_count", drop_count)))
	fate_card_per_open = maxi(0, int(config.get("fate_card_per_open", fate_card_per_open)))
	mimic = bool(config.get("mimic", mimic))
	mimic_monster_kind = str(config.get("mimic_monster_kind", mimic_monster_kind))


func _ready() -> void:
	add_to_group("treasure_chest_3d")
	# 交互系统靠这个组发现可交互物（`PlayerInteractionController3D._refresh_focused_candidate`）。
	add_to_group(PlayerInteractionController3D.PROVIDER_GROUP)
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_visual()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player_3d"):
		_player_in_range = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player_3d"):
		_player_in_range = false


# ---------------------------------------------------------------------------
# 交互协议（`PlayerInteractionController3D` 的约定）
# ---------------------------------------------------------------------------

func get_interaction_candidate(_player: Player3D) -> Dictionary:
	if _opened or not _player_in_range:
		return {}
	return {
		"available": true,
		"interaction_id": "treasure_chest:%s:%d" % [chest_id, get_instance_id()],
		"position": global_position,
		# 60 > 家具的 40：宝箱与家具挨着时优先开箱（玩家一定是冲着箱子来的）。
		"priority": 60,
		"prompt": _prompt_text(),
	}


## 提示牌是纯文案载体（同 `RoomFurniture3D`）：可见反馈交给 InteractionDot3D。
func set_interaction_focus(_candidate: Dictionary, _focused: bool) -> void:
	pass


func perform_interaction(_player: Player3D, _candidate: Dictionary) -> bool:
	if _opened or not _player_in_range:
		return false
	# ⚠ **这里不置 `_opened`**。开箱是否成功由 `Dungeon3D` 决定（可能没有钥匙）。
	# 先置位再判定，会出现「没钥匙也把箱子标成已开」的假成功 —— 玩家看到箱子开了却没东西。
	# 由 `Dungeon3D` 回调 `commit_opened()` 收口状态。
	open_requested.emit(self)
	return true


func get_interaction_dot_anchor() -> Vector3:
	return global_position + Vector3.UP * (CHEST_DIMENSIONS.y + 0.62)


func is_interaction_dot_visible() -> bool:
	return not _opened


func get_interaction_progress() -> Dictionary:
	# 开箱是瞬发（不像家具要读条），不画进度环。
	return {"active": false, "progress": 0.0}


func _prompt_text() -> String:
	if _opened:
		return "已开启"
	if requires_key:
		return "[E] 开启宝箱 · 消耗 1 把钥匙"
	return "[E] 开启宝箱"


# ---------------------------------------------------------------------------
# 状态收口（由 Dungeon3D 调用）
# ---------------------------------------------------------------------------

## 真正开箱：切形态 + 播盖开动画。**幂等** —— 重复调用不会重播。
## `Dungeon3D` 只有在扣钥匙 / 抽奖都成功后才调它，所以「打不开」时箱子保持原样。
func commit_opened() -> void:
	if _opened:
		return
	_opened = true
	_player_in_range = false
	if _prompt != null:
		_prompt.text = "已开启"
		_prompt.modulate = Color(0.55, 0.61, 0.62)
	if _body_material != null:
		_body_material.albedo_color = _body_material.albedo_color.darkened(0.22)
	if _trim_material != null:
		_trim_material.emission_energy_multiplier = 0.15
	if _glow != null:
		_glow.visible = true
	# 盖子绕**后缘**上翻：pivot 放在箱体后侧，盖 mesh 相对 pivot 前移半深，
	# 这样旋转时前缘抬起来、后缘不动 —— 与真实合页一致。
	if _lid_pivot != null:
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(_lid_pivot, "rotation:x", deg_to_rad(-104.0), LID_OPEN_SECONDS)
	if AudioManager != null:
		AudioManager.play_sfx("container_open", -2.0)
	opened.emit(self)


## 存档恢复 / 探针构造已开状态的箱子。不做动画，直接落到终态。
func restore_opened_state(opened_state: bool) -> void:
	if not opened_state:
		return
	_opened = true
	_player_in_range = false
	if _prompt != null:
		_prompt.text = "已开启"
		_prompt.modulate = Color(0.55, 0.61, 0.62)
	if _body_material != null:
		_body_material.albedo_color = _body_material.albedo_color.darkened(0.22)
	if _lid_pivot != null:
		_lid_pivot.rotation.x = deg_to_rad(-104.0)
	if _glow != null:
		_glow.visible = true


func is_opened() -> bool:
	return _opened


# ---------------------------------------------------------------------------
# 拟态（开箱变怪）
# ---------------------------------------------------------------------------

## 打开一只**拟态**箱子：抖动 → 咬开 → 整体消失。
##
## 为什么不复用 `commit_opened()`：那条路径的语义是「箱子开了、里面有东西」——
## 盖子缓慢上翻、内部发光面亮起、提示牌写「已开启」。拟态正相反：**箱子吞了钥匙就跑**，
## 玩家该看到的是「这箱子不是箱子」，而不是一盏温柔的奖励灯。
##
## 本函数**不发奖励、不刷怪**：钥匙已在 `Dungeon3D` 扣完，怪也由 `Dungeon3D` 生成。
## 箱子只把「我没了」这件事演完，然后消失 —— 否则怪会跟箱子叠在同一个位置互相遮挡。
func commit_mimic_reveal() -> void:
	if _opened:
		return
	_opened = true
	_player_in_range = false
	# 提示牌直接隐藏而不是改写成「已开启」：接下来玩家要看的是那只怪，
	# 一句状态文案留在半空只会挡住它。
	if _prompt != null:
		_prompt.visible = false
	if _visual_root != null:
		var shake := create_tween()
		shake.set_loops(4)
		shake.tween_property(_visual_root, "rotation:z", deg_to_rad(4.5), 0.05)
		shake.tween_property(_visual_root, "rotation:z", deg_to_rad(-4.5), 0.05)
		shake.chain().tween_property(_visual_root, "rotation:z", 0.0, 0.02)
	if _lid_pivot != null:
		var lid := create_tween()
		lid.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		lid.tween_interval(MIMIC_SHAKE_SECONDS)
		lid.tween_property(_lid_pivot, "rotation:x", deg_to_rad(-140.0), 0.16)
	if AudioManager != null:
		AudioManager.play_sfx("container_open", -2.0)
	# 先发 `opened`：房间在这一刻就把「已开」记进账，之后无论 detail 重建多少次、
	# 玩家读档重进多少次，这只箱子都不会再是可开的箱子。
	opened.emit(self)
	# 消失走 tween 回调，不用 `await` —— `Dungeon3D` 紧接着就要在同一帧刷怪，
	# 把 `commit_*` 变成协程会让「先扣钥匙后刷怪」的顺序断在第一帧。
	var vanish := create_tween()
	vanish.tween_interval(MIMIC_SHAKE_SECONDS + 0.34)
	vanish.tween_callback(_vanish_for_mimic)


## 拟态的终态：视觉与碰撞一起收掉。
## 只藏视觉不关碰撞，会在房间里留一块看不见的挡路石头（玩家会以为是 bug）。
func _vanish_for_mimic() -> void:
	if _visual_root != null:
		_visual_root.visible = false
	if _collision != null:
		_collision.disabled = true
	monitoring = false
	if _prompt != null:
		_prompt.visible = false


## detail 重建 / 读档回灌已"咬过"的拟态箱：直接落到终态，不重播抖动。
func restore_mimic_state() -> void:
	_opened = true
	_player_in_range = false
	_vanish_for_mimic()


## 品质 → 掉落品质加成档数。`Dungeon3D._apply_fate_item_quality()` 吃这个值。
## 宝箱品质在原作里是「棕/蓝/绿/红/黑」五档，我们映射到 4 档品质加成（0~3）。
func quality_tier() -> int:
	match quality:
		"uncommon":
			return 1
		"rare":
			return 2
		"epic":
			return 3
		_:
			return 0


func get_chest_snapshot() -> Dictionary:
	return {
		"chest_id": chest_id,
		"quality": quality,
		"requires_key": requires_key,
		"opened": _opened,
		"mimic": mimic,
		"visual_visible": _visual_root.visible if _visual_root != null else false,
		"collision_disabled": _collision.disabled if _collision != null else false,
		"prompt": _prompt.text if _prompt != null else "",
		"dot_visible": is_interaction_dot_visible(),
		"lid_open_deg": rad_to_deg(_lid_pivot.rotation.x) if _lid_pivot != null else 0.0,
	}


# ---------------------------------------------------------------------------
# 视觉（程序化，不依赖美术资产）
# ---------------------------------------------------------------------------

func _build_visual() -> void:
	var trim_color: Color = QUALITY_COLORS.get(quality, QUALITY_COLORS["common"])

	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = Color(0.24, 0.17, 0.12)
	_body_material.metallic = 0.15
	_body_material.roughness = 0.72

	_trim_material = StandardMaterial3D.new()
	_trim_material.albedo_color = trim_color
	_trim_material.metallic = 0.72
	_trim_material.roughness = 0.26
	_trim_material.emission_enabled = true
	_trim_material.emission = trim_color
	# 品质越高的箱子越「亮」—— 这是玩家在房间门口就能读出「值不值得拿钥匙」的唯一线索。
	_trim_material.emission_energy_multiplier = 0.75

	_visual_root = Node3D.new()
	_visual_root.name = "ChestVisual"
	add_child(_visual_root)

	var half := CHEST_DIMENSIONS * 0.5
	# 箱体（下半）
	_add_box(
		_visual_root, Vector3(CHEST_DIMENSIONS.x, CHEST_DIMENSIONS.y * 0.62, CHEST_DIMENSIONS.z),
		Vector3(0, CHEST_DIMENSIONS.y * 0.31, 0), _body_material
	)
	# 四条竖包边
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_box(
				_visual_root, Vector3(0.10, CHEST_DIMENSIONS.y * 0.64, 0.10),
				Vector3(sx * (half.x - 0.05), CHEST_DIMENSIONS.y * 0.31, sz * (half.z - 0.05)),
				_trim_material
			)
	# 腰线
	_add_box(
		_visual_root, Vector3(CHEST_DIMENSIONS.x + 0.02, 0.08, CHEST_DIMENSIONS.z + 0.02),
		Vector3(0, CHEST_DIMENSIONS.y * 0.62, 0), _trim_material
	)

	# 盖子：pivot 在后缘
	_lid_pivot = Node3D.new()
	_lid_pivot.name = "LidPivot"
	_lid_pivot.position = Vector3(0, CHEST_DIMENSIONS.y * 0.62, -half.z)
	_visual_root.add_child(_lid_pivot)
	var lid_depth := CHEST_DIMENSIONS.z
	var lid_height := CHEST_DIMENSIONS.y * 0.30
	_add_box(
		_lid_pivot, Vector3(CHEST_DIMENSIONS.x, lid_height, lid_depth),
		Vector3(0, lid_height * 0.5, half.z), _body_material
	)
	# 盖上的两条金属带 + 锁扣
	for sx in [-1.0, 1.0]:
		_add_box(
			_lid_pivot, Vector3(0.10, lid_height + 0.02, lid_depth + 0.02),
			Vector3(sx * (half.x - 0.05), lid_height * 0.5, half.z), _trim_material
		)
	_add_box(
		_lid_pivot, Vector3(0.26, 0.24, 0.12),
		Vector3(0, lid_height * 0.18, lid_depth - 0.04), _trim_material
	)

	# 内部发光面：开箱后才可见（盖子抬起时从缝里透出光）
	var glow_mesh := BoxMesh.new()
	glow_mesh.size = Vector3(CHEST_DIMENSIONS.x * 0.82, 0.04, CHEST_DIMENSIONS.z * 0.78)
	var glow_material := StandardMaterial3D.new()
	glow_material.albedo_color = trim_color
	glow_material.emission_enabled = true
	glow_material.emission = trim_color.lightened(0.35)
	glow_material.emission_energy_multiplier = 3.2
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mesh.material = glow_material
	_glow = MeshInstance3D.new()
	_glow.name = "ChestGlow"
	_glow.mesh = glow_mesh
	_glow.position = Vector3(0, CHEST_DIMENSIONS.y * 0.60, 0)
	_glow.visible = false
	_visual_root.add_child(_glow)

	var shape := BoxShape3D.new()
	shape.size = Vector3(CHEST_DIMENSIONS.x + 0.3, CHEST_DIMENSIONS.y + 0.3, CHEST_DIMENSIONS.z + 0.3)
	_collision = CollisionShape3D.new()
	_collision.position.y = CHEST_DIMENSIONS.y * 0.5
	_collision.shape = shape
	add_child(_collision)

	# 提示文案。同家具/钥匙口径：不画描边（outline 8 相对 34 号字太粗），正对镜头。
	_prompt = Label3D.new()
	_prompt.name = "ChestPrompt"
	_prompt.position = Vector3(0, CHEST_DIMENSIONS.y + 0.62, 0)
	_prompt.text = _prompt_text()
	_prompt.font_size = 32
	_prompt.pixel_size = 0.010
	_prompt.outline_size = 0
	_prompt.modulate = trim_color.lightened(0.3)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	add_child(_prompt)


func _add_box(parent: Node3D, size: Vector3, offset: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = offset
	parent.add_child(instance)
