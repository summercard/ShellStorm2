extends Node
## 常驻交互圆点契约（2026-10-02 随「交互提示统一改为圆点」新增）。
##
## 盯住六条硬约束：
## 1. 每个可交互 provider 都会拿到一个圆点，且圆点**常驻**（不靠近也可见）。
## 2. 距离越近越清晰：近处圆点的 clarity 明显高于远处。
## 3. 近处圆点播放**放大呼吸**动画（scale 随时间波动）。
## 4. 读条类交互走**圆环**：进度跨过 1.0 时自动播一次放大脉冲；
##    交互成功也会放大脉冲。
## 5. 手写三角扇/环带的**绕序必须与引擎自带 QuadMesh 同向**。绕反了会被 CULL_BACK
##    整块剔除：圆点只剩内核（直径凭空少一半），而 visible / AABB / surfaces 全都正常。
## 6. 圆点材质**不许开 billboard**。着色器 billboard 会归一化模型基向量、连带吃掉
##    node.scale —— 呼吸与脉冲会静默失效（实测倍率 1.071→0.5、渲染面积纹丝不动）。
##
## 同时静态守住「旧搜索进度条 UI 已移除」这个已经明确的重构结果。

const DOT_SCRIPT := preload("res://src/ui/InteractionDot3D.gd")


class DotProbe:
	extends Node3D

	var probe_id := ""
	var priority := 0
	var interaction_count := 0
	var progress_active := false
	var progress_value := 0.0

	func configure(id_value: String, priority_value: int) -> void:
		probe_id = id_value
		priority = priority_value
		add_to_group(PlayerInteractionController3D.PROVIDER_GROUP)

	func get_interaction_candidate(_player: Player3D) -> Dictionary:
		return {
			"available": true,
			"interaction_id": probe_id,
			"position": global_position,
			"priority": priority,
			"prompt": probe_id,
		}

	func set_interaction_focus(_candidate: Dictionary, _focused: bool) -> void:
		pass

	func perform_interaction(_player: Player3D, _candidate: Dictionary) -> bool:
		interaction_count += 1
		return true

	func get_interaction_dot_anchor() -> Vector3:
		return global_position

	func get_interaction_progress() -> Dictionary:
		return {"active": progress_active, "progress": progress_value}


func _ready() -> void:
	var failures: Array[String] = []
	_validate_legacy_search_ui_removed(failures)
	_validate_dot_geometry(failures)

	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 1009902
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	await _validate_dots(tower, failures)

	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("INTERACTION_DOT_PRESENTATION_OK: resident dots, distance clarity, breathing, ring progress and pulse")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("INTERACTION_DOT_PRESENTATION_FAIL: %s" % failure)
	get_tree().quit(1)


