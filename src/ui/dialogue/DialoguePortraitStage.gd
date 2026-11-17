class_name DialoguePortraitStage
extends Control
## 只拥有临时立绘会话；文字 run 与剧情完成仍由原拥有者管理。

const Catalog = preload("res://src/ui/dialogue/DialoguePortraitCatalog.gd")
const PLAYER_PORTRAIT = preload("res://assets/art/ui/dialogue/dialogue_portrait_player.tscn")
const NPC_PORTRAIT = preload("res://assets/art/ui/dialogue/dialogue_portrait_green.tscn")

var session_id := ""
var active_speaker := ""
var exit_running := false
var _participants: Dictionary = {}
var _options: Dictionary = {}
var _portraits_enabled := true
var _slots: Dictionary = {}
var _motions: Dictionary = {}
var _progress := {"left": 0.0, "right": 0.0}
var _generation := 0
var _sequence := 0
var _reduced := false
var _frozen := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)


func begin_presentation(id: String, participants: Array = [], options: Dictionary = {}) -> String:
	if id.is_empty():
		_sequence += 1
		id = "portrait_%d" % _sequence
	_generation += 1
	_kill_motions()
	for slot in _slots.values():
		slot.stop_rendering()
	_progress = {"left": 0.0, "right": 0.0}
	session_id = id
	active_speaker = ""
	exit_running = false
	_participants.clear()
	_options = options.duplicate(true)
	_portraits_enabled = bool(options.get("portraits_enabled", true))
	if not _portraits_enabled:
		for slot in _slots.values():
			remove_child(slot)
			slot.free()
		_slots.clear()
	_reduced = bool(options.get("reduce_motion", ProjectSettings.get_setting("accessibility/reduce_motion", false)))
	for entry in participants:
		if entry is Dictionary:
			var participant: Dictionary = entry.duplicate(true)
			if not participant.has("portrait_mode") and (bool(options.get("hologram", false)) or str(options.get("left_mode", "")) == "hologram"):
				participant["portrait_mode"] = "hologram"
			var config := Catalog.resolve(participant)
			if not config.is_empty():
				_participants[config["speaker_id"]] = config
	return session_id


