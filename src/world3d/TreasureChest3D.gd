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

var _opened := false
var _player_in_range := false
var _visual_root: Node3D
var _lid_pivot: Node3D
var _prompt: Label3D
var _body_material: StandardMaterial3D
var _trim_material: StandardMaterial3D
var _glow: MeshInstance3D


func configure(config: Dictionary) -> void:
	chest_id = str(config.get("id", chest_id))
	quality = str(config.get("quality", quality))
	requires_key = bool(config.get("requires_key", requires_key))
	reward_pool_id = str(config.get("reward_pool_id", reward_pool_id))
	drop_count = maxi(1, int(config.get("drop_count", drop_count)))
	fate_card_per_open = maxi(0, int(config.get("fate_card_per_open", fate_card_per_open)))


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
	var collision := CollisionShape3D.new()
	collision.position.y = CHEST_DIMENSIONS.y * 0.5
	collision.shape = shape
	add_child(collision)

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
