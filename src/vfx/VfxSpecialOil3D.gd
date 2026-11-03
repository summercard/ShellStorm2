class_name VfxSpecialOil3D
extends VfxEffectBase3D

func _on_activate(_pos: Vector3, _color: Color, _size: float, context: Dictionary) -> void:
	lifetime = float(context.get("duration", 45.0))
	$OilSurface.scale = Vector3(effect_size, 1.0, effect_size)
