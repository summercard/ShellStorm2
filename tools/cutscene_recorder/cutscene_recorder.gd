extends Node3D
## 剧情过场录制台：用真实塔楼/远征场景播放正式剧本，逐帧抓取画面合成视频。
##
## 设计要点：
## - **不伪造演出**：只调用 `NarrativeDirector.play(id)`，镜头、演员、特效全部走正式适配器链路；
##   夹具只负责「把玩家摆到剧情发生的房间」这一件真实玩家本来就会做的事。
## - **只代替玩家按鼠标**：对白 `wait=true` 与手电等待由本台自动推进，其余一律真实 process。
## - **逐帧抓取而非 Movie Maker**：Movie Maker 会把场景生成期的几十秒黑屏一起录进去，
##   而本台在 `play()` 成功后才开始抓帧，第 0 帧即演出第 0 帧。
## - `--fixed-fps 30` 保证逻辑 delta 恒为 1/30，抓到的帧与叙事时间一一对应。
##
## 环境变量：
##   SHELLSTORM_CUTSCENE_ID    必填，NarrativeCatalog 中的 narrative_id
##   SHELLSTORM_CUTSCENE_OUT   必填，工程外输出目录（帧序列写在其 f/ 子目录）
##   SHELLSTORM_CUTSCENE_HOLD  可选，单句对白停留秒数，默认 2.6
##   SHELLSTORM_CUTSCENE_FLASHLIGHT  可选 on/off/auto，默认 auto

const TOWER_SCENE := "res://scenes/TowerDescent3D.tscn"
const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const MAX_SECONDS := 150.0

## 锚点 → 所属房间。剧本的 `point_anchor` 只给锚点不给房间，但怪物生成与光照
## 需要正确的 `_current_room_id`，所以这里按塔楼实际布局把房间补齐。
const ANCHOR_ROOM := {
	"stair_b_entry": "floor_01_entry",
	"stair_b_bottom": "floor_01_entry",
	"stair_b_up": "floor_01_entry",
	"stair_b_middle": "floor_01_entry",
	"stair_a_bottom": "facility",
	"stair_a_middle": "facility",
	"stair_a_upper": "facility",
	"base_west_exit": "facility",
	"rooftop_stair_exit": "start",
	"rooftop_bridge_approach": "start",
	"rooftop_bridge_guard": "start",
}

var _id := ""
var _out := ""
var _frames_dir := ""
var _hold_seconds := 2.6
var _host: Node3D
var _player: Node3D
var _npc: Node3D
var _controller: Node
var _boss: Enemy3D
var _frame := 0
var _recording := false
var _dialogue_hold := 0.0
var _last_line := -2
var _finish_reason := ""
var _started_ms := 0
var _frame_trace: Array[String] = []
var _room_at_play := ""
var _flashlight_mode := "auto"


func _ready() -> void:
	_id = OS.get_environment("SHELLSTORM_CUTSCENE_ID")
	_out = OS.get_environment("SHELLSTORM_CUTSCENE_OUT")
	var hold := OS.get_environment("SHELLSTORM_CUTSCENE_HOLD")
	if not hold.is_empty():
		_hold_seconds = float(hold)
	var mode := OS.get_environment("SHELLSTORM_CUTSCENE_FLASHLIGHT")
	if not mode.is_empty():
		_flashlight_mode = mode
	if _id.is_empty() or _out.is_empty():
		push_error("[cutscene] 缺 SHELLSTORM_CUTSCENE_ID / SHELLSTORM_CUTSCENE_OUT")
		get_tree().quit(2)
		return
	if not NarrativeCatalog.has_id(_id):
		push_error("[cutscene] 未知 narrative_id: " + _id)
		get_tree().quit(2)
		return
	_frames_dir = _out.path_join("f")
	DirAccess.make_dir_recursive_absolute(_frames_dir)
	_started_ms = Time.get_ticks_msec()
	await _run()


