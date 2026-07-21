class_name Player3DStateBase
extends State

var player: Node = null


func enter() -> void:
	player = owner


func _input_direction() -> Vector3:
	if player != null and player.has_method("_get_input_direction_3d"):
		return player.call("_get_input_direction_3d") as Vector3
	return Vector3.ZERO


func _announce(state_id: String, context: Dictionary = {}) -> void:
	if player != null and player.has_method("_set_presentation_state"):
		player.call("_set_presentation_state", state_id, context)


func _tick_dash_cooldown(delta: float) -> void:
	if player != null and player.has_method("_tick_dash_cooldown"):
		player.call("_tick_dash_cooldown", delta)


func _begin_dash() -> bool:
	return bool(player.call("_begin_dash")) if player != null and player.has_method("_begin_dash") else false


func _go(state_name: String) -> void:
	if player == null:
		return
	var machine := player.get("_state_machine") as StateMachine
	if machine != null:
		machine.transition_to(state_name)
