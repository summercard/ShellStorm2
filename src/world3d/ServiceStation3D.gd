class_name ServiceStation3D
extends Area3D

signal activated(station: ServiceStation3D)

@export_enum("merchant", "upgrade", "event", "reset") var station_type := "event"
@export var display_name := "废土终端"
@export var accent_color := Color(0.40, 0.82, 0.92)

var _player_in_range := false
var _prompt: Label3D
var _objective_label: Label3D
var _physical_collision: CollisionShape3D


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

	# 事件终端是房间必做目标，不能因为镜头裁切或模型载入异常留下“透明阻挡”。
	# 商店/改造台保留实体体积；事件终端只用交互 Area，不阻断角色移动。
	if station_type != "event":
		var body := StaticBody3D.new()
		body.name = "StationBody"
		body.collision_layer = 1
		body.collision_mask = 0
		add_child(body)
		_physical_collision = CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.45, 1.1, 0.85)
		_physical_collision.position = Vector3(0, 0.55, 0)
		_physical_collision.shape = shape
		body.add_child(_physical_collision)
	var interaction := CollisionShape3D.new()
	var interaction_shape := BoxShape3D.new()
	interaction_shape.size = Vector3(2.8, 2.2, 2.2)
	interaction.position = Vector3(0, 0.8, 0)
	interaction.shape = interaction_shape
	add_child(interaction)

	_prompt = Label3D.new()
	_prompt.position = Vector3(0, 1.92, 0)
	_prompt.text = (
		"[E] 结算房间事件"
		if station_type == "event"
		else "[E] %s" % display_name
	)
	_prompt.font_size = 38
	_prompt.pixel_size = 0.012
	_prompt.modulate = accent_color.lightened(0.22)
	_prompt.outline_size = 8
	_prompt.visible = false
	add_child(_prompt)
	if station_type == "event":
		_build_event_objective_marker(glow)


func get_snapshot() -> Dictionary:
	return {
		"station_type": station_type,
		"display_name": display_name,
		"player_in_range": _player_in_range,
		"prompt_visible": _prompt != null and _prompt.visible,
		"objective_marker_visible": _objective_label != null and _objective_label.visible,
		"blocks_player": _physical_collision != null and not _physical_collision.disabled,
		"required_room_objective": bool(get_meta("required_room_objective", false)),
	}


func set_objective_resolved() -> void:
	if station_type != "event":
		return
	_player_in_range = false
	if _prompt != null:
		_prompt.visible = false
	for node_name in ["EventObjectiveFloorMarker", "EventObjectiveBeacon", "EventObjectiveLabel"]:
		var marker := get_node_or_null(node_name) as Node3D
		if marker != null:
			marker.visible = false
	set_deferred("monitoring", false)


func _build_event_objective_marker(glow: StandardMaterial3D) -> void:
	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = 1.75
	marker_mesh.bottom_radius = 1.75
	marker_mesh.height = 0.035
	marker_mesh.radial_segments = 32
	marker_mesh.material = glow
	var marker := MeshInstance3D.new()
	marker.name = "EventObjectiveFloorMarker"
	marker.position = Vector3(0, 0.025, 0)
	marker.mesh = marker_mesh
	add_child(marker)

	var beacon_mesh := BoxMesh.new()
	beacon_mesh.size = Vector3(0.08, 2.4, 0.08)
	beacon_mesh.material = glow
	var beacon := MeshInstance3D.new()
	beacon.name = "EventObjectiveBeacon"
	beacon.position = Vector3(0, 1.55, 0)
	beacon.mesh = beacon_mesh
	add_child(beacon)

	_objective_label = Label3D.new()
	_objective_label.name = "EventObjectiveLabel"
	_objective_label.position = Vector3(0, 2.85, 0)
	_objective_label.text = "事件目标 · 异常信号终端"
	_objective_label.font_size = 34
	_objective_label.pixel_size = 0.012
	_objective_label.modulate = accent_color.lightened(0.30)
	_objective_label.outline_size = 8
	_objective_label.no_depth_test = true
	add_child(_objective_label)


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