func _run() -> void:
	var spec := _spec_for(_id)
	BaseManager.data = BaseData.new()
	BaseManager.replace_narrative_history_for_test({})
	BaseManager.save_path = "user://cutscene_recorder.json"
	if bool(spec.get("main_story_033", false)):
		BaseManager.data.main_story = {
			"schema_version": 1,
			"accepted": true,
			"keys": {"mq_key_rare_earth": {"state": "acquired"}},
		}
	NarrativeDirector.reset_for_test()
	if bool(spec.get("ceremony", false)):
		# 入场仪式只认「从基地情报室传送到远征」这条真实出发请求，
		# 伪造 _entry_context 会让 _is_valid_expedition_entry_ceremony 直接否掉。
		GameEntryFlow.request_gameplay_entry(GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT)

	_host = (load(str(spec.scene)) as PackedScene).instantiate() as Node3D
	_host.set("test_mode", true)
	# 入场仪式的两条剧本由 seed 奇偶决定播哪一条，必须钉住 seed 才能录到指定那条。
	_host.set("run_seed_override", int(spec.get("seed", 990098)))
	if bool(spec.get("opening", false)):
		_host.set("force_new_game_opening_for_test", true)
	if bool(spec.get("main_story", false)):
		_host.set("force_main_story_for_test", true)
	var mounted := {"generated": false, "started": false}
	_host.connect("generation_completed", func(_s: Dictionary) -> void: mounted.generated = true)
	_host.connect("gameplay_started", func(_r: String) -> void: mounted.started = true)
	add_child(_host)
	var deadline := Time.get_ticks_msec() + 90000
	while (not mounted.generated or not mounted.started) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not mounted.started:
		_fail("场景90秒内未进入 gameplay_started")
		return
	await get_tree().physics_frame

	_player = _host.get("player") as Node3D
	if _player == null:
		_fail("真实场景没有 player")
		return
	# 自动触发全部关掉：本台只播指定那一条，不允许别的剧情插进来污染镜头。
	NarrativeDirector.reset_for_test()
	for entry in NarrativeCatalog.all_ids():
		NarrativeDirector.disarm(str(entry))
	NarrativeDirector.bind_dungeon_for_test(_host)
	_host.set("_main_story_gameplay_started", false)
	_controller = _host.call("get_main_story_controller") as Node
	if _controller != null:
		_controller.set_process(true)

	await _place_actor(spec)
	_apply_flashlight()
	_host.call("_update_floor_visibility_state")
	_host.call("_apply_indoor_camera_pose")
	var camera := _player.get("camera") as Camera3D
	if camera != null:
		camera.make_current()
	await get_tree().process_frame
	await get_tree().process_frame

	NarrativeDirector.narrative_finished.connect(func(fid: String, reason: String) -> void:
		if fid == _id:
			_finish_reason = reason)
	if bool(spec.get("ceremony", false)):
		# 正式入口：宿主自己预热 + 发事件，导演据 seed 选片。本台只等它真的起播。
		_host.call("prepare_expedition_entry_ceremony")
		_host.call("notify_expedition_entry_ceremony_ready")
		var wait := Time.get_ticks_msec() + 15000
		while not NarrativeDirector.is_playing() and Time.get_ticks_msec() < wait:
			await get_tree().process_frame
		if NarrativeDirector.active_id() != _id:
			_fail("仪式未起播，当前 active=%s" % NarrativeDirector.active_id())
			return
	else:
		if not NarrativeDirector.play(_id):
			_fail("NarrativeDirector.play 拒绝播放")
			return
	NarrativeDirector.set_process(true)
	_recording = true
	await _record_loop()
	_report()


## 按剧本类型决定用哪个宿主场景、以及需要哪些前置夹具。
func _spec_for(narrative_id: String) -> Dictionary:
	var spec := {"scene": TOWER_SCENE, "opening": false, "main_story": false, "main_story_033": false}
	# 远征入场仪式发生在「从基地情报室传送到远征 01」这条真实出发链上，
	# 只能在远征关卡里、且开局的 start 房就是演出位。
	if narrative_id.begins_with("nar_expedition_entry_hologram_"):
		spec.scene = EXPEDITION_SCENE
		spec.ceremony = true
		# _expedition_entry_narrative_id() 按 run_seed 奇偶选片：偶=scan，奇=materialize。
		spec.seed = 20261111 if narrative_id.ends_with("materialize") else 20261110
	# 主线 3.2（显示器观众席）必须在真实远征 01 的 Boss 房内，塔楼里没有那只 Boss。
	elif narrative_id.begins_with("nar_main_032_monitor_audience"):
		spec.scene = EXPEDITION_SCENE
		spec.main_story = true
	elif narrative_id.begins_with("nar_main_"):
		spec.main_story = true
		spec.main_story_033 = narrative_id.begins_with("nar_main_033")
	if narrative_id.begins_with("nar_tower_opening_"):
		spec.opening = true
	return spec


