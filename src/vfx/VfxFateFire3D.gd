class_name VfxFateFire3D
extends "res://src/vfx/VfxEffectBase3D.gd"
var _ground_fire := false
var _illuminate := false
var _light_energy := 4.0
## Caller owns state duration; one visual per active element, refreshed without spawning.
func _on_activate(_pos: Vector3, _color: Color, _size: float, _context: Dictionary) -> void:
	lifetime = float(_context.get("duration", 3600000.0))
	_ground_fire = bool(_context.get("ground_fire", false))
	_illuminate = bool(_context.get("illuminate", false))
	$FireLight.visible = _illuminate
	_light_energy = float(_context.get("light_energy", 4.0))
	$FireLight.light_energy = _light_energy if _illuminate else 0.0
	$FireLight.omni_range = float(_context.get("light_range", 4.5 * effect_size))
	$Embers.visible = _ground_fire
	rotation = Vector3.ZERO
	_on_tick(0.0, lifetime)

func _on_tick(elapsed: float, _total: float) -> void:
	var fade := smoothstep(0.0, 0.6, maxf(0.0, _total - elapsed))
	if _illuminate:
		$FireLight.light_energy = _light_energy * fade * (0.92 + sin(elapsed * 9.0) * 0.06 + sin(elapsed * 17.0) * 0.04)
	if _ground_fire:
		for index in 3:
			var ember := get_node("Embers/E%d" % index) as MeshInstance3D
			var progress := fmod(elapsed * (0.52 + index * 0.08) + index * 0.33, 1.0)
			ember.position = Vector3(sin(elapsed * 1.8 + index * 2.1) * (0.12 + progress * 0.22), 0.35 + progress * 1.45, cos(elapsed + index * 2.4) * 0.18) * effect_size
			ember.scale = Vector3.ONE * sin(progress * PI) * effect_size * fade
			ember.transparency = 1.0 - fade

	for i in range(4):
		var phase := fmod(elapsed * 2.4 + i * 0.25, 1.0)
		var angle := i * TAU / 4.0 + sin(elapsed * 4.0 + i) * 0.12
		var p := get_node("Particles/P%d" % i) as MeshInstance3D
		p.position = Vector3(cos(angle) * 0.23, 0.30 + sin(phase * PI) * 0.26, sin(angle) * 0.23) * effect_size
		p.scale = Vector3(0.8 + 0.25 * sin(phase * TAU), 0.7 + 0.8 * sin(phase * PI), 0.8) * effect_size * fade
		p.transparency = 1.0 - fade
		p.rotation = Vector3(0.12 * sin(elapsed * 6.0 + i), angle, 0.16 * cos(elapsed * 5.0 + i))

func _on_lifetime_expired() -> void:
	$FireLight.light_energy = 0.0
	$FireLight.visible = false
	$Embers.visible = false
