class_name RoomLightSwitch3D
extends Area3D
## 房间墙面灯开关。只控制真实房间灯，不参与 PlayerVision3D 的玩法显隐。

signal light_toggled(is_on: bool)

const INTERACTION_RANGE := 2.2

var _controlled_lights: Array[WastelandLight3D] = []
var _player_in_range := false
var _prompt: Label3D
var _indicator_material: StandardMaterial3D


func configure(controlled_light: WastelandLight3D, starts_on := false) -> void:
	var lights: Array[WastelandLight3D] = []
	if controlled_light != null:
		lights.append(controlled_light)
	configure_group(lights, starts_on)


func configure_group(
	controlled_lights: Array[WastelandLight3D],
	starts_on := false
) -> void:
	_controlled_lights.clear()
	for light in controlled_lights:
		if light != null and is_instance_valid(light):
			_controlled_lights.append(light)
			light.set_light_enabled(starts_on)
	_update_state_visual()


func _ready() -> void:
	add_to_group("room_light_switch_3d")
	add_to_group(PlayerInteractionController3D.PROVIDER_GROUP)
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = true
	_build_visual()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_update_state_visual()


func get_interaction_candidate(_player: Player3D) -> Dictionary:
	if not _player_in_range or _controlled_lights.is_empty():
		return {}
	return {
		"available": true,
		"interaction_id": "room_light:%d" % get_instance_id(),
		"position": global_position,
		"priority": 50,
		"prompt": _prompt.text if _prompt != null else "[E] 切换中央灯",
	}


func set_interaction_focus(_candidate: Dictionary, focused: bool) -> void:
	set_prompt_visible(focused and _player_in_range)


func perform_interaction(_player: Player3D, _candidate: Dictionary) -> bool:
	return _player_in_range and toggle_light()


func toggle_light() -> bool:
	_prune_invalid_lights()
	if _controlled_lights.is_empty():
		return false
	var next_state := not is_light_on()
	for light in _controlled_lights:
		light.set_light_enabled(next_state)
	_update_state_visual()
	light_toggled.emit(next_state)
	return true


func set_light_on(enabled: bool) -> bool:
	_prune_invalid_lights()
	if _controlled_lights.is_empty():
		return false
	for light in _controlled_lights:
		light.set_light_enabled(enabled)
	_update_state_visual()
	return true


func is_light_on() -> bool:
	_prune_invalid_lights()
	if _controlled_lights.is_empty():
		return false
	for light in _controlled_lights:
		if not light.is_light_enabled():
			return false
	return true


func set_prompt_visible(visible_state: bool) -> void:
	if _prompt != null:
		_prompt.visible = visible_state


func get_snapshot() -> Dictionary:
	return {
		"light_on": is_light_on(),
		"player_in_range": _player_in_range,
		"has_prompt": _prompt != null,
		"controlled_light_count": _controlled_lights.size(),
		"is_3d": true,
	}


func _prune_invalid_lights() -> void:
	for index in range(_controlled_lights.size() - 1, -1, -1):
		if not is_instance_valid(_controlled_lights[index]):
			_controlled_lights.remove_at(index)


func _build_visual() -> void:
	if get_node_or_null("SwitchPlate") != null:
		return
	var metal := _material(Color(0.10, 0.12, 0.13), 0.72, 0.34)
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(0.54, 0.72, 0.14)
	plate_mesh.material = metal
	var plate := MeshInstance3D.new()
	plate.name = "SwitchPlate"
	plate.position.y = 1.0
	plate.mesh = plate_mesh
	add_child(plate)

	_indicator_material = _material(Color(0.70, 0.14, 0.10), 0.12, 0.30, true)
	var indicator_mesh := SphereMesh.new()
	indicator_mesh.radius = 0.075
	indicator_mesh.height = 0.15
	indicator_mesh.radial_segments = 10
	indicator_mesh.rings = 5
	indicator_mesh.material = _indicator_material
	var indicator := MeshInstance3D.new()
	indicator.name = "Indicator"
	indicator.position = Vector3(0, 1.17, -0.11)
	indicator.mesh = indicator_mesh
	add_child(indicator)

	var lever_mesh := BoxMesh.new()
	lever_mesh.size = Vector3(0.10, 0.28, 0.10)
	lever_mesh.material = _material(Color(0.66, 0.68, 0.65), 0.84, 0.24)
	var lever := MeshInstance3D.new()
	lever.name = "Lever"
	lever.position = Vector3(0, 0.91, -0.12)
	lever.mesh = lever_mesh
	add_child(lever)

	var shape := SphereShape3D.new()
	shape.radius = INTERACTION_RANGE
	var collision := CollisionShape3D.new()
	collision.position.y = 0.9
	collision.shape = shape
	add_child(collision)

	_prompt = Label3D.new()
	_prompt.name = "InteractLabel"
	_prompt.position = Vector3(0, 1.75, 0)
	_prompt.font_size = 34
	_prompt.pixel_size = 0.010
	_prompt.outline_size = 8
	_prompt.modulate = Color(0.88, 0.94, 0.90)
	_prompt.no_depth_test = true
	_prompt.visible = false
	add_child(_prompt)


func _update_state_visual() -> void:
	var enabled := is_light_on()
	if _prompt != null:
		_prompt.text = "[E] 关闭中央灯" if enabled else "[E] 开启中央灯"
	if _indicator_material != null:
		var color := Color(0.26, 0.92, 0.50) if enabled else Color(0.78, 0.16, 0.10)
		_indicator_material.albedo_color = color
		_indicator_material.emission = color


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player_3d"):
		_player_in_range = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player_3d"):
		_player_in_range = false
		set_prompt_visible(false)


func _material(color: Color, metallic: float, roughness: float, emission := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.8
	return material
