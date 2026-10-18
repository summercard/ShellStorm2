class_name VfxFatePoison3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## Caller owns state duration; one visual per active element, refreshed without spawning.
func _on_activate(_pos: Vector3, _color: Color, _size: float, _context: Dictionary) -> void:
	lifetime = 3600000.0
	rotation = Vector3.ZERO
	_on_tick(0.0, lifetime)

func _on_tick(elapsed: float, _total: float) -> void:

	for i in range(4):
		var angle := elapsed * 1.6 + i * TAU / 4.0
		var p := get_node("Particles/P%d" % i) as MeshInstance3D
		p.position = Vector3(cos(angle) * 0.42, 0.42 + sin(elapsed * 2.7 + i) * 0.18, sin(angle) * 0.42) * effect_size
		p.scale = Vector3.ONE * (0.85 + 0.15 * sin(elapsed * 3.0 + i)) * effect_size
		p.rotation = Vector3.ZERO
