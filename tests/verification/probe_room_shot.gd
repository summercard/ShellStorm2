extends Node

## 一次性探针（业主 2026-10-21）：「08 号房间的装配也有问题，检查一下。」
##
## 数不出来就拍下来看。用真实游戏流程（`test_mode = false`）加载远征 01，
## 把目标房间拍成 6 张图：
##   00_overhead  正上方 26 m 俯视（一眼看墙、地板、门、家具的关系）
##   01..04       房心 1.7 m 平视 北/东/南/西
##   05_door_in   从主路门内侧朝房心
##
## 用法（必须带窗口，headless 出不了图）：
##   SS2_ROOM=room_08 godot --path . res://tests/verification/probe_room_shot.tscn

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const WAIT_LIMIT_S := 60.0
const OUT_ROOT := "res://outputs/room_shot"
const EYE_Y := 1.70
const OVERHEAD_M := 26.0

var _tower: TowerDescent3D = null
var _room: DungeonRoom3D = null
var _cam: Camera3D = null
var _out_dir := ""


func _ready() -> void:
	var want := OS.get_environment("SS2_ROOM")
	if want.is_empty():
		want = "room_08"
	_out_dir = "%s/%s" % [OUT_ROOT, want]
	var scene := load(EXPEDITION_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = false
	_tower = tower
	add_child(tower)

	var waited := 0.0
	while waited < WAIT_LIMIT_S:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not (tower.get("_records") as Array).is_empty():
			for _i in range(6):
				await get_tree().process_frame
			break

	for node in tower.find_children("*", "", true, false):
		if node is DungeonRoom3D and str((node as DungeonRoom3D).room_id) == want:
			_room = node as DungeonRoom3D
			break
	if _room == null:
		print("找不到房间 %s" % want)
		get_tree().quit(1)
		return

	if DisplayServer.get_name() == "headless":
		print("headless 出不了图，请带窗口运行")
		get_tree().quit(2)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	_hide_ui(tower)
	_release_cameras(tower)
	# 用房间自己的顶灯照（作者美术的正式光），探针只补一点填充光，
	# 否则夜景里素材全是黑剪影、或者被补光压成一片平灰。
	if _room.has_method("set_room_light_on"):
		_room.call("set_room_light_on", true)

	var dims := _room.get_dimensions()
	var center := _room.global_position
	print("")
	print("=== 拍照 %s  世界=(%.2f, %.2f, %.2f)  尺寸=%.1f x %.1f ===" % [
		want, center.x, center.y, center.z, dims.x, dims.y,
	])

	# 00 俯视：镜头在**室内** 8.0 m（再高会被顶板挡住），朝下看平面。
	var overhead := center + Vector3(0.0, 8.0, 0.0)
	var cam := _ensure_cam()
	cam.global_position = overhead
	cam.look_at(center + Vector3(0.0, 0.0, -0.001), Vector3(0.0, 0.0, -1.0))
	cam.fov = 78.0
	await _shoot("00_overhead")
	_print_ray_report()

	# 00b 角落斜视：站在西南角内侧 3m、高 2.2m，朝东北角看 —— 一眼看完四面墙与地板接缝。
	var corner := center + Vector3(-dims.x * 0.5 + 3.0, 2.2, dims.y * 0.5 - 3.0)
	cam.global_position = corner
	cam.fov = 70.0
	cam.look_at(center + Vector3(dims.x * 0.25, 0.0, -dims.y * 0.25), Vector3.UP)
	await _shoot("00b_corner")

	# 01..04 房心平视
	var eye := center + Vector3(0.0, EYE_Y, 0.0)
	var dirs := {
		"01_north": Vector3(0.0, 0.0, -1.0),
		"02_east": Vector3(1.0, 0.0, 0.0),
		"03_south": Vector3(0.0, 0.0, 1.0),
		"04_west": Vector3(-1.0, 0.0, 0.0),
	}
	for key in dirs:
		cam.fov = 63.0
		cam.global_position = eye
		cam.look_at(eye + (dirs[key] as Vector3) * 10.0, Vector3.UP)
		await _shoot(str(key))

	# 05 从主路门内侧朝房心
	var doors_value: Variant = _room.get("_door_nodes")
	if doors_value is Dictionary and not (doors_value as Dictionary).is_empty():
		var keys: Array = (doors_value as Dictionary).keys()
		keys.sort()
		var door := (doors_value as Dictionary)[keys[0]] as Node3D
		if door != null and is_instance_valid(door):
			var inward := Vector3(center.x - door.global_position.x, 0.0, center.z - door.global_position.z)
			if inward.length_squared() > 0.01:
				inward = inward.normalized()
			var door_eye := door.global_position + inward * 2.0
			door_eye.y = door.global_position.y + EYE_Y
			cam.fov = 43.0
			cam.global_position = door_eye
			cam.look_at(Vector3(center.x, door_eye.y, center.z), Vector3.UP)
			await _shoot("05_door_in_%s" % str(keys[0]))

	# 06 正交平面图：把高于 3.2m 的件全部藏掉（顶板/吊管/灯），正上方正交俯视。
	# 这是唯一能一眼看出「墙是不是压在房间里、家具是不是摆到墙外」的拍法。
	await _shoot_plan(dims, center)

	# 07 只看墙：除了墙和地砖一律藏掉，墙改**无光照**纯红材质。
	# 夜景里靠灯补出来的平面图明暗关系全糊，改成 unshaded 材质就与光照无关了，
	# 墙圈合不合、哪一面错位一眼就能看出来。
	await _shoot_walls_only(dims, center)

	# 08 邻房全景：把本房与所有邻房一起拍进来，只留墙。
	# 「一边墙错位」往往不是本房自己的墙歪了，而是**本房的墙与邻房的墙接不上**
	# —— 只看本房永远看不出来，必须把两边摆在同一张图上。
	await _shoot_neighbourhood(tower, dims, center)

	# 09 三维斜俯视只看墙：平面图看不出「墙立在哪、有没有错位」，斜视才能看到
	# 墙板的前后关系与转角接缝。无光照材质 + 黑底，与夜景光照彻底脱钩。
	await _shoot_walls_oblique(dims, center)

	print("ROOM_SHOT_END")
	get_tree().quit(0)


func _shoot(label: String) -> void:
	_sync_fill_light()
	for _i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("  [失败] %s" % label)
		return
	var path := "%s/%s.png" % [_out_dir, label]
	img.save_png(path)
	print("  [拍照] %s" % path)


## 诊断用补光：跟着相机走的平行光（不投影、不改游戏里的任何灯）。
## 塔内是夜间环境光，不补光拍出来全是黑剪影；但补过头会把明暗关系压平，0.85 是实测折中。
var _fill: DirectionalLight3D = null


func _sync_fill_light() -> void:
	if _fill == null or not is_instance_valid(_fill):
		_fill = DirectionalLight3D.new()
		_fill.name = "ProbeFillLight"
		_fill.light_energy = 0.35
		_fill.shadow_enabled = true
		_fill.light_color = Color(1.0, 0.96, 0.90)
		add_child(_fill)
	if _cam == null:
		return
	# 平行光方向 = 相机的朝向再向下压 25°，模拟「手电筒 + 环境补光」。
	var forward := -_cam.global_transform.basis.z
	var down := (forward + Vector3(0.0, -0.45, 0.0)).normalized()
	if down.length_squared() > 0.001:
		var up := Vector3.UP
		if absf(down.dot(up)) > 0.98:
			up = Vector3.BACK
		_fill.global_transform = Transform3D(
			Basis.looking_at(down, up), _cam.global_position
		)


## 房心 1.5 m 高、16 个方向打射线：打印每一面墙离房心多远。
## 这是判断「墙是不是插进房间里」的数字口径 —— 45×40 的房间，正东正西应 ≈22.5m。
func _print_ray_report() -> void:
	var space := get_viewport().world_3d.direct_space_state
	var center := _room.global_position + Vector3(0.0, 1.5, 0.0)
	print("")
	print("── 房心 8 向墙距（1.5m 高，命中即停）──")
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var query := PhysicsRayQueryParameters3D.create(center, center + dir * 60.0)
		query.collide_with_areas = false
		var hit: Dictionary = space.intersect_ray(query)
		var dist := -1.0
		var who := "<无>"
		if not hit.is_empty():
			dist = center.distance_to(hit.get("position", center))
			var collider := hit.get("collider") as Node
			who = str(collider.name) if collider != null else "<无 collider>"
		print("  %+6.1f°  (%.2f, %.2f)  距离=%6.2fm  ← %s" % [
			rad_to_deg(-angle), dir.x, dir.z, dist, who,
		])


## 正上方正交俯视，先把高于 3.2m 的件（顶板 / 吊管 / 灯）藏掉。
func _shoot_plan(dims: Vector2, center: Vector3) -> void:
	var hidden: Array[Node3D] = []
	for node in _room.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var top := mesh.global_position.y + mesh.mesh.get_aabb().end.y * mesh.global_transform.basis.get_scale().y
		if top > center.y + 3.2:
			mesh.visible = false
			hidden.append(mesh)
	var cam := _ensure_cam()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = _ortho_size_for(dims.x, dims.y, 2.0)
	cam.global_position = center + Vector3(0.0, 40.0, 0.0)
	cam.look_at(center, Vector3(0.0, 0.0, -1.0))
	await _shoot("06_plan_ortho")
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	for mesh in hidden:
		if is_instance_valid(mesh):
			mesh.visible = true


## 只看墙的正交平面图：除墙件与地砖外全部隐藏，墙件换 unshaded 纯白材质。
## 为什么必须 unshaded：塔内是夜间光，靠补光拍出来的平面图明暗全糊在一起；
## 无光照材质与光照无关，墙圈合不合、哪一面错位一眼可见。
func _shoot_walls_only(dims: Vector2, center: Vector3) -> void:
	var wall_mat := StandardMaterial3D.new()
	wall_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall_mat.albedo_color = Color(1.0, 0.28, 0.24)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mat.albedo_color = Color(0.22, 0.26, 0.32)
	var door_mat := StandardMaterial3D.new()
	door_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	door_mat.albedo_color = Color(1.0, 0.85, 0.20)

	var saved: Array[Dictionary] = []
	for node in _room.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var upper := _piece_root_name(mesh).to_upper()
		var is_wall := upper.contains("WALL")
		var is_floor := upper.contains("TILE") or upper.contains("FLOOR")
		var is_door := upper.contains("DOOR")
		saved.append({
			"mesh": mesh,
			"visible": mesh.visible,
			"override": mesh.material_override,
		})
		mesh.visible = is_wall or is_floor or is_door
		if is_wall:
			mesh.material_override = wall_mat
		elif is_floor:
			mesh.material_override = floor_mat
		elif is_door:
			mesh.material_override = door_mat

	# 房间外的塔楼地板 / 顶板会把画面填成一片灰，看不出墙圈。清屏色压黑 + 只拍房间范围。
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.03))
	var cam := _ensure_cam()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = _ortho_size_for(dims.x, dims.y, 3.0)
	cam.global_position = center + Vector3(0.0, 40.0, 0.0)
	cam.look_at(center, Vector3(0.0, 0.0, -1.0))
	await _shoot("07_walls_only")
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	RenderingServer.set_default_clear_color(Color(0.0, 0.0, 0.0))
	for entry in saved:
		var mesh := entry["mesh"] as MeshInstance3D
		if mesh != null and is_instance_valid(mesh):
			mesh.visible = bool(entry["visible"])
			mesh.material_override = entry["override"] as Material


