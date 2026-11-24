class_name ChannelManagerEncounter
extends Node3D
## room_09 的频道管理者交互与局内金币分支。
## 只在 room_09 替代异常信号终端；门口战斗触发仍归 Dungeon3D。

signal encounter_finished
signal event_resolved(result: String)
signal portal_opened(result: String)

const NPC_SCENE := preload("res://assets/art/characters/npc/channel_manager/runtime/channel_manager_runtime.tscn")
const PORTAL_SCRIPT := preload("res://assets/art/characters/npc/channel_manager/runtime/channel_manager_portal.gd")
const PRICE := 1000
const INPUT_HOLD_SOURCE := "channel_manager_encounter"

var _dungeon: Node
var _room: Node3D
var _player: Node3D
var _npc: ChannelManagerRuntime
var _portal: Node3D
var _npc_state := "sleep"
var _skill_result := ""
var _player_in_range := false
var _started := false
var _first_conversation_done := false
var _reopened := false
var _searched := false
var _paid := false
var _payment_busy := false
var _payment_pending := false
var _interaction_active := false
var _interaction_serial := 0
var _dialogue_session := ""
var _dialogue_outcome := ""
var _information_button: Button
var _pay_button: Button
var _leave_button: Button
var _status_label: Label


func configure(dungeon: Node, room: Node3D, player: Node3D) -> void:
	_dungeon = dungeon
	_room = room
	_player = player
	name = "ChannelManagerEncounter"
	add_to_group("channel_manager_encounter")
	if _room != null and get_parent() == null:
		_room.add_child(self)
	_setup_npc()
	_setup_interaction()
	var dialogue_ui := _dialogue_ui()
	if dialogue_ui != null:
		dialogue_ui.connect("dialogue_finished", _on_dialogue_finished)
		dialogue_ui.connect("dialogue_shown", _on_dialogue_shown)
	if is_instance_valid(_player) and _player.has_signal("hp_changed"):
		_player.connect("hp_changed", _on_player_hp_changed)
	if is_instance_valid(_dungeon) and _dungeon.has_signal("run_completed"):
		_dungeon.connect("run_completed", _on_run_completed)


func _exit_tree() -> void:
	_end_interaction()


func _setup_interaction() -> void:
	# 交互控制器统一按距离轮询 provider；不新增 Area3D/碰撞节点。
	add_to_group("interaction_provider_3d")


func get_interaction_candidate(_candidate_player: Node) -> Dictionary:
	if _interaction_active or not is_instance_valid(_player) or not is_instance_valid(_npc):
		return {}
	if _player.global_position.distance_to(_npc.global_position) > 2.8:
		return {}
	return {"available": true, "interaction_id": "channel_manager_encounter", "position": _npc.global_position, "priority": 98, "prompt": "[E] 听一听屏幕里的声音"}


func perform_interaction(candidate_player: Node, _candidate: Dictionary) -> bool:
	if candidate_player != _player or get_interaction_candidate(candidate_player).is_empty() or not _can_start_interaction():
		return false
	interact()
	return true


func get_interaction_dot_anchor() -> Vector3:
	return _npc.global_position + Vector3.UP * 3.0


func is_interaction_dot_visible() -> bool:
	return false


func _setup_npc() -> void:
	if _npc != null and is_instance_valid(_npc):
		return
	_npc = NPC_SCENE.instantiate() as ChannelManagerRuntime
	_npc.name = "ChannelManagerNPC"
	_npc.auto_activate = false
	_npc.skill_windup_duration_override = 3.0
	_npc.skill_lock_duration_override = 0.58
	_npc.rng_seed = 91024
	_npc.set_process(true)
	add_child(_npc)
	# 房心略后，避免遮挡门口战斗通道；后续可由作者锚点覆写。
	_npc.position = Vector3(0.0, 0.0, -4.0)
	if _player != null:
		_npc.set_observer(_player)
	_npc.runtime_state_changed.connect(_on_npc_state_changed)

	_portal = PORTAL_SCRIPT.new()
	_portal.name = "ChannelManagerPortal"
	add_child(_portal)
	_portal.call("configure_room", _room)


func _can_start_interaction() -> bool:
	return not _interaction_active and not _dialogue_is_active() and is_instance_valid(_npc) and _npc.get_state_name() in ["sleep", "active_idle"]