func present_line(metadata: Dictionary) -> void:
	if session_id.is_empty() or exit_running or not _portraits_enabled:
		return
	var id := Catalog.speaker_id(metadata)
	active_speaker = id
	for slot in _slots.values():
		slot.set_focus(false)
	if id.is_empty():
		return
	var merged: Dictionary = (_participants.get(id, {}) as Dictionary).duplicate(true)
	merged.merge(metadata, true)
	# 未声明的行字段不覆盖会话给出的全息模式/表情。
	merged["speaker_id"] = id
	if id != "player" and not merged.has("portrait_mode"):
		merged["portrait_mode"] = "hologram" if bool(_options.get("hologram", false)) or str(_options.get("left_mode", "")) == "hologram" else "normal"
	var config := Catalog.resolve(merged)
	if config.is_empty():
		return
	_participants[id] = config
	var side := str(config["side"])
	var slot := _get_slot(side)
	var first_appearance := not slot.visible or slot.speaker_id != id
	if not slot.configure(config):
		slot.stop_rendering()
		return
	slot.set_focus(true)
	slot.set_motion(_reduced, _frozen)
	if first_appearance:
		_stop_motion(side)
		_progress[side] = 0.0
		slot.entering = true
		slot.exiting = false
		slot.show()
		_layout()
		var tween := create_tween()
		_motions[side] = tween
		_set_tween_pause(tween)
		tween.tween_method(_set_progress.bind(side), 0.0, 1.0, 0.09 if _reduced else 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_callback(_finish_enter.bind(side, _generation))
	else:
		slot.show()
	_layout()


func end_presentation(id: String, immediate: bool = false) -> void:
	if id.is_empty() or id != session_id:
		return
	if exit_running and not immediate:
		return
	_generation += 1
	_kill_motions()
	active_speaker = ""
	if immediate:
		_finish_exit(_generation)
		return
	exit_running = true
	var has_visible := false
	var tween := create_tween().set_parallel(true)
	_motions["exit"] = tween
	_set_tween_pause(tween)
	for side in _slots:
		var slot: DialoguePortrait3D = _slots[side]
		if not slot.visible:
			continue
		has_visible = true
		slot.entering = false
		slot.exiting = true
		tween.tween_method(_set_progress.bind(str(side)), float(_progress[side]), 0.0, 0.08 if _reduced else 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if not has_visible:
		tween.kill()
		_finish_exit(_generation)
		return
	tween.chain().tween_callback(_finish_exit.bind(_generation))


func set_paused(paused: bool) -> void:
	if _frozen == paused:
		return
	_frozen = paused
	for slot in _slots.values():
		slot.set_motion(_reduced, paused)
	for tween in _motions.values():
		_set_tween_pause(tween)


func get_presentation_snapshot() -> Dictionary:
	var count := 0
	var result := {"session_id": session_id, "active_speaker": active_speaker, "exit_running": exit_running}
	for side in ["left", "right"]:
		var state := {"speaker_id": "", "visible": false, "mode": "normal", "entering": false, "exiting": false, "rect": Rect2(), "mesh_count": 0, "source_path": ""}
		if _slots.has(side):
			state = _slots[side].get_snapshot()
			count += int(state["viewport_count"])
		result[side] = state
	result["viewport_count"] = count
	result["portraits_enabled"] = _portraits_enabled
	result["mode"] = str(_options.get("dialogue_mode", ""))
	return result


func _get_slot(side: String) -> DialoguePortrait3D:
	if _slots.has(side):
		return _slots[side] as DialoguePortrait3D
	var packed: PackedScene = PLAYER_PORTRAIT if side == "right" else NPC_PORTRAIT
	var slot := packed.instantiate() as DialoguePortrait3D
	slot.default_speaker_id = ""
	slot.name = "RightPortrait" if side == "right" else "LeftPortrait"
	slot.hide()
	add_child(slot)
	_slots[side] = slot
	_layout()
	return slot


func _set_progress(value: float, side: String) -> void:
	_progress[side] = value
	_layout()


func _layout() -> void:
	var ui_scale := clampf(size.y / 720.0, 0.65, 1.5) * clampf(float(_options.get("portrait_scale", 1.0)), 0.7, 1.2)
	var height := minf(330.0 * ui_scale, size.y * 0.47)
	var width := minf(250.0 * ui_scale, size.x * 0.21)
	height = minf(height, width / 0.76)
	for side in _slots:
		var slot: DialoguePortrait3D = _slots[side]
		var progress := float(_progress[side])
		var resting_x := size.x * 0.012 if side == "left" else size.x * 0.988 - width
		var outside_x := -width - 8.0 if side == "left" else size.x + 8.0
		slot.position = Vector2(resting_x if _reduced else lerpf(outside_x, resting_x, progress), size.y - 136.0 - height)
		slot.size = Vector2(width, height)
		slot.modulate.a = progress if _reduced else 1.0


func _finish_enter(side: String, generation: int) -> void:
	if generation != _generation or exit_running:
		return
	var slot: DialoguePortrait3D = _slots[side]
	slot.entering = false
	_progress[side] = 1.0
	_motions.erase(side)
	_layout()


func _finish_exit(generation: int) -> void:
	if generation != _generation:
		return
	for slot in _slots.values():
		slot.stop_rendering()
	_progress = {"left": 0.0, "right": 0.0}
	exit_running = false
	session_id = ""
	active_speaker = ""
	_participants.clear()
	_motions.clear()


func _stop_motion(side: String) -> void:
	if _motions.has(side):
		var tween: Tween = _motions[side]
		if tween.is_valid():
			tween.kill()
		_motions.erase(side)


func _kill_motions() -> void:
	for side in _motions.keys():
		_stop_motion(str(side))


func _set_tween_pause(tween: Tween) -> void:
	if not tween.is_valid():
		return
	if _frozen:
		tween.pause()
	else:
		tween.play()
