extends Node
## 主线静态契约与真实塔楼、控制器、NPC、Boss 的跨模块验收。
## Runner 必须在 Autoload 前隔离 APPDATA 与 LOCALAPPDATA。

const ROOT := "res://"
const SCRIPT_PATHS := [
	"res://src/narrative/MainStoryChapter3D.gd",
	"res://src/narrative/NarrativeAdapter3D.gd",
	"res://src/narrative/NarrativeDirector3D.gd",
	"res://src/narrative/NarrativeCatalog.gd",
	"res://src/npc/NpcCharacter3D.gd",
]
const NARRATIVE_FILES := {
	"nar_main_031_green_briefing": "res://data/narrative/nar_main_031_green_briefing.json",
	"nar_main_032_monitor_audience": "res://data/narrative/nar_main_032_monitor_audience.json",
	"nar_main_033_key_install": "res://data/narrative/nar_main_033_key_install.json",
}
const OWNED_FILES := [
	"src/narrative/NarrativeAdapter3D.gd",
	"src/narrative/NarrativeDirector3D.gd",
	"src/narrative/NarrativeCatalog.gd",
	"src/narrative/MainStoryChapter3D.gd",
	"src/npc/NpcCharacter3D.gd",
	"data/narrative/nar_main_031_green_briefing.json",
	"data/narrative/nar_main_032_monitor_audience.json",
	"data/narrative/nar_main_033_key_install.json",
	"tests/verification/verify_main_story_narrative.gd",
	"tests/verification/verify_main_story_narrative.tscn",
]

var _failures: Array[String] = []
var _checks := 0

func _ready() -> void:
	if OS.get_environment("SHELLSTORM_MAIN_STORY_ISOLATED") != "1" or not "main_story_performance" in ProjectSettings.globalize_path("user://"):
		push_error("主线叙事验收拒绝未在 Autoload 前隔离的用户目录")
		get_tree().quit(2)
		return
	_check_files_exist()
	_check_json_contracts()
	_check_source_contracts()
	_check_forbidden_scope_mentions()
	await _check_runtime_contracts()
	_report()

func _check_files_exist() -> void:
	for path in SCRIPT_PATHS:
		_assert(FileAccess.file_exists(path), "脚本存在：%s" % path)
	for path in NARRATIVE_FILES.values():
		_assert(FileAccess.file_exists(str(path)), "JSON存在：%s" % path)

func _check_json_contracts() -> void:
	var expected_lines := {
		"nar_main_031_green_briefing": [
			"好久没人来了呢，啧啧。", "我认识你的主人。", "四把钥匙",
			"传不了生物。你是机器人，能用。", "mission_operations"
		],
		"nar_main_032_monitor_audience": [
			"你一句我也没听懂…", "………", "啊啊啊啊！", "story.boss.activate"
		],
		"nar_main_033_key_install": [
			"啧啧，真被你拿到了，给我吧", "story.deposit.commit", "钥匙接入 1/4"
		]
	}
	for narrative_id in NARRATIVE_FILES:
		var path := str(NARRATIVE_FILES[narrative_id])
		var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_assert(decoded is Dictionary, "%s 顶层是对象" % narrative_id)
		if not decoded is Dictionary:
			continue
		var source := decoded as Dictionary
		_assert(str(source.get("narrative_id", "")) == narrative_id, "%s id一致" % narrative_id)
		_assert(int(source.get("schema_version", 0)) == 1, "%s schema=1" % narrative_id)
		var cues: Variant = source.get("cues", [])
		_assert(cues is Array and not (cues as Array).is_empty(), "%s cues非空" % narrative_id)
		var last_at := -1.0
		if cues is Array:
			for cue_value in cues as Array:
				_assert(cue_value is Dictionary, "%s cue是对象" % narrative_id)
				if not cue_value is Dictionary:
					continue
				var cue := cue_value as Dictionary
				var at := float(cue.get("at", -1.0))
				_assert(at >= last_at, "%s cue按时间升序" % narrative_id)
				last_at = at
				_assert(str(cue.get("do", "")).contains("."), "%s cue是域动作" % narrative_id)
			_assert(float(source.get("duration", 0.0)) >= last_at, "%s duration覆盖最后cue" % narrative_id)
		var raw := FileAccess.get_file_as_string(path)
		for line in expected_lines.get(narrative_id, []):
			_assert(raw.contains(str(line)), "%s包含关键原文/动作：%s" % [narrative_id, line])

