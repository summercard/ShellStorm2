extends Node

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const ROOM_IDS := [
	"start", "room_01", "room_02", "room_03", "room_04", "room_05", "room_06",
	"room_07", "room_08", "room_09", "room_10", "boss", "extraction",
]
const EXPECTED_MIN_CHILDREN := {
	"start": 29, "room_01": 121, "room_02": 86, "room_03": 105, "room_04": 123,
	"room_05": 242, "room_06": 86, "room_07": 36, "room_08": 121, "room_09": 106,
	"room_10": 86, "boss": 208, "extraction": 34,
}
var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	for room_id in ROOM_IDS:
		var path := _scene_path(room_id)
		_check(ResourceLoader.exists(path), "%s 静态场景必须存在" % room_id)
		if ResourceLoader.exists(path):
			var packed := load(path) as PackedScene
			_check(packed != null, "%s 必须可加载为 PackedScene" % room_id)
			if packed != null:
				var instance := packed.instantiate() as Node3D
				_check(instance != null, "%s 必须可实例化为 Node3D" % room_id)
				if instance != null:
					add_child(instance)
					_check(str(instance.get_meta("schema", "")) == "shellstorm2.expedition.room_static_layout.v001", "%s schema 错误" % room_id)
					_check(instance.get_child_count() >= int(EXPECTED_MIN_CHILDREN[room_id]), "%s 静态组件数不足" % room_id)
					_check(instance.find_children("*", "RoomDoor3D", true, false).is_empty(), "%s TSCN 不得固化 RoomDoor3D" % room_id)
					_check(instance.get_node_or_null("RoomTrigger") == null, "%s TSCN 不得固化 RoomTrigger" % room_id)
					_check(instance.find_children("*", "NavigationRegion3D", true, false).is_empty(), "%s TSCN 不得固化 NavigationRegion3D" % room_id)
					_check(instance.find_children("RuntimeDetail", "Node3D", true, false).is_empty(), "%s TSCN 不得固化 RuntimeDetail" % room_id)
					if room_id == "room_03":
						_check(
							instance.get_node_or_null("filing_run_west") == null,
							"room_03 入口净空不得固化默认西侧文件柜"
						)
					if room_id == "start":
						_check(
							_count_nodes_with_meta(instance, "tower_wall_corner") == 4,
							"start TSCN 必须包含四个 L 型转角墙 prefab"
						)
						_check(
							_count_nodes_with_meta(instance, "editor_preview_only") == 2,
							"start TSCN 必须包含两扇编辑器门扇预览"
						)
					instance.queue_free()
					await get_tree().process_frame
					await get_tree().physics_frame
	var tower := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	_check(tower != null, "远征场景必须可实例化")
	if tower != null:
		tower.test_mode = true
		tower.run_seed_override = 77001199
		add_child(tower)
		for _index in range(8):
			await get_tree().process_frame
			await get_tree().physics_frame
		var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
		_check(block != null, "运行时必须生成远征区块")
		if block != null:
			for room_id in ROOM_IDS:
				var room := block.get_node_or_null(room_id) as DungeonRoom3D
				_check(room != null, "运行时缺少 %s" % room_id)
				if room == null:
					continue
				room.ensure_shell_built()
				_check(bool(room.get_meta("static_layout_scene_loaded", false)), "%s 必须从 TSCN 加载静态布局" % room_id)
				_check(room.get_node_or_null("RoomTrigger") != null, "%s 必须保留运行时 RoomTrigger" % room_id)
				_check((room.get("_door_nodes") as Dictionary).size() == room.doors.size(), "%s 必须保留全部运行时门" % room_id)
				var art_root := room.get_node_or_null(
					"SafeRoomArtRoot" if room_id == "start" else "AuthoredLayoutArtRoot"
				) as Node3D
				_check(art_root != null, "%s 必须保留静态艺术根" % room_id)
				if art_root != null:
					_check_static_camera_wall_contract(art_root, room_id)
					_check_camera_wall_rotation_invariance(room, art_root, room_id)
				if room_id == "start" and art_root != null:
					_check(
						_count_nodes_with_meta(art_root, "tower_wall_corner") == 4,
						"start 运行时必须保留四个 L 型转角墙"
					)
					_check(
						_count_visible_nodes_with_meta(art_root, "editor_preview_only") == 0,
						"start 运行时必须隐藏两扇编辑器门扇预览"
					)
					_check(
						(room.get("_door_nodes") as Dictionary).size() == 2,
						"start 运行时必须创建两扇动态门"
					)
				if art_root != null and room.authored_layout_shell:
					_check(
						int(art_root.get_meta("layout_instance_total", -1))
						== room.authored_layout_instances.size(),
						"%s TSCN 实例数必须与规划一致" % room_id
					)
					_check(
						(room.get("_authored_tile_cells") as Array).size()
						== int(art_root.get_meta("authored_layout_floor_tile_count", -1)),
						"%s 刷怪 footprint 必须与静态地砖统计一致" % room_id
					)
		tower.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().physics_frame
		_check(not is_instance_valid(tower), "远征验收场景必须在退出前完成释放")
	if failures.is_empty():
		print("EXPEDITION_ROOM_STATIC_SCENES_OK checks=%d rooms=%d" % [checks, ROOM_IDS.size()])
		call_deferred("_finish", 0)
		return
	for failure in failures:
		print("FAIL %s" % failure)
	call_deferred("_finish", 1)

