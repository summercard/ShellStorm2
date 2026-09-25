extends Node
## 探针 v7：给「远征01 房间内每一类壳体组件」染上互不相同的自发光纯色后实拍。
##
## 目的：一张图直接回答「玩家在房间里看到的每一块墙面，到底是哪一件资产」。
## 染色口径（按实例 meta / 节点名分类，与装配层同源）：
##   · 红色   = 直墙（battle v004 通用墙，slot_role=solid_wall，带 tower_wall_direction）
##   · 橙色   = 桥房下沉坑的坑壁（同一组件，不带 tower_wall_direction）
##   · 绿色   = 角件 L（tower A 套 v007 重装甲，ENV-TOWER-CORNER-L-5M）
##   · 蓝色   = 门墙（battle v004 通用门墙）
##   · 紫色   = 门扇
## 地砖**不染**，保留原色作参照。

const OUT_DIR := "I:/ss2_iso/wall_shots"
const WALL_STANDARD_ID := "ENV-SHARED-GENERIC-WALL-STANDARD-5M"

const COLOR_WALL := Color(1.0, 0.10, 0.10)
const COLOR_PIT := Color(1.0, 0.55, 0.05)
const COLOR_CORNER := Color(0.10, 1.0, 0.20)
const COLOR_DOORWALL := Color(0.15, 0.35, 1.0)
const COLOR_DOORLEAF := Color(0.75, 0.15, 1.0)

