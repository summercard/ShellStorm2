extends Node
## Desktop gameplay capture. Launch this scene with isolated APPDATA/LOCALAPPDATA
## and Godot Movie Maker. Injects input only: no teleport, forced door state or damage.

const LOADING := "res://scenes/ExpeditionLoadingScreen.tscn"
const AXES := ["move_left", "move_right", "move_up", "move_down"]
var tower: TowerDescent3D
var player: Player3D
var shots := 0
var previous_ammo := -1
var crossed := false
var elapsed := 0.0
var started_at := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var sandbox := OS.get_environment("SS2_GAMEPLAY_VIDEO_ISOLATION").replace("\\", "/").simplify_path()
	var user_dir := OS.get_user_data_dir().replace("\\", "/").simplify_path()
	var manager := get_node_or_null("/root/BaseManager")
	if sandbox.is_empty() or not user_dir.begins_with(sandbox + "/") or manager == null or not ProjectSettings.globalize_path(str(manager.get("save_path"))).replace("\\", "/").simplify_path().begins_with(user_dir + "/") or DisplayServer.get_name() == "headless":
		_finish(2, "isolation or renderer check failed")
		return
	print("RECORD_USER_DIR ", user_dir)
	get_tree().current_scene = null
	GameEntryFlow.request_gameplay_entry(GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT)
	if not GameDesignConfig.select_expedition_level("expedition_01") or get_tree().change_scene_to_file(LOADING) != OK:
		_finish(2, "official entry failed")
		return
	var deadline := Time.get_ticks_msec() + 240000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var live := get_tree().current_scene as TowerDescent3D
		if live != null and not live._expedition_loading_active and live._room_by_id.has("room_01") and live.player != null:
			tower = live
			player = live.player
			break
	if player == null:
		_finish(2, "official level not ready")
		return
	started_at = Engine.get_process_frames()
	print("RECORD_START frame=", started_at, " room=", tower._current_room_id, " position=", player.global_position)
	var start := tower._room_by_id.get("start") as DungeonRoom3D
	var next := tower._room_by_id.get("room_01") as DungeonRoom3D
	var door := start.get_door_node_towards("room_01")
	if door == null:
		_finish(2, "entry door unavailable")
		return
	var anchor := door.global_position
	var from_center := anchor - start.global_position
	var outward := Vector3(signf(from_center.x), 0.0, 0.0) if absf(from_center.x) > absf(from_center.z) else Vector3(0.0, 0.0, signf(from_center.z))
	await _pause(1.0, anchor)
	# First move laterally a little to show the low wall with the production follow camera.
	var tangent := Vector3(outward.z, 0, -outward.x)
	await _walk(player.global_position + tangent * 2.0, anchor, 1.6, 0.42)
	if not await _walk(anchor - outward * 1.55, anchor, 7.0, 0.28):
		_finish(2, "could not reach the entry door")
		return
	await _pause(0.65, anchor)
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await get_tree().process_frame
	var release := InputEventAction.new()
	release.action = "interact"
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await _pause(0.85, anchor)
	print("RECORD_DOOR open=", door.is_open, " focus=", player.get_interaction_focus_snapshot())
	if not door.is_open:
		_finish(2, "normal interact input did not open entry door")
		return
	await _walk(anchor + outward * 4.2, anchor + outward * 9.0, 5.0, 0.4)
	await _pause(0.3, anchor + outward * 9.0)
	var curtain := tower.get_node_or_null("FlowViewWalls")
	crossed = tower._current_room_id == "room_01" and curtain != null and str(curtain.get_meta("view_wall_room_id", "")) == "room_01"
	print("RECORD_CROSS room=", tower._current_room_id, " curtain_room=", str(curtain.get_meta("view_wall_room_id", "")) if curtain != null else "missing", " frame=", Engine.get_process_frames())
	if not crossed:
		_finish(2, "player did not cross the doorway or curtain did not follow")
		return
	if player.weapon != null:
		previous_ammo = player.weapon.current_ammo
	await _fight(next, anchor, outward, tangent)
	await _pause(1.0, next.global_position)
	_finish(0, "entry, door and room switch captured")

