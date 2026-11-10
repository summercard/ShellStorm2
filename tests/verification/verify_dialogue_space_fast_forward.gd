extends Node3D
## 必须由启动进程在 Autoload 前隔离用户目录；只做逻辑验收。

class PlayerProbe extends Node3D:
	var input_locked := false
	var aim_locked := false
	var current_hp := 100
	var is_invincible := false
	var camera: Camera3D
	var aim_yaw := 0.0
	var avatar: Node3D
	func set_input_locked(value: bool) -> void:
		input_locked = value

class BarrierProbe extends Node:
	var blocked := false
	var actions: Array[String] = []
	func call_instruction(action: String, _params: Dictionary) -> Dictionary:
		actions.append(action)
		if action == "move":
			blocked = true
		return {"ok": action != "fail", "degraded": false, "reason": "专项预期失败"}
	func should_advance_narrative() -> bool:
		return not blocked
	func should_end_narrative(_id: String) -> bool:
		return true
	func can_commit_narrative(_id: String, _reason: String) -> bool:
		return not actions.has("fail")

class InputWitness extends Node:
	var interactions := 0
	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed("interact"):
			interactions += 1

var player: PlayerProbe
var barrier: BarrierProbe
var controller: Node
var bark: CharacterBark3D
var witness: InputWitness
var failures: Array[String] = []
var checks := 0
var real_npc: NpcCharacter3D
var facility: Node3D
var pedestal: MainStoryPedestal3D

class AvatarProbe extends Node3D:
	var bunny_hand_r: Node3D

func get_main_story_controller() -> Node:
	return controller

func narrative_player_bark() -> CharacterBark3D:
	return bark

func expect(ok: bool, message: String) -> void:
	checks += 1
	print("SPACE_CHECK ", checks, " ok=", ok, " ", message)
	if not ok:
		failures.append(message)

func _ready() -> void:
	if not "dialogue_space_" in OS.get_environment("APPDATA") or not "dialogue_space_" in OS.get_environment("LOCALAPPDATA"):
		push_error("空格专项拒绝未在Autoload前隔离的进程")
		get_tree().quit(2)
		return
	print("SPACE_ISOLATION user=", ProjectSettings.globalize_path("user://"), " APPDATA=", OS.get_environment("APPDATA"), " LOCALAPPDATA=", OS.get_environment("LOCALAPPDATA"))
	NarrativeDirector.reset_for_test()
	NarrativeDirector.set_process(false)
	DialogueUI.set_process(false)
	BaseManager.save_path = "user://space_probe_%d.json" % Time.get_ticks_usec()
	BaseManager.replace_narrative_history_for_test({})
	player = PlayerProbe.new()
	add_child(player)
	player.add_to_group("player_3d")
	player.camera = Camera3D.new()
	player.add_child(player.camera)
	player.camera.position = Vector3(0, 4, 6)
	bark = CharacterBark3D.attach_to(player)
	bark.get_bubble().set_process(false)
	barrier = BarrierProbe.new()
	add_child(barrier)
	controller = barrier
	witness = InputWitness.new()
	add_child(witness)
	NarrativeDirector.bind_dungeon_for_test(self)
	await _check_independent_ui()
	await _check_timeline()
	await _check_barrier_and_failure()
	await _check_real_deposit()
	await _check_real_boss()
	NarrativeDirector.reset_for_test()
	DialogueUI.close()
	print("SPACE_REPORT ", JSON.stringify({"checks": checks, "failures": failures, "expected_faults": ["story.fail"], "rendered_acceptance": false}))
	get_tree().quit(0 if failures.is_empty() else 1)

