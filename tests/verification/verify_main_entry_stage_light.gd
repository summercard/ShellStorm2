extends Node
## 开场页舞台灯专项。
##
## 这条验收钉的是几件容易悄悄退化的事：
##   1. 光柱/光斑不能退化成真实 Light3D —— 一旦混进去就会真的照亮基地，
##      而画面上"看起来差不多"，肉眼查不出来。
##   2. 光斑半径必须等于光柱底半径 —— 改一边忘另一边会露出错位的亮圈。
##   3. 进游戏（start_game / skip_to_gameplay / 节点异常卸载）后默认必须释放干净，
##      否则它会跟着玩家进基地，成为一盏永远打在天花板上的灯。
##   4. 关掉之后必须能再开回来：这是「随时开」的契约，不能是一次性的。

const ENTRY_SCENE := preload("res://scenes/ui/MainEntryScreen3D.tscn")
const PLAYER_SCENE := preload("res://scenes/Player3D.tscn")
const STAGE_NODE_NAME := "MainEntryStageLight"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures: Array[String] = []
	await _verify_stage_light(failures)
	await _verify_entry_vignette(failures)
	await _verify_dismiss_animation(failures)
	await _verify_stage_removed_on_start(failures)
	await _verify_stage_removed_on_skip(failures)
	await _verify_toggle_after_game_started(failures)
	await _verify_get_active_entry(failures)
	if failures.is_empty():
		print("MAIN_ENTRY_STAGE_LIGHT_OK: geometry-only beam+pool+keylight, animated collapse on entry, re-openable anytime")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("MAIN_ENTRY_STAGE_LIGHT_FAIL: %s" % failure)
	get_tree().quit(1)


