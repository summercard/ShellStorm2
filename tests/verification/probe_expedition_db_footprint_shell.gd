extends SceneTree

## 数据库房壳体的轮廓回归：db_01 不是 40×30 包围盒，而是 40×25 主体加南中段
## 10×5 外凸。这里直接检验组合器输出，防止房型布局补墙时又误取 size_m 铺矩形。
const ROOM_SHELL := preload("res://src/world3d/RoomShellLayoutBuilder3D.gd")
const ROOM02_STATIC_LAYOUT: PackedScene = preload(
	"res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01/f00_room_02_static_layout.tscn"
)

var checks := 0
var failures: Array[String] = []


func _init() -> void:
	var result := ROOM_SHELL.build_block([{
		"room_id": "room_02",
		"bounds_x_m": [-20.0, 20.0],
		"bounds_y_m": [-15.0, 15.0],
		"doors": {"west": -2.5, "east": -2.5},
		"exits": {},
		"use_corner_l": true,
		"footprint_frame": ROOM_SHELL.FOOTPRINT_FRAME,
		"footprint_vertices_m": [
			[0.0, 0.0], [40.0, 0.0], [40.0, 25.0], [25.0, 25.0],
			[25.0, 30.0], [15.0, 30.0], [15.0, 25.0], [0.0, 25.0],
		],
	}])
	_expect((result.get("errors", []) as Array).is_empty(), "db_01 轮廓必须可生成")
	_expect((result.get("corners", []) as Array).size() == 6, "db_01 必须有 6 个凸角 L 件")
	_expect((result.get("corners_dropped", []) as Array).is_empty(), "db_01 不应丢弃凸角")
	var instances := result.get("instances", []) as Array
	# 外凸三条 5m 边由两件 L 角的臂覆盖，而非重复放直墙；验证两个凸角的真坐标。
	var corners := result.get("corners", []) as Array
	_expect(_has_corner(corners, Vector2(-5.0, -15.0)), "南侧外凸西凸角必须存在")
	_expect(_has_corner(corners, Vector2(5.0, -15.0)), "南侧外凸东凸角必须存在")
	_expect(_has_wall(instances, Vector2(-20.0, -2.5)), "西侧 A 门洞必须占外边界 lane")
	_expect(_has_wall(instances, Vector2(20.0, -2.5)), "东侧 B 门洞必须占外边界 lane")
	var static_layout := ROOM02_STATIC_LAYOUT.instantiate() as Node3D
	_expect(static_layout != null, "room02 静态布局必须可实例化")
	if static_layout != null:
		var static_corners := 0
		var anonymous_corners := 0
		var floor_tiles: Array[Vector3] = []
		var corner_positions: Array[Vector3] = []
		var door_wall_positions: Array[Vector3] = []
		var solid_wall_positions: Array[Vector3] = []
		for child in static_layout.get_children():
			if child is Node3D and str(child.get_meta("authored_source_component_id", "")).begins_with(
				"ENV-EXPEDITION-L01-DB-FLOOR_TILE_5M_"
			):
				floor_tiles.append((child as Node3D).position)
			if child is Node3D and str(child.get_meta("asset_id", "")) == "ENV-BATTLE-COMMON-WALL-DOOR-5M":
				door_wall_positions.append((child as Node3D).position)
			if child is Node3D and str(child.get_meta("asset_id", "")) == "ENV-BATTLE-COMMON-WALL-STANDARD-5M":
				solid_wall_positions.append((child as Node3D).position)
			if str(child.get_meta("asset_id", "")) != "ENV-TOWER-CORNER-L-5M":
				continue
			static_corners += 1
			if child is Node3D:
				corner_positions.append((child as Node3D).position)
			if str(child.name).begins_with("@Node3D"):
				anonymous_corners += 1
		# room02 本局为 180° 旋转：先由真实地砖确认外凸在南侧，再确认墙/角跟同一外轮廓。
		# 西侧连接槽应由 room02 持有一件真门墙；东侧槽委派给下一房，room02 不得留下实墙。
		_expect(floor_tiles.size() == 42, "room02 必须保留 42 块数据库房真实地砖")
		_expect(_has_position(floor_tiles, Vector3(-2.5, 0.0, -12.5)), "地砖外凸西格必须位于南侧")
		_expect(_has_position(floor_tiles, Vector3(2.5, 0.0, -12.5)), "地砖外凸东格必须位于南侧")
		_expect(not _has_position(floor_tiles, Vector3(7.5, 0.0, -12.5)), "南侧凹口外不得误铺地砖")
		_expect(static_corners == 6, "room02 必须固化 6 个轮廓凸角 L 件")
		_expect(_has_position(corner_positions, Vector3(-5.0, 0.0, -15.0)), "墙体必须包住南侧外凸的西转角")
		_expect(_has_position(corner_positions, Vector3(5.0, 0.0, -15.0)), "墙体必须包住南侧外凸的东转角")
		_expect(not _has_position(corner_positions, Vector3(-5.0, 0.0, 15.0)), "北侧不得生成反向外凸角")
		_expect(not _has_position(corner_positions, Vector3(5.0, 0.0, 15.0)), "北侧不得生成反向外凸角")
		_expect(_has_position(door_wall_positions, Vector3(-20.0, 0.0, 2.5)), "room02 西侧连接必须在真门槽生成门墙")
		_expect(not _has_position(solid_wall_positions, Vector3(-20.0, 0.0, 2.5)), "room02 西侧门槽不得残留实墙空气阻挡")
		_expect(not _has_position(solid_wall_positions, Vector3(20.0, 0.0, 2.5)), "room02 东侧委派门槽不得重复生成实墙")
		_expect(anonymous_corners == 0, "room02 静态凸角必须全部具有可读节点名")
		static_layout.free()
	if failures.is_empty():
		print("EXPEDITION_DB_FOOTPRINT_SHELL_OK checks=%d" % checks)
		quit(0)
		return
	for message in failures:
		push_error(message)
	quit(1)


func _has_wall(instances: Array, position: Vector2) -> bool:
	for value in instances:
		var instance := value as Dictionary
		if str(instance.get("slot_role", "")) not in ["solid_wall", "door_wall"]:
			continue
		var raw := instance.get("position_m", []) as Array
		if raw.size() < 2:
			continue
		if is_equal_approx(float(raw[0]), position.x) and is_equal_approx(float(raw[1]), position.y):
			return true
	return false


func _has_corner(corners: Array, position: Vector2) -> bool:
	for value in corners:
		var corner := value as Dictionary
		var raw := corner.get("point_m", []) as Array
		if raw.size() < 2:
			continue
		if is_equal_approx(float(raw[0]), position.x) and is_equal_approx(float(raw[1]), position.y):
			return true
	return false


func _has_position(positions: Array[Vector3], expected: Vector3) -> bool:
	for position in positions:
		if (
			is_equal_approx(position.x, expected.x)
			and is_equal_approx(position.z, expected.z)
		):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
