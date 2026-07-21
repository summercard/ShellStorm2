class_name DungeonRoom3D
extends Node3D
## 3D 房间构造器：房型、大小、门、家具、搜索点、服务点和灯具都通过配置组合。

signal player_entered(room: DungeonRoom3D)
signal prop_searched(room: DungeonRoom3D, loot: Dictionary)
signal service_activated(room: DungeonRoom3D, station: ServiceStation3D)

const LIGHT_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_wasteland_light_root_top3d_v001.tscn")
const FURNITURE_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_furniture_root_top3d_v001.tscn")
const SEARCH_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_search_container_root_top3d_v001.tscn")
const SERVICE_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_service_station_root_top3d_v001.tscn")
const HAZARD_SCENE: PackedScene = preload("res://assets/art/vfx/environment_3d/vfx_hazard_field_root_top3d_v001.tscn")

const ROOM_DIMENSIONS := {
	"small": Vector2(12.0, 11.0),
	"medium": Vector2(16.0, 14.0),
	"large": Vector2(22.0, 18.0),
}

var room_id := "room_00"
var room_type := "COMBAT"
var size_class := "medium"
var doors: Array[String] = []
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


func configure(config: Dictionary) -> void:
	room_id = str(config.get("room_id", room_id))
	room_type = str(config.get("room_type", room_type)).to_upper()
	size_class = str(config.get("size_class", size_class))
	doors.assign(config.get("doors", []))
	theme = config.get("theme", theme) as DungeonTheme3D
	room_seed = int(config.get("seed", room_seed))
	is_main_path = bool(config.get("is_main_path", is_main_path))


func _ready() -> void:
	_rng.seed = room_seed
	if theme == null:
		theme = load("res://assets/art/environments/dungeon_3d/env_iron_frontier_kit_top3d_v001.tres") as DungeonTheme3D
	add_to_group("dungeon_room_3d")
	_build_shell()
	_build_content()
	_build_trigger()
	_build_spawn_points()


func get_dimensions() -> Vector2:
	return ROOM_DIMENSIONS.get(size_class, ROOM_DIMENSIONS["medium"])


func get_room_snapshot() -> Dictionary:
	return {
		"room_id": room_id, "room_type": room_type, "size_class": size_class,
		"dimensions": get_dimensions(), "doors": doors.duplicate(), "visited": visited,
		"cleared": cleared, "is_main_path": is_main_path,
		"furniture_count": get_tree().get_nodes_in_group("room_prop_3d").filter(func(node): return is_ancestor_of(node)).size(),
		"light_count": get_tree().get_nodes_in_group("wasteland_light_3d").filter(func(node): return is_ancestor_of(node)).size(),
		"is_3d": true,
	}


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


func _build_content() -> void:
	var dimensions := get_dimensions()
	for index in range(2 if size_class != "large" else 3):
		var light := LIGHT_SCENE.instantiate() as WastelandLight3D
		var x := dimensions.x * (-0.32 if index % 2 == 0 else 0.32)
		var z := dimensions.y * (-0.28 if index < 2 else 0.30)
		light.position = Vector3(x, 0, z)
		light.rotation.y = 0.0 if x < 0.0 else PI
		light.configure(theme.key_light_color, theme.fixture_energy, theme.fixture_range, room_seed + index, index == 0 and size_class == "large", index != 0)
		add_child(light)
		light.add_to_group("wasteland_light_3d")

	var prop_count := 2 if size_class == "small" else 4 if size_class == "medium" else 6
	if room_type in ["STORAGE", "SCAVENGE"]:
		prop_count += 2
	for index in range(prop_count):
		var is_search := room_type in ["STORAGE", "SCAVENGE", "EVENT"] and index < maxi(1, prop_count / 2)
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
		var row := float(index / 2)
		prop.position = Vector3(side * dimensions.x * 0.34, 0, -dimensions.y * 0.25 + row * 2.5)
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
	if room_type == "TRAP":
		var hazard := HAZARD_SCENE.instantiate() as HazardField3D
		hazard.configure(theme.hazard_color, 2.2 if size_class != "large" else 2.8, 6 + theme.difficulty_rank * 2)
		hazard.position = Vector3(0, 0.06, 0)
		add_child(hazard)


func _choose_prop_size(index: int) -> String:
	if size_class == "small":
		return "small" if index % 3 != 0 else "medium"
	if size_class == "large":
		return ["small", "medium", "large"][index % 3]
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
	var count := 2 if size_class == "small" else 3 if size_class == "medium" else 5
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