var _camera: Camera3D
var _shot_index := 0
var _tally: Dictionary = {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_setup_environment()
	await _phase_assembly_and_tint()
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


func _phase_assembly_and_tint() -> void:
	print("========== 组件分类染色 ==========")
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

	var tinted := 0
	for value in rooms:
		var room := value as DungeonRoom3D
		if room == null or not room.authored_layout_shell:
			continue
		var stack: Array[Node] = [room]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			for sub in node.get_children():
				stack.append(sub)
			var category := _category_of(node)
			if category.is_empty():
				continue
			tinted += _paint(node, _color_of(category))
			_tally[category] = int(_tally.get(category, 0)) + 1
	print("  染色节点数=%d" % tinted)
	var keys := _tally.keys()
	keys.sort()
	for key in keys:
		print("    %-14s %d" % [str(key), int(_tally[key])])
	# 诊断：除了上面五类，房间里还有哪些「带网格但没被归类」的节点（截图里的白色竖条是谁）。
	print("  —— 未归类网格节点（按 名称/资产 去重）——")
	var untinted: Dictionary = {}
	for value in rooms:
		var room := value as DungeonRoom3D
		if room == null or not room.authored_layout_shell:
			continue
		var stack: Array[Node] = [room]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			for sub in node.get_children():
				stack.append(sub)
			if _category_of(node) != "":
				continue
			var mi := node as MeshInstance3D
			if mi == null:
				continue
			var key := "%s|%s|%s" % [
				str(node.name), str(node.get_meta("asset_id", "")),
				str(node.scene_file_path),
			]
			untinted[key] = int(untinted.get(key, 0)) + 1
	var untinted_keys := untinted.keys()
	untinted_keys.sort()
	for key in untinted_keys:
		print("    ×%-4d %s" % [int(untinted[key]), str(key)])
	print("")

	for spec in [
		{"room": "room_01", "tag": "room_01"},
		{"room": "room_04", "tag": "room_04"},
		{"room": "boss", "tag": "boss"},
		{"room": "room_06", "tag": "room_06(桥房)"},
	]:
		await _shoot_room(rooms, str(spec["room"]), str(spec["tag"]))
	# 共墙（共享 lane）正/反两面实拍 —— 直接验证「邻房那一面看到的是什么」。
	await _phase_shared_wall_shots(rooms)
	print("")


func _category_of(node: Node) -> String:
	var name := str(node.name)
	if name.begins_with("Imported_CornerL5M_") or name == "ENV_TOWER_CORNER_L_5M":
		return "corner_L(towerA套)"
	if name == "ENV_TOWER_DOOR_LEAF_5M":
		return "door_leaf"
	var cid := str(node.get_meta("authored_component_id", ""))
	if cid.is_empty():
		return ""
	if cid == WALL_STANDARD_ID:
		if str(node.get_meta("tower_wall_direction", "")).is_empty():
			return "pit_wall(坑壁)"
		return "wall_standard(battle直墙)"
	if cid.contains("WALL-DOOR"):
		return "wall_door(门墙)"
	if cid.contains("GENERIC-DOOR"):
		return "door_leaf"
	return ""


func _color_of(category: String) -> Color:
	match category:
		"wall_standard(battle直墙)":
			return COLOR_WALL
		"pit_wall(坑壁)":
			return COLOR_PIT
		"corner_L(towerA套)":
			return COLOR_CORNER
		"wall_door(门墙)":
			return COLOR_DOORWALL
		_:
			return COLOR_DOORLEAF


## 给节点整棵子树套自发光纯色（覆盖 PaletteUV，避免被色盘盖回原色）。
func _paint(root: Node, color: Color) -> int:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.6
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var count := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for sub in node.get_children():
			stack.append(sub)
		var mi := node as MeshInstance3D
		if mi != null:
			mi.material_override = material
			count += 1
	return count


## 从**地砖形心**出发，眼高 1.7m、俯仰 0°、FOV 90°，朝四个方位各拍一张。
## 这才是玩家在房间正中站着环视时真正看到的东西；俯仰 0° 保证没有仰角把结构背面
## 看成正面，也保证同一面墙在不同方位照里能互相印证。
## 共墙验证：lane 台账里 claims.size()>=2 的那 40 道墙，全局只有**一份**实例，
## 它挂在 owner 房的子树上。于是 owner 房那一侧看到装甲面，邻房那一侧看到结构背面。
## 本段挑几道共墙，站在**同一堵墙的两侧**各拍一张，把「谁看到装甲、谁看到光板」钉死。
func _phase_shared_wall_shots(rooms: Array) -> void:
	print("========== 共墙两侧实拍 ==========")
	var pairs := [
		{"owner": "room_01", "other": "room_02", "axis": "x", "line": 70.0},
		{"owner": "room_04", "other": "room_03", "axis": "y", "line": -20.0},
		{"owner": "boss", "other": "room_10", "axis": "y", "line": 35.0},
	]
	for spec in pairs:
		var owner_room := _find_room(rooms, str(spec["owner"]))
		var other_room := _find_room(rooms, str(spec["other"]))
		if owner_room == null or other_room == null:
			continue
		var wall := _find_lane_wall(
			owner_room, str(spec["axis"]), float(spec["line"])
		)
		if wall == null:
			print("  !! %s 未找到 %s@%.1f 上的墙" % [
				str(spec["owner"]), str(spec["axis"]), float(spec["line"]),
			])
			continue
		var normal := (wall.global_transform.basis * Vector3(0.0, 0.0, -1.0)).normalized()
		var base := wall.global_position
		# 哪一侧通向 owner、哪一侧通向 other：拿两房中心比点积符号。
		var to_owner := owner_room.global_position - base
		var to_other := other_room.global_position - base
		to_owner.y = 0.0
		to_other.y = 0.0
		var owner_is_plus := normal.dot(to_owner.normalized()) > 0.0
		print("  · 共墙 %s@%.1f 世界=(%.1f,%.1f,%.1f) 法向=(%.2f,%.2f,%.2f)" % [
			str(spec["axis"]), float(spec["line"]), base.x, base.y, base.z,
			normal.x, normal.y, normal.z,
		])
		print("      → %s 在法向%s侧；%s 在法向%s侧" % [
			str(spec["owner"]), ("+" if owner_is_plus else "−"),
			str(spec["other"]), ("−" if owner_is_plus else "+"),
		])
		for side in [true, false]:
			var sign := (1.0 if side else -1.0) * (1.0 if owner_is_plus else -1.0)
			var who := str(spec["owner"]) if side else str(spec["other"])
			var expect := "装甲面（它是 owner）" if side else "结构背面（墙不属于它）"
			_camera.fov = 80.0
			_camera.position = Vector3(base.x + normal.x * sign * 6.0, 1.7, base.z + normal.z * sign * 6.0)
			_camera.look_at(Vector3(base.x, 3.0, base.z), Vector3.UP)
			await _capture("80_共墙_%s侧看_预期%s" % [who, expect])
			print("        拍 %s 侧（预期%s）" % [who, expect])


func _find_room(rooms: Array, room_id: String) -> DungeonRoom3D:
	for value in rooms:
		var room := value as DungeonRoom3D
		if room != null and room.authored_layout_shell and room.authored_layout_room_id == room_id:
			return room
	return null


## 在 owner 房里找落在给定 lane（轴 + 平面坐标）上的**非门墙**墙件。
func _find_lane_wall(room: DungeonRoom3D, axis: String, line_m: float) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	var stack: Array[Node] = [room]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for sub in node.get_children():
			stack.append(sub)
		var node3d := node as Node3D
		if node3d == null:
			continue
		if str(node.get_meta("authored_component_id", "")) != WALL_STANDARD_ID:
			continue
		if str(node.get_meta("tower_wall_direction", "")).is_empty():
			continue
		var world := node3d.global_position
		# 房间是**塔楼网格镜像**（world.z = −plan.y）⇒ 拿世界坐标跟 lane 平面比。
		var plane := world.x if axis == "x" else -world.z
		var d := absf(plane - line_m)
		if d < best_d:
			best_d = d
			best = node3d
	return best


func _shoot_room(rooms: Array, wanted: String, tag: String) -> void:
	for value in rooms:
		var room := value as DungeonRoom3D
		if room == null or not room.authored_layout_shell:
			continue
		if room.authored_layout_room_id != wanted:
			continue
		var tiles := _collect_tiles(room)
		if tiles.is_empty():
			print("     %s 跳过：无地砖" % tag)
			return
		var centroid := Vector3.ZERO
		for tile_value in tiles:
			centroid += (tile_value as Node3D).global_position
		centroid /= float(tiles.size())
		print("     %s 地砖形心=(%.1f, %.1f) 砖数=%d" % [
			tag, centroid.x, centroid.z, tiles.size(),
		])
		var yaws := [
			{"n": 0, "yaw": 0.0, "label": "+Z（南）"},
			{"n": 1, "yaw": 90.0, "label": "+X（东）"},
			{"n": 2, "yaw": 180.0, "label": "-Z（北）"},
			{"n": 3, "yaw": 270.0, "label": "-X（西）"},
		]
		for spec in yaws:
			var yaw := deg_to_rad(float(spec["yaw"]))
			# Godot 相机默认朝 -Z；yaw 绕 Y 正向旋转。
			var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
			_camera.fov = 90.0
			_camera.position = Vector3(centroid.x, 1.7, centroid.z)
			_camera.look_at(
				_camera.position + forward, Vector3.UP
			)
			await _capture("71_染色_%s_朝%s" % [tag, str(spec["label"])])
		return


func _collect_tiles(room: DungeonRoom3D) -> Array:
	var tiles: Array = []
	var stack: Array[Node] = [room]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for sub in node.get_children():
			stack.append(sub)
		var node3d := node as Node3D
		if node3d == null:
			continue
		if str(node.get_meta("authored_component_id", "")).contains("FLOOR-TILE"):
			tiles.append(node3d)
	return tiles


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
