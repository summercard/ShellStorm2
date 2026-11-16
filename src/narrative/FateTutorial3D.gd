class_name FateTutorial3D
extends Node
## 只保留真实实体/已认领报价的待播证据；文字、播放进度和历史各归原系统。

const DROP_ID := "nar_tutorial_fate_drop_01"
const OPEN_ID := "nar_tutorial_fate_open_01"
const POLL_SECONDS := 0.1
const RETRY_SECONDS := 0.3

var _host_ref: WeakRef
var _pickups: Dictionary = {}
var _offer_pickup_id := ""
var _offer_id := 0
var _offer_room_id := ""
var _generation := 0
var _active_generation := -1
var _active_id := ""
var _phase := "idle"
var _pending := false
var _poll_left := 0.0
var _retry_left := 0.0
var _request_count := 0
var _active_player: WeakRef
var _active_room_id := ""
# 完整播放但提交失败只在本会话让路，不冒充持久完成，也不反复轰炸玩家。
var _read_without_commit: Dictionary = {}
var _closing := false


func configure(host: Node) -> void:
	_host_ref = weakref(host)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var player := host.get("player") as Player3D
	if is_instance_valid(player):
		player.hp_changed.connect(_on_player_hp_changed)
		player.presentation_state_changed.connect(_on_player_state_changed)
		player.tree_exiting.connect(_on_player_exiting)
	host.connect("room_entered", _on_room_entered)
	if NarrativeDirector != null and not NarrativeDirector.narrative_finished.is_connected(_on_narrative_finished):
		NarrativeDirector.narrative_finished.connect(_on_narrative_finished)
	set_process(false)


func register_pickup(pickup: GroundLootPickup3D) -> void:
	if not is_instance_valid(pickup) or not pickup.is_inside_tree() or not pickup.requires_manual_interaction():
		return
	if not FateCardDropPickup3D.is_fate_pickup_data(pickup.item_data):
		return
	var pickup_id := str(pickup.item_data.get("fate_pickup_id", ""))
	if pickup_id.is_empty() or _stage_read(DROP_ID):
		return
	_pickups[pickup_id] = weakref(pickup)
	_wake()


func notify_offer_open(pickup_id: String, offer_id: int) -> void:
	var host := _host()
	if host == null or pickup_id.is_empty() or offer_id <= 0:
		return
	if str(host.get("_fate_offer_source")) != "pickup" or str(host.get("_fate_offer_pickup_id")) != pickup_id:
		return
	if not bool((host.get("_fate_pickup_claimed") as Dictionary).get(pickup_id, false)):
		return
	if _offer_id != offer_id or _offer_pickup_id != pickup_id:
		abort_for_overlay_close()
		_generation += 1
	_offer_pickup_id = pickup_id
	_offer_id = offer_id
	_offer_room_id = str(host.get("_current_room_id"))
	_closing = false
	if not _stage_read(DROP_ID) or not _stage_read(OPEN_ID):
		host.call("set_fate_tutorial_locked", true)
		_wake()


func abort_for_overlay_close() -> void:
	if _closing:
		return
	_closing = true
	_abort_owned("fate_overlay_closed")
	_generation += 1
	_offer_id = 0
	_offer_pickup_id = ""
	_offer_room_id = ""
	var host := _host()
	if host != null:
		host.call("set_fate_tutorial_locked", false)
	_closing = false


func _wake() -> void:
	_pending = true
	set_process(true)