func _check_source_contracts() -> void:
	var chapter := FileAccess.get_file_as_string("res://src/narrative/MainStoryChapter3D.gd")
	for signature in [
		"func setup(host: Node) -> void",
		"func resolve_actor(actor_id: String) -> Node3D",
		"func resolve_anchor(anchor_id: String) -> Variant",
		"func configure_enemy(enemy: Node) -> void",
		"func on_key_claimed() -> void",
		"func call_instruction(action: String, params: Dictionary) -> Dictionary",
		"func get_snapshot() -> Dictionary",
		"const KEY_RARE_EARTH := \"mq_key_rare_earth\"",
		"start_main_story_auto_extraction",
		"request_story_activation",
		"get_story_activation_snapshot",
		"deposit_main_story_key",
		"func claim_main_story_key(source: Dictionary, checkpoint: Dictionary = {}) -> Dictionary",
	]:
		_assert(chapter.contains(signature), "MainStoryChapter3D契约：%s" % signature)
	var adapter := FileAccess.get_file_as_string("res://src/narrative/NarrativeAdapter3D.gd")
	for signature in ["\"story\":", "func _main_story_controller() -> Node", "func can_commit_narrative", "func should_end_narrative"]:
		_assert(adapter.contains(signature), "Adapter契约：%s" % signature)
	var director := FileAccess.get_file_as_string("res://src/narrative/NarrativeDirector3D.gd")
	_assert(director.contains("_adapter.should_end_narrative"), "Director关键条件阻止假结束")
	_assert(director.contains("_adapter.can_commit_narrative"), "Director关键条件阻止假历史")
	var npc := FileAccess.get_file_as_string("res://src/npc/NpcCharacter3D.gd")
	for signature in ["func scripted_move_to", "func scripted_gesture", "func set_scripted_facing"]:
		_assert(npc.contains(signature), "NPC实体表演接口：%s" % signature)
	_assert(not adapter.contains("narrative_player_bark") or adapter.contains("who != \"player\""), "非玩家actor不误走主角bark")

func _check_forbidden_scope_mentions() -> void:
	for path in OWNED_FILES:
		if path == "tests/verification/verify_main_story_narrative.gd":
			continue
		if not FileAccess.file_exists(ROOT + path):
			continue
		var text := FileAccess.get_file_as_string(ROOT + path)
		# 注释中的模块说明不是代码耦合；仅检查实际加载实现脚本的语句。
		var coupling := RegEx.new()
		coupling.compile("(?:load|preload)\\s*\\(\\s*[\\\"'][^\\\"']*(?:Dungeon3D|BaseManager)\\.gd[\\\"']")
		_assert(coupling.search(text) == null, "独占文件不直接加载Dungeon/BaseManager实现：%s" % path)
	_assert(not FileAccess.file_exists("res://src/narrative/MainStoryDialoguePlayer.gd"), "未新增对白播放器")

func _check_runtime_contracts() -> void:
	var old_data := BaseManager.data
	var old_path := BaseManager.save_path
	BaseManager.data = BaseData.new()
	BaseManager.save_path = "user://narrative_runtime.json"
	BaseManager.replace_narrative_history_for_test({})
	NarrativeDirector.reset_for_test()
	NarrativeDirector.set_process(false)
	# 两个重场景可由Runner分进程验收，每个进程仍使用真实正式装配链。
	var runtime_case := OS.get_environment("SHELLSTORM_NARRATIVE_CASE")
	if runtime_case not in ["boss", "boss_full"]:
		await _check_base_runtime()
	if runtime_case != "base":
		await _check_boss_runtime()
	NarrativeDirector.reset_for_test()
	DialogueUI.close()
	BaseManager.data = old_data
	BaseManager.save_path = old_path