## 一件美术件的名字：往上走到「父节点是房间或其直接子容器」为止。
func _piece_root_name(mesh: Node) -> String:
	var cursor: Node = mesh
	while true:
		var parent := cursor.get_parent()
		if parent == null or parent == _room:
			return str(cursor.name)
		if parent.get_parent() == _room or parent.get_parent() == null:
			return str(cursor.name)
		cursor = parent
	return str(mesh.name)


## 邻房全景：本房 + 所有相邻房间一起俯视，只留墙与地砖。
## 判据是「本房的墙和邻房的墙在共享边上接不接得上」，单看一间房看不出来。
func _shoot_neighbourhood(tower: Node, dims: Vector2, center: Vector3) -> void:
	var rooms: Array[DungeonRoom3D] = []
	var reach := maxf(dims.x, dims.y) * 0.5 + 30.0
	for node in tower.find_children("*", "", true, false):
		var room := node as DungeonRoom3D
		if room == null:
			continue
		var flat := Vector2(room.global_position.x - center.x, room.global_position.z - center.z).length()
		if flat <= reach:
			rooms.append(room)
	if rooms.size() <= 1:
		return

	var wall_mat := StandardMaterial3D.new()
	wall_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall_mat.albedo_color = Color(0.98, 0.25, 0.22)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mat.albedo_color = Color(0.20, 0.24, 0.30)

	var saved: Array[Dictionary] = []
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for room in rooms:
		var size := room.get_dimensions()
		min_x = minf(min_x, room.global_position.x - size.x * 0.5)
		max_x = maxf(max_x, room.global_position.x + size.x * 0.5)
		min_z = minf(min_z, room.global_position.z - size.y * 0.5)
		max_z = maxf(max_z, room.global_position.z + size.y * 0.5)
		for node in room.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh == null or mesh.mesh == null:
				continue
			var upper := _piece_root_name(mesh).to_upper()
			var is_wall := upper.contains("WALL")
			var is_floor := upper.contains("TILE") or upper.contains("FLOOR")
			saved.append({"mesh": mesh, "visible": mesh.visible, "override": mesh.material_override})
			mesh.visible = is_wall or is_floor
			if is_wall:
				mesh.material_override = wall_mat
			elif is_floor:
				mesh.material_override = floor_mat

	var pivot := Vector3((min_x + max_x) * 0.5, center.y, (min_z + max_z) * 0.5)
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.03))
	var cam := _ensure_cam()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = _ortho_size_for(max_x - min_x, max_z - min_z, 4.0)
	cam.global_position = pivot + Vector3(0.0, 45.0, 0.0)
	cam.look_at(pivot, Vector3(0.0, 0.0, -1.0))
	print("")
	print("  邻房全景：%d 间房，覆盖 x %.1f~%.1f  z %.1f~%.1f" % [
		rooms.size(), min_x, max_x, min_z, max_z,
	])
	for room in rooms:
		print("    %-14s 中心=(%7.1f,%7.1f) 尺寸=%.0fx%.0f 门=%s" % [
			str(room.room_id), room.global_position.x, room.global_position.z,
			room.get_dimensions().x, room.get_dimensions().y, str(room.doors),
		])
	await _shoot("08_neighbours")
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	RenderingServer.set_default_clear_color(Color(0.0, 0.0, 0.0))
	for entry in saved:
		var mesh := entry["mesh"] as MeshInstance3D
		if mesh != null and is_instance_valid(mesh):
			mesh.visible = bool(entry["visible"])
			mesh.material_override = entry["override"] as Material


