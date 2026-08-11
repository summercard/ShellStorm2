class_name DungeonRoom3D
extends Node3D
## 3D 房间构造器：房型、大小、门、家具、搜索点、服务点和灯具都通过配置组合。
## 几何全部由 prefab .tscn 提供；脚本只做"找 prefab → 实例化 → 设位置/缩放/材质"。

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
const TOWER_GEOMETRY := preload("res://src/world3d/TowerGeometry3D.gd")

# —— 5m 塔楼模块 prefab（A 节）
const TOWER_WALL_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_wall_solid_5m.tscn"
)
const TOWER_DOOR_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_wall_door_5m.tscn"
)
const TOWER_PARAPET_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_wall_parapet_5m.tscn"
)
const TOWER_PARAPET_DOOR_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_wall_parapet_door_5m.tscn"
)
# 4 拐角模块
const TOWER_CORNER_L_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_corner_L_5m.tscn"
)
const TOWER_CORNER_T_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_corner_T_5m.tscn"
)
const TOWER_CORNER_X_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_corner_X_5m.tscn"
)
const TOWER_CORNER_L_PARAPET_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_corner_L_parapet_5m.tscn"
)
const TOWER_FLOOR_TILE_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_floor_tile_5m.tscn"
)
# —— 房间壳体原子件 prefab（B 节）
const FLOOR_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_floor.tscn")
const FLOOR_INSET_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_floor_inset.tscn")
const FLOOR_SEAM_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_floor_seam_strip.tscn")
const WALL_SEGMENT_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_wall_segment.tscn")
const WALL_DOOR_SEGMENT_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_wall_door_segment.tscn")
const DOOR_LINTEL_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_door_lintel.tscn")
const CORNER_POST_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_corner_post.tscn")
const PARTITION_VERTICAL_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_floor_partition_vertical.tscn")
const PARTITION_HORIZONTAL_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_floor_partition_horizontal.tscn")
# —— 楼顶/楼梯厅装饰 prefab（C 节）
const ROOFTOP_FACADE_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_rooftop_facade.tscn")
const ROOFTOP_FACADE_BAND_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_rooftop_facade_band.tscn")
const ROOFTOP_RAIL_LOWER_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_rooftop_railing_lower.tscn")
const ROOFTOP_RAIL_UPPER_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_rooftop_railing_upper.tscn")
const ROOFTOP_RAIL_POST_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_rooftop_rail_post.tscn")
const ROOFTOP_STAIR_FRAME_POST_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_rooftop_stair_frame_post.tscn")
const ROOFTOP_STAIR_FRAME_LINTEL_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_rooftop_stair_frame_lintel.tscn")
const ROOFTOP_DESCENT_MARKER_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_rooftop_descent_marker.tscn")
const STAIR_LOBBY_ROUTE_GUIDE_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_stair_lobby_route_guide.tscn")
const STAIR_LOBBY_THRESHOLD_GUIDE_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_stair_lobby_threshold_guide.tscn")
const ACCESS_STEP_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_access_step.tscn")
const VERTICAL_ACCESS_LABEL_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_vertical_access_marker_label.tscn")
const FLOOR_TILE_MATERIAL_LIGHT: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_override_top3d_v001.tres"
)
const FLOOR_TILE_MATERIAL_DARK: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_dark_top3d_v001.tres"
)
# v0.1 v2 拼接交替材质（A/B 微差异版）
const FLOOR_TILE_MATERIAL_A: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_warm_a_v001.tres"
)
const FLOOR_TILE_MATERIAL_B: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_warm_b_v001.tres"
)
const WALL_SOLID_MATERIAL_A: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_tower_wall_solid_a_v001.tres"
)
const WALL_SOLID_MATERIAL_B: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_tower_wall_solid_b_v001.tres"
)
# —— 基地专属材质（FACILITY 房间使用，不影响战斗房 / 屋顶 / 楼梯厅）。
# 棋盘 A 格 = 深褐主色、B 格 = 亮深褐；墙 = 尘深蓝；装饰带 trim 与地板同色系。
const FACILITY_FLOOR_TILE_A: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_facility_floor_tile_a_v001.tres"
)
const FACILITY_FLOOR_TILE_B: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_facility_floor_tile_b_v001.tres"
)
const FACILITY_WALL_MATERIAL: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_facility_wall_v001.tres"
)
const FACILITY_TRIM_MATERIAL: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_facility_trim_v001.tres"
)
const ROOFTOP_FACADE_HEIGHT := 6.0
static var _tower_solid_wall_mesh: Mesh
static var _tower_floor_tile_mesh: Mesh

const ROOM_DIMENSIONS := {
	# 约按 2D RoomData 的 0.034 m/px 映射，保留四档真实战斗尺度。
	"small": Vector2(22.0, 18.0),
	"medium": Vector2(32.0, 26.0),
	"large": Vector2(44.0, 34.0),
	"arena": Vector2(56.0, 42.0),
	# v0.1 塔楼入口使用固定真实尺度；不改变既有四档房间契约。
	"floor": Vector2(65.0, 65.0),
	"rooftop": Vector2(65.0, 65.0),
	"tower_cell": Vector2(15.0, 15.0),
}

var room_id := "room_00"
var room_type := "COMBAT"
var size_class := "medium"
var doors: Array[String] = []
var door_targets: Dictionary = {}
var door_policies: Dictionary = {}
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
var _room_lights: Array[WastelandLight3D] = []
var _light_switch: RoomLightSwitch3D
var custom_dimensions := Vector2.ZERO
var tower_module_shell := false
var open_wall_directions: Array[String] = []


func configure(config: Dictionary) -> void:
	room_id = str(config.get("room_id", room_id))
	room_type = str(config.get("room_type", room_type)).to_upper()
	size_class = str(config.get("size_class", size_class))
	doors.assign(config.get("doors", []))
	door_targets = (config.get("door_targets", {}) as Dictionary).duplicate(true)
	door_policies = (config.get("door_policies", {}) as Dictionary).duplicate(true)
	theme = config.get("theme", theme) as DungeonTheme3D
	room_seed = int(config.get("seed", room_seed))
	is_main_path = bool(config.get("is_main_path", is_main_path))
	custom_dimensions = config.get("custom_dimensions", custom_dimensions) as Vector2
	tower_module_shell = bool(config.get("tower_module_shell", tower_module_shell))
	open_wall_directions.assign(config.get("open_wall_directions", []))


func _ready() -> void:
	_rng.seed = room_seed
	if theme == null:
		theme = load("res://assets/art/environments/dungeon_3d/env_iron_frontier_kit_top3d_v001.tres") as DungeonTheme3D
	add_to_group("dungeon_room_3d")
	_build_spawn_points()
	set_stream_state(0)


func get_dimensions() -> Vector2:
	if custom_dimensions.x > 0.0 and custom_dimensions.y > 0.0:
		return custom_dimensions
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
		"room_light_on": _light_switch != null and _light_switch.is_light_on(),
		"light_switch": _light_switch != null,
		"controlled_light_count": _room_lights.size(),
		"shadow_capable_light_count": _count_shadow_capable_lights(),
		"active_shadow_light_count": _count_active_shadow_lights(),
		"room_light_cull_mask": GameDesignConfig.LIGHT_MASK_WORLD_AND_PLAYER,
		"base_grid_dimensions": Vector2i(6, 6) if room_type == "FACILITY" else Vector2i.ZERO,
		"base_grid_tile_count": 36 if room_type == "FACILITY" else 0,
		"base_grid_tile_count_light": 18 if room_type == "FACILITY" else 0,
		"base_grid_tile_count_dark": 18 if room_type == "FACILITY" else 0,
		"base_grid_checkerboard_pattern": room_type == "FACILITY",
		"tower_wall_module_count": _count_nodes_with_meta(self, "asset_id", "ENV-TOWER-WALL-SOLID-5M"),
		"tower_door_wall_module_count": _count_nodes_with_meta(self, "asset_id", "ENV-TOWER-WALL-DOOR-5M"),
		"tower_corner_module_count": _count_nodes_with_meta(self, "asset_id", "ENV-TOWER-CORNER-L-5M"),
		"wall_material_variant_a_count": _count_nodes_with_meta(self, "material_variant", "A"),
		"wall_material_variant_b_count": _count_nodes_with_meta(self, "material_variant", "B"),
		"tower_module_shell": tower_module_shell,
		"open_wall_directions": open_wall_directions.duplicate(),
		"wall_height": TOWER_GEOMETRY.FLOOR_HEIGHT_M if tower_module_shell else 2.8,
		"support_collision_persistent": _has_enabled_support_collision(),
		"service_station_count": _get_service_stations().size(),
		"event_objective_ready": get_service_station("event") != null,
		"door_snapshots": _get_door_snapshots(),
		"is_3d": true,
	}


