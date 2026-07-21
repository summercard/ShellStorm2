class_name ServiceStation3D
extends Area3D

signal activated(station: ServiceStation3D)

@export_enum("merchant", "upgrade", "event", "reset") var station_type := "event"
@export var display_name := "废土终端"
@export var accent_color := Color(0.40, 0.82, 0.92)

var _player_in_range := false
var _prompt: Label3D


func configure(type_id: String, title: String, color: Color) -> void:
	station_type = type_id
	display_name = title
	accent_color = color


func _ready() -> void:
	add_to_group("service_station_3d")
	collision_layer = 0
	collision_mask = 1
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_visual()


func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range or not event.is_action_pressed("interact"):
		return
	get_viewport().set_input_as_handled()
	activated.emit(self)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player_3d"):
		_player_in_range = true
		_prompt.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player_3d"):
		_player_in_range = false
		_prompt.visible = false


func _build_visual() -> void:
	var metal := _material(Color(0.08, 0.11, 0.12), 0.72, 0.44)
	var trim := _material(accent_color.darkened(0.18), 0.42, 0.38)
	var glow := _material(accent_color, 0.12, 0.22, true)
	_add_box("Base", Vector3(0, 0.55, 0), Vector3(1.45, 1.1, 0.85), metal)
	var screen := _add_box("Screen", Vector3(0, 1.05, -0.48), Vector3(1.04, 0.54, 0.06), glow)
	screen.rotation_degrees.x = -12.0
	_add_box("Trim", Vector3(0, 0.28, -0.47), Vector3(1.22, 0.10, 0.07), trim)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.45, 1.1, 0.85)
	collision.position = Vector3(0, 0.55, 0)
	collision.shape = shape
	body.add_child(collision)
	var interaction := CollisionShape3D.new()
	var interaction_shape := BoxShape3D.new()
	interaction_shape.size = Vector3(2.8, 2.2, 2.2)
	interaction.position = Vector3(0, 0.8, 0)
	interaction.shape = interaction_shape
	add_child(interaction)

	_prompt = Label3D.new()
	_prompt.position = Vector3(0, 1.92, 0)
	_prompt.text = "[E] %s" % display_name
	_prompt.font_size = 38
	_prompt.pixel_size = 0.012
	_prompt.modulate = accent_color.lightened(0.22)
	_prompt.outline_size = 8
	_prompt.visible = false
	add_child(_prompt)


func _add_box(node_name: String, position: Vector3, size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
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
