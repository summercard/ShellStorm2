class_name TowerDescent3D
extends Dungeon3D
## PH34 正式入口：楼顶、设施层与五个战斗层共用 Dungeon3D 战斗/命运/掉落管线，
## 这里只定义垂直拓扑、设施层和楼层级流送。

const FACILITY_SCENE: PackedScene = preload("res://assets/art/props/base_world_3d/prp_base_facility_root_top3d_v001.tscn")
const TOWER_GEOMETRY := preload("res://src/world3d/TowerGeometry3D.gd")
const COMBAT_FLOOR_COUNT := 5
const FLOOR_HEIGHT := TOWER_GEOMETRY.FLOOR_HEIGHT_M
const STAIR_WIDTH := TOWER_GEOMETRY.PASSAGE_WIDTH_M
const STAIR_RUN := TOWER_GEOMETRY.RUN_LENGTH_M
const STAIR_LANE_SPACING := TOWER_GEOMETRY.LANE_CENTER_SPACING_M
const STAIR_GUARD_HEIGHT := TOWER_GEOMETRY.GUARD_HEIGHT_M
const STAIR_CUTAWAY_MARGIN := 0.9

var _active_facility_menu: CanvasLayer = null
var _facility_nodes: Array[BaseFacility3D] = []
var _descent_side_sequence: Array[String] = []
var _edge_side_by_key: Dictionary = {}
var _stair_surface_snap_count := 0
var _stair_cutaway_hidden_count := 0


func _ready() -> void:
	process_physics_priority = 100
	super()
	player.global_position = Vector3(-14.0, 0.05, 0.0)
	_install_facilities()
	title_label.text = "弹壳风暴2 · 向下爬楼行动"
	seed_label.text = "塔楼种子 %d" % run_seed
	status_label.text = "楼顶出生点 · 左侧护栏处为首个下行楼梯门"
	_refresh_facility_runtime()


func _physics_process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_update_stairwell_cutaway()
	for connector_value in _corridor_by_edge.values():
		var connector := connector_value as Node3D
		if connector == null or not connector.visible:
			continue
		var points: Array = connector.get_meta("path_points", [])
		for index in range(points.size() - 1):
			var start := points[index] as Vector3
			var end := points[index + 1] as Vector3
			if absf(end.y - start.y) <= 0.05:
				continue
			if _snap_player_to_stair_surface(start, end):
				_stair_surface_snap_count += 1
				return


func _snap_player_to_stair_surface(start: Vector3, end: Vector3) -> bool:
	var start_planar := Vector2(start.x, start.z)
	var end_planar := Vector2(end.x, end.z)
	var player_planar := Vector2(player.global_position.x, player.global_position.z)
	var segment := end_planar - start_planar
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return false
	var ratio := clampf((player_planar - start_planar).dot(segment) / length_squared, 0.0, 1.0)
	var closest := start_planar + segment * ratio
	if player_planar.distance_to(closest) > STAIR_WIDTH * 0.42:
		return false
	var target_y := lerpf(start.y, end.y, ratio) + 0.05
	var min_y := minf(start.y, end.y) - 0.65
	var max_y := maxf(start.y, end.y) + 0.95
	if player.global_position.y < min_y or player.global_position.y > max_y:
		return false
	var snapped := player.global_position
	snapped.y = target_y
	player.global_position = snapped
	return true


