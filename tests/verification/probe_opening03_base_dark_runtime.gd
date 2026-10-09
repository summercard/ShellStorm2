extends Node
## 探针：真实塔楼里跑一次「开场03」——验证端到端接线与灯态语义。
##
## 要钉死的事实：
##   1. 玩家走到 99F 基地东门内侧时，nar_tower_opening_03_base_dark 真的起播。
##   2. 起播瞬间基地转关灯（scene.light persist:true）。
##   3. 运镜枢轴解析到东墙灯开关锚点（camera.pivot=light_switch / preferred_entry=east），
##      且相机到锚点的距离等于剧本声明的 distance。
##   4. 收口后输入归还、相机归还 —— 但**灯仍保持关闭**（persist 的意义）。
##
## 运行：
##   godot --headless --path . res://tests/verification/probe_opening03_base_dark_runtime.tscn

const SEED := 990099
const NARRATIVE_ID := "nar_tower_opening_03_base_dark"
## 与剧本 trigger.point_offset 保持同一口径（相对房间中心）。
const TRIGGER_LOCAL := Vector3(10.0, 0.0, -2.5)
const CAMERA_DECLARED_DISTANCE := 7.5
## 采样「运镜已到位」的时刻：camera.focus 在 3.6s 起、时长 1.4s ⇒ 5.0s 后应稳定。
const SAMPLE_CAMERA_AT := 5.6

var _failures: Array[String] = []
var _checks := 0


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
	var facility := room_by_id.get("facility") as DungeonRoom3D
	_check(facility != null, "样本哨兵：facility 房间存在")
	if facility == null:
		_finish()
		return
	facility.call("set_stream_state", 2)
	await _settle()

	var player := tower.get("player") as Player3D
	_check(player != null, "样本哨兵：玩家存在")
	if player == null:
		_finish()
		return

	print("\n########## BEFORE ##########")
	print("-- light_on = %s" % str(facility.call("is_room_light_on")))
	print("-- player   = %s" % str(player.global_position))
	print("-- director active = '%s'" % str(NarrativeDirector.active_id()))
	_check(facility.call("is_room_light_on"), "哨兵：基地默认是亮的（活契约）")

	# 走到东门内侧：把玩家放到触发点（房间局部 12.5 / -2.5），等位置轮询命中。
	var trigger_world := facility.to_global(TRIGGER_LOCAL)
	player.global_position = trigger_world
	await _settle()
	for i in 12:
		player.global_position = trigger_world
		await get_tree().process_frame
		if NarrativeDirector.active_id() == NARRATIVE_ID:
			break

	print("\n########## 起播瞬间 ##########")
	print("-- director active = '%s'" % str(NarrativeDirector.active_id()))
	_check(
		NarrativeDirector.active_id() == NARRATIVE_ID,
		"走到基地东门内侧触发了开场03"
	)
	print("-- light_on = %s  (期望 false)" % str(facility.call("is_room_light_on")))
	_check(not facility.call("is_room_light_on"), "起播后基地转为关灯（persist 生效）")
	_check(
		NarrativeDirector.is_player_input_locked(),
		"演出期间玩家输入被独占"
	)

	# 推进到「运镜已到位」的时刻。
	await _advance_to(NarrativeDirector, SAMPLE_CAMERA_AT)

	print("\n########## 运镜到位（剧本 t≈%.1fs） ##########" % SAMPLE_CAMERA_AT)
	var anchor: Variant = facility.call("get_narrative_light_switch_anchor", "east")
	var anchor_pos: Vector3 = (anchor as Dictionary)["position"]
	print("-- pivot mode/room/entry = %s / %s / %s" % [
		str(NarrativeDirector._adapter.get("_camera_pivot_mode")),
		str(NarrativeDirector._adapter.get("_camera_pivot_room_id")),
		str(NarrativeDirector._adapter.get("_camera_pivot_preferred_entry")),
	])
	_check(
		str(NarrativeDirector._adapter.get("_camera_pivot_mode")) == "light_switch"
		and str(NarrativeDirector._adapter.get("_camera_pivot_room_id")) == "facility"
		and str(NarrativeDirector._adapter.get("_camera_pivot_preferred_entry")) == "east",
		"相机枢轴解析为基地东墙灯开关"
	)
	_check(
		NarrativeDirector.is_camera_override_active(),
		"演出期间相机由叙事接管"
	)
	var camera: Camera3D = player.camera
	var measured_distance := camera.global_position.distance_to(anchor_pos)
	print("-- east anchor = %s" % str(anchor_pos))
	print("-- camera pos  = %s" % str(camera.global_position))
	print("-- camera->anchor = %.3f m  (剧本声明 %.1f)" % [
		measured_distance, CAMERA_DECLARED_DISTANCE
	])
	_check(
		absf(measured_distance - CAMERA_DECLARED_DISTANCE) < 0.4,
		"相机确实拉近到开关锚点、距离等于剧本 distance"
	)

	# 等剧本跑完。
	var waited := SAMPLE_CAMERA_AT
	while waited < 14.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if NarrativeDirector.active_id().is_empty():
			break

	print("\n########## AFTER ##########")
	print("-- director active = '%s'" % str(NarrativeDirector.active_id()))
	print("-- light_on = %s  (期望 false：persist 不还原)" % str(facility.call("is_room_light_on")))
	print("-- camera override = %s" % str(NarrativeDirector.is_camera_override_active()))
	print("-- player input locked = %s" % str(NarrativeDirector.is_player_input_locked()))
	_check(NarrativeDirector.active_id().is_empty(), "剧本已在 duration 收口")
	_check(not facility.call("is_room_light_on"), "收口后基地仍保持关灯（persist）")
	_check(
		not NarrativeDirector.is_camera_override_active(),
		"收口后相机归还给玩法镜头"
	)
	_check(
		not NarrativeDirector.is_player_input_locked(),
		"收口后玩家输入归还"
	)

	print("\n########## DISPATCH LOG ##########")
	for line in NarrativeDirector.dispatch_log():
		print("   %s" % line)
	print("\n########## DIAGNOSTICS ##########")
	for line in NarrativeDirector.diagnostics():
		print("   %s" % line)

	_finish()


## 推进到剧本时间 >= target 秒（用导演自己的 active_time，避免被帧率影响）。
func _advance_to(director: Node, target: float) -> void:
	var guard := 0
	while guard < 3000:
		guard += 1
		await get_tree().process_frame
		if director.active_id().is_empty():
			return
		if director.active_time() >= target:
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
		print("\nPROBE_OPENING03_BASE_DARK_RUNTIME_OK checks=%d" % _checks)
		get_tree().quit(0)
	else:
		printerr(
			"\nPROBE_OPENING03_BASE_DARK_RUNTIME_FAILED checks=%d failures=%d"
			% [_checks, _failures.size()]
		)
		get_tree().quit(1)
