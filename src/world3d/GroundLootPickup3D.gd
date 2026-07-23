class_name GroundLootPickup3D
extends Area3D
## 3D 地面物品。先落地，接触时再请求进入 12 格背包；满包时保持在原地。

signal pickup_requested(pickup: GroundLootPickup3D, item_data: Dictionary)

var item_data: Dictionary = {}
var _visual: Node3D
var _accepted := false
var _label: Label3D

const PICKUP_ANIMATION_DURATION := 0.32


func configure(data: Dictionary, color := Color(0.38, 0.88, 0.72)) -> void:
	item_data = data.duplicate(true)
	_build_visual(color)


func _ready() -> void:
	add_to_group("ground_loot_3d")
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if not _accepted and _visual != null:
		_visual.rotation.y += delta * 1.35
		_visual.position.y = 0.46 + sin(Time.get_ticks_msec() * 0.0035 + float(get_instance_id() % 13)) * 0.07


func accept_pickup() -> void:
	if _accepted:
		return
	_accepted = true
	monitoring = false
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
	if _accepted or not body.is_in_group("player_3d"):
		return
	pickup_requested.emit(self, item_data.duplicate(true))


func _build_visual(color: Color) -> void:
	_visual = ItemModelFactory3D.create_model(item_data, color)
	_visual.name = "LootVisual"
	_visual.scale = Vector3.ONE * (0.82 if str(item_data.get("type", "")) == "weapon" else 0.72)
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
	_label.font_size = 30
	_label.pixel_size = 0.010
	_label.outline_size = 8
	_label.modulate = color.lightened(0.20)
	add_child(_label)


func get_model_snapshot() -> Dictionary:
	return {
		"item_id": str(item_data.get("id", "")),
		"model_kind": ItemModelFactory3D.get_model_kind(item_data),
		"mesh_count": ItemModelFactory3D.count_mesh_instances(_visual) if _visual != null else 0,
		"uses_shared_model_factory": true,
		"accepted": _accepted,
		"pickup_animation_duration": PICKUP_ANIMATION_DURATION,
	}