func _build_records() -> void:
	_records.clear()
	_descent_side_sequence.clear()
	_edge_side_by_key.clear()

	var definitions := [
		{"id": "start", "type": "START", "size": "rooftop"},
		{"id": "facility", "type": "FACILITY", "size": "floor"},
		{"id": "floor_01", "type": "COMBAT", "size": "floor"},
		{"id": "floor_02", "type": "COMBAT", "size": "floor"},
		{"id": "floor_03", "type": "ELITE", "size": "floor"},
		{"id": "floor_04", "type": "COMBAT", "size": "floor"},
		{"id": "extraction", "type": "BOSS", "size": "floor"},
	]
	for index in range(definitions.size()):
		var definition: Dictionary = definitions[index]
		_records.append(_record(
			str(definition["id"]),
			str(definition["type"]),
			str(definition["size"]),
			Vector3(0.0, -FLOOR_HEIGHT * index, 0.0),
			[],
			true,
			"" if index == 0 else str(definitions[index - 1]["id"]),
			index,
			-index
		))
	var previous_side := ""
	for index in range(1, _records.size()):
		var parent := _records[index - 1] as Dictionary
		var child := _records[index] as Dictionary
		var side := "west" if index == 1 else _choose_descent_side(previous_side)
		(parent["doors"] as Array).append(side)
		(child["doors"] as Array).append(side)
		var edge := _edge_key(str(parent["id"]), str(child["id"]))
		_edge_side_by_key[edge] = side
		_descent_side_sequence.append(side)
		previous_side = side


func _choose_descent_side(previous_side: String) -> String:
	var candidates: Array[String] = ["north", "south", "west", "east"]
	candidates.erase(previous_side)
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _build_topology() -> void:
	_room_neighbors.clear()
	_open_edges.clear()
	for record in _records:
		_room_neighbors[str(record["id"])] = []
	for index in range(1, _records.size()):
		var parent := _records[index - 1] as Dictionary
		var child := _records[index] as Dictionary
		var parent_id := str(parent["id"])
		var child_id := str(child["id"])
		var edge := _edge_key(parent_id, child_id)
		var side := str(_edge_side_by_key.get(edge, "west"))
		(_room_neighbors[parent_id] as Array).append(child_id)
		(_room_neighbors[child_id] as Array).append(parent_id)
		_open_edges[edge] = false
		(parent["door_targets"] as Dictionary)[side] = child_id
		(child["door_targets"] as Dictionary)[side] = parent_id


func _build_corridor(from_room: DungeonRoom3D, to_room: DungeonRoom3D, index: int) -> void:
	var edge := _edge_key(from_room.room_id, to_room.room_id)
	var side := str(_edge_side_by_key.get(edge, "west"))
	var outward := {
		"north": Vector3(0, 0, -1),
		"south": Vector3(0, 0, 1),
		"west": Vector3(-1, 0, 0),
		"east": Vector3(1, 0, 0),
	}.get(side, Vector3(-1, 0, 0)) as Vector3
	var tangent := Vector3(-outward.z, 0, outward.x)
	var from_dimensions := from_room.get_dimensions()
	var to_dimensions := to_room.get_dimensions()
	var from_half := from_dimensions.y * 0.5 if side in ["north", "south"] else from_dimensions.x * 0.5
	var to_half := to_dimensions.y * 0.5 if side in ["north", "south"] else to_dimensions.x * 0.5
	var upper_y := from_room.global_position.y
	var lower_y := to_room.global_position.y
	var upper_door := outward * from_half + Vector3.UP * upper_y
	var lower_door := outward * to_half + Vector3.UP * lower_y
	var upper_approach_distance := from_half + TOWER_GEOMETRY.APPROACH_OUTSET_M
	var lower_approach_distance := to_half + TOWER_GEOMETRY.APPROACH_OUTSET_M
	var upper_approach := outward * upper_approach_distance
	var lower_approach := outward * lower_approach_distance
	var upper_run_end := outward * (upper_approach_distance + STAIR_RUN)
	var lower_run_start := upper_run_end + tangent * STAIR_LANE_SPACING
	var lower_run_end := lower_approach + tangent * STAIR_LANE_SPACING
	var middle_y := upper_y - FLOOR_HEIGHT * 0.5
	# 标准U形楼梯：3m门外平台、第一跑、整块转向平台、平行第二跑、
	# 下层对门平台。两跑中心距统一5.2m，所有接缝都位于端点。
	var points: Array[Vector3] = [
		upper_door,
		upper_approach + Vector3.UP * upper_y,
		upper_run_end + Vector3.UP * middle_y,
		lower_run_start + Vector3.UP * middle_y,
		lower_run_end + Vector3.UP * lower_y,
		lower_approach + Vector3.UP * lower_y,
		lower_door,
	]
	var connector := Node3D.new()
	connector.name = "TowerStairwell_%02d" % index
	connector.set_meta("is_vertical_connector", true)
	connector.set_meta("from_room_id", from_room.room_id)
	connector.set_meta("to_room_id", to_room.room_id)
	connector.set_meta("height_delta", lower_y - upper_y)
	connector.set_meta("side", side)
	connector.set_meta("path_points", points)
	connector.set_meta("lane_spacing", STAIR_LANE_SPACING)
	connector.set_meta("guard_height", STAIR_GUARD_HEIGHT)
	connector.set_meta("passage_width", STAIR_WIDTH)
	connector.set_meta("approach_outset", TOWER_GEOMETRY.APPROACH_OUTSET_M)
	connector.set_meta("guard_end_clearance", TOWER_GEOMETRY.GUARD_END_CLEARANCE_M)
	connector.set_meta("outward", outward)
	connector.set_meta("upper_door_position", upper_door)
	connector.visible = false
	connector.process_mode = Node.PROCESS_MODE_DISABLED
	$GeneratedCorridors.add_child(connector)
	_corridor_by_edge[edge] = connector
	var floor_material := _tower_material(visual_theme.floor_color.lightened(0.06), 0.46, 0.72)
	var wall_material := _tower_material(visual_theme.wall_color.darkened(0.08), 0.62, 0.58)
	for point_index in range(points.size() - 1):
		_add_stair_segment(
			connector,
			points[point_index],
			points[point_index + 1],
			floor_material,
			wall_material,
			point_index
		)


