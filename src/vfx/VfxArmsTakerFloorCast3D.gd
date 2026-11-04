class_name VfxArmsTakerFloorCast3D
extends VfxEffectBase3D

var _impact := false

func _on_configure(context: Dictionary) -> void:
	lifetime = maxf(0.05, float(context.get("duration", 0.7)))
	_impact = bool(context.get("impact", false))

func _on_activate(_position: Vector3, _color: Color, _size: float, _context: Dictionary) -> void:
	_on_tick(0.0, lifetime)

func _on_tick(elapsed: float, total: float) -> void:
	var progress := clampf(elapsed / total, 0.0, 1.0)
	var radius := lerpf(0.32, 1.8, progress) if _impact else lerpf(1.08, 0.83, progress)
	$Ring.scale = Vector3.ONE * radius * effect_size
	$Ticks.scale = $Ring.scale
	$Ticks.rotation.y = progress * 0.42 if not _impact else 0.0
	$Ring.visible = not _impact or progress < 0.74
	$Ticks.visible = not _impact or progress < 0.9