## 正式运行时 O(1) 读取。完整 get_room_snapshot() 会扫描节点组和递归统计
## 组件，只允许验收/调试低频调用，禁止在 _process/_physics_process 中使用。
func get_stream_state() -> int:
	return _stream_state


func is_streamed() -> bool:
	return _stream_state > 0


func ensure_detail_built() -> void:
	if _detail_built:
		return
	_detail_built = true
	_build_content()
	_set_room_light_runtime_state(self)


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
	# 远层只卸载通行/交互碰撞，承重楼板永久保留。否则隐藏楼层时，
	# 仍驻留的掉落或冻结实体可能穿过已卸载楼板坠向更深层。
	_set_collision_enabled(self, _stream_state > 0, true)
	if _stream_state > 0:
		for value in _door_nodes.values():
			var door := value as RoomDoor3D
			if door != null:
				door.set_open(door.is_open, true)
	_set_room_light_runtime_state(self)


func _set_room_light_runtime_state(root: Node) -> void:
	for child in root.get_children():
		if child is WastelandLight3D:
			(child as WastelandLight3D).set_runtime_active(
				_stream_state > 0, _stream_state == 2, _stream_state == 2
			)
		else:
			_set_room_light_runtime_state(child)


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


func get_door_node(direction: String) -> RoomDoor3D:
	return _door_nodes.get(direction) as RoomDoor3D


func get_service_station(type_id := "") -> ServiceStation3D:
	for station in _get_service_stations():
		if type_id.is_empty() or station.station_type == type_id:
			return station
	return null


func ensure_required_service_station() -> ServiceStation3D:
	if room_type not in ["MERCHANT", "UPGRADE", "EVENT"]:
		return null
	ensure_detail_built()
	var type_id := room_type.to_lower()
	var existing := get_service_station(type_id)
	if existing != null:
		return existing
	return _create_service_station(type_id, get_dimensions())


func _get_service_stations() -> Array[ServiceStation3D]:
	var result: Array[ServiceStation3D] = []
	for child in get_children():
		if child is ServiceStation3D:
			result.append(child as ServiceStation3D)
	return result


func _build_shell() -> void:
	var dimensions := get_dimensions()
	_floor_material = _material(theme.floor_color, 0.08, 0.90)
	_wall_material = _material(theme.wall_color, 0.62, 0.62)
	_trim_material = _material(theme.trim_color, 0.74, 0.38)
	# 基地走专属材质：地板用 FACILITY_FLOOR_TILE_A/B（由 _build_base_facility_shell
	# 单独覆盖），墙由 _get_wall_module_material 接管，trim 替换为深褐色装饰带。
	if room_type == "FACILITY":
		_trim_material = FACILITY_TRIM_MATERIAL
	if tower_module_shell:
		_build_tower_module_shell(dimensions)
		return
	# Floor：1×1×1 prefab + scale = (dim.x, 0.36, dim.y)
	_spawn_prefab("Floor", FLOOR_PREFAB, Vector3(0, -0.18, 0), Vector3(dimensions.x, 0.36, dimensions.y), _floor_material)
	_spawn_prefab("FloorInset", FLOOR_INSET_PREFAB, Vector3(0, 0.012, 0), Vector3(dimensions.x * 0.80, 0.025, dimensions.y * 0.80), _material(theme.floor_color.lightened(0.055), 0.04, 0.94))
	for x in range(-int(dimensions.x * 0.4), int(dimensions.x * 0.4), 3):
		_spawn_prefab("FloorSeam", FLOOR_SEAM_PREFAB, Vector3(float(x), 0.03, 0), Vector3(0.025, 0.018, dimensions.y * 0.76), _trim_material)
	if size_class == "rooftop":
		_build_rooftop_shell(dimensions)
		return
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
		_spawn_prefab("CornerPost", CORNER_POST_PREFAB, corner, Vector3(0.42, 2.9, 0.42), _trim_material)
	if size_class == "floor":
		_build_floor_partitions(dimensions)


func _build_rooftop_shell(dimensions: Vector2) -> void:
	for direction in ["north", "south", "west", "east"]:
		_build_rooftop_exterior_wall(direction, dimensions)
		_build_rooftop_railing(direction, dimensions)
	for direction in doors:
		_build_door(direction, str(door_targets.get(direction, "")), dimensions)
	var access_direction := doors[0] if not doors.is_empty() else "west"
	var access_center := Vector3.ZERO
	match access_direction:
		"west":
			access_center = Vector3(-dimensions.x * 0.5, 1.45, 0)
		"east":
			access_center = Vector3(dimensions.x * 0.5, 1.45, 0)
		"north":
			access_center = Vector3(0, 1.45, -dimensions.y * 0.5)
		_:
			access_center = Vector3(0, 1.45, dimensions.y * 0.5)
	var frame_axis_x := access_direction in ["north", "south"]
	for side in [-1.0, 1.0]:
		var frame_half_width := TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M * 0.5 + 0.22
		var post_offset := Vector3(side * frame_half_width, 0, 0) if frame_axis_x else Vector3(0, 0, side * frame_half_width)
		_spawn_prefab("RooftopStairFramePost", ROOFTOP_STAIR_FRAME_POST_PREFAB, access_center + post_offset, Vector3(0.34, 2.9, 0.34), _wall_material)
	var frame_span := TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M + 0.78
	var lintel_size := Vector3(frame_span, 0.38, 0.34) if frame_axis_x else Vector3(0.34, 0.38, frame_span)
	_spawn_prefab("RooftopStairFrameLintel", ROOFTOP_STAIR_FRAME_LINTEL_PREFAB, access_center + Vector3(0, 1.24, 0), lintel_size, _wall_material)
	# 楼梯头顶部做缺口标识；真正通行口仍由公共 RoomDoor3D 阻挡与开启。
	var marker := ROOFTOP_DESCENT_MARKER_PREFAB.instantiate() as Node3D
	marker.name = "RooftopDescentMarker"
	marker.position = access_center + Vector3(0, 1.9, 0)
	var label3d := marker.get_node("RooftopDescentMarker") as Label3D
	if label3d != null:
		label3d.text = "下行楼梯"
		label3d.modulate = theme.accent_color.lightened(0.18)
	add_child(marker)


