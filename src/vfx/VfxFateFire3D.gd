class_name VfxFateFire3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## Caller owns state duration; one visual per active element, refreshed without spawning.
func _on_activate(_pos: Vector3, _color: Color, _size: float, _context: Dictionary) -> void:
	lifetime = 3600000.0
	rotation = Vector3.ZERO
	_on_tick(0.0, lifetime)

func _on_tick(elapsed: float, _total: float) -> void:

	for i in range(4):
		var phase := fmod(elapsed * 2.4 + i * 0.25, 1.0)
		var angle := i * TAU / 4.0 + sin(elapsed * 4.0 + i) * 0.12
		var p := get_node("Particles/P%d" % i) as MeshInstance3D
		p.position = Vector3(cos(angle) * 0.23, 0.30 + sin(phase * PI) * 0.26, sin(angle) * 0.23) * effect_size
		p.scale = Vector3(0.8 + 0.25 * sin(phase * TAU), 0.7 + 0.8 * sin(phase * PI), 0.8) * effect_size
		p.rotation = Vector3(0.12 * sin(elapsed * 6.0 + i), angle, 0.16 * cos(elapsed * 5.0 + i))