func _add_stair_segment(
	root: Node3D,
	start: Vector3,
	end: Vector3,
	floor_material: StandardMaterial3D,
	wall_material: StandardMaterial3D,
	index: int
) -> void:
	var delta := end - start
	var along_x := absf(delta.x) >= absf(delta.z)
	var planar_length := absf(delta.x) if along_x else absf(delta.z)
	if planar_length <= 0.05:
		return
	var length := sqrt(planar_length * planar_length + delta.y * delta.y)
	var center := (start + end) * 0.5
	var rotation := Vector3.ZERO
	if along_x:
		rotation.z = atan(delta.y / delta.x) if absf(delta.x) > 0.01 else 0.0
	else:
		rotation.x = -atan(delta.y / delta.z) if absf(delta.z) > 0.01 else 0.0
	var floor_size := (
		Vector3(length, TOWER_GEOMETRY.FLOOR_THICKNESS_M, STAIR_WIDTH)
		if along_x
		else Vector3(STAIR_WIDTH, TOWER_GEOMETRY.FLOOR_THICKNESS_M, length)
	)
	# 路径点表示“可行走顶面”，不是盒体中心。沿盒体自身法线下移半厚度，
	# 水平楼道与门厅严格齐平，斜坡的承重顶面也精确落在同一条路径线上。
	# 旧版直接把盒体中心放在路径Y，入口会高出0.12m并卡死CharacterBody3D。
	var surface_normal := Basis.from_euler(rotation) * Vector3.UP
	var floor_center := center - surface_normal * (TOWER_GEOMETRY.FLOOR_THICKNESS_M * 0.5)
	_add_connector_box(root, "StairFloor_%02d" % index, floor_center, floor_size, rotation, floor_material)
	if absf(delta.y) > 0.05:
		# 护栏只沿斜坡设置；水平平台若也封边，会在90度转角横穿入口并卡住角色。
		var perpendicular := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
		var guard_planar_length := maxf(
			0.4,
			planar_length - TOWER_GEOMETRY.GUARD_END_CLEARANCE_M * 2.0
		)
		var guard_length := length * guard_planar_length / planar_length
		for side_sign in [-1.0, 1.0]:
			var guard_center: Vector3 = (
				center
				+ perpendicular * side_sign * (STAIR_WIDTH * 0.5 + 0.12)
				+ surface_normal * (STAIR_GUARD_HEIGHT * 0.5)
			)
			var guard_size := (
				Vector3(guard_length, STAIR_GUARD_HEIGHT, 0.24)
				if along_x
				else Vector3(0.24, STAIR_GUARD_HEIGHT, guard_length)
			)
			_add_connector_box(root, "StairGuard_%02d" % index, guard_center, guard_size, rotation, wall_material)
		var tread_count := maxi(5, int(planar_length / 0.8))
		for tread_index in range(tread_count):
			var ratio := (float(tread_index) + 0.5) / float(tread_count)
			var tread_position := start.lerp(end, ratio) + Vector3.UP * 0.09
			var tread_size := Vector3(planar_length / float(tread_count) * 0.74, 0.07, STAIR_WIDTH - 0.34) if along_x else Vector3(STAIR_WIDTH - 0.34, 0.07, planar_length / float(tread_count) * 0.74)
			# 踏步保持水平；承重和移动仍由下方连续斜坡负责。
			_add_connector_mesh(root, "StairTread_%02d_%02d" % [index, tread_index], tread_position, tread_size, Vector3.ZERO, wall_material)


