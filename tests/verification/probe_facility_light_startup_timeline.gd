extends Node
## 探针：99F 基地开关「开启」的延迟时间线（业主 2026-09-24 指定）。
##
## 背景：开关点开后，设施自发光按 18 批铺开约 5 秒；而美术师手摆的原生
## OmniLight3D（`Blocks/Base/Art/基地美术灯光_可编辑/中央冷色主灯`）**不参与分批**，
## 由 BaseFixtureGlow3D.AUTHORED_ART_LIGHT_DELAY_SECONDS 统一延后 ≈2 秒一次点亮。
## 本探针把这条时间线逐帧量出来，防止延迟被改回「第一批就亮」或整条接线丢失。
##
## 判定：手摆美术灯的亮相时刻必须落在 EXPECTED_ART_MAIN_DELAY_* 区间内，
## 且玩法主灯仍按 RoomLightSwitch3D.STAGED_MAIN_LIGHT_START_SECONDS(4.5s) 亮。
##
## 运行：
##   godot --path . --scene res://tests/verification/probe_facility_light_startup_timeline.tscn

const TOWER_SCENE := "res://scenes/TowerDescent3D.tscn"
const ART_MAIN_NODE_NAME := "中央冷色主灯"
## 手摆美术灯的开启延迟容差带（设计值 2.0s；headless 帧粒度会带来零点几秒抖动）。
const EXPECTED_ART_MAIN_DELAY_MIN := 1.5
const EXPECTED_ART_MAIN_DELAY_MAX := 2.6
## 玩法主灯由开关在第 4.5 秒点亮，容差放大到 5.5s（headless 计时器粒度较粗）。
const EXPECTED_GAMEPLAY_MAIN_MAX := 5.6
const SAMPLE_TIMEOUT_SECONDS := 9.0

var _failures: Array[String] = []
var _t0 := 0


func _ready() -> void:
	var tower := (load(TOWER_SCENE) as PackedScene).instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	tower.force_enter_room_for_test("facility")
	var facility := (tower.get("_room_by_id") as Dictionary)["facility"] as DungeonRoom3D
	_check(facility != null, "样本哨兵：facility 房间存在")
	if facility == null:
		_finish()
		return
	facility.ensure_shell_built()
	facility.ensure_detail_built()
	await _settle(4)

	var art := facility.get_node_or_null("Art")
	var light_switch := facility.find_child("RoomLightSwitch3D", true, false) as RoomLightSwitch3D
	var main_light := facility.find_child("FacilityCeilingLight_Main", true, false) as WastelandLight3D
	var art_main := facility.find_child(ART_MAIN_NODE_NAME, true, false) as OmniLight3D
	_check(art != null, "样本哨兵：基地美术布局 Art 存在")
	_check(light_switch != null, "样本哨兵：基地墙面开关存在")
	_check(main_light != null, "样本哨兵：中央玩法顶灯存在")
	_check(art_main != null, "样本哨兵：手摆美术灯「%s」存在" % ART_MAIN_NODE_NAME)
	if art == null or light_switch == null or main_light == null or art_main == null:
		_finish()
		return

	var spills: Array = art.get("_controlled_spill_lights")
	var authored: Dictionary = art.get("_authored_art_light_visible")
	var snapshot: Dictionary = art.get_presentation_snapshot()
	print("  INFO spill_count=%d authored_art_lights=%d" % [
		spills.size(), int(snapshot.get("authored_art_lights", -1))
	])
	_check(
		authored.has(art_main.get_instance_id()),
		"手摆美术灯已登记进开关控制（_authored_art_light_visible）"
	)
	_check(
		float(snapshot.get("authored_art_light_delay_seconds", -1.0)) > 0.0,
		"手摆美术灯延迟常量已生效：%s" % str(snapshot.get("authored_art_light_delay_seconds"))
	)

	# 先关灯：关灯是瞬时的，不走启动序列。
	light_switch.set_light_on(false)
	await _settle(4)
	_check(not art_main.visible, "关灯后手摆美术灯立即熄灭（延迟只作用于开启）")
	_check(not main_light.is_light_enabled(), "关灯后中央玩法顶灯熄灭")

	# 再开灯：走玩家真实路径 toggle_light() → RoomLightSwitch3D._run_turn_on_sequence()
	_t0 = Time.get_ticks_msec()
	light_switch.toggle_light()
	print("  TIMELINE t=0.000 toggle_light()")
	var art_main_at := -1.0
	var gameplay_main_at := -1.0
	var elapsed := 0.0
	while elapsed < SAMPLE_TIMEOUT_SECONDS:
		await get_tree().process_frame
		elapsed = float(Time.get_ticks_msec() - _t0) / 1000.0
		if art_main.visible and art_main_at < 0.0:
			art_main_at = elapsed
			print("  TIMELINE t=%.3f 手摆美术灯「%s」亮" % [elapsed, ART_MAIN_NODE_NAME])
		if main_light.is_light_enabled() and gameplay_main_at < 0.0:
			gameplay_main_at = elapsed
			print("  TIMELINE t=%.3f 中央玩法顶灯亮" % elapsed)
		if art_main_at > 0.0 and gameplay_main_at > 0.0 and elapsed > gameplay_main_at + 0.5:
			break

	print(
		"  INFO art_main_on_at=%.3f gameplay_main_on_at=%.3f"
		% [art_main_at, gameplay_main_at]
	)
	_check(
		art_main_at >= EXPECTED_ART_MAIN_DELAY_MIN
		and art_main_at <= EXPECTED_ART_MAIN_DELAY_MAX,
		"手摆美术灯开启延迟落在 %.1f~%.1fs：实测 %.3fs"
		% [EXPECTED_ART_MAIN_DELAY_MIN, EXPECTED_ART_MAIN_DELAY_MAX, art_main_at]
	)
	_check(
		gameplay_main_at > 0.0 and gameplay_main_at <= EXPECTED_GAMEPLAY_MAIN_MAX,
		"中央玩法顶灯仍在 4.5s 档点亮：实测 %.3fs" % gameplay_main_at
	)
	_check(
		art_main_at < gameplay_main_at,
		"手摆美术灯先于中央玩法顶灯亮：%.3fs < %.3fs" % [art_main_at, gameplay_main_at]
	)
	_finish()


func _settle(frame_count: int) -> void:
	for _frame in range(frame_count):
		await get_tree().process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PROBE_OK   %s" % label)
	else:
		printerr("  PROBE_FAIL %s" % label)
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("PROBE_FACILITY_LIGHT_STARTUP_TIMELINE_OK")
		get_tree().quit(0)
	else:
		printerr(
			"PROBE_FACILITY_LIGHT_STARTUP_TIMELINE_FAILED 失败项=%d" % _failures.size()
		)
		get_tree().quit(1)
