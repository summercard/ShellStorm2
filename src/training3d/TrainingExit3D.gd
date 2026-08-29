class_name TrainingExit3D
extends Area3D

signal exit_requested

var _player_in_range := false
var _prompt: Label3D


func _ready() -> void:
	add_to_group(PlayerInteractionController3D.PROVIDER_GROUP)
	collision_layer = 0
	collision_mask = 1
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_visual()


func get_interaction_candidate(_player: Player3D) -> Dictionary:
	if not _player_in_range:
		return {}
	return {
		"available": true,
		"interaction_id": "training_exit:%d" % get_instance_id(),
		"position": global_position,
		"priority": 90,
		"prompt": _prompt.text if _prompt != null else "[E] 返回3D基地",
	}


func set_interaction_focus(_candidate: Dictionary, focused: bool) -> void:
	if _prompt != null:
		_prompt.visible = focused and _player_in_range


func perform_interaction(_player: Player3D, _candidate: Dictionary) -> bool:
	if not _player_in_range:
		return false
	exit_requested.emit()
	return true


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player_3d"):
		_player_in_range = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player_3d"):
		_player_in_range = false
		_prompt.visible = false


func _build_visual() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.24, 0.25)
	material.emission_enabled = true
	material.emission = Color(0.18, 0.70, 0.78)
	material.emission_energy_multiplier = 1.2
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.2, 2.6, 0.28)
	mesh.material = material
	var door := MeshInstance3D.new()
	door.position.y = 1.3
	door.mesh = mesh
	add_child(door)
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.3, 3.0, 2.2)
	var collision := CollisionShape3D.new()
	collision.position = Vector3(0, 1.3, -0.7)
	collision.shape = shape
	add_child(collision)
	_prompt = Label3D.new()
	_prompt.position = Vector3(0, 3.05, 0)
	_prompt.text = "[E] 返回3D基地"
	_prompt.font_size = 42
	_prompt.pixel_size = 0.012
	_prompt.outline_size = 9
	_prompt.modulate = Color(0.45, 0.92, 1.0)
	_prompt.visible = false
	add_child(_prompt)