func _make_host(scene_path: String) -> TowerDescent3D:
	var scene := load(scene_path) as PackedScene
	var host := scene.instantiate() as TowerDescent3D
	host.test_mode = true
	host.force_main_story_for_test = true
	host.run_seed_override = 77001199
	add_child(host)
	await get_tree().process_frame
	await get_tree().physics_frame
	host.set_process(false)
	host.player.set_physics_process(false)
	var controller := host.get_main_story_controller()
	_assert(controller != null, "正式场景装配真实主线控制器")
	if controller != null:
		controller.set_process(false)
	NarrativeDirector.abort("runtime_fixture_ready")
	NarrativeDirector.bind_dungeon_for_test(host)
	return host


func _check_base_runtime() -> void:
	var host := await _make_host("res://scenes/TowerDescent3D.tscn")
	var controller := host.get_main_story_controller()
	var npc := host.find_npc("npc_base99_green") as Node3D
	_assert(npc != null and controller != null, "基地使用真实绿苔与控制器")
	if npc == null or controller == null:
		host.queue_free()
		await get_tree().process_frame
		return
	host._current_room_id = "facility"
	host.player.global_position = host.get_facility_spawn_point()
	# 未执行 accept 不允许 skip 伪造3.1完成。
	_assert(NarrativeDirector.play(MainStoryChapter3D.BRIEFING_ID), "3.1可启动")
	NarrativeDirector.skip()
	_assert(not BaseManager.has_narrative_completed(MainStoryChapter3D.BRIEFING_ID), "accept前skip不写3.1历史")
	_assert(NarrativeDirector.play(MainStoryChapter3D.BRIEFING_ID), "3.1同会话可重试")
	NarrativeDirector.call("_process", 100.0)
	_assert(not NarrativeDirector.is_playing() and BaseManager.has_narrative_completed(MainStoryChapter3D.BRIEFING_ID), "3.1完整JSON收口并写真实历史")
	_assert(not npc.call("is_scripted_appearance"), "3.1收口释放NPC")
	BaseManager.data.main_story = {"schema_version": 1, "accepted": true, "keys": {MainStoryChapter3D.KEY_RARE_EARTH: {"state": "acquired"}}}
	_assert(NarrativeDirector.play(MainStoryChapter3D.DEPOSIT_ID), "3.3可启动")
	NarrativeDirector.call("_process", 100.0)
	_assert(is_equal_approx(NarrativeDirector.active_time(), 0.2), "低帧移动cue立即截断到0.2而非穿透后续cue")
	var adapter: NarrativeAdapter3D = NarrativeDirector.get("_adapter")
	var before := npc.global_position
	var frozen_time := NarrativeDirector.active_time()
	await get_tree().create_timer(0.15).timeout
	NarrativeDirector.call("_process", 0.15)
	_assert(npc.global_position.distance_to(before) > 0.01, "导演屏障不停止NPC实体process")
	_assert(is_equal_approx(NarrativeDirector.active_time(), frozen_time), "屏障期间不累积叙事delta")
	var pivot: Dictionary = adapter.get("_camera_pivot_channel")
	var tracking: Vector3 = controller.resolve_anchor("npc_tracking")
	_assert((pivot.get("to", Vector3.ZERO) as Vector3).distance_to(tracking) < 0.001, "follow_anchor动态跟踪NPC而非快照")
	_assert(float(pivot.get("t", 0.0)) > 0.0, "跟踪锚点不重置镜头动画相位")
	NarrativeDirector.skip()
	_assert(not BaseManager.has_narrative_completed(MainStoryChapter3D.DEPOSIT_ID), "未安装skip不写3.3历史")
	_assert(not npc.call("is_scripted_appearance") and (controller.get_snapshot().get("key_visual", {}) as Dictionary).is_empty(), "skip释放NPC与同一临时钥匙")
	# 真实移动无法收口时，60秒报错并归还，而非永久锁住。
	NarrativeDirector.play(MainStoryChapter3D.DEPOSIT_ID)
	NarrativeDirector.call("_process", 1.0)
	npc.set_process(false)
	print("MAIN_STORY_EXPECTED_FAILURE_BEGIN barrier_timeout")
	NarrativeDirector.call("_process", 60.0)
	print("MAIN_STORY_EXPECTED_FAILURE_END barrier_timeout")
	npc.set_process(true)
	_assert(not NarrativeDirector.is_playing() and not NarrativeDirector.is_player_input_locked(), "60秒屏障超时abort并解锁")
	_assert(not npc.call("is_scripted_appearance"), "超时归还真实NPC")
	_assert(NarrativeDirector.play(MainStoryChapter3D.DEPOSIT_ID), "超时后同会话重试")
	var deadline := Time.get_ticks_msec() + 30000
	while NarrativeDirector.is_playing() and Time.get_ticks_msec() < deadline:
		var step := 0.5 if controller.should_advance_narrative() else get_process_delta_time()
		NarrativeDirector.call("_process", step)
		await get_tree().process_frame
	_assert(not NarrativeDirector.is_playing(), "3.3真实屏障最终解除并完整收口")
	_assert(BaseManager.has_narrative_completed(MainStoryChapter3D.DEPOSIT_ID), "仅真实插入安装后写3.3历史")
	_assert(str(BaseManager.get_main_story_snapshot().get("keys", {}).get(MainStoryChapter3D.KEY_RARE_EARTH, {}).get("state", "")) == "deposited", "3.3真实领域安装事务成功")
	_assert(not NarrativeDirector.is_player_input_locked() and not NarrativeDirector.is_camera_override_active(), "3.3收口无镜头输入残留")
	_assert(not npc.call("is_scripted_appearance"), "3.3完整收口恢复NPC")
	_check_critical_failures(host)
	NarrativeDirector.abort("base_runtime_cleanup")
	host.queue_free()
	await get_tree().process_frame
	NarrativeDirector.reset_for_test()


