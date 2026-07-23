class_name DungeonRoom3D
extends Node3D
## 3D 房间构造器：房型、大小、门、家具、搜索点、服务点和灯具都通过配置组合。

signal player_entered(room: DungeonRoom3D)
signal prop_searched(room: DungeonRoom3D, loot: Dictionary)
signal service_activated(room: DungeonRoom3D, station: ServiceStation3D)

const LIGHT_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_wasteland_light_root_top3d_v001.tscn")
const LIGHT_SWITCH_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_light_switch_root_top3d_v001.tscn")
const FURNITURE_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_furniture_root_top3d_v001.tscn")
const SEARCH_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_search_container_root_top3d_v001.tscn")
const SERVICE_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_service_station_root_top3d_v001.tscn")
const HAZARD_SCENE: PackedScene = preload("res://assets/art/vfx/environment_3d/vfx_hazard_field_root_top3d_v001.tscn")
const DOOR_SCRIPT := preload("res://src/world3d/RoomDoor3D.gd")

const ROOM_DIMENSIONS := {
	# 约按 2D RoomData 的 0.034 m/px 映射，保留四档真实战斗尺度。
	"small": Vector2(22.0, 18.0),
	"medium": Vector2(32.0, 26.0),
	"large": Vector2(44.0, 34.0),
	"arena": Vector2(56.0, 42.0),
}

var room_id := "room_00"
var room_type := "COMBAT"
var size_class := "medium"
var doors: Array[String] = []
var door_targets: Dictionary = {}
var theme: DungeonTheme3D
var room_seed := 1
var is_main_path := true
var visited := false
var cleared := false
var enemy_spawn_points: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()
var _floor_material: StandardMaterial3D
var _wall_material: StandardMaterial3D
var _trim_material: StandardMaterial3D
var _detail_built := false
var _shell_built := false
var _stream_state := -1
var _door_nodes: Dictionary = {}
var _central_light: WastelandLight3D
var _light_switch: RoomLightSwitch3D


func configure(config: Dictionary) -> void:
	room_id = str(config.get("room_id", room_id))
	room_type = str(config.get("room_type", room_type)).to_upper()
	size_class = str(config.get("size_class", size_class))
	doors.assign(config.get("doors", []))
	door_targets = (config.get("door_targets", {}) as Dictionary).duplicate(true)
	theme = config.get("theme", theme) as DungeonTheme3D
	room_seed = int(config.get("seed", room_seed))
	is_main_path = bool(config.get("is_main_path", is_main_path))


func _ready() -> void:
	_rng.seed = room_seed
	if theme == null:
		theme = load("res://assets/art/environments/dungeon_3d/env_iron_frontier_kit_top3d_v001.tres") as DungeonTheme3D
	add_to_group("dungeon_room_3d")
	_build_spawn_points()
	set_stream_state(0)


func get_dimensions() -> Vector2:
	return ROOM_DIMENSIONS.get(size_class, ROOM_DIMENSIONS["medium"])


func get_room_snapshot() -> Dictionary:
	return {
		"room_id": room_id, "room_type": room_type, "size_class": size_class,
		"dimensions": get_dimensions(), "doors": doors.duplicate(), "visited": visited,
		"cleared": cleared, "is_main_path": is_main_path,
		"shell_built": _shell_built, "detail_built": _detail_built, "stream_state": _stream_state,
		"furniture_count": get_tree().get_nodes_in_group("room_prop_3d").filter(func(node): return is_ancestor_of(node)).size(),
		"light_count": get_tree().get_nodes_in_group("wasteland_light_3d").filter(func(node): return is_ancestor_of(node)).size(),
		"central_light": _central_light != null,
		"room_light_on": _central_light != null and _central_light.is_light_enabled(),
		"light_switch": _light_switch != null,
		"is_3d": true,
	}


func ensure_detail_built() -> void:
	if _detail_built:
		return
	_detail_built = true
	_build_content()


func ensure_shell_built() -> void:
	if _shell_built:
		return
	_shell_built = true
	_build_shell()
	_build_trigger()


func _prewarm_detail_if_streamed() -> void:
	if _stream_state > 0:
		ensure_detail_built()


