extends Node3D
## 录制 v2：带日志与看门狗。目标——在真实关卡场景里拍「收租人」。
## godot --path . res://tests/rec/record_elite.tscn --resolution 1280x720 > rec.log 2>&1

const LEVEL_SCENE := "res://scenes/ExpeditionLevel99_3D.tscn"
const ROOM_ID := "room_01"
const OUT_DIR := "res://tests/rec/out"
const FPS := 15
const SECONDS := 8.0
const DIST_NEAR := 3.4
const DIST_FAR := 5.2
const HEIGHT := 1.45

var _elite: Node3D = null
var _angle := 0.0
var _fill: OmniLight3D = null
var _log_path := ""


func _ready() -> void:
	_log_path = ProjectSettings.globalize_path("res://tests/rec/rec_progress.log")
	_log("BOOT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_log("OUT_DIR ready")

	var packed: PackedScene = load(LEVEL_SCENE)
	if packed == null:
		_log("FAIL 关卡场景加载失败")
		get_tree().quit(1)
		return
	_log("scene resource loaded")
	var scene := packed.instantiate()
	add_child(scene)
	_log("scene instantiated")
	# 关卡场景自带标题/开始 UI（CanvasLayer 全屏盖住画面），录之前全部隐藏。
	var hidden := 0
	for node in scene.find_children("*", "CanvasLayer", true, false):
		var layer := node as CanvasLayer
		if layer != null and layer.visible:
			layer.visible = false
			hidden += 1
	_log("canvaslayers hidden=%d" % hidden)

	var rooms: Array = []
	for i in range(600):
		await get_tree().process_frame
		var value: Variant = scene.get("_rooms")
		if value is Array and (value as Array).size() >= 4:
			rooms = value as Array
			break
		if i % 100 == 0:
			_log("waiting rooms i=%d" % i)
	if rooms.is_empty():
		_log("FAIL 房间未装配")
		get_tree().quit(1)
		return
	_log("rooms ready n=%d" % rooms.size())

	var target: DungeonRoom3D = null
	for room in rooms:
		var typed := room as DungeonRoom3D
		if typed != null and typed.room_id == ROOM_ID:
			target = typed
	if target == null:
		_log("FAIL 找不到 %s" % ROOM_ID)
		get_tree().quit(1)
		return
	_log("room found elite_id=%s" % str(target.elite_id))

	scene.call("_spawn_room_enemies", target)
	_log("spawn called")
	for _i in range(6):
		await get_tree().process_frame
	_log("spawn settled")

	var by_room: Dictionary = scene.get("_enemy_nodes_by_room") as Dictionary
	var nodes: Array = by_room.get(ROOM_ID, []) as Array
	var listing: Array[String] = []
	for node in nodes:
		var enemy := node as Enemy3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var data := enemy.get_enemy_data()
		var is_elite := bool(data.get("is_elite", false))
		listing.append("%s%s" % [str(data.get("elite_id", "?")), " [ELITE]" if is_elite else ""])
		if is_elite and _elite == null:
			_elite = enemy
	_log("enemies n=%d %s" % [nodes.size(), str(listing)])

	if _elite == null:
		_log("FAIL 找不到精英，退化为直接加载精英模型")
		await _fallback_record()
		return

	for _i in range(20):
		await get_tree().process_frame
	_log("warmup done, elite_pos=%s" % str(_elite.global_position))

	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.05
	cam.far = 800.0
	add_child(cam)
	cam.make_current()
	var spot := SpotLight3D.new()
	spot.light_energy = 0.9
	spot.spot_range = 12.0
	spot.spot_angle = 40.0
	spot.shadow_enabled = false
	spot.light_color = Color(1.0, 0.95, 0.88)
	cam.add_child(spot)
	_fill = OmniLight3D.new()
	_fill.light_energy = 0.35
	_fill.omni_range = 8.0
	_fill.shadow_enabled = false
	_fill.light_color = Color(0.8, 0.9, 1.0)
	add_child(_fill)
	_log("lights ready")
	var arc := _pick_arc()
	_log("arc start=%.1f span=%.1f" % [rad_to_deg(arc.x), rad_to_deg(arc.y)])
	_aim(cam, 4.4)
	_log("camera ready")

	var total := int(FPS * SECONDS)
	for i in range(total):
		var t := float(i) / float(FPS)
		var p := clampf(t / SECONDS, 0.0, 1.0)
		_angle = arc.x + arc.y * p
		var dist: float = lerp(4.6, 3.2, clampf((p - 0.15) / 0.85, 0.0, 1.0))
		_aim(cam, dist)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "%s/frame_%04d.png" % [ProjectSettings.globalize_path(OUT_DIR), i + 1]
		var err := img.save_png(path)
		if err != OK:
			_log("FAIL 保存 i=%d err=%d" % [i, err])
			get_tree().quit(1)
			return
		if i % 15 == 0:
			_log("frame %d/%d" % [i + 1, total])
	_log("REC_OK frames=%d fps=%d" % [total, FPS])
	get_tree().quit(0)


func _fallback_record() -> void:
	var packed: PackedScene = load("res://assets/art/enemies/elite_3d/enm_elite_arms_taker/runtime/enm_elite_arms_taker/enm_elite_arms_taker_root_top3d.tscn")
	if packed == null:
		_log("FAIL 精英场景也加载失败")
		get_tree().quit(1)
		return
	var node := packed.instantiate()
	add_child(node)
	_elite = node as Node3D
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.09, 0.13)
	e.ambient_light_color = Color(0.45, 0.5, 0.65)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, 40.0, 0.0)
	light.light_energy = 1.8
	add_child(light)
	var plain := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20.0, 20.0)
	plain.mesh = pm
	add_child(plain)
	for _i in range(20):
		await get_tree().process_frame
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.make_current()
	_log("fallback ready")
	var total := int(FPS * SECONDS)
	for i in range(total):
		var t := float(i) / float(FPS)
		_angle = deg_to_rad(-55.0 + t * 22.0) if t < 5.0 else deg_to_rad(30.0)
		_aim(cam, DIST_FAR)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/frame_%04d.png" % [ProjectSettings.globalize_path(OUT_DIR), i + 1])
	_log("REC_OK(fallback) frames=%d" % total)
	get_tree().quit(0)


