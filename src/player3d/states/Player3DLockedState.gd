class_name Player3DLockedState
extends Player3DStateBase


func enter() -> void:
	super.enter()
	_announce("locked")
	player.set("velocity", Vector3.ZERO)


func physics_update(delta: float) -> void:
	if int(player.get("current_hp")) <= 0:
		_go("dead")
		return
	_tick_dash_cooldown(delta)
	if _move_grounded(Vector3.ZERO, delta):
		return
	if not bool(player.get("input_locked")):
		player.call("_transition_to_locomotion")
