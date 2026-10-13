extends Node
## 只读出图 + 射线诊断：塔楼 98F「楼梯入口大厅」的**玩家原生第三人称**视角。
##
## 用途：主人实机截图里画面下半部有一条横向带子，怀疑是"不该有的墙"。
##       本探针**不动玩家相机的俯仰**（保持场景默认的第三人称俯视机位），
##       只把玩家摆到房间里、转四个朝向各拍一张，用来和主人截图逐张比对；
##       同时对画面上下左右多个方向打射线，把"看起来像墙的东西"落到具体 asset_id 上。
##
## ⚠️ 朝向换算（踩过的坑）：本项目玩家 root 的 rotation.y=0 是**朝北（-Z）**，
##    不是朝 +X。所以朝东要 rotation.y = -90°，朝西是 +90°，朝南是 180°。
##
## 跑法（**必须带窗口**，headless 不渲染）：
##   "<godot_console>" --path "<project>" --scene res://tests/verification/probe_stair_lobby_pov.tscn

const OUT_DIR := "user://stair_lobby_pov2"
const ROOM_ID := "floor_01_entry"


func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	for i in 8:
		await get_tree().process_frame
		await get_tree().physics_frame
	tower.generate_through_floor_for_test(95)
	for i in 8:
		await get_tree().process_frame
		await get_tree().physics_frame

	var room_by_id: Dictionary = tower.get("_room_by_id")
	var room := room_by_id.get(ROOM_ID) as DungeonRoom3D
	if room == null:
		printerr("[pov] 没找到 %s" % ROOM_ID)
		get_tree().quit(1)
		return
	room.ensure_shell_built()
	for i in 8:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.8).timeout

	var player := tower.get("player") as Player3D
	if player == null:
		printerr("[pov] 拿不到 player")
		get_tree().quit(2)
		return
	var cam := player.camera
	if cam == null:
		printerr("[pov] 玩家没有 camera")
		get_tree().quit(3)
		return

	var center := room.global_position
	var dims := room.get_dimensions()
	print("[pov] 房间 %s center=%s dims=%s" % [room.room_id, str(center), str(dims)])
	print("[pov] 房内 x∈[%.1f,%.1f]  z∈[%.1f,%.1f]（z 小=北）  地面y=%.2f  天花板y=%.2f" % [
		center.x - dims.x * 0.5, center.x + dims.x * 0.5,
		center.z - dims.y * 0.5, center.z + dims.y * 0.5,
		center.y, center.y + TowerGeometry3D.WALL_VISUAL_HEIGHT_M])

	# 站位：房间中心偏西偏南一点，模拟"站在房里看四周"
	var stand := Vector3(center.x - 1.5, center.y + 0.05, center.z + 1.0)
	player.global_position = stand
	print("[pov] 玩家站位=%s（房间中心偏西偏南）" % str(stand))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# ⚠️ 不改 cam.rotation：保持场景默认第三人称俯视机位，才能和主人截图同机位比对
	var yaws: Array = [
		["yaw000_朝北-Z", 0.0],
		["yaw090_朝西-X", 90.0],
		["yaw180_朝南+Z", 180.0],
		["yaw270_朝东+X", 270.0],
	]
	for item in yaws:
		var tag := str(item[0])
		player.rotation.y = deg_to_rad(float(item[1]))
		for i in range(14):
			await get_tree().process_frame
		var ct := cam.global_transform
		print("[pov] %s 相机 gpos=(%.2f,%.2f,%.2f) 俯角=%.1f°" % [
			tag, ct.origin.x, ct.origin.y, ct.origin.z,
			rad_to_deg(asin(clampf(-ct.basis.z.y, -1.0, 1.0)))])
		var img: Image = get_viewport().get_texture().get_image()
		if img != null:
			var out := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, tag])
			img.save_png(out)
			print("[pov]   出图 -> %s" % out)
		print("[pov]   ---- 射线诊断 ----")
		_probe_rays(cam)

	print("STAIR_LOBBY_POV_DONE")
	get_tree().quit(0)


func _probe_rays(cam: Camera3D) -> void:
	var space := cam.get_world_3d().direct_space_state
	var origin := cam.global_position
	var basis := cam.global_transform.basis
	var fwd := -basis.z
	var up := basis.y
	var right := basis.x
	var cases: Array = [
		["正前", fwd],
		["上20", (fwd + up * 0.36).normalized()],
		["下12", (fwd - up * 0.21).normalized()],
		["下22", (fwd - up * 0.40).normalized()],
		["下32", (fwd - up * 0.62).normalized()],
		["左下", (fwd - right * 0.5 - up * 0.35).normalized()],
		["右下", (fwd + right * 0.5 - up * 0.35).normalized()],
		["左25", (fwd - right * 0.47).normalized()],
		["右25", (fwd + right * 0.47).normalized()],
	]
	for c in cases:
		var label := str(c[0])
		var dir := c[1] as Vector3
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 60.0)
		q.collide_with_areas = true
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			print("      %-5s -> <无命中>" % label)
			continue
		var co := hit["collider"] as Node
		var pos := hit["position"] as Vector3
		var aid := ""
		var cur := co
		while cur != null:
			if not str(cur.get_meta("asset_id", "")).is_empty():
				aid = str(cur.get_meta("asset_id", ""))
				break
			cur = cur.get_parent()
		print("      %-5s d=%5.2fm %-30s pos=(%7.2f,%6.2f,%7.2f) L%d aid=%s" % [
			label, origin.distance_to(pos),
			String(co.name) if co != null else "<?>",
			pos.x, pos.y, pos.z,
			(co as CollisionObject3D).collision_layer if co is CollisionObject3D else -1,
			aid if not aid.is_empty() else "-"])