func _pick_arc() -> Vector2:
	# 在角色四周扫一圈，找最长的一段「视线不被墙挡」的扇区，镜头只在扇区内走。
	var n := 48
	var step := TAU / float(n)
	var flags: Array[bool] = []
	var radius := 4.2
	for _try in range(3):
		flags.clear()
		for k in range(n):
			flags.append(_is_clear(float(k) * step, radius))
		var clear_n := 0
		for f in flags:
			if f:
				clear_n += 1
		if clear_n >= n / 3:
			break
		radius -= 1.0
	var best_start := 0
	var best_len := 0
	for k in range(n):
		if not flags[k]:
			continue
		if flags[(k - 1 + n) % n]:
			continue
		var length := 0
		while length < n and flags[(k + length) % n]:
			length += 1
		if length > best_len:
			best_len = length
			best_start = k
	if best_len <= 1:
		return Vector2(deg_to_rad(-55.0), deg_to_rad(24.0))
	var span := step * float(best_len) * 0.85
	var start := float(best_start) * step + step * 0.1
	return Vector2(start, span)


func _is_clear(angle: float, dist: float) -> bool:
	if _elite == null or not is_instance_valid(_elite):
		return true
	var look := _elite.global_position + Vector3(0.0, 1.05, 0.0)
	var dir := Vector3(sin(angle), 0.0, cos(angle))
	var probe := look + dir * dist + Vector3(0.0, HEIGHT - 1.05, 0.0)
	var space := get_viewport().world_3d.direct_space_state
	if space == null:
		return true
	var q := PhysicsRayQueryParameters3D.create(look, probe)
	q.collide_with_areas = false
	if _elite is CollisionObject3D:
		q.exclude = [(_elite as CollisionObject3D).get_rid()]
	return space.intersect_ray(q).is_empty()


func _aim(cam: Camera3D, dist: float) -> void:
	if _elite == null or not is_instance_valid(_elite):
		return
	var base := _elite.global_position
	var look := base + Vector3(0.0, 1.05, 0.0)
	var dir := Vector3(sin(_angle), 0.0, cos(_angle))
	var space := get_viewport().world_3d.direct_space_state
	# 房间 25x25，环绕时镜头会穿墙：从远到近试距离，取第一个视线不被墙挡住的。
	var chosen := dist
	if space != null:
		var try_d := dist
		var found := -1.0
		while try_d >= 1.8:
			var probe := look + dir * try_d + Vector3(0.0, HEIGHT - 1.05, 0.0)
			var q := PhysicsRayQueryParameters3D.create(look, probe)
			q.collide_with_areas = false
			if _elite is CollisionObject3D:
				q.exclude = [(_elite as CollisionObject3D).get_rid()]
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				found = try_d
				break
			try_d -= 0.4
		chosen = found if found > 0.0 else 1.8
	var want := look + dir * chosen + Vector3(0.0, HEIGHT - 1.05, 0.0)
	cam.global_position = want
	cam.look_at(look, Vector3.UP)
	if _fill != null and is_instance_valid(_fill):
		_fill.global_position = base + Vector3(0.0, 2.4, 0.0)


func _log(msg: String) -> void:
	print("REC ", msg)
	var f := FileAccess.open(_log_path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(_log_path, FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(msg)
		f.flush()
		f.close()
