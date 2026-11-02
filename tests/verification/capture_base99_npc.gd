extends SceneTree
## 截图：真实渲染器下拍 **正式 99F 基地**里的 NPC（衣柜绿皮肤 / 面饰 / 黄色交互提示 / 台词气泡）。
##
## 用法（必须**不带** `--headless`，否则拿到的是 dummy renderer）：
##   godot --path . --resolution 1280x720 --script res://tests/verification/capture_base99_npc.gd
##   NPC_SHOT_HOUR=12 NPC_SHOT_CLOSE=1 godot ... --resolution 900x900 ...
##   NPC_SHOT_HOUR=12 NPC_SHOT_WALK=1 godot ...   # 走路中构图，用来看有没有残影
##
## 环境变量：
##   NPC_SHOT_HOUR  —— 世界时间（小时，0–24）；不设则用档内当前时间
##   NPC_SHOT_CLOSE —— 任意非空值 ⇒ 正面近景（只用来看脸，不代表游戏观感）
##   NPC_SHOT_WALK  —— 任意非空值 ⇒ 保持巡逻、拍"正在走"的那一帧（查残影/拖影）
##   NPC_SHOT_OUT   —— 输出路径，默认 `res://docs/v0.1/audits/evidence/2026-11-02_base99_npc/base99_npc_shot.png`
##
## ⚠️ 场景口径：拍的是 `TowerDescent3D.tscn` 的 99F `facility` 房间。
##   2026-11-02 第一版错拍了 `BaseWorld3D.tscn`（旧的"基地与荒野"兼容场景），
##   主人一眼看出「这不是我的基地里头」—— 别再退回那个场景拍。
##
## ⚠️ 朝向：`_yaw` / `_yaw_target` 都要设。只改 `rotation.y` 会被 `_tick_pose`
##   每帧覆盖，拍出来永远是背面（Godot 节点前方是 -Z，正面朝相机 = yaw 取 PI）。
##
## ⚠️ 高度：2026-11-02 起 NPC 与玩家同口径（资产 1.519m × 0.8 ≈ 1.215m）。
##   相机目标高度按 1.2m 角色重算；沿用旧的 1.5m 数值会把角色压在画面下缘。

var _tower: Node = null
var _npc: Node3D = null
var _camera: Camera3D = null
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
		if not _setup_subject():
			quit(1)
			return true
	if _frames == 16 and _npc != null and _camera != null:
		_frame_camera()
		_npc.call("advance_dialogue")
	# 走路模式多等 30 帧，让步态进入中段再拍。
	if _frames == 46 and _camera != null:
		var walking := not OS.get_environment("NPC_SHOT_WALK").is_empty()
		if walking:
			_frame_camera()
		_save()
		quit(0)
		return true
	return false


## 世界时刻是「从 09:00 起点起累计的秒数」，所以要显示 hour 点就得减掉 9 小时。
func _push_clock() -> void:
	var hour := OS.get_environment("NPC_SHOT_HOUR")
	if hour.is_empty():
		return
	var time := root.get_node_or_null("GameTimeManager")
	if time == null:
		return
	time.call("set_elapsed_game_seconds", (float(hour.to_float()) - 9.0) * 3600.0, false)
	var snapshot: Dictionary = time.call("get_time_snapshot")
	print("NPC_SHOT_HOUR %s solar=%s" % [hour, JSON.stringify(snapshot.get("solar", {}))])


func _setup_subject() -> bool:
	_npc = _tower.call("find_npc", "npc_base99_green") as Node3D
	if _npc == null:
		print("NPC_SHOT_FAIL no_npc")
		return false
	var walking := not OS.get_environment("NPC_SHOT_WALK").is_empty()
	_npc.set("patrol_enabled", walking)
	if not walking:
		_npc.set("_yaw", PI)
		_npc.set("_yaw_target", PI)
	# 游戏视角模式：直接用玩家自己的相机（相机的相对位姿由场景决定），
	# 把玩家摆到 NPC 正前方 3.4m。这才是业主实际看到的构图。
	if not OS.get_environment("NPC_SHOT_GAME").is_empty():
		var player := _tower.get("player") as Node3D
		if player != null:
			player.global_position = _npc.global_position + Vector3(0.0, 0.0, 3.4)
			player.set("velocity", Vector3.ZERO)
		return true
	# 关掉游戏自己那台相机，避免两台相机抢 current。
	var player_camera := _tower.get("player").get("camera") as Camera3D
	if player_camera != null:
		player_camera.current = false
	_camera = Camera3D.new()
	root.add_child(_camera)
	_camera.fov = 70.0
	_camera.current = true
	return true


func _frame_camera() -> void:
	# 游戏视角模式不动相机。
	if not OS.get_environment("NPC_SHOT_GAME").is_empty():
		return
	var target := _npc.global_position + Vector3(0.0, 0.85, 0.0)
	# 约 4.9m 距离、约 32° 俯角，接近玩家在基地里的实际观感。
	_camera.global_position = target + Vector3(0.0, 2.6, 4.2)
	if not OS.get_environment("NPC_SHOT_CLOSE").is_empty():
		var head := _npc.global_position + Vector3(0.0, 0.95, 0.0)
		_camera.global_position = head + Vector3(0.0, 0.20, 0.95)
		target = head
	_camera.look_at(target, Vector3.UP)


func _save() -> void:
	var path := OS.get_environment("NPC_SHOT_OUT")
	if path.is_empty():
		path = "res://docs/v0.1/audits/evidence/2026-11-02_base99_npc/base99_npc_shot.png"
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	print("NPC_SHOT %s error=%d size=%s" % [path, error, str(image.get_size())])
