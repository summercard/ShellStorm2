class_name RunVendingTutorial3D
extends Node
## 首次实际接近当前房间活贩卖机的薄控制器；不打开商店、不消费局内金币、不改货架。

const NARRATIVE_ID := "nar_tutorial_run_vending_01"
const LOCK_REASON := "run_vending_tutorial"
const POLL_SECONDS := 0.1
const RETRY_SECONDS := 0.3

var _host_ref: WeakRef
var _active_generation := -1
var _generation := 0
var _active := false
var _pending := true
var _retry_left := 0.0
var _poll_left := 0.0
var _active_room_id := ""
var _active_station: WeakRef
var _active_player: WeakRef
var _request_count := 0
var _read_without_commit := false
var _phase := "waiting_evidence"


func configure(host: Node) -> void:
	_host_ref = weakref(host)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var player := host.get("player") as Player3D
	if is_instance_valid(player):
		if player.has_signal("hp_changed") and not player.hp_changed.is_connected(_on_player_hp_changed):
			player.hp_changed.connect(_on_player_hp_changed)
		if player.has_signal("presentation_state_changed") and not player.presentation_state_changed.is_connected(_on_player_state_changed):
			player.presentation_state_changed.connect(_on_player_state_changed)
		if not player.tree_exiting.is_connected(_on_player_exiting):
			player.tree_exiting.connect(_on_player_exiting)
	if host.has_signal("room_entered") and not host.room_entered.is_connected(_on_room_entered):
		host.room_entered.connect(_on_room_entered)
	if NarrativeDirector != null and not NarrativeDirector.narrative_finished.is_connected(_on_narrative_finished):
		NarrativeDirector.narrative_finished.connect(_on_narrative_finished)
	set_process(true)


func _process(delta: float) -> void:
	_retry_left = maxf(0.0, _retry_left - delta)
	if not _active:
		if not _pending or _retry_left > 0.0:
			return
		_poll_left -= delta
		if _poll_left > 0.0:
			return
		_poll_left = POLL_SECONDS
		_try_start()
		return
	if not _active_evidence_valid():
		_abort_owned("run_vending_tutorial_evidence_lost")
		_release_lock()
		_retry_left = RETRY_SECONDS
		_pending = true


func _try_start() -> void:
	var host := _host()
	if not _player_valid(host):
		_phase = "waiting_player"
		return
	if _completed() or _read_without_commit:
		_phase = "completed"
		_pending = false
		_release_lock()
		return
	var station_snapshot := _merchant_station_snapshot(host)
	if station_snapshot.is_empty():
		_phase = "waiting_evidence"
		_release_lock()
		return
	if not _host_ready(host):
		_phase = "waiting_idle"
		return
	_active = true
	_pending = false
	_active_generation = _generation
	_active_room_id = str(station_snapshot.get("room_id", ""))
	_active_station = weakref(station_snapshot.get("station") as Node)
	_active_player = weakref(host.get("player") as Node)
	_phase = "playing"
	_request_count += 1
	host.call("set_run_vending_tutorial_locked", true, LOCK_REASON)
	if not NarrativeDirector.play(NARRATIVE_ID, {"priority": 20, "merchant_station": station_snapshot}):
		_active = false
		_phase = "waiting_idle"
		_retry_left = RETRY_SECONDS
		_pending = true
		_release_lock()


func should_block_merchant_open(station: ServiceStation3D) -> bool:
	var host := _host()
	if station == null or not is_instance_valid(station) or _completed() or _read_without_commit:
		return false
	var snapshot := _merchant_station_snapshot(host)
	if snapshot.is_empty() or snapshot.get("station") != station:
		return false
	if not _active:
		_try_start()
	return _active


func _host() -> Node:
	return _host_ref.get_ref() as Node if _host_ref != null else null


func _player_valid(host: Node) -> bool:
	if not is_instance_valid(host) or not host.is_inside_tree() or host.is_queued_for_deletion():
		return false
	var player := host.get("player") as Player3D
	return (
		is_instance_valid(player)
		and player.is_inside_tree()
		and not player.is_queued_for_deletion()
		and player.current_hp > 0
		and player.get_state_machine_state() != "dead"
		and not bool(host.get("_completed"))
	)