func _probe_script(id: String, cues: Array) -> void:
	var script := NarrativeScript3D.from_dictionary({"narrative_id": id, "schema_version": 1, "duration": 1.0, "trigger": {"kind": "manual", "once": "run"}, "cues": cues})
	_assert(script.is_valid(), "内存故障剧本通过结构校验")
	NarrativeDirector.register_script_for_test(id, script)


func _check_critical_failures(host: Node) -> void:
	_probe_script("nar_main_failed_probe", [{"at": 0.0, "do": "story.boss.release_control"}, {"at": 0.0, "do": "flow.mark", "key": "failed_leaked"}])
	print("MAIN_STORY_EXPECTED_FAILURE_BEGIN critical_failed")
	NarrativeDirector.play("nar_main_failed_probe")
	NarrativeDirector.call("_process", 1.0)
	print("MAIN_STORY_EXPECTED_FAILURE_END critical_failed")
	_assert(not NarrativeDirector.is_playing() and (NarrativeDirector.get("_active") as Dictionary).is_empty(), "failed收口后active真正为空")
	_assert(not NarrativeDirector.has_flag("failed_leaked"), "failed不穿透同帧剩余cue")
	_probe_script("nar_main_degraded_probe", [{"at": 0.0, "do": "story.missing"}, {"at": 0.0, "do": "flow.mark", "key": "degraded_leaked"}])
	# 无控制器是正式适配器的degraded路径，不注入替身controller。
	var empty_host := Node.new()
	add_child(empty_host)
	NarrativeDirector.bind_dungeon_for_test(empty_host)
	print("MAIN_STORY_EXPECTED_FAILURE_BEGIN critical_degraded")
	NarrativeDirector.play("nar_main_degraded_probe")
	NarrativeDirector.call("_process", 1.0)
	print("MAIN_STORY_EXPECTED_FAILURE_END critical_degraded")
	_assert(not NarrativeDirector.is_playing() and not NarrativeDirector.has_flag("degraded_leaked"), "critical degraded立即abort且无假active")
	_probe_script("nar_main_no_controller", [{"at": 1.0, "do": "flow.end"}])
	NarrativeDirector.play("nar_main_no_controller")
	NarrativeDirector.skip()
	_assert(not BaseManager.has_narrative_completed("nar_main_no_controller"), "无controller的主线skip同样拒绝假历史")
	_probe_script("ordinary_probe", [{"at": 0.0, "do": "flow.mark", "key": "ordinary_advanced"}, {"at": 1.0, "do": "flow.end"}])
	NarrativeDirector.play("ordinary_probe")
	NarrativeDirector.call("_process", 1.0)
	_assert(NarrativeDirector.has_flag("ordinary_advanced") and not NarrativeDirector.is_playing(), "无controller普通剧情不受主线屏障影响")
	NarrativeDirector.bind_dungeon_for_test(host)
	# flow.end契约失败也不能在_finish之后再写index。
	_probe_script("nar_main_033_key_install", [{"at": 0.0, "do": "flow.end"}])
	host.get_main_story_controller().set("_deposit_succeeded", false)
	print("MAIN_STORY_EXPECTED_FAILURE_BEGIN flow_contract")
	NarrativeDirector.play(MainStoryChapter3D.DEPOSIT_ID)
	NarrativeDirector.call("_process", 1.0)
	print("MAIN_STORY_EXPECTED_FAILURE_END flow_contract")
	_assert(not NarrativeDirector.is_playing(), "flow.end业务拒绝后不污染active")
	empty_host.queue_free()