func set_stream_state(state: int) -> void:
	var next_state := clampi(state, 0, 2)
	if next_state == _stream_state:
		return
	_stream_state = next_state
	if _stream_state > 0:
		ensure_shell_built()
		if _stream_state == 2:
			ensure_detail_built()
		else:
			call_deferred("_prewarm_detail_if_streamed")
	visible = _stream_state > 0
	process_mode = Node.PROCESS_MODE_INHERIT if _stream_state > 0 else Node.PROCESS_MODE_DISABLED
	_set_collision_enabled(self, _stream_state > 0)
	if _stream_state > 0:
		for value in _door_nodes.values():
			var door := value as RoomDoor3D
			if door != null:
				door.set_open(door.is_open, true)
	for child in get_children():
		if child is WastelandLight3D:
			(child as WastelandLight3D).set_runtime_active(
				_stream_state > 0, _stream_state == 2, _stream_state == 2
			)


func set_door_open(direction: String, opened: bool, immediate := false) -> void:
	if not _shell_built and _stream_state > 0:
		ensure_shell_built()
	var door := _door_nodes.get(direction) as RoomDoor3D
	if door != null:
		door.set_open(opened, immediate)


func get_nearest_door(player_position: Vector3, max_distance := 3.4) -> Dictionary:
	var nearest_distance := max_distance
	var nearest: RoomDoor3D = null
	for value in _door_nodes.values():
		var door := value as RoomDoor3D
		if door == null:
			continue
		var distance := player_position.distance_to(door.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = door
	for value in _door_nodes.values():
		var candidate := value as RoomDoor3D
		if candidate != null:
			candidate.set_prompt_visible(candidate == nearest)
	if nearest == null:
		return {}
	return {
		"direction": nearest.direction,
		"target_room_id": nearest.target_room_id,
		"is_open": nearest.is_open,
		"distance": nearest_distance,
	}


func hide_door_prompts() -> void:
	for value in _door_nodes.values():
		var door := value as RoomDoor3D
		if door != null:
			door.set_prompt_visible(false)


func _build_shell() -> void:
	var dimensions := get_dimensions()
	_floor_material = _material(theme.floor_color, 0.44, 0.72)
	_wall_material = _material(theme.wall_color, 0.62, 0.62)
	_trim_material = _material(theme.trim_color, 0.74, 0.38)
	_add_static_box("Floor", Vector3(0, -0.18, 0), Vector3(dimensions.x, 0.36, dimensions.y), _floor_material)
	_add_box("FloorInset", Vector3(0, 0.012, 0), Vector3(dimensions.x * 0.80, 0.025, dimensions.y * 0.80), _material(theme.floor_color.lightened(0.055), 0.36, 0.84))
	for x in range(-int(dimensions.x * 0.4), int(dimensions.x * 0.4), 3):
		_add_box("FloorSeam", Vector3(float(x), 0.03, 0), Vector3(0.025, 0.018, dimensions.y * 0.76), _trim_material)
	_build_wall("north", Vector3(0, 1.4, -dimensions.y * 0.5), dimensions.x, Vector3(1, 0, 0))
	_build_wall("south", Vector3(0, 1.4, dimensions.y * 0.5), dimensions.x, Vector3(1, 0, 0))
	_build_wall("west", Vector3(-dimensions.x * 0.5, 1.4, 0), dimensions.y, Vector3(0, 0, 1))
	_build_wall("east", Vector3(dimensions.x * 0.5, 1.4, 0), dimensions.y, Vector3(0, 0, 1))
	for direction in doors:
		_build_door(direction, str(door_targets.get(direction, "")), dimensions)
	for corner in [
		Vector3(-dimensions.x * 0.5, 1.45, -dimensions.y * 0.5),
		Vector3(dimensions.x * 0.5, 1.45, -dimensions.y * 0.5),
		Vector3(-dimensions.x * 0.5, 1.45, dimensions.y * 0.5),
		Vector3(dimensions.x * 0.5, 1.45, dimensions.y * 0.5),
	]:
		_add_static_box("CornerPost", corner, Vector3(0.42, 2.9, 0.42), _trim_material)


func _build_wall(direction: String, center: Vector3, length: float, axis: Vector3) -> void:
	var has_door := doors.has(direction)
	var thickness := 0.28
	var height := 2.8
	if not has_door:
		var size := Vector3(length, height, thickness) if axis.x > 0.0 else Vector3(thickness, height, length)
		_add_static_box("Wall_%s" % direction, center, size, _wall_material)
		return
	var opening := 3.8
	var segment_length := (length - opening) * 0.5
	for side in [-1.0, 1.0]:
		var offset: Vector3 = axis * float(side) * (opening * 0.5 + segment_length * 0.5)
		var segment_size := Vector3(segment_length, height, thickness) if axis.x > 0.0 else Vector3(thickness, height, segment_length)
		_add_static_box("Wall_%s" % direction, center + offset, segment_size, _wall_material)
	var lintel_size := Vector3(opening, 0.45, thickness * 1.28) if axis.x > 0.0 else Vector3(thickness * 1.28, 0.45, opening)
	_add_static_box("DoorLintel_%s" % direction, center + Vector3(0, 1.18, 0), lintel_size, _trim_material)


func _build_door(direction: String, target_room_id: String, dimensions: Vector2) -> void:
	var door := DOOR_SCRIPT.new() as RoomDoor3D
	door.configure(direction, target_room_id, theme.accent_color)
	match direction:
		"north":
			door.position = Vector3(0, 0, -dimensions.y * 0.5)
		"south":
			door.position = Vector3(0, 0, dimensions.y * 0.5)
		"west":
			door.position = Vector3(-dimensions.x * 0.5, 0, 0)
			door.rotation.y = PI * 0.5
		"east":
			door.position = Vector3(dimensions.x * 0.5, 0, 0)
			door.rotation.y = PI * 0.5
	add_child(door)
	_door_nodes[direction] = door


func _build_content() -> void:
	var dimensions := get_dimensions()
	_central_light = LIGHT_SCENE.instantiate() as WastelandLight3D
	_central_light.name = "RoomCeilingLight"
	_central_light.position = Vector3.ZERO
	_central_light.configure(
		theme.key_light_color,
		theme.fixture_energy * (3.25 if size_class in ["large", "arena"] else 2.75),
		maxf(theme.fixture_range * 1.32, minf(dimensions.x, dimensions.y) * 0.78),
		room_seed,
		true,
		false,
		"ceiling",
	)
	_central_light.set_light_enabled(false)
	add_child(_central_light)
	_central_light.add_to_group("wasteland_light_3d")

	_light_switch = LIGHT_SWITCH_SCENE.instantiate() as RoomLightSwitch3D
	_light_switch.name = "RoomLightSwitch3D"
	_place_light_switch(_light_switch, dimensions)
	_light_switch.configure(_central_light, false)
	add_child(_light_switch)

	var prop_count := 3 if size_class == "small" else 5 if size_class == "medium" else 7 if size_class == "large" else 9
	if room_type in ["STORAGE", "SCAVENGE", "BASEMENT"]:
		prop_count += 2
	for index in range(prop_count):
		var is_search := (
			room_type in ["STORAGE", "SCAVENGE", "EVENT", "BASEMENT"]
			and index < maxi(1, prop_count / 2)
		) or room_type in ["START", "EXTRACTION"] and index == 0
		var prop := (SEARCH_SCENE if is_search else FURNITURE_SCENE).instantiate() as RoomFurniture3D
		var type_options: Array[String] = theme.furniture_bias.duplicate()
		if room_type == "STORAGE":
			type_options.append_array(["locker", "shelf", "archive"])
		elif room_type == "UPGRADE":
			type_options.append_array(["workbench", "generator", "console"])
		elif room_type == "TRAP":
			type_options.append_array(["tank", "vat"])
		var prop_type := type_options[_rng.randi_range(0, type_options.size() - 1)] if not type_options.is_empty() else "crate"
		var prop_size := _choose_prop_size(index)
		prop.configure({
			"id": "%s_prop_%02d" % [room_id, index], "type": prop_type, "size": prop_size,
			"searchable": is_search, "accent": theme.accent_color, "base_color": theme.prop_color,
			"loot_value": 4 + theme.difficulty_rank * 2 + (6 if prop_size == "large" else 0),
		})
		var side := -1.0 if index % 2 == 0 else 1.0
		var row := index / 2
		var row_count := int(ceil(float(prop_count) / 2.0))
		var row_ratio := 0.5 if row_count <= 1 else float(row) / float(row_count - 1)
		var x_factor := 0.18 if size_class in ["large", "arena"] and row % 3 == 2 else 0.34
		prop.position = Vector3(side * dimensions.x * x_factor, 0, lerpf(-dimensions.y * 0.28, dimensions.y * 0.28, row_ratio))
		prop.rotation.y = 0.12 * side + PI * (1.0 if side > 0.0 else 0.0)
		add_child(prop)
		if is_search:
			prop.searched.connect(_on_prop_searched)

	if room_type in ["MERCHANT", "UPGRADE", "EVENT"]:
		var station := SERVICE_SCENE.instantiate() as ServiceStation3D
		var type_id := room_type.to_lower()
		var title: String = str({"merchant": "拾荒商终端", "upgrade": "武器改造台", "event": "异常信号终端"}.get(type_id, "废土终端"))
		station.configure(type_id, title, theme.accent_color)
		station.position = Vector3(0, 0, -dimensions.y * 0.27)
		add_child(station)
		station.activated.connect(_on_service_activated)
	if room_type in ["STAIRS_DOWN", "STAIRS_UP", "ELEVATOR"]:
		_build_vertical_access_marker(room_type)
	if room_type == "TRAP":
		var hazard := HAZARD_SCENE.instantiate() as HazardField3D
		hazard.configure(theme.hazard_color, 3.2 if size_class in ["large", "arena"] else 2.6, 6 + theme.difficulty_rank * 2)
		hazard.position = Vector3(0, 0.06, 0)
		add_child(hazard)


func _place_light_switch(light_switch: RoomLightSwitch3D, dimensions: Vector2) -> void:
	var side: int = absi(room_seed) % 4
	var x_margin := minf(4.2, dimensions.x * 0.22)
	var z_margin := minf(4.2, dimensions.y * 0.22)
	match side:
		0:
			light_switch.position = Vector3(x_margin, 0, -dimensions.y * 0.5 + 0.34)
			light_switch.rotation.y = 0.0
		1:
			light_switch.position = Vector3(-x_margin, 0, dimensions.y * 0.5 - 0.34)
			light_switch.rotation.y = PI
		2:
			light_switch.position = Vector3(-dimensions.x * 0.5 + 0.34, 0, z_margin)
			light_switch.rotation.y = -PI * 0.5
		_:
			light_switch.position = Vector3(dimensions.x * 0.5 - 0.34, 0, -z_margin)
			light_switch.rotation.y = PI * 0.5


func _build_vertical_access_marker(type_id: String) -> void:
	var up := type_id != "STAIRS_DOWN"
	var step_material := _material(theme.trim_color.lightened(0.08), 0.68, 0.48)
	for index in range(6):
		var step_height := 0.12 + index * 0.13 if up else 0.77 - index * 0.13
		_add_box("AccessStep", Vector3(0, step_height * 0.5, -2.2 + index * 0.75), Vector3(3.0, step_height, 0.72), step_material)
	var label := Label3D.new()
	label.position = Vector3(0, 2.2, 0)
	label.text = "电梯 / 垂直层" if type_id == "ELEVATOR" else "上层" if up else "地下层"
	label.font_size = 42
	label.pixel_size = 0.012
	label.modulate = theme.accent_color.lightened(0.18)
	label.outline_size = 8
	add_child(label)


func _choose_prop_size(index: int) -> String:
	if size_class == "small":
		return "small" if index % 3 != 0 else "medium"
	if size_class == "large":
		return ["small", "medium", "large"][index % 3]
	if size_class == "arena":
		return ["medium", "large", "small"][index % 3]
	return "medium" if index % 3 != 0 else "small"


func _build_trigger() -> void:
	var dimensions := get_dimensions()
	var area := Area3D.new()
	area.name = "RoomTrigger"
	area.collision_layer = 0
	area.collision_mask = 1
	add_child(area)
	var shape := BoxShape3D.new()
	shape.size = Vector3(dimensions.x * 0.72, 2.2, dimensions.y * 0.72)
	var collision := CollisionShape3D.new()
	collision.position.y = 0.9
	collision.shape = shape
	area.add_child(collision)
	area.body_entered.connect(_on_room_body_entered)


func _build_spawn_points() -> void:
	var dimensions := get_dimensions()
	var count := 3 if size_class == "small" else 5 if size_class == "medium" else 7 if size_class == "large" else 9
	for index in range(count):
		var angle := TAU * float(index) / float(count) + _rng.randf_range(-0.24, 0.24)
		enemy_spawn_points.append(global_position + Vector3(cos(angle) * dimensions.x * 0.23, 0.0, sin(angle) * dimensions.y * 0.23))


func _on_room_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player_3d"):
		return
	if not visited:
		visited = true
	player_entered.emit(self)


func _on_prop_searched(_prop: RoomFurniture3D, loot: Dictionary) -> void:
	prop_searched.emit(self, loot)


func _on_service_activated(station: ServiceStation3D) -> void:
	service_activated.emit(self, station)


func _add_static_box(node_name: String, position: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	body.name = "%sBody" % node_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = position
	add_child(body)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	body.add_child(instance)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


func _add_box(node_name: String, position: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.mesh = mesh
	add_child(instance)


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _set_collision_enabled(root: Node, enabled: bool) -> void:
	if root is CollisionShape3D:
		(root as CollisionShape3D).disabled = not enabled
	for child in root.get_children():
		_set_collision_enabled(child, enabled)
