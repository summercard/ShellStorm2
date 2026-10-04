extends Node
## 常驻交互圆点契约（2026-10-02 随「交互提示统一改为圆点」新增；
## 同日二轮：统一白点、圆点变小、常驻态改七成、按键牌改「(e) 功能词」、基地设施退回文字牌）。
##
## 盯住十条硬约束：
## 1. 每个可交互 provider 都会拿到一个圆点，且圆点**常驻**（不靠近也可见）。
##    例外只有基地设施，见第 9 条。
## 2. 距离越近越清晰：近处圆点的 clarity 明显高于远处。
## 3. 近处圆点播放**放大呼吸**动画（scale 随时间波动）。
## 4. 读条类交互走**圆环**：进度跨过 1.0 时自动播一次放大脉冲；
##    交互成功也会放大脉冲。
## 5. 手写三角扇/环带的**绕序必须与引擎自带 QuadMesh 同向**。绕反了会被 CULL_BACK
##    整块剔除：圆点只剩内核（直径凭空少一半），而 visible / AABB / surfaces 全都正常。
## 6. 圆点材质**不许开 billboard**。着色器 billboard 会归一化模型基向量、连带吃掉
##    node.scale —— 呼吸与脉冲会静默失效（实测倍率 1.071→0.5、渲染面积纹丝不动）。
## 7. **全场统一白点**：所有圆点色值必须一致且为白，不许按对象类型分色。
## 8. 按键牌是「(e) + 功能词」，功能词从 provider 的 prompt 抽；没有 `[E]` 标记的
##    状态文案不显示按键牌 —— 不能空口承诺「按 e 能做某事」。
## 9. **基地设施家族（BaseFacility3D 及其子类）没有圆点**，且它自己的黄色文字提示牌必须
##    还能随聚焦显隐。这是那次改动被整体回退的两半，任一半失效都要红。
##    ⚠️ 2026-10-04 补的子类一半：豁免清单只按「父类脚本路径相等」匹配时，
##    `HologramExpeditionFacility3D`（99F 远征情报室中央全息平台）/ `WardrobeFacility3D`
##    会静默漏网、重新长出圆点。控制器已改为**沿基类链**匹配，这里父类、子类各钉一条。
## 10. **尺寸档贴着可操作半径**（APPROACH_* 2.6 → 5.2m），与清晰度档（3.2 → 16m）
##     分开：站到能按 e 的距离 = 满尺寸，走出 5.2m = FAR_SCALE 常驻尺寸。两档一旦
##     重新合回一条，房间里就永远走不到常驻尺寸 —— 那正是「远处还是很大」的成因。
##
## 同时静态守住「旧搜索进度条 UI 已移除」这个已经明确的重构结果。