## ⑤⑥ 圆点几何与材质的隐性契约。这两条都是「日志全绿、画面全错」的坑：
## 绕序反了 → 一部分被剔除；材质开 billboard → node.scale 被吃掉。
func _validate_dot_geometry(failures: Array[String]) -> void:
	var dot := DOT_SCRIPT.new() as MeshInstance3D
	# add_child 会同步触发 _ready → _build()，网格与材质当场就绪，不需要等帧。
	add_child(dot)
	var reference := _first_triangle_normal_z(QuadMesh.new().get_mesh_arrays())
	_expect(
		not is_zero_approx(reference),
		"取不到 QuadMesh 的参考绕序，无法校验圆盘",
		failures
	)
	var disc := dot.mesh as ArrayMesh
	_expect(disc != null and disc.get_surface_count() > 0, "圆盘没有生成网格", failures)
	if disc != null and disc.get_surface_count() > 0:
		var disc_winding := _first_triangle_normal_z(disc.surface_get_arrays(0))
		_expect(
			signf(disc_winding) == signf(reference),
			"圆盘三角绕序与 QuadMesh 相反（disc=%.6f ref=%.6f）—— 会被 CULL_BACK 剔除"
				% [disc_winding, reference],
			failures
		)

	# 圆环：推一次进度让它把网格建出来。
	dot.call("set_progress", true, 0.5)
	var ring := dot.get_node_or_null("RingProgress") as MeshInstance3D
	_expect(ring != null, "圆点没有挂进度环节点", failures)
	if ring != null and ring.mesh is ArrayMesh and (ring.mesh as ArrayMesh).get_surface_count() > 0:
		var ring_winding := _first_triangle_normal_z((ring.mesh as ArrayMesh).surface_get_arrays(0))
		_expect(
			signf(ring_winding) == signf(reference),
			"进度环绕序与 QuadMesh 相反（ring=%.6f ref=%.6f）—— 会被 CULL_BACK 剔除"
				% [ring_winding, reference],
			failures
		)
	else:
		_expect(false, "进度环没有生成网格", failures)

	# 材质不许开 billboard：它归一化模型基向量，node.scale 会被丢掉。
	var disc_material := dot.material_override as StandardMaterial3D
	_expect(disc_material != null, "圆盘没有材质", failures)
	if disc_material != null:
		_expect(
			disc_material.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED,
			"圆盘材质开了 billboard —— 会把 node.scale 归一化掉，呼吸与脉冲会静默失效",
			failures
		)
	if ring != null and ring.material_override is StandardMaterial3D:
		_expect(
			(ring.material_override as StandardMaterial3D).billboard_mode
				== BaseMaterial3D.BILLBOARD_DISABLED,
			"进度环材质开了 billboard —— 会吃掉 node.scale",
			failures
		)

	# 缩放通道必须是活的：clarity 1.0 与 0.0 的 base_scale 应当差一倍（FAR_SCALE=0.5）。
	for _step in range(40):
		dot.call("update_state", 1.0, false, 0.033)
	var wide := dot.scale.x
	for _step in range(40):
		dot.call("update_state", 0.0, false, 0.033)
	var narrow := dot.scale.x
	_expect(
		wide > narrow * 1.5,
		"圆点缩放没有随清晰度变化（near=%.3f far=%.3f）—— 缩放通道已失效" % [wide, narrow],
		failures
	)
	dot.queue_free()


## 首三角的法线 z 分量。同平面网格比大小即可判定绕序是否同向 —— 不依赖引擎的正反面约定。
func _first_triangle_normal_z(arrays: Array) -> float:
	if arrays.is_empty():
		return 0.0
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if vertices.is_empty() or indices.size() < 3:
		return 0.0
	var a := vertices[indices[0]]
	var b := vertices[indices[1]]
	var c := vertices[indices[2]]
	return (b - a).cross(c - a).z


func _validate_legacy_search_ui_removed(failures: Array[String]) -> void:
	var file := FileAccess.open("res://src/world3d/RoomFurniture3D.gd", FileAccess.READ)
	_expect(file != null, "无法读取 RoomFurniture3D.gd", failures)
	if file == null:
		return
	var source := file.get_as_text()
	_expect(
		"SearchProgressOverlay" not in source and "ProgressBar.new()" not in source,
		"旧的搜索进度条 UI 仍留在 RoomFurniture3D",
		failures
	)
	_expect(
		"func get_interaction_progress" in source,
		"搜索容器没有把读条进度交给圆环",
		failures
	)


