class_name GroundLootPickup3D
extends Area3D
## 3D 地面物品。生成后先抛高并在地面弹两次，弹完才开放拾取。
## 拾取使用角色中心的水平距离，不要求整个人体碰到物品；事务成功后物品飞入角色身体。

signal pickup_requested(pickup: GroundLootPickup3D, item_data: Dictionary)

var item_data: Dictionary = {}
var _visual: Node3D
var _accepted := false
var _label: Label3D
var _pickup_grace_until_msec := 0
var _spawn_animating := false
var _pickup_unlocked := true
var _pickup_request_cooldown_until_msec := 0
var _collecting := false
var _collection_target: Node3D
var _collection_start := Vector3.ZERO
var _collection_elapsed := 0.0
var _collection_start_scale := Vector3.ONE
var _nearby_player: Node3D
var _pickup_collision_shape: CollisionShape3D

const PICKUP_ANIMATION_DURATION := 0.32
const SPAWN_LAUNCH_HEIGHT_M := 1.65
const SPAWN_FIRST_LANDING_S := 0.30
const SPAWN_RISE_S := 0.12
const SPAWN_BOUNCE_HEIGHTS_M := [1.02, 0.72]
const SPAWN_BOUNCE_DURATIONS_S := [0.29, 0.22]
## 默认获取距离；实际运行值由 `pickup_distance_m` 持有，可通过
## `set_pickup_distance_m()` 动态调整，后续调手感不需要改判定逻辑。
const DEFAULT_PICKUP_DISTANCE_M := 2.00
## 兼容旧探针和外部读取；正式逻辑统一读取实例的动态距离。
const PICKUP_DISTANCE_M := DEFAULT_PICKUP_DISTANCE_M
@export_range(0.25, 5.0, 0.05) var pickup_distance_m: float = DEFAULT_PICKUP_DISTANCE_M
const PICKUP_REQUEST_RETRY_S := 0.18
const COLLECTION_ARC_HEIGHT_M := 0.45
## —— 头顶名牌（业主 2026-09-29：俯视镜头读不到名字）——
## 原来 Label3D 用的是默认朝向（不 billboard），文字躺在自己的 XY 平面上、
## 只朝世界 +Z。俯视镜头看到的是纸片侧面 ⇒ 一个字都读不出来。
## 现在与敌人血条 / 伤害数字同一口径：始终正对镜头，且不被家具与墙体遮掉。
## 下面几个数就是「上面的文字」的可调旋钮，改这里，别在别处复刻一份：
##   嫌小 → 抬 LABEL_FONT_SIZE（字号）或 LABEL_PIXEL_SIZE（世界尺寸/像素比）
##   嫌高/嫌低 → 改 LABEL_HEIGHT_M（相对物品原点的米数）
##   嫌糊 → 抬 LABEL_OUTLINE_SIZE（黑描边宽度）
const LABEL_HEIGHT_M := 1.05
const LABEL_FONT_SIZE := 30
const LABEL_PIXEL_SIZE := 0.010
const LABEL_OUTLINE_SIZE := 8
## entity_size_baseline_v2：旧资产的 70% 定义为当前世界道具的 100%。
## 保留旧倍率用于迁移/回退，禁止把 0.70 直接烘进各物品类型的旧值。
const CURRENT_BASE_SIZE_MULTIPLIER := 0.70
const LEGACY_WEAPON_VISUAL_SCALE := 0.82
const LEGACY_ITEM_VISUAL_SCALE := 0.72


func configure(data: Dictionary, color := Color(0.38, 0.88, 0.72)) -> void:
	item_data = WeaponInstance.ensure_weapon_item(data)
	_build_visual(color)


func _ready() -> void:
	add_to_group("ground_loot_3d")
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## 玩家主动从物品栏丢到地面的物品需要短暂拾取保护，
## 否则玩家胶囊与新掉落物同帧重叠时会立即自动拾回背包。
func set_pickup_grace_seconds(seconds: float) -> void:
	_pickup_grace_until_msec = Time.get_ticks_msec() + int(maxf(0.0, seconds) * 1000.0)


## 动态调节地面物获取距离。范围同步更新到 Area3D 的碰撞球，
## 距离判定和物理触发始终使用同一个运行时数值。
func set_pickup_distance_m(distance_m: float) -> void:
	pickup_distance_m = clampf(distance_m, 0.25, 5.0)
	if _pickup_collision_shape != null and is_instance_valid(_pickup_collision_shape):
		var sphere := _pickup_collision_shape.shape as SphereShape3D
		if sphere != null:
			sphere.radius = pickup_distance_m


func get_pickup_distance_m() -> float:
	return pickup_distance_m


