extends Control

## 命运卡反馈的独立视觉层：只画边缘短闪与少量方块粒子，不接管输入。

var accent_color := Color.WHITE
var _hovered := false
var _flash_elapsed := 999.0
var _flash_duration := 0.34
var _particles: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func setup(color: Color) -> void:
	accent_color = Color(color, 1.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func set_hovered(value: bool) -> void:
	_hovered = value
	queue_redraw()


func trigger_flash() -> void:
	if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)):
		return
	_flash_elapsed = 0.0
	_particles.clear()
	_spawn_particles()
	set_process(true)
	queue_redraw()


func reset_feedback() -> void:
	_hovered = false
	_flash_elapsed = 999.0
	_particles.clear()
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	_flash_elapsed += delta
	for particle in _particles:
		var position: Vector2 = particle["position"]
		var velocity: Vector2 = particle["velocity"]
		var life: float = float(particle["life"]) - delta
		particle["position"] = position + velocity * delta
		particle["life"] = life
	_particles = _particles.filter(func(particle: Dictionary) -> bool: return float(particle["life"]) > 0.0)
	if _flash_elapsed >= _flash_duration and _particles.is_empty():
		set_process(false)
	queue_redraw()


func _draw() -> void:
	var bounds := Rect2(Vector2(2.0, 2.0), size - Vector2(4.0, 4.0))
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	# 棱镜线框：**只画 1px 线**。旧版那两道 grow(3)/grow(1) 的粗描边叠起来是一圈
	# 发光晕，属上一代语言；这里把"闪一下"完全交给线的亮度变化表达。
	var flash_ratio := clampf(1.0 - _flash_elapsed / _flash_duration, 0.0, 1.0)
	var edge_alpha := 0.20 if _hovered else 0.0
	var line_width := 1.0
	if flash_ratio > 0.0:
		edge_alpha = maxf(edge_alpha, 0.42 + flash_ratio * 0.52)
		# 闪的瞬间线提到 2px（仍是方角实线，不是发光），落回后保持 1px。
		line_width = 1.0 + flash_ratio
	if edge_alpha > 0.0:
		draw_rect(bounds, Color(accent_color, edge_alpha), false, line_width)
	for particle in _particles:
		var life := clampf(float(particle["life"]) / 0.34, 0.0, 1.0)
		var particle_size := float(particle["size"])
		var particle_position: Vector2 = particle["position"]
		draw_rect(
			Rect2(particle_position - Vector2.ONE * particle_size * 0.5, Vector2.ONE * particle_size),
			Color(accent_color, life * 0.72),
			true
		)


func _spawn_particles() -> void:
	var width := maxf(size.x, 1.0)
	var height := maxf(size.y, 1.0)
	var center := Vector2(width, height) * 0.5
	for index in range(7):
		var edge := index % 4
		var start := Vector2.ZERO
		match edge:
			0:
				start = Vector2(fmod(index * 47.0, width), 2.0)
			1:
				start = Vector2(width - 2.0, fmod(index * 61.0, height))
			2:
				start = Vector2(width - fmod(index * 53.0, width), height - 2.0)
			_:
				start = Vector2(2.0, height - fmod(index * 43.0, height))
		var outward := (start - center).normalized()
		var tangent := Vector2(-outward.y, outward.x)
		_particles.append({
			"position": start,
			"velocity": outward * (16.0 + float(index % 3) * 7.0) + tangent * (index - 3) * 3.0,
			"life": 0.22 + float(index % 3) * 0.04,
			"size": 3.0 + float(index % 2) * 1.5,
		})
