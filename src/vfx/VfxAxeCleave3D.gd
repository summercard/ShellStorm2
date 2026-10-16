class_name VfxAxeCleave3D
extends "res://src/vfx/VfxMeleeRibbonBase3D.gd"
func _on_tick(elapsed: float, total: float) -> void:
	face_forward()
	visual.rotation.z = PI/2
	visual.rotation.x = lerpf(-1.2,1.2,clampf(elapsed/total,0,1))
	fade(1.0-elapsed/total)