func _build_rooftop_exterior_wall(direction: String, dimensions: Vector2) -> void:
	var horizontal := direction in ["north", "south"]
	var length := dimensions.x if horizontal else dimensions.y
	var has_door := doors.has(direction)
	var facade_material := _material(theme.wall_color.lightened(0.14), 0.54, 0.68)
	var facade_band_material := _material(theme.trim_color.lightened(0.10), 0.70, 0.42)
	facade_material.emission_enabled = true
	facade_material.emission = theme.wall_color.lightened(0.24)
	facade_material.emission_energy_multiplier = 0.28
	facade_band_material.emission_enabled = true
	facade_band_material.emission = theme.trim_color.lightened(0.18)
	facade_band_material.emission_energy_multiplier = 0.46
	# 立面门洞贯穿本层高度，让上下两端都沿同一门轴进入楼梯间。
	var opening := TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M if has_door else 0.0
	var segment_length := (length - opening) * 0.5 if has_door else length
	var centers: Array[float] = [0.0]
	if has_door:
		centers = [
			-(opening * 0.5 + segment_length * 0.5),
			opening * 0.5 + segment_length * 0.5,
		]
	for segment_center in centers:
		var center := Vector3.ZERO
		if horizontal:
			center = Vector3(
				segment_center,
				-ROOFTOP_FACADE_HEIGHT * 0.5,
				-dimensions.y * 0.5 if direction == "north" else dimensions.y * 0.5
			)
		else:
			center = Vector3(
				-dimensions.x * 0.5 if direction == "west" else dimensions.x * 0.5,
				-ROOFTOP_FACADE_HEIGHT * 0.5,
				segment_center
			)
		var size := (
			Vector3(segment_length, ROOFTOP_FACADE_HEIGHT, 0.54)
			if horizontal
			else Vector3(0.54, ROOFTOP_FACADE_HEIGHT, segment_length)
		)
		# 立面是视觉楼体；屋顶边界、门和楼梯间各自承担真实碰撞，避免重复墙体卡人。
		_spawn_prefab("RooftopExteriorWall_%s" % direction, ROOFTOP_FACADE_PREFAB, center, size, facade_material)
		for band_y in [-0.72, -5.28]:
			var band_center := Vector3(center.x, band_y, center.z)
			var band_size := (
				Vector3(segment_length, 0.18, 0.62)
				if horizontal
				else Vector3(0.62, 0.18, segment_length)
			)
			_spawn_prefab("RooftopExteriorBand_%s" % direction, ROOFTOP_FACADE_BAND_PREFAB, band_center, band_size, facade_band_material)


func _build_rooftop_railing(direction: String, dimensions: Vector2) -> void:
	var horizontal := direction in ["north", "south"]
	var length := dimensions.x if horizontal else dimensions.y
	var has_door := doors.has(direction)
	var opening := TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M if has_door else 0.0
	var segment_length := (length - opening) * 0.5 if has_door else length
	var centers: Array[float] = [0.0]
	if has_door:
		centers = [
			-(opening * 0.5 + segment_length * 0.5),
			opening * 0.5 + segment_length * 0.5,
		]
	for segment_center in centers:
		var center := Vector3.ZERO
		if horizontal:
			center = Vector3(segment_center, 0.62, -dimensions.y * 0.5 if direction == "north" else dimensions.y * 0.5)
		else:
			center = Vector3(-dimensions.x * 0.5 if direction == "west" else dimensions.x * 0.5, 0.62, segment_center)
		var rail_size := Vector3(segment_length, 0.12, 0.18) if horizontal else Vector3(0.18, 0.12, segment_length)
		_spawn_prefab("RooftopRailLower_%s" % direction, ROOFTOP_RAIL_LOWER_PREFAB, center, rail_size, _trim_material)
		_spawn_prefab("RooftopRailUpper_%s" % direction, ROOFTOP_RAIL_UPPER_PREFAB, center + Vector3(0, 0.62, 0), rail_size, _trim_material)
		var post_count := maxi(2, int(segment_length / 4.0) + 1)
		for post_index in range(post_count):
			var ratio := float(post_index) / float(maxi(1, post_count - 1))
			var offset := lerpf(-segment_length * 0.5, segment_length * 0.5, ratio)
			var post_position := center
			if horizontal:
				post_position.x += offset
			else:
				post_position.z += offset
			post_position.y = 0.66
			_spawn_prefab("RooftopRailPost_%s" % direction, ROOFTOP_RAIL_POST_PREFAB, post_position, Vector3(0.16, 1.32, 0.16), _trim_material)


func _build_tower_module_shell(dimensions: Vector2) -> void:
	if (
		room_type == "FACILITY"
		and is_equal_approx(dimensions.x, 30.0)
		and is_equal_approx(dimensions.y, 30.0)
	):
		_build_base_facility_shell(dimensions)
		return
	# v0.1 v2：4 拐角 + 边墙拟合 + 门洞
	_build_tower_wall_v2(dimensions)


func _build_base_facility_shell(dimensions: Vector2) -> void:
	# 30m 基地使用 6×6 的 5m 美术地砖；下方 TowerFloorStage 继续承担整层
	# 承重碰撞，因此这里的地砖只做轻微抬升的视觉层，避免重复碰撞。
	var floor_mesh := _get_tower_floor_tile_mesh()
	if floor_mesh != null:
		var light_transforms: Array[Transform3D] = []
		var dark_transforms: Array[Transform3D] = []
		for tile_z in range(6):
			for tile_x in range(6):
				var transform := Transform3D(
					Basis.IDENTITY,
					Vector3(
						-12.5 + float(tile_x) * TOWER_GEOMETRY.GRID_UNIT_M,
						0.015,
						-12.5 + float(tile_z) * TOWER_GEOMETRY.GRID_UNIT_M
					)
				)
				if (tile_x + tile_z) % 2 == 0:
					light_transforms.append(transform)
				else:
					dark_transforms.append(transform)
		_add_base_floor_grid(
			"BaseFloorGrid6x6_A",
			floor_mesh,
			light_transforms,
			FACILITY_FLOOR_TILE_A
		)
		_add_base_floor_grid(
			"BaseFloorGrid6x6_B",
			floor_mesh,
			dark_transforms,
			FACILITY_FLOOR_TILE_B
		)
	# 基地与楼顶/战斗房统一复用 5m 实墙、门墙和独立拐角组件。
	# 不再用整条 Box 拉伸成墙，门洞表现、碰撞和 RoomDoor3D 触发保持同源。
	_build_tower_wall_v2(dimensions)


func _add_base_floor_grid(
	node_name: String,
	floor_mesh: Mesh,
	transforms: Array[Transform3D],
	material: StandardMaterial3D
) -> void:
	var floor_multimesh := MultiMesh.new()
	floor_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	floor_multimesh.mesh = floor_mesh
	floor_multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		floor_multimesh.set_instance_transform(index, transforms[index])
	var floor_grid := MultiMeshInstance3D.new()
	floor_grid.name = node_name
	floor_grid.multimesh = floor_multimesh
	floor_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	floor_grid.material_override = material
	floor_grid.set_meta("asset_id", "ENV-TOWER-FLOOR-TILE-5M")
	floor_grid.set_meta("grid_dimensions", Vector2i(6, 6))
	add_child(floor_grid)


func _get_tower_floor_tile_mesh() -> Mesh:
	if _tower_floor_tile_mesh != null:
		return _tower_floor_tile_mesh
	var source := TOWER_FLOOR_TILE_PREFAB.instantiate()
	_tower_floor_tile_mesh = _find_first_mesh(source)
	source.free()
	return _tower_floor_tile_mesh


func _build_tower_wall_run(direction: String, dimensions: Vector2) -> void:
	var horizontal := direction in ["north", "south"]
	var length := dimensions.x if horizontal else dimensions.y
	var module_count := maxi(1, int(round(length / TOWER_GEOMETRY.GRID_UNIT_M)))
	var has_door := doors.has(direction)
	# 门模块位置：选择最接近沿墙中心的模块；6 段选择 2 或 3，哪个离 0 近选哪个。
	var door_index := 0
	if has_door:
		var candidate_a := int(floor((module_count - 1) / 2.0))
		var candidate_b := int(ceil((module_count - 1) / 2.0))
		var pos_a := -length * 0.5 + TOWER_GEOMETRY.GRID_UNIT_M * (float(candidate_a) + 0.5)
		var pos_b := -length * 0.5 + TOWER_GEOMETRY.GRID_UNIT_M * (float(candidate_b) + 0.5)
		door_index = candidate_a if absf(pos_a) <= absf(pos_b) else candidate_b
		var door_offset_along := -length * 0.5 + TOWER_GEOMETRY.GRID_UNIT_M * (float(door_index) + 0.5)
		set_meta("tower_wall_door_offset_%s" % direction, door_offset_along)
	var wall_offset := dimensions.y * 0.5 if horizontal else dimensions.x * 0.5
	var solid_transforms: Array[Transform3D] = []
	for module_index in range(module_count):
		var along := -length * 0.5 + TOWER_GEOMETRY.GRID_UNIT_M * (float(module_index) + 0.5)
		var module_position := Vector3.ZERO
		var rotation_y := 0.0
		match direction:
			"north":
				module_position = Vector3(along, 0.0, -wall_offset)
			"south":
				module_position = Vector3(along, 0.0, wall_offset)
				rotation_y = PI
			"west":
				module_position = Vector3(-wall_offset, 0.0, along)
				rotation_y = PI * 0.5
			_:
				module_position = Vector3(wall_offset, 0.0, along)
				rotation_y = -PI * 0.5
		var is_door_module := has_door and module_index == door_index
		if is_door_module:
			var module := TOWER_DOOR_PREFAB.instantiate() as Node3D
			module.name = "Imported_DoorWall5M_%s_I%02d" % [
				direction.capitalize(),
				module_index,
			]
			module.position = module_position
			module.rotation.y = rotation_y
			module.set_meta("asset_id", "ENV-TOWER-WALL-DOOR-5M")
			module.set_meta("grid_unit_m", TOWER_GEOMETRY.GRID_UNIT_M)
			module.set_meta("tower_wall_direction", direction)
			_set_camera_lower_wall_on_static_bodies(
				module, direction in ["north", "south"]
			)
			add_child(module)
			_add_tower_wall_collision(
				direction,
				module_position,
				rotation_y,
				true,
				module_index
			)
		else:
			solid_transforms.append(Transform3D(
				Basis(Vector3.UP, rotation_y),
				module_position
			))
	_spawn_solid_wall_visual_instances(direction, solid_transforms)
	_add_tower_solid_run_collision(
		direction,
		length,
		module_count,
		door_index,
		has_door,
		wall_offset
	)


