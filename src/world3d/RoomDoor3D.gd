class_name RoomDoor3D
extends StaticBody3D
## 一条地图边在房间侧的实体门。地图边状态由 Dungeon3D 统一管理，门只负责表现、阻挡和提示。

var direction := "east"
var target_room_id := ""
var is_open := false
var _panel: MeshInstance3D
var _collision: CollisionShape3D
var _prompt: Label3D


func configure(p_direction: String, p_target_room_id: String, accent: Color) -> void:
	direction = p_direction
	target_room_id = p_target_room_id
	_build(accent)


func set_open(opened: bool, immediate := false) -> void:
	var changed := is_open != opened
	is_open = opened
	if _collision != null:
		_collision.set_deferred("disabled", opened)
	if _prompt != null:
		_prompt.text = "通道已开启" if opened else "[E] 使用房间钥匙"
		_prompt.modulate = Color(0.42, 0.92, 0.68) if opened else Color(1.0, 0.72, 0.22)
	if _panel == null:
		return
	var target_y := 3.2 if opened else 1.15
	if immediate or not is_inside_tree() or not changed:
		_panel.position.y = target_y
	else:
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(_panel, "position:y", target_y, 0.24)


func set_prompt_visible(show_prompt: bool) -> void:
	if _prompt != null:
		_prompt.visible = show_prompt


func get_snapshot() -> Dictionary:
	return {
		"direction": direction,
		"target_room_id": target_room_id,
		"is_open": is_open,
		"blocks_passage": _collision != null and not _collision.disabled,
		"is_3d": true,
	}


func _build(accent: Color) -> void:
	if _panel != null:
		return
	name = "Door_%s" % direction.capitalize()
	collision_layer = 1
	collision_mask = 0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.11, 0.13, 0.13)
	material.metallic = 0.78
	material.roughness = 0.34
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(3.25, 2.3, 0.30)
	panel_mesh.material = material
	_panel = MeshInstance3D.new()
	_panel.name = "DoorPanel"
	_panel.position.y = 1.15
	_panel.mesh = panel_mesh
	add_child(_panel)
	var stripe_material := StandardMaterial3D.new()
	stripe_material.albedo_color = accent
	stripe_material.emission_enabled = true
	stripe_material.emission = accent
	stripe_material.emission_energy_multiplier = 1.5
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(2.55, 0.12, 0.035)
	stripe_mesh.material = stripe_material
	var stripe := MeshInstance3D.new()
	stripe.name = "LockStripe"
	stripe.position = Vector3(0, 0, -0.17)
	stripe.mesh = stripe_mesh
	_panel.add_child(stripe)
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.25, 2.3, 0.42)
	_collision = CollisionShape3D.new()
	_collision.name = "DoorCollision"
	_collision.position.y = 1.15
	_collision.shape = shape
	add_child(_collision)
	_prompt = Label3D.new()
	_prompt.name = "DoorPrompt"
	_prompt.position = Vector3(0, 2.75, 0)
	_prompt.text = "[E] 使用房间钥匙"
	_prompt.font_size = 38
	_prompt.pixel_size = 0.011
	_prompt.outline_size = 8
	_prompt.modulate = Color(1.0, 0.72, 0.22)
	_prompt.visible = false
	add_child(_prompt)
	set_open(false, true)
