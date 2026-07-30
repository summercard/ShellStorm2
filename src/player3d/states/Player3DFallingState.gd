class_name Player3DFallingState
extends Player3DStateBase


func enter() -> void:
	super.enter()
	player.set("is_dashing", false)
	_announce("falling", {
		"start_y": float(player.get("_fall_start_y")),
		"velocity_y": (player.get("velocity") as Vector3).y,
	})


func physics_update(delta: float) -> void:
	if int(player.get("current_hp")) <= 0:
		_go("dead")
		return
	_tick_dash_cooldown(delta)
	var direction := Vector3.ZERO
	if not bool(player.get("input_locked")):
		direction = _input_direction()
		if direction != Vector3.ZERO:
			player.set("last_move_direction", direction)
	var landed := bool(player.call(
		"move_airborne",
		direction * float(player.call("get_move_speed")),
		delta
	))
	if landed:
		_go("landing")