func _place_actor(spec: Dictionary) -> void:
	if bool(spec.get("ceremony", false)):
		# 仪式位就是宿主自己摆的出生点，不要把人挪走。
		return
	if str(spec.scene) == EXPEDITION_SCENE:
		await _place_in_boss_room()
		return
	if _id.begins_with("nar_main_0"):
		await _place_in_facility(true)
		return
	if _id.begins_with("nar_tutorial_"):
		await _place_in_facility(false)
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(NarrativeCatalog.path_for(_id)))
	var trigger: Dictionary = data.get("trigger", {})
	var room_id := str(trigger.get("point_room", ""))
	var target := Vector3.ZERO
	var has_target := false
	if trigger.has("point_offset"):
		var offset: Array = trigger.get("point_offset", [0, 0, 0])
		target = Vector3(float(offset[0]), float(offset[1]), float(offset[2]))
		if not room_id.is_empty():
			_host.call("force_enter_room_for_test", room_id)
			var room := _room(room_id)
			if room != null:
				target = room.to_global(target)
				has_target = true
	elif trigger.has("point_anchor"):
		var anchor_id := str(trigger.get("point_anchor"))
		room_id = str(ANCHOR_ROOM.get(anchor_id, ""))
		var point: Variant = _host.call("narrative_anchor", anchor_id)
		if point is Vector3:
			target = point as Vector3
			has_target = true
		if not room_id.is_empty():
			_host.call("force_enter_room_for_test", room_id)
	elif str(trigger.get("on", "")) == "gameplay_started":
		var filter: Dictionary = trigger.get("filter", {})
		room_id = str(filter.get("room_id", "floor_01_exit"))
		_host.call("force_enter_room_for_test", room_id)
		var room := _room(room_id)
		if room != null:
			target = room.global_position
			has_target = true
	elif str(trigger.get("on", "")) == "room_entered":
		var filter: Dictionary = trigger.get("filter", {})
		room_id = str(filter.get("room_id", ""))
		if not room_id.is_empty():
			_host.call("force_enter_room_for_test", room_id)
			var room := _room(room_id)
			if room != null:
				target = room.global_position
				has_target = true
	if has_target:
		_player.global_position = target + Vector3.UP * 0.06
		_player.set("velocity", Vector3.ZERO)
	_room_at_play = room_id
	await get_tree().physics_frame
	await get_tree().physics_frame


func _place_in_facility(use_npc: bool) -> void:
	var facility := str(ANCHOR_ROOM["base_west_exit"])
	_room_at_play = "facility"
	_host.call("force_enter_room_for_test", "facility")
	var room := _room("facility")
	if room != null:
		room.call("ensure_shell_built")
		room.call("ensure_detail_built")
	_host.call("apply_narrative_light_state", facility, true)
	_npc = _host.call("find_npc", "npc_base99_green") as Node3D
	var spawn: Vector3 = _host.call("get_facility_spawn_point")
	if use_npc and _npc != null:
		spawn = _npc.global_position + Vector3(0, 0, 3.0)
	_player.global_position = spawn + Vector3.UP * 0.06
	if use_npc and _npc != null:
		var look := _npc.global_position - _player.global_position
		if Vector2(look.x, look.z).length() > 0.01:
			var yaw := atan2(-look.x, -look.z)
			_player.rotation.y = yaw
			_player.set("aim_yaw", yaw)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _place_in_boss_room() -> void:
	_room_at_play = "boss"
	var room := _room("boss")
	if room == null:
		_fail("远征01 没有 boss 房")
		return
	room.call("ensure_shell_built")
	room.call("ensure_detail_built")
	room.call("set_stream_state", 1)
	_host.call("force_enter_room_for_test", "boss")
	var spawn := room.global_position + Vector3(5.0, 0.1, 5.0)
	var probe := PhysicsRayQueryParameters3D.create(spawn + Vector3.UP * 20.0, spawn + Vector3.DOWN * 20.0, 1)
	probe.collide_with_areas = false
	var hit := _host.get_world_3d().direct_space_state.intersect_ray(probe)
	if not hit.is_empty():
		spawn = (hit["position"] as Vector3) + Vector3.UP * 0.06
	_player.global_position = spawn
	var configs: Array[Dictionary] = [{
		"enemy_type": "boss",
		"boss_content_id": "boss_monitor002",
		"hp": 100,
		"max_hp": 100,
		"persistent_id": "cutscene_monitor",
	}]
	_host.call("_spawn_enemy_batch", room, configs, true, false, [room.global_position])
	await get_tree().physics_frame
	_boss = _host.call("get_main_story_boss") as Enemy3D
	if _boss != null:
		_boss.set_runtime_active(true)
		_boss.set_physics_process(true)
	await get_tree().physics_frame