func _verify_stage_light(failures: Array[String]) -> void:
	var ctx := await _present_entry(failures)
	if ctx.is_empty():
		return
	var entry: MainEntryScreen3D = ctx["entry"]
	var player: Player3D = ctx["player"]
	var snapshot: Dictionary = entry.get_entry_snapshot()
	_expect(bool(snapshot.get("intro_stage_active", false)), "展示期间没有舞台灯光柱容器", failures)
	_expect(bool(snapshot.get("intro_stage_beam_active", false)), "展示期间没有光柱 StageBeam", failures)
	_expect(bool(snapshot.get("intro_stage_pool_active", false)), "展示期间没有地面光斑 StagePool", failures)
	# 容器里允许且只允许**一盏**真实光源：StageKeyLight。
	# 它的职责是真正照亮地砖（靶场 WastelandLight3D 的第一层）。
	# 只画发光贴片不点灯，地面受光不变，看起来就是一张圆纸 —— 这正是之前发灰的根因。
	# 安全边界由「只许一盏 + 必须标记 main_entry_only + 进游戏必删」三条共同守住。
	_expect(
		int(snapshot.get("intro_stage_light_count", -1)) == 1,
		"舞台灯容器里的真实光源数量应为 1（仅 StageKeyLight），实际不是",
		failures
	)
	var stage := player.get_node_or_null(STAGE_NODE_NAME) as Node3D
	if stage == null:
		failures.append("舞台灯没有挂在角色节点下（应随角色自动跟随，而不是每帧同步）")
		_teardown(entry, player)
		return
	_expect(bool(stage.get_meta("main_entry_only", false)), "舞台灯没有标记 main_entry_only", failures)
	# 那一盏必须叫 StageKeyLight，且照 WORLD 层（否则照不亮地砖）。
	var key_light := stage.get_node_or_null("StageKeyLight") as OmniLight3D
	_expect(key_light != null, "缺少 StageKeyLight（真正照亮地面的那盏）", failures)
	if key_light != null:
		_expect(
			(key_light.light_cull_mask & GameDesignConfig.RENDER_LAYER_WORLD) != 0,
			"StageKeyLight 没有照 WORLD 层（照不亮地砖，地面仍不会有光斑）",
			failures
		)
		_expect(
			bool(key_light.get_meta("main_entry_only", false)),
			"StageKeyLight 没有标记 main_entry_only（进游戏可能漏光）",
			failures
		)
		_expect(not key_light.shadow_enabled, "StageKeyLight 不应投影", failures)
	var beam := stage.get_node_or_null("StageBeam") as MeshInstance3D
	var pool := stage.get_node_or_null("StagePool") as MeshInstance3D
	if beam == null or pool == null:
		failures.append("舞台灯缺 StageBeam 或 StagePool 子节点")
		_teardown(entry, player)
		return
	_expect(beam.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "光柱不应投影", failures)
	_expect(pool.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "光斑不应投影", failures)
	_expect(
		_uses_additive_unshaded_shader(beam),
		"光柱材质必须是叠加混合 + unshaded（否则会被当作实体表面明暗着色）",
		failures
	)
	# 光斑材质：StandardMaterial3D + unshaded + alpha 透明（与靶场 LightPool 同构）。
	# 注意这里**不检查 emission** —— unshaded 会跳过光照阶段，emission 根本不参与合成，
	# 配了也是死参数（实测倍率 2.7→10.0 画面零变化）。亮度只由 albedo 决定。
	var pool_material := pool.get_active_material(0) as StandardMaterial3D
	if pool_material == null:
		pool_material = pool.material_override as StandardMaterial3D
	_expect(pool_material != null, "光斑材质不是 StandardMaterial3D（应与靶场 LightPool 同款）", failures)
	if pool_material != null:
		_expect(
			pool_material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
			"光斑材质不是 unshaded",
			failures
		)
		_expect(
			is_equal_approx(pool_material.albedo_color.a, MainEntryScreen3D.STAGE_POOL_ALPHA),
			"光斑 alpha 与 STAGE_POOL_ALPHA 不一致",
			failures
		)
		# 这是"壳/淡"的判据：albedo 必须等于光斑专用色，而不是偏暗的舞台暖橙。
		var pool_color := MainEntryScreen3D.STAGE_POOL_COLOR
		_expect(
			pool_material.albedo_color.is_equal_approx(
				Color(pool_color.r, pool_color.g, pool_color.b, MainEntryScreen3D.STAGE_POOL_ALPHA)
			),
			"光斑 albedo 不等于 STAGE_POOL_COLOR（会导致光斑发暗发灰）",
			failures
		)
	# 几何对位：锥底半径 == 光斑半径，锥顶收在展示灯高度上。
	var beam_mesh := beam.mesh as CylinderMesh
	var pool_mesh := pool.mesh as CylinderMesh
	if beam_mesh == null or pool_mesh == null:
		failures.append("光柱/光斑网格类型不是 CylinderMesh")
		_teardown(entry, player)
		return
	# 光柱底半径不再强制等于光斑半径：两者职责不同，光斑负责"地面被照亮"的范围、
	# 光柱只负责"一束光打下来"的形态。共用同一个值会把锥体一起撑宽，
	# 近景下 5.2m 的锥底到 2.3m 就糊满上半屏了。
	# 要守的是「光柱不得比光斑宽」—— 那样会在光斑外围留下没有落点的悬空锥。
	_expect(
		beam_mesh.bottom_radius <= MainEntryScreen3D.STAGE_POOL_RADIUS_M + 0.001,
		"光柱底半径大于光斑半径（锥体落在光斑之外，会露出悬空的锥脚）",
		failures
	)
	_expect(
		beam_mesh.bottom_radius >= MainEntryScreen3D.STAGE_POOL_RADIUS_M * 0.35,
		"光柱底半径过小（锥体细得像根棍，失去舞台灯形态）",
		failures
	)
	_expect(
		is_equal_approx(pool_mesh.bottom_radius, MainEntryScreen3D.STAGE_POOL_RADIUS_M),
		"光斑底半径不等于 STAGE_POOL_RADIUS_M",
		failures
	)
	_expect(
		is_equal_approx(beam_mesh.height, MainEntryScreen3D.INTRO_SPOTLIGHT_HEIGHT_M),
		"光柱高度不等于展示灯高度",
		failures
	)
	# 落地与顶部：光斑贴脚、光柱顶端对齐展示灯。
	var feet := player.global_position
	_expect(
		absf(pool.global_position.y - (feet.y + MainEntryScreen3D.STAGE_POOL_LIFT_M)) < 0.001,
		"光斑没有贴在角色脚下",
		failures
	)
	var beam_top_y := beam.global_position.y + beam_mesh.height * 0.5
	_expect(
		absf(beam_top_y - (feet.y + MainEntryScreen3D.INTRO_SPOTLIGHT_HEIGHT_M)) < 0.001,
		"光柱顶端没有对齐展示灯高度",
		failures
	)
	var horizontal_offset := Vector2(
		pool.global_position.x - feet.x, pool.global_position.z - feet.z
	).length()
	_expect(horizontal_offset < 0.001, "光斑没有居中在角色脚下", failures)
	_teardown(entry, player)


