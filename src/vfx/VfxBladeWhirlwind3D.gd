class_name VfxBladeWhirlwind3D
extends "res://src/vfx/VfxMeleeRibbonBase3D.gd"
func _on_tick(elapsed: float, total: float) -> void:
	visual.rotation.y = -elapsed * TAU / .55
	visual.position.y = .05*sin(elapsed*18)
	fade(.65+.15*sin(elapsed*22))
