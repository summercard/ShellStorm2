class_name GroundLootPickup3D
extends Area3D
## 3D 地面物品。先落地，接触时再请求进入 12 格背包；满包时保持在原地。

signal pickup_requested(pickup: GroundLootPickup3D, item_data: Dictionary)

var item_data: Dictionary = {}
var _visual: Node3D
var _accepted := false


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
	if _visual != null:
		_visual.rotation.y += delta * 1.35
		_visual.position.y = 0.46 + sin(Time.get_ticks_msec() * 0.0035 + float(get_instance_id() % 13)) * 0.07


func accept_pickup() -> void:
	if _accepted:
		return
	_accepted = true
	queue_free()


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
	var label := Label3D.new()
	label.position = Vector3(0, 1.05, 0)
	label.text = str(item_data.get("name", item_data.get("id", "物资")))
	label.font_size = 30
	label.pixel_size = 0.010
	label.outline_size = 8
	label.modulate = color.lightened(0.20)
	add_child(label)


func get_model_snapshot() -> Dictionary:
	return {
		"item_id": str(item_data.get("id", "")),
		"model_kind": ItemModelFactory3D.get_model_kind(item_data),
		"mesh_count": ItemModelFactory3D.count_mesh_instances(_visual) if _visual != null else 0,
		"uses_shared_model_factory": true,
	}