func _verify_get_active_entry(failures: Array[String]) -> void:
	var ctx := await _present_entry(failures)
	if ctx.is_empty():
		return
	var entry: MainEntryScreen3D = ctx["entry"]
	var player: Player3D = ctx["player"]
	_expect(
		MainEntryScreen3D.get_active_entry() == entry,
		"get_active_entry() 没有返回当前活着的入口界面（游戏内将拿不到舞台灯宿主）",
		failures
	)
	_teardown(entry, player)
	await get_tree().process_frame
	_expect(
		MainEntryScreen3D.get_active_entry() == null,
		"入口界面释放后 get_active_entry() 仍返回失效实例",
		failures
	)


## 「随时开」的核心契约：进游戏（已销毁）之后还能重新开出来，并且再关得掉。
func _verify_toggle_after_game_started(failures: Array[String]) -> void:
	var ctx := await _present_entry(failures)
	if ctx.is_empty():
		return
	var entry: MainEntryScreen3D = ctx["entry"]
	var player: Player3D = ctx["player"]
	entry.start_game()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not entry.is_stage_light_enabled(), "进游戏后舞台灯没有默认关闭", failures)
	var opened := entry.set_stage_light_enabled(true)
	await get_tree().process_frame
	_expect(opened, "进游戏后 set_stage_light_enabled(true) 返回失败", failures)
	_expect(entry.is_stage_light_enabled(), "进游戏后无法把舞台灯开回来", failures)
	_expect(_tree_has_stage_light(), "开回来之后场景里找不到舞台灯节点", failures)
	_expect(
		player.get_node_or_null(STAGE_NODE_NAME) != null,
		"重新开启的舞台灯没有挂到角色节点下",
		failures
	)
	entry.set_stage_light_enabled(false)
	await get_tree().process_frame
	_expect(not entry.is_stage_light_enabled(), "set_stage_light_enabled(false) 之后仍报告为开启", failures)
	_expect(not _tree_has_stage_light(), "关掉之后场景里仍残留舞台灯节点", failures)
	# 反复开关不应累积节点：开→关→开之后，角色下必须只有一个。
	entry.set_stage_light_enabled(true)
	entry.set_stage_light_enabled(false)
	entry.set_stage_light_enabled(true)
	await get_tree().process_frame
	_expect(
		_count_stage_lights_in_tree() == 1,
		"反复开关后舞台灯节点发生累积（应始终只有 1 个）",
		failures
	)
	_teardown(entry, player)


