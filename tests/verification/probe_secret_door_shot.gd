extends Node

## 一次性探针：把四个暗门位点**用相机拍下来**，人眼看看到底像不像"墙壁凸出来一块"。
##
## 与 `probe_secret_door_visibility.gd` 的区别：那个只用射线量数据（可 headless），
## 这个要真渲染 —— `--headless` 走 dummy 渲染驱动，`get_viewport().get_texture()`
## 拿不到任何像素，所以必须带窗口跑。
##
## 用法：
##   godot --path . res://tests/verification/probe_secret_door_shot.tscn
## 产物：`outputs/secret_door_shots/<site>_<room>.png`，外加一张 S1 正面照。

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const DEFAULT_SEED := 77001199
const OUT_DIR := "res://outputs/secret_door_shots"
const SHOT_W := 1280
const SHOT_H := 720

## 退到房间里多远、偏到侧面多少、机位多高（人眼略高一点好看墙的凸起）。
const SHOT_BACK_M := 4.6
## 正面照退多少：比 3/4 近一点，门占画面更满。
const SHOT_FRONT_M := 3.4
## 贴近拍一张：4.6m 那张如果看不见门，这张能区分「门没渲染」还是「中间有东西挡」。
const SHOT_CLOSE_M := 1.4
const SHOT_SIDE_M := 1.9
const SHOT_EYE_Y_M := 1.62
const LOOK_Y_M := 1.15

var _branch: Node = null


func _ready() -> void:
	get_window().size = Vector2i(SHOT_W, SHOT_H)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var scene := load(EXPEDITION_SCENE) as PackedScene
	if scene == null:
		print("SECRET_DOOR_SHOT_MISS 远征场景加载失败")
		get_tree().quit(0)
		return
	var tower := scene.instantiate() as TowerDescent3D
	if tower == null:
		print("SECRET_DOOR_SHOT_MISS 远征场景实例化失败")
		get_tree().quit(0)
		return
	tower.test_mode = true
	var seed_env := OS.get_environment("SS2_SEED")
	tower.run_seed_override = int(seed_env) if not seed_env.is_empty() else DEFAULT_SEED
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	_branch = tower.get_node_or_null("SecretBranches")
	if _branch == null:
		print("SECRET_DOOR_SHOT_MISS 没有 SecretBranches 节点")
		get_tree().quit(0)
		return

	# 战局 HUD 会糊住画面，截图时全关；玩家相机也交出来，别跟我们的机位抢。
	_hide_ui(tower)
	_release_cameras(tower)

	# 对照实验用：`SS2_SHOT_HIDE=<路径子串>` 把命中的绘制件藏掉，看门是否露出来，
	# 从而确定到底是谁挡的；`SS2_SHOT_ONLY=S2` 只拍一个位点。
	var hide := OS.get_environment("SS2_SHOT_HIDE")
	if not hide.is_empty():
		var hidden := _hide_matching(tower, hide)
		print("对照实验：藏掉 %d 个含 \"%s\" 的绘制件" % [hidden, hide])
	var only := OS.get_environment("SS2_SHOT_ONLY")

	var normal_at := _site_normals()
	var shot := 0
	for site_id in ["S1", "S2", "S3", "S4"]:
		if not only.is_empty() and site_id != only:
			continue
		var door := _branch.get_node_or_null("SecretDoor_%s" % site_id) as Node3D
		if door == null:
			print("  跳过 %s（本次种子没刷出）" % site_id)
			continue
		_inspect(site_id, door)
		if not normal_at.has(site_id):
			print("  跳过 %s（快照里没有这个位点的法线）" % site_id)
			continue
		var normal := normal_at[site_id] as Vector3
		var room_id := str(normal_at.get("%s_room" % site_id, ""))
		_report_room_light(room_id)
		var tangent := normal.cross(Vector3.UP).normalized()
		# 沿墙往空间更宽的一侧偏：偏到墙角那一侧，画面前景会被半堵墙糊住。
		var side := _side_sign(door, room_id, tangent) * SHOT_SIDE_M
		await _shoot(door, normal, tangent, side, SHOT_BACK_M, "%s_%s" % [site_id, room_id])
		await _shoot(door, normal, tangent, 0.0, SHOT_CLOSE_M, "%s_%s_close" % [site_id, room_id])
		# 正面照：不偏侧，四道门构图一致，最能说明"墙面凸出来一块"。
		await _shoot(door, normal, tangent, 0.0, SHOT_FRONT_M, "%s_%s_front" % [site_id, room_id])
		shot += 3

	print("")
	print("SECRET_DOOR_SHOT_OK seed=%d 张数=%d 目录=%s" % [tower.run_seed_override, shot, OUT_DIR])
	get_tree().quit(0)