func _build_tower_wall_multimesh(
	direction: String,
	transforms: Array[Transform3D]
) -> void:
	var mesh := _get_tower_solid_wall_mesh()
	if mesh == null or transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		var wall_transform := transforms[index]
		wall_transform.origin.y += TOWER_GEOMETRY.FLOOR_HEIGHT_M * 0.5
		multimesh.set_instance_transform(index, wall_transform)
	var visual := MultiMeshInstance3D.new()
	visual.name = "Imported_SolidWall5M_%s_Run" % direction.capitalize()
	visual.multimesh = multimesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	visual.set_meta("asset_id", "ENV-TOWER-WALL-SOLID-5M")
	visual.set_meta("grid_unit_m", TOWER_GEOMETRY.GRID_UNIT_M)
	visual.set_meta("tower_wall_direction", direction)
	add_child(visual)


## v0.1 v2 拼接交替装饰：每段 5m 实例一个 MeshInstance3D，偶奇 index 分 A/B 两色。
## 墙同一段与地砖同步节奏（同一房间内统一定义）。
func _spawn_solid_wall_visual_instances(
	direction: String,
	transforms: Array[Transform3D],
	segment_indices: Array[int] = []
) -> void:
	var mesh := _get_tower_solid_wall_mesh()
	if mesh == null or transforms.is_empty():
		return
	var container := Node3D.new()
	container.name = "Imported_SolidWall5M_%s_Run" % direction.capitalize()
	container.set_meta("asset_id", "ENV-TOWER-WALL-SOLID-5M")
	container.set_meta("grid_unit_m", TOWER_GEOMETRY.GRID_UNIT_M)
	container.set_meta("tower_wall_direction", direction)
	add_child(container)
	for index in range(transforms.size()):
		var abs_segment_index := (
			segment_indices[index]
			if index < segment_indices.size()
			else index
		)
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.material_override = _get_wall_module_material(abs_segment_index)
		var wall_transform := transforms[index]
		# BoxMesh 原点在几何中心；抬高半层后才是从地面到 9m，而不是 -4.5~+4.5m。
		wall_transform.origin.y += TOWER_GEOMETRY.FLOOR_HEIGHT_M * 0.5
		visual.transform = wall_transform
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		visual.name = "Imported_SolidWall5M_%s_I%02d" % [
			direction.capitalize(),
			abs_segment_index,
		]
		visual.set_meta("asset_id", "ENV-TOWER-WALL-SOLID-5M")
		visual.set_meta("segment_index", abs_segment_index)
		visual.set_meta("material_variant", "A" if abs_segment_index % 2 == 0 else "B")
		container.add_child(visual)


func _get_tower_solid_wall_mesh() -> Mesh:
	if _tower_solid_wall_mesh != null:
		return _tower_solid_wall_mesh
	var source := TOWER_WALL_PREFAB.instantiate()
	_tower_solid_wall_mesh = _find_first_mesh(source)
	source.free()
	return _tower_solid_wall_mesh


func _find_first_mesh(root: Node) -> Mesh:
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		return (root as MeshInstance3D).mesh
	for child in root.get_children():
		var found := _find_first_mesh(child)
		if found != null:
			return found
	return null


## v0.1 v2 模块化墙拼装：4 拐角 + 边墙 + 门洞
## 以门的世界坐标为锥点：拿到门 world pos → 拆为沿墙距离 → 取最近 5m 段作门洞。
## 拼装规则：
##   1. 4 拐角 L 形各布于房间四角原点，2.5m 双向覆盖
##   2. 4 边墙剔除两端 2.5m 后用 5m 单元填：门洞取距 door world pos 最近的 5m 段
##   3. 门洞剩余部分仍走 _build_door 独立挂门
func _build_tower_wall_v2(dimensions: Vector2) -> void:
	var wall_directions: Array[String] = ["north", "south", "west", "east"]
	if size_class == "rooftop":
		var access_direction := doors[0] if not doors.is_empty() else "west"
		wall_directions.assign([access_direction])
		if access_direction in ["west", "east"]:
			wall_directions.append("north")
			wall_directions.append("south")
		else:
			wall_directions.append("west")
			wall_directions.append("east")
	for open_direction in open_wall_directions:
		wall_directions.erase(open_direction)
	# 1. 拼 4 拐角 L 型（房间四角）
	if size_class != "rooftop":
		_spawn_room_corner(Vector2(-dimensions.x * 0.5, -dimensions.y * 0.5), "NW")
		_spawn_room_corner(Vector2(dimensions.x * 0.5, -dimensions.y * 0.5), "NE")
		_spawn_room_corner(Vector2(-dimensions.x * 0.5, dimensions.y * 0.5), "SW")
		_spawn_room_corner(Vector2(dimensions.x * 0.5, dimensions.y * 0.5), "SE")
	# 2. 每条边跳过两端 2.5m，用 5m 单元填。门洞位置由门 world pos 准动计算。
	for direction in wall_directions:
		_build_corner_aware_wall_run(direction, dimensions)
	# 3. 门洞仍走原 _build_door
	for direction in doors:
		_build_door(direction, str(door_targets.get(direction, "")), dimensions)


## 将房间门 world pos 折算为“沿墙距离”（沿该边从负端点量起的米数）
func _local_along_from_door_world(direction: String, door_world: Vector3, dimensions: Vector2) -> float:
	var horizontal := direction in ["north", "south"]
	var wall_offset := dimensions.y * 0.5 if horizontal else dimensions.x * 0.5
	var center := global_position
	var local := door_world - center
	# 沿墙轴的投影分量：n/s 门走 ±x，w/e 门走 ±z
	var along_local: float
	if horizontal:
		along_local = local.x
		if direction == "south":
			along_local = -along_local
	else:
		along_local = local.z
		if direction == "east":
			along_local = -along_local
	# local 中已含“沿墙距离 = 门 world 距房中心”在墙面投影后的位置
	# （world_x - center_x）与 wall_offset 无关，该偏移是横向墙厚
	return along_local


