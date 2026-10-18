class_name VfxFateFrost3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## Caller owns state duration; one visual per active element, refreshed without spawning.
func _on_activate(_pos: Vector3, _color: Color, _size: float, _context: Dictionary) -> void:
	lifetime = 3600000.0
	rotation = Vector3.ZERO
	_on_tick(0.0, lifetime)

func _on_tick(elapsed: float, _total: float) -> void:

	$Patch.position = Vector3.UP * 0.025 * effect_size
	$Patch.scale = Vector3.ONE * effect_size
	for i in range(4):
		var angle := i * TAU / 4.0 + 0.3
		var p := get_node("Particles/P%d" % i) as MeshInstance3D
		p.position = Vector3(cos(angle) * 0.34, 0.12, sin(angle) * 0.34) * effect_size
		p.scale = Vector3(1, 0.85 + 0.15 * sin(elapsed * 4.0 + i), 1) * effect_size
		p.rotation = Vector3(0, -angle, 0.25)