func _process(delta: float) -> void:
	_retry_left = maxf(0.0, _retry_left - delta)
	var host := _host()
	if not _active_id.is_empty():
		if not _active_evidence_valid(host):
			_abort_owned("fate_tutorial_evidence_lost")
			_release_lock()
			_retry_left = RETRY_SECONDS
			_pending = true
		return
	if not _pending:
		set_process(false)
		return
	_poll_left -= delta
	if _poll_left > 0.0 or _retry_left > 0.0:
		return
	_poll_left = POLL_SECONDS
	if not _player_valid(host):
		_release_lock()
		return
	var offer_valid := _offer_valid(host)
	if _offer_id > 0 and not offer_valid:
		abort_for_overlay_close()
	if _stage_read(DROP_ID) and _stage_read(OPEN_ID):
		_set_idle()
		return
	var pickup := _visible_pickup(host)
	if not offer_valid and pickup == null:
		_phase = "waiting_evidence"
		if _pickups.is_empty():
			_set_idle()
		return
	if not _host_ready(host, offer_valid):
		_phase = "waiting_idle"
		return
	if offer_valid:
		host.call("set_fate_tutorial_locked", true)
		if not _offer_presentation_ready(host):
			_phase = "waiting_presentation"
			return
	var next_id := DROP_ID if not _stage_read(DROP_ID) else OPEN_ID
	if next_id == OPEN_ID and not offer_valid:
		_set_idle()
		return
	_active_generation = _generation
	_active_room_id = str(host.get("_current_room_id"))
	_active_player = weakref(host.get("player") as Node)
	_active_id = next_id
	_phase = "drop" if next_id == DROP_ID else "open"
	_request_count += 1
	if not NarrativeDirector.play(next_id, {"pickup_id": _offer_pickup_id if offer_valid else str(pickup.item_data.get("fate_pickup_id", "")), "offer_id": _offer_id, "generation": _generation}):
		_active_id = ""
		_retry_left = RETRY_SECONDS


func _host() -> Node:
	return _host_ref.get_ref() as Node if _host_ref != null else null


func _player_valid(host: Node) -> bool:
	if not is_instance_valid(host) or not host.is_inside_tree() or host.is_queued_for_deletion():
		return false
	var player := host.get("player") as Player3D
	return is_instance_valid(player) and player.is_inside_tree() and not player.is_queued_for_deletion() and player.current_hp > 0 and player.get_state_machine_state() != "dead" and not bool(host.get("_completed"))


func _offer_valid(host: Node) -> bool:
	if host == null or _offer_id <= 0 or _offer_room_id != str(host.get("_current_room_id")):
		return false
	var overlay := host.get("_fate_overlay") as Control
	return bool(host.get("_door_fate_active")) and not bool(host.get("_fate_overlay_closing")) and is_instance_valid(overlay) and overlay.is_visible_in_tree() and str(host.get("_fate_offer_source")) == "pickup" and str(host.get("_fate_offer_pickup_id")) == _offer_pickup_id and int(host.get("_fate_door_offer_id")) == _offer_id and bool((host.get("_fate_pickup_claimed") as Dictionary).get(_offer_pickup_id, false))


func _visible_pickup(host: Node) -> GroundLootPickup3D:
	var current_room := str(host.get("_current_room_id"))
	for pickup_id: String in _pickups.keys():
		var pickup := (_pickups[pickup_id] as WeakRef).get_ref() as GroundLootPickup3D
		if not is_instance_valid(pickup) or not pickup.is_inside_tree() or pickup.is_queued_for_deletion() or bool((host.get("_fate_pickup_claimed") as Dictionary).get(pickup_id, false)):
			_pickups.erase(pickup_id)
			continue
		var room := pickup.get_parent() as DungeonRoom3D
		if is_instance_valid(room) and host.is_ancestor_of(room) and room.room_id == current_room and str(pickup.item_data.get("source_room_id", "")) == current_room and pickup.is_visible_in_tree() and pickup.is_pickup_available():
			return pickup
	return null


func _host_ready(host: Node, own_offer: bool) -> bool:
	if NarrativeDirector == null or NarrativeDirector.is_playing() or get_tree().paused or DialogueUI.is_active():
		return false
	if bool(host.get("_expedition_loading_active")) or bool(host.get("_scripted_input_hold")):
		return false
	var player := host.get("player") as Player3D
	if not own_offer and (player.input_locked or bool(host.call("_has_exclusive_modal"))):
		return false
	var inventory := host.get("_inventory_ui") as InventoryUI
	if is_instance_valid(inventory) and inventory.is_inventory_open():
		return false
	for property in ["_weapon_panel", "_merchant_ui", "_workbench_panel", "_full_map_overlay", "_death_dialog", "_fate_confirm"]:
		var modal := host.get(property) as Control
		if is_instance_valid(modal) and modal.is_visible_in_tree():
			return false
	return not bool(host.get("_fate_purchase_busy"))


