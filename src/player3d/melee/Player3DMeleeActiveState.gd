class_name Player3DMeleeActiveState
extends Player3DMeleeStateBase


func enter() -> void:
	super.enter()
	melee.enter_phase("active")
	melee.resolve_active_hit()


func physics_update(_delta: float) -> void:
	if melee.get_phase_progress() >= 1.0:
		_go("recovery")
