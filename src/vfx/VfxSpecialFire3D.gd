class_name VfxSpecialFire3D
extends VfxEffectBase3D

func _on_activate(_pos: Vector3, _color: Color, _size: float, context: Dictionary) -> void:
	lifetime = float(context.get("duration", 5.0))
	$Flames.scale = Vector3(effect_size, minf(effect_size, 1.35), effect_size)
	$Scorch.scale = Vector3(effect_size, 1.0, effect_size)
	$FireLight.omni_range = effect_size * 2.0
	$FireLight.light_energy = 1.5 if effect_size > 1.0 else 0.0
	_on_tick(0.0, lifetime)

func _on_tick(elapsed: float, total: float) -> void:
	var fade := clampf((total - elapsed) / 0.35, 0.0, 1.0)
	$FireLight.light_energy = (1.5 if effect_size > 1.0 else 0.0) * fade * (0.9 + sin(elapsed * 12.0) * 0.1)
	for index in $Flames.get_child_count():
		var flame := $Flames.get_child(index) as Node3D
		var pulse := 0.82 + sin(elapsed * (7.0 + index * 0.37) + index * 2.1) * 0.18
		flame.scale = Vector3(0.9, pulse * fade, 0.9)

func _on_lifetime_expired() -> void:
	$FireLight.light_energy = 0.0