## 三维斜俯视只看墙：从房间西南上方看进来，墙用无光照红色、地砖深灰、其余全藏。
## 俯视图会把「墙立偏了 0.5 m」压成一个像素；斜视才看得出墙板之间有没有错台。
func _shoot_walls_oblique(dims: Vector2, center: Vector3) -> void:
	var wall_mat := StandardMaterial3D.new()
	wall_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall_mat.albedo_color = Color(0.98, 0.28, 0.24)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mat.albedo_color = Color(0.26, 0.30, 0.36)

	var saved: Array[Dictionary] = []
	for node in _room.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var upper := _piece_root_name(mesh).to_upper()
		var is_wall := upper.contains("WALL")
		var is_floor := upper.contains("TILE") or upper.contains("FLOOR")
		saved.append({"mesh": mesh, "visible": mesh.visible, "override": mesh.material_override})
		mesh.visible = is_wall or is_floor
		if is_wall:
			mesh.material_override = wall_mat
		elif is_floor:
			mesh.material_override = floor_mat

	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.03))
	var cam := _ensure_cam()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 55.0
	cam.global_position = center + Vector3(-dims.x * 0.62, maxf(dims.x, dims.y) * 0.75, dims.y * 0.62)
	cam.look_at(center + Vector3(0.0, 1.5, 0.0), Vector3.UP)
	await _shoot("09_walls_oblique")
	RenderingServer.set_default_clear_color(Color(0.0, 0.0, 0.0))
	for entry in saved:
		var mesh := entry["mesh"] as MeshInstance3D
		if mesh != null and is_instance_valid(mesh):
			mesh.visible = bool(entry["visible"])
			mesh.material_override = entry["override"] as Material


