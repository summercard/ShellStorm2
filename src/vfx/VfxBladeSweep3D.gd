class_name VfxBladeSweep3D
extends "res://src/vfx/VfxMeleeRibbonBase3D.gd"
func _on_tick(elapsed: float, total: float) -> void:
	face_forward()
	visual.rotation.y = _side * lerpf(-1.4,1.4,clampf(elapsed/total,0,1))
	fade(1.0-elapsed/total)
