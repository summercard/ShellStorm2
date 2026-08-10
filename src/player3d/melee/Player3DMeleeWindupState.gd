class_name Player3DMeleeWindupState
extends Player3DMeleeStateBase


func enter() -> void:
	super.enter()
	melee.enter_phase("windup")


func physics_update(_delta: float) -> void:
	if melee.get_phase_progress() >= 1.0:
		_go("active")
