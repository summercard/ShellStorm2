class_name VfxAxeImpact3D
extends "res://src/vfx/VfxMeleeRibbonBase3D.gd"
func _on_tick(elapsed: float, total: float) -> void:
	face_forward()
	var t := clampf(elapsed/total,0,1)
	visual.scale = Vector3.ONE * effect_size * (.2+1.8*t)
	fade((1-t)*(1-t))
