class_name Player3DClimbingState
extends Player3DStateBase


func enter() -> void:
	super.enter()
	_announce("climbing")
	player.set("is_dashing", false)


func physics_update(delta: float) -> void:
	if int(player.get("current_hp")) <= 0:
		player.call("_finish_ladder_climb", false)
		_go("dead")
		return
	player.call("_tick_ladder_climb", delta)
