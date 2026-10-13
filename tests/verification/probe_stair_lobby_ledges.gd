extends Node
## 只读探查：塔楼 98F「楼梯入口大厅」里有没有**不该存在的水平台面 / 矮墙**。
##
## 用途：主人实机截图里画面下半部有一条横向的带子，问"这儿是不是有堵不该有的墙"。
##       本探针站到房间中心、按眼高向上/水平/向下打**密集射线网格**，
##       把命中的**水平面（法线朝上）**且高度在 0.15~3.5m 的命中点聚合成"台面"，
##       直接报出是哪个 asset_id、尺寸多大、离墙多远。
##       这类"半空中的水平带子"绝不会是地面，也不是四面墙，只能是多出来的件。
##
## 跑法：
##   "<godot_console>" --headless --path "<project>" --scene res://tests/verification/probe_stair_lobby_ledges.tscn

const ROOM_ID := "floor_01_entry"
const EYE := 1.70


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
		printerr("[ledges] 没找到 %s" % ROOM_ID)
		get_tree().quit(1)
		return
	room.ensure_shell_built()
	for i in 8:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.5).timeout

	var center := room.global_position
	var dims := room.get_dimensions()
	var half_x := dims.x * 0.5
	var half_z := dims.y * 0.5
	print("[ledges] 房间 %s center=%s dims=%s 眼高=%.2f" % [
		room.room_id, str(center), str(dims), EYE])
	print("[ledges] 房内 x∈[%.1f,%.1f] z∈[%.1f,%.1f] 地面y=%.2f" % [
		center.x - half_x, center.x + half_x, center.z - half_z, center.z + half_z, center.y])

	var space := room.get_world_3d().direct_space_state
	var origin := Vector3(center.x, center.y + EYE, center.z)

	# 水平面命中表：位置量化到 0.25m，同时记 aid
	var surfaces: Dictionary = {}
	var scans := 0
	# 以房间中心为原点，按方位角 5° 一档、俯角 -50°~+10° 每 2° 一档，打完全球下半部
	var az := 0.0
	while az < 360.0:
		var pitch := 10.0
		while pitch >= -50.0:
			scans += 1
			var ar := deg_to_rad(az)
			var pr := deg_to_rad(pitch)
			var dir := Vector3(cos(pr) * sin(ar), sin(pr), -cos(pr) * cos(ar))
			var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 60.0)
			q.collide_with_areas = true
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var n := hit.get("normal", Vector3.ZERO) as Vector3
				var pos := hit["position"] as Vector3
				var above := pos.y - center.y
				# 水平面（法线朝上明显）+ 高度 0.15~3.5m ⇒ 可疑台面
				if n.y > 0.82 and above > 0.15 and above < 3.5:
					var co := hit["collider"] as Node
					var aid := ""
					var cur := co
					var owner_name := ""
					while cur != null:
						if owner_name.is_empty():
							owner_name = String(cur.name)
						if not str(cur.get_meta("asset_id", "")).is_empty():
							aid = str(cur.get_meta("asset_id", ""))
							break
						cur = cur.get_parent()
					var key := "%s|%.2f" % [owner_name, snappedf(above, 0.25)]
					if not surfaces.has(key):
						surfaces[key] = {
							"aid": aid, "above": above, "name": owner_name,
							"n": 0, "xmin": pos.x, "xmax": pos.x,
							"zmin": pos.z, "zmax": pos.z,
						}
					var rec: Dictionary = surfaces[key]
					rec["n"] = int(rec["n"]) + 1
					rec["xmin"] = minf(float(rec["xmin"]), pos.x)
					rec["xmax"] = maxf(float(rec["xmax"]), pos.x)
					rec["zmin"] = minf(float(rec["zmin"]), pos.z)
					rec["zmax"] = maxf(float(rec["zmax"]), pos.z)
			pitch -= 2.0
		az += 5.0
	print("[ledges] 扫描射线 %d 条" % scans)

	print()
	print("=== 房间内「半空水平台面」(法线朝上 + 高度 0.15~3.5m) ===")
	var rows: Array = []
	for v in surfaces.values():
		rows.append(v)
	rows.sort_custom(func(a, b): return int(b["n"]) > int(a["n"]))
	for r in rows:
		var xmin := float(r["xmin"]); var xmax := float(r["xmax"])
		var zmin := float(r["zmin"]); var zmax := float(r["zmax"])
		print("  %-30s aid=%-34s 高度=%5.2fm 命中=%3d 覆盖 x[%6.2f,%6.2f](%.1f) z[%6.2f,%6.2f](%.1f)" % [
			String(r["name"]), String(r["aid"]) if not String(r["aid"]).is_empty() else "-",
			float(r["above"]), int(r["n"]),
			xmin, xmax, xmax - xmin, zmin, zmax, zmax - zmin])

	# ---- 另外：把房间内所有 layer=1 且「顶面在 0.15~3.5m」的碰撞盒全列出来 ----
	print()
	print("=== 房间内所有 CollisionShape3D（layer=1），标注顶面高度 ===")
	for cv in room.find_children("*", "CollisionObject3D", true, false):
		var co := cv as CollisionObject3D
		if co == null or co.collision_layer != 1:
			continue
		var aid := ""
		var cur2: Node = co
		while cur2 != null:
			if not str(cur2.get_meta("asset_id", "")).is_empty():
				aid = str(cur2.get_meta("asset_id", ""))
				break
			cur2 = cur2.get_parent()
		for sv in co.find_children("*", "CollisionShape3D", true, false):
			var cs := sv as CollisionShape3D
			if cs == null or not (cs.shape is BoxShape3D):
				continue
			var bx := cs.shape as BoxShape3D
			var xf := cs.global_transform
			var c := xf * Vector3.ZERO
			var half := bx.size * 0.5
			var top := c.y + absf(xf.basis.y.y) * half.y + absf(xf.basis.x.y) * half.x + absf(xf.basis.z.y) * half.z
			var bot := c.y - (absf(xf.basis.y.y) * half.y + absf(xf.basis.x.y) * half.x + absf(xf.basis.z.y) * half.z)
			print("  %-28s aid=%-34s box=(%5.2f,%5.2f,%5.2f) 世界y=[%7.2f,%7.2f] 离地顶=%5.2fm ctr=(%7.2f,%6.2f)" % [
				String(co.name), aid if not aid.is_empty() else "-",
				bx.size.x, bx.size.y, bx.size.z,
				bot, top, top - center.y, c.x, c.z])

	print()
	print("LEDGE_SCAN_DONE")
	get_tree().quit(0)
