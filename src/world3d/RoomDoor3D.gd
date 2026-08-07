class_name RoomDoor3D
extends StaticBody3D
## 一条地图边在房间侧的实体门。地图边状态由 Dungeon3D 统一管理，门只负责表现、阻挡和提示。

const TOWER_GEOMETRY := preload("res://src/world3d/TowerGeometry3D.gd")
const PANEL_THICKNESS_M := 0.18
const COLLISION_DEPTH_M := 0.42
const OPEN_LIFT_CLEARANCE_M := 0.32

var direction := "east"
var target_room_id := ""
var is_open := false
var requires_key := true
var requires_clear := true
var triggers_fate := true
var _panel: MeshInstance3D
var _collision: CollisionShape3D
var _prompt: Label3D


func configure(p_direction: String, p_target_room_id: String, accent: Color) -> void:
	direction = p_direction
	target_room_id = p_target_room_id
	_build(accent)


func set_access_policy(policy: Dictionary) -> void:
	requires_key = bool(policy.get("requires_key", true))
	requires_clear = bool(policy.get("requires_clear", true))
	triggers_fate = bool(policy.get("triggers_fate", true))
	_refresh_prompt()


func set_open(opened: bool, immediate := false) -> void:
	var changed := is_open != opened
	is_open = opened
	if _collision != null:
		_collision.set_deferred("disabled", opened)
	_refresh_prompt()
	if _panel == null:
		return
	var closed_y := TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M * 0.5
	var target_y := (
		TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M * 1.5 + OPEN_LIFT_CLEARANCE_M
		if opened
		else closed_y
	)
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
		"requires_key": requires_key,
		"requires_clear": requires_clear,
		"triggers_fate": triggers_fate,
		"blocks_passage": _collision != null and not _collision.disabled,
		"clear_width_m": TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M,
		"clear_height_m": TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M,
		"panel_size": Vector3(
			TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M,
			TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M,
			PANEL_THICKNESS_M
		),
		"is_3d": true,
	}


func _refresh_prompt() -> void:
	if _prompt == null:
		return
	if is_open:
		_prompt.text = "通道已开启"
		_prompt.modulate = Color(0.42, 0.92, 0.68)
	elif requires_key:
		_prompt.text = "[E] 使用房间钥匙"
		_prompt.modulate = Color(1.0, 0.72, 0.22)
	elif triggers_fate:
		_prompt.text = "[E] 开启入口 · 选择命运"
		_prompt.modulate = Color(0.44, 0.88, 1.0)
	else:
		_prompt.text = "[E] 开启通道"
		_prompt.modulate = Color(0.52, 0.94, 0.80)


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
	panel_mesh.size = Vector3(
		TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M,
		TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M,
		PANEL_THICKNESS_M
	)
	panel_mesh.material = material
	_panel = MeshInstance3D.new()
	_panel.name = "DoorPanel"
	_panel.position.y = TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M * 0.5
	_panel.mesh = panel_mesh
	add_child(_panel)
	var stripe_material := StandardMaterial3D.new()
	stripe_material.albedo_color = accent
	stripe_material.emission_enabled = true
	stripe_material.emission = accent
	stripe_material.emission_energy_multiplier = 1.5
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(
		TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M * 0.72,
		0.11,
		0.035
	)
	stripe_mesh.material = stripe_material
	var stripe := MeshInstance3D.new()
	stripe.name = "LockStripe"
	stripe.position = Vector3(0, 0, -0.17)
	stripe.mesh = stripe_mesh
	_panel.add_child(stripe)
	var stripe_back := MeshInstance3D.new()
	stripe_back.name = "LockStripeBack"
	stripe_back.position = Vector3(0, 0, 0.17)
	stripe_back.mesh = stripe_mesh
	_panel.add_child(stripe_back)
	var shape := BoxShape3D.new()
	shape.size = Vector3(
		TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M,
		TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M,
		COLLISION_DEPTH_M
	)
	_collision = CollisionShape3D.new()
	_collision.name = "DoorCollision"
	_collision.position.y = TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M * 0.5
	_collision.shape = shape
	add_child(_collision)
	_prompt = Label3D.new()
	_prompt.name = "DoorPrompt"
	_prompt.position = Vector3(
		0,
		TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M + 0.62,
		0
	)
	_prompt.text = "[E] 使用房间钥匙"
	_prompt.font_size = 38
	_prompt.pixel_size = 0.011
	_prompt.outline_size = 8
	_prompt.visible = false
	add_child(_prompt)
	set_open(false, true)
