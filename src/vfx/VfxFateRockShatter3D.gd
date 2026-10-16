class_name VfxFateRockShatter3D
extends VfxEffectBase3D

func _on_activate(_pos: Vector3, _color: Color, _size: float, _context: Dictionary) -> void:
	scale = Vector3.ONE * effect_size
	_on_tick(0.0, lifetime)

func _on_tick(elapsed: float, total: float) -> void:
	var t := clampf(elapsed / maxf(total, 0.01), 0.0, 1.0)
	for index in get_child_count():
		var piece := get_child(index) as Node3D
		var angle := TAU * float(index) / 8.0
		piece.position = Vector3(cos(angle) * elapsed * 2.4, elapsed * (1.3 + 0.2 * (index % 3)) - 3.0 * elapsed * elapsed, sin(angle) * elapsed * 2.4)
		piece.rotation = Vector3(elapsed * 3.0, angle + elapsed * 4.0, elapsed)
		piece.scale = Vector3.ONE * (1.0 - t)
