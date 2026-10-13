extends Node
## 只读出图：把**运行时真实装配**的远征02 关卡拍下来。
##
## 与 `_scratch/exp02_topview.gd` 的区别很重要：
##   那个直接把 26 个房间 `.tscn` 摆一遍，**拍不到运行时额外生成的东西**；
##   本探针加载真正的关卡场景，让 `TowerDescent3D` 自己装配（房间壳 + 连接件），
##   因此能证明「相邻房之间有没有多长出通用走廊 / 地板 / 挡人碰撞」。
##
## 跑法（**必须带窗口**，headless 不渲染）：
##   "<godot_console>" --path "<project>" --scene res://tests/verification/probe_expedition02_live_view.tscn

const LEVEL_SCENE := "res://scenes/ExpeditionLevel02_3D.tscn"
const OUT_DIR := "user://exp02_live"


func _ready() -> void:
	var packed := load(LEVEL_SCENE) as PackedScene
	if packed == null:
		printerr("[live] 关卡场景加载失败")
		get_tree().quit(1)
		return
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	add_child(tower)
	for i in 12:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(1.2).timeout

	var room_by_id: Dictionary = tower.get("_room_by_id")
	print("[live] 房间数=%d" % room_by_id.size())
	var corridors: Dictionary = tower.get("_corridor_by_edge")
	var with_geom := 0
	for v in corridors.values():
		var c := v as Node3D
		if c == null:
			continue
		if int(c.get_meta("module_count", 0)) > 0:
			with_geom += 1
	print("[live] 连接件=%d 其中带几何=%d" % [corridors.size(), with_geom])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# ---------- ① 顶视正交：整关 ----------
	# 隐藏 26 个房间的封顶（否则只看得到屋顶）。运行时的走廊件不带这个前缀，不会被误藏。
	var hidden := 0
	for v in room_by_id.values():
		var room := v as DungeonRoom3D
		if room == null:
			continue
		for mv in room.find_children("*", "MeshInstance3D", true, false):
			var mi := mv as MeshInstance3D
			if mi != null and String(mi.name).begins_with("ceiling_deck_5m"):
				mi.visible = false
				hidden += 1
	print("[live] 隐藏封顶件=%d" % hidden)

	# 关雾：本关环境雾 fog_density=0.04 / fog_light_energy=0.36，正交机位拉到 90m 高时
	# 整张图会被雾洗成一片灰（第一版就是这么废掉的）。截图只为看结构，雾没有信息量。
	var env := _find_environment(tower)
	if env != null:
		print("[live] 关雾：fog_enabled %s -> false" % str(env.fog_enabled))
		env.fog_enabled = false
	else:
		print("[live] 没找到 Environment")
	for i in range(6):
		await get_tree().process_frame

	var boxes: Array[AABB] = []
	var owners: Array = []
	_walk_aabb_owner(tower, boxes, owners)
	var bounds := boxes[0]
	for b in boxes:
		bounds = bounds.merge(b)
	print("[live] 可见包围盒 min=%s max=%s mesh=%d" % [
		str(bounds.position), str(bounds.end), boxes.size()])

	# 报告「跑出关卡矩形」的件 —— 关卡本体只有 x∈[-40,40] z∈[-100,60]，
	# 超出这个范围的可见 Mesh 就是不该出现在这一关里的东西。
	print("[live] --- 跑出关卡矩形 x∈[-40,40] z∈[-100,60] 的可见件 ---")
	var outliers := 0
	for i in range(boxes.size()):
		var b: AABB = boxes[i]
		if (
			b.position.x < -42.0 or b.end.x > 42.0
			or b.position.z < -102.0 or b.end.z > 62.0
		):
			print("      %-52s min=(%8.2f,%7.2f,%8.2f) size=(%7.2f,%6.2f,%7.2f)" % [
				str(owners[i]), b.position.x, b.position.y, b.position.z,
				b.size.x, b.size.y, b.size.z])
			outliers += 1
			if outliers >= 25:
				print("      ...（只列前 25 条）")
				break
	if outliers == 0:
		print("      <无>")

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.5
	cam.far = 800.0
	tower.add_child(cam)
	var pad := 1.06
	var need_z := bounds.size.z * pad
	var need_x := bounds.size.x * pad
	# 竖幅窗口：80m 宽 × 160m 长的关卡用接近 1:2 的画幅才不浪费像素。
	var canvas := Vector2i(1500, 2700)
	get_window().size = canvas
	await get_tree().process_frame
	await get_tree().process_frame
	var aspect := float(canvas.x) / float(canvas.y)
	cam.size = maxf(need_z, need_x / aspect)
	var center := bounds.get_center()
	cam.global_position = Vector3(center.x, bounds.end.y + 90.0, center.z)
	cam.look_at(Vector3(center.x, 0.0, center.z), Vector3(0, 0, -1))
	cam.make_current()
	print("[live] 顶视 size=%.1fm 覆盖横=%.1f 纵=%.1f" % [cam.size, cam.size * aspect, cam.size])
	for i in range(14):
		await get_tree().process_frame
	await _save("A_顶视_整关.png")

	# ---------- ② 阳台 ↔ room_01 交界处放大顶视 ----------
	# 业主反馈的就这一处：「开阳台到 room_01 的门，刷出一堆墙」。
	# 关掉封顶后俯视这一带，能直接看出两房之间是不是**只有一道共墙**、
	# 有没有多长出通用走廊/地板。
	var start_room := room_by_id.get("start") as DungeonRoom3D
	var room_01 := room_by_id.get("room_01") as DungeonRoom3D
	if start_room != null and room_01 != null:
		# 横版窗口：竖幅窗口在透视下水平视野太窄，什么都看不清。
		get_window().size = Vector2i(1920, 1080)
		await get_tree().process_frame
		await get_tree().process_frame
		var z0 := room_01.global_position.z - 18.0
		var z1 := start_room.global_position.z + 12.0
		var mid := Vector2((start_room.global_position.x + room_01.global_position.x) * 0.5, (z0 + z1) * 0.5)
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = (z1 - z0) * 1.12
		cam.global_position = Vector3(mid.x, 40.0, mid.y)
		cam.look_at(Vector3(mid.x, 0.0, mid.y), Vector3(0, 0, -1))
		cam.make_current()
		for i in range(12):
			await get_tree().process_frame
		await _save("B_交界处放大顶视_阳台到room01.png")

		# ---------- ③ 阳台内第一人称看 room_01 的门 ----------
		get_window().size = Vector2i(1920, 1080)
		await get_tree().process_frame
		await get_tree().process_frame
		var sp := start_room.global_position
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 75.0
		cam.near = 0.05
		# 站在阳台南侧、眼高，朝北看向与 room_01 的共墙
		cam.global_position = Vector3(sp.x - 2.5, sp.y + 1.10, sp.z + 5.5)
		cam.look_at(Vector3(sp.x - 2.5, sp.y + 0.80, sp.z - 8.0), Vector3.UP)
		cam.make_current()
		for i in range(12):
			await get_tree().process_frame
		await _save("C_阳台内第一人称看门.png")

	# ---------- ④ 长廊内看西墙那 5 扇客房门 ----------
	# 这是本次修复的核心场景：一墙 5 门，修复前只有 1 扇有门扇、其余 4 个是空门洞。
	var corridor := room_by_id.get("room_02") as DungeonRoom3D
	if corridor != null:
		var cp := corridor.global_position
		# 站在长廊北段、贴近东墙，朝西南看 —— 一眼能扫到西墙 z=22.5 / 7.5 / -7.5 三扇门
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 78.0
		cam.near = 0.05
		cam.global_position = Vector3(cp.x + 3.6, cp.y + 1.25, cp.z + 20.0)
		cam.look_at(Vector3(cp.x - 5.0, cp.y + 1.05, cp.z - 2.0), Vector3.UP)
		cam.make_current()
		for i in range(12):
			await get_tree().process_frame
		await _save("D_长廊西墙5扇客房门.png")

		# 反向：朝东南看东墙那 5 扇
		cam.global_position = Vector3(cp.x - 3.6, cp.y + 1.25, cp.z + 20.0)
		cam.look_at(Vector3(cp.x + 5.0, cp.y + 1.05, cp.z - 2.0), Vector3.UP)
		cam.make_current()
		for i in range(12):
			await get_tree().process_frame
		await _save("E_长廊东墙5扇客房门.png")

	print("EXP02_LIVE_VIEW_DONE")
	get_tree().quit(0)


func _save(name: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		printerr("[live] 取图失败 %s" % name)
		return
	var out := ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, name])
	var err := img.save_png(out)
	print("[live] 出图 %-28s -> %s (err=%d)" % [name, out, err])


func _walk_aabb(node: Node, boxes: Array[AABB]) -> void:
	_walk_aabb_owner(node, boxes, [])


## 与 `_walk_aabb` 同一次遍历，但额外记录每个 AABB 的**归属路径**，
## 用来回答"这个跑出去的件是谁"。
func _walk_aabb_owner(node: Node, boxes: Array[AABB], owners: Array) -> void:
	var mi := node as MeshInstance3D
	if mi != null and mi.is_visible_in_tree() and mi.mesh != null:
		boxes.append(_aabb(mi))
		owners.append(node.get_path())
	for child in node.get_children():
		_walk_aabb_owner(child, boxes, owners)


func _find_environment(root: Node) -> Environment:
	for child in root.find_children("*", "WorldEnvironment", true, false):
		var we := child as WorldEnvironment
		if we != null and we.environment != null:
			return we.environment
	return null


func _aabb(mi: MeshInstance3D) -> AABB:
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
