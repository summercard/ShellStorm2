class_name VfxSpecialOil3D
extends VfxEffectBase3D

func _on_activate(_pos: Vector3, _color: Color, _size: float, context: Dictionary) -> void:
	lifetime = float(context.get("duration", 45.0))
	$OilSurface.scale = Vector3(effect_size, 1.0, effect_size)
	set_fade_ratio(1.0)

func _on_tick(elapsed: float, total: float) -> void:
	$OilSurface.transparency = maxf($OilSurface.transparency, 1.0 - smoothstep(0.0, 0.6, maxf(0.0, total - elapsed)))

func set_fade_ratio(value: float) -> void:
	$OilSurface.transparency = 1.0 - clampf(value, 0.0, 1.0)
