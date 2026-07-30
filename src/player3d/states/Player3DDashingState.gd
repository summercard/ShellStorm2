class_name Player3DDashingState
extends Player3DStateBase

var _remaining := 0.0


func enter() -> void:
	super.enter()
	_announce("dashing", {"direction": player.get("dash_direction")})
	player.set("is_dashing", true)
	player.set("is_invincible", true)
	_remaining = float(player.call("get_dash_duration"))
	if AudioManager != null:
		AudioManager.play_dash_sfx()
	if player.has_signal("dash_started"):
		player.emit_signal("dash_started")


func physics_update(delta: float) -> void:
	if int(player.get("current_hp")) <= 0:
		_go("dead")
		return
	_tick_dash_cooldown(delta)
	if bool(player.get("input_locked")):
		player.set("velocity", Vector3.ZERO)
		_go("locked")
		return
	if _move_grounded(
		player.get("dash_direction") * float(player.call("get_dash_speed")),
		delta
	):
		return
	_remaining -= delta
	if _remaining <= 0.0:
		player.call("_transition_to_locomotion")


func exit() -> void:
	player.set("is_dashing", false)
	if player.has_signal("dash_ended"):
		player.emit_signal("dash_ended")
