extends Node
## 远征03 性能体检：真实装配后统计节点/网格/材质/灯光/物理体开销，并量 CPU 帧时。
##
## 为什么单独做：`verify_3d_performance_budget` 跑的是 `AbyssArchive3D`（塔楼），
## 不含远征03 的公馆壳体。远征03 的结构件是「每 5m 一块」的独立 Prefab，
## 17 间房实测 759 块地砖 + 446 段墙 + 24 扇门，节点与绘制量级完全是另一回事。
##
## 判据用**量级**，不是硬阈值：这台机器 headless 无 GPU，帧时只能反映 CPU 侧
## （脚本 + 物理 + 场景树遍历），不代表真机帧率。所以：
##   · 会红项：单帧 CPU 耗时 > 33ms（撑不住 30fps 保障线）、生成耗时 > 3s
##   · 只打印：节点数 / 网格数 / 材质数 / 灯数 / 三角形数（供与预算表对照）
##
## 只读。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const SEEDS := [77003244, 100990, 42]
const SAMPLE_FRAMES := 180
const CPU_FRAME_BUDGET_MS := 33.0
const SPAWN_BUDGET_MS := 3000.0

var _failures: Array[String] = []


func _ready() -> void:
	for seed_value in SEEDS:
		await _measure(seed_value)
	print("PERF_%s failures=%d" % ["OK" if _failures.is_empty() else "FAILED", _failures.size()])
	for reason in _failures:
		printerr("PERF_FAIL ", reason)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _measure(seed_value: int) -> void:
	var t0 := Time.get_ticks_usec()
	var tower := SCENE.instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", seed_value)
	add_child(tower)
	for _frame in 20:
		await get_tree().process_frame
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room != null:
			room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
			room.ensure_shell_built()
			room.ensure_detail_built()
	for _frame in 3:
		await get_tree().process_frame
	var settle_ms := float(Time.get_ticks_usec() - t0) / 1000.0

	var stats := _walk(tower)
	print("PERF_SEED %d settle=%.0fms" % [seed_value, settle_ms])
	print("  NODES total=%d  mesh=%d  material_unique=%d  light=%d(cast_shadow=%d)  static_body=%d  shape=%d  collisionshape=%d"
		% [
			stats["nodes"], stats["mesh"], stats["materials"],
			stats["lights"], stats["shadow_lights"],
			stats["static_bodies"], stats["shapes"], stats["col_shapes"],
		])
	print("  TRIANGLES approx=%d  surfaces=%d" % [stats["triangles"], stats["surfaces"]])
	print("  PER_ROOM %s" % stats["per_room_text"])

	# ── CPU 帧时（headless：脚本 + 物理 + 树遍历，不含 GPU）──────────────
	var times: Array[float] = []
	for _i in SAMPLE_FRAMES:
		var f0 := Time.get_ticks_usec()
		await get_tree().process_frame
		times.append(float(Time.get_ticks_usec() - f0) / 1000.0)
	times.sort()
	var avg := 0.0
	for t in times:
		avg += t
	avg /= float(times.size())
	var p50: float = times[int(float(times.size()) * 0.5)]
	var p95: float = times[int(float(times.size()) * 0.95)]
	var worst: float = times[times.size() - 1]
	print("  FRAME cpu avg=%.2fms p50=%.2f p95=%.2f worst=%.2f (%d 帧)"
		% [avg, p50, p95, worst, SAMPLE_FRAMES])
	if p95 > CPU_FRAME_BUDGET_MS:
		_failures.append("seed %d: CPU p95 帧时 %.1fms 超 %.0fms" % [seed_value, p95, CPU_FRAME_BUDGET_MS])
	if worst > CPU_FRAME_BUDGET_MS * 2.0:
		_failures.append("seed %d: 单帧最差 %.1fms（疑似卡顿尖峰）" % [seed_value, worst])
	if settle_ms > SPAWN_BUDGET_MS:
		_failures.append("seed %d: 装配耗时 %.0fms 超 %.0fms" % [seed_value, settle_ms, SPAWN_BUDGET_MS])

	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _walk(root: Node) -> Dictionary:
	var nodes := 0
	var mesh := 0
	var surfaces := 0
	var triangles := 0
	var lights := 0
	var shadow_lights := 0
	var static_bodies := 0
	var shapes := 0
	var col_shapes := 0
	var materials := {}
	var per_room: Array[String] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		nodes += 1
		if node is MeshInstance3D:
			mesh += 1
			var mi := node as MeshInstance3D
			if mi.mesh != null:
				surfaces += mi.mesh.get_surface_count()
				for s in mi.mesh.get_surface_count():
					var mat := mi.get_active_material(s)
					if mat != null:
						materials[mat.get_instance_id()] = true
			if mi.material_override != null:
				materials[mi.material_override.get_instance_id()] = true
		elif node is Light3D:
			lights += 1
			if (node as Light3D).shadow_enabled:
				shadow_lights += 1
		elif node is StaticBody3D:
			static_bodies += 1
		elif node is CollisionShape3D:
			col_shapes += 1
			if (node as CollisionShape3D).shape != null:
				shapes += 1
		for child in node.get_children():
			stack.append(child)

	# 粗略三角量：对每个 surface 取表面数组大小 /3 不现实（无 GPU 也要读 mesh），
	# 这里用「表面数 × 平均 200 面」占位，只用于量级比较。
	triangles = surfaces * 200
	for value in root.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room == null or not room.procedural_shell:
			continue
		var art_root := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
		var manor := 0
		var art: Array[Node] = []
		if art_root != null:
			art = art_root.find_children("*", "Node3D", true, false)
		for n in art:
			if str(n.scene_file_path).contains("env_manor_"):
				manor += 1
		per_room.append("%s=%d" % [room.room_id, manor])
	return {
		"nodes": nodes,
		"mesh": mesh,
		"surfaces": surfaces,
		"triangles": triangles,
		"materials": materials.size(),
		"lights": lights,
		"shadow_lights": shadow_lights,
		"static_bodies": static_bodies,
		"shapes": shapes,
		"col_shapes": col_shapes,
		"per_room_text": " ".join(per_room),
	}