func _room(room_id: String) -> Node3D:
	var table: Dictionary = _host.get("_room_by_id")
	return table.get(room_id) as Node3D


## 98F 整层没有灯，真实玩家在 2.1 结尾被要求打开手电、此后一直亮着；
## 99F 关灯基地同理。不还原这一步，录出来就是一片死黑，看不出任何演出。
func _apply_flashlight() -> void:
	var want := false
	match _flashlight_mode:
		"on": want = true
		"off": want = false
		_: want = _room_at_play.begins_with("floor_01") or _id.contains("base_dark")
	if not want:
		return
	var light := _player.get_node_or_null("PlayerFlashlight3D")
	if light != null and light.has_method("set_light_enabled"):
		light.call("set_light_enabled", true)


func _process(delta: float) -> void:
	if _recording:
		_autopilot(delta)


## 只代替真人做两件事：对白中点一下、剧情要求手电时打开手电。
func _autopilot(delta: float) -> void:
	if NarrativeDirector.is_waiting_for_flashlight():
		var light := _player.get_node_or_null("PlayerFlashlight3D")
		if light != null and light.has_method("set_light_enabled"):
			light.call("set_light_enabled", true)
		NarrativeDirector.complete_flashlight_wait()
		return
	if not DialogueUI.is_active():
		_dialogue_hold = 0.0
		_last_line = -2
		return
	var index := DialogueUI.current_line_index()
	if index != _last_line:
		_last_line = index
		_dialogue_hold = 0.0
		return
	_dialogue_hold += delta
	var text := DialogueUI.current_text()
	var need := maxf(_hold_seconds, 1.6 + float(text.length()) * 0.055)
	if _dialogue_hold >= need:
		DialogueUI.reveal_all()
		DialogueUI.advance()
		_dialogue_hold = 0.0


func _record_loop() -> void:
	var deadline := Time.get_ticks_msec() + int(MAX_SECONDS * 1000.0)
	var tail := 0
	while true:
		await RenderingServer.frame_post_draw
		_grab()
		if not NarrativeDirector.is_playing() and not DialogueUI.is_active():
			tail += 1
			if tail >= 12:
				break
		else:
			tail = 0
		if Time.get_ticks_msec() > deadline:
			_finish_reason = "timeout"
			break
		await get_tree().process_frame
	_recording = false


func _grab() -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null:
		return
	var path := _frames_dir.path_join("%06d.jpg" % _frame)
	image.save_jpg(path, 0.92)
	if _frame % 30 == 0:
		_frame_trace.append("%d t=%.3f" % [_frame, NarrativeDirector.active_time()])
	_frame += 1


func _report() -> void:
	var payload := {
		"narrative_id": _id,
		"frames": _frame,
		"fps": 30,
		"finish_reason": _finish_reason,
		"wall_seconds": float(Time.get_ticks_msec() - _started_ms) / 1000.0,
		"diagnostics": NarrativeDirector.diagnostics(),
		"dispatch_log": NarrativeDirector.dispatch_log(),
		"input_locked": NarrativeDirector.is_player_input_locked(),
		"camera_override": NarrativeDirector.is_camera_override_active(),
		"trace": _frame_trace,
	}
	var file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(payload, "  "))
	print("CUTSCENE_DONE id=%s frames=%d reason=%s diag=%d" % [_id, _frame, _finish_reason, NarrativeDirector.diagnostics().size()])
	NarrativeDirector.abort("cutscene_cleanup")
	get_tree().quit(0 if _frame > 12 else 1)


func _fail(message: String) -> void:
	push_error("[cutscene] " + message)
	_finish_reason = "error: " + message
	_report()