func _add_connector_box(
	root: Node3D,
	node_name: String,
	position: Vector3,
	size: Vector3,
	rotation: Vector3,
	material: StandardMaterial3D
) -> void:
	var body := StaticBody3D.new()
	body.name = "%sBody" % node_name
	body.position = position
	body.rotation = rotation
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.set_meta("stair_cutaway_surface_y", position.y)
	body.add_child(instance)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.disabled = true
	body.add_child(collision)


func _add_connector_mesh(
	root: Node3D,
	node_name: String,
	position: Vector3,
	size: Vector3,
	rotation: Vector3,
	material: StandardMaterial3D
) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.rotation = rotation
	instance.mesh = mesh
	instance.set_meta("stair_cutaway_surface_y", position.y)
	root.add_child(instance)


func _update_stairwell_cutaway() -> void:
	var hidden_count := 0
	var cutaway_room_ids: Dictionary = {}
	for connector_value in _corridor_by_edge.values():
		var connector := connector_value as Node3D
		if connector == null:
			continue
		var player_inside := connector.visible and _is_player_on_connector(connector)
		hidden_count += _set_connector_cutaway(connector, player_inside)
		if not player_inside:
			continue
		var from_id := str(connector.get_meta("from_room_id", ""))
		var upper_room := _room_by_id.get(from_id) as DungeonRoom3D
		if (
			upper_room != null
			and _current_room_id == from_id
			and (
				player.global_position.y < upper_room.global_position.y - 0.45
				or (
					(player.global_position - (connector.get_meta("upper_door_position", Vector3.ZERO) as Vector3))
					.dot(connector.get_meta("outward", Vector3.ZERO) as Vector3)
					> 0.65
				)
			)
		):
			# 角色跨过门平面或真正下到楼板以下后切掉上一层渲染；
			# 节点和承重碰撞仍保留，避免屋顶/外立面挡住楼梯镜头。
			cutaway_room_ids[from_id] = true
	var current_room := _room_by_id.get(_current_room_id) as DungeonRoom3D
	if current_room != null:
		current_room.visible = not cutaway_room_ids.has(_current_room_id)
	_stair_cutaway_hidden_count = hidden_count


