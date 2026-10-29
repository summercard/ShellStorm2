extends Node
## 远征03 实房截图：证明随机布置的易碎小物件真的在游戏房间里，不是只在探针数据里。
## 必须用真实渲染器运行（headless 只能验数据，不能验画面）。

const LEVEL_SCENE := "res://scenes/ExpeditionLevel03_3D.tscn"
const LEVEL_ID := "expedition_03"

var tower: TowerDescent3D
var failures: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("远征03 物件截图需要真实渲染器")
		get_tree().quit(1)
		return
	get_window().size = Vector2i(1600, 1000)
	get_viewport().scaling_3d_scale = 1.0
	if not GameDesignConfig.select_expedition_level(LEVEL_ID):
		push_error("select_expedition_level 被拒绝")
		get_tree().quit(1)
		return
	tower = (load(LEVEL_SCENE) as PackedScene).instantiate() as TowerDescent3D
	tower.set("test_mode", true)
	tower.set("run_seed_override", 100990)
	add_child(tower)
	for step in range(90):
		await get_tree().process_frame
		if not (tower.get("_room_by_id") as Dictionary).is_empty():
			break
	await _settle()
	var rooms: Dictionary = tower.get("_room_by_id")
	var targets: Array[DungeonRoom3D] = []
	for room_id in rooms:
		var room := rooms[room_id] as DungeonRoom3D
		room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		room.ensure_detail_built()
	await _settle()
	for room_id in rooms:
		var room := rooms[room_id] as DungeonRoom3D
		var dimensions := room.get_dimensions()
		if minf(dimensions.x, dimensions.y) < 20.0:
			continue
		if _room_clutter(room).size() < 3:
			continue
		targets.append(room)
	if targets.is_empty():
		push_error("没有找到含易碎物件的房间")
		get_tree().quit(1)
		return
	print("E3_SHOT_TARGETS ", targets.size())
	var out := OS.get_environment("E3_CLUTTER_QA_DIR")
	if out.is_empty():
		out = ProjectSettings.globalize_path("res://outputs/expedition03_clutter_20261029")
	DirAccess.make_dir_recursive_absolute(out)
	# 隐藏 HUD 与玩家，避免遮挡画面
	for value in tower.find_children("*", "CanvasLayer", true, false):
		(value as CanvasLayer).visible = false
	var player := tower.get("player") as Node3D
	if player != null:
		player.visible = false
	var camera := Camera3D.new()
	camera.fov = 68.0
	camera.near = 0.05
	camera.far = 300.0
	add_child(camera)
	camera.make_current()
	var index := 0
	for room_value in targets.slice(0, 3):
		var room: DungeonRoom3D = room_value
		room.set_room_light_on(true)
		var dimensions: Vector2 = room.get_dimensions()
		var center: Vector3 = room.global_position
		# 45° 俯视看全房
		camera.global_position = center + Vector3(dimensions.x * 0.35, dimensions.x * 0.55, dimensions.y * 0.42)
		camera.look_at(center + Vector3(0, 0.2, 0), Vector3.UP)
		for step in range(10):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			"%s/e3_room_%02d_%s.png" % [out, index, room.room_id]
		)
		# 近景：对着该房第一件物件
		var clutter := _room_clutter(room)
		if not clutter.is_empty():
			var target: Vector3 = clutter[0].global_position
			camera.global_position = target + Vector3(1.15, 0.95, 1.35)
			camera.look_at(target + Vector3(0, 0.16, 0))
			for step in range(8):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				"%s/e3_closeup_%02d_%s.png" % [out, index, room.room_id]
			)
			print(
				"E3_SHOT ", room.room_id, " items=", clutter.size(),
				" dims=", dimensions, " first=", target
			)
		index += 1
	print("E3_SHOT_DIR ", out)
	print("E3_SHOT_OK")
	get_tree().quit(0)


func _room_clutter(room: DungeonRoom3D) -> Array[BreakableClutter3D]:
	var result: Array[BreakableClutter3D] = []
	for value in get_tree().get_nodes_in_group("breakable_clutter_3d"):
		var clutter := value as BreakableClutter3D
		if clutter != null and room.is_ancestor_of(clutter):
			result.append(clutter)
	return result


func _settle() -> void:
	for step in range(5):
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout
