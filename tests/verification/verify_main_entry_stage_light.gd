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
	await _verify_stage_removed_on_start(failures)
	await _verify_stage_removed_on_skip(failures)
	await _verify_toggle_after_game_started(failures)
	await _verify_get_active_entry(failures)
	if failures.is_empty():
		print("MAIN_ENTRY_STAGE_LIGHT_OK: beam+pool geometry-only, off by default after entry, re-openable anytime")
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
	# 这一条是关键：两件东西必须是可见几何，不能是 Light3D。
	_expect(
		int(snapshot.get("intro_stage_light_count", -1)) == 0,
		"舞台灯容器里混入了 Light3D（会真的照亮基地，而不只是可见光柱）",
		failures
	)
	var stage := player.get_node_or_null(STAGE_NODE_NAME) as Node3D
	if stage == null:
		failures.append("舞台灯没有挂在角色节点下（应随角色自动跟随，而不是每帧同步）")
		_teardown(entry, player)
		return
	_expect(bool(stage.get_meta("main_entry_only", false)), "舞台灯没有标记 main_entry_only", failures)
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
	_expect(
		_uses_additive_unshaded_shader(pool),
		"光斑材质必须是叠加混合 + unshaded",
		failures
	)
	# 几何对位：锥底半径 == 光斑半径，锥顶收在展示灯高度上。
	var beam_mesh := beam.mesh as CylinderMesh
	var pool_mesh := pool.mesh as PlaneMesh
	if beam_mesh == null or pool_mesh == null:
		failures.append("光柱/光斑网格类型不是 CylinderMesh / PlaneMesh")
		_teardown(entry, player)
		return
	_expect(
		is_equal_approx(beam_mesh.bottom_radius, MainEntryScreen3D.STAGE_POOL_RADIUS_M),
		"光柱底半径与光斑半径不一致（会露出错位的亮圈）",
		failures
	)
	_expect(
		is_equal_approx(pool_mesh.size.x, MainEntryScreen3D.STAGE_POOL_RADIUS_M * 2.0),
		"光斑直径不等于两倍半径",
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


func _verify_stage_removed_on_start(failures: Array[String]) -> void:
	var ctx := await _present_entry(failures)
	if ctx.is_empty():
		return
	var entry: MainEntryScreen3D = ctx["entry"]
	var player: Player3D = ctx["player"]
	entry.start_game()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(
		not bool(entry.get_entry_snapshot().get("intro_stage_active", true)),
		"点击开始游戏后舞台灯仍在",
		failures
	)
	_expect(not _tree_has_stage_light(), "点击开始游戏后场景里仍残留舞台灯节点", failures)
	_teardown(entry, player)


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
