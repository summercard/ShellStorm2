extends Node
## 探针 终版 v3：共墙两面「正对实拍」—— 全部基于**运行时几何**，不依赖任何固定种子。
##
## v2 的漏洞：用固定 seed 跑设计源台账算出墙名，再去装配场按名查找。
## 但装配场的版图种子不是这个固定值 ⇒ 墙名对不上（每次都报「找不到节点」）。
##
## v3 判据（只用运行时数据）：
##   1. 每个房间的地砖集合给出该房的**实际占地区域**（XZ 凸包矩形，地块格心已知）；
##   2. 每面墙的装饰面法向 n 已知（prefab forward_axis = −Z 经实例旋转变换）；
##   3. 从墙心沿 ±n 各走 2.5m 得两个采样点：
##        · 两侧都落在**某个房间**里（且不是同一间） ⇒ 这是相邻共墙；
##        · 只有一侧落在房间里                       ⇒ 这是外墙。
##   4. 把共墙的「装甲侧 / 结构背侧」各正对拍一张。

const OUT_DIR := "I:/ss2_iso/wall_shots"
const WALL_STANDARD_ID := "ENV-SHARED-GENERIC-WALL-STANDARD-5M"
const PROBE_OFFSET := 2.5

var _camera: Camera3D
var _shot_index := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_setup_environment()
	await _run()
	print("\nDONE shots=%d" % _shot_index)
	get_tree().quit(0)


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.60, 0.66)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.60, 0.68)
	env.ambient_light_energy = 0.55
	var world_env := WorldEnvironment.new()
	world_env.name = "ProbeWorldEnvironment"
	world_env.environment = env
	add_child(world_env)
	# 三盏灯分打 ±Z / 侧向：共墙两面都得有光。
	for spec in [
		Vector3(-26.0, 0.0, 0.0), Vector3(-26.0, 180.0, 0.0), Vector3(-34.0, 90.0, 0.0),
	]:
		var sun := DirectionalLight3D.new()
		sun.name = "ProbeSun"
		sun.rotation_degrees = spec
		sun.light_energy = 0.9
		sun.shadow_enabled = true
		add_child(sun)
	_camera = Camera3D.new()
	_camera.name = "ProbeCamera"
	_camera.near = 0.05
	add_child(_camera)