## 开场页压暗必须是「中心透、四边暗」的径向渐变。
## 原来是一整块均匀 alpha 0.46 的深蓝盖住全屏 —— 实测把画面饱和度从 0.269 拉到 0.226、
## 无彩像素从 27.8% 拉到 34.4%，是"灰蒙蒙"的主要来源。这条断言防它被改回去。
func _verify_entry_vignette(failures: Array[String]) -> void:
	var ctx := await _present_entry(failures)
	if ctx.is_empty():
		return
	var entry: MainEntryScreen3D = ctx["entry"]
	var player: Player3D = ctx["player"]
	var backdrop := entry.get_node_or_null("Screen/Backdrop") as ColorRect
	if backdrop == null:
		failures.append("开场页缺少 Backdrop 节点（节点路径被改动）")
		_teardown(entry, player)
		return
	var material := backdrop.material as ShaderMaterial
	_expect(material != null, "Backdrop 没有径向渐变材质（退回成整块均匀压暗）", failures)
	if material != null:
		var center := float(material.get_shader_parameter("center_alpha"))
		var edge := float(material.get_shader_parameter("edge_alpha"))
		var inner := float(material.get_shader_parameter("inner_radius"))
		var outer := float(material.get_shader_parameter("outer_radius"))
		_expect(
			is_equal_approx(center, MainEntryScreen3D.ENTRY_VIGNETTE_CENTER_ALPHA),
			"压暗中心 alpha 与常量不一致",
			failures
		)
		_expect(
			is_equal_approx(edge, MainEntryScreen3D.ENTRY_VIGNETTE_EDGE_ALPHA),
			"压暗边缘 alpha 与常量不一致",
			failures
		)
		# 核心契约：中心必须比边缘透，否则就不是暗角而是均匀蒙层。
		_expect(
			center < edge - 0.05,
			"压暗中心不比边缘更透（说明又退回了均匀蒙层，画面会发灰）",
			failures
		)
		_expect(inner < outer, "暗角 inner_radius 必须小于 outer_radius", failures)
		_expect(center <= 0.15, "压暗中心 alpha 偏高（中心会重新发灰）", failures)
	_teardown(entry, player)


func _verify_stage_removed_on_start(failures: Array[String]) -> void:
	var ctx := await _present_entry(failures)
	if ctx.is_empty():
		return
	var entry: MainEntryScreen3D = ctx["entry"]
	var player: Player3D = ctx["player"]
	entry.start_game()
	# start_game 会先播收束动画（约 0.3s），所以要等动画结束再判「已清干净」。
	await _wait_dismiss_animation()
	_expect(
		not bool(entry.get_entry_snapshot().get("intro_stage_active", true)),
		"点击开始游戏后舞台灯仍在",
		failures
	)
	_expect(not _tree_has_stage_light(), "点击开始游戏后场景里仍残留舞台灯节点", failures)
	_teardown(entry, player)


## 收灯动画存在性：这是主人明确要求的「很快但必须有」。
## 光靠「最终消失了」无法区分「有动画」和「直接硬删」，所以必须抓过程中间态。
func _verify_dismiss_animation(failures: Array[String]) -> void:
	var ctx := await _present_entry(failures)
	if ctx.is_empty():
		return
	var entry: MainEntryScreen3D = ctx["entry"]
	var player: Player3D = ctx["player"]
	var stage_before := _find_stage_light()
	if stage_before == null:
		failures.append("收灯动画前置条件失败：展示期没有舞台灯节点")
		_teardown(entry, player)
		return
	var beam_before := stage_before.get_node_or_null("StageBeam") as MeshInstance3D
	var pool_before := stage_before.get_node_or_null("StagePool") as MeshInstance3D
	if beam_before == null or pool_before == null:
		failures.append("收灯动画前置条件失败：缺 StageBeam 或 StagePool")
		_teardown(entry, player)
		return
	_expect(
		is_equal_approx(beam_before.scale.x, 1.0),
		"展示期锥体缩放不是 1.0",
		failures
	)
	entry.start_game()
	# ① 立刻检查：节点必须还在。若这里就没了，说明是硬切而非收束。
	if not _tree_has_stage_light():
		failures.append("start_game 后舞台灯立刻消失 —— 没有收束过程，是一次硬切")
		_teardown(entry, player)
		return
	var stage_mid := _find_stage_light()
	# ② 等动画走到约一半，缩放必须已经变小（证明在连续推进，不是最后一帧才跳变）。
	await get_tree().create_timer(MainEntryScreen3D.STAGE_DISMISS_DURATION_S * 0.5).timeout
	if not is_instance_valid(stage_mid):
		failures.append("舞台灯在收灯动画中途就被释放了 —— 动画没有播完")
	else:
		var beam_mid := stage_mid.get_node_or_null("StageBeam") as MeshInstance3D
		var pool_mid := stage_mid.get_node_or_null("StagePool") as MeshInstance3D
		if beam_mid != null:
			_expect(
				beam_mid.scale.x < 0.98,
				"收灯动画中途锥体没有收缩（缩放仍接近 1.0）",
				failures
			)
			_expect(
				beam_mid.scale.x > MainEntryScreen3D.STAGE_DISMISS_END_SCALE,
				"收灯动画中途锥体已缩到终点（说明是瞬间缩完再等，不是渐进）",
				failures
			)
		if pool_mid != null:
			_expect(
				pool_mid.scale.x < 0.98,
				"收灯动画中途地面光斑没有收缩",
				failures
			)
	# ③ 动画结束后必须彻底消失。
	await _wait_dismiss_animation()
	_expect(not _tree_has_stage_light(), "收灯动画结束后场景里仍残留舞台灯节点", failures)
	_teardown(entry, player)


