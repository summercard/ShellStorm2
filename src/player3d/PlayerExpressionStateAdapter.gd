class_name PlayerExpressionStateAdapter
extends RefCounted
## Initial random policy; future state-to-emotion policy belongs here, not in the service.
var _system: CharacterExpressionSystem
var _last_state := ""
var state_call_count := 0

func configure(system: CharacterExpressionSystem, initial_state: String) -> void:
	_system = system
	_last_state = initial_state

func on_presentation_state_changed(state_id: String, _context: Dictionary) -> void:
	if state_id == _last_state or not is_instance_valid(_system):
		return
	_last_state = state_id
	state_call_count += 1
	_system.request_random(2.0)
