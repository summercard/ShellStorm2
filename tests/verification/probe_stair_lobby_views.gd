extends Node
## 只读出图：塔楼 98F「楼梯入口大厅」(STAIR_LOBBY) 房内四个朝向的第一人称视角。
##
## 用途：主人在实机里看到画面下半部有一条横向的带子/凸块，问"这儿是不是有堵不该有的墙"。
##       本探针站到房间中心，按 东/南/西/北 四个朝向各拍一张，用来和主人截图逐张比对。
##
## 跑法（**必须带窗口，不能 --headless**：headless 下不渲染）：
##   "<godot_console>" --path "<project>" --scene res://tests/verification/probe_stair_lobby_views.tscn
## 输出：user:// 下 4 张 PNG，探针自己打印绝对路径。

const OUT_DIR := "user://stair_lobby_views"
const EYE_HEIGHT := 1.70
const FOV := 70.0


func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	tower.generate_through_floor_for_test(95)
	await get_tree().process_frame
	await get_tree().physics_frame

	var room_by_id: Dictionary = tower.get("_room_by_id")
	var target: DungeonRoom3D = null
	for key_value in room_by_id.keys():
		var room := room_by_id.get(key_value) as DungeonRoom3D
		if room == null or room.room_type != "STAIR_LOBBY":
			continue
		var fi := int(round(-room.global_position.y / TowerGeometry3D.FLOOR_HEIGHT_M))
		if fi == 2:
			target = room
	if target == null:
		printerr("[views] 没找到 98F STAIR_LOBBY")
		get_tree().quit(1)
		return
	target.ensure_shell_built()
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.6).timeout

	var center := target.global_position
	var eye_y := center.y + EYE_HEIGHT
	print("[views] 房间 %s 中心=%s 眼高=%.2f" % [target.room_id, str(center), eye_y])

	# 把玩家挪到房间中心并压住朝向，避免它挡镜头 / 触发流送
	var player := tower.get("player") as Node3D
	if player != null:
		player.global_position = Vector3(center.x, center.y + 0.05, center.z)
		print("[views] 玩家已挪到房间中心")

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var cam := Camera3D.new()
	cam.fov = FOV
	cam.near = 0.05
	cam.far = 400.0
	add_child(cam)

	# 朝向 → 世界方向向量（Godot 里 -Z 是镜头默认前方）
	var dirs: Array = [
		["north_-Z", Vector3(0, 0, -1)],
		["east_+X", Vector3(1, 0, 0)],
		["south_+Z", Vector3(0, 0, 1)],
		["west_-X", Vector3(-1, 0, 0)],
	]
	for item in dirs:
		var tag := str(item[0])
		var dir := item[1] as Vector3
		cam.global_position = Vector3(center.x, eye_y, center.z)
		cam.look_at(cam.global_position + dir, Vector3.UP)
		cam.make_current()
		for i in range(10):
			await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		if img == null:
			printerr("[views] %s 取图失败" % tag)
			continue
		var out := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, tag])
		var err := img.save_png(out)
		print("[views] %-10s -> %s (err=%d)" % [tag, out, err])
		# 打印该朝向上最近的几件几何，便于对照
		_dump_ahead(target, cam.global_position, dir)

	print("STAIR_LOBBY_VIEWS_DONE")
	get_tree().quit(0)


## 把该朝向上、水平距离 0.8~14m 内、且投影落在视野中央 70% 的件列出来
func _dump_ahead(room: DungeonRoom3D, eye: Vector3, dir: Vector3) -> void:
	var right := dir.cross(Vector3.UP).normalized()
	var rows: Array = []
	for mv in room.find_children("*", "MeshInstance3D", true, false):
		var mi := mv as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var ab := _world_aabb(mi)
		if ab.size.x < 0.8 and ab.size.z < 0.8:
			continue
		var c := ab.get_center()
		var to := Vector3(c.x - eye.x, 0.0, c.z - eye.z)
		var fwd := to.dot(dir)
		if fwd < 0.5 or fwd > 16.0:
			continue
		var lateral := absf(to.dot(right))
		var half_w := maxf(ab.size.x, ab.size.z) * 0.5
		if lateral - half_w > fwd * 1.2:
			continue
		rows.append([fwd, String(mi.name), c, ab.size])
	rows.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for r in rows:
		print("      d=%5.1fm %-38s c=(%7.2f,%6.2f,%7.2f) size=(%5.2f,%5.2f,%5.2f)" % [
			float(r[0]), String(r[1]),
			(r[2] as Vector3).x, (r[2] as Vector3).y, (r[2] as Vector3).z,
			(r[3] as Vector3).x, (r[3] as Vector3).y, (r[3] as Vector3).z])


func _world_aabb(mi: MeshInstance3D) -> AABB:
	var a := mi.get_aabb()
	var xf := mi.global_transform
	var p := a.position
	var s := a.size
	var mn := xf * p
	var mx := mn
	for i in range(8):
		var c := p + Vector3(
			s.x if (i & 1) else 0.0,
			s.y if (i & 2) else 0.0,
			s.z if (i & 4) else 0.0)
		var wp := xf * c
		mn = Vector3(minf(mn.x, wp.x), minf(mn.y, wp.y), minf(mn.z, wp.z))
		mx = Vector3(maxf(mx.x, wp.x), maxf(mx.y, wp.y), maxf(mx.z, wp.z))
	return AABB(mn, mx - mn)
