extends Node
## 窄接口专项：正常Autoload入口，启动前隔离userdata，不生成关卡。
const DUNGEON = preload("res://src/world3d/Dungeon3D.gd")
const RING = preload("res://src/ui/EncounterCountdownRing.gd")
const OVERLAY = preload("res://src/ui/EncounterAlertOverlay.gd")
const DIRECTOR = preload("res://src/world3d/EncounterEventDirector3D.gd")
const HOST = preload("res://src/world3d/EncounterEventHost3D.gd")
const PLAN_LOADER = preload("res://src/map/LevelPlanLoader.gd")
const GENERATOR = preload("res://src/map/FloorPlanGenerator.gd")
var checks := 0
var failures: Array[String] = []

# 只替代实体交付和存活事实；事件推进、编译与HUD仍调用生产实现，不代表完整整关。
class TimedHost extends RefCounted:
	var live := 0
	var emitted := 0
	var close_calls := 0
	var identities: Array[String] = []
	var held := false

	func encounter_event_context(_room_id: String, _instance_id: String) -> Dictionary:
		return {"player_alive": true, "run_active": true, "current_room_id": "room_03"}

	func encounter_event_spawn(_instance_id: String, _room_id: String, spec: Dictionary, count: int) -> Dictionary:
		for index in count:
			identities.append("%s:%d" % [str(spec.get("_persistent_id_base", "")), index])
		live += count
		emitted += count
		return {"ok": true, "spawned": count}

	func encounter_event_live_count(_instance_id: String) -> int:
		return live

	func encounter_event_close_dispatch(_instance_id: String) -> Dictionary:
		close_calls += 1
		return {"ok": true, "dropped": 0}

	func encounter_event_input_hold(_instance_id: String, value: bool) -> void:
		held = value

	func encounter_event_apply_result(_action: Dictionary) -> Dictionary:
		return {"ok": true}

# 五房使用真实房间上下文，不改变旧room03专用夹具。
class ProductionTimedHost extends TimedHost:
	var room_id := ""

	func encounter_event_context(_room_id: String, _instance_id: String) -> Dictionary:
		return {"player_alive": true, "run_active": true, "current_room_id": room_id}

