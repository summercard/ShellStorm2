class_name VfxAxeCharge3D
extends "res://src/vfx/VfxMeleeRibbonBase3D.gd"
func _on_tick(elapsed: float, total: float) -> void:
	face_forward()
	visual.rotation.y = elapsed * 3.0
	visual.scale = Vector3.ONE * effect_size * (1.1 - minf(elapsed,1.0)*.3 + .04*sin(elapsed*15))
	fade(.65+.25*sin(elapsed*8))
