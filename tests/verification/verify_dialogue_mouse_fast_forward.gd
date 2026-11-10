extends Node3D
## 鼠标专项独立证据，不改写空格44项报告。

class BarrierProbe extends Node:
	var blocked := false
	var actions: Array[String] = []
	func call_instruction(action: String, _params: Dictionary) -> Dictionary:
		actions.append(action)
		if action == "move":
			blocked = true
		return {"ok": action != "fail", "degraded": false, "reason": "鼠标专项预期失败"}
	func should_advance_narrative() -> bool:
		return not blocked
	func should_end_narrative(_id: String) -> bool:
		return true
	func can_commit_narrative(_id: String, _reason: String) -> bool:
		return not actions.has("fail")

class InputWitness extends Node:
	var mouse_events := 0
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			mouse_events += 1

var player: Player3D
var bark: CharacterBark3D
var npc: NpcCharacter3D
var barrier: BarrierProbe
var witness: InputWitness
var checks := 0
var failures: Array[String] = []
var shots := 0

func expect(ok: bool, message: String) -> void:
	checks += 1
	print("MOUSE_CHECK ", checks, " ok=", ok, " ", message)
	if not ok:
		failures.append(message)

func get_main_story_controller() -> Node:
	return barrier

func narrative_player_bark() -> CharacterBark3D:
	return bark

func _ready() -> void:
	if not "dialogue_mouse_" in OS.get_environment("APPDATA") or not "dialogue_mouse_" in OS.get_environment("LOCALAPPDATA"):
		push_error("鼠标专项拒绝未在Autoload前隔离的进程")
		get_tree().quit(2)
		return
	print("MOUSE_ISOLATION user=", ProjectSettings.globalize_path("user://"), " APPDATA=", OS.get_environment("APPDATA"), " LOCALAPPDATA=", OS.get_environment("LOCALAPPDATA"))
	NarrativeDirector.reset_for_test()
	NarrativeDirector.set_process(false)
	DialogueUI.set_process(false)
	BaseManager.save_path = "user://mouse_%d.json" % Time.get_ticks_usec()
	BaseManager.replace_narrative_history_for_test({})
	player = (load("res://scenes/Player3D.tscn") as PackedScene).instantiate() as Player3D
	add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.set_input_locked(false)
	player.set_combat_enabled(true)
	var result := player.equip_weapon_item_to_slot(ItemRegistry.get_instance().get_item("weapon_rifle"), 0)
	expect(bool(result.get("success", false)), "真实Player装备有限弹药步枪")
	player.weapon.shot_fired.connect(func(_count: int) -> void: shots += 1)
	bark = CharacterBark3D.attach_to(player)
	bark.get_bubble().set_process(false)
	barrier = BarrierProbe.new()
	add_child(barrier)
	witness = InputWitness.new()
	add_child(witness)
	NarrativeDirector.bind_dungeon_for_test(self)
	await _check_independent_ui()
	await _check_director()
	await _check_barrier()
	await _check_free_npc()
	await _check_charge_release()
	var raw_mouse_checks := checks
	if OS.get_environment("SHELLSTORM_DIALOGUE_MOUSE_RECOVERY_TEST") == "1":
		await _check_mouse_recovery()
		await _check_unrelated_combat_input()
		await _check_free_npc_mixed_input()
		print("MOUSE_RECOVERY_SAMPLES base_mouse_checks=", raw_mouse_checks, " added_checks=", checks - raw_mouse_checks)
	await release_mouse()
	NarrativeDirector.reset_for_test()
	DialogueUI.close()
	player.queue_free()
	await get_tree().process_frame
	print("MOUSE_REPORT ", JSON.stringify({"checks": checks, "failures": failures, "expected_faults": ["story.fail"], "rendered_acceptance": false, "space_report_overwritten": false}))
	get_tree().quit(0 if failures.is_empty() else 1)