class DoorDungeonHarness extends DUNGEON:
	func _ready() -> void:
		pass

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func run() -> void:
	var appdata := OS.get_environment("APPDATA").replace("\\", "/").to_lower()
	var localappdata := OS.get_environment("LOCALAPPDATA").replace("\\", "/").to_lower()
	if not (appdata.contains("shellstorm-verification.") and appdata.ends_with("/appdata") and localappdata.ends_with("/localappdata") and appdata != localappdata and appdata.get_base_dir() == localappdata.get_base_dir()):
		push_error("必须启动前隔离userdata")
		get_tree().quit(1)
		return
	var dungeon = DUNGEON.new()
	var ring = RING.new()
	var overlay = OVERLAY.new()
	var hud := Control.new()
	hud.size = Vector2(1280,720)
	add_child(hud)
	hud.add_child(ring)
	hud.add_child(overlay)
	var label: Label = dungeon._make_hud_label("",26,DUNGEON.RUN_COIN_READOUT_COLOR)
	ring.bind_label(label)
	overlay.bind_warning_label(dungeon._make_hud_label("",18,OVERLAY.WARNING_COLOR))
	dungeon._hud_countdown_ring = ring
	dungeon._hud_encounter_alert = overlay
	dungeon._current_room_id = "room_03"
	dungeon._encounter_event_director = DIRECTOR.new()
	var row := {"instance_id":"fixture#1","room_id":"room_03","status":"active","terminal":false,"config":{"duration_sec":0.0,"hud_countdown":false,"alert_style":"red_eva","alert_text":"远端接敌警报","alert_beep_interval_sec":0.5,"alert_pulse":true},"preparation_total_sec":3.0,"preparation_remaining_sec":2.75,"trigger_port_id":"B","stage_states":[]}
	dungeon._encounter_event_director._instances["fixture#1"] = row.duplicate(true)
	var before: Dictionary = dungeon._encounter_event_director.export_snapshot()
	var projected: Dictionary = dungeon.get_encounter_hud_snapshot("room_03")
	check(projected.alert_phase == "preparation" and projected.alert_port_id == "B", "消费正式Director投影")
	projected.preparation_remaining_sec = 1.0
	check(dungeon._encounter_event_director.export_snapshot() == before, "查询不反写Owner")
	var actor := Player3D.new()
	actor.camera = Camera3D.new()
	actor.add_child(actor.camera)
	actor.camera_feedback.configure(actor)
	dungeon.player = actor
	ring.presentation_pulse_requested.connect(dungeon._on_encounter_countdown_pulse)
	var old_reduced = ProjectSettings.get_setting("accessibility/reduce_motion",false)
	ProjectSettings.set_setting("accessibility/reduce_motion",false)
	AudioManager.reset_feedback_debug()
	dungeon._tick_encounter_countdown_hud()
	check(label.text == "【接敌】 2.75 秒" and ring.visible and overlay.visible, "HUD实际显示百分秒")
	check(ring.anchor_top < 0.25 and ring.size.x > 400, "上方横排不盖准星中心")
	check(is_equal_approx(ring.anchor_top, 0.20) and ring.size.y >= 70.0, "数码倒计时上移并保留完整高度")
	check(ring.get_snapshot().digital_display and not label.visible, "正式装配启用七段数码而非旧字体")
	check(ring.get_snapshot().digital_text == "2.75", "数码值来自正式Director快照")
	check(is_equal_approx(overlay.get_node("EncounterWarningLabel").anchor_top, 0.12), "警报文字同步上移避免重叠")
	check(actor.camera_feedback._shake_remaining > 0.0, "red_eva路由现有镜头冲击")
	check(AudioManager.get_feedback_debug_snapshot().request_counts.get("ui_error",0) == 1, "反馈回调不重复蜂鸣")
	dungeon._tick_encounter_countdown_hud()
	check(AudioManager.get_feedback_debug_snapshot().request_counts.get("ui_error",0) == 1, "重复快照不重播")
	row.preparation_remaining_sec = 2.5
	dungeon._encounter_event_director._instances["fixture#1"] = row.duplicate(true)
	dungeon._tick_encounter_countdown_hud()
	check(AudioManager.get_feedback_debug_snapshot().request_counts.get("ui_error",0) == 2, "0.5秒蜂鸣实际路由")
	actor.camera_feedback.reset()
	row.config.alert_pulse = false
	row.preparation_remaining_sec = 2.0
	dungeon._encounter_event_director._instances["fixture#1"] = row.duplicate(true)
	dungeon._tick_encounter_countdown_hud()
	check(actor.camera_feedback._shake_remaining == 0.0, "pulse=false禁震屏")
	row.config.alert_style = "subtle"
	row.preparation_remaining_sec = 1.5
	dungeon._encounter_event_director._instances["fixture#1"] = row.duplicate(true)
	var count: int = AudioManager.get_feedback_debug_snapshot().request_counts.get("ui_error",0)
	dungeon._tick_encounter_countdown_hud()
	check(not overlay.visible and label.get_theme_font_size("font_size") <= 16, "subtle仅小字")
	check(AudioManager.get_feedback_debug_snapshot().request_counts.get("ui_error",0) == count, "subtle无蜂鸣")
	row.config.alert_style = "none"
	dungeon._encounter_event_director._instances["fixture#1"] = row.duplicate(true)
	dungeon._tick_encounter_countdown_hud()
	check(not ring.visible and not overlay.visible, "none隐藏全部")
	row.config.alert_style = "red_eva"
	row.config.alert_pulse = true
	row.preparation_remaining_sec = 0.0
	row.intermission_remaining_sec = 3.0
	row.config.intermission_sec = 3.0
	dungeon._encounter_event_director._instances["fixture#1"] = row.duplicate(true)
	dungeon._tick_encounter_countdown_hud()
	check(label.text == "【下一批接敌】 3.00 秒", "正式Director间歇投影")
	ProjectSettings.set_setting("accessibility/reduce_motion",true)
	actor.camera_feedback.reset()
	row.intermission_remaining_sec = 2.0
	dungeon._encounter_event_director._instances["fixture#1"] = row.duplicate(true)
	dungeon._tick_encounter_countdown_hud()
	check(label.text == "【下一批接敌】 2 秒" and actor.camera_feedback._shake_remaining == 0.0, "reduce_motion整秒无震屏")
	row.intermission_remaining_sec = 0.0
	dungeon._encounter_event_director._instances["fixture#1"] = row.duplicate(true)
	dungeon._tick_encounter_countdown_hud()
	check(label.text == "【清除入侵者】" and not overlay.visible, "战斗提示降级")
	actor.current_hp = 0
	dungeon._tick_encounter_countdown_hud()
	check(not ring.visible and not overlay.visible, "死亡清理")
	actor.current_hp = 100
	dungeon._completed = true
	dungeon._tick_encounter_countdown_hud()
	check(not ring.visible, "行动结束清理")
	dungeon._completed = false
	dungeon.apply_encounter_hud_snapshot({"room_id":"other","config":{"alert_style":"red_eva"}})
	check(not ring.visible, "跨房清理")
	var old := {"instance_id":"old#1","room_id":"room_03","status":"active","elapsed":38.0,"config":{"duration_sec":60.0,"hud_countdown":true}}
	dungeon._encounter_event_director._instances = {"old#1":old}
	dungeon._tick_encounter_countdown_hud()
	check(label.text == "0:22" and not overlay.visible and ring.anchor_left == 0.0, "旧环位置与读数不变")
	print("ENCOUNTER_ALERT_LEGACY_%s checks=%d failures=%d" % ["OK" if failures.is_empty() else "FAIL", checks, failures.size()])
	ProjectSettings.set_setting("accessibility/reduce_motion",false)
	var compiled := verify_room03_compilation(dungeon)
	if not compiled.is_empty():
		verify_timed_loop(dungeon, ring, overlay, compiled, "PRODUCTION")
	else:
		print("ROOM03_TIMED_PRODUCTION_BLOCKED compilation_or_data_invalid=true")
	var timed_fixture := {"schema_version": 1, "event_id": "room03_timed_fixture", "room_id": "room_03", "duration_sec": 60.0, "preparation_sec": 0.0, "freeze_player_sec": 1.0, "completion": "clear", "stage_advance": "clear", "deadline_behavior": "close_dispatch_and_clear", "repeat_last_stage": true, "intermission_sec": 0.0, "hud_countdown": true, "alert_style": "red_eva", "max_alive": 8, "stages": [{"at_sec": 2.0, "monsters": [{"type": "melee_chaser", "count": 5}]}, {"at_sec": 0.0, "monsters": [{"type": "melee_chaser", "count": 7}]}, {"at_sec": 0.0, "monsters": [{"type": "melee_chaser", "count": 8}]}]}
	verify_timed_loop(dungeon, ring, overlay, timed_fixture, "FIXTURE")
	verify_host_close_dispatch()
	verify_all_timed_production(dungeon, ring, overlay)
	await verify_room_door_animation()
	ProjectSettings.set_setting("accessibility/reduce_motion",old_reduced)
	actor.camera_feedback.free()
	actor.free()
	AudioManager.stop_all_sfx()
	dungeon.free()
	hud.free()
	for failure in failures:
		push_error(failure)
	print("ENCOUNTER_ALERT_CONFIG_INTEGRATION_%s checks=%d failures=%d" % ["OK" if failures.is_empty() else "FAIL",checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func verify_room03_compilation(dungeon: Dungeon3D) -> Dictionary:
	var checks_before := checks
	var failures_before := failures.size()
	var floor_source: Dictionary = PLAN_LOADER.load_floor_plan("expedition_01", 0)
	check(not floor_source.is_empty(), "正式LevelPlanLoader未读取远征01")
	var authored := find_room03(floor_source.get("rooms", []) as Array)
	check(not authored.is_empty(), "正式L2缺少room03")
	var expected := {"duration_sec": 60.0, "preparation_sec": 0.0, "freeze_player_sec": 1.0, "start_delay_sec": 2.0, "stage_advance": "clear", "completion": "clear", "deadline_behavior": "close_dispatch_and_clear", "repeat_last_stage": true, "intermission_sec": 0.0}
	var raw := authored.get("encounter", {}) as Dictionary
	for key in expected:
		check(raw.has(key) and raw[key] == expected[key], "room03正式字段%s应为%s，实际%s" % [key, str(expected[key]), str(raw.get(key))])
	var plan: Dictionary = GENERATOR.generate_from_level_plan("expedition_01", 0, 77001199)
	check(bool(plan.get("valid", false)), "正式Generator验证失败：%s" % str(plan.get("validation_errors", [])))
	var record := find_room03(plan.get("rooms", []) as Array)
	check(not record.is_empty(), "正式生成计划缺少room03")
	check(record.get("encounter", {}) == raw, "Loader→Generator遭遇字段丢失或改写")
	if record.is_empty():
		return {}
	var room := DungeonRoom3D.new()
	room.room_id = "room_03"
	room.encounter = (record.get("encounter", {}) as Dictionary).duplicate(true)
	dungeon.visual_theme = DungeonTheme3D.new()
	dungeon.run_seed = 77001199
	dungeon._records.assign(plan.get("rooms", []) as Array)
	var config: Dictionary = dungeon._build_room_encounter_config(room)
	room.free()
	for key in expected:
		if key != "start_delay_sec":
			check(config.has(key) and config[key] == expected[key], "Dungeon编译透传%s错误：%s" % [key, str(config.get(key))])
	var stages := config.get("stages", []) as Array
	check(stages.size() == 3, "room03必须保留三个模板批")
	if stages.size() != 3:
		return {}
	check(float(stages[0].get("at_sec", -1.0)) == 2.0, "room03首批at_sec必须为2")
	for index in 3:
		var count := 0
		for monster: Dictionary in stages[index].get("monsters", []):
			count += int(monster.get("count", 0))
		check(count == [5, 7, 8][index], "room03第%d批必须为%d，实际%d" % [index + 1, [5, 7, 8][index], count])
	var validation: Dictionary = DIRECTOR.validate_config(config)
	check(bool(validation.get("ok", false)), "正式编译配置被Director拒绝：%s" % str(validation))
	print("ROOM03_TIMED_COMPILATION_%s checks=%d failures=%d" % ["OK" if failures.size() == failures_before else "FAIL", checks - checks_before, failures.size() - failures_before])
	return config if bool(validation.get("ok", false)) and failures.size() == failures_before else {}

func verify_timed_loop(dungeon: Dungeon3D, ring: Control, overlay: Control, config: Dictionary, source: String) -> void:
	var checks_before := checks
	var failures_before := failures.size()
	var host := TimedHost.new()
	var director = DIRECTOR.new(host)
	dungeon._encounter_event_director = director
	var started: Dictionary = director.start(config)
	check(bool(started.get("ok", false)), "正式room03编译配置未启动")
	if not bool(started.get("ok", false)):
		return
	var id := str(started.get("instance_id", ""))
	director.tick(0.0)
	var freeze := float(config.get("freeze_player_sec", 0.0))
	var alarm_count := [0]
	director.encounter_event_alarm_started.connect(func(_snapshot: Dictionary): alarm_count[0] += 1)
	if freeze > 0.0:
		var initial := director.get_snapshot(id)
		check(host.emitted == 0 and host.live == 0 and host.held and float(initial.get("elapsed", -1.0)) == 0.0, "起点必须held=true、无怪且elapsed=0")
		check(initial.get("alert_phase") == "trigger_freeze" and is_equal_approx(float(initial.get("freeze_player_remaining_sec", -1.0)), freeze), "起点必须投影独立冻结期")
		check_timed_trigger_freeze_hud(dungeon, ring, overlay, id, "起点")
		director.tick(freeze - 0.01)
		var frozen := director.get_snapshot(id)
		check(host.emitted == 0 and host.live == 0 and host.held and float(frozen.get("elapsed", -1.0)) == 0.0, "冻结结束前不得出怪或推进elapsed")
		check(frozen.get("alert_phase") == "trigger_freeze" and is_equal_approx(float(frozen.get("freeze_player_remaining_sec", -1.0)), 0.01), "冻结结束前仍须保持trigger_freeze")
		check_timed_trigger_freeze_hud(dungeon, ring, overlay, id, "冻结结束前")
		director.tick(0.01)
		var alarmed := director.get_snapshot(id)
		check(bool(alarmed.get("alarm_emitted", false)) and host.emitted == 0 and host.live == 0 and not host.held and float(alarmed.get("elapsed", -1.0)) == 0.0, "冻结结束必须发alarm、解除held且elapsed仍为0")
		check(alarmed.get("alert_phase") == "battle" and float(alarmed.get("alert_total_sec", -1.0)) == 60.0 and float(alarmed.get("alert_remaining_sec", -1.0)) == 60.0, "alarm后必须从60秒battle窗口起算")
	else:
		check(host.emitted == 0 and not host.held, "起点不得出怪或冻结")
		check_timed_hud(dungeon, ring, "60.00", 60.0, "起点")
	check(bool(round_trip(director).get("ok", false)), "起点/冻结结束JSON恢复失败")
	director.tick(1.99)
	var before_first := director.get_snapshot(id)
	check(host.emitted == 0 and not host.held and is_equal_approx(float(before_first.get("elapsed", -1.0)), 1.99), "首批前1.99秒不得出怪，且battle elapsed应为1.99")
	check_timed_hud(dungeon, ring, "58.01", 58.01, "首批前")
	check(bool(round_trip(director).get("ok", false)), "1.99秒JSON恢复失败")
	director.tick(0.01)
	check(host.emitted == 5 and host.live == 5, "第2秒应只派首批5只")
	check_timed_hud(dungeon, ring, "58.00", 58.0, "首批战斗")
	# 实际房间零间歇；增加独立1秒间歇变体，防止HUD将总计时退化成下一批计时。
	verify_timed_intermission(dungeon, ring, config)
	dungeon._encounter_event_director = director
	var expected_total := 5
	for wave in range(1, 8):
		var emitted_before := host.emitted
		check(bool(round_trip(director).get("ok", false)), "在场批次JSON恢复失败")
		director.tick(0.01)
		check(host.emitted == emitted_before, "恢复后在场批次重复派发")
		host.live = 0
		director.notify_enemy_departed(id, "killed")
		var cleared: Dictionary = director.get_snapshot(id)
		check(cleared.get("status") == "active" and not bool(cleared.get("terminal", true)), "截止前清空不得完成")
		check(float(cleared.get("intermission_remaining_sec", -1.0)) == 0.0, "正式room03不得补造间歇")
		var requested_before := int(cleared.get("requested", 0))
		check(bool(round_trip(director).get("ok", false)), "清空待续批JSON恢复失败")
		director.notify_enemy_departed(id, "killed")
		check(int(director.get_snapshot(id).get("requested", 0)) == requested_before, "重复清空通知重复预约末批")
		director.tick(0.01)
		expected_total += 7 if wave == 1 else 8
		check(host.emitted == expected_total and host.live == (7 if wave == 1 else 8), "第%d批应按5/7/8后重复8：累计%d实际%d" % [wave + 1, expected_total, host.emitted])
		check((director.get_snapshot(id).get("stage_states", []) as Array).size() == 3, "末批循环不得扩张模板状态")
		var remaining := 60.0 - float(director.get_snapshot(id).get("elapsed", 0.0))
		check_timed_hud(dungeon, ring, RING.format_preparation_time(remaining), remaining, "循环第%d批" % [wave + 1])
	check(expected_total == 60 and host.emitted > 20, "循环超过三批后不得受旧20只总量上限限制")
	var identities := {}
	for identity in host.identities:
		check(not identities.has(identity), "恢复/末批循环重用敌人身份：%s" % identity)
		identities[identity] = true
	var before_deadline: Dictionary = director.get_snapshot(id)
	director.tick(59.99 - float(before_deadline.get("elapsed", 0.0)))
	check_timed_hud(dungeon, ring, "0.01", 0.01, "截止前")
	director.tick(0.01)
	var expired: Dictionary = director.get_snapshot(id)
	check(expired.get("elapsed") == 60.0 and expired.get("dispatch_closed") == true, "60秒必须关闭派发")
	check(expired.get("alert_phase") == "cleanup" and expired.get("alert_remaining_sec") == 0.0, "截止必须投影cleanup")
	check(expired.get("status") == "active" and host.live == 8 and host.close_calls == 1, "截止不得失败、删除残怪或提前完成")
	dungeon._tick_encounter_countdown_hud()
	check(not bool(ring.get_snapshot().get("digital_display", true)) and ring.get_snapshot().get("text") == "【清除入侵者】" and not overlay.visible, "cleanup应退出数码计时并显示清怪提示")
	check(bool(round_trip(director).get("ok", false)), "cleanup JSON恢复失败")
	director.tick(10.0)
	check(host.emitted == expected_total and host.close_calls == 1 and director.get_snapshot(id).get("status") == "active", "截止恢复后重发、重复关闭或忽略残怪")
	host.live = 0
	director.notify_enemy_departed(id, "killed")
	director.notify_enemy_departed(id, "killed")
	check(director.get_snapshot(id).get("status") == "completed", "截止残怪清零后必须completed")
	dungeon._tick_encounter_countdown_hud()
	check(not ring.visible and not overlay.visible, "正式事件完成后HUD应清理")
	check(bool(round_trip(director).get("ok", false)), "终态JSON恢复失败")
	director.tick(60.0)
	check(director.get_snapshot_rows().is_empty() and host.emitted == expected_total, "终态恢复不得重新建立事件或派发")
	print("ROOM03_TIMED_%s_%s checks=%d failures=%d batches=8 emitted=%d close_calls=%d " % [source, "OK" if failures.size() == failures_before else "FAIL", checks - checks_before, failures.size() - failures_before, host.emitted, host.close_calls])

func verify_all_timed_production(dungeon: Dungeon3D, ring: Control, overlay: Control) -> void:
	var checks_before := checks
	var failures_before := failures.size()
	var source: Dictionary = PLAN_LOADER.load_floor_plan("expedition_01", 0)
	var plan: Dictionary = GENERATOR.generate_from_level_plan("expedition_01", 0, 77001199)
	check(not source.is_empty(), "五房正式Loader不能为空")
	check(bool(plan.get("valid", false)), "五房正式Generator校验失败：%s" % str(plan.get("validation_errors", [])))
	var expected := {"duration_sec": 60.0, "start_delay_sec": 2.0, "preparation_sec": 0.0, "freeze_player_sec": 1.0, "intermission_sec": 0.0, "completion": "clear", "stage_advance": "clear", "deadline_behavior": "close_dispatch_and_clear", "repeat_last_stage": true, "hud_countdown": true}
	var templates := {"room_03": {"max_alive": 8, "counts": [5, 7, 8]}, "room_04": {"max_alive": 6, "counts": [6, 6]}, "room_06": {"max_alive": 10, "counts": [8, 9, 13]}, "room_09": {"max_alive": 16, "counts": [12, 16, 20, 24]}, "room_10": {"max_alive": 10, "counts": [10, 12]}}
	dungeon.visual_theme = DungeonTheme3D.new()
	dungeon.run_seed = 77001199
	dungeon._records.assign(plan.get("rooms", []) as Array)
	for room_id: String in templates:
		var room_failures := failures.size()
		var authored := find_timed_room(source.get("rooms", []) as Array, room_id)
		var record := find_timed_room(plan.get("rooms", []) as Array, room_id)
		check(not authored.is_empty() and not record.is_empty(), "%s正式Loader/Generator缺少房间" % room_id)
		if authored.is_empty() or record.is_empty():
			continue
		var raw := authored.get("encounter", {}) as Dictionary
		for key in expected:
			check(raw.has(key) and raw[key] == expected[key], "%s正式字段%s应为%s，实际%s" % [room_id, key, str(expected[key]), str(raw.get(key))])
		check(record.get("encounter", {}) == raw, "%s Loader→Generator必须完整保留全部遭遇字段" % room_id)
		var baseline := templates[room_id] as Dictionary
		check(raw.get("max_alive") == baseline.max_alive, "%s不得更改原容量%s" % [room_id, str(baseline.max_alive)])
		var room := DungeonRoom3D.new()
		room.room_id = room_id
		room.encounter = (record.get("encounter", {}) as Dictionary).duplicate(true)
		var config: Dictionary = dungeon._build_room_encounter_config(room)
		room.free()
		for key in expected:
			if key != "start_delay_sec":
				check(config.has(key) and config[key] == expected[key], "%s Dungeon编译字段%s错误：%s" % [room_id, key, str(config.get(key))])
		for key in raw:
			if key not in ["trigger", "seal_room", "light_on_finish", "start_delay_sec", "stages"]:
				check(config.has(key) and config[key] == raw[key], "%s Dungeon编译不得丢失或改写%s" % [room_id, key])
		check(config.get("room_id") == room_id and config.get("event_id") == "room_encounter:%s" % room_id and config.get("progress_mode") == "tick", "%s编译事件归属和时钟错误" % room_id)
		var actions: Array = [{"type": "light", "room_id": room_id, "on": true}] if bool(raw.get("light_on_finish", false)) else []
		check(config.get("on_completed") == actions, "%s亮灯结果动作必须保留" % room_id)
		var stages := config.get("stages", []) as Array
		var raw_stages := raw.get("stages", []) as Array
		var counts := baseline.counts as Array
		check(stages.size() == counts.size() and raw_stages.size() == counts.size(), "%s原模板数量不得改变" % room_id)
		for index in mini(stages.size(), raw_stages.size()):
			check(stages[index].get("at_sec") == (2.0 if index == 0 else 0.0), "%s第%d模板延迟错误" % [room_id, index + 1])
			var monsters := stages[index].get("monsters", []) as Array
			var raw_monsters := raw_stages[index].get("monsters", []) as Array
			check(monsters.size() == raw_monsters.size(), "%s第%d模板怪种条目数不得改变" % [room_id, index + 1])
			for monster_index in mini(monsters.size(), raw_monsters.size()):
				var authored_monster := raw_monsters[monster_index] as Dictionary
				var compiled_monster := monsters[monster_index] as Dictionary
				check(compiled_monster.size() == authored_monster.size(), "%s第%d模板怪物字段数不得改变" % [room_id, index + 1])
				for key in authored_monster:
					# JSON数量为float，编译为int；逐字段比较数值而非容器类型相等。
					check(compiled_monster.has(key) and compiled_monster[key] == authored_monster[key], "%s第%d模板怪物%d的%s不得改写" % [room_id, index + 1, monster_index + 1, key])
			if index < counts.size():
				check(timed_stage_count(stages[index]) == int(counts[index]), "%s第%d模板必须保留原数量%d" % [room_id, index + 1, int(counts[index])])
		var validation: Dictionary = DIRECTOR.validate_config(config)
		check(bool(validation.get("ok", false)), "%s正式编译配置被Director拒绝：%s" % [room_id, str(validation)])
		print("ALL_TIMED_COMPILATION room=%s result=%s templates=%d cap=%s failures=%d" % [room_id, "OK" if failures.size() == room_failures else "FAIL", stages.size(), str(config.get("max_alive")), failures.size() - room_failures])
		if failures.size() == room_failures:
			verify_production_timed_loop(dungeon, ring, overlay, config)
		else:
			print("ALL_TIMED_PRODUCTION_BLOCKED room=%s compilation_or_data_invalid=true" % room_id)
	print("ALL_TIMED_PRODUCTION_%s rooms=5 checks=%d failures=%d" % ["OK" if failures.size() == failures_before else "FAIL", checks - checks_before, failures.size() - failures_before])

# 快照经JSON恢复后数值类型可能变化，结构与全部字段仍须逐项一致。
func timed_contract_equal(actual: Variant, expected: Variant) -> bool:
	if expected is Dictionary:
		if not actual is Dictionary or actual.size() != expected.size():
			return false
		for key in expected:
			if not actual.has(key) or not timed_contract_equal(actual[key], expected[key]):
				return false
		return true
	if expected is Array:
		if not actual is Array or actual.size() != expected.size():
			return false
		for index in expected.size():
			if not timed_contract_equal(actual[index], expected[index]):
				return false
		return true
	return actual == expected

func is_expected_freeze_validator_compat(errors: Variant) -> bool:
	if not errors is Array or (errors as Array).is_empty():
		return false
	for error_value in errors as Array:
		if not str(error_value).begins_with("encounter_close_dispatch_combination_invalid:"):
			return false
	return true

func find_timed_room(rows: Array, room_id: String) -> Dictionary:
	for row: Dictionary in rows:
		if str(row.get("key", row.get("id", ""))) == room_id:
			return row
	return {}

func timed_stage_count(stage: Dictionary) -> int:
	var total := 0
	for monster: Dictionary in stage.get("monsters", []):
		total += int(monster.get("count", 0))
	return total

func verify_production_timed_loop(dungeon: Dungeon3D, ring: Control, overlay: Control, config: Dictionary) -> void:
	var checks_before := checks
	var failures_before := failures.size()
	var room_id := str(config.room_id)
	var host := ProductionTimedHost.new()
	host.room_id = room_id
	var director = DIRECTOR.new(host)
	dungeon._current_room_id = room_id
	dungeon._encounter_event_director = director
	var started: Dictionary = director.start(config)
	check(bool(started.get("ok", false)), "%s正式Director启动失败" % room_id)
	if not bool(started.get("ok", false)):
		return
	var id := str(started.instance_id)
	var normalized := (started.snapshot.config as Dictionary).duplicate(true)
	for key in config:
		check(normalized.has(key) and normalized[key] == config[key], "%s Director规范化不得改写编译字段%s" % [room_id, key])
	var stages := config.stages as Array
	var cap := int(config.max_alive)
	var alarm_count := [0]
	director.encounter_event_alarm_started.connect(func(_snapshot: Dictionary): alarm_count[0] += 1)
	var initial := director.get_snapshot(id)
	check(host.live == 0 and host.emitted == 0 and host.held and float(initial.get("elapsed", -1.0)) == 0.0, "%s启动必须冻结、无怪且elapsed=0" % room_id)
	check(initial.get("alert_phase") == "trigger_freeze" and float(initial.get("freeze_player_remaining_sec", -1.0)) == 1.0, "%s启动必须投影独立1秒trigger_freeze" % room_id)
	check_production_trigger_freeze_hud(dungeon, ring, overlay, id, "%s冻结起点" % room_id)
	director.tick(0.99)
	var frozen := director.get_snapshot(id)
	check(host.emitted == 0 and host.live == 0 and host.held and float(frozen.get("elapsed", -1.0)) == 0.0, "%s冻结0.99秒不得出怪、不得推进battle elapsed" % room_id)
	check(frozen.get("alert_phase") == "trigger_freeze" and is_equal_approx(float(frozen.get("freeze_player_remaining_sec", -1.0)), 0.01), "%s冻结0.99秒仍须保持trigger_freeze" % room_id)
	check_production_trigger_freeze_hud(dungeon, ring, overlay, id, "%s冻结0.99秒" % room_id)
	director.tick(0.01)
	var alarmed := director.get_snapshot(id)
	check(bool(alarmed.get("alarm_emitted", false)) and host.emitted == 0 and host.live == 0 and not host.held and float(alarmed.get("elapsed", -1.0)) == 0.0, "%s冻结结束必须只发一次alarm、解除held且elapsed仍为0" % room_id)
	check(alarmed.get("alert_phase") == "battle" and float(alarmed.get("alert_total_sec", -1.0)) == 60.0 and float(alarmed.get("alert_remaining_sec", -1.0)) == 60.0, "%s alarm后必须从60秒battle窗口起算" % room_id)
	check(bool(round_trip(director).get("ok", false)), "%s alarm边界JSON恢复失败" % room_id)
	director.tick(1.99)
	var before_first := director.get_snapshot(id)
	check(host.emitted == 0 and host.live == 0 and is_equal_approx(float(before_first.get("elapsed", -1.0)), 1.99), "%s alarm后1.99秒不得派首批" % room_id)
	check_production_timed_state(dungeon, ring, id, normalized, "%s首批前" % room_id)
	director.tick(0.01)
	var first_count := timed_stage_count(stages[0])
	check(host.emitted == mini(first_count, cap) and host.live == mini(first_count, cap), "%s alarm后第2秒首批应按min(count,max_alive)派发" % room_id)
	check(int(director.get_snapshot(id).get("pending", -1)) == maxi(0, first_count - cap), "%s首批容量不足必须保留pending" % room_id)
	var expected_total := 0
	var partial_kills := 0
	var batches := stages.size() + 4
	for wave in batches:
		var stage_index := mini(wave, stages.size() - 1)
		var amount := timed_stage_count(stages[stage_index])
		var prefix := mini(amount, cap)
		check(host.emitted == expected_total + prefix and host.live == prefix, "%s第%d批首段数量/容量错误：累计%d实际%d live=%d" % [room_id, wave + 1, expected_total + prefix, host.emitted, host.live])
		check_production_timed_state(dungeon, ring, id, normalized, "%s第%d批" % [room_id, wave + 1])
		# 最后一轮保留首段残怪以及可能的pending，直接考察截止撤销。
		if wave == batches - 1:
			expected_total += prefix
			break
		var remaining := amount - prefix
		while remaining > 0:
			check(int(director.get_snapshot(id).get("pending", -1)) == remaining, "%s第%d批pending应为%d" % [room_id, wave + 1, remaining])
			clear_production_timed_live(director, host, id, room_id)
			partial_kills += 1
			var delivered := mini(remaining, cap)
			prefix += delivered
			remaining -= delivered
			check(host.live == delivered and host.live <= cap and host.emitted == expected_total + prefix, "%s第%d批清空释放容量后应只补pending，不能跳批或超cap" % [room_id, wave + 1])
			check_production_timed_state(dungeon, ring, id, normalized, "%s第%d批补发" % [room_id, wave + 1])
		expected_total += amount
		check(host.emitted == expected_total and int(director.get_snapshot(id).get("pending", -1)) == 0, "%s第%d批分段派发后必须交齐原模板数量" % [room_id, wave + 1])
		check(bool(round_trip(director).get("ok", false)), "%s在场批次JSON恢复失败" % room_id)
		var emitted_before := host.emitted
		director.tick(0.01)
		check(host.emitted == emitted_before and host.live <= cap, "%s恢复后不得重复派发或越过容量" % room_id)
		clear_production_timed_live(director, host, id, room_id)
	check(int(director.get_snapshot(id).get("repeat_stage_sequence", 0)) >= 4 and expected_total > sum_timed_stages(stages), "%s必须超过原模板批次数和原总量仍循环" % room_id)
	var identities := {}
	for identity in host.identities:
		check(not identities.has(identity), "%s循环/恢复不得重用敌人身份%s" % [room_id, identity])
		identities[identity] = true
	var live_before := host.live
	var pending_before := int(director.get_snapshot(id).get("pending", 0))
	director.tick(59.99 - float(director.get_snapshot(id).get("elapsed", 0.0)))
	check(host.emitted == expected_total and host.live == live_before and host.close_calls == 0, "%s截止前不得提前关闭、补怪或删怪" % room_id)
	check_production_timed_state(dungeon, ring, id, normalized, "%s截止前0.01秒" % room_id)
	director.tick(0.01)
	var expired: Dictionary = director.get_snapshot(id)
	check(expired.get("elapsed") == 60.0 and expired.get("dispatch_closed") == true and host.close_calls == 1, "%s第60秒必须且仅关闭派发一次" % room_id)
	check(expired.get("pending") == 0 and int(expired.get("dropped", -1)) == pending_before and host.emitted == expected_total, "%s截止不得派发pending，必须准确撤销剩余%d只" % [room_id, pending_before])
	check(expired.get("status") == "active" and not bool(expired.get("terminal", true)) and host.live == live_before and live_before > 0, "%s截止必须保留残怪进入清理而非提前完成" % room_id)
	check(expired.get("alert_phase") == "cleanup" and expired.get("alert_remaining_sec") == 0.0 and expired.get("alert_total_sec") == 60.0, "%s截止HUD必须投影cleanup" % room_id)
	check((expired.get("stage_states", []) as Array).size() == stages.size(), "%s截止模板数组长度不得改变" % room_id)
	var owner_before: Dictionary = director.export_snapshot()
	dungeon._tick_encounter_countdown_hud()
	check(ring.visible and not bool(ring.get_snapshot().get("digital_display", true)) and ring.get_snapshot().get("text") == "【清除入侵者】" and not overlay.visible, "%s cleanup必须退出数码并显示清怪提示" % room_id)
	check(director.export_snapshot() == owner_before, "%s cleanup HUD不得反写Owner" % room_id)
	check(bool(round_trip(director).get("ok", false)), "%s cleanup JSON恢复失败" % room_id)
	director.tick(10.0)
	check(host.emitted == expected_total and host.live == live_before and host.close_calls == 1 and director.get_snapshot(id).get("status") == "active", "%s截止后恢复不得补发、重复关闭或忽略残怪" % room_id)
	if host.live > 1:
		host.live -= 1
		director.notify_enemy_departed(id, "killed")
		director.tick(0.01)
		check(director.get_snapshot(id).get("status") == "active" and host.emitted == expected_total, "%s清理期仅杀部分残怪不得完成或补发" % room_id)
	host.live = 0
	director.notify_enemy_departed(id, "killed")
	director.notify_enemy_departed(id, "killed")
	check(director.get_snapshot(id).get("status") == "completed" and director.get_snapshot(id).get("terminal") == true, "%s截止残怪全清后必须completed" % room_id)
	dungeon._tick_encounter_countdown_hud()
	check(not ring.visible and not overlay.visible, "%s完成后HUD必须清理" % room_id)
	check(bool(round_trip(director).get("ok", false)), "%s终态JSON恢复失败" % room_id)
	director.tick(60.0)
	check(director.get_snapshot_rows().is_empty() and host.emitted == expected_total and host.close_calls == 1, "%s终态恢复不得重建或派发" % room_id)
	print("ALL_TIMED_LOOP room=%s result=%s templates=%d batches=%d cap=%d partial_kills=%d emitted=%d deadline_pending=%d close_calls=%d checks=%d failures=%d " % [room_id, "OK" if failures.size() == failures_before else "FAIL", stages.size(), batches, cap, partial_kills, host.emitted, pending_before, host.close_calls, checks - checks_before, failures.size() - failures_before])

func sum_timed_stages(stages: Array) -> int:
	var total := 0
	for stage: Dictionary in stages:
		total += timed_stage_count(stage)
	return total

func clear_production_timed_live(director: RefCounted, host: ProductionTimedHost, id: String, room_id: String) -> void:
	host.live = 0
	director.notify_enemy_departed(id, "killed")
	var cleared: Dictionary = director.get_snapshot(id)
	check(cleared.get("status") == "active" and not bool(cleared.get("terminal", true)), "%s截止前每次清空fakehost/live均不得complete" % room_id)
	check(cleared.get("intermission_remaining_sec") == 0.0, "%s每次清空不得补造间歇" % room_id)
	var requested := int(cleared.get("requested", 0))
	check(bool(round_trip(director).get("ok", false)), "%s清空/待补发JSON恢复失败" % room_id)
	director.notify_enemy_departed(id, "killed")
	check(int(director.get_snapshot(id).get("requested", 0)) == requested, "%s重复清空通知不得重复预约" % room_id)
	director.tick(0.01)

func check_production_trigger_freeze_hud(dungeon: Dungeon3D, ring: Control, overlay: Control, id: String, context: String) -> void:
	var state := dungeon._encounter_event_director.get_snapshot(id)
	dungeon._tick_encounter_countdown_hud()
	var presentation: Dictionary = ring.get_snapshot()
	var alert: Dictionary = overlay.get_snapshot()
	check(state.get("alert_phase") == "trigger_freeze", "%s Director阶段必须是trigger_freeze" % context)
	check(presentation.get("text") == "【接敌警报】" and not bool(presentation.get("digital_display", false)), "%s HUD冻结期必须提示接敌警报" % context)
	var expected_text := str((state.get("config", {}) as Dictionary).get("alert_text", "WARNING"))
	var red_overlay_expected := str((state.get("config", {}) as Dictionary).get("alert_style", "")) == "red_eva"
	check((overlay.visible == red_overlay_expected) and (not red_overlay_expected or (bool(alert.get("alert_active", false)) and alert.get("warning_text") == expected_text)), "%s HUD冻结期Overlay表现必须符合alert_style" % context)


func check_production_timed_state(dungeon: Dungeon3D, ring: Control, id: String, config: Dictionary, context: String) -> void:
	var director = dungeon._encounter_event_director
	var before: Dictionary = director.export_snapshot()
	var state: Dictionary = director.get_snapshot(id)
	check(state.get("status") == "active" and not bool(state.get("terminal", true)) and not bool(state.get("dispatch_closed", true)) and not bool(state.get("paused", true)), "%s截止前必须保持active、未关闭且未暂停" % context)
	check(timed_contract_equal(state.get("config"), config) and (state.get("stage_states", []) as Array).size() == (config.stages as Array).size(), "%s循环/恢复中全部配置和模板数组长度必须固定" % context)
	check(float(state.get("preparation_remaining_sec", 0.0)) == 0.0 and float(state.get("freeze_player_remaining_sec", -1.0)) == 0.0 and float(state.get("intermission_remaining_sec", -1.0)) == 0.0, "%s不得出现准备、冻结或间歇" % context)
	var remaining := 60.0 - float(state.get("elapsed", 0.0))
	var projected: Dictionary = dungeon.get_encounter_hud_snapshot(str(config.room_id))
	check(projected.get("room_id") == config.room_id and projected.get("alert_phase") == "battle" and projected.get("alert_total_sec") == 60.0 and is_equal_approx(float(projected.get("alert_remaining_sec", -1.0)), remaining), "%s必须投影本房60秒总计时" % context)
	dungeon._tick_encounter_countdown_hud()
	var presentation: Dictionary = ring.get_snapshot()
	check(ring.visible and bool(presentation.get("digital_display", false)) and presentation.get("digital_text") == RING.format_preparation_time(remaining) and is_equal_approx(float(presentation.get("remaining_sec", -1.0)), remaining), "%s HUD必须显示正式Owner总剩余%s" % [context, RING.format_preparation_time(remaining)])
	check(director.export_snapshot() == before, "%s HUD消费不得反写Owner" % context)

func verify_room_door_animation() -> void:
	var door_dungeon := DoorDungeonHarness.new()
	var hud := Control.new()
	hud.name = "HUD"
	var status_panel := Control.new()
	status_panel.name = "StatusPanel"
	var margin := Control.new()
	margin.name = "Margin"
	var status := Label.new()
	status.name = "StatusLabel"
	margin.add_child(status)
	status_panel.add_child(margin)
	hud.add_child(status_panel)
	var minimap := preload("res://src/ui/DungeonMinimap3D.gd").new()
	minimap.name = "DungeonMinimap3D"
	hud.add_child(minimap)
	door_dungeon.add_child(hud)
	add_child(door_dungeon)
	door_dungeon.set_process(false)
	door_dungeon.set_physics_process(false)
	var room_a := DungeonRoom3D.new()
	var room_b := DungeonRoom3D.new()
	room_a.room_id = "door_fixture_a"
	room_b.room_id = "door_fixture_b"
	room_a.global_position = Vector3.ZERO
	room_b.global_position = Vector3(10.0, 0.0, 0.0)
	room_a.door_targets = {"east": room_b.room_id}
	room_b.door_targets = {"west": room_a.room_id}
	room_a.door_policies = {"east": {"requires_key": false, "requires_clear": false, "triggers_fate": false}}
	room_b.door_policies = {"west": {"requires_key": false, "requires_clear": false, "triggers_fate": false}}
	room_a.cleared = true
	room_b.cleared = true
	door_dungeon.add_child(room_a)
	door_dungeon.add_child(room_b)
	var door_a := RoomDoor3D.new()
	var door_b := RoomDoor3D.new()
	door_a.configure("east", room_b.room_id, Color.WHITE)
	door_b.configure("west", room_a.room_id, Color.WHITE)
	room_a.add_child(door_a)
	room_b.add_child(door_b)
	room_a._door_nodes["east"] = door_a
	room_b._door_nodes["west"] = door_b
	door_dungeon._room_by_id = {room_a.room_id: room_a, room_b.room_id: room_b}
	door_dungeon._current_room_id = room_a.room_id
	var edge := door_dungeon._edge_key(room_a.room_id, room_b.room_id)
	door_dungeon._open_edges = {edge: false}
	door_dungeon._pending_room_door_open_edges.clear()
	door_dungeon._door_fate_active = false
	door_dungeon._completed = false
	var door_failures_before := failures.size()
	var first_result := door_dungeon._try_open_room_door(room_b.room_id)
	var duplicate_result := door_dungeon._try_open_room_door(room_b.room_id)
	check(first_result and duplicate_result, "门动画fixture首次/重复点击都应接受请求")
	check(not bool(door_dungeon._open_edges.get(edge, false)) and door_dungeon._pending_room_door_open_edges.size() == 1, "0.18秒前边不得提交且重复点击不得重复挂起")
	check(not door_a.is_open and not door_b.is_open and (door_a.is_in_motion() or door_b.is_in_motion() or door_dungeon._pending_room_door_open_edges.has(edge)), "0.18秒前门必须保持关闭并处于pending或过渡态")
	await get_tree().create_timer(0.10, false).timeout
	check(not bool(door_dungeon._open_edges.get(edge, false)) and door_dungeon._pending_room_door_open_edges.has(edge), "0.10秒时边仍不得open")
	await get_tree().create_timer(0.14, false).timeout
	check(bool(door_dungeon._open_edges.get(edge, false)) and door_dungeon._pending_room_door_open_edges.is_empty(), "0.18秒后才提交_open_edges并清pending")
	check(door_a.is_open and door_b.is_open and (door_a.is_in_motion() or door_b.is_in_motion() or bool(door_a.get_snapshot().get("target_open", false)) and bool(door_b.get_snapshot().get("target_open", false))), "边提交后必须调用RoomDoor3D升降动画")
	var pending_after_commit := door_dungeon._pending_room_door_open_edges.duplicate(true)
	var edge_after_commit := door_dungeon._open_edges.duplicate(true)
	var third_result := door_dungeon._try_open_room_door(room_b.room_id)
	check(third_result and door_dungeon._pending_room_door_open_edges == pending_after_commit and door_dungeon._open_edges == edge_after_commit, "动画已提交后重复点击不得二次提交")
	print("ROOM_DOOR_ANIMATION_INTEGRATION_%s edge=%s transitioning_a=%s transitioning_b=%s checks_failures=%d" % ["OK" if failures.size() == door_failures_before else "FAIL", edge, door_a.is_in_motion(), door_b.is_in_motion(), failures.size() - door_failures_before])
	door_dungeon.free()


func find_room03(rows: Array) -> Dictionary:
	for row: Dictionary in rows:
		if str(row.get("key", row.get("id", ""))) == "room_03":
			return row
	return {}

func round_trip(director: RefCounted) -> Dictionary:
	return director.import_snapshot(JSON.parse_string(JSON.stringify(director.export_snapshot())) as Dictionary)

func check_timed_trigger_freeze_hud(dungeon: Dungeon3D, ring: Control, overlay: Control, id: String, context: String) -> void:
	var state := dungeon._encounter_event_director.get_snapshot(id)
	dungeon._tick_encounter_countdown_hud()
	var presentation: Dictionary = ring.get_snapshot()
	var alert: Dictionary = overlay.get_snapshot()
	check(state.get("alert_phase") == "trigger_freeze", "%s Director阶段必须是trigger_freeze" % context)
	check(presentation.get("text") == "【接敌警报】" and not bool(presentation.get("digital_display", false)), "%s HUD冻结期必须提示接敌警报" % context)
	var expected_text := str((state.get("config", {}) as Dictionary).get("alert_text", "WARNING"))
	var red_overlay_expected := str((state.get("config", {}) as Dictionary).get("alert_style", "")) == "red_eva"
	check((overlay.visible == red_overlay_expected) and (not red_overlay_expected or (bool(alert.get("alert_active", false)) and alert.get("warning_text") == expected_text)), "%s HUD冻结期Overlay表现必须符合alert_style" % context)


func check_timed_hud(dungeon: Dungeon3D, ring: Control, text: String, remaining: float, context: String) -> void:
	var owner_before: Dictionary = dungeon._encounter_event_director.export_snapshot()
	var projected: Dictionary = dungeon.get_encounter_hud_snapshot("room_03")
	check(projected.get("alert_phase") == "battle" and is_equal_approx(float(projected.get("alert_remaining_sec", -1.0)), remaining) and projected.get("alert_total_sec") == 60.0, "%s必须投影60秒总计时" % context)
	dungeon._tick_encounter_countdown_hud()
	var presentation: Dictionary = ring.get_snapshot()
	check(ring.visible and bool(presentation.get("digital_display", false)) and presentation.get("digital_text") == text and is_equal_approx(float(presentation.get("remaining_sec", -1.0)), remaining), "%s数码必须显示总剩余%s，实际%s digital=%s" % [context, text, str(presentation.get("digital_text")), str(presentation.get("digital_display"))])
	check(dungeon._encounter_event_director.export_snapshot() == owner_before, "%s HUD消费不得反写Owner" % context)

func verify_timed_intermission(dungeon: Dungeon3D, ring: Control, compiled: Dictionary) -> void:
	var variant := compiled.duplicate(true)
	variant["intermission_sec"] = 1.0
	var host := TimedHost.new()
	var director = DIRECTOR.new(host)
	dungeon._encounter_event_director = director
	var started: Dictionary = director.start(variant)
	check(bool(started.get("ok", false)), "独立间歇变体未启动")
	if not bool(started.get("ok", false)):
		return
	var id := str(started.get("instance_id", ""))
	var alarm_count := [0]
	director.encounter_event_alarm_started.connect(func(_snapshot: Dictionary): alarm_count[0] += 1)
	var initial := director.get_snapshot(id)
	check(host.held and host.emitted == 0 and float(initial.get("elapsed", -1.0)) == 0.0, "间歇变体启动必须先处于1秒freeze且battle elapsed=0")
	director.tick(1.0)
	var alarmed := director.get_snapshot(id)
	check(bool(alarmed.get("alarm_emitted", false)) and not host.held and host.emitted == 0 and float(alarmed.get("elapsed", -1.0)) == 0.0 and alarmed.get("alert_phase") == "battle", "间歇变体必须先消耗freeze并同步发alarm")
	director.tick(2.0)
	host.live = 0
	director.notify_enemy_departed(id, "killed")
	check(director.get_snapshot(id).get("intermission_remaining_sec") == 1.0, "变体未建立真实间歇")
	check(is_equal_approx(float(director.get_snapshot(id).get("elapsed", -1.0)), 2.0), "alarm后首批前battle elapsed必须为2.0")
	check_timed_hud(dungeon, ring, "58.00", 58.0, "间歇起点")
	check(bool(round_trip(director).get("ok", false)), "间歇变体JSON恢复失败")
	director.tick(0.5)
	check(host.emitted == 5 and director.get_snapshot(id).get("intermission_remaining_sec") == 0.5, "间歇恢复提前派发或重置")
	check_timed_hud(dungeon, ring, "57.50", 57.5, "间歇中")
	director.tick(0.5)
	check(host.emitted == 12, "间歇到点未派正式第二批7只")
	check_timed_hud(dungeon, ring, "57.00", 57.0, "间歇后战斗")

func verify_host_close_dispatch() -> void:
	var checks_before := checks
	var failures_before := failures.size()
	var dungeon := DUNGEON.new()
	var host := HOST.new(dungeon)
	var target := {"encounter_event_instance_id": "target#1", "persistent_id": "target_queue"}
	var legacy := {"encounter_instance_id": "target#1", "persistent_id": "legacy_queue"}
	var noncombat := {"encounter_event_instance_id": "target#1", "counts_for_room_clear": false}
	var other := {"encounter_event_instance_id": "other#1", "persistent_id": "other_queue"}
	var dual := {"encounter_event_instance_id": "other#1", "encounter_instance_id": "target#1", "persistent_id": "dual_owner"}
	var mixed := {"serial": 10, "configs": [target.duplicate(true), other.duplicate(true), noncombat.duplicate(true), legacy.duplicate(true), dual.duplicate(true)], "positions": [[0, 0, 0], [1, 0, 0], [2, 0, 0], [3, 0, 0]], "marker": "保留请求元数据"}
	dungeon._reserved_room_spawns = {"room_03": [mixed], "room_b": [{"configs": [target.duplicate(true)], "positions": [[4, 0, 0]]}], "unrelated": [{"configs": [other.duplicate(true)], "positions": [[9, 0, 0]]}]}
	dungeon._pending_delayed_spawns = {"room_03": [{"serial": 20, "config": target.duplicate(true), "position": [5, 0, 0], "due_msec": 200}, {"serial": 21, "config": other.duplicate(true), "position": [6, 0, 0], "due_msec": 300}, {"serial": 22, "config": noncombat.duplicate(true), "position": [7, 0, 0], "due_msec": 400}]}
	var actor := Enemy3D.new()
	actor.enemy_data = target.duplicate(true)
	var peer := Enemy3D.new()
	peer.enemy_data = other.duplicate(true)
	dungeon._enemy_nodes_by_room = {"room_03": [actor, peer]}
	dungeon._alive_by_room = {"room_03": 8, "room_b": 1, "unrelated": 1}
	var sleeping_enemies := [{"enemy_data": target.duplicate(true)}, {"enemy_data": other.duplicate(true)}]
	dungeon._segment_runtime_state = {"room_03": {"reserved_spawns": dungeon._reserved_room_spawns["room_03"].duplicate(true), "pending_delayed_spawns": dungeon._pending_delayed_spawns["room_03"].duplicate(true), "alive_count": 8, "enemies": sleeping_enemies.duplicate(true), "marker": "保留运行态"}, "room_b": {"reserved_spawns": dungeon._reserved_room_spawns["room_b"].duplicate(true), "alive_count": 1, "enemies": []}}
	var unrelated_before: Array = dungeon._reserved_room_spawns["unrelated"].duplicate(true)
	var delayed_other: Dictionary = dungeon._pending_delayed_spawns["room_03"][1].duplicate(true)
	var closed: Dictionary = host.encounter_event_close_dispatch("target#1")
	check(bool(closed.get("ok", false)) and closed.get("dropped") == 6, "真实Host只应计6个队列取消，不重复计runtime镜像：%s" % str(closed))
	check(dungeon._reserved_room_spawns["room_03"] == [{"serial": 10, "configs": [other, dual], "positions": [[1, 0, 0]], "marker": "保留请求元数据"}], "混合configs/短positions前缀过滤错位、补位或丢请求字段")
	check(not dungeon._reserved_room_spawns.has("room_b") and dungeon._reserved_room_spawns["unrelated"] == unrelated_before, "未移除目标独占请求或误删其他房事件")
	check(dungeon._pending_delayed_spawns["room_03"] == [delayed_other], "delayed应整条撤销目标并原样保留其他serial/position/due")
	check(dungeon._alive_by_room == {"room_03": 5, "room_b": 0, "unrelated": 1}, "alive账只应扣计入清房的取消预约")
	var mirror := dungeon._segment_runtime_state["room_03"] as Dictionary
	check(mirror["reserved_spawns"] == dungeon._reserved_room_spawns["room_03"] and mirror["pending_delayed_spawns"] == [delayed_other] and mirror["alive_count"] == 5, "runtime队列镜像/存活账未同步过滤")
	check((dungeon._segment_runtime_state["room_b"]["reserved_spawns"] as Array).is_empty() and dungeon._segment_runtime_state["room_b"]["alive_count"] == 0, "独占预约runtime镜像未清空")
	check(mirror["enemies"] == sleeping_enemies and mirror["marker"] == "保留运行态", "关闭不得删除休眠实体或其他runtime字段")
	check(is_instance_valid(actor) and not actor.is_queued_for_deletion() and is_instance_valid(peer) and not peer.is_queued_for_deletion() and dungeon._enemy_nodes_by_room["room_03"] == [actor, peer], "关闭不得删除任何已生成实体")
	check(host.encounter_event_live_count("target#1") == 1 and host.encounter_event_live_count("other#1") == 5, "真实Host关闭后live归属错误或双字段归属优先级错误")
	var queues_before := [dungeon._reserved_room_spawns.duplicate(true), dungeon._pending_delayed_spawns.duplicate(true), dungeon._alive_by_room.duplicate(true), dungeon._segment_runtime_state.duplicate(true)]
	var repeated: Dictionary = host.encounter_event_close_dispatch("target#1")
	check(repeated.get("dropped") == 0 and queues_before == [dungeon._reserved_room_spawns, dungeon._pending_delayed_spawns, dungeon._alive_by_room, dungeon._segment_runtime_state], "重复close_dispatch必须返回0且所有账本不变")
	actor.free()
	peer.free()
	dungeon._enemy_nodes_by_room.clear()
	dungeon.free()
	print("ROOM03_REAL_HOST_CLOSE_%s checks=%d failures=%d dropped=%s repeated=%s" % ["OK" if failures.size() == failures_before else "FAIL", checks - checks_before, failures.size() - failures_before, str(closed.get("dropped")), str(repeated.get("dropped"))])