func _wait_dismiss_animation() -> void:
	# 多等 0.1s 余量：动画结束到 queue_free 实际生效之间还有一帧延迟。
	await get_tree().create_timer(MainEntryScreen3D.STAGE_DISMISS_DURATION_S + 0.10).timeout


func _find_stage_light() -> Node3D:
	for node in get_tree().root.find_children("*", "Node3D", true, false):
		if node.name == STAGE_NODE_NAME:
			return node as Node3D
	return null


func _verify_stage_removed_on_skip(failures: Array[String]) -> void:
	var ctx := await _present_entry(failures)
	if ctx.is_empty():
		return
	var entry: MainEntryScreen3D = ctx["entry"]
	var player: Player3D = ctx["player"]
	entry.skip_to_gameplay()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(
		not bool(entry.get_entry_snapshot().get("intro_stage_active", true)),
		"直接进入玩法后舞台灯仍在",
		failures
	)
	_expect(not _tree_has_stage_light(), "直接进入玩法后场景里仍残留舞台灯节点", failures)
	_teardown(entry, player)


func _present_entry(failures: Array[String]) -> Dictionary:
	var player := PLAYER_SCENE.instantiate() as Player3D
	add_child(player)
	# 这里没有地板，Player3D 会在 _physics_process 里一直自由下落。
	# 不冻结的话，「光斑贴在脚下」这类位置断言会跟物理步抖动互相打架 ——
	# 测的是灯跟着角色走，不是在测重力。
	player.set_physics_process(false)
	await get_tree().process_frame
	var entry := ENTRY_SCENE.instantiate() as MainEntryScreen3D
	entry.auto_present_when_player_found = false
	add_child(entry)
	await get_tree().process_frame
	if not entry.present(player):
		failures.append("开场页没有成功接管展示")
		entry.queue_free()
		player.queue_free()
		return {}
	await get_tree().process_frame
	return {"entry": entry, "player": player}


func _teardown(entry: MainEntryScreen3D, player: Player3D) -> void:
	if is_instance_valid(entry):
		entry.call("_remove_intro_spotlight")
		entry.queue_free()
	if is_instance_valid(player):
		player.queue_free()


func _tree_has_stage_light() -> bool:
	return _count_stage_lights_in_tree() > 0


func _count_stage_lights_in_tree() -> int:
	var count := 0
	for node in get_tree().root.find_children("*", "Node3D", true, false):
		if node.name == STAGE_NODE_NAME:
			count += 1
	return count


func _uses_additive_unshaded_shader(instance: MeshInstance3D) -> bool:
	var material := instance.material_override as ShaderMaterial
	if material == null or material.shader == null:
		return false
	var code := material.shader.code
	return code.contains("blend_add") and code.contains("unshaded")


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