func interact() -> bool:
	if not _can_start_interaction():
		return false
	_interaction_active = true
	_interaction_serial += 1
	var serial := _interaction_serial
	_set_input_hold(true)
	if not _first_conversation_done:
		_started = true
		if _npc.get_state_name() == "sleep":
			_npc.activate()
		if not await _wait_until(func() -> bool: return _npc.get_state_name() == "active_idle", 3.2, serial):
			if _is_current(serial):
				_end_interaction()
			return false
		if not await _say_sequence([
			["频道管理者", "别动……让我听清你的信号。你是……水？"],
			["主角", "你见过我的主人吗？"],
			["频道管理者", "见过的不是人，是一段被掐断的回声。它从这里经过，往更深处去了。"],
			["频道管理者", "我可以替你把那段回声翻回来……不过，换台要一千枚局内金币。"]
		], serial):
			return false
		_first_conversation_done = true
		_show_choices(false)
		return true
	if _paid:
		_reopened = true
		if not await _say_sequence([["频道管理者", "你又回来了。那道裂口还在闪……还想从哪一段开始听？"]], serial):
			return false
	else:
		if not await _say_sequence([["频道管理者", "那段回声还没有走远。你要继续听，还是先离开？"]], serial):
			return false
	_show_choices(true)
	return true


func _show_choices(show_information: bool) -> void:
	_close_choices()
	_pay_button = Button.new()
	_pay_button.text = "把金币交给它"
	_pay_button.custom_minimum_size = Vector2(0, 44)
	_leave_button = Button.new()
	_leave_button.text = "先离开这里"
	_leave_button.custom_minimum_size = Vector2(0, 44)
	_pay_button.disabled = _paid or _payment_busy
	_pay_button.pressed.connect(_on_pay_pressed)
	_leave_button.pressed.connect(_on_leave_pressed)
	var controls: Array[Control] = [_pay_button, _leave_button]
	if show_information:
		_information_button = Button.new()
		_information_button.text = "再问一句"
		_information_button.custom_minimum_size = Vector2(0, 44)
		_information_button.pressed.connect(_on_information_pressed)
		controls.append(_information_button)
	var dialogue_ui := _dialogue_ui()
	if dialogue_ui == null:
		_end_interaction()
		return
	dialogue_ui.call("mount_choice_controls", controls)
	_leave_button.grab_focus()


func _on_pay_pressed() -> void:
	if not has_dialogue_choices() or _payment_busy or _paid:
		return
	var serial := _interaction_serial
	_payment_busy = true
	_close_choices()
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager == null or not bool(game_manager.call("spend_currency", PRICE)):
		_payment_busy = false
		if await _say_sequence([["频道管理者", "你的口袋太轻了……等攒够一千枚，再来敲我的屏幕。"]], serial):
			_show_choices(true)
		return
	_payment_pending = true
	if not await _say_sequence([["频道管理者", "很好。别眨眼——我把旧频道翻出来给你看。"]], serial):
		return
	var opened := await _run_paid_skill(serial)
	if not _is_current(serial):
		return
	if opened:
		_paid = true
		_payment_pending = false
		event_resolved.emit(_skill_result)
		portal_opened.emit(_skill_result)
	_end_interaction()


func _on_leave_pressed() -> void:
	if has_dialogue_choices():
		_end_interaction()
		encounter_finished.emit()


func _on_information_pressed() -> void:
	if not has_dialogue_choices() or not is_instance_valid(_information_button):
		return
	var serial := _interaction_serial
	_close_choices()
	if not _searched:
		if not await _say_sequence([
			["频道管理者", "再靠近一点……嗯，听见了。你要找的人没有直走。"],
			["频道管理者", "他的回声被切成了三段：一段躲进监听区，另一段借中继走远了。"]
		], serial):
			return
		_searched = true
	else:
		if not await _say_sequence([["频道管理者", "它又在漂……别只看第一眼。监听会骗人，中继也会把脚步声带偏。"]], serial):
			return
	_show_choices(true)


func _run_paid_skill(serial: int) -> bool:
	if not is_instance_valid(_npc) or not is_instance_valid(_portal) or not _npc.trigger_skill():
		return false
	if not await _wait_until(func() -> bool: return _npc.get_state_name() == "skill_release", 5.0, serial):
		return false
	_skill_result = str(_npc.get_snapshot().get("result", ""))
	if _skill_result.is_empty() or not bool(_portal.call("open", _skill_result)):
		return false
	# Inputs stay held until the actual range-box animation reaches its final pose.
	return await _wait_until(func() -> bool: return bool(_portal.call("is_open")), 3.0, serial)