func _pause(seconds: float, target: Vector3) -> void:
	_set_move(Vector3.ZERO)
	for i in range(roundi(seconds * 60.0)):
		_aim(target)
		await get_tree().physics_frame
	elapsed += seconds

func _walk(target: Vector3, aim_target: Vector3, seconds: float, tolerance: float) -> bool:
	for i in range(roundi(seconds * 60.0)):
		var diff := target - player.global_position
		diff.y = 0.0
		if diff.length() < tolerance:
			_set_move(Vector3.ZERO)
			return true
		_aim(aim_target)
		_set_move(diff)
		await get_tree().physics_frame
	_set_move(Vector3.ZERO)
	print("RECORD_WALK_TIMEOUT target=", target, " player=", player.global_position)
	return false

func _fight(room: DungeonRoom3D, anchor: Vector3, outward: Vector3, tangent: Vector3) -> void:
	# Fire through the real combat input and keep the player on the entrance side of the room.
	var move_target := anchor + outward * 6.3
	var fired_this_frame := false
	for i in range(660):
		if player.current_hp <= 0:
			break
		var diff := move_target - player.global_position
		diff.y = 0.0
		_set_move(diff if diff.length() > 0.55 else Vector3.ZERO)
		if i in [150, 305, 445, 570]:
			var sign_value := -1.0 if i in [305, 570] else 1.0
			move_target = anchor + outward * (5.3 if i > 400 else 7.0) + tangent * (2.0 * sign_value)
		var target := _nearest_enemy(room.room_id)
		_aim(target.global_position + Vector3.UP * 0.82 if target != null else player.global_position + outward * 8.0)
		var fire := i > 30 and (target != null or (shots == 0 and i < 95)) and i % 90 < 68
		if fire != fired_this_frame:
			if fire:
				Input.action_press("shoot")
			else:
				Input.action_release("shoot")
			fired_this_frame = fire
		if player.weapon != null:
			var now := player.weapon.current_ammo
			if previous_ammo >= 0 and now < previous_ammo:
				shots += previous_ammo - now
			previous_ammo = now
			if now == 0 and i % 60 == 1:
				Input.action_press("reload")
			elif i % 60 == 3:
				Input.action_release("reload")
		await get_tree().physics_frame
	_set_move(Vector3.ZERO)
	Input.action_release("shoot")
	Input.action_release("reload")
	print("RECORD_COMBAT shots=", shots, " room=", tower._current_room_id, " hp=", player.current_hp)

func _nearest_enemy(room_id: String) -> Enemy3D:
	var best: Enemy3D
	var distance := INF
	for node in get_tree().get_nodes_in_group("enemy_3d"):
		var enemy := node as Enemy3D
		if enemy == null or enemy.room_id != room_id or enemy.ai_state == "dead" or not enemy.is_visible_in_tree():
			continue
		var d := player.global_position.distance_squared_to(enemy.global_position)
		if d < distance:
			best = enemy
			distance = d
	return best

func _aim(target: Vector3) -> void:
	var camera := player.camera
	if camera == null or camera.is_position_behind(target):
		return
	var pos := camera.unproject_position(target)
	var vp := camera.get_viewport()
	var bounds := vp.get_visible_rect().size
	var motion := InputEventMouseMotion.new()
	motion.position = pos.clamp(Vector2(2.0, 2.0), bounds - Vector2(2.0, 2.0))
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	Input.flush_buffered_events()

func _set_move(delta: Vector3) -> void:
	var direction := delta.normalized()
	var values := [maxf(-direction.x, 0.0), maxf(direction.x, 0.0), maxf(-direction.z, 0.0), maxf(direction.z, 0.0)]
	for i in AXES.size():
		if values[i] > 0.14:
			Input.action_press(AXES[i], values[i])
		else:
			Input.action_release(AXES[i])

func _finish(code: int, result: String) -> void:
	_set_move(Vector3.ZERO)
	Input.action_release("shoot")
	Input.action_release("reload")
	print("RECORD_END code=", code, " result=", result, " start_frame=", started_at, " end_frame=", Engine.get_process_frames(), " crossed=", crossed, " shots=", shots)
	get_tree().quit(code)
