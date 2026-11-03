class_name VfxSpecialBlast3D
extends VfxEffectBase3D

func _on_activate(_pos: Vector3, _color: Color, _size: float, context: Dictionary) -> void:
	lifetime = float(context.get("duration", 0.65))
	$BlastLight.omni_range = effect_size * 2.5
	_on_tick(0.0, lifetime)

func _on_tick(elapsed: float, total: float) -> void:
	var t := clampf(elapsed / total, 0.0, 1.0)
	$Shockwave.scale = Vector3.ONE * maxf(0.01, effect_size * (0.1 + t * 0.9))
	$Shockwave.transparency = t
	$Core.scale = Vector3.ONE * effect_size * (0.2 + sin(t * PI) * 0.55)
	$Core.transparency = t
	$BlastLight.light_energy = 5.0 * (1.0 - t) * (1.0 - t)
	for index in $Debris.get_child_count():
		var particle := $Debris.get_child(index) as MeshInstance3D
		var angle := index * TAU / float($Debris.get_child_count())
		particle.position = Vector3(cos(angle) * t, sin(t * PI) * 0.6, sin(angle) * t) * effect_size
		particle.rotation = Vector3(t * 8.0, angle, t * 5.0)
		particle.scale = Vector3.ONE * maxf(0.01, 1.0 - t)
		particle.transparency = t

func _on_lifetime_expired() -> void:
	$BlastLight.light_energy = 0.0