func _merchant_station_snapshot(host: Node) -> Dictionary:
	if not host.has_method("get_run_vending_tutorial_station_snapshot"):
		return {}
	var value: Variant = host.call("get_run_vending_tutorial_station_snapshot")
	return value as Dictionary if value is Dictionary else {}


func _host_ready(host: Node) -> bool:
	if NarrativeDirector == null or NarrativeDirector.is_playing() or get_tree().paused or DialogueUI.is_active():
		return false
	if bool(host.get("_expedition_loading_active")) or bool(host.get("_scripted_input_hold")):
		return false
	var player := host.get("player") as Player3D
	if not is_instance_valid(player) or player.input_locked or bool(host.call("_has_exclusive_modal")):
		return false
	var inventory := host.get("_inventory_ui") as InventoryUI
	if is_instance_valid(inventory) and inventory.is_inventory_open():
		return false
	for property in ["_weapon_panel", "_merchant_ui", "_workbench_panel", "_full_map_overlay", "_death_dialog", "_fate_confirm"]:
		var modal := host.get(property) as Control
		if is_instance_valid(modal) and modal.is_visible_in_tree():
			return false
	return true


func _active_evidence_valid() -> bool:
	var host := _host()
	if not _active or _active_generation != _generation or not _player_valid(host):
		return false
	var player := host.get("player") as Player3D
	if _active_player == null or _active_player.get_ref() != player:
		return false
	var station := _merchant_station_snapshot(host)
	return (
		not station.is_empty()
		and str(station.get("room_id", "")) == _active_room_id
		and _active_station != null
		and _active_station.get_ref() == station.get("station")
	)


func _on_player_hp_changed(current: int, _maximum: int) -> void:
	if current <= 0:
		_abort_and_retry("run_vending_tutorial_player_dead")


func _on_player_state_changed(state_id: String, _context: Dictionary) -> void:
	if state_id == "dead":
		_abort_and_retry("run_vending_tutorial_player_dead")


func _on_player_exiting() -> void:
	_abort_owned("run_vending_tutorial_player_unloaded")
	_release_lock()


func _on_room_entered(_room: Variant) -> void:
	if _active and not _active_evidence_valid():
		_abort_and_retry("run_vending_tutorial_room_changed")
	_pending = true


func _on_narrative_finished(narrative_id: String, reason: String) -> void:
	if narrative_id != NARRATIVE_ID or not _active:
		return
	if NarrativeDirector != null and NarrativeDirector.active_id() == narrative_id:
		return
	_active = false
	_active_generation = -1
	if reason in ["duration", "flow.end"]:
		if not _completed():
			_read_without_commit = true
			_phase = "completed_read_without_commit"
	else:
		_phase = "waiting_evidence"
		_pending = true
		_read_without_commit = false
	_retry_left = RETRY_SECONDS
	_release_lock()


func _abort_and_retry(reason: String) -> void:
	_abort_owned(reason)
	_release_lock()
	_active = false
	_active_generation = -1
	_generation += 1
	_pending = true
	_phase = "waiting_evidence"
	_retry_left = RETRY_SECONDS


func _abort_owned(reason: String) -> void:
	var owned := _active
	if not owned:
		return
	_active = false
	_generation += 1
	if NarrativeDirector != null and NarrativeDirector.active_id() == NARRATIVE_ID:
		NarrativeDirector.abort(reason)


func _release_lock() -> void:
	var host := _host()
	if host != null and host.has_method("set_run_vending_tutorial_locked"):
		host.call("set_run_vending_tutorial_locked", false)


func _completed() -> bool:
	return BaseManager != null and BaseManager.has_narrative_completed(NARRATIVE_ID)


func get_snapshot() -> Dictionary:
	var host := _host()
	return {
		"phase": _phase,
		"pending": _pending,
		"active": _active,
		"request_count": _request_count,
		"generation": _generation,
		"active_generation": _active_generation,
		"active_room_id": _active_room_id,
		"history_completed": _completed(),
		"read_without_commit": _read_without_commit,
		"locked": bool(host.get("_run_vending_tutorial_locked")) if host != null else false,
		"lock_reason": str(host.get("_run_vending_tutorial_lock_reason")) if host != null else "",
	}


func _exit_tree() -> void:
	_abort_owned("run_vending_tutorial_scene_unloaded")
	_release_lock()
