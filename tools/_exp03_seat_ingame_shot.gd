extends Node
## 真实关卡内确认：远征03 沙发/扶手椅/地毯放大后，游戏里实际看到的画面。
##
## 用法：godot --path . tools/_exp03_seat_ingame_shot.tscn
## 输出：sessions/.../ingame/<room_id>.png
##
## 走真实关卡 `ExpeditionLevel03_3D.tscn` + 固定种子，只是把相机摆到房间上方，
## 不改任何房间内容 —— 用来对照用户截图，确认结论在真实运行里成立。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const OUT_DIR := "I:/工作项目/shellstrom2/ShellStorm2-work/sessions/2026-11-02_seat_rug_scale/ingame"
const SEED := 1118653462
## 要找的房间类型：入口楼梯厅 + 宴客厅 + 主厅
const WANT_TYPES := ["stair_lobby", "combat", "boss"]

var _shot := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var tower := SCENE.instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", SEED)
	add_child(tower)
	for _i in 30:
		await get_tree().process_frame

	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.far = 400.0
	add_child(cam)
	cam.make_current()

	# 只拍"真的摆了沙发/扶手椅"的房间，每份美术文件一张
	var seen := {}
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room == null or not room.procedural_shell or not room.is_inside_tree():
			continue
		room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		room.ensure_shell_built()
		room.ensure_detail_built()
		for _i in 2:
			await get_tree().process_frame
		var art := _seating_art_path(room)
		print("ROOM %s type=%s dim=%s seat_art=%s" % [room.room_id, str(room.room_type),
			"%s" % room.call("get_dimensions"), art])
		if art == "" or seen.has(art):
			continue
		seen[art] = true
		var dim: Vector2 = room.call("get_dimensions")
		await _render(cam, room, dim, str(room.room_type), room.room_id)
		if seen.size() >= 6:
			break
	print("INGAME_DONE %d" % _shot)
	get_tree().quit(0)


## 房间美术层里是否摆了沙发/扶手椅；返回该美术文件路径（用于去重）。
func _seating_art_path(room: DungeonRoom3D) -> String:
	for node in room.find_children("*", "Node3D", true, false):
		var n3 := node as Node3D
		var asset := str(n3.get_meta("asset_id", ""))
		if asset.contains("MANOR-SOFA") or asset.contains("MANOR-ARMCHAIR"):
			var scene_file := ""
			var walk: Node = n3
			for _i in 8:
				if walk == null:
					break
				if walk.scene_file_path != "":
					scene_file = walk.scene_file_path
					break
				walk = walk.get_parent()
			return str(n3.get_meta("asset_id", "")) + "|" + scene_file
	return ""


func _render(cam: Camera3D, room: DungeonRoom3D, dim: Vector2, rtype: String, rid: String) -> void:
	room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	room.ensure_shell_built()
	room.ensure_detail_built()
	for _i in 3:
		await get_tree().process_frame

	# 关卡自带体积雾把俯视图压暗，出图前关掉；这只影响截图观感，不改关卡配置
	for value in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		var we := value as WorldEnvironment
		if we != null and we.environment != null:
			we.environment.fog_enabled = false
			we.environment.volumetric_fog_enabled = false

	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.03, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.47, 0.52)
	env.ambient_light_energy = 3.2
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-68, 24, 0)
	sun.light_energy = 3.6
	sun.shadow_enabled = false
	add_child(sun)

	var c: Vector3 = room.global_position
	var span := maxf(dim.x, dim.y)
	cam.look_at_from_position(
		c + Vector3(span * 0.42, span * 1.02, span * 0.78),
		c + Vector3(0, 0.4, 0))

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var name := "%s_%s_%s" % [rtype, rid.replace("/", "-"), "%.0fx%.0f" % [dim.x, dim.y]]
	img.save_png(OUT_DIR + "/" + name + ".png")
	_shot += 1
	print("INGAME_SHOT %s" % name)
	world.queue_free()
	sun.queue_free()
