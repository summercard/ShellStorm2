class_name VfxFateRock3D
extends VfxEffectBase3D

func _on_configure(_context: Dictionary) -> void:
	scale = Vector3.ONE * effect_size
	$Rock.rotation = Vector3.ZERO

func _on_activate(_pos: Vector3, _color: Color, _size: float, _context: Dictionary) -> void:
	set_process(false) # The projectile owns lifetime and rolling distance.

func roll(radians: float) -> void:
	$Rock.rotate_x(-radians)