func _is_player_on_connector(connector: Node3D) -> bool:
	var points: Array = connector.get_meta("path_points", [])
	if points.size() < 2:
		return false
	var lower_y := INF
	var upper_y := -INF
	for point_value in points:
		var point := point_value as Vector3
		lower_y = minf(lower_y, point.y)
		upper_y = maxf(upper_y, point.y)
	if player.global_position.y < lower_y - 0.7 or player.global_position.y > upper_y + 1.0:
		return false
	var player_planar := Vector2(player.global_position.x, player.global_position.z)
	for index in range(points.size() - 1):
		var start := points[index] as Vector3
		var end := points[index + 1] as Vector3
		var a := Vector2(start.x, start.z)
		var b := Vector2(end.x, end.z)
		var segment := b - a
		var length_squared := segment.length_squared()
		if length_squared <= 0.001:
			continue
		var ratio := clampf((player_planar - a).dot(segment) / length_squared, 0.0, 1.0)
		if player_planar.distance_to(a + segment * ratio) <= STAIR_WIDTH * 0.64:
			return true
	return false


func _set_connector_cutaway(root: Node, player_inside: bool) -> int:
	var hidden_count := 0
	if root is MeshInstance3D and root.has_meta("stair_cutaway_surface_y"):
		var mesh := root as MeshInstance3D
		var hide_above_player := (
			player_inside
			and mesh.global_position.y > player.global_position.y + STAIR_CUTAWAY_MARGIN
		)
		mesh.visible = not hide_above_player
		if hide_above_player:
			hidden_count += 1
	for child in root.get_children():
		hidden_count += _set_connector_cutaway(child, player_inside)
	return hidden_count


func _tower_material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _refresh_edge_visuals(a: String, b: String, opened: bool) -> void:
	var room_a := _room_by_id.get(a) as DungeonRoom3D
	var room_b := _room_by_id.get(b) as DungeonRoom3D
	if room_a == null or room_b == null:
		return
	var side := str(_edge_side_by_key.get(_edge_key(a, b), "west"))
	room_a.set_door_open(side, opened)
	room_b.set_door_open(side, opened)


func _update_corridor_streaming(current_id: String) -> void:
	for edge in _corridor_by_edge.keys():
		var connector := _corridor_by_edge[edge] as Node3D
		if connector == null:
			continue
		var ids := str(edge).split("|")
		var active := bool(_open_edges.get(edge, false)) and current_id in ids
		connector.visible = active
		connector.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		_set_connector_collision_enabled(connector, active)


func _set_connector_collision_enabled(root: Node, enabled: bool) -> void:
	if root is CollisionShape3D:
		(root as CollisionShape3D).set_deferred("disabled", not enabled)
	for child in root.get_children():
		_set_connector_collision_enabled(child, enabled)


func _on_room_entered(room: DungeonRoom3D) -> void:
	super(room)
	if room == null:
		return
	var depth := maxi(0, -int(round(room.global_position.y / FLOOR_HEIGHT)))
	if room.room_id == "start":
		room_label.text = "楼顶 · 50×50m"
		player.set_combat_enabled(false)
	elif room.room_id == "facility":
		room_label.text = "设施层 · 30×30m · 安全区"
		player.set_combat_enabled(false)
		var facility_light := room.get_node_or_null("RoomCeilingLight") as WastelandLight3D
		if facility_light != null:
			facility_light.set_light_enabled(true)
	else:
		var combat_floor := depth - 1
		room_label.text = "地下 %d/5 层 · 30×30m · %s" % [
			combat_floor,
			"最终层" if combat_floor == COMBAT_FLOOR_COUNT else room.room_type,
		]
		player.set_combat_enabled(true)
	_refresh_facility_runtime()


func _update_room_streaming(current_id: String) -> void:
	super(current_id)
	var current := _room_by_id.get(current_id) as DungeonRoom3D
	if current == null:
		return
	# 相邻上层保持触发/承重碰撞以支持回爬，但渲染强制隐藏，避免上层楼板盖住镜头。
	for room in _rooms:
		if room.room_id != current_id and room.global_position.y > current.global_position.y + 0.1:
			room.visible = false
	_refresh_facility_runtime()