func mouse_event(pressed: bool, button := MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = Vector2(400, 300)
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	return event

func send(event: InputEventMouseButton) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func press_mouse() -> InputEventMouseButton:
	await get_tree().process_frame
	var event := mouse_event(true)
	send(event)
	return event

func release_mouse() -> void:
	send(mouse_event(false))
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame

func fire_tick() -> void:
	player.weapon.set("_cooldown", 0.0)
	player.call("_update_combat_input")

func start_script(id: String, cues: Array) -> void:
	NarrativeDirector.abort("mouse_case_reset")
	DialogueUI.close()
	var data := NarrativeScript3D.from_dictionary({"schema_version": 1, "narrative_id": id, "duration": 40.0, "trigger": {"kind": "manual", "once": "run"}, "cues": cues})
	expect(data.is_valid(), "鼠标剧本结构有效：" + id)
	NarrativeDirector.register_script_for_test(id, data)
	expect(NarrativeDirector.play(id), "鼠标剧本真实启动：" + id)
	NarrativeDirector.call("_process", 0.0)

func _check_independent_ui() -> void:
	await release_mouse()
	var before := witness.mouse_events
	var down := await press_mouse()
	expect(witness.mouse_events == before + 1, "无对白左键pressed不消费")
	expect(Input.is_action_pressed("shoot"), "真实InputEventMouseButton使shoot轮询为true")
	var ammo := player.weapon.current_ammo
	fire_tick()
	expect(shots > 0 and player.weapon.current_ammo < ammo, "无对白真实Player可以开火，证明防穿透测试不是空跑")
	await release_mouse()
	DialogueUI.show_lines({"lines": [{"text": "纯底栏第一句话必须全显"}, {"text": "纯底栏第二句话"}]})
	before = witness.mouse_events
	ammo = player.weapon.current_ammo
	var shots_before := shots
	down = await press_mouse()
	expect(DialogueUI.current_line_index() == 0 and not DialogueUI.is_typing(), "纯DialogueUI左键第一下全显且句号不变")
	expect(Input.is_action_pressed("shoot"), "被消费的左键仍使Input轮询shoot为true")
	fire_tick()
	expect(shots == shots_before and player.weapon.current_ammo == ammo, "消费左键不穿透真实Player开火")
	send(mouse_event(true, MOUSE_BUTTON_RIGHT))
	expect(DialogueUI.current_line_index() == 0 and not DialogueUI.is_typing(), "右键不推进对白")
	send(mouse_event(false))
	send(mouse_event(true))
	expect(DialogueUI.current_line_index() == 0, "同帧释放再按新事件也不能双推进")
	send(down)
	await get_tree().process_frame
	send(mouse_event(true))
	fire_tick()
	expect(DialogueUI.current_line_index() == 0 and player.weapon.current_ammo == ammo, "同事件重发及持续按住跨帧不推进不射击")
	await release_mouse()
	expect(DialogueUI.current_line_index() == 0, "release只重置按压生命周期，不推进")
	var direct := mouse_event(true)
	DialogueUI.consume_advance_input(direct)
	expect(DialogueUI.current_line_index() == 1, "直接同对象测试使用真实MouseButton新pressed")
	DialogueUI.consume_advance_input(mouse_event(false))
	await get_tree().process_frame
	DialogueUI.consume_advance_input(direct)
	expect(DialogueUI.current_line_index() == 1 and DialogueUI.is_typing(), "同一MouseButton对象释放后重复消费拒绝")
	await release_mouse()
	DialogueUI.show_lines({"lines": [{"text": "纯底栏第一句话必须全显"}, {"text": "纯底栏第二句话"}]})
	await press_mouse()
	await release_mouse()
	await press_mouse()
	expect(DialogueUI.current_line_index() == 1 and DialogueUI.is_typing(), "释放后第二个真实左键pressed进入下一句")
	expect(witness.mouse_events == before, "对白pressed/released不进入场景开火或交互输入见证口")
	await release_mouse()
	await press_mouse()
	expect(not DialogueUI.is_typing(), "第二句先揭字而不是整场跳过")
	await release_mouse()
	await press_mouse()
	expect(not DialogueUI.is_active(), "末句正常完成，不使用skip/abort")
	fire_tick()
	await get_tree().process_frame
	fire_tick()
	expect(shots == shots_before, "末句关闭后仍按住不漏出开火")
	send(mouse_event(false))
	fire_tick()
	expect(shots == shots_before, "释放当帧不触发开火/蓄力释放")
	await release_mouse()
	await press_mouse()
	fire_tick()
	expect(shots > shots_before, "生命周期结束后新左键正常恢复开火")
	await release_mouse()
	DialogueUI.show_message("暂停不能全显此句", "系统", 30.0)
	get_tree().paused = true
	var count := DialogueUI.visible_char_count()
	down = mouse_event(true)
	expect(not DialogueUI.consume_advance_input(down), "暂停期间不消费/处理鼠标对白输入")
	send(down)
	DialogueUI.call("_process", 10.0)
	expect(DialogueUI.is_typing() and DialogueUI.visible_char_count() == count, "Pause输入和计时都不揭字")
	get_tree().paused = false
	await release_mouse()
	DialogueUI.close()

func _check_director() -> void:
	start_script("mouse_timeline", [{"at": 0.0, "do": "actor.say", "text": "真实角色气泡第一句话", "hold": 30.0}, {"at": 2.0, "do": "flow.mark", "key": "mouse_middle"}, {"at": 5.0, "do": "ui.subtitle", "text": "系统底栏第二句话", "auto": 30.0}, {"at": 8.0, "do": "actor.say", "text": "角色第三句话", "hold": 30.0}, {"at": 40.0, "do": "flow.end"}])
	var sentence := bark.current_sentence_id()
	var ammo := player.weapon.current_ammo
	var down := await press_mouse()
	expect(not DialogueUI.is_typing() and bark.current_sentence_id() == sentence and is_zero_approx(NarrativeDirector.active_time()), "Director actor.say左键首按只全显")
	fire_tick()
	expect(player.weapon.current_ammo == ammo, "主线气泡左键不传真实Player开火")
	send(down)
	await get_tree().process_frame
	send(mouse_event(true))
	expect(int(NarrativeDirector.get("_advance_target")) == -1, "气泡同事件和按住不预约下一句")
	await release_mouse()
	await press_mouse()
	NarrativeDirector.call("_process", 0.01)
	expect(DialogueUI.current_text() == "系统底栏第二句话" and DialogueUI.is_typing() and NarrativeDirector.has_flag("mouse_middle"), "气泡第二次点击到系统底栏，中间cue真实执行")
	await release_mouse()
	await press_mouse()
	expect(not DialogueUI.is_typing() and is_equal_approx(NarrativeDirector.active_time(), 5.0), "ui.subtitle首按只全显不换句")
	await release_mouse()
	await press_mouse()
	NarrativeDirector.call("_process", 0.01)
	expect(DialogueUI.current_text() == "角色第三句话" and DialogueUI.is_typing(), "ui.subtitle第二次点击进入下一句角色气泡")
	expect(not BaseManager.has_narrative_completed("mouse_timeline"), "逐句推进未伪造整段history")
	await release_mouse()
	NarrativeDirector.abort("mouse_timeline_cleanup")
	start_script("mouse_no_dialogue", [{"at": 2.0, "do": "flow.mark", "key": "not_yet"}, {"at": 40.0, "do": "flow.end"}])
	var before := witness.mouse_events
	await press_mouse()
	expect(witness.mouse_events == before + 1 and is_zero_approx(NarrativeDirector.active_time()), "仅导演活跃但没有对白时左键不消费")
	await release_mouse()

func _check_barrier() -> void:
	barrier.actions.clear()
	start_script("nar_main_mouse_barrier", [{"at": 0.0, "do": "ui.subtitle", "text": "移动前的台词", "auto": 30.0}, {"at": 2.0, "do": "story.move"}, {"at": 3.0, "do": "story.handoff"}, {"at": 4.0, "do": "ui.subtitle", "text": "移动后下一句话", "auto": 30.0}, {"at": 40.0, "do": "flow.end"}])
	await press_mouse()
	await release_mouse()
	await press_mouse()
	NarrativeDirector.call("_process", 0.01)
	expect(barrier.actions == ["move"] and is_equal_approx(NarrativeDirector.active_time(), 2.0), "鼠标快进每cue后检查实体barrier，不穿到handoff")
	await release_mouse()
	await press_mouse()
	NarrativeDirector.call("_process", 0.1)
	expect(barrier.actions == ["move"], "屏障等待期间重复点击不消耗下一动作")
	barrier.blocked = false
	NarrativeDirector.call("_process", 0.01)
	expect(barrier.actions == ["move", "handoff"] and DialogueUI.current_text() == "移动后下一句话" and DialogueUI.is_typing(), "屏障解除按原序到下一句，等待连按不缓存揭字")
	await release_mouse()
	barrier.actions.clear()
	start_script("nar_main_mouse_failed", [{"at": 0.0, "do": "ui.subtitle", "text": "失败前台词", "auto": 30.0}, {"at": 2.0, "do": "story.fail"}, {"at": 3.0, "do": "ui.subtitle", "text": "禁止假显示"}, {"at": 40.0, "do": "flow.end"}])
	await press_mouse()
	await release_mouse()
	await press_mouse()
	print("MOUSE_EXPECTED_FAILURE_BEGIN story.fail")
	NarrativeDirector.call("_process", 0.01)
	print("MOUSE_EXPECTED_FAILURE_END story.fail")
	expect(not NarrativeDirector.is_playing() and not BaseManager.has_narrative_completed("nar_main_mouse_failed") and not DialogueUI.is_active(), "关键失败不写history也不假显示下一句")
	await release_mouse()

func _check_charge_release() -> void:
	var equipped := player.equip_weapon_item_to_slot(ItemRegistry.get_instance().get_item("weapon_charge"), 0)
	expect(bool(equipped.get("success", false)), "真实Player装备蓄力枪验证release不击发")
	var charged_shots := {"count": 0}
	player.weapon.shot_fired.connect(func(_count: int) -> void: charged_shots["count"] += 1)
	await release_mouse()
	await press_mouse()
	fire_tick()
	expect(player.weapon.is_charge_active(), "对白出现前正常按住确实开始蓄力")
	DialogueUI.show_message("蓄力中出现的对白", "系统", 30.0)
	send(mouse_event(false))
	await release_mouse()
	await press_mouse()
	fire_tick()
	expect(not player.weapon.is_charge_active(), "对白消费左键取消原蓄力，不保留迟发")
	var ammo := player.weapon.current_ammo
	send(mouse_event(false))
	fire_tick()
	expect(charged_shots["count"] == 0 and player.weapon.current_ammo == ammo, "消费点击的release不触发真实蓄力枪击发")
	await release_mouse()
	DialogueUI.close()

func send_key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func settle_input_frames() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame

func _check_mouse_recovery() -> void:
	await release_mouse()
	DialogueUI.show_message("失焦不能导致卡死", "系统", 30.0)
	await press_mouse()
	DialogueUI.notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	expect(not bool(DialogueUI.get("_mouse_dialogue_hold")) and DialogueUI.is_dialogue_mouse_fire_blocked(), "窗口失焦显式清hold且隔离开火")
	DialogueUI.notification(NOTIFICATION_WM_WINDOW_FOCUS_IN)
	expect(DialogueUI.is_dialogue_mouse_fire_blocked(), "窗口恢复同帧仍block，防迟发")
	var ammo := player.weapon.current_ammo
	fire_tick()
	expect(player.weapon.current_ammo == ammo, "恢复同帧真实Player不消耗弹药")
	await settle_input_frames()
	expect(not DialogueUI.is_dialogue_mouse_fire_blocked(), "恢复后隔离帧到期不持续锁开火")
	await release_mouse()
	DialogueUI.close()

	DialogueUI.show_message("物理释放丢事件", "系统", 30.0)
	await press_mouse()
	expect(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and bool(DialogueUI.get("_mouse_poll_observed_down")), "真实Input已确认本次pressed，可启用release纠偏")
	# Input仍收到release，但关闭UI输入回调模拟事件被更早节点截获。
	DialogueUI.set_process_input(false)
	DialogueUI.set_process_unhandled_input(false)
	send(mouse_event(false))
	DialogueUI.set_process_input(true)
	DialogueUI.set_process_unhandled_input(true)
	expect(not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and bool(DialogueUI.get("_mouse_dialogue_hold")), "构造Input已松开而对白漏收release的反向状态")
	expect(DialogueUI.is_dialogue_mouse_fire_blocked() and not bool(DialogueUI.get("_mouse_dialogue_hold")), "物理状态纠偏清hold，但纠偏当帧不漏射")
	ammo = player.weapon.current_ammo
	fire_tick()
	expect(player.weapon.current_ammo == ammo, "丢release纠偏当帧真实Player不迟发")
	await settle_input_frames()
	expect(not DialogueUI.is_dialogue_mouse_fire_blocked(), "丢release纠偏后不持续锁开火")
	DialogueUI.close()

	DialogueUI.show_message("合成鼠标不可误清", "系统", 30.0)
	DialogueUI.consume_advance_input(mouse_event(true))
	expect(not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not bool(DialogueUI.get("_mouse_poll_observed_down")), "直接合成pressed未改变真实Input轮询")
	await settle_input_frames()
	expect(DialogueUI.is_dialogue_mouse_fire_blocked() and bool(DialogueUI.get("_mouse_dialogue_hold")), "未曾物理确认的合成按压不能被轮询误清")
	DialogueUI.consume_advance_input(mouse_event(false))
	await settle_input_frames()
	expect(not DialogueUI.is_dialogue_mouse_fire_blocked(), "合成输入显式release正常解除hold")
	DialogueUI.close()

	DialogueUI.show_message("暂停释放防迟发", "系统", 30.0)
	await press_mouse()
	get_tree().paused = true
	send(mouse_event(false))
	expect(not bool(DialogueUI.get("_mouse_dialogue_hold")), "暂停期间release也清hold")
	get_tree().paused = false
	expect(DialogueUI.is_dialogue_mouse_fire_blocked(), "暂停中release记录消费帧，恢复同帧不迟发")
	ammo = player.weapon.current_ammo
	fire_tick()
	expect(player.weapon.current_ammo == ammo and not player.weapon.is_charge_active(), "暂停release后同帧真实Player无蓄力迟发")
	await settle_input_frames()
	expect(not DialogueUI.is_dialogue_mouse_fire_blocked(), "暂停释放恢复后不持续锁开火")
	DialogueUI.close()

func _check_unrelated_combat_input() -> void:
	var result := player.equip_weapon_item_to_slot(ItemRegistry.get_instance().get_item("weapon_rifle"), 0)
	expect(bool(result.get("success", false)), "恢复专项使用真实步枪")
	player.set_reload_ammo_provider(func(_count: int) -> int: return 100)
	player.weapon.current_ammo = player.weapon.magazine_size - 2
	await release_mouse()
	DialogueUI.show_message("鼠标不能吞掉换弹", "系统", 30.0)
	await press_mouse()
	send_key(KEY_R, true)
	fire_tick()
	expect(player.weapon.is_reloading(), "被消费左键hold期间真实R换弹仍执行")
	send_key(KEY_R, false)
	player.weapon.cancel_reload()
	player.set("_mobile_input_available", true)
	player.set("_mobile_shoot_was_active", false)
	player.call("_on_mobile_shoot_pressed")
	var ammo := player.weapon.current_ammo
	fire_tick()
	expect(player.weapon.current_ammo < ammo, "鼠标hold只过滤鼠标，触屏/手柄共用信号按压仍可开火")
	player.call("_on_mobile_shoot_released")
	fire_tick()
	player.set("_mobile_input_available", false)
	await release_mouse()
	DialogueUI.close()

	result = player.equip_weapon_item_to_slot(ItemRegistry.get_instance().get_item("weapon_charge"), 0)
	expect(bool(result.get("success", false)), "共用信号release验证真实蓄力枪")
	await release_mouse()
	DialogueUI.show_message("保留非鼠标蓄力", "系统", 30.0)
	await press_mouse()
	player.set("_mobile_input_available", true)
	player.set("_mobile_shoot_was_active", false)
	player.call("_on_mobile_shoot_pressed")
	fire_tick()
	expect(player.weapon.is_charge_active(), "鼠标hold不取消独立触屏/手柄信号启动的蓄力")
	player.call("_on_mobile_shoot_released")
	fire_tick()
	expect(not player.weapon.is_charge_active() and not bool(player.get("_mobile_shoot_was_active")), "共用信号release仍走正常释放，不被鼠标守卫吞掉")
	player.set("_mobile_input_available", false)
	player.weapon.set("_cooldown", 0.0)
	player.weapon.try_fire(Vector3.FORWARD, player)
	expect(player.weapon.is_charge_active(), "构造非鼠标显式启动的真实蓄力")
	fire_tick()
	expect(player.weapon.is_charge_active(), "鼠标消费不取消非鼠标显式蓄力，自动链不被每帧清空")
	player.weapon.cancel_charge()
	await release_mouse()
	DialogueUI.close()

func _check_free_npc_mixed_input() -> void:
	NarrativeDirector.reset_for_test()
	DialogueUI.close()
	npc = NpcCharacter3D.new()
	add_child(npc)
	npc.set_process(false)
	npc.global_position = player.global_position + Vector3(0.5, 0, 0)
	npc.call("_on_body_entered", player)
	player.interaction_controller.set_process(false)
	await settle_input_frames()
	send_key(KEY_E, true)
	send_key(KEY_E, false)
	var carrier := npc.get_scripted_dialogue_carrier()
	carrier.get_bubble().set_process(false)
	expect(npc.is_speaking() and int(npc.get_snapshot().get("line_index", -1)) == 0, "真实E经过既有交互控制器开启NPC第0句")
	await settle_input_frames()
	send_key(KEY_SPACE, true)
	send_key(KEY_SPACE, false)
	expect(not DialogueUI.is_typing() and int(npc.get_snapshot().get("line_index", -1)) == 0, "真实Space经interact只全显当前自由NPC句")
	await press_mouse()
	expect(DialogueUI.is_typing() and int(npc.get_snapshot().get("line_index", -1)) == 1, "混合E/Space后左键进入自由NPC下一句，不走导演旧句柄")
	await release_mouse()
	send_key(KEY_E, true)
	send_key(KEY_E, false)
	expect(not DialogueUI.is_typing() and int(npc.get_snapshot().get("line_index", -1)) == 1, "混合后E仍先全显同一句")
	npc.hide_dialogue()
	npc.queue_free()
	await get_tree().process_frame

func _check_free_npc() -> void:
	npc = NpcCharacter3D.new()
	add_child(npc)
	npc.set_process(false)
	npc.call("_on_body_entered", player)
	npc.set_interaction_focus({}, true)
	expect(npc.perform_interaction(player, {}), "自由NPC仍由原interact协议开始交谈")
	var npc_bark := npc.get_scripted_dialogue_carrier()
	npc_bark.get_bubble().set_process(false)
	var index := int(npc.get_snapshot().get("line_index", -1))
	var sentence := npc_bark.current_sentence_id()
	var ammo := player.weapon.current_ammo
	await press_mouse()
	expect(not DialogueUI.is_typing() and npc_bark.current_sentence_id() == sentence, "已开始自由NPC对白左键首按只揭字")
	fire_tick()
	expect(player.weapon.current_ammo == ammo, "自由NPC鼠标不穿开火，不依赖基地禁射")
	await release_mouse()
	await press_mouse()
	expect(int(npc.get_snapshot().get("line_index", -1)) == index + 1 and DialogueUI.is_typing(), "自由NPC第二次点击推进目录下一句")
	await release_mouse()
	npc.hide_dialogue()
	var before := witness.mouse_events
	await press_mouse()
	expect(witness.mouse_events == before + 1 and not npc.is_speaking(), "NPC无活跃对白时左键不触发交谈/设施交互")
	await release_mouse()
	npc.queue_free()
	await get_tree().process_frame
