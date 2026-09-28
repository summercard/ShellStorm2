extends Node

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const ROOM_IDS := [
	"start", "room_01", "room_02", "room_03", "room_04", "room_05", "room_06",
	"room_07", "room_08", "room_09", "room_10", "boss", "extraction",
]
const EXPECTED_MIN_CHILDREN := {
	"start": 29, "room_01": 121, "room_02": 86, "room_03": 106, "room_04": 123,
	"room_05": 242, "room_06": 86, "room_07": 36, "room_08": 121, "room_09": 106,
	"room_10": 86, "boss": 210, "extraction": 34,
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
			var expected_body := (
				"WallCollisionLong" if corner_id in ["SW", "NE"]
				else "WallCollisionShort"
			)
			for value in child.find_children("*", "StaticBody3D", true, false):
				var body := value as StaticBody3D
				if body.name not in ["WallCollisionLong", "WallCollisionShort"]:
					continue
				_check(
					bool(body.get_meta("camera_lower_wall", false)) == (body.name == expected_body),
					"%s %s 转角的 %s 摄像机墙标记错误" % [room_id, corner_id, body.name]
				)
			continue
		var direction := str(child.get_meta("tower_wall_direction", ""))
		if direction not in ["north", "south", "east", "west"]:
			continue
		var static_bodies: Array[Node] = []
		if child is StaticBody3D:
			static_bodies.append(child)
		static_bodies.append_array(child.find_children("*", "StaticBody3D", true, false))
		_check(not static_bodies.is_empty(), "%s %s 墙必须保留摄像机碰撞" % [room_id, direction])
		for value in static_bodies:
			var body := value as StaticBody3D
			_check(
				bool(body.get_meta("camera_lower_wall", false)) == (direction in ["north", "south"]),
				"%s %s 墙的 %s 摄像机墙标记错误" % [room_id, direction, body.name]
			)


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
