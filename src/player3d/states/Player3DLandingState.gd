class_name Player3DLandingState
extends Player3DStateBase

var _remaining := 0.0


func enter() -> void:
	super.enter()
	_remaining = float(player.call("get_landing_duration"))
	_announce("landing", {
		"impact_speed": float(player.call("get_landing_impact_speed")),
		"duration": _remaining,
	})
	player.set("velocity", Vector3.ZERO)


func physics_update(delta: float) -> void:
	if int(player.get("current_hp")) <= 0:
		_go("dead")
		return
	_tick_dash_cooldown(delta)
	if _move_grounded(Vector3.ZERO, delta):
		return
	_remaining -= delta
	if _remaining <= 0.0:
		player.call("_transition_to_locomotion")
