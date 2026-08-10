class_name Player3DMeleeRecoveryState
extends Player3DMeleeStateBase


func enter() -> void:
	super.enter()
	melee.enter_phase("recovery")


func physics_update(_delta: float) -> void:
	if melee.get_phase_progress() >= 1.0:
		melee.finish_recovery()