func _finish(exit_code: int) -> void:
	var exit_timer := Timer.new()
	exit_timer.one_shot = true
	exit_timer.wait_time = 0.1
	exit_timer.timeout.connect(get_tree().quit.bind(exit_code))
	get_tree().root.add_child(exit_timer)
	exit_timer.start()
	queue_free()

func _scene_path(room_id: String) -> String:
	return (
		"res://assets/art/environments/tower_zones/expedition/runtime/"
		+ "room_instances/expedition_01/f00_%s_static_layout.tscn" % room_id
	)

func _check_static_camera_wall_contract(art_root: Node, room_id: String) -> void:
	for child in art_root.get_children():
		var corner_id := str(child.get_meta("tower_wall_corner", ""))
		if not corner_id.is_empty():
			var corner_node := child as Node3D
			var basis := corner_node.global_transform.basis
			var long_along_world_x := absf(basis.x.x) >= absf(basis.x.z)
			var short_along_world_x := absf(basis.z.x) >= absf(basis.z.z)
			for value in child.find_children("*", "StaticBody3D", true, false):
				var body := value as StaticBody3D
				var expected := false
				if body.name == "WallCollisionLong":
					expected = long_along_world_x
				elif body.name == "WallCollisionShort":
					expected = short_along_world_x
				else:
					continue
				_check(
					bool(body.get_meta("camera_lower_wall", false)) == expected,
					"%s %s 转角的 %s 世界朝向判定与摄像机墙标记不一致" % [
						room_id, corner_id, body.name
					]
				)
			continue
		if not (child is Node3D):
			continue
		var piece := child as Node3D
		if not _is_wall_piece(piece):
			continue
		var static_bodies: Array[Node] = []
		if piece is StaticBody3D:
			static_bodies.append(piece)
		static_bodies.append_array(piece.find_children("*", "StaticBody3D", true, false))
		if static_bodies.is_empty():
			# 标签 / 预览这类无碰撞装饰件不参与；带 side meta 的墙必须保留碰撞体。
			var direction := str(piece.get_meta("tower_wall_direction", ""))
			_check(
				direction not in ["north", "south", "east", "west"],
				"%s %s 墙必须保留摄像机碰撞" % [room_id, piece.name]
			)
			continue
		# 期望值按**几何**给（墙长轴是否沿世界 X），不按 `tower_wall_direction`：
		# 该 meta 是烘焙当时的方向，房间整体旋转后即过期；且 L 型房型的**内墙**在源
		# 清单里根本没有可用的 side（room_01 内侧横墙标的是 west，几何上却与南外墙
		# 同向）—— 按 meta 判会让内墙漏标，镜头从那里穿出去。转角分支本就走几何口径。
		_check_wall_piece_camera_flags(piece, static_bodies, room_id, "")


