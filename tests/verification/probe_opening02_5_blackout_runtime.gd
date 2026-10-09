extends Node
## 探针：真实塔楼里验证「开场 2.5 → 开场 03」这条提前关灯链，并钉死
## 「关灯之后到剧本03 收口之间，基地灯一次都没有再亮过」（消除先亮后暗的割裂感）。
##
## 要钉死的事实：
##   1. 初始：99F 基地灯是亮的（默认契约）。
##   2. 玩家经过 98F→99F 楼梯间中段折角平台时，剧本 2.5 起播、基地灯立即转暗。
##   3. 从那一刻起（含剧本 03 起播与收口），逐帧采样灯态**从未回到亮**。
##   4. 剧本 2.5 不锁输入（玩家正在上楼，不能被定住）。
##
## 运行：
##   godot --headless --path . res://tests/verification/probe_opening02_5_blackout_runtime.tscn

const SEED := 990099
const BLACKOUT_ID := "nar_tower_opening_02_5_stairwell_blackout"
const DARK_ID := "nar_tower_opening_03_base_dark"
## 楼梯间中段折角平台**几何中心**（与剧本 trigger.point 同一口径）。
const STAIR_MID := Vector3(42.501, -18.0, -17.0637)
## 剧本03 触发点：facility 房局部 (10, 0, -2.5)。
const DARK_TRIGGER_LOCAL := Vector3(10.0, 0.0, -2.5)

var _failures: Array[String] = []
var _checks := 0
var _facility: DungeonRoom3D = null
var _lights_ever_on := false
var _light_samples := 0


func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if scene == null:
		print("PROBE_FAIL: TowerDescent3D.tscn 加载失败")
		get_tree().quit(1)
		return
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED
	add_child(tower)
	await _settle()

	var room_by_id: Dictionary = tower.get("_room_by_id")
	_facility = room_by_id.get("facility") as DungeonRoom3D
	var player := tower.get("player") as Player3D
	_check(_facility != null and player != null, "样本哨兵：facility 与玩家存在")
	if _facility == null or player == null:
		_finish()
		return

	print("\n########## BEFORE ##########")
	print("-- light_on = %s" % str(_facility.call("is_room_light_on")))
	_check(_facility.call("is_room_light_on"), "初始：99F 基地灯是亮的（默认契约）")

	# —— 第一步：站上楼梯间中段平台，等位置轮询命中剧本 2.5 ——
	var stair_world := STAIR_MID + Vector3.UP * 0.05
	player.global_position = stair_world
	await _settle()
	var fired_blackout := false
	for i in 20:
		player.global_position = stair_world
		player.velocity = Vector3.ZERO
		await get_tree().process_frame
		if NarrativeDirector.active_id() == BLACKOUT_ID:
			fired_blackout = true
			break

	print("\n########## 楼梯间中段 ##########")
	print("-- director active = '%s'" % str(NarrativeDirector.active_id()))
	print("-- input locked = %s  (期望 false：不能定住正在上楼的玩家)" % str(
		NarrativeDirector.is_player_input_locked()
	))
	_check(fired_blackout, "经过楼梯间中段触发了剧本 2.5")
	_check(
		not NarrativeDirector.is_player_input_locked(),
		"剧本 2.5 不锁输入（玩家在楼梯上不受干扰）"
	)
	# 触发那一帧 cue 还没派发（导演在下一帧 _process 才派发），所以给几帧观察窗；
	# 「立即转暗」的口径 = 0.2s 内完成，而不是同一帧。
	var dark_delay_frames := -1
	for i in 12:
		await get_tree().process_frame
		if not bool(_facility.call("is_room_light_on")):
			dark_delay_frames = i + 1
			break
	print("-- 触发后第 %d 帧转暗，light_on = %s" % [
		dark_delay_frames, str(_facility.call("is_room_light_on"))
	])
	_check(
		dark_delay_frames > 0 and not _facility.call("is_room_light_on"),
		"剧本 2.5 起播后基地在 0.2s 内转暗"
	)

	# 等 2.5 收口（期间持续采样灯态）。
	await _wait_until_idle_sampling(4.0)
	print("-- 2.5 收口后 light_on = %s  (期望 false)" % str(_facility.call("is_room_light_on")))
	_check(not _facility.call("is_room_light_on"), "剧本 2.5 收口后灯仍暗（persist）")

	# —— 第二步：走到基地东门内侧，触发剧本 03，全程逐帧采样灯态 ——
	var dark_world := _facility.to_global(DARK_TRIGGER_LOCAL)
	var fired_dark := false
	for i in 40:
		player.global_position = dark_world
		player.velocity = Vector3.ZERO
		await get_tree().process_frame
		_sample_light()
		if NarrativeDirector.active_id() == DARK_ID:
			fired_dark = true
			break

	print("\n########## 基地东门内侧 ##########")
	print("-- director active = '%s'" % str(NarrativeDirector.active_id()))
	print("-- light_on = %s  (期望 false：03 重放关灯是幂等的，不产生任何亮变化)" % str(
		_facility.call("is_room_light_on")
	))
	_check(fired_dark, "走到基地东门内侧触发了剧本 03")
	_check(not _facility.call("is_room_light_on"), "剧本 03 起播时灯已是暗的")
	_check(
		not _lights_ever_on,
		"从剧本 2.5 起播到剧本 03 起播之间，灯一次都没有再亮过（无先亮后暗）"
	)

	# 等 03 收口（期间继续采样），再确认灯保持暗。
	await _wait_until_idle_sampling(14.0)
	print("\n########## 03 收口后 ##########")
	print("-- director active = '%s'" % str(NarrativeDirector.active_id()))
	print("-- light_on = %s  (期望 false)" % str(_facility.call("is_room_light_on")))
	print("-- 采样帧数 = %d，其中「亮」出现 = %s" % [
		_light_samples, str(_lights_ever_on)
	])
	_check(not _facility.call("is_room_light_on"), "03 收口后基地仍保持暗（等玩家按开关）")

	print("\n########## DISPATCH LOG ##########")
	for line in NarrativeDirector.dispatch_log():
		print("   %s" % line)
	print("\n########## DIAGNOSTICS ##########")
	for line in NarrativeDirector.diagnostics():
		print("   %s" % line)

	_finish()


func _sample_light() -> void:
	if _facility == null:
		return
	_light_samples += 1
	if bool(_facility.call("is_room_light_on")):
		_lights_ever_on = true


func _wait_until_idle_sampling(timeout: float) -> void:
	var waited := 0.0
	while waited < timeout:
		await get_tree().process_frame
		waited += get_process_delta_time()
		_sample_light()
		if NarrativeDirector.active_id().is_empty():
			return


func _settle() -> void:
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PROBE_OK   %s" % label)
	else:
		printerr("  PROBE_FAIL %s" % label)
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("\nPROBE_OPENING02_5_BLACKOUT_RUNTIME_OK checks=%d" % _checks)
		get_tree().quit(0)
	else:
		printerr(
			"\nPROBE_OPENING02_5_BLACKOUT_RUNTIME_FAILED checks=%d failures=%d"
			% [_checks, _failures.size()]
		)
		get_tree().quit(1)
