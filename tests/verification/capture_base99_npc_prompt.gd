extends SceneTree
## 截图：`[E] 交谈` 黄色提示的实际观感（只在这一帧能看到）。
##
## 用法：
##   NPC_SHOT_HOUR=12 godot --path . --resolution 1280x720 --script res://tests/verification/capture_base99_npc_prompt.gd
##
## ⚠️ 不要套 `timeout` —— 本机 Git Bash 的 timeout 会吞掉环境变量，脚本读不到 `NPC_SHOT_*`。

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
	if _frames == 10:
		_npc = _tower.call("find_npc", "npc_base99_green") as Node3D
		if _npc == null:
			print("NPC_SHOT_FAIL no_npc")
			quit(1)
			return true
		_npc.set("patrol_enabled", false)
		# 把玩家塞进交互半径内（1.5m），让控制器聚焦，提示才会出现。
		var player := _tower.get("player") as Node3D
		player.global_position = _npc.global_position + Vector3(0.0, 0.0, 1.2)
		player.set("velocity", Vector3.ZERO)
	if _frames == 40:
		print("NPC_PROMPT state=%s" % str(_npc.call("get_snapshot").get("prompt_visible", false)))
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
		path = "res://docs/v0.1/audits/evidence/2026-11-02_base99_npc/base99_npc_prompt.png"
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	print("NPC_SHOT %s error=%d size=%s" % [path, error, str(image.get_size())])