func _run() -> void:
	print("========== 运行时几何判定：外墙 vs 共墙 ==========")
	var scene := load("res://scenes/ExpeditionLevel01_3D.tscn") as PackedScene
	if scene == null:
		print("  !! 场景加载失败")
		return
	var instance := scene.instantiate()
	add_child(instance)
	for _i in range(12):
		await get_tree().process_frame
	var hud := instance.get_node_or_null("HUD")
	if hud != null:
		(hud as CanvasLayer).visible = false
	var rooms := get_tree().get_nodes_in_group("dungeon_room_3d")
	for value in rooms:
		var room := value as DungeonRoom3D
		if room != null and room.authored_layout_shell:
			room.set_stream_state(2)
	await get_tree().process_frame

	# ① 每个房间的占地（地砖格心的 XZ 范围）。
	var footprints: Array = []
	for value in rooms:
		var room := value as DungeonRoom3D
		if room == null or not room.authored_layout_shell:
			continue
		var tiles := _tiles_of(room)
		if tiles.is_empty():
			continue
		var min_x := INF
		var max_x := -INF
		var min_z := INF
		var max_z := -INF
		for tile_value in tiles:
			var p := (tile_value as Node3D).global_position
			min_x = minf(min_x, p.x)
			max_x = maxf(max_x, p.x)
			min_z = minf(min_z, p.z)
			max_z = maxf(max_z, p.z)
		footprints.append({
			"room": room, "id": room.authored_layout_room_id,
			"min_x": min_x, "max_x": max_x, "min_z": min_z, "max_z": max_z,
			"tiles": tiles.size(),
		})
	print("  房间占地（地砖范围 + 外扩 2.5m 视为房间内侧）：")
	for value in footprints:
		var fp := value as Dictionary
		print("    %-12s X[%.1f, %.1f] Z[%.1f, %.1f] 砖=%d" % [
			str(fp["id"]), float(fp["min_x"]) - 2.5, float(fp["max_x"]) + 2.5,
			float(fp["min_z"]) - 2.5, float(fp["max_z"]) + 2.5, int(fp["tiles"]),
		])
	print("")

	# ② 逐墙判定：沿法向 ±2.5m 两点各自落在哪间房。
	var exterior := 0
	var shared: Array = []
	for value in rooms:
		var room := value as DungeonRoom3D
		if room == null or not room.authored_layout_shell:
			continue
		for wall_value in _walls_of(room):
			var wall := wall_value as Node3D
			var normal := (wall.global_transform.basis * Vector3(0.0, 0.0, -1.0)).normalized()
			var base := wall.global_position
			var plus := base + normal * PROBE_OFFSET
			var minus := base - normal * PROBE_OFFSET
			var room_plus := _room_at(footprints, plus)
			var room_minus := _room_at(footprints, minus)
			if room_plus != "" and room_minus != "" and room_plus != room_minus:
				shared.append({
					"wall": wall, "owner": str(room.authored_layout_room_id),
					"plus_room": room_plus, "minus_room": room_minus,
					"base": base, "normal": normal,
					"name": str(wall.name),
				})
			elif room_plus.is_empty() and room_minus.is_empty():
				exterior += 1
	print("  —— 共墙 %d 面 · 两侧皆空（外圈墙）%d 面 ——" % [shared.size(), exterior])
	print("  共墙清单（owner = 声明并持有该墙实例的房间）：")
	for value in shared:
		var row := value as Dictionary
		var base: Vector3 = row["base"]
		print("    %-26s owner=%-12s 法向+侧=%-12s 法向−侧=%-12s 世界=(%.1f, %.1f, %.1f)" % [
			str(row["name"]), str(row["owner"]), str(row["plus_room"]),
			str(row["minus_room"]), base.x, base.y, base.z,
		])
	print("")

	# ③ 挑 3 面共墙，正对两侧各拍一张（同距离同 FOV）。
	var shot := 0
	for value in shared:
		if shot >= 3:
			break
		var row := value as Dictionary
		var base: Vector3 = row["base"]
		var normal: Vector3 = row["normal"]
		var plus_room := str(row["plus_room"])
		var minus_room := str(row["minus_room"])
		# 装饰面（法向所指）朝哪一间，那一间就是「看到装甲」的房间。
		shot += 1
		print("  · 共墙 #%d %s：法向侧=%s（应看到装甲面）／反侧=%s（应看到结构背）" % [
			shot, str(row["name"]), plus_room, minus_room,
		])
		_camera.fov = 55.0
		for sign in [1.0, -1.0]:
			var who := plus_room if sign > 0.0 else minus_room
			var expect := "装甲面" if sign > 0.0 else "结构背面"
			_camera.position = Vector3(
				base.x + normal.x * sign * 7.5, 5.6, base.z + normal.z * sign * 7.5
			)
			_camera.look_at(Vector3(base.x, 5.6, base.z), Vector3.UP)
			await _capture("90_共墙%02d_%s侧（%s）" % [shot, who, expect])
	print("")


## 采样点落在哪个房间里（用「离最近的砖有多远」放宽到 2.5m，等价于房间轮廓外扩）。
func _room_at(footprints: Array, point: Vector3) -> String:
	var best := ""
	var best_d := 2.51
	for value in footprints:
		var fp := value as Dictionary
		# 点到矩形距离。
		var dx := maxf(maxf(float(fp["min_x"]) - point.x, point.x - float(fp["max_x"])), 0.0)
		var dz := maxf(maxf(float(fp["min_z"]) - point.z, point.z - float(fp["max_z"])), 0.0)
		var d := sqrt(dx * dx + dz * dz)
		if d < best_d:
			best_d = d
			best = str(fp["id"])
	return best


func _tiles_of(room: DungeonRoom3D) -> Array:
	var out: Array = []
	var stack: Array[Node] = [room]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for sub in node.get_children():
			stack.append(sub)
		var node3d := node as Node3D
		if node3d == null:
			continue
		if str(node3d.get_meta("authored_component_id", "")).contains("FLOOR-TILE"):
			out.append(node3d)
	return out


func _walls_of(room: DungeonRoom3D) -> Array:
	var out: Array = []
	var stack: Array[Node] = [room]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for sub in node.get_children():
			stack.append(sub)
		var node3d := node as Node3D
		if node3d == null:
			continue
		if str(node3d.get_meta("authored_component_id", "")) != WALL_STANDARD_ID:
			continue
		if str(node3d.get_meta("tower_wall_direction", "")).is_empty():
			continue
		out.append(node3d)
	return out


func _capture(label: String) -> void:
	_camera.make_current()
	for _i in range(3):
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		print("  !! %s 截图失败" % label)
		return
	_shot_index += 1
	var path := "%s/%s.png" % [OUT_DIR, label]
	var err := image.save_png(path)
	print("     截图 %s (err=%d)" % [path, err])
