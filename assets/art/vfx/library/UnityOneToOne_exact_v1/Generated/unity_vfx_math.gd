extends RefCounted
## Numeric conversion only. Normalized emitter time and normalized particle age
## are deliberately separate inputs at the call sites.

const MIRROR := Basis(Vector3.RIGHT, Vector3.UP, Vector3.FORWARD)

static func vec(v: Array) -> Vector3:
	return Vector3(float(v[0]), float(v[1]), float(v[2]))

static func polar(v: Vector3) -> Vector3:
	return MIRROR * v

static func axial(v: Vector3) -> Vector3:
	return -(MIRROR * v)

static func rgba(v: Array) -> Color:
	return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]))

static func curve(c: Dictionary, t: float, roll: float, fallback := 0.0) -> float:
	match str(c.get("mode", "")):
		"Constant": return float(c.constant)
		"TwoConstants": return lerpf(float(c.min), float(c.max), roll)
		"Curve": return float(c.multiplier) * _keys(c.keys, t, c.get("curve", {}))
		"TwoCurves":
			return float(c.multiplier) * lerpf(_keys(c.keys_min, t, c.get("curve_min", {})), _keys(c.keys_max, t, c.get("curve_max", {})), roll)
	return fallback

static func _keys(keys: Array, t: float, wraps: Dictionary) -> float:
	if keys.is_empty(): return 0.0
	var start: float = keys[0].t
	var finish: float = keys[-1].t
	if keys.size() == 1 or finish <= start: return float(keys[0].v)
	if t < start or t > finish:
		var mode: String = wraps.get("pre_wrap_mode" if t < start else "post_wrap_mode", "ClampForever")
		if mode == "Loop": t = start + fposmod(t - start, finish - start)
		elif mode == "PingPong": t = start + pingpong(t - start, finish - start)
		else: t = clampf(t, start, finish)
	if t <= start: return float(keys[0].v)
	for j in range(1, keys.size()):
		var b: Dictionary = keys[j]
		if t > float(b.t): continue
		var a: Dictionary = keys[j - 1]
		if t >= float(b.t): return float(b.v)
		var span := float(b.t) - float(a.t)
		var x := (t - float(a.t)) / span
		if not a.get("out", 0.0) is float and not a.get("out", 0.0) is int: return float(a.v)
		if not b.get("in", 0.0) is float and not b.get("in", 0.0) is int: return float(a.v)
		var out_tangent := float(a.get("out", 0.0))
		var in_tangent := float(b.get("in", 0.0))
		if not is_finite(out_tangent) or not is_finite(in_tangent): return float(a.v)
		var out_weight := str(a.get("weighted_mode", "None")) in ["Out", "Both", "2", "3"]
		var in_weight := str(b.get("weighted_mode", "None")) in ["In", "Both", "1", "3"]
		if out_weight or in_weight:
			var w0 := clampf(float(a.get("out_weight", 1.0 / 3.0)), 0.0, 1.0) if out_weight else 1.0 / 3.0
			var w1 := clampf(float(b.get("in_weight", 1.0 / 3.0)), 0.0, 1.0) if in_weight else 1.0 / 3.0
			var lo := 0.0
			var hi := 1.0
			for iteration in range(20):
				var q := (lo + hi) * 0.5
				if _bezier(0.0, w0, 1.0 - w1, 1.0, q) < x: lo = q
				else: hi = q
			return _bezier(float(a.v), float(a.v) + out_tangent * span * w0, float(b.v) - in_tangent * span * w1, float(b.v), (lo + hi) * 0.5)
		var x2 := x * x
		var x3 := x2 * x
		return (2.0 * x3 - 3.0 * x2 + 1.0) * float(a.v) + (x3 - 2.0 * x2 + x) * span * out_tangent + (-2.0 * x3 + 3.0 * x2) * float(b.v) + (x3 - x2) * span * in_tangent
	return float(keys[-1].v)

static func _bezier(a: float, b: float, c: float, d: float, t: float) -> float:
	var u := 1.0 - t
	return u*u*u*a + 3.0*u*u*t*b + 3.0*u*t*t*c + t*t*t*d

static func color_at(data: Dictionary, time: float, roll: float) -> Color:
	match str(data.get("mode", "Color")):
		"Color": return rgba(data.get("color", [1, 1, 1, 1]))
		"TwoColors": return rgba(data.color_min).lerp(rgba(data.color_max), roll)
		"Gradient": return _gradient(data.gradient, time)
		"TwoGradients": return _gradient(data.gradient_min, time).lerp(_gradient(data.gradient_max, time), roll)
		"RandomColor": return _gradient(data.gradient, roll)
	return Color.WHITE

static func _gradient(g: Dictionary, t: float) -> Color:
	var ck: Array = g.color_keys
	var ak: Array = g.alpha_keys
	var out := Color.WHITE
	var fixed: bool = g.get("mode", "Blend") == "Fixed"
	if not ck.is_empty():
		var rgb := _grad_key(ck, t, fixed)
		var rgb_a: Array = rgb[0]
		var rgb_b: Array = rgb[1]
		out = Color(float(rgb_a[1]), float(rgb_a[2]), float(rgb_a[3])).lerp(Color(float(rgb_b[1]), float(rgb_b[2]), float(rgb_b[3])), float(rgb[2]))
	if not ak.is_empty():
		var alpha := _grad_key(ak, t, fixed)
		out.a = lerpf(float(alpha[0][1]), float(alpha[1][1]), float(alpha[2]))
	return out

static func _grad_key(keys: Array, t: float, fixed: bool) -> Array:
	var a: Array = keys[0]
	if t <= float(a[0]): return [a, a, 0.0]
	for i in range(1, keys.size()):
		var b: Array = keys[i]
		if t <= float(b[0]):
			if fixed: return [b, b, 0.0]
			return [a, b, inverse_lerp(float(a[0]), float(b[0]), t)]
		a = b
	return [a, a, 0.0]

static func sheet_slot(sheet: Dictionary, age01: float, frame_roll: float, start_roll: float) -> int:
	if not bool(sheet.enabled): return 0
	var tiles: Array = sheet.tiles
	var count := int(tiles[0]) * int(tiles[1])
	var f := curve(sheet.frame_over_time, age01, frame_roll) * float(sheet.cycles) + curve(sheet.start_frame, 0.0, start_roll)
	# Floor, never round: even a 3/9–5/9 range only samples 3 and 4 for roll < 1.
	return posmod(floori(f * count + 1.0e-7), count)

static func limit_speed(v: Vector3, limit: float, dampen: float, dt: float) -> Vector3:
	var speed := v.length()
	if speed <= limit or speed < 1.0e-8 or dampen <= 0.0: return v
	var next := limit + (speed - limit) * pow(1.0 - clampf(dampen, 0.0, 1.0), 30.0 * dt)
	return v * (next / speed)

static func collision_velocity(v: Vector3, normal: Vector3, dampen: float, bounce: float) -> Vector3:
	return (v - normal * minf(0.0, v.dot(normal)) * (1.0 + bounce)) * (1.0 - dampen)