func _offer_presentation_ready(host: Node) -> bool:
	var presentation := host.get("_fate_presentation") as Control
	if not is_instance_valid(presentation) or bool(presentation.get("_moving")):
		return false
	var row := presentation.get("row") as Control
	if not is_instance_valid(row) or not row.is_visible_in_tree():
		return false
	var buttons: Array = host.get("_fate_choice_buttons")
	if buttons.is_empty() or buttons.size() != (host.get("_door_fate_choices") as Array).size():
		return false
	for button: Button in buttons:
		if not is_instance_valid(button) or not button.is_visible_in_tree() or not bool(button.get_meta("tarot_face_ready", false)):
			return false
	return true


func _active_evidence_valid(host: Node) -> bool:
	if not _player_valid(host) or _active_generation != _generation or _active_room_id != str(host.get("_current_room_id")):
		return false
	if _active_player == null or _active_player.get_ref() != host.get("player"):
		return false
	return _offer_valid(host) if _offer_id > 0 else (_active_id == DROP_ID and _visible_pickup(host) != null)


func _on_player_exiting() -> void:
	_abort_owned("fate_tutorial_player_unloaded")
	var host := _host()
	if host != null:
		host.call("set_fate_tutorial_locked", false)


func _on_room_entered(room: Variant) -> void:
	if not _active_id.is_empty() and (not is_instance_valid(room) or str(room.get("room_id")) != _active_room_id):
		_abort_owned("fate_tutorial_room_changed")
		_release_lock()
		_retry_left = RETRY_SECONDS


func _on_player_hp_changed(current: int, _maximum: int) -> void:
	if current <= 0:
		_abort_owned("fate_tutorial_player_dead")
		_release_lock()
		_retry_left = RETRY_SECONDS


func _on_player_state_changed(state_id: String, _context: Dictionary) -> void:
	if state_id == "dead":
		_abort_owned("fate_tutorial_player_dead")
		_release_lock()
		_retry_left = RETRY_SECONDS


func _on_narrative_finished(narrative_id: String, reason: String) -> void:
	if narrative_id != _active_id or _active_generation != _generation:
		return
	if NarrativeDirector != null and NarrativeDirector.active_id() == narrative_id:
		return
	_active_id = ""
	if reason in ["duration", "flow.end"] and not _completed(narrative_id):
		_read_without_commit[narrative_id] = true
	_retry_left = RETRY_SECONDS
	_release_lock()
	_wake()


func _abort_owned(reason: String) -> void:
	var owned := _active_id
	_active_id = ""
	if not owned.is_empty() and NarrativeDirector != null and NarrativeDirector.active_id() == owned:
		NarrativeDirector.abort(reason)


func _completed(narrative_id: String) -> bool:
	return BaseManager != null and BaseManager.has_narrative_completed(narrative_id)


func _stage_read(narrative_id: String) -> bool:
	return _completed(narrative_id) or _read_without_commit.has(narrative_id)


func _release_lock() -> void:
	var host := _host()
	if host != null:
		# 两段之间保留同一offer的表现锁；重试也不漏出购买/退出输入。
		var held := _player_valid(host) and _offer_valid(host) and (not _stage_read(DROP_ID) or not _stage_read(OPEN_ID))
		host.call("set_fate_tutorial_locked", held)


func _set_idle() -> void:
	_phase = "idle"
	_pending = false
	_pickups.clear()
	_release_lock()
	set_process(false)


func get_snapshot() -> Dictionary:
	var host := _host()
	return {"phase": _phase, "pending": _pending, "drop_completed": _completed(DROP_ID), "open_completed": _completed(OPEN_ID), "request_count": _request_count, "active_id": _active_id, "locked": bool(host.get("_fate_tutorial_locked")) if host != null else false, "offer_id": _offer_id, "generation": _generation, "history_retry_deferred": _read_without_commit.keys()}


func _exit_tree() -> void:
	_abort_owned("fate_tutorial_scene_unloaded")
	var host := _host()
	if host != null:
		host.call("set_fate_tutorial_locked", false)
