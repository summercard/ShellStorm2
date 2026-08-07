class_name Player3DDeadState
extends Player3DStateBase

const DEATH_DURATION_S := 1.35
const LAUNCH_SPEED_MPS := 5.8
const LAUNCH_UP_SPEED_MPS := 4.6
const BOUNCE_UP_SPEED_MPS := 1.65
const DEATH_GRAVITY_MPS2 := 17.0

var _elapsed := 0.0
var _bounced := false
var _finished := false


func enter() -> void:
	super.enter()
	_announce("dead")
	player.set("input_locked", true)
	player.call("set_combat_enabled", false)
	_elapsed = 0.0
	_bounced = false
	_finished = false
	var direction := player.call("get_death_launch_direction") as Vector3
	player.set("velocity", direction * LAUNCH_SPEED_MPS + Vector3.UP * LAUNCH_UP_SPEED_MPS)
	player.call("_set_death_animation_progress", 0.0)


func physics_update(delta: float) -> void:
	_elapsed += maxf(0.0, delta)
	var velocity := player.get("velocity") as Vector3
	velocity.y -= DEATH_GRAVITY_MPS2 * maxf(0.0, delta)
	velocity.x = move_toward(velocity.x, 0.0, 4.2 * maxf(0.0, delta))
	velocity.z = move_toward(velocity.z, 0.0, 4.2 * maxf(0.0, delta))
	player.set("velocity", velocity)
	player.call("move_and_slide")
	velocity = player.get("velocity") as Vector3
	if player.call("is_on_floor"):
		if not _bounced and _elapsed >= 0.20:
			_bounced = true
			velocity.y = BOUNCE_UP_SPEED_MPS
			velocity.x *= 0.34
			velocity.z *= 0.34
		else:
			velocity.y = 0.0
			velocity.x = move_toward(velocity.x, 0.0, 12.0 * maxf(0.0, delta))
			velocity.z = move_toward(velocity.z, 0.0, 12.0 * maxf(0.0, delta))
		player.set("velocity", velocity)
	player.call("_set_death_animation_progress", _elapsed / DEATH_DURATION_S)
	if not _finished and _elapsed >= DEATH_DURATION_S:
		_finished = true
		player.set("velocity", Vector3.ZERO)
		player.call("_complete_death_animation")


func exit() -> void:
	pass
