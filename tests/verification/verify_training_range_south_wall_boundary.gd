extends Node3D
## 靶场南墙「去可视、留阻挡」验收（2026-10-16 业主要求）。
##
## 两件事一起钉住，缺一不可：
##   ① **可视确实没了** —— 南墙 10 段的 `ImportedModel.visible == false`，且其余三面未被误伤。
##   ② **阻挡确实还在** —— 从场地内朝 +Z 打物理射线，必须命中南墙的碰撞体
##      （节点名以 WallSegment_ 开头），而不是穿出去。
##
## 🔴 这两条判据**全部不需要渲染器** ⇒ 本验收注册在 `core` 套件里跑（headless）。
##    截图只是附加证据，渲染器不可用时自动跳过，**不影响退出码**。
##
## 单跑（带截图，真实渲染器）：
##   godot --path . --scene res://tests/verification/verify_training_range_south_wall_boundary.tscn

const RANGE_SCENE: PackedScene = preload("res://scenes/TrainingRange3D.tscn")
const OUT_DIR := "user://training_south_wall"
## 与 TrainingRangeEnvironment3D 的场地半宽一致：南墙内表面在 z = +25 - 0.15。
const HALF_EXTENT := 25.0

var _failures: Array[String] = []
var _range: Node3D
var _cam: Camera3D


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_range = RANGE_SCENE.instantiate()
	add_child(_range)
	for _i in range(6):
		await get_tree().process_frame
	_check_visual_state()
	await _check_collision_state()
	await _shoot()
	_report()
	get_tree().quit()


func _check_visual_state() -> void:
	var root := _range.get_node_or_null("EnvironmentKit/BoundaryWalls")
	if root == null:
		_failures.append("找不到 EnvironmentKit/BoundaryWalls")
		return
	var south_total := 0
	var south_hidden := 0
	var other_total := 0
	var other_hidden := 0
	for child in root.get_children():
		var node := child as Node3D
		if node == null:
			continue
		var visual := node.get_node_or_null("ImportedModel") as Node3D
		if visual == null:
			_failures.append("%s 缺 ImportedModel" % node.name)
			continue
		var is_south := absf(node.position.z - HALF_EXTENT) < 0.01
		if is_south:
			south_total += 1
			if not visual.visible:
				south_hidden += 1
		else:
			other_total += 1
			if not visual.visible:
				other_hidden += 1
	if south_total != 10:
		_failures.append("南墙段数应为 10，实测 %d" % south_total)
	if south_hidden != south_total:
		_failures.append("南墙仍有 %d/%d 段可视未隐藏" % [south_total - south_hidden, south_total])
	if other_hidden != 0:
		_failures.append("除南墙外有 %d 段被误隐藏（应为 0）" % other_hidden)
	var snapshot: Dictionary = _range.get_node("EnvironmentKit").call("get_snapshot")
	if int(snapshot.get("boundary_wall_segment_count", 0)) != 40:
		_failures.append("边界墙总段数应为 40，实测 %d" % int(snapshot.get("boundary_wall_segment_count", 0)))
	if int(snapshot.get("boundary_wall_visual_hidden_count", -1)) != 10:
		_failures.append(
			"snapshot 隐藏计数应为 10，实测 %d" % int(snapshot.get("boundary_wall_visual_hidden_count", -1))
		)
	print(
		"VISUAL south_hidden=%d/%d other_hidden=%d/%d"
		% [south_hidden, south_total, other_hidden, other_total]
	)