## 拼接一条边墙：剔除两端 5m（跨过拐角覆盖区）后用 5m 单元填
## 边墙与地砖严格对齐同 5m 网格：地砖 6×6 的房间，边墙 6 段总数中 2 端被拐角覆盖，中间 4 段拼接。
func _build_corner_aware_wall_run(direction: String, dimensions: Vector2) -> void:
	var horizontal := direction in ["north", "south"]
	var length := dimensions.x if horizontal else dimensions.y
	var wall_offset := dimensions.y * 0.5 if horizontal else dimensions.x * 0.5
	# 门预留：直接读 _plan_room_layout 写入的 meta “tower_wall_door_offset_<dir>”
	var has_door := doors.has(direction)
	var door_index := -1
	if has_door:
		var door_offset_along := float(get_meta("tower_wall_door_offset_%s" % direction, 0.0))
		# 反推 door_index：6 段 30m 房，段中心 = -length/2 + 5*(index+0.5)
		var module_count_full := maxi(1, int(round(length / TOWER_GEOMETRY.GRID_UNIT_M)))
		for module_index in range(module_count_full):
			var segment_center := -length * 0.5 + TOWER_GEOMETRY.GRID_UNIT_M * (float(module_index) + 0.5)
			if absf(segment_center - door_offset_along) < 0.01:
				door_index = module_index
				break
	# 墙段范围：从段 1 开始（跳过段 0 拐角覆盖）到段 module_count-2 结束（跳过末段拐角）
	var module_count := maxi(1, int(round(length / TOWER_GEOMETRY.GRID_UNIT_M)))
	var start_index := 1
	var end_index := module_count - 2
	if end_index < start_index:
		return
	var middle_module_count := end_index - start_index + 1
	var solid_transforms: Array[Transform3D] = []
	var solid_segment_indices: Array[int] = []
	for module_index in range(start_index, end_index + 1):
		var along := -length * 0.5 + TOWER_GEOMETRY.GRID_UNIT_M * (float(module_index) + 0.5)
		var is_door_module := has_door and module_index == door_index
		var module_position := Vector3.ZERO
		var rotation_y := 0.0
		match direction:
			"north":
				module_position = Vector3(along, 0.0, -wall_offset)
			"south":
				module_position = Vector3(along, 0.0, wall_offset)
				rotation_y = PI
			"west":
				module_position = Vector3(-wall_offset, 0.0, along)
				rotation_y = PI * 0.5
			_:
				module_position = Vector3(wall_offset, 0.0, along)
				rotation_y = -PI * 0.5
		if is_door_module:
			var module := TOWER_DOOR_PREFAB.instantiate() as Node3D
			module.name = "Imported_DoorWall5M_%s_I%02d" % [
				direction.capitalize(),
				module_index,
			]
			module.position = module_position
			module.rotation.y = rotation_y
			module.set_meta("asset_id", "ENV-TOWER-WALL-DOOR-5M")
			module.set_meta("grid_unit_m", TOWER_GEOMETRY.GRID_UNIT_M)
			module.set_meta("tower_wall_direction", direction)
			_apply_module_material_variant(module, module_index)
			_set_camera_lower_wall_on_static_bodies(
				module, direction in ["north", "south"]
			)
			add_child(module)
			_add_tower_wall_collision(
				direction,
				module_position,
				rotation_y,
				true,
				module_index
			)
		else:
			solid_transforms.append(Transform3D(
				Basis(Vector3.UP, rotation_y),
				module_position
			))
			solid_segment_indices.append(module_index)
	_spawn_solid_wall_visual_instances(
		direction,
		solid_transforms,
		solid_segment_indices
	)
	var collision_start := -length * 0.5 + TOWER_GEOMETRY.GRID_UNIT_M * float(start_index)
	var collision_end := -length * 0.5 + TOWER_GEOMETRY.GRID_UNIT_M * float(end_index + 1)
	_add_corner_aware_solid_run_collision(
		direction,
		wall_offset,
		collision_start,
		collision_end,
		has_door,
		door_index
	)


## 拐角 L 拼装。从 4 个角位置以合适的 rotation 报入。
## corner_id: "NW" / "NE" / "SW" / "SE"
func _spawn_room_corner(corner_pos: Vector2, corner_id: String) -> void:
	var module := TOWER_CORNER_L_PREFAB.instantiate() as Node3D
	module.name = "Imported_CornerL5M_%s" % corner_id
	module.position = Vector3(corner_pos.x, 0.0, corner_pos.y)
	# L 默认 long=+X, short=-Z
	# NW 角：需 long=+X(东), short=+Z(南) → rotation_y = -PI/2
	# NE 角：需 long=-X(西), short=+Z(南) → rotation_y = PI
	# SW 角：需 long=+X(东), short=-Z(北) → rotation_y = 0
	# SE 角：需 long=-X(西), short=-Z(北) → rotation_y = PI/2
	match corner_id:
		"NW": module.rotation.y = -PI * 0.5
		"NE": module.rotation.y = PI
		"SW": module.rotation.y = 0.0
		"SE": module.rotation.y = PI * 0.5
	module.set_meta("asset_id", "ENV-TOWER-CORNER-L-5M")
	module.set_meta("tower_wall_corner", corner_id)
	# 拐角两条墙臂使用独立碰撞：SW 的长臂、SE 的短臂才属于南墙。
	# 不能把整个 L 角标记为南墙，否则西/东侧臂也会错误推动摄像机。
	_configure_corner_camera_collisions(module, corner_id)
	var corner_variant_index := 0 if corner_id in ["NW", "SE"] else 1
	_apply_module_material_variant(module, corner_variant_index)
	add_child(module)


func _get_wall_module_material(segment_index: int) -> StandardMaterial3D:
	# 基地走专属尘深蓝墙（不分 A/B 段交替，整墙统一色）。
	# 其他房间沿用塔楼暖色 A/B 段交替，保留模块拼接节奏。
	if room_type == "FACILITY":
		return FACILITY_WALL_MATERIAL
	return WALL_SOLID_MATERIAL_A if segment_index % 2 == 0 else WALL_SOLID_MATERIAL_B


func _apply_module_material_variant(module: Node, segment_index: int) -> void:
	var variant := "A" if segment_index % 2 == 0 else "B"
	var material := _get_wall_module_material(segment_index)
	module.set_meta("segment_index", segment_index)
	module.set_meta("material_variant", variant)
	if module is MeshInstance3D:
		(module as MeshInstance3D).material_override = material
	for child in module.get_children():
		_apply_module_material_override(child, material)


func _apply_module_material_override(root: Node, material: Material) -> void:
	if root is MeshInstance3D:
		(root as MeshInstance3D).material_override = material
	for child in root.get_children():
		_apply_module_material_override(child, material)


func _count_nodes_with_meta(root: Node, key: String, value: Variant) -> int:
	var count := 1 if root.has_meta(key) and root.get_meta(key) == value else 0
	for child in root.get_children():
		count += _count_nodes_with_meta(child, key, value)
	return count


func _count_shadow_capable_lights() -> int:
	var count := 0
	for room_light in _room_lights:
		if room_light != null and room_light.cast_shadow:
			count += 1
	return count


func _count_active_shadow_lights() -> int:
	var count := 0
	for room_light in _room_lights:
		if room_light == null:
			continue
		var snapshot := room_light.get_snapshot()
		if bool(snapshot.get("shadow_enabled", false)):
			count += 1
	return count