## 从 `debug_snapshot()` 的 sites 里拿每个位点的外法线（`position` 已含外推量）。
func _site_normals() -> Dictionary:
	var out: Dictionary = {}
	var snapshot := _branch.call("debug_snapshot") as Dictionary
	var sites: Array = snapshot.get("sites", []) as Array
	for value in sites:
		var site := value as Dictionary
		var site_id := str(site.get("site_id", ""))
		if site_id.is_empty():
			continue
		var wall := str(site.get("wall", ""))
		var normal := Vector3.ZERO
		match wall:
			"south":
				normal = Vector3(0.0, 0.0, 1.0)
			"north":
				normal = Vector3(0.0, 0.0, -1.0)
			"east":
				normal = Vector3(1.0, 0.0, 0.0)
			"west":
				normal = Vector3(-1.0, 0.0, 0.0)
		if normal == Vector3.ZERO:
			continue
		out[site_id] = normal
		out["%s_room" % site_id] = str(site.get("room_id", ""))
	return out


func _shoot(door: Node3D, normal: Vector3, tangent: Vector3, side_m: float, back_m: float, label: String) -> void:
	var cam := Camera3D.new()
	cam.fov = 68.0
	cam.near = 0.05
	cam.far = 400.0
	add_child(cam)

	var target := door.global_position + Vector3(0.0, LOOK_Y_M, 0.0)
	var eye := target - normal * back_m + tangent * side_m
	eye.y = SHOT_EYE_Y_M
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	cam.current = true

	# 塔内是夜间光，暗门本身没有自发光，不补光就是一团黑 —— 这不是"看不见"的
	# 证据，只是没光照。挂一盏**拍照专用**的补光（跟着相机走，朝正前方），
	# 与游戏内实际照明无关，仅用于把几何形状照出来。
	# `SS2_SHOT_NOFILL=1` 关掉补光 = 还原玩家在游戏里真实看到的样子。
	if OS.get_environment("SS2_SHOT_NOFILL") != "1":
		_add_fill_lights(cam)

	var projected := cam.unproject_position(target)
	print("    机位=(%.1f, %.1f, %.1f) 门=(%.1f, %.1f, %.1f) 屏幕坐标=(%.0f, %.0f)" % [
		eye.x, eye.y, eye.z,
		door.global_position.x, door.global_position.y, door.global_position.z,
		projected.x, projected.y,
	])

	# 给渲染器几帧：材质/骨骼/灯光的首帧装配都在这里完成。
	for _i in range(6):
		cam.current = true
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.get_width() == 0:
		print("  ✘ %s 取帧失败（渲染驱动拿不到画面）" % label)
		cam.queue_free()
		return
	var path := "%s/%s.png" % [OUT_DIR, label]
	var err := image.save_png(path)
	print("  %s  %s  (%dx%d)" % ["✔" if err == OK else "✘", path, image.get_width(), image.get_height()])
	cam.queue_free()


## 拍照补光：一盏朝正前方的聚光 + 一盏近身补光。**只用于看清几何**，
## 与游戏内真实照明无关；`SS2_SHOT_NOFILL=1` 时完全不挂，等于玩家视角。
func _add_fill_lights(cam: Camera3D) -> void:
	var lamp := SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.97, 0.92)
	lamp.light_energy = 9.0
	lamp.spot_range = 16.0
	lamp.spot_angle = 46.0
	lamp.spot_attenuation = 0.8
	lamp.shadow_enabled = false
	cam.add_child(lamp)
	lamp.position = Vector3(0.0, 0.0, 0.0)
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.85, 0.9, 1.0)
	fill.light_energy = 2.2
	fill.omni_range = 9.0
	fill.shadow_enabled = false
	cam.add_child(fill)
	fill.position = Vector3(0.0, 0.4, 0.6)