## 正交相机要覆盖 width_m × depth_m 的平面，正确的 `size` 是**纵向**跨度。
##
## ⚠️ 这一条踩过坑：`Camera3D.size` 在正交模式下是**垂直**可视高度，水平方向 = size × 宽高比。
## 早先写成 `max(宽, 深) + 6`，在 16:9 下纵向只覆盖约 (max+6)×9/16 —— 40 m 深的房间
## 只看到 28 m，南北两面墙被裁在画面外，看图会误判成「墙缺了 / 墙错位」。
## 正确做法：先按纵向需求定 size，再检查横向够不够（不够就按横向反算）。
func _ortho_size_for(width_m: float, depth_m: float, margin_m: float = 3.0) -> float:
	var aspect := 16.0 / 9.0
	var viewport := get_viewport().get_visible_rect().size
	if viewport.y > 1.0:
		aspect = viewport.x / viewport.y
	var need_for_depth := depth_m + margin_m * 2.0
	var need_for_width := (width_m + margin_m * 2.0) / aspect
	return maxf(need_for_depth, need_for_width)


func _ensure_cam() -> Camera3D:
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.near = 0.05
		_cam.far = 800.0
		add_child(_cam)
	_cam.current = true
	return _cam


func _hide_ui(root: Node) -> void:
	for node in root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	for node in root.find_children("*", "Control", true, false):
		(node as Control).visible = false


func _release_cameras(root: Node) -> void:
	for node in root.find_children("*", "Camera3D", true, false):
		(node as Camera3D).current = false