func _install_facilities() -> void:
	var facility_floor := _room_by_id.get("facility") as DungeonRoom3D
	if facility_floor == null or not _facility_nodes.is_empty():
		return
	var definitions := [
		{
			"name": "MissionOperations", "position": Vector3(-10.8, 0, -10.2),
			"display": "远征情报终端", "description": "查看本轮楼层与下行规则",
			"menu": "", "color": Color(0.88, 0.48, 0.18),
		},
		{
			"name": "Workshop", "position": Vector3(-5.4, 0, -10.2),
			"display": "枪械工坊", "description": "解锁枪身、弹药与配件蓝图",
			"menu": "res://scenes/WorkshopMenu.tscn", "color": Color(0.75, 0.42, 0.16),
		},
		{
			"name": "Divination", "position": Vector3(0.0, 0, -10.2),
			"display": "命运占卜台", "description": "为下一次深入准备命运预兆",
			"menu": "res://scenes/DivinationMenu.tscn", "color": Color(0.55, 0.31, 0.78),
		},
		{
			"name": "Vault", "position": Vector3(-10.8, 0, 10.2),
			"display": "保险柜", "description": "管理撤离物资与下局带入",
			"menu": "res://scenes/VaultMenu.tscn", "color": Color(0.24, 0.58, 0.72),
		},
		{
			"name": "Archive", "position": Vector3(-5.4, 0, 10.2),
			"display": "怪物档案台", "description": "查看成长中的精英与悬赏情报",
			"menu": "res://scenes/MonsterArchiveMenu.tscn", "color": Color(0.48, 0.65, 0.26),
		},
		{
			"name": "FateCollection", "position": Vector3(0.0, 0, 10.2),
			"display": "命运卡收藏台", "description": "浏览已发现的命运卡片",
			"menu": "res://scenes/FateCardCollectionMenu.tscn", "color": Color(0.72, 0.28, 0.58),
		},
		{
			"name": "BaseConsole", "position": Vector3(-10.8, 0, 0.0),
			"display": "基地管理终端", "description": "处理战利品、升级建筑与查看总览",
			"menu": "res://scenes/BaseMenu.tscn", "color": Color(0.28, 0.52, 0.68),
		},
	]
	for definition in definitions:
		var facility := FACILITY_SCENE.instantiate() as BaseFacility3D
		facility.name = str(definition["name"])
		facility.position = definition["position"] as Vector3
		facility.display_name = str(definition["display"])
		facility.description = str(definition["description"])
		facility.facility_color = definition["color"] as Color
		var menu_path := str(definition["menu"])
		if menu_path.is_empty():
			facility.activation_type = BaseFacility3D.ActivationType.SHOW_INFO
		else:
			facility.activation_type = BaseFacility3D.ActivationType.OPEN_MENU
			facility.menu_scene_path = menu_path
		facility_floor.add_child(facility)
		facility.activated.connect(_on_facility_activated)
		_facility_nodes.append(facility)


func _on_facility_activated(facility: BaseFacility3D) -> void:
	if _active_facility_menu != null and is_instance_valid(_active_facility_menu):
		return
	status_label.text = "%s：%s" % [facility.display_name, facility.description]
	if facility.activation_type == BaseFacility3D.ActivationType.OPEN_MENU:
		_open_facility_menu(facility.menu_scene_path)


func _open_facility_menu(scene_path: String) -> void:
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path, "PackedScene"):
		status_label.text = "该设施尚未接入功能。"
		return
	var menu_scene := load(scene_path) as PackedScene
	var menu := menu_scene.instantiate() as CanvasLayer
	if menu == null:
		status_label.text = "设施功能加载失败。"
		return
	if menu is BaseMenu:
		menu.overlay_mode = true
	_active_facility_menu = menu
	add_child(menu)
	menu.tree_exited.connect(_on_active_facility_menu_closed)
	_sync_player_input_lock()