func _hide_ui(root: Node) -> void:
	for node in root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	for node in root.find_children("*", "Control", true, false):
		(node as Control).visible = false


## 沿墙方向哪边空间更大（+1 / -1）：机位偏到空间大的一侧，前景才不会被墙糊住。
func _side_sign(door: Node3D, room_id: String, tangent: Vector3) -> float:
	var rooms: Variant = _branch.get("_room_nodes")
	if not (rooms is Dictionary) or not (rooms as Dictionary).has(room_id):
		return 1.0
	var room := (rooms as Dictionary)[room_id] as Node3D
	if room == null:
		return 1.0
	var dims: Vector2 = room.call("get_dimensions")
	var along := (door.global_position - room.global_position).dot(tangent)
	# 南北墙沿 X 展开、东西墙沿 Z 展开，半长要取对应那个轴。
	var half := (dims.x if absf(tangent.x) > 0.5 else dims.y) * 0.5
	var free_plus := half - along
	var free_minus := half + along
	return 1.0 if free_plus >= free_minus else -1.0


func _release_cameras(root: Node) -> void:
	for node in root.find_children("*", "Camera3D", true, false):
		(node as Camera3D).current = false


func _hide_matching(root: Node, needle: String) -> int:
	var count := 0
	for node in root.find_children("*", "VisualInstance3D", true, false):
		var path := str(node.get_path())
		if not path.contains(needle):
			continue
		(node as VisualInstance3D).visible = false
		count += 1
	return count


## 门的"在不在画面上"自查：节点可见链、缩放、木板网格数。
## 房间灯状态：塔内默认夜间光，房间灯通常是**关着等玩家去按开关**的。
## 若关着，玩家看到的是一片黑 —— 那"看不见暗门"就跟几何无关了。
func _report_room_light(room_id: String) -> void:
	var rooms: Variant = _branch.get("_room_nodes")
	if not (rooms is Dictionary) or not (rooms as Dictionary).has(room_id):
		return
	var room := (rooms as Dictionary)[room_id] as Node3D
	if room == null:
		return
	var is_on := false
	if room.has_method("is_room_light_on"):
		is_on = bool(room.call("is_room_light_on"))
	var force := OS.get_environment("SS2_SHOT_ROOMLIGHT")
	if force == "on" and not is_on and room.has_method("set_room_light_on"):
		room.call("set_room_light_on", true)
		is_on = true
	var energy := 0.0
	for node in room.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if light.visible and light.light_energy > 0.0:
			energy = maxf(energy, light.light_energy)
	# 直连把房间灯点亮：走开关会放 4.5s 的"启动演出"，探针里等不起。
	if OS.get_environment("SS2_SHOT_FORCELIGHT") == "1":
		var lit := 0
		for node in room.find_children("*", "Light3D", true, false):
			if node.has_method("set_light_enabled"):
				node.call("set_light_enabled", true)
				lit += 1
		await get_tree().create_timer(0.6).timeout
		print("  [灯] %s 强制点亮 %d 盏灯" % [room_id, lit])
	print("  [灯] %s 房间灯=%s 最亮灯能量=%.2f" % [room_id, "开" if is_on else "关", energy])


func _inspect(site_id: String, door: Node3D) -> void:
	var boards := door.get_node_or_null("Boards") as Node3D
	var meshes := 0
	if boards != null:
		for node in boards.find_children("*", "MeshInstance3D", true, false):
			if (node as MeshInstance3D).mesh != null:
				meshes += 1
	print("  [检查] %s visible=%s in_tree=%s 缩放=%.2f 木板网格=%d" % [
		site_id, str(door.visible), str(door.is_visible_in_tree()),
		door.global_transform.basis.get_scale().x, meshes,
	])