const DOT_SCRIPT := preload("res://src/ui/InteractionDot3D.gd")
## 与控制器里的豁免清单必须一致；控制器改了而这里没改，第 9 条会当场变红。
const EXCLUDED_PROVIDER_SCRIPT := "res://src/base3d/BaseFacility3D.gd"


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
			# 真实的容器文案：用来验「[E] 搜索 · SMALL → (e) 搜索」这条抽取链。
			"prompt": "[E] 搜索 · SMALL",
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
	_validate_action_verb_extraction(failures)
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
		print(
			"INTERACTION_DOT_PRESENTATION_OK: uniform white resident dots, distance clarity, "
			+ "approach sizing bracketed to the operable range, breathing, ring progress, pulse, "
			+ "(e) verb key hint, base facility reverted to its own prompt"
		)
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

	# ⑦ 统一白点：圆盘必须就是白色，色值不许按对象类型走。
	var disc_material := dot.material_override as StandardMaterial3D
	_expect(disc_material != null, "圆盘没有材质", failures)
	if disc_material != null:
		_expect(
			disc_material.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED,
			"圆盘材质开了 billboard —— 会把 node.scale 归一化掉，呼吸与脉冲会静默失效",
			failures
		)
		var albedo := disc_material.albedo_color
		_expect(
			absf(albedo.r - 1.0) < 0.001 and absf(albedo.g - 1.0) < 0.001 and absf(albedo.b - 1.0) < 0.001,
			"圆盘不是白点（albedo=%s）—— 又按对象类型分色了" % str(albedo),
			failures
		)
	if ring != null and ring.material_override is StandardMaterial3D:
		_expect(
			(ring.material_override as StandardMaterial3D).billboard_mode
				== BaseMaterial3D.BILLBOARD_DISABLED,
			"进度环材质开了 billboard —— 会吃掉 node.scale",
			failures
		)
	# 进度环必须画在圆盘**外面**：内径大于圆盘半径，否则环会压在盘上糊成一坨。
	_expect(
		float(DOT_SCRIPT.RING_INNER_RADIUS_M) > float(DOT_SCRIPT.DOT_RADIUS_M),
		"进度环内径（%.3f）不大于圆盘半径（%.3f）—— 环会压在圆盘上"
			% [float(DOT_SCRIPT.RING_INNER_RADIUS_M), float(DOT_SCRIPT.DOT_RADIUS_M)],
		failures
	)

	# 缩放通道必须活着，且常驻比例就是 FAR_SCALE（2026-10-02 主人指定为接近态的七成）。
	# clarity 0.0 时呼吸是关的（见 BREATH_MIN_CLARITY），所以这里应当**精确**等于 FAR_SCALE，
	# 不是「大概差不多」—— 常驻比例被谁动了，这条当场红。
	for _step in range(60):
		dot.call("update_state", 0.0, false, 0.033)
	var narrow := dot.scale.x
	_expect(
		absf(narrow - float(DOT_SCRIPT.FAR_SCALE)) < 0.005,
		"常驻态缩放不等于 FAR_SCALE（narrow=%.4f 期望=%.4f）—— 常驻比例被改动过"
			% [narrow, float(DOT_SCRIPT.FAR_SCALE)],
		failures
	)

	# ⑩ 尺寸档必须**贴着可操作半径**，不能挂在 16m 的清晰度窗口上。
	#
	# 盯的是主人 2026-10-02 的原话：「战局内可搜索的设施，在远处还是很大，并没有缩小，
	# 应该是走近到可以操作后变大」。当时的缺陷正是尺寸跟着清晰度档走（3.2→16m）：
	# 房间里永远到不了 FAR_SCALE，5m 处还有满尺寸的 85%。
	var approach_near := float(DOT_SCRIPT.APPROACH_NEAR_DISTANCE_M)
	var approach_far := float(DOT_SCRIPT.APPROACH_FAR_DISTANCE_M)
	var clarity_near := float(DOT_SCRIPT.NEAR_DISTANCE_M)
	var clarity_far := float(DOT_SCRIPT.FAR_DISTANCE_M)
	_expect(
		approach_near < approach_far,
		"尺寸档窗口反了（near=%.2f far=%.2f）—— 会变成「走远反而变大」"
			% [approach_near, approach_far],
		failures
	)
	# 尺寸窗口必须是清晰度窗口的真子集，否则远处又缩不下去。
	_expect(
		approach_near < clarity_near and approach_far < clarity_far,
		"尺寸档没有比清晰度档更贴边（尺寸 %.2f~%.2f vs 清晰度 %.2f~%.2f）—— 远处又会「还是很大」"
			% [approach_near, approach_far, clarity_near, clarity_far],
		failures
	)
	# 窗口远端一旦越过清晰度近端太多，中间会留出「已经能按 e、圆点却还没变大」的空档。
	_expect(
		approach_far <= clarity_near + 2.0,
		"尺寸档远端 %.2f 离可操作距离（清晰度近端 %.2f）太远 —— 中间会出现已可操作但还没变大的空档"
			% [approach_far, clarity_near],
		failures
	)
	# 两端取代表值：站在可操作距离上必须满尺寸（家具交互盒半宽 ≈1.5m + 圆点架高 1.5m
	# ⇒ 3D 距离 ≈2.2m）；走出 8m 必须落回常驻尺寸。
	var readable_d := sqrt(1.6 * 1.6 + 1.5 * 1.5)
	var readable_approach := float(DOT_SCRIPT.approach_for_distance(readable_d))
	_expect(
		readable_approach >= 0.9,
		"站在可操作的距离上（3D %.2fm）圆点还不是满尺寸（approach=%.3f）" % [readable_d, readable_approach],
		failures
	)
	var distant_d := sqrt(8.2 * 8.2 + 1.5 * 1.5)
	var distant_approach := float(DOT_SCRIPT.approach_for_distance(distant_d))
	_expect(
		is_zero_approx(distant_approach),
		"8m 外圆点没落到常驻尺寸（approach=%.3f）—— 远处还是很大" % distant_approach,
		failures
	)
	# 单调：距离越远，尺寸档只能更小。写反了会变成「越走远越大」。
	var monotonic := true
	var previous := 2.0
	for index in range(0, 41):
		var value := float(DOT_SCRIPT.approach_for_distance(float(index) * 0.25))
		if value > previous + 0.0001:
			monotonic = false
			break
		previous = value
	_expect(monotonic, "尺寸档不是单调递减 —— 距离越远反而越大", failures)

	# 缩放通道要真的跟着尺寸档动：同一条 clarity 下喂近/喂远，必须量出两个不同的 scale。
	for _step in range(60):
		dot.call("set_approach_from_distance", distant_d)
		dot.call("update_state", 0.0, false, 0.033)
	var scaled_far := dot.scale.x
	for _step in range(60):
		dot.call("set_approach_from_distance", readable_d)
		dot.call("update_state", 0.0, false, 0.033)
	var scaled_near := dot.scale.x
	_expect(
		scaled_near > scaled_far + 0.1,
		"尺寸档没有驱动缩放（近=%.3f 远=%.3f）——「走近才变大」失效（缩放通道已失效）"
			% [scaled_near, scaled_far],
		failures
	)
	dot.queue_free()


