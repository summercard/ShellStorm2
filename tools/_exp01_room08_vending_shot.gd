extends Node
## 把 room_08 中庭的局内贩卖机拍下来（真实渲染器）。业主验收用。
##
## 用法：SS2_SHOT_DIR=<绝对目录> godot --path . res://tools/_exp01_room08_vending_shot.tscn

const SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"

var _tower: TowerDescent3D = null
var _room: DungeonRoom3D = null
var _cam: Camera3D = null
var _out := ""


func _ready() -> void:
	_out = OS.get_environment("SS2_SHOT_DIR")
	if _out.is_empty():
		_out = ProjectSettings.globalize_path("res://outputs/room_shot/vending")
	_tower = (load(SCENE) as PackedScene).instantiate() as TowerDescent3D
	_tower.test_mode = false
	add_child(_tower)
	var waited := 0.0
	while waited < 60.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not (_tower.get("_records") as Array).is_empty():
			break
	for _i in range(6):
		await get_tree().process_frame
	for node in _tower.find_children("*", "", true, false):
		if node is DungeonRoom3D and str((node as DungeonRoom3D).room_id) == "room_08":
			_room = node as DungeonRoom3D
			break
	if _room == null:
		print("SHOT room_missing")
		get_tree().quit(1)
		return
	_room.ensure_shell_built()
	_room.ensure_detail_built()
	# 买家必须看得见：房间灯打开（作者灯默认是关的）。
	if _room.has_method("set_room_light_on"):
		_room.call("set_room_light_on", true)
	await get_tree().process_frame
	await get_tree().physics_frame

	var station := _room.get_service_station("merchant")
	if station == null:
		print("SHOT station_missing")
		get_tree().quit(1)
		return
	print("SHOT station=%s world=%s" % [station.name, str(station.global_position)])
	# 玩家搬到机器正前方：`PlayerVision3D` 按「玩家能否看见」剔除 service_station_3d 组，
	# 玩家还留在入口房时机器必然 visible=false。要拍「玩家看到的画面」就得站过去。
	var player := _tower.get("player") as Player3D
	var pfront := station.global_transform.basis.z
	pfront.y = 0.0
	pfront = pfront.normalized()
	if player != null:
		player.global_position = station.global_position + pfront * 3.4 + Vector3(0.0, 0.05, 0.0)
		player.look_at(Vector3(station.global_position.x, player.global_position.y, station.global_position.z), Vector3.UP)
		for _i in range(6):
			await get_tree().process_frame
			await get_tree().physics_frame
		print("  玩家站位=%s 机器 visible=%s visible_in_tree=%s" % [
			str(player.global_position), str(station.visible), str(station.is_visible_in_tree()),
		])
	DirAccess.make_dir_recursive_absolute(_out)
	_hide_ui()
	_release_cameras()

	var basis := station.global_transform.basis
	var front := basis.z
	front.y = 0.0
	front = front.normalized()
	var right := basis.x
	right.y = 0.0
	right = right.normalized()
	var target := station.global_position + Vector3(0.0, 1.5, 0.0)

	var cam := _ensure_cam()
	cam.fov = 55.0
	# ① 正面 6.5m，视线高度 1.7m —— 玩家走近时看到的样子
	# 站位不能拍脑袋：机器可能贴在中庭里，退 8m 就进墙了。
	# 沿正面打一条射线，退到「最近的墙往里 1.2m」为止。
	cam.global_position = target + front * _safe_back_off(target, front) + Vector3(0.0, 0.35, 0.0)
	cam.look_at(target, Vector3.UP)
	print("  front 相机=%s 机器=%s 朝向basis.z=%s front=%s 在视锥内=%s" % [
		str(cam.global_position), str(target), str(basis.z), str(front),
		str(cam.is_position_in_frustum(target)),
	])
	# 视觉包络:机器到底有多大、在不在
	# 谁把它藏了：逐级打印 visible / stream 状态
	var cursor: Node = station
	while cursor != null:
		if cursor is Node3D:
			print("    chain %s(%s) visible=%s" % [cursor.name, cursor.get_class(), str((cursor as Node3D).visible)])
		if cursor == _room:
			break
		cursor = cursor.get_parent()
	print("    room stream=%s detail_built=%s" % [
		_room.get_stream_state_name(), str(_room.get("_detail_built")),
	])
	var vis := station.get_node_or_null("Visual") as Node3D
	if vis != null:
		var box := AABB()
		var first := true
		for n in vis.find_children("*", "MeshInstance3D", true, false):
			var m := n as MeshInstance3D
			if m == null or m.mesh == null:
				continue
			var a: AABB = m.get_aabb()
			var w: AABB = m.global_transform * a
			box = w if first else box.merge(w)
			first = false
			print("    mesh %s visible_in_tree=%s aabb_world=%s" % [m.name, str(m.is_visible_in_tree()), str(w)])
		print("  Visual 包络=%s" % str(box))
	# 八向射线：机器四周多空
	var space := get_viewport().world_3d.direct_space_state
	print("  八向墙距（从机器中心 1.2m 高）:")
	for i in range(8):
		var ang := TAU * float(i) / 8.0
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var from := station.global_position + Vector3(0.0, 1.2, 0.0)
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 40.0)
		q.collide_with_areas = false
		var hit := space.intersect_ray(q)
		var who := "<空>"
		var distv := -1.0
		if not hit.is_empty():
			distv = from.distance_to(hit.get("position", from))
			who = str((hit.get("collider") as Node).name) if hit.get("collider") != null else "?"
		print("    %5.1f° dist=%.2f <- %s" % [rad_to_deg(ang), distv, who])
	await _shoot("10_vending_front")
	# ② 斜前 45°：同时看到机器侧面体积与它在中庭里的关系
	var back := _safe_back_off(target, front) * 0.85
	cam.global_position = target + front * back + right * minf(3.4, back * 0.55) + Vector3(0.0, 1.5, 0.0)
	cam.look_at(target, Vector3.UP)
	await _shoot("11_vending_oblique")
	# ③ 从入口门方向看进来：验证「走进中庭就正对机器」
	var door := (_room.get("_door_nodes") as Dictionary).get("north") as Node3D
	if door != null:
		var inward := _room.global_position - door.global_position
		inward.y = 0.0
		var eye := door.global_position + inward.normalized() * 2.5
		eye.y = 1.7
		cam.global_position = eye
		cam.fov = 60.0
		cam.look_at(Vector3(target.x, 1.4, target.z), Vector3.UP)
		await _shoot("12_vending_from_door")
	# ④ 俯视整间房（压掉 3.2m 以上的吊管/灯），看机器在中庭里的位置
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 52.0
	cam.global_position = _room.global_position + Vector3(0.0, 30.0, 0.0)
	cam.look_at(_room.global_position, Vector3(0.0, 0.0, -1.0))
	await _shoot("13_vending_plan")
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	print("SHOT_END %s" % _out)
	get_tree().quit(0)


## 沿 `dir` 从 `target` 往外退，最多 `limit` 米，遇墙提前停（再往里收 1.2m）。
func _safe_back_off(target: Vector3, dir: Vector3, limit := 8.0) -> float:
	var space := get_viewport().world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(target, target + dir * (limit + 2.0))
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return limit
	var dist := target.distance_to(hit.get("position", target))
	print("  前方 %.1f m 有墙，退到 %.1f m" % [dist, maxf(2.2, dist - 1.2)])
	return clampf(dist - 1.2, 2.2, limit)


func _shoot(label: String) -> void:
	for _i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("  [失败] %s" % label)
		return
	var path := "%s/%s.png" % [_out, label]
	img.save_png(path)
	print("  [拍照] %s" % path)


func _ensure_cam() -> Camera3D:
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.near = 0.05
		_cam.far = 800.0
		add_child(_cam)
	_cam.current = true
	return _cam


func _hide_ui() -> void:
	for node in _tower.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	for node in _tower.find_children("*", "Control", true, false):
		(node as Control).visible = false


func _release_cameras() -> void:
	for node in _tower.find_children("*", "Camera3D", true, false):
		(node as Camera3D).current = false
