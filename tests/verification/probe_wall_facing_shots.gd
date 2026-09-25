extends Node
## 探针 v5：远征01 墙面实证 —— 「装饰面朝向」用**本房地砖**判内外（凹形房也准）。
##
## 为什么换判据：房间可能不是矩形（L 形走廊 / U 形办公 / 桥房），此时「几何中心」
## 可能落在房间外面，用 `法向·(中心−墙)` 会把朝房内的墙误判成朝外。
## 地砖只铺在轮廓内部（`point_in_polygon` 过滤），所以「离墙最近的那几块砖在本房侧
## 还是另一侧」是**不依赖凸性**的内外判据。
##
## 同时把「共享 lane」的两侧归属摊开：一道共墙全局只有一份实例，
## 声明它的 owner 房看到装甲面，另一房看到结构背面。

const GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const LOADER := preload("res://src/map/LevelPlanLoader.gd")
const BUILDER := preload("res://src/world3d/RoomShellLayoutBuilder3D.gd")

const LEVEL := "expedition_01"
const SEED := 700000
const OUT_DIR := "I:/ss2_iso/wall_shots"

const WALL_STANDARD_ID := "ENV-SHARED-GENERIC-WALL-STANDARD-5M"

var _camera: Camera3D
var _shot_index := 0
## `authored_shell_block()` 返回的是**房间摆位记录数组**（Array），`build_block()` 也吃 Array。
var _block: Array = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_setup_environment()
	_phase_lane_audit()
	await _phase_assembly()
	print("\nDONE shots=%d" % _shot_index)
	get_tree().quit(0)


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.52, 0.57, 0.62)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.48, 0.54, 0.62)
	env.ambient_light_energy = 0.45
	var world_env := WorldEnvironment.new()
	world_env.name = "ProbeWorldEnvironment"
	world_env.environment = env
	add_child(world_env)
	for spec in [Vector3(-24.0, 112.0, 0.0), Vector3(-30.0, -68.0, 0.0)]:
		var sun := DirectionalLight3D.new()
		sun.name = "ProbeSun"
		sun.rotation_degrees = spec
		sun.light_energy = 1.15
		sun.shadow_enabled = true
		add_child(sun)
	_camera = Camera3D.new()
	_camera.name = "ProbeCamera"
	_camera.fov = 70.0
	_camera.near = 0.05
	add_child(_camera)


## ① lane 台账 + 共享 lane 的品牌归属。
func _phase_lane_audit() -> void:
	print("========== ① lane 台账与共享 lane 归属 ==========")
	var level_plan := LOADER.load_level_plan(LEVEL)
	var policy := level_plan.get("generation_policy", {}) as Dictionary
	var templates := LOADER.load_room_templates(LEVEL)
	var normalized := LOADER.normalize_floor(LEVEL, 0)
	var generated := GENERATOR._generate_constrained_floor(
		LEVEL, 0, SEED, normalized, policy, templates
	)
	_block = GENERATOR.authored_shell_block(generated.get("rooms", []), templates)
	var result := BUILDER.build_block(_block)
	var lanes := result.get("wall_lanes", []) as Array
	var seen: Dictionary = {}
	var dup := 0
	var shared_rows: Array = []
	for value in lanes:
		var lane := value as Dictionary
		var axis := str(lane.get("axis", ""))
		var line_m := float(lane.get("line_m", 0.0))
		var lane_key := int(lane.get("lane_key", 0))
		var key := "%s|%s|%d" % [axis, str(line_m), lane_key]
		if seen.has(key):
			dup += 1
		else:
			seen[key] = true
		var claims := (lane.get("claims", []) as Array)
		if claims.size() >= 2:
			shared_rows.append({
				"lane": "%s@%.1f#%d" % [axis, line_m, lane_key],
				"owner": str(lane.get("owner_room", "")),
				"claims": claims,
			})
	print("  wall_lanes=%d   唯一 lane=%d   重复=%d" % [lanes.size(), seen.size(), dup])
	print("  共享 lane=%d ⇒ 这 %d 道墙每道只出一份实例，另一房看到的是结构背面" % [
		shared_rows.size(), shared_rows.size(),
	])
	for value in shared_rows:
		var row := value as Dictionary
		print("    %-16s owner=%-10s claims=%s" % [
			str(row["lane"]), str(row["owner"]), str(row["claims"]),
		])
	print("")