## 拐角 L 拼装：中间段碰撞（跳过两端拐角 + 门洞 span）
func _add_corner_aware_solid_run_collision(
	direction: String,
	wall_offset: float,
	inner_start: float,
	inner_end: float,
	has_door: bool,
	door_index: int
) -> void:
	var body := StaticBody3D.new()
	body.name = "TowerWallCollision_%s_Run" % direction.capitalize()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("camera_lower_wall", direction in ["north", "south"])
	add_child(body)
	var inner_length := inner_end - inner_start
	if inner_length <= 0.0:
		return
	# 以 5m 网格从 inner_start 到 inner_end 划成连续段，门洞位置拆为左右两段
	var segments: Array[Vector2] = []
	segments.append(Vector2(inner_start, inner_end))
	if has_door:
		var door_offset_meta := "tower_wall_door_offset_%s" % direction
		if has_meta(door_offset_meta):
			var door_along := float(get_meta(door_offset_meta))
			var door_left := door_along - TOWER_GEOMETRY.GRID_UNIT_M * 0.5
			var door_right := door_along + TOWER_GEOMETRY.GRID_UNIT_M * 0.5
			var new_segments: Array[Vector2] = []
			for seg in segments:
				var seg_start: float = seg.x
				var seg_end: float = seg.y
				if door_left < seg_end and door_right > seg_start:
					if door_left > seg_start:
						new_segments.append(Vector2(seg_start, minf(door_left, seg_end)))
					if door_right < seg_end:
						new_segments.append(Vector2(maxf(door_right, seg_start), seg_end))
				else:
					new_segments.append(seg)
			segments = new_segments
	for seg in segments:
		var seg_start: float = seg.x
		var seg_end: float = seg.y
		if seg_end <= seg_start:
			continue
		var run_length := seg_end - seg_start
		var along := (seg_start + seg_end) * 0.5
		var position := Vector3.ZERO
		var size := Vector3.ZERO
		match direction:
			"north":
				position = Vector3(along, TOWER_GEOMETRY.FLOOR_HEIGHT_M * 0.5, -wall_offset)
				size = Vector3(run_length, TOWER_GEOMETRY.FLOOR_HEIGHT_M, 0.30)
			"south":
				position = Vector3(along, TOWER_GEOMETRY.FLOOR_HEIGHT_M * 0.5, wall_offset)
				size = Vector3(run_length, TOWER_GEOMETRY.FLOOR_HEIGHT_M, 0.30)
			"west":
				position = Vector3(-wall_offset, TOWER_GEOMETRY.FLOOR_HEIGHT_M * 0.5, along)
				size = Vector3(0.30, TOWER_GEOMETRY.FLOOR_HEIGHT_M, run_length)
			_:
				position = Vector3(wall_offset, TOWER_GEOMETRY.FLOOR_HEIGHT_M * 0.5, along)
				size = Vector3(0.30, TOWER_GEOMETRY.FLOOR_HEIGHT_M, run_length)
		_add_collision_shape(body, position, size)


func _add_tower_solid_run_collision(
	direction: String,
	length: float,
	module_count: int,
	door_index: int,
	has_door: bool,
	wall_offset: float
) -> void:
	# 5m 实心墙 prefab 自带 WallCollision，这里只用于门洞跨度的可视化标记。
	var body := StaticBody3D.new()
	body.name = "TowerWallCollision_%s_Run" % direction.capitalize()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var runs: Array[Vector2i] = []
	if not has_door:
		runs.append(Vector2i(0, module_count))
	else:
		if door_index > 0:
			runs.append(Vector2i(0, door_index))
		if door_index + 1 < module_count:
			runs.append(Vector2i(door_index + 1, module_count - door_index - 1))
	for run in runs:
		var run_length := float(run.y) * TOWER_GEOMETRY.GRID_UNIT_M
		var along := (
			-length * 0.5
			+ TOWER_GEOMETRY.GRID_UNIT_M * (float(run.x) + float(run.y) * 0.5)
		)
		var position := Vector3.ZERO
		var size := Vector3.ZERO
		match direction:
			"north":
				position = Vector3(along, TOWER_GEOMETRY.FLOOR_HEIGHT_M * 0.5, -wall_offset)
				size = Vector3(run_length, TOWER_GEOMETRY.FLOOR_HEIGHT_M, 0.30)
			"south":
				position = Vector3(along, TOWER_GEOMETRY.FLOOR_HEIGHT_M * 0.5, wall_offset)
				size = Vector3(run_length, TOWER_GEOMETRY.FLOOR_HEIGHT_M, 0.30)
			"west":
				position = Vector3(-wall_offset, TOWER_GEOMETRY.FLOOR_HEIGHT_M * 0.5, along)
				size = Vector3(0.30, TOWER_GEOMETRY.FLOOR_HEIGHT_M, run_length)
			_:
				position = Vector3(wall_offset, TOWER_GEOMETRY.FLOOR_HEIGHT_M * 0.5, along)
				size = Vector3(0.30, TOWER_GEOMETRY.FLOOR_HEIGHT_M, run_length)
		_add_collision_shape(body, position, size)


func _add_tower_wall_collision(
	direction: String,
	module_position: Vector3,
	rotation_y: float,
	is_door_module: bool,
	module_index: int
) -> void:
	# 5m 带门墙 prefab 自带 WallCollision；这里用 BoxShape3D 调整门洞两侧门柱+门楣的精确阻挡。
	var body := StaticBody3D.new()
	body.name = "TowerWallCollision_%s_I%02d" % [direction.capitalize(), module_index]
	body.position = module_position
	body.rotation.y = rotation_y
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("camera_lower_wall", direction in ["north", "south"])
	add_child(body)
	if not is_door_module:
		_add_collision_shape(
			body,
			Vector3(0.0, TOWER_GEOMETRY.FLOOR_HEIGHT_M * 0.5, 0.0),
			Vector3(
				TOWER_GEOMETRY.GRID_UNIT_M,
				TOWER_GEOMETRY.FLOOR_HEIGHT_M,
				0.30
			)
		)
		return
	if direction in ["north", "south"]:
		_add_camera_only_door_wall_proxy(
			direction, body.position, body.rotation.y, module_index
		)
	var pillar_width := (
		TOWER_GEOMETRY.GRID_UNIT_M - TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M
	) * 0.5
	var pillar_center := (
		TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M * 0.5 + pillar_width * 0.5
	)
	for x in [-pillar_center, pillar_center]:
		_add_collision_shape(
			body,
			Vector3(x, TOWER_GEOMETRY.FLOOR_HEIGHT_M * 0.5, 0.0),
			Vector3(pillar_width, TOWER_GEOMETRY.FLOOR_HEIGHT_M, 0.30)
		)
	_add_collision_shape(
		body,
		Vector3(
			0.0,
			TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M
			+ (TOWER_GEOMETRY.FLOOR_HEIGHT_M - TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M) * 0.5,
			0.0
		),
		Vector3(
			TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M,
			TOWER_GEOMETRY.FLOOR_HEIGHT_M - TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M,
			0.30
		)
	)


func _add_camera_only_door_wall_proxy(
	direction: String,
	module_position: Vector3,
	rotation_y: float,
	module_index: int
) -> void:
	# 门洞打开后不能放置世界层实体碰撞，否则会挡住角色与子弹。使用独立
	# camera-only层覆盖完整5m门墙，仅供TowerDescent3D的镜头探针命中。
	var proxy := StaticBody3D.new()
	proxy.name = "CameraOnlyDoorWall_%s_I%02d" % [
		direction.capitalize(),
		module_index,
	]
	proxy.position = module_position
	proxy.rotation.y = rotation_y
	proxy.collision_layer = GameDesignConfig.COLLISION_LAYER_CAMERA_ONLY
	proxy.collision_mask = 0
	proxy.set_meta("camera_lower_wall", true)
	proxy.set_meta("camera_only_door_wall", true)
	proxy.set_meta("tower_wall_direction", direction)
	add_child(proxy)
	_add_collision_shape(
		proxy,
		Vector3(0.0, TOWER_GEOMETRY.FLOOR_HEIGHT_M * 0.5, 0.0),
		Vector3(
			TOWER_GEOMETRY.GRID_UNIT_M,
			TOWER_GEOMETRY.FLOOR_HEIGHT_M,
			0.08
		)
	)