func key(code: int, echo := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	event.echo = echo
	get_viewport().push_input(event, true)

func press(code := KEY_SPACE) -> void:
	await get_tree().process_frame
	key(code)

func script(id: String, cues: Array, duration := 40.0) -> void:
	NarrativeDirector.abort("space_case_reset")
	DialogueUI.close()
	var data := NarrativeScript3D.from_dictionary({"schema_version": 1, "narrative_id": id, "duration": duration, "trigger": {"kind": "manual", "once": "run"}, "cues": cues})
	expect(data.is_valid(), "专项剧本结构有效：" + id)
	NarrativeDirector.register_script_for_test(id, data)
	expect(NarrativeDirector.play(id), "专项剧本真实启动：" + id)
	NarrativeDirector.call("_process", 0.0)

func _check_independent_ui() -> void:
	DialogueUI.show_lines({"lines": [{"line_id": "a", "text": "独立底栏的第一句话"}, {"line_id": "b", "text": "独立底栏的第二句话"}]})
	await press()
	expect(not DialogueUI.is_typing() and DialogueUI.current_line_index() == 0, "独立UI第一下全显但句号不变")
	key(KEY_SPACE)
	key(KEY_SPACE, true)
	expect(DialogueUI.current_line_index() == 0, "独立UI同帧与echo不推进")
	await press()
	expect(DialogueUI.current_line_index() == 1 and DialogueUI.is_typing(), "独立UI第二下进入下一句")
	await press(KEY_ENTER)
	expect(not DialogueUI.is_typing() and DialogueUI.current_line_index() == 1, "独立UI保留Enter全显")
	get_tree().paused = true
	key(KEY_SPACE)
	DialogueUI.call("_process", 10.0)
	expect(DialogueUI.is_active() and DialogueUI.current_line_index() == 1, "Pause中输入与计时无效")
	get_tree().paused = false
	DialogueUI.close()
	expect(witness.interactions == 0, "独立对白Space不穿透场景交互")
	await press()
	expect(witness.interactions == 1, "无对白无主线时Space仍交给原interact")
	witness.interactions = 0
	DialogueUI.announce("自动节奏保留", 0.2)
	DialogueUI.call("_process", 1.0)
	DialogueUI.call("_process", 0.3)
	expect(not DialogueUI.is_active(), "未按空格的自动播放仍会自然结束")

func _check_timeline() -> void:
	script("space_timeline", [{"at": 0.0, "do": "actor.say", "text": "当前角色台词必须先完整显示", "hold": 30.0}, {"at": 5.0, "do": "flow.mark", "key": "middle"}, {"at": 6.0, "do": "camera.focus", "distance": 3.0, "duration": 2.0}, {"at": 10.0, "do": "ui.subtitle", "text": "下一句系统台词", "auto": 30.0}, {"at": 20.0, "do": "flow.mark", "key": "tail"}, {"at": 40.0, "do": "flow.end"}])
	var sentence := bark.current_sentence_id()
	await press()
	expect(not DialogueUI.is_typing() and bark.current_sentence_id() == sentence and is_zero_approx(NarrativeDirector.active_time()), "角色第一下全显且句号和导演时间不变")
	get_tree().paused = true
	key(KEY_SPACE)
	NarrativeDirector.call("_process", 5.0)
	expect(is_zero_approx(NarrativeDirector.active_time()) and int(NarrativeDirector.get("_advance_target")) == -1, "主线Pause拒绝推进与时间变化")
	get_tree().paused = false
	key(KEY_ESCAPE)
	expect(int(NarrativeDirector.get("_advance_target")) == -1 and get_tree().paused, "ESC保留真实暂停且不推进对白")
	Global.release_pause("manual")
	key(KEY_SPACE)
	key(KEY_SPACE, true)
	expect(int(NarrativeDirector.get("_advance_target")) == -1, "角色同帧与echo不预约快进")
	await press()
	NarrativeDirector.call("_process", 0.01)
	expect(DialogueUI.current_text() == "下一句系统台词" and DialogueUI.is_typing(), "角色第二下到下一句系统对白")
	expect(NarrativeDirector.has_flag("middle") and not NarrativeDirector.has_flag("tail"), "中间cue派发但目标后cue未执行")
	var adapter: NarrativeAdapter3D = NarrativeDirector.get("_adapter")
	var channel: Dictionary = adapter.get("_camera_channel")
	expect(is_zero_approx(float(channel.get("t", -1))), "快进不向Adapter灌入虚拟delta")
	await press()
	expect(not DialogueUI.is_typing() and is_equal_approx(NarrativeDirector.active_time(), 10.0), "系统台词第一下全显不换句")
	await press()
	NarrativeDirector.call("_process", 0.1)
	expect(not DialogueUI.is_active() and NarrativeDirector.is_playing() and not NarrativeDirector.has_flag("tail"), "无下一句只提前结束文字停留，不一键结束整段")
	expect(is_equal_approx(NarrativeDirector.active_time(), 10.1), "无下一句后续动作仍按正常时序")
	expect(witness.interactions == 0, "主线Space不穿透场景交互")

func _check_barrier_and_failure() -> void:
	barrier.actions.clear()
	script("nar_main_space_barrier", [{"at": 0.0, "do": "ui.subtitle", "text": "屏障前台词", "auto": 30.0}, {"at": 2.0, "do": "story.move"}, {"at": 3.0, "do": "story.handoff"}, {"at": 4.0, "do": "ui.subtitle", "text": "屏障后的下一句话", "auto": 30.0}, {"at": 40.0, "do": "flow.end"}])
	await press()
	await press()
	NarrativeDirector.call("_process", 0.01)
	expect(barrier.actions == ["move"] and is_equal_approx(NarrativeDirector.active_time(), 2.0), "中间实体barrier不穿透到交接或下一句")
	await press()
	NarrativeDirector.call("_process", 0.1)
	expect(barrier.actions == ["move"] and int(NarrativeDirector.get("_advance_target")) >= 0, "barrier阻塞时不消耗下一动作且不缓存连按")
	barrier.blocked = false
	NarrativeDirector.call("_process", 0.01)
	expect(barrier.actions == ["move", "handoff"] and DialogueUI.current_text() == "屏障后的下一句话" and DialogueUI.is_typing(), "屏障解除后按原序到目标句，连按没把新句全显")
	barrier.actions.clear()
	script("nar_main_space_failed", [{"at": 0.0, "do": "ui.subtitle", "text": "失败前台词", "auto": 30.0}, {"at": 1.0, "do": "story.fail"}, {"at": 2.0, "do": "ui.subtitle", "text": "不能显示"}, {"at": 40.0, "do": "flow.end"}])
	await press()
	await press()
	print("SPACE_EXPECTED_FAILURE_BEGIN story.fail")
	NarrativeDirector.call("_process", 0.01)
	print("SPACE_EXPECTED_FAILURE_END story.fail")
	expect(not NarrativeDirector.is_playing() and not BaseManager.has_narrative_completed("nar_main_space_failed"), "关键失败不写history、不伪造下一句")

func find_npc(_id: String) -> Node3D:
	return real_npc if is_instance_valid(real_npc) else null

func get_main_story_facility(_id: String) -> Node3D:
	return facility if is_instance_valid(facility) else null

func get_main_story_room(_id: String) -> Node3D:
	return null

func _check_real_deposit() -> void:
	NarrativeDirector.reset_for_test()
	NarrativeDirector.bind_dungeon_for_test(self)
	BaseManager.data = BaseData.new()
	BaseManager.save_path = "user://space_deposit_%d.json" % Time.get_ticks_usec()
	BaseManager.data.main_story = {"schema_version": 1, "accepted": true, "keys": {"mq_key_rare_earth": {"state": "acquired"}}}
	var avatar := AvatarProbe.new()
	player.add_child(avatar)
	avatar.bunny_hand_r = Node3D.new()
	avatar.bunny_hand_r.name = "PlayerHand"
	avatar.add_child(avatar.bunny_hand_r)
	player.avatar = avatar
	real_npc = NpcCharacter3D.new()
	add_child(real_npc)
	real_npc.set_process(false)
	real_npc.position = Vector3(3, 0, 0)
	facility = Node3D.new()
	add_child(facility)
	facility.position = Vector3(6, 0, 0)
	pedestal = MainStoryPedestal3D.new()
	facility.add_child(pedestal)
	pedestal.set_process(false)
	var chapter := MainStoryChapter3D.new()
	add_child(chapter)
	chapter.setup(self)
	chapter.set_process(false)
	controller = chapter
	expect(NarrativeDirector.play(MainStoryChapter3D.DEPOSIT_ID), "真实3.3正式JSON启动")
	var phases: Array[String] = []
	var moves := 0.0
	var previous := real_npc.global_position
	var steps := 0
	while NarrativeDirector.is_playing() and steps < 4000:
		steps += 1
		await get_tree().process_frame
		var state: Dictionary = chapter.get_snapshot()
		var visual: Dictionary = state.get("key_visual", {})
		var phase := str(visual.get("phase", ""))
		if not phase.is_empty() and not phases.has(phase):
			phases.append(phase)
		# 所有实体各自走固定真实步长；快进只走导演，不伪造实体完成。
		real_npc.call("_process", 1.0 / 60.0)
		moves += real_npc.global_position.distance_to(previous)
		previous = real_npc.global_position
		var key_visual := chapter.get("_key_visual") as Node3D
		if is_instance_valid(key_visual):
			key_visual.set_process(false)
			key_visual.call("_process", 1.0 / 60.0)
		var npc_bark := real_npc.get_scripted_dialogue_carrier()
		npc_bark.get_bubble().set_process(false)
		if not DialogueUI.is_typing():
			npc_bark.get_bubble().call("_process", 0.0)
		# 每帧按一次Space，故能检验等待连按不会跳过新句。
		key(KEY_SPACE)
		NarrativeDirector.call("_process", 1.0 / 60.0)
	expect(steps < 4000 and not NarrativeDirector.is_playing(), "真实3.3按Space仍能完整收口")
	expect(moves > 3.0 and phases.has("present") and phases.has("handoff") and phases.has("insert"), "真实NPC跑动、拿出、交接、插入均执行")
	expect(MainStoryProgress.key_state(BaseManager.get_main_story_snapshot(), "mq_key_rare_earth") == "deposited" and BaseManager.has_narrative_completed(MainStoryChapter3D.DEPOSIT_ID), "真实安装落盘后才有3.3 history")
	var log := "\n".join(NarrativeDirector.dispatch_log())
	expect(log.find("story.deposit.key_present") < log.find("story.deposit.key_handoff") and log.find("story.deposit.key_handoff") < log.find("story.deposit.key_insert") and log.find("story.deposit.key_insert") < log.find("story.deposit.commit"), "真实安装cue顺序保持")
	expect(not real_npc.is_scripted_appearance(), "完整收口归还真实NPC")
	facility.queue_free()
	real_npc.queue_free()
	chapter.queue_free()
	avatar.queue_free()
	player.avatar = null
	controller = barrier
	await get_tree().process_frame

func get_main_story_boss() -> Node3D:
	return get_node_or_null("RealBoss") as Node3D

func set_scripted_input_hold(held: bool, _aim := true) -> void:
	player.set_input_locked(held)
	player.aim_locked = held

func refresh_player_input_lock() -> void:
	player.set_input_locked(NarrativeDirector.is_player_input_locked())

func _check_real_boss() -> void:
	BaseManager.replace_narrative_history_for_test({})
	var chapter := MainStoryChapter3D.new()
	add_child(chapter)
	chapter.setup(self)
	chapter.set_process(false)
	controller = chapter
	var enemy_scene := load("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn") as PackedScene
	var boss := enemy_scene.instantiate() as Enemy3D
	boss.name = "RealBoss"
	add_child(boss)
	boss.configure_from_enemy_data(MonsterInjector.new()._generate_boss(1, 0, {"boss_content_id": "boss_monitor002", "floor_number": 0}))
	boss.set_runtime_active(true)
	boss.set_process(false)
	boss.set_physics_process(false)
	script(MainStoryChapter3D.BOSS_ID, [{"at": 0.0, "do": "story.boss.hold"}, {"at": 0.0, "do": "player.lock_input", "locked": true}, {"at": 0.0, "do": "story.boss.control_hold", "held": true}, {"at": 0.0, "do": "ui.subtitle", "text": "激活前的真实对白", "auto": 30.0}, {"at": 3.0, "do": "story.boss.activate"}, {"at": 4.0, "do": "ui.subtitle", "text": "激活后的下一句", "auto": 30.0}, {"at": 40.0, "do": "flow.end"}])
	await press()
	await press()
	NarrativeDirector.call("_process", 0.01)
	expect(bool(boss.get_story_activation_snapshot().get("started", false)) and is_zero_approx(float(boss.get_story_activation_snapshot().get("elapsed", -1))), "快进真实请求Boss激活但不虚增6.4秒时钟")
	boss._physics_process(5.39)
	NarrativeDirector.call("_process", 0.01)
	expect(player.input_locked and player.aim_locked, "真实Boss5.4前仍锁控制")
	boss._physics_process(0.02)
	NarrativeDirector.call("_process", 0.02)
	expect(not player.input_locked and not player.aim_locked and NarrativeDirector.is_playing(), "真实Boss5.4释控但未完成剧情")
	var hp := boss.current_hp
	boss.take_damage(1)
	expect(boss.current_hp == hp and not BaseManager.has_narrative_completed(MainStoryChapter3D.BOSS_ID), "5.4窗口未开放受伤或假history")
	await press()
	boss._physics_process(1.0)
	NarrativeDirector.call("_process", 0.01)
	expect(bool(boss.get_story_activation_snapshot().get("completed", false)) and DialogueUI.current_text() == "激活后的下一句" and DialogueUI.is_typing(), "真实Boss6.4完成才派发下一句，等待连按未缓存")
	boss.take_damage(1)
	expect(boss.current_hp == hp - 1, "真实Boss完成后才开放伤害")
	NarrativeDirector.call("_process", 36.0)
	expect(not NarrativeDirector.is_playing() and BaseManager.has_narrative_completed(MainStoryChapter3D.BOSS_ID), "正常flow.end才写真实Boss history")
	boss.queue_free()
	chapter.queue_free()
	controller = barrier
	await get_tree().process_frame