## ② 用本房地砖判内外 + ④ 实拍。
## ⚠️ 必须把「房间外墙」与「桥房下沉坑的坑壁」分开统计：
## 坑壁用的也是同一个通用墙组件，但它按 `_spawn_authored_multi_level` 摆、**不写
## `tower_wall_direction`**（DungeonRoom3D L2019 注释），朝向规则是「朝坑内」而非
## 「朝房内」。混在一起会把坑壁的合法朝向算成假红（room_02/room_06 实测各 17/14 面）。
func _phase_assembly() -> void:
	print("========== ② 朝向普查（地砖判内外）==========")
	var scene := load("res://scenes/ExpeditionLevel01_3D.tscn") as PackedScene
	if scene == null:
		print("  !! 场景加载失败")
		return
	var instance := scene.instantiate()
	add_child(instance)
	for _i in range(10):
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

	var total_in := 0
	var total_out := 0
	var total_pit := 0
	var reports: Array = []
	for value in rooms:
		var room := value as DungeonRoom3D
		if room == null or not room.authored_layout_shell:
			continue
		var nodes := _collect(room)
		var walls: Array = nodes["walls"]
		var pits: Array = nodes["pits"]
		var tiles: Array = nodes["tiles"]
		if walls.is_empty() and pits.is_empty():
			continue
		var inward: Array = []
		var outward: Array = []
		for wall_value in walls:
			var wall := wall_value as Node3D
			var normal := (wall.global_transform.basis * Vector3(0.0, 0.0, -1.0)).normalized()
			if _tiles_on_normal_side(wall.global_position, normal, tiles):
				inward.append(wall)
			else:
				outward.append(wall)
		var pits_facing := 0
		for pit_value in pits:
			var pit := pit_value as Node3D
			var normal := (pit.global_transform.basis * Vector3(0.0, 0.0, -1.0)).normalized()
			var to_center := room.global_position - pit.global_position
			to_center.y = 0.0
			if to_center.length() > 0.01 and normal.dot(to_center.normalized()) > 0.0:
				pits_facing += 1
		total_in += inward.size()
		total_out += outward.size()
		total_pit += pits.size()
		reports.append({
			"room": room, "id": room.authored_layout_room_id, "walls": walls,
			"tiles": tiles, "inward": inward, "outward": outward,
		})
		print("  · %-12s 外墙%2d 坑壁%2d 地砖%3d ｜ 装甲朝房内 %2d ｜ 朝外(看到结构背) %2d ｜ 坑壁朝房心 %d/%d" % [
			str(room.authored_layout_room_id), walls.size(), pits.size(), tiles.size(),
			inward.size(), outward.size(), pits_facing, pits.size(),
		])
	print("  —— 合计：外墙装甲朝房内 %d 面 · 朝外 %d 面 · 坑壁 %d 面 ——" % [
		total_in, total_out, total_pit,
	])
	print("")
	await _phase_shots(reports)
	print("")


## 只有本房该侧确实铺了砖，才算「装甲朝本房」。
## 取最近 3 块砖多数票：薄房/凹角单块砖可能恰好落在墙的另一侧。
func _tiles_on_normal_side(
	wall_pos: Vector3, normal: Vector3, tiles: Array
) -> bool:
	if tiles.is_empty():
		return true
	var scored: Array = []
	for value in tiles:
		var tile := value as Node3D
		var delta := tile.global_position - wall_pos
		delta.y = 0.0
		scored.append({"d": delta.length(), "s": normal.dot(delta)})
	scored.sort_custom(func(a, b) -> bool: return float(a["d"]) < float(b["d"]))
	var positive := 0
	var negative := 0
	for i in range(mini(3, scored.size())):
		if float((scored[i] as Dictionary)["s"]) > 0.0:
			positive += 1
		else:
			negative += 1
	return positive > negative


## ④ 实拍：装甲面正对 / 背面 —— 都在「本房地砖所在」的那一侧取景，保证是玩家视角。
func _phase_shots(reports: Array) -> void:
	print("========== ④ 实拍 ==========")
	var shot_rooms := ["room_01", "room_02", "room_04", "room_09", "boss"]
	for value in reports:
		var item := value as Dictionary
		var room_id := str(item["id"])
		if room_id not in shot_rooms:
			continue
		var walls: Array = item["walls"]
		var outward: Array = item["outward"]
		var inward: Array = item["inward"]
		if not inward.is_empty():
			await _shoot(room_id, inward[0] as Node3D, "60", "装甲朝房内")
		if not outward.is_empty():
			await _shoot(room_id, outward[0] as Node3D, "61", "装甲朝外·本房看到结构背")
		# 房内全景：站第一块砖上、眼高，朝样本墙看（同框直墙 + 角件 + 门墙）。
		if not walls.is_empty():
			var wall := walls[0] as Node3D
			var anchor := (item["tiles"] as Array)[0] as Node3D
			var wp := wall.global_position
			_camera.fov = 80.0
			_camera.position = Vector3(anchor.global_position.x, 1.7, anchor.global_position.z)
			_camera.look_at(Vector3(wp.x, 5.0, wp.z), Vector3.UP)
			await _capture("62_%s_房内全景" % room_id)


func _shoot(room_id: String, wall: Node3D, index: String, tag: String) -> void:
	var normal := (wall.global_transform.basis * Vector3(0.0, 0.0, -1.0)).normalized()
	var base := wall.global_position
	_camera.fov = 75.0
	_camera.position = Vector3(base.x + normal.x * 4.5, 1.7, base.z + normal.z * 4.5)
	_camera.look_at(Vector3(base.x, 2.4, base.z), Vector3.UP)
	await _capture("%s_%s_%s" % [index, room_id, tag])
	print("     [%s] %s dir=%s 世界=(%.1f,%.1f,%.1f) 法向=(%.2f,%.2f,%.2f) 局部转角=%.1f°" % [
		tag, room_id, str(wall.get_meta("tower_wall_direction", "")),
		base.x, base.y, base.z, normal.x, normal.y, normal.z, rad_to_deg(wall.rotation.y),
	])


## 分类收集：本房外墙 / 坑壁 / 地砖。
## `tower_wall_direction` 非空 = 四向房间外墙（`_spawn_authored_layout_wall` 写的）；
## 为空且带同一组件 id = 桥房下沉坑的坑壁（`_spawn_authored_multi_level` 摆的）。
func _collect(room: DungeonRoom3D) -> Dictionary:
	var walls: Array = []
	var pits: Array = []
	var tiles: Array = []
	var stack: Array[Node] = [room]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for sub in node.get_children():
			stack.append(sub)
		var cid := str(node.get_meta("authored_component_id", ""))
		var node3d := node as Node3D
		if node3d == null:
			continue
		if cid.contains("FLOOR-TILE"):
			tiles.append(node3d)
		elif cid == WALL_STANDARD_ID and not bool(node.get_meta("authored_door_wall_promoted", false)):
			if str(node.get_meta("tower_wall_direction", "")).is_empty():
				pits.append(node3d)
			else:
				walls.append(node3d)
	return {"walls": walls, "pits": pits, "tiles": tiles}


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