## 逐件比对 `camera_lower_wall` 与几何口径。`context` 非空时写进失败信息
## （用于「摆到 90° 时」这类需要标明朝向的场合）。
func _check_wall_piece_camera_flags(
	piece: Node3D, static_bodies: Array[Node], room_id: String, context: String
) -> void:
	var expected := _wall_runs_along_world_x(piece)
	var prefix := "" if context.is_empty() else "%s " % context
	for value in static_bodies:
		var body := value as StaticBody3D
		_check(
			bool(body.get_meta("camera_lower_wall", false)) == expected,
			"%s%s %s 墙的 %s 摄像机墙标记错误（长轴沿世界 X = %s）" % [
				prefix, room_id, piece.name, body.name, str(expected)
			]
		)


## 镜头后墙契约必须**随朝向重放**：随机拼接下每局房间朝向不同（room_01 在各局取过
## 0 / 90 / 180 / 270），而 `tower_wall_direction` 是**烘焙当时**的方向、整体旋转后即过期；
## L 型房型的**内墙**更是连 side 都没有（源清单只标外圈）。
##
## 只在当前朝向查一遍抓不住这条：实测 room_01 在 90°/180°/270° 三个朝向下共 **28 个
## 地砖格点镜头会穿墙**（玩家在走廊北段时，镜头后墙正是那道没被标记的内侧横墙），
## 而它那一局恰好落在 0°、单朝向断言全绿。所以这里把房间依次摆到另外三个朝向、
## 重放契约，再逐件比对标记与几何 —— 判据掉了这条就会当场变红。
func _check_camera_wall_rotation_invariance(
	room: DungeonRoom3D, art_root: Node3D, room_id: String
) -> void:
	var original_rotation := art_root.rotation.y
	for rotation in [90.0, 180.0, 270.0]:
		art_root.rotation.y = deg_to_rad(rotation)
		room._restore_static_layout_camera_wall_contract(art_root)
		for child in art_root.get_children():
			if not (child is Node3D):
				continue
			var piece := child as Node3D
			if not _is_wall_piece(piece) or piece.has_meta("tower_wall_corner"):
				continue
			var bodies: Array[Node] = []
			if piece is StaticBody3D:
				bodies.append(piece)
			bodies.append_array(piece.find_children("*", "StaticBody3D", true, false))
			if bodies.is_empty():
				continue
			_check_wall_piece_camera_flags(
				piece, bodies, room_id, "摆到 %d° 时" % int(rotation)
			)
	art_root.rotation.y = original_rotation
	room._restore_static_layout_camera_wall_contract(art_root)


## 墙件判定：只认组件来源（与 DungeonRoom3D._is_static_layout_wall_piece 同口径）。
func _is_wall_piece(piece: Node3D) -> bool:
	if piece.scene_file_path.is_empty():
		return piece.has_meta("tower_wall_direction")
	if piece.scene_file_path.contains("wall_door") or piece.scene_file_path.contains("door_wall"):
		return true
	return piece.scene_file_path.get_file().begins_with("wall")


## 墙长轴是否沿世界 X：取碰撞盒世界包围盒较长的一边（独立实现，不复用生产代码）。
func _wall_runs_along_world_x(piece: Node3D) -> bool:
	var bounds := AABB()
	var has_bounds := false
	for value in piece.find_children("*", "CollisionShape3D", true, false):
		var collision := value as CollisionShape3D
		var box := collision.shape as BoxShape3D
		if box == null:
			continue
		var shape_basis := collision.global_transform.basis
		var half := box.size * 0.5
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var point: Vector3 = (
						collision.global_transform.origin
						+ shape_basis * (Vector3(sx, sy, sz) * half)
					)
					if not has_bounds:
						bounds = AABB(point, Vector3.ZERO)
						has_bounds = true
					else:
						bounds = bounds.expand(point)
	if not has_bounds:
		return false
	return bounds.size.x >= bounds.size.z


func _count_nodes_with_meta(root: Node, key: StringName) -> int:
	var count := 1 if root.has_meta(key) else 0
	for child in root.get_children():
		count += _count_nodes_with_meta(child, key)
	return count


func _count_visible_nodes_with_meta(root: Node, key: StringName) -> int:
	var count := 0
	if root.has_meta(key) and root is Node3D and (root as Node3D).visible:
		count += 1
	for child in root.get_children():
		count += _count_visible_nodes_with_meta(child, key)
	return count


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