func _check_collision_state() -> void:
	var space := get_viewport().world_3d.direct_space_state
	# 每 5m 槽位正中打一条：从场内 (x, 5, 20) 朝 +Z 直射，最远 40m。
	# 起点刻意抬到 5m 高、退到 z=20 —— 低于装备墙(≤3.3m)与军械库货架(≤3.3m)的顶面，
	# 又已在它们的 z 范围之外，保证这条射线**只可能**撞南墙，不会被场景内其他碰撞体截胡。
	# 未隐藏可视前会命中南墙；去掉可视后**必须仍然命中**，否则就是"阻挡也没了"。
	var along_list: Array[float] = []
	for index in range(10):
		along_list.append(-HALF_EXTENT + 5.0 * (float(index) + 0.5))
	var hits := 0
	var miss_list: Array[String] = []
	for along in along_list:
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(along, 5.0, 20.0), Vector3(along, 5.0, 40.0)
		)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			miss_list.append("%.1f" % along)
			continue
		var collider := hit.get("collider") as Node
		var owner_name := ""
		var probe: Node = collider
		while probe != null:
			if probe.name.begins_with("WallSegment_"):
				owner_name = str(probe.name)
				break
			probe = probe.get_parent()
		if owner_name == "":
			miss_list.append("%.1f(命中 %s)" % [along, str(collider.name) if collider != null else "?"])
			continue
		hits += 1
		# 命中点必须落在南墙内表面附近（z ≈ 24.85），不能是场地内别的东西。
		var pos: Vector3 = hit.get("position", Vector3.ZERO)
		if absf(pos.z - (HALF_EXTENT - 0.15)) > 0.25:
			_failures.append("x=%.1f 命中 z=%.2f 不在南墙内表面附近" % [along, pos.z])
	if hits != 10:
		_failures.append("南墙阻挡缺失：10 条射线只命中 %d 条，漏 %s" % [hits, str(miss_list)])
	print("COLLISION south_hits=%d/10 miss=%s" % [hits, str(miss_list)])
	# 反向对照：南墙如果是「碰撞也没了」，这里应当命中 0 —— 用一条已知会漏的射线证明探针有分辨力。
	var control := PhysicsRayQueryParameters3D.create(Vector3(0.0, 1.5, 0.0), Vector3(0.0, 1.5, -40.0))
	control.collide_with_areas = false
	control.collide_with_bodies = true
	var north_hit := space.intersect_ray(control)
	print("CONTROL north_ray_hit=%s" % str(not north_hit.is_empty()))
	await get_tree().physics_frame


## 截图是**附加证据**，不是判据。
##
## 🔴 必须用 `DisplayServer.get_name() == "headless"` 来判定，**不能**判
## `get_viewport().get_texture() == null` —— 在 dummy 渲染器下那个调用返回的是
## **非 null** 的 ViewportTexture，于是会走进截图分支，然后
## `await RenderingServer.frame_post_draw` 因为 dummy 后端**永不发出绘制信号**而永久挂起
## （2026-10-16 实测：本验收在 headless 下卡了 41 分钟不退出，日志停在 CONTROL 行之后）。
func _shoot() -> void:
	if DisplayServer.get_name() == "headless":
		print("SHOT_SKIPPED headless_display_server")
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var hud := _range.get_node_or_null("HUD")
	if hud != null:
		hud.visible = false
	var probe_light := DirectionalLight3D.new()
	probe_light.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	probe_light.light_energy = 2.5
	probe_light.shadow_enabled = false
	add_child(probe_light)
	_cam = Camera3D.new()
	_cam.fov = 65.0
	_cam.far = 400.0
	add_child(_cam)
	_cam.make_current()
	await _capture(Vector3(0, 1.5, 0), Vector3(0, 1.5, 25), "after_center_to_SOUTH.png")
	await _capture(Vector3(0, 1.5, 8), Vector3(0, 1.5, 25), "after_armory_to_SOUTH.png")
	await _capture(Vector3(0, 1.5, 0), Vector3(0, 1.5, -25), "after_center_to_NORTH.png")


func _capture(pos: Vector3, look: Vector3, shot_name: String) -> void:
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)
	for _i in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		return
	img.save_png(OUT_DIR + "/" + shot_name)
	print("SHOT %s" % shot_name)


func _report() -> void:
	if _failures.is_empty():
		print("TRAINING_RANGE_SOUTH_WALL_BOUNDARY_OK: 南墙可视已隐藏且其余三面未动，10/10 射线仍被南墙挡住")
		get_tree().quit(0)
		return
	for item in _failures:
		push_error("南墙边界契约失败：%s" % item)
	get_tree().quit(1)
