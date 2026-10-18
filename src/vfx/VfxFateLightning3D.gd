class_name VfxFateLightning3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## Six authored arc segments, four large sparks, two endpoint halos and a travelling head.
const FLIGHT_TIME := 0.045
const ARC_LIFETIME := 0.20
var _end := Vector3.ZERO
var _delay := 0.0
var _points: Array[Vector3] = []

func _on_activate(_pos: Vector3, _color: Color, _size: float, context: Dictionary) -> void:
	rotation = Vector3.ZERO
	_delay = clampf(float(context.get("delay", 0.0)), 0.0, 0.15)
	lifetime = ARC_LIFETIME + _delay
	_end = (context.get("end_position", global_position + Vector3.RIGHT) as Vector3) - global_position
	var forward := _end.normalized() if _end.length_squared() > 0.0001 else Vector3.RIGHT
	var side := forward.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	_points.clear()
	for i in range(7):
		var jitter := (0.11 if i % 2 == 0 else -0.11) * effect_size if i > 0 and i < 6 else 0.0
		_points.append(_end * float(i) / 6.0 + side * jitter)
	$ArcLight.omni_range = 1.8 * effect_size
	_on_tick(0.0, lifetime)

func _on_tick(elapsed: float, _total: float) -> void:
	var age := elapsed - _delay
	var travel := clampf(age / FLIGHT_TIME, 0.0, 1.0)
	var fade := clampf(1.0 - maxf(0.0, age - FLIGHT_TIME) / (ARC_LIFETIME - FLIGHT_TIME), 0.0, 1.0)
	var enabled := age >= 0.0 and age < ARC_LIFETIME
	for i in range(6):
		var a := _points[i]
		var b := _points[i + 1]
		var fraction := clampf(travel * 6.0 - i, 0.0, 1.0)
		b = a.lerp(b, fraction)
		for kind in ["Core", "Halo"]:
			var mesh := get_node("%s%d" % [kind, i]) as MeshInstance3D
			mesh.visible = enabled and fraction > 0.001 and fade > 0.0
			if not mesh.visible:
				continue
			mesh.position = (a + b) * 0.5
			mesh.basis = Basis.looking_at((b - a).normalized(), Vector3.UP if absf((b-a).normalized().dot(Vector3.UP)) < 0.98 else Vector3.RIGHT)
			var width := (0.042 if kind == "Core" else 0.13) * effect_size * fade
			mesh.scale = Vector3(width, width, maxf(0.001, a.distance_to(b)))
	for i in range(4):
		var target_end := i >= 2
		var burst_age := age - (FLIGHT_TIME if target_end else 0.0)
		var p := get_node("Particles/P%d" % i) as MeshInstance3D
		p.visible = enabled and burst_age >= 0.0 and burst_age < 0.11
		var t := clampf(burst_age / 0.11, 0.0, 1.0)
		var ray := Vector3(-1.0 if i % 2 == 0 else 1.0, 0.7, 0.25).normalized()
		p.position = (_end if target_end else Vector3.ZERO) + ray * (0.06 + 0.40 * (1.0 - pow(1.0-t, 3.0))) * effect_size
		p.rotation = Vector3(0, 0, -0.8 if i % 2 == 0 else 0.8)
		p.scale = Vector3.ONE * (1.0 - t) * effect_size
	for name in ["StartGlow", "EndGlow"]:
		var node := get_node(name) as MeshInstance3D
		var glow_age := age - (FLIGHT_TIME if name == "EndGlow" else 0.0)
		var t := clampf(glow_age / 0.14, 0.0, 1.0)
		node.visible = enabled and glow_age >= 0.0 and glow_age < 0.14
		node.position = _end if name == "EndGlow" else Vector3.ZERO
		node.scale = Vector3.ONE * (0.8 + t * 0.7) * (1.0-t) * effect_size
	$Leader.visible = enabled and travel < 1.0
	$Leader.position = _end * travel
	$Leader.scale = Vector3.ONE * 0.45 * effect_size
	$ArcLight.position = _end * travel
	$ArcLight.light_energy = 0.8 * fade if enabled else 0.0

func _on_lifetime_expired() -> void:
	$ArcLight.light_energy = 0.0
