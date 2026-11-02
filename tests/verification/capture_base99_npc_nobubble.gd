extends SceneTree
## 截图：**同机位、不说话**的对照帧，用来 A/B 量气泡底板的实际不透明度。
##
## 与 `capture_base99_npc_talk.gd` 的唯一差别：不调用 `advance_dialogue()`。
## 玩家/NPC 位置与相机完全一致，所以两张图同像素位置的差值 = 底板 alpha 的贡献。
##
##   APPDATA=<临时目录> NPC_SHOT_HOUR=12 godot --path . --resolution 1280x720 \
##       --script res://tests/verification/capture_base99_npc_nobubble.gd

var _tower: Node = null
var _npc: Node3D = null
var _frames := 0


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
		_npc = _tower.call("find_npc", "npc_base99_green") as Node3D
		if _npc == null:
			print("NPC_SHOT_FAIL no_npc")
			quit(1)
			return true
		_npc.set("patrol_enabled", false)
		var player := _tower.get("player") as Node3D
		player.global_position = _npc.global_position + Vector3(0.0, 0.0, 1.2)
		player.set("velocity", Vector3.ZERO)
	if _frames == 60:
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


func _save() -> void:
	var path := OS.get_environment("NPC_SHOT_OUT")
	if path.is_empty():
		path = "res://_scratch/npc_nobubble_ref.png"
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	print("NPC_SHOT %s error=%d" % [path, error])
