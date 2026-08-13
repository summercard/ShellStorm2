class_name GroundLootPickup3D
extends Area3D
## 3D 地面物品。先落地，接触时再请求进入 12 格背包；满包时保持在原地。

signal pickup_requested(pickup: GroundLootPickup3D, item_data: Dictionary)

var item_data: Dictionary = {}
var _visual: Node3D
var _accepted := false
var _label: Label3D
var _pickup_grace_until_msec := 0

const PICKUP_ANIMATION_DURATION := 0.32
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


## 玩家主动从物品栏丢到地面的物品需要短暂拾取保护，
## 否则玩家胶囊与新掉落物同帧重叠时会立即自动拾回背包。
func set_pickup_grace_seconds(seconds: float) -> void:
	_pickup_grace_until_msec = Time.get_ticks_msec() + int(maxf(0.0, seconds) * 1000.0)


func _process(delta: float) -> void:
	if not _accepted and _visual != null:
		_visual.rotation.y += delta * 1.35
		_visual.position.y = 0.46 + sin(Time.get_ticks_msec() * 0.0035 + float(get_instance_id() % 13)) * 0.07


func accept_pickup() -> void:
	if _accepted:
		return
	_accepted = true
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


func _on_body_entered(body: Node3D) -> void:
	if (
		_accepted
		or Time.get_ticks_msec() < _pickup_grace_until_msec
		or not body.is_in_group("player_3d")
	):
		return
	pickup_requested.emit(self, item_data.duplicate(true))


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
	shape.radius = 0.82
	var collision := CollisionShape3D.new()
	collision.position.y = 0.48
	collision.shape = shape
	add_child(collision)
	_label = Label3D.new()
	_label.position = Vector3(0, 1.05, 0)
	_label.text = str(item_data.get("name", item_data.get("id", "物资")))
	if str(item_data.get("type", "")) == "weapon":
		var upgrades: Variant = item_data.get("fate_upgrades", [])
		var used: int = upgrades.size() if upgrades is Array else 0
		_label.text += " #%s · 构筑 %d/%d" % [
			str(item_data.get("weapon_instance_id", "")).right(6).to_upper(),
			used,
			int(item_data.get("fate_slot_capacity", 8)),
		]
	_label.font_size = 30
	_label.pixel_size = 0.010
	_label.outline_size = 8
	_label.modulate = color.lightened(0.20)
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
		"pickup_grace_active": Time.get_ticks_msec() < _pickup_grace_until_msec,
		"size_baseline_id": "entity_size_baseline_v2",
		"legacy_visual_scale": legacy_scale,
		"base_size_multiplier": CURRENT_BASE_SIZE_MULTIPLIER,
		"visual_scale": _visual.scale if _visual != null else Vector3.ZERO,
	}