func _on_active_facility_menu_closed() -> void:
	_active_facility_menu = null
	_sync_player_input_lock()


func _has_exclusive_modal() -> bool:
	return (
		(_active_facility_menu != null and is_instance_valid(_active_facility_menu))
		or super()
	)


func try_close_modal_for_pause() -> bool:
	if _active_facility_menu != null and is_instance_valid(_active_facility_menu):
		_active_facility_menu.queue_free()
		return true
	return super()


func _refresh_facility_runtime() -> void:
	if _facility_nodes.is_empty():
		return
	var active := _current_room_id == "facility"
	for facility in _facility_nodes:
		if not is_instance_valid(facility):
			continue
		facility.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		facility.set_deferred("monitoring", active)
		facility.set_deferred("monitorable", active)


func _room_status(type_id: String) -> String:
	if type_id == "FACILITY":
		return "设施安全层：整备完成后从右侧通道继续下行"
	return super(type_id)


func get_facility_count() -> int:
	return _facility_nodes.size()


func get_active_facility_menu() -> CanvasLayer:
	return _active_facility_menu


func get_tower_snapshot() -> Dictionary:
	var combat_floor_records: Array[Dictionary] = []
	var floor_heights: Array[float] = []
	var support_floor_count := 0
	var rendered_floor_count := 0
	for room in _rooms:
		var snapshot := room.get_room_snapshot()
		floor_heights.append(room.global_position.y)
		if bool(snapshot.get("support_collision_persistent", false)):
			support_floor_count += 1
		if room.visible:
			rendered_floor_count += 1
		if room.room_id not in ["start", "facility"]:
			combat_floor_records.append({
				"id": room.room_id,
				"type": room.room_type,
				"dimensions": room.get_dimensions(),
				"height": room.global_position.y,
			})
	var vertical_connector_count := 0
	var closed_door_count := 0
	for corridor in _corridor_by_edge.values():
		if corridor is Node3D and bool((corridor as Node3D).get_meta("is_vertical_connector", false)):
			vertical_connector_count += 1
	for room in _rooms:
		for door_snapshot in room.get_room_snapshot().get("door_snapshots", []):
			if bool(door_snapshot.get("blocks_passage", false)):
				closed_door_count += 1
	return {
		"mode": "tower_descent",
		"rooftop_dimensions": (_room_by_id["start"] as DungeonRoom3D).get_dimensions(),
		"facility_dimensions": (_room_by_id["facility"] as DungeonRoom3D).get_dimensions(),
		"combat_floor_count": combat_floor_records.size(),
		"combat_floors": combat_floor_records,
		"floor_heights": floor_heights,
		"floor_height": FLOOR_HEIGHT,
		"facility_count": get_facility_count(),
		"vertical_connector_count": vertical_connector_count,
		"descent_sides": _descent_side_sequence.duplicate(),
		"support_floor_count": support_floor_count,
		"rendered_floor_count": rendered_floor_count,
		"closed_door_count": closed_door_count,
		"current_room_id": _current_room_id,
		"return_scene_path": return_scene_path,
		"stair_surface_snap_count": _stair_surface_snap_count,
		"stair_cutaway_hidden_count": _stair_cutaway_hidden_count,
		"stair_geometry_m": {
			"door_clear_width": TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M,
			"passage_width": STAIR_WIDTH,
			"approach_outset": TOWER_GEOMETRY.APPROACH_OUTSET_M,
			"run_length": STAIR_RUN,
			"lane_center_spacing": STAIR_LANE_SPACING,
			"guard_end_clearance": TOWER_GEOMETRY.GUARD_END_CLEARANCE_M,
			"floor_thickness": TOWER_GEOMETRY.FLOOR_THICKNESS_M,
		},
	}
