extends Node
## 窄接口专项：正常Autoload入口，启动前隔离userdata，不生成关卡。
const DUNGEON = preload("res://src/world3d/Dungeon3D.gd")
const RING = preload("res://src/ui/EncounterCountdownRing.gd")
const OVERLAY = preload("res://src/ui/EncounterAlertOverlay.gd")
const DIRECTOR = preload("res://src/world3d/EncounterEventDirector3D.gd")
var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func run() -> void:
	if not OS.get_environment("APPDATA").contains("shellstorm-verification."):
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
