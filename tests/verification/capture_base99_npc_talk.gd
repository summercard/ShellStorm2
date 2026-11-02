extends SceneTree
## 截图：把玩家摆到 NPC 面前、并让它说话 —— 一次同时看三件事：
##   1. 气泡是否抬高到不再遮住角色（业主「对话框会遮住整个角色，往上放一些」）
##   2. 底板是否半透明（业主「黑色背景半透明」）
##   3. 白点与白色「(e) 交谈」是否完全消失（业主「这个白色的交谈和白点不要了」）
##
## 用法（**不要**套 timeout —— 本机 Git Bash 的 timeout 会吞掉 NPC_SHOT_* 环境变量）：
##   APPDATA=<临时目录> NPC_SHOT_HOUR=12 godot --path . --resolution 1280x720 \
##       --script res://tests/verification/capture_base99_npc_talk.gd

var _tower: Node = null
var _npc: Node3D = null
var _frames := 0
var _spoken := false


func _initialize() -> void:
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	_tower = packed.instantiate()
	_tower.set("test_mode", true)
	_tower.set("run_seed_override", 990099)
	root.add_child(_tower)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 4:
		_push_clock()
	if _frames == 12:
		if not _setup():
			quit(1)
			return true
	if _frames == 40 and _npc != null:
		# 站进交互半径，等控制器聚焦 → 先拍"有提示"的那一帧之前先说话。
		_npc.call("advance_dialogue")
		_spoken = true
	if _frames == 60 and _npc != null:
		_report()
		_save()
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


func _setup() -> bool:
	_npc = _tower.call("find_npc", "npc_base99_green") as Node3D
	if _npc == null:
		print("NPC_SHOT_FAIL no_npc")
		return false
	_npc.set("patrol_enabled", false)
	var player := _tower.get("player") as Node3D
	# 站在 NPC 正前方 1.2m（交互半径 1.5m 以内），并把视角对准它。
	player.global_position = _npc.global_position + Vector3(0.0, 0.0, 1.2)
	player.set("velocity", Vector3.ZERO)
	return true


func _report() -> void:
	print("NPC_TALK bubble_visible=%s bubble_y=%.2f dot=%s prompt=%s" % [
		str(_npc.call("is_speaking")),
		float(_npc.get("BARK_HEIGHT")),
		"none",
		str(_npc.call("get_snapshot").get("prompt_visible", false)),
	])
	var player := _tower.get("player") as Node3D
	var dot := player.get("interaction_controller").call("get_interaction_dot_snapshot", _npc) as Dictionary
	print("NPC_TALK dot_snapshot_empty=%s" % str(dot.is_empty()))


func _save() -> void:
	var path := OS.get_environment("NPC_SHOT_OUT")
	if path.is_empty():
		path = "res://docs/v0.1/audits/evidence/2026-11-02_base99_npc/base99_npc_talk.png"
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	print("NPC_SHOT %s error=%d size=%s" % [path, error, str(image.get_size())])