func _say_sequence(lines: Array, serial: int) -> bool:
	if not _is_current(serial):
		return false
	var payload: Array[Dictionary] = []
	var holds := [1.35, 1.70, 2.25, 1.05]
	var speeds := [25.0, 29.0, 21.0, 34.0]
	for index in range(lines.size()):
		var pair: Array = lines[index]
		var beat := mini(index, holds.size() - 1)
		payload.append({
			"speaker": str(pair[0]),
			"text": str(pair[1]),
			"chars_per_sec": speeds[beat],
			"auto_advance_sec": holds[beat],
		})
	var dialogue_ui := _dialogue_ui()
	if dialogue_ui == null:
		_end_interaction()
		return false
	_dialogue_outcome = ""
	_dialogue_session = dialogue_ui.show_lines({"lines": payload, "interrupt": false})
	if _dialogue_session.is_empty():
		_end_interaction()
		return false
	while _is_current(serial) and dialogue_ui.current_run_id() == _dialogue_session:
		await get_tree().process_frame
	if not _is_current(serial):
		return false
	_dialogue_session = ""
	if _dialogue_outcome not in ["completed", "skipped"]:
		_end_interaction()
		return false
	return true


func _wait_until(predicate: Callable, timeout: float, serial: int) -> bool:
	var left := timeout
	while _is_current(serial):
		if predicate.call():
			return true
		if left <= 0.0:
			break
		await get_tree().process_frame
		if _is_current(serial) and not get_tree().paused:
			left -= get_process_delta_time()
	return false


func _is_current(serial: int) -> bool:
	return _interaction_active and _interaction_serial == serial


func _set_input_hold(held: bool) -> void:
	if is_instance_valid(_dungeon) and _dungeon.is_inside_tree() and _dungeon.has_method("set_scripted_input_hold"):
		_dungeon.call("set_scripted_input_hold", held, false, INPUT_HOLD_SOURCE)


func has_dialogue_choices() -> bool:
	return _interaction_active and is_instance_valid(_leave_button) and _leave_button.is_visible_in_tree()


func dialogue_needs_cursor() -> bool:
	return has_dialogue_choices() or (_interaction_active and not _dialogue_session.is_empty() and _dialogue_is_active())


func try_close_dialogue() -> bool:
	if not _interaction_active or _payment_busy:
		return false
	_end_interaction()
	return true


func _on_dialogue_finished(run_id: String, outcome: String) -> void:
	if _interaction_active and run_id == _dialogue_session:
		_dialogue_outcome = outcome
		if outcome == "aborted":
			_end_interaction()


func _on_dialogue_shown(run_id: String, _line_id: String) -> void:
	if _interaction_active and (has_dialogue_choices() or (not _dialogue_session.is_empty() and run_id != _dialogue_session)):
		_end_interaction()


func _on_player_hp_changed(current: int, _maximum: int) -> void:
	if current <= 0:
		_end_interaction()


func _on_run_completed(_success: bool, _summary: Dictionary) -> void:
	_end_interaction()


func _end_interaction() -> void:
	if not _interaction_active:
		return
	_interaction_active = false
	_close_choices()
	var run_id := _dialogue_session
	_dialogue_session = ""
	var dialogue_ui := _dialogue_ui()
	if dialogue_ui != null and not run_id.is_empty() and dialogue_ui.current_run_id() == run_id:
		dialogue_ui.close()
	if _payment_pending:
		_payment_pending = false
		if is_instance_valid(_npc):
			_npc.cancel_skill()
		if is_instance_valid(_portal) and _portal.is_inside_tree():
			_portal.call("cancel_opening")
		var game_manager := get_node_or_null("/root/GameManager")
		if game_manager != null:
			game_manager.call("add_currency", PRICE)
	_payment_busy = false
	_set_input_hold(false)


func _on_npc_state_changed(_previous: String, current: String) -> void:
	_npc_state = current


func _dialogue_ui() -> Node:
	return get_tree().root.get_node_or_null("DialogueUI") if is_inside_tree() else null


func _dialogue_is_active() -> bool:
	var dialogue_ui := _dialogue_ui()
	return dialogue_ui != null and bool(dialogue_ui.call("is_active"))


func _close_choices() -> void:
	var dialogue_ui := _dialogue_ui()
	if dialogue_ui != null and is_instance_valid(_leave_button) and _leave_button.is_inside_tree():
		dialogue_ui.call("unmount_choice_controls")
	for button in [_pay_button, _leave_button, _information_button]:
		if is_instance_valid(button):
			button.queue_free()
	_pay_button = null
	_leave_button = null
	_information_button = null


func get_snapshot() -> Dictionary:
	return {
		"started": _started,
		"first_conversation_done": _first_conversation_done,
		"searched": _searched,
		"paid": _paid,
		"payment_busy": _payment_busy,
		"interaction_active": _interaction_active,
		"npc_state": _npc_state,
		"portal_open": _portal != null and bool(_portal.call("is_open")),
		"portal_result": str(_portal.get("result")) if _portal != null else "",
	}