func _check_boss_runtime() -> void:
	BaseManager.replace_narrative_history_for_test({})
	var full_scene := OS.get_environment("SHELLSTORM_NARRATIVE_CASE") == "boss_full"
	var host := await _make_host("res://scenes/ExpeditionLevel01_3D.tscn" if full_scene else "res://scenes/TowerDescent3D.tscn")
	if not full_scene:
		# 聚焦接线：保留正式host/controller/生成链，仅避开无关整张远征美术预热。
		host.expedition_mode = true
		host.expedition_run_id = "expedition_01"
		host.expedition_plan_id = "expedition_01"
		var boss_room := DungeonRoom3D.new()
		boss_room.configure({"room_id": "boss", "room_type": "BOSS", "custom_dimensions": Vector2(30.0, 30.0), "procedural_furniture_enabled": false})
		host.add_child(boss_room)
		boss_room.global_position = host.player.global_position + Vector3(0.0, 0.0, 30.0)
		host._room_by_id["boss"] = boss_room
	var room := host.get_main_story_room("boss") as DungeonRoom3D
	_assert(room != null, "正式host可查询真实Boss房")
	if room == null:
		host.queue_free()
		await get_tree().process_frame
		return
	room.ensure_shell_built()
	room.ensure_detail_built()
	host._current_room_id = "boss"
	host.player.global_position = room.global_position + Vector3(5.0, 0.5, 5.0)
	var configs: Array[Dictionary] = [{"enemy_type": "boss", "boss_content_id": "boss_monitor002", "hp": 100, "max_hp": 100, "persistent_id": "narrative_monitor"}]
	_assert(host._spawn_enemy_batch(room, configs, true, false, [room.global_position]) == 1, "正式生成链装配真实显示器")
	var boss := host.get_main_story_boss() as Enemy3D
	_assert(boss != null, "controller查询命中真实显示器")
	if boss == null:
		host.queue_free()
		await get_tree().process_frame
		return
	boss.set_runtime_active(true)
	boss.set_physics_process(false)
	boss.set_process(false)
	_assert(NarrativeDirector.play(MainStoryChapter3D.BOSS_ID), "3.2完整JSON可启动")
	NarrativeDirector.skip()
	_assert(not BaseManager.has_narrative_completed(MainStoryChapter3D.BOSS_ID), "激活前skip不写3.2假历史")
	_assert(NarrativeDirector.play(MainStoryChapter3D.BOSS_ID), "3.2被中断后同会话可重试")
	NarrativeDirector.call("_process", 42.0)
	_assert(not bool(boss.get_story_activation_snapshot()["started"]) and NarrativeDirector.is_player_input_locked(), "静态42秒仍处于对白hold而非提前激活")
	NarrativeDirector.call("_process", 1.0)
	_assert(NarrativeDirector.is_playing() and is_equal_approx(NarrativeDirector.active_time(), 42.253), "43秒低帧停在真实activate cue，不伪造flow.end")
	_assert(not BaseManager.has_narrative_completed(MainStoryChapter3D.BOSS_ID), "activation未完成不写3.2历史")
	var adapter: NarrativeAdapter3D = NarrativeDirector.get("_adapter")
	adapter.call_instruction("actor.face", {"who": "player", "yaw_deg": 35.0})
	# 将朝向占用放入正式收口表，以验证晚到restore不会覆盖玩家新瞄准。
	var facing: Dictionary = adapter.call_instruction("actor.face", {"who": "player", "yaw_deg": 70.0})
	NarrativeDirector.call("_occupy", "actor.facing", facing["restore"])
	boss._physics_process(4.39)
	NarrativeDirector.call("_process", 1.0)
	_assert(not bool(host.get_main_story_controller().get_snapshot()["boss_camera_return_requested"]), "A<4.4不提前回镜")
	boss._physics_process(0.02)
	NarrativeDirector.call("_process", 0.0)
	_assert(bool(host.get_main_story_controller().get_snapshot()["boss_camera_return_requested"]), "真实A>=4.4通过导演公共入口回镜")
	boss._physics_process(0.98)
	NarrativeDirector.call("_process", 0.98)
	_assert(NarrativeDirector.is_player_input_locked() and host.player.aim_locked, "A<5.4保持输入瞄准锁")
	boss._physics_process(0.02)
	NarrativeDirector.call("_process", 0.02)
	_assert(not host.player.input_locked and not host.player.aim_locked and not NarrativeDirector.is_actor_facing_overridden(), "真实A>=5.4释放移动与瞄准")
	_assert(not NarrativeDirector.is_camera_override_active(), "5.4无相机残余接管")
	_assert(NarrativeDirector.is_playing() and not BaseManager.has_narrative_completed(MainStoryChapter3D.BOSS_ID), "5.4释放不等于6.4激活完成")
	var hp := boss.current_hp
	boss.take_damage(1)
	_assert(boss.current_hp == hp and boss.ai_state not in ["telegraph", "attack"], "5.4至6.4仍由Enemy门闩保护伤害与攻击")
	var player := host.player
	var start := player.global_position
	player.set("_test_move_direction", Vector3.RIGHT)
	player.set("_mobile_input_available", true)
	player.call("_on_mobile_face_direction", Vector2(0.0, -1.0))
	var previous_yaw := player.aim_yaw
	player.call("_physics_process", 0.1)
	_assert(player.global_position.distance_to(start) > 0.01, "5.4窗口真实Player物理步可移动")
	var new_yaw := player.aim_yaw
	_assert(absf(angle_difference(previous_yaw, new_yaw)) > 0.01, "5.4窗口真实Player接受新瞄准输入")
	NarrativeDirector.call("_process", 0.1)
	_assert(is_equal_approx(player.aim_yaw, new_yaw), "5.4后导演tick不顶回玩家新瞄准")
	boss._physics_process(1.0)
	NarrativeDirector.call("_process", 0.3)
	_assert(bool(boss.get_story_activation_snapshot()["completed"]), "6.4由真实Enemy完成激活")
	_assert(not NarrativeDirector.is_playing() and BaseManager.has_narrative_completed(MainStoryChapter3D.BOSS_ID), "真实completed后flow.end才写历史")
	_assert(is_equal_approx(player.aim_yaw, new_yaw), "收口旧facing restore不覆盖解锁后新瞄准")
	boss.take_damage(1)
	_assert(boss.current_hp == hp - 1, "6.4后才恢复真实Boss受伤")
	_assert(player.combat_enabled, "收口归还玩家战斗占用")
	NarrativeDirector.abort("boss_runtime_cleanup")
	host.queue_free()
	await get_tree().process_frame


func _assert(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		print("MAIN_STORY_NARRATIVE_FAIL ", label)

func _report() -> void:
	if _failures.is_empty():
		print("MAIN_STORY_NARRATIVE_STATIC_OK checks=%d" % _checks)
		print("MAIN_STORY_NARRATIVE_RUNTIME_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[verify_main_story_narrative] " + failure)
	push_error("MAIN_STORY_NARRATIVE_STATIC_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
	get_tree().quit(1)
