class_name ExtractionBeacon3D
extends Area3D

signal extraction_started(duration: float)
signal extraction_progress(progress: float)
signal extraction_cancelled
signal extraction_completed

@export var accent_color := Color(0.32, 0.88, 1.0)
@export_range(1.0, 10.0, 0.25) var duration := 4.0

var locked := true
var _player_in_range := false
var _active := false
var _remaining := 0.0
var _prompt: Label3D
var _light: OmniLight3D


func configure(color: Color, p_duration: float) -> void:
	accent_color = color
	duration = p_duration


func _ready() -> void:
	add_to_group("extraction_beacon_3d")
	collision_layer = 0
	collision_mask = 1
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_visual()
	_refresh_prompt()


func _process(delta: float) -> void:
	rotation.y += delta * 0.36
	if _light != null:
		_light.light_energy = 2.2 + sin(Time.get_ticks_msec() * 0.004) * 0.35
	if not _active:
		return
	if not _player_in_range:
		_cancel()
		return
	_remaining = maxf(0.0, _remaining - delta)
	extraction_progress.emit(1.0 - _remaining / maxf(0.01, duration))
	_prompt.text = "撤离同步 %.1fs" % _remaining
	if _remaining <= 0.0:
		_active = false
		extraction_completed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range or _active or not event.is_action_pressed("interact"):
		return
	get_viewport().set_input_as_handled()
	if locked:
		_prompt.text = "Boss 信号仍在干扰"
		return
	_active = true
	_remaining = duration
	extraction_started.emit(duration)


func set_locked(value: bool) -> void:
	locked = value
	if value and _active:
		_cancel()
	_refresh_prompt()


func force_complete_for_test() -> void:
	if locked:
		return
	extraction_completed.emit()


func _cancel() -> void:
	_active = false
	_remaining = 0.0
	_refresh_prompt()
	extraction_cancelled.emit()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player_3d"):
		_player_in_range = true
		_prompt.visible = true
		_refresh_prompt()


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player_3d"):
		_player_in_range = false
		_prompt.visible = false


func _refresh_prompt() -> void:
	if _prompt == null:
		return
	_prompt.text = "信号锁定 · 先击败 Boss" if locked else "[E] 启动撤离同步"


func _build_visual() -> void:
	var metal := _material(Color(0.07, 0.10, 0.11), 0.74, 0.36)
	var glow := _material(accent_color, 0.16, 0.22, true)
	_add_cylinder("Base", Vector3(0, 0.18, 0), 1.1, 0.34, metal)
	_add_cylinder("Core", Vector3(0, 1.15, 0), 0.28, 2.0, glow)
	for index in range(3):
		var ring := _add_torus("Ring", Vector3(0, 0.65 + index * 0.55, 0), 0.52 + index * 0.12, 0.07, glow)
		ring.rotation_degrees.x = 90.0 if index % 2 == 0 else 0.0
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 1.5, 0)
	_light.light_color = accent_color
	_light.omni_range = 7.0
	_light.light_energy = 2.4
	add_child(_light)
	var shape := CylinderShape3D.new()
	shape.radius = 2.0
	shape.height = 2.5
	var collision := CollisionShape3D.new()
	collision.position.y = 1.0
	collision.shape = shape
	add_child(collision)
	_prompt = Label3D.new()
	_prompt.position = Vector3(0, 2.75, 0)
	_prompt.font_size = 42
	_prompt.pixel_size = 0.012
	_prompt.modulate = accent_color.lightened(0.18)
	_prompt.outline_size = 9
	_prompt.visible = false
	add_child(_prompt)


func _add_cylinder(node_name: String, position: Vector3, radius: float, height: float, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.mesh = mesh
	add_child(instance)
	return instance


func _add_torus(node_name: String, position: Vector3, radius: float, thickness: float, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius
	mesh.outer_radius = radius + thickness
	mesh.rings = 24
	mesh.ring_segments = 7
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.mesh = mesh
	add_child(instance)
	return instance


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