func _process(delta: float) -> void:
	if _collecting:
		_process_collection(delta)
		return
	if not _accepted and _visual != null and not _spawn_animating:
		_visual.rotation.y += delta * 1.35
		_visual.position.y = 0.46 + sin(Time.get_ticks_msec() * 0.0035 + float(get_instance_id() % 13)) * 0.07
	_update_player_distance()
	if _player_in_range and is_pickup_available() and Time.get_ticks_msec() >= _pickup_request_cooldown_until_msec:
		_pickup_request_cooldown_until_msec = Time.get_ticks_msec() + int(PICKUP_REQUEST_RETRY_S * 1000.0)
		pickup_requested.emit(self, item_data.duplicate(true))


## 生成后的真实掉落表现：先抛高，落地后连续弹两下；第二次落地前不允许拾取。
## 落点由 Dungeon3D 先做贴地与净空校验，动画只负责表现，不改变存档坐标。
func begin_spawn_animation() -> void:
	if _visual == null or _spawn_animating or _accepted:
		return
	_spawn_animating = true
	_pickup_unlocked = false
	_visual.position.y = 0.46
	var tween := create_tween()
	tween.tween_property(_visual, "position:y", 0.46 + SPAWN_LAUNCH_HEIGHT_M, SPAWN_RISE_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_visual, "position:y", 0.46, SPAWN_FIRST_LANDING_S - SPAWN_RISE_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for index in range(SPAWN_BOUNCE_HEIGHTS_M.size()):
		var height := float(SPAWN_BOUNCE_HEIGHTS_M[index])
		var duration := float(SPAWN_BOUNCE_DURATIONS_S[index])
		tween.tween_property(_visual, "position:y", 0.46 + height, duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(_visual, "position:y", 0.46, duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(_finish_spawn_animation)


func _finish_spawn_animation() -> void:
	_spawn_animating = false
	_pickup_unlocked = true
	if _player_in_range and not _accepted:
		_pickup_request_cooldown_until_msec = 0


func set_collection_target(target: Node3D) -> void:
	_collection_target = target


func accept_pickup(target: Node3D = null) -> void:
	if _accepted:
		return
	_accepted = true
	_collecting = false
	if target != null:
		_collection_target = target
	if AudioManager != null:
		AudioManager.play_sfx(
			"soul_pickup" if bool(item_data.get("is_currency", false)) else "item_pickup",
			-4.0,
			randf_range(0.97, 1.03)
		)
	set_deferred("monitoring", false)
	collision_mask = 0
	for child in find_children("*", "CollisionShape3D", true, false):
		(child as CollisionShape3D).set_deferred("disabled", true)
	if _visual == null:
		queue_free()
		return
	if _collection_target != null and is_instance_valid(_collection_target):
		_start_collection_animation()
		return
	# 没有目标时保留旧的向上回收兜底，仅供独立表现测试使用；正式拾取总是传玩家目标。
	var start_scale := _visual.scale
	var motion := create_tween().set_parallel(true)
	motion.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	motion.tween_property(_visual, "position", _visual.position + Vector3(0, 1.18, 0), PICKUP_ANIMATION_DURATION)
	motion.tween_property(_visual, "rotation:y", _visual.rotation.y + TAU * 1.65, PICKUP_ANIMATION_DURATION)
	if _label != null:
		motion.tween_property(_label, "modulate:a", 0.0, PICKUP_ANIMATION_DURATION * 0.72)
	var scale_tween := create_tween()
	scale_tween.tween_property(_visual, "scale", start_scale * 1.18, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(_visual, "scale", start_scale * 0.04, PICKUP_ANIMATION_DURATION - 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	scale_tween.tween_callback(queue_free)


func _start_collection_animation() -> void:
	_collecting = true
	_collection_elapsed = 0.0
	_collection_start = _visual.global_position
	_collection_start_scale = _visual.scale
	if _label != null:
		_label.modulate.a = 0.0


func _process_collection(delta: float) -> void:
	if _visual == null:
		queue_free()
		return
	_collection_elapsed += delta
	var progress := clampf(_collection_elapsed / PICKUP_ANIMATION_DURATION, 0.0, 1.0)
	var target_position := _get_collection_target_position()
	var curved := _collection_start.lerp(target_position, progress)
	curved.y += COLLECTION_ARC_HEIGHT_M * 4.0 * progress * (1.0 - progress)
	_visual.global_position = curved
	_visual.rotation.y += delta * TAU * 5.0
	_visual.scale = _collection_start_scale.lerp(Vector3.ZERO, progress)
	if progress >= 1.0:
		queue_free()


func _get_collection_target_position() -> Vector3:
	if _collection_target == null or not is_instance_valid(_collection_target):
		return _collection_start + Vector3.UP * 0.5
	if _collection_target.has_method("get_loot_collection_target_position"):
		return _collection_target.get_loot_collection_target_position()
	return _collection_target.global_position + Vector3.UP * 0.65


func is_pickup_accepted() -> bool:
	return _accepted


## 发放前的统一前置条件，Dungeon3D 同样校验，避免其他请求路径绕过弹跳和保护期。
func is_pickup_available() -> bool:
	return not _accepted and _pickup_unlocked and not _spawn_animating and Time.get_ticks_msec() >= _pickup_grace_until_msec


func _update_player_distance() -> void:
	if not is_instance_valid(_nearby_player) or not _nearby_player.is_inside_tree():
		_nearby_player = get_tree().get_first_node_in_group("player_3d") as Node3D
	_player_in_range = false
	if not is_instance_valid(_nearby_player) or not _nearby_player.is_inside_tree():
		return
	var offset := _nearby_player.global_position - global_position
	offset.y = 0.0
	_player_in_range = offset.length() <= pickup_distance_m


var _player_in_range := false


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player_3d"):
		return
	_nearby_player = body
	_update_player_distance()
	if not _player_in_range or not is_pickup_available():
		return
	_pickup_request_cooldown_until_msec = Time.get_ticks_msec() + int(PICKUP_REQUEST_RETRY_S * 1000.0)
	pickup_requested.emit(self, item_data.duplicate(true))


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player_3d"):
		_player_in_range = false


func _build_visual(color: Color) -> void:
	_visual = ItemModelFactory3D.create_model(item_data, color)
	_visual.name = "LootVisual"
	var legacy_scale := (
		LEGACY_WEAPON_VISUAL_SCALE
		if str(item_data.get("type", "")) == "weapon"
		else LEGACY_ITEM_VISUAL_SCALE
	)
	_visual.scale = Vector3.ONE * legacy_scale * CURRENT_BASE_SIZE_MULTIPLIER
	add_child(_visual)
	var shape := SphereShape3D.new()
	shape.radius = pickup_distance_m
	_pickup_collision_shape = CollisionShape3D.new()
	_pickup_collision_shape.position.y = 0.48
	_pickup_collision_shape.shape = shape
	add_child(_pickup_collision_shape)
	_label = Label3D.new()
	_label.name = "LootLabel"
	_label.position = Vector3(0, LABEL_HEIGHT_M, 0)
	## 业主 2026-09-29：地面掉落物名牌**只写名字**。
	## 原来武器会追加「 #编号 · 构筑 n/8」，那两项在拾取前对玩家没有任何决策价值，
	## 只把名牌撑长、挤小字号。武器实例号与构筑进度在背包（I）/ 工作台里看得更全。
	## 不要再把后缀加回来 —— 需要看实例身份请走 InventoryUI，别复刻到世界里。
	_label.text = str(item_data.get("name", item_data.get("id", "物资")))
	_label.font_size = LABEL_FONT_SIZE
	_label.pixel_size = LABEL_PIXEL_SIZE
	_label.outline_size = LABEL_OUTLINE_SIZE
	_label.modulate = color.lightened(0.20)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 正对镜头 + 不参与深度遮挡：俯视相机下这才读得到（与敌人血条同口径）。
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	add_child(_label)


func get_model_snapshot() -> Dictionary:
	var legacy_scale := (
		LEGACY_WEAPON_VISUAL_SCALE
		if str(item_data.get("type", "")) == "weapon"
		else LEGACY_ITEM_VISUAL_SCALE
	)
	return {
		"item_id": str(item_data.get("id", "")),
		"model_kind": ItemModelFactory3D.get_model_kind(item_data),
		"mesh_count": ItemModelFactory3D.count_mesh_instances(_visual) if _visual != null else 0,
		"uses_shared_model_factory": true,
		"accepted": _accepted,
		"pickup_animation_duration": PICKUP_ANIMATION_DURATION,
		"pickup_distance_m": pickup_distance_m,
		"pickup_distance_dynamic": true,
		"spawn_animating": _spawn_animating,
		"pickup_unlocked": _pickup_unlocked,
		"collecting": _collecting,
		"collection_target_valid": _collection_target != null and is_instance_valid(_collection_target),
		"pickup_grace_active": Time.get_ticks_msec() < _pickup_grace_until_msec,
		"size_baseline_id": "entity_size_baseline_v2",
		"legacy_visual_scale": legacy_scale,
		"base_size_multiplier": CURRENT_BASE_SIZE_MULTIPLIER,
		"visual_scale": _visual.scale if _visual != null else Vector3.ZERO,
		"visual_world_position": _visual.global_position if _visual != null and _visual.is_inside_tree() else Vector3.ZERO,
		# 头顶名牌朝向：与 `Enemy3D.overhead_health_camera_billboard` 同一口径，
		# 让门禁能直接断言「俯视镜头读得到名字」，而不是只靠肉眼。
		"label_camera_billboard": _label != null and _label.billboard == BaseMaterial3D.BILLBOARD_ENABLED,
		"label_no_depth_test": _label != null and _label.no_depth_test,
		"label_height_m": LABEL_HEIGHT_M,
		"label_text": _label.text if _label != null else "",
	}
