extends SceneTree
## 截图：首遇收租人后回 99F 的 NPC 迎宾（`BASE-NPC` 一次性剧情节拍）。
##
## 两种机位，各拍一张：
##   - **默认（合成相机）** → `base99_npc_greeting_standby.png`
##     玩家被挪到远处（不触发招呼），看的是"NPC 站在归航点**边上**等、不在巡逻线上"。
##   - **`NPC_SHOT_GAME=1`（玩家自带相机）** → `base99_npc_greeting_talk.png`
##     玩家站在归航点，看的是"真实游玩时迎面被提醒"的构图（进气、气泡、可读性）。
##
## 用法（必须**不带** `--headless`，否则是 dummy renderer）：
##   APPDATA=<临时目录> NPC_SHOT_HOUR=12 godot --path . --resolution 1280x720 \
##       --script res://tests/verification/capture_base99_npc_greeting.gd
##   APPDATA=<临时目录> NPC_SHOT_HOUR=12 NPC_SHOT_GAME=1 godot --path . --resolution 1280x720 \
##       --script res://tests/verification/capture_base99_npc_greeting.gd
##
## ⚠️ 不要套 `timeout`：本机 Git Bash 的 timeout 会吞掉 NPC_SHOT_* 环境变量。
## ⚠️ `--script` 模式下不能按标识符引用 Autoload（编译顺序），一律 `root.get_node_or_null`。
## ⚠️ 塔楼场景必须等 Autoload 就绪后再建：`_initialize()` 早于 Autoload 的 `_ready()`，
##    那时 `EliteRosterService` 的定义表还是空的，造遭遇会静默失败（实测 count=0）。

const NPC_ID := "npc_base99_green"
const ELITE_ID := "elite_arms_taker"
const ENCOUNTER_ID := "capture_story_beat:92:elite_arms_taker"
const EVIDENCE_DIR := "res://docs/v0.1/audits/evidence/2026-11-04_base_npc_greeting/"
const SPAWN := Vector3(0.0, -11.95, 5.0)

var _tower: Node = null
var _npc: Node3D = null
var _camera: Camera3D = null
var _frames := 0


## 造出"已经遭遇过收租人"的跨局事实（预约 + 首次生成确认）。
func _seed_encounter() -> void:
	var roster := root.get_node_or_null("EliteRosterService")
	var base := root.get_node_or_null("BaseManager")
	if roster == null or base == null:
		print("NPC_SHOT_FAIL missing_autoload")
		return
	base.call("replace_elite_archive_records_for_test", {})
	roster.call("reset_roster_for_test")
	roster.call("reserve", ELITE_ID, ENCOUNTER_ID, 92)
	roster.call("confirm_reservation", ELITE_ID, ENCOUNTER_ID)
	var record: Dictionary = roster.call("get_record", ELITE_ID)
	print("NPC_SHOT_ENCOUNTER count=%d" % int(record.get("encounter_count", 0)))


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_seed_encounter()
		var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
		_tower = packed.instantiate()
		_tower.set("test_mode", true)
		_tower.set("run_seed_override", 990099)
		root.add_child(_tower)
	if _frames == 6:
		_push_clock()
	if _frames == 16:
		if not _setup_subject():
			quit(1)
			return true
	if _frames == 30:
		_frame_camera()
	if _frames == 44:
		_report()
		_save("base99_npc_greeting.png")
		quit(0)
		return true
	return false


func _push_clock() -> void:
	var hour := OS.get_environment("NPC_SHOT_HOUR")
	if hour.is_empty():
		return
	var time := root.get_node_or_null("GameTimeManager")
	if time == null:
		return
	time.call("set_elapsed_game_seconds", (float(hour.to_float()) - 9.0) * 3600.0, false)


func _is_game_camera() -> bool:
	return not OS.get_environment("NPC_SHOT_GAME").is_empty()


func _setup_subject() -> bool:
	_npc = _tower.call("find_npc", NPC_ID) as Node3D
	if _npc == null:
		print("NPC_SHOT_FAIL no_npc")
		return false
	var snapshot: Dictionary = _npc.call("get_snapshot")
	print("NPC_SHOT_STANDBY %s at %s" % [
		str(snapshot.get("story_standby", false)),
		str(_npc.global_position),
	])
	var player := _tower.get("player") as Node3D
	if _is_game_camera():
		# 玩家视角：站在归航点，NPC 在 3.2m 外 → 会自动开口（这就是要拍的构图）。
		if player != null:
			player.global_position = SPAWN
			player.set("velocity", Vector3.ZERO)
		return true
	# 合成相机：把玩家挪远（10m 外），才能拍到"还没开口、站在边上等"的那一帧。
	if player != null:
		player.global_position = SPAWN + Vector3(-12.0, 0.0, 10.0)
		player.set("velocity", Vector3.ZERO)
		var player_camera := player.get("camera") as Camera3D
		if player_camera != null:
			player_camera.current = false
	_camera = Camera3D.new()
	root.add_child(_camera)
	_camera.fov = 70.0
	_camera.current = true
	return true


func _frame_camera() -> void:
	if _camera == null or _npc == null:
		return
	# 从归航点方向（+Z、略高）看过去，NPC 在画面偏一侧。
	var target := _npc.global_position + Vector3(0.0, 1.1, 0.0)
	_camera.global_position = _npc.global_position + Vector3(-1.6, 3.2, 6.2)
	_camera.look_at(target, Vector3.UP)


func _report() -> void:
	var snapshot: Dictionary = _npc.call("get_snapshot")
	print("NPC_SHOT_STATE delivered=%s standby=%s beat=%s" % [
		str(snapshot.get("story_beat_delivered", false)),
		str(snapshot.get("story_standby", false)),
		str(snapshot.get("story_beat_id", "")),
	])
	var bark := _npc.get_node_or_null("CharacterBark3D")
	if bark != null:
		print("NPC_SHOT_TEXT %s" % str(bark.call("get_current_text")))


func _save(base_name: String) -> void:
	var path := OS.get_environment("NPC_SHOT_OUT")
	if path.is_empty():
		var suffix := "_talk" if _is_game_camera() else "_standby"
		path = EVIDENCE_DIR + base_name.replace(".png", suffix + ".png")
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	print("NPC_SHOT %s error=%d size=%s" % [path, error, str(image.get_size())])
