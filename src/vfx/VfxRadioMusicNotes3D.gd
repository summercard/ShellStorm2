class_name VfxRadioMusicNotes3D
extends VfxEffectBase3D
## 收音机持有的持续附件；预制五槽位，不借战斗池，不创建运行时几何。

const EMISSION_INTERVAL := 0.4
const NOTE_LIFETIME := 1.8
const RISE_M := 1.1
const SWAY_M := 0.09
const MAX_NOTES := 5

var _notes: Array[MeshInstance3D] = []
var _ages: Array[float] = []
var _serials: Array[int] = []
var _clock := 0.0
var _serial := 0

func _ready() -> void:
	for child in get_children():
		var note := child as MeshInstance3D
		if note != null:
			note.material_override = note.material_override.duplicate()
			_notes.append(note)
			_ages.append(-1.0)
			_serials.append(-1)
	set_emitting(false)

func set_emitting(enabled: bool) -> void:
	if enabled == _active and enabled:
		return
	_active = enabled
	visible = enabled
	set_process(enabled)
	if enabled:
		_clock = EMISSION_INTERVAL
	else:
		_clock = 0.0
		_serial = 0
		for index in _notes.size():
			_ages[index] = -1.0
			_serials[index] = -1
			_notes[index].hide()
			(_notes[index].material_override as StandardMaterial3D).albedo_color.a = 0.0

func _exit_tree() -> void:
	set_emitting(false)

func _process(delta: float) -> void:
	if not _active:
		return
	for index in _notes.size():
		if _ages[index] < 0.0:
			continue
		_ages[index] += delta
		if _ages[index] >= NOTE_LIFETIME:
			_ages[index] = -1.0
			_notes[index].hide()
		else:
			_update_note(index)
	_clock += delta
	if _clock >= EMISSION_INTERVAL:
		_clock = fmod(_clock, EMISSION_INTERVAL)
		for index in _notes.size():
			if _ages[index] < 0.0:
				_ages[index] = 0.0
				_serials[index] = _serial
				_serial += 1
				_notes[index].show()
				_update_note(index)
				break

func _update_note(index: int) -> void:
	var age := _ages[index]
	var phase := float(_serials[index]) * 2.39996
	var t := age / NOTE_LIFETIME
	_notes[index].position = Vector3(sin(phase) * 0.22 + sin(age * 2.8 + phase) * SWAY_M, RISE_M * t, cos(phase) * 0.06)
	_notes[index].scale = Vector3.ONE * (0.88 + 0.18 * sin(t * PI))
	var alpha := smoothstep(0.0, 0.16, age) * (1.0 - smoothstep(1.35, NOTE_LIFETIME, age)) * 0.88
	(_notes[index].material_override as StandardMaterial3D).albedo_color.a = alpha

func get_presentation_snapshot() -> Dictionary:
	var live: Array[Dictionary] = []
	for index in _notes.size():
		if _ages[index] >= 0.0 and _notes[index].visible:
			var pos := _notes[index].global_position
			live.append({"slot": index, "serial": _serials[index], "age": _ages[index], "y": pos.y, "position": [pos.x, pos.y, pos.z], "alpha": (_notes[index].material_override as StandardMaterial3D).albedo_color.a})
	return {"emitting": _active, "live_count": live.size(), "live": live, "budget": _notes.size()}
