extends Node3D
## 只提交总电源命令；能源与存档由 BaseManager 唯一拥有。

var _indicator: StandardMaterial3D


func _ready() -> void:
	add_to_group(PlayerInteractionController3D.PROVIDER_GROUP)
	_indicator = StandardMaterial3D.new()
	_indicator.emission_enabled = true
	var lamp := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.055
	mesh.height = 0.11
	lamp.mesh = mesh
	lamp.material_override = _indicator
	lamp.position = Vector3(0.43, 0.93, -1.02)
	lamp.name = "PowerSwitchIndicator"
	add_child(lamp)
	BaseManager.base_power_changed.connect(_update_indicator)
	_update_indicator(BaseManager.is_base_power_on())


func _update_indicator(enabled: bool) -> void:
	var color := Color(0.15, 0.9, 0.35) if enabled else Color(0.75, 0.12, 0.08)
	_indicator.albedo_color = color
	_indicator.emission = color


func get_interaction_candidate(player: Player3D) -> Dictionary:
	if player == null or player.global_position.distance_to(global_position) > 2.8:
		return {}
	return {
		"available": true,
		"interaction_id": "rooftop_generator_power",
		"position": global_position,
		"priority": 65,
		"prompt": "[E] 关闭发电机 · 基地总电源" if BaseManager.is_base_power_on() else "[E] 启动发电机 · 基地总电源",
	}


func perform_interaction(player: Player3D, _candidate: Dictionary) -> bool:
	if get_interaction_candidate(player).is_empty():
		return false
	var result := BaseManager.set_base_generator_enabled(not BaseManager.is_base_power_on())
	return bool(result.get("success", false))


func get_interaction_dot_anchor() -> Vector3:
	return global_position + Vector3(0, 1.5, 0)


func is_interaction_dot_visible() -> bool:
	return true