func _validate_dots(tower: TowerDescent3D, failures: Array[String]) -> void:
	var player := tower.player
	_expect(player != null, "TowerDescent3D 没有玩家", failures)
	if player == null:
		return
	var controller := player.interaction_controller
	_expect(controller != null, "玩家没有安装唯一交互控制器", failures)
	if controller == null:
		return

	# 把玩家挪到空场，排除关卡内真实对象的干扰。
	player.global_position = Vector3(0.0, 0.05, 1000.0)
	player.velocity = Vector3.ZERO

	var near := DotProbe.new()
	near.position = player.global_position + Vector3(1.0, 0.0, 0.0)
	near.configure("near_dot_probe", 90)
	tower.add_child(near)

	var far := DotProbe.new()
	far.position = player.global_position + Vector3(12.0, 0.0, 0.0)
	far.configure("far_dot_probe", 10)
	tower.add_child(far)

	var progress := DotProbe.new()
	progress.position = player.global_position + Vector3(-1.4, 0.0, 0.0)
	progress.configure("progress_dot_probe", 10)
	tower.add_child(progress)

	# 让控制器把圆点建出来并跑几帧插值。
	for _index in range(12):
		await get_tree().process_frame

	var near_dot := controller.get_interaction_dot_snapshot(near)
	var far_dot := controller.get_interaction_dot_snapshot(far)
	var progress_dot := controller.get_interaction_dot_snapshot(progress)
	_expect(not near_dot.is_empty(), "近处 provider 没有拿到圆点", failures)
	_expect(not far_dot.is_empty(), "远处 provider 没有拿到圆点", failures)
	_expect(not progress_dot.is_empty(), "读条 provider 没有拿到圆点", failures)
	if near_dot.is_empty() or far_dot.is_empty():
		return

	# ① 常驻：远处圆点也必须可见。
	_expect(
		float(far_dot.get("visible_amount", 0.0)) > 0.5,
		"远处圆点没有常驻显示（visible_amount=%.3f）" % float(far_dot.get("visible_amount", 0.0)),
		failures
	)
	# ② 距离决定清晰度。
	var near_clarity := float(near_dot.get("clarity", 0.0))
	var far_clarity := float(far_dot.get("clarity", 0.0))
	_expect(
		near_clarity > far_clarity + 0.2,
		"近处圆点没有比远处更清晰（near=%.3f far=%.3f）" % [near_clarity, far_clarity],
		failures
	)
	# ③ 呼吸：真实时间采样 1 秒，scale 必须有可观测波动。
	var lowest := 999.0
	var highest := -999.0
	for _index in range(20):
		await get_tree().create_timer(0.05).timeout
		var sampled := controller.get_interaction_dot_snapshot(near)
		var scale_multiplier := float(sampled.get("scale_multiplier", 0.0))
		lowest = minf(lowest, scale_multiplier)
		highest = maxf(highest, scale_multiplier)
	_expect(
		highest - lowest > 0.02,
		"近处圆点没有放大呼吸动画（波动 %.4f）" % (highest - lowest),
		failures
	)

	# ④ 读条走圆环：进度 0.5 时圆环可见且停在半圈。
	progress.progress_active = true
	progress.progress_value = 0.5
	await get_tree().process_frame
	await get_tree().process_frame
	var ring_dot := controller.get_interaction_dot_snapshot(progress)
	_expect(
		bool(ring_dot.get("ring_visible", false)),
		"读条中圆环没有显示",
		failures
	)
	_expect(
		absf(float(ring_dot.get("ring_progress", 0.0)) - 0.5) < 0.05,
		"圆环进度没有跟随读条（%.3f）" % float(ring_dot.get("ring_progress", 0.0)),
		failures
	)

	# ⑤ 圈满即完成：进度跨过 1.0 自动播一次放大脉冲。
	progress.progress_value = 1.0
	await get_tree().process_frame
	var completed := controller.get_interaction_dot_snapshot(progress)
	_expect(
		bool(completed.get("pulsing", false)),
		"进度圈满后圆点没有播放放大反馈",
		failures
	)

	# ⑥ 交互成功也放大脉冲（控制器在 perform_interaction 返回 true 后触发）。
	controller.pulse_dot(near)
	await get_tree().process_frame
	var pulsed := controller.get_interaction_dot_snapshot(near)
	_expect(
		bool(pulsed.get("pulsing", false)),
		"交互成功后圆点没有播放放大反馈",
		failures
	)

	# ⑦ 圆点数量应覆盖场上全部 provider（含真实关卡对象）。
	_expect(
		controller.get_interaction_dot_count() >= 3,
		"圆点数量少于已注册 provider（%d）" % controller.get_interaction_dot_count(),
		failures
	)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