func _add_collision_shape(body: StaticBody3D, local_position: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.position = local_position
	collision.shape = shape
	body.add_child(collision)


func _build_floor_partitions(dimensions: Vector2) -> void:
	var mirror := -1.0 if absi(room_seed) % 2 == 0 else 1.0
	if room_type == "FACILITY":
		# v0.1：30m基地中央必须保持通畅；设施全部沿墙摆放。
		return
	var partition_x := mirror * 4.8
	for z in [-8.0, 7.5]:
		_spawn_prefab(
			"FloorPartitionVertical",
			PARTITION_VERTICAL_PREFAB,
			Vector3(partition_x, 1.4, z),
			Vector3(0.28, 2.8, 8.0),
			_wall_material
		)
	var partition_z := mirror * 6.2
	for x in [-8.2, 8.2]:
		var horizontal_partition := _spawn_prefab(
			"FloorPartitionHorizontal",
			PARTITION_HORIZONTAL_PREFAB,
			Vector3(x, 1.4, partition_z),
			Vector3(8.0, 2.8, 0.28),
			_wall_material
		)
		# 内部横向隔墙没有north/south资产朝向；只要它位于角色与固定
		# 后方镜头之间，就应与外围南墙执行同一套抬升收镜逻辑。
		if horizontal_partition != null:
			horizontal_partition.set_meta("camera_lower_wall_component", true)
			_set_camera_lower_wall_on_static_bodies(horizontal_partition, true)


func _build_wall(direction: String, center: Vector3, length: float, axis: Vector3) -> void:
	var has_door := doors.has(direction)
	var thickness := 0.28
	var height := 2.8
	if not has_door:
		var size := Vector3(length, height, thickness) if axis.x > 0.0 else Vector3(thickness, height, length)
		var wall := _spawn_prefab(
			"Wall_%s" % direction,
			WALL_SEGMENT_PREFAB,
			center,
			size,
			_wall_material
		)
		if wall != null and direction in ["north", "south"]:
			_set_camera_lower_wall_on_static_bodies(wall, true)
		return
	var opening := TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M
	var segment_length := (length - opening) * 0.5
	for side in [-1.0, 1.0]:
		var offset: Vector3 = axis * float(side) * (opening * 0.5 + segment_length * 0.5)
		var segment_size := Vector3(segment_length, height, thickness) if axis.x > 0.0 else Vector3(thickness, height, segment_length)
		var wall_segment := _spawn_prefab(
			"Wall_%s" % direction,
			WALL_DOOR_SEGMENT_PREFAB,
			center + offset,
			segment_size,
			_wall_material
		)
		if wall_segment != null and direction in ["north", "south"]:
			_set_camera_lower_wall_on_static_bodies(wall_segment, true)
	var lintel_size := Vector3(opening, 0.45, thickness * 1.28) if axis.x > 0.0 else Vector3(thickness * 1.28, 0.45, opening)
	var lintel := _spawn_prefab(
		"DoorLintel_%s" % direction,
		DOOR_LINTEL_PREFAB,
		center + Vector3(0, 1.18, 0),
		lintel_size,
		_trim_material
	)
	if lintel != null and direction in ["north", "south"]:
		_set_camera_lower_wall_on_static_bodies(lintel, true)


func _build_door(direction: String, target_room_id: String, dimensions: Vector2) -> void:
	var door := DOOR_SCRIPT.new() as RoomDoor3D
	door.configure(direction, target_room_id, theme.accent_color)
	door.set_access_policy(door_policies.get(direction, {}) as Dictionary)
	door.set_meta("camera_lower_wall", direction in ["north", "south"])
	# 与 _build_tower_wall_run 同步：门偏移到沿墙中心最近模块位置 (5m 网格偶数段是 ±2.5m)。
	var door_offset_along := float(get_meta("tower_wall_door_offset_%s" % direction, 0.0))
	match direction:
		"north":
			door.position = Vector3(door_offset_along, 0, -dimensions.y * 0.5)
		"south":
			door.position = Vector3(door_offset_along, 0, dimensions.y * 0.5)
		"west":
			door.position = Vector3(-dimensions.x * 0.5, 0, door_offset_along)
			door.rotation.y = PI * 0.5
		"east":
			door.position = Vector3(dimensions.x * 0.5, 0, door_offset_along)
			door.rotation.y = PI * 0.5
	add_child(door)
	_door_nodes[direction] = door


func _set_camera_lower_wall_on_static_bodies(root: Node, enabled: bool) -> void:
	if root is StaticBody3D:
		(root as StaticBody3D).set_meta("camera_lower_wall", enabled)
	for child in root.get_children():
		_set_camera_lower_wall_on_static_bodies(child, enabled)


func _configure_corner_camera_collisions(module: Node, corner_id: String) -> void:
	for value in module.find_children("*", "StaticBody3D", true, false):
		var body := value as StaticBody3D
		var enabled := (
			(corner_id == "SW" and body.name == "WallCollisionLong")
			or (corner_id == "SE" and body.name == "WallCollisionShort")
			or (corner_id == "NW" and body.name == "WallCollisionShort")
			or (corner_id == "NE" and body.name == "WallCollisionLong")
		)
		body.set_meta("camera_lower_wall", enabled)


func _build_stair_lobby_markings(dimensions: Vector2) -> void:
	var guide_material := _material(theme.accent_color, 0.20, 0.34)
	guide_material.emission_enabled = true
	guide_material.emission = theme.accent_color * 0.72
	guide_material.emission_energy_multiplier = 1.25
	var east_west_route := "east" in doors or "west" in doors
	var guide_size := (
		Vector3(dimensions.x - 2.0, 0.035, 1.20)
		if east_west_route
		else Vector3(1.20, 0.035, dimensions.y - 2.0)
	)
	_spawn_prefab(
		"StairLobbyRouteGuide",
		STAIR_LOBBY_ROUTE_GUIDE_PREFAB,
		Vector3(0.0, 0.045, 0.0),
		guide_size,
		guide_material
	)
	var threshold_size := (
		Vector3(0.26, 0.045, 4.2)
		if east_west_route
		else Vector3(4.2, 0.045, 0.26)
	)
	for threshold_index in range(2):
		var direction_sign := -1.0 if threshold_index == 0 else 1.0
		var threshold_position := Vector3.ZERO
		if east_west_route:
			threshold_position.x = direction_sign * (dimensions.x * 0.5 - 0.65)
		else:
			threshold_position.z = direction_sign * (dimensions.y * 0.5 - 0.65)
		threshold_position.y = 0.055
		_spawn_prefab(
			"StairLobbyThresholdGuide_%s" % (
				"A" if threshold_index == 0 else "B"
			),
			STAIR_LOBBY_THRESHOLD_GUIDE_PREFAB,
			threshold_position,
			threshold_size,
			guide_material
		)


func _build_content() -> void:
	var dimensions := get_dimensions()
	_room_lights.clear()
	if room_type == "FACILITY":
		# 简单顶光：4 盏 ceiling 灯分布在四角 ±10m 处，统一受基地开关控制。
		# 单灯 energy * 3.0、range * 2.8（整体亮度 ×2，比 BOSS 4 灯的 *2.4 更亮）。
		_central_light = null
		for light_index in range(4):
			var x_sign := -1.0 if light_index % 2 == 0 else 1.0
			var z_sign := -1.0 if light_index < 2 else 1.0
			var facility_light := _create_room_light(
				"FacilityCeilingLight_%02d" % (light_index + 1),
				Vector3(x_sign * 10.0, 0.0, z_sign * 10.0),
				theme.fixture_energy * 3.00,
				maxf(
					theme.fixture_range * 2.80,
					minf(dimensions.x, dimensions.y) * 1.10
				),
				room_seed + light_index * 17,
				true
			)
			if _central_light == null:
				_central_light = facility_light
			_room_lights.append(facility_light)
	elif room_type == "BOSS" and minf(dimensions.x, dimensions.y) >= 64.0:
		# 90m终局竞技场不能依赖一盏超大范围点光源：四区灯具让中心与
		# 四周都保持可读，同时仍由同一个墙边开关统一控制。
		for light_index in range(4):
			var x_sign := -1.0 if light_index % 2 == 0 else 1.0
			var z_sign := -1.0 if light_index < 2 else 1.0
			var arena_light := _create_room_light(
				"ArenaCeilingLight_%02d" % (light_index + 1),
				Vector3(
					x_sign * dimensions.x * 0.24,
					0.0,
					z_sign * dimensions.y * 0.24
				),
				theme.fixture_energy * 2.40,
				maxf(
					theme.fixture_range * 1.72,
					minf(dimensions.x, dimensions.y) * 0.58
				),
				room_seed + light_index * 19,
				light_index == 0
			)
			_room_lights.append(arena_light)
		_central_light = _room_lights[0]
	else:
		_central_light = _create_room_light(
			"RoomCeilingLight",
			Vector3.ZERO,
			theme.fixture_energy * (
				2.20 if size_class in ["large", "arena", "floor"] else 1.85
			),
			maxf(
				theme.fixture_range * 1.72,
				minf(dimensions.x, dimensions.y) * 0.94
			),
			room_seed,
			true
		)
		_room_lights.append(_central_light)

	_light_switch = LIGHT_SWITCH_SCENE.instantiate() as RoomLightSwitch3D
	_light_switch.name = "RoomLightSwitch3D"
	_place_light_switch(_light_switch, dimensions)
	var starts_on := room_type in ["FACILITY", "STAIR_LOBBY", "BOSS"]
	_light_switch.configure_group(_room_lights, starts_on)
	add_child(_light_switch)
	if room_type == "STAIR_LOBBY":
		_build_stair_lobby_markings(dimensions)

	var prop_count := (
		3 if size_class in ["small", "tower_cell"]
		else 5 if size_class == "medium"
		else 7 if size_class in ["large", "floor"]
		else 9
	)
	if size_class == "rooftop":
		prop_count = 3
	if room_type == "FACILITY":
		prop_count = 0
	if room_type == "STAIR_LOBBY":
		prop_count = 0
	if room_type in ["STORAGE", "SCAVENGE", "BASEMENT"]:
		prop_count += 2
	for index in range(prop_count):
		# 可搜完全随机：每个 prop 独立 50/50。FACILITY / STAIR_LOBBY 在 prop_count=0
		# 的分支里就已经退出，此处不再额外排除任何房间类型。
		var is_search := _rng.randf() < 0.5
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
		_create_service_station(room_type.to_lower(), dimensions)
	if room_type in ["STAIRS_DOWN", "STAIRS_UP"]:
		_build_vertical_access_marker(room_type)
	if room_type == "TRAP":
		var hazard := HAZARD_SCENE.instantiate() as HazardField3D
		hazard.configure(
			theme.hazard_color,
			3.2 if size_class in ["large", "arena"] else 2.6,
			6 + theme.difficulty_rank * 2
		)
		hazard.position = Vector3(0, 0.06, 0)
		add_child(hazard)


func _create_service_station(type_id: String, dimensions: Vector2) -> ServiceStation3D:
	var station := SERVICE_SCENE.instantiate() as ServiceStation3D
	if station == null:
		push_error("DungeonRoom3D: failed to instantiate required %s station in %s" % [type_id, room_id])
		return null
	var title: String = str({
		"merchant": "拾荒商终端",
		"upgrade": "武器改造台",
		"event": "异常信号终端",
	}.get(type_id, "废土终端"))
	station.configure(type_id, title, theme.accent_color)
	# 必做目标不能贴在镜头会裁切的北墙。事件终端放到房间中部安全区，
	# 同时避开出生点圆环和两侧家具，保证所有 30×25m 以上房型都可接近。
	var forward_offset := minf(4.5, dimensions.y * 0.18)
	station.position = Vector3(0, 0, -forward_offset)
	station.set_meta("required_room_objective", type_id == "event")
	add_child(station)
	station.activated.connect(_on_service_activated)
	return station


func _create_room_light(
	node_name: String,
	planar_position: Vector3,
	p_energy: float,
	p_range: float,
	seed: int,
	shadow: bool
) -> WastelandLight3D:
	var room_light := LIGHT_SCENE.instantiate() as WastelandLight3D
	room_light.name = node_name
	room_light.position = planar_position
	room_light.configure(
		theme.key_light_color,
		p_energy,
		p_range,
		seed,
		shadow,
		false,
		"ceiling",
	)
	if tower_module_shell:
		# 灯具自身的顶装高度是 2.72m；整体抬升后与 9m 天花板贴合。
		room_light.position.y = TOWER_GEOMETRY.FLOOR_HEIGHT_M - 2.72
	room_light.set_light_enabled(false)
	add_child(room_light)
	room_light.add_to_group("wasteland_light_3d")
	return room_light


func _place_light_switch(light_switch: RoomLightSwitch3D, dimensions: Vector2) -> void:
	if room_type == "FACILITY":
		# 基地开关固定在西墙内侧，对应基地视图左侧绿色框标注的墙面。
		# 沿墙偏移 4.2m，避开墙角与北侧入口；面板朝向房间内部。
		var facility_wall_offset := minf(4.2, dimensions.y * 0.22)
		light_switch.position = Vector3(
			-dimensions.x * 0.5 + 0.34,
			0.0,
			facility_wall_offset,
		)
		light_switch.rotation.y = -PI * 0.5
		light_switch.set_meta("facility_entry_switch_clearance_m", 5.0)
		light_switch.set_meta("facility_entry_direction", "west_wall_left_marked_area")
		return
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
		_spawn_prefab("AccessStep", ACCESS_STEP_PREFAB, Vector3(0, step_height * 0.5, -2.2 + index * 0.75), Vector3(3.0, step_height, 0.72), step_material)
	var label_instance := VERTICAL_ACCESS_LABEL_PREFAB.instantiate() as Node3D
	label_instance.name = "VerticalAccessMarkerLabel"
	label_instance.position = Vector3(0, 2.2, 0)
	var label3d := label_instance.get_node("VerticalAccessLabel") as Label3D
	if label3d != null:
		label3d.text = "电梯 / 垂直层" if type_id == "ELEVATOR" else "上层" if up else "地下层"
		label3d.modulate = theme.accent_color.lightened(0.18)
	add_child(label_instance)


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
	var count := (
		4 if size_class == "tower_cell"
		else 3 if size_class == "small"
		else 5 if size_class == "medium"
		else 7 if size_class == "large"
		else 9
	)
	for index in range(count):
		var angle := TAU * float(index) / float(count) + _rng.randf_range(-0.24, 0.24)
		enemy_spawn_points.append(global_position + Vector3(cos(angle) * dimensions.x * 0.23, 0.0, sin(angle) * dimensions.y * 0.23))


func _on_room_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player_3d"):
		return
	call_deferred("_emit_player_entered_if_present", body)


func _emit_player_entered_if_present(body: Node3D) -> void:
	if body == null or not is_instance_valid(body) or not body.is_in_group("player_3d"):
		return
	var local_position := to_local(body.global_position)
	var dimensions := get_dimensions()
	if (
		absf(local_position.x) > dimensions.x * 0.42
		or absf(local_position.z) > dimensions.y * 0.42
		or absf(local_position.y) > 1.8
	):
		return
	if not visited:
		visited = true
	player_entered.emit(self)


func _on_prop_searched(_prop: RoomFurniture3D, loot: Dictionary) -> void:
	prop_searched.emit(self, loot)


func _on_service_activated(station: ServiceStation3D) -> void:
	service_activated.emit(self, station)


# —— prefab 通用入口：实例化 + 设位置/缩放/材质
# 预制体内部 mesh/collision 已经是 1×1×1 或真实参考尺寸，scale 整体传递到子节点。
func _spawn_prefab(node_name: String, prefab: PackedScene, position: Vector3, scale_vec: Vector3, material: StandardMaterial3D) -> Node3D:
	if prefab == null:
		push_error("DungeonRoom3D: missing prefab for %s" % node_name)
		return null
	var instance := prefab.instantiate() as Node3D
	if instance == null:
		return null
	instance.name = node_name
	instance.position = position
	instance.scale = scale_vec
	_apply_material_override(instance, material)
	add_child(instance)
	return instance


func _apply_material_override(root: Node, material: StandardMaterial3D) -> void:
	if material == null:
		return
	for child in root.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = material
		_apply_material_override(child, material)


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _set_collision_enabled(root: Node, enabled: bool, preserve_support := false) -> void:
	if root is CollisionShape3D:
		var collision := root as CollisionShape3D
		var is_support := collision.get_parent() != null and collision.get_parent().name == "FloorBody"
		collision.set_deferred("disabled", false if preserve_support and is_support else not enabled)
	for child in root.get_children():
		_set_collision_enabled(child, enabled, preserve_support)


func _has_enabled_support_collision() -> bool:
	# FloorBody 可能嵌套在 prefab 根节点下，递归查找。
	return _find_floor_body_enabled(self)


func _find_floor_body_enabled(root: Node) -> bool:
	if root is StaticBody3D and root.name == "FloorBody":
		for child in root.get_children():
			if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
				return true
	for child in root.get_children():
		if _find_floor_body_enabled(child):
			return true
	return false


func _get_door_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in _door_nodes.values():
		var door := value as RoomDoor3D
		if door != null:
			result.append(door.get_snapshot())
	return result