## ⑧ 功能词抽取。用例全是场上真实存在的文案，改坏了会直接体现在玩家看到的牌子上。
func _validate_action_verb_extraction(failures: Array[String]) -> void:
	var cases := [
		["[E] 搜索 · SMALL", "搜索"],
		["[E] 搜索", "搜索"],
		["[E] 开启入口 · 选择命运", "开启入口"],
		["[E] 开启通道", "开启通道"],
		["[E] 切换中央灯", "切换中央灯"],
		["[E] 使用房间钥匙", "使用房间钥匙"],
		["[E] 交谈", "交谈"],
		["[E] 返回3D基地", "返回3D基地"],
		["[e] 搜索", "搜索"],
		["E 坐上座椅", "坐上座椅"],
		["E 放下伸缩梯", "放下伸缩梯"],
		["E 扶正座椅", "扶正座椅"],
		# 状态类文案：没有按键标记，不该冒出一个 (e) 前缀。
		["通道开启中…", ""],
		["通道已开启", ""],
		["已搜索", ""],
		["搜索中 · 请保持靠近", ""],
		["Boss 信号仍在干扰", ""],
		["", ""],
	]
	for entry in cases:
		var raw := str(entry[0])
		var expected := str(entry[1])
		var actual := str(DOT_SCRIPT.extract_action_verb(raw))
		_expect(
			actual == expected,
			"功能词抽取不对：「%s」→「%s」，期望「%s」" % [raw, actual, expected],
			failures
		)


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
	# 优先级给到远超场内真实 provider（最高 120）的档位：下面要验「聚焦那个圆点的按键牌」，
	# 不能让它被别的候选抢走焦点。
	near.configure("near_dot_probe", 900)
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

	# ⑦ 统一白点：场上所有圆点的色值必须完全一致，而且就是白。
	var near_color: Color = near_dot.get("color", Color.BLACK)
	var far_color: Color = far_dot.get("color", Color.BLACK)
	_expect(
		near_color == far_color,
		"场上圆点颜色不一致（near=%s far=%s）—— 不是统一白点" % [str(near_color), str(far_color)],
		failures
	)
	_expect(
		near_color == Color(1.0, 1.0, 1.0),
		"圆点不是白色（%s）" % str(near_color),
		failures
	)

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
	# ⑩ 尺寸档：近处圆点必须**明显**大于远处。这条才是主人要的「走近到可以操作后变大」
	# 在运行时层面的复核 —— 前面的几何断言只验了映射函数，这里验真实跑起来的圆点。
	# 近处那个还叠着聚焦放大与呼吸，只会更大，所以阈值给 0.15 已留足余量。
	var near_scale := float(near_dot.get("scale_multiplier", 0.0))
	var far_scale := float(far_dot.get("scale_multiplier", 0.0))
	_expect(
		near_scale > far_scale + 0.15,
		"近处圆点没有明显大于远处（近=%.3f 远=%.3f）——「走近才变大」没生效"
			% [near_scale, far_scale],
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

	# ⑧ 按键牌：聚焦那个圆点必须挂出从 prompt 抽出来的功能词。
	_expect(
		str(near_dot.get("action_verb", "")) == "搜索",
		"聚焦圆点没有抽出功能词（action_verb=「%s」）" % str(near_dot.get("action_verb", "")),
		failures
	)
	_expect(
		str(near_dot.get("key_hint_text", "")) == "(e) 搜索",
		"聚焦圆点的按键牌文案不对（「%s」，期望「(e) 搜索」）" % str(near_dot.get("key_hint_text", "")),
		failures
	)
	_expect(
		not str(far_dot.get("key_hint_text", "")).begins_with("(e)"),
		"未聚焦的圆点也挂了按键牌（「%s」）—— 牌子上只该有一个功能词" % str(far_dot.get("key_hint_text", "")),
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

	# 圆点数量应覆盖场上全部 provider（含真实关卡对象）。
	_expect(
		controller.get_interaction_dot_count() >= 3,
		"圆点数量少于已注册 provider（%d）" % controller.get_interaction_dot_count(),
		failures
	)

	# ⑨ 基地设施整体退回原版：它没有圆点，且自己的文字提示牌还能随聚焦显隐。
	await _validate_base_facility_reverted(tower, controller, failures)


## ⑨ 基地设施（BaseFacility3D 家族）被整体退回原版。两半都要验 ——
## 只验一半的话，「又给它挂回圆点」或「把它的提示牌永久藏起来」都会溜过去。
##
## 家族要验**两层**：父类 + 至少一个真实子类。豁免早年只按 resource_path 相等匹配，
## 子类当场漏网 —— 远征情报室的全息平台就是这么多出一个圆点的（主人 2026-10-04 指出）。
func _validate_base_facility_reverted(
	tower: TowerDescent3D, controller: PlayerInteractionController3D, failures: Array[String]
) -> void:
	# 先在源码层点名：路径写到别处去了，下面的行为断言只会给出一句含糊的
	# 「基地设施被挂上了圆点」，这里直接把「清单里没有这个路径」说清楚。
	var controller_source := FileAccess.get_file_as_string(
		"res://src/player3d/PlayerInteractionController3D.gd"
	)
	_expect(
		controller_source.contains(EXCLUDED_PROVIDER_SCRIPT),
		"控制器的圆点豁免清单里没有 %s" % EXCLUDED_PROVIDER_SCRIPT,
		failures
	)
	# 家族匹配是**沿基类链**走的，只按路径相等就够不上子类。这里静态确认那段逻辑还在
	# （匹配带变量的写法，避免被注释里那串同名文字蒙混过去）。
	_expect(
		controller_source.contains("cursor.get_base_script()"),
		"圆点豁免没有沿基类链匹配（缺 cursor.get_base_script()）—— 基地设施子类会漏网长出圆点",
		failures
	)

	await _validate_facility_family_has_no_dot(
		tower, controller, BaseFacility3D.new(), "基地设施父类", failures
	)
	# 真实子类：99F 远征情报室中央全息平台。它的 _ready 会 super()，所以子节点
	# （$NameLabel / $PromptLabel）必须入树前挂好，与父类同口径。
	await _validate_facility_family_has_no_dot(
		tower, controller, HologramExpeditionFacility3D.new(), "远征情报室全息平台（子类）", failures
	)


## 一个基地设施实例入树后必须**拿不到圆点**，且自己的黄色提示牌还能随聚焦显隐。
func _validate_facility_family_has_no_dot(
	tower: TowerDescent3D,
	controller: PlayerInteractionController3D,
	facility: BaseFacility3D,
	label: String,
	failures: Array[String]
) -> void:
	facility.display_name = "单元测试设施"
	# BaseFacility3D 用 @onready $NameLabel / $PromptLabel，所以子节点必须在入树前挂好。
	var name_label := Label3D.new()
	name_label.name = "NameLabel"
	facility.add_child(name_label)
	var prompt_label := Label3D.new()
	prompt_label.name = "PromptLabel"
	facility.add_child(prompt_label)
	facility.position = tower.player.global_position + Vector3(2.6, 0.0, 0.0)
	tower.add_child(facility)
	for _index in range(4):
		await get_tree().process_frame

	_expect(
		controller.get_interaction_dot_snapshot(facility).is_empty(),
		"%s被挂上了圆点 —— 会与它自己的黄色文字提示牌叠成双份提示" % label,
		failures
	)

	# 原版行为：聚焦且玩家在范围内 → 提示牌显示；退出聚焦 → 隐藏。
	facility.set("_player_in_range", true)
	facility.call("set_interaction_focus", {}, true)
	_expect(prompt_label.visible, "%s的文字提示牌没有随聚焦显示 —— 回退不完整" % label, failures)
	facility.call("set_interaction_focus", {}, false)
	_expect(not prompt_label.visible, "%s的文字提示牌退出聚焦后没有隐藏" % label, failures)

	facility.queue_free()
	await get_tree().process_frame


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
