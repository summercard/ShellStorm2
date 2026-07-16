class_name TrainingTarget
extends CharacterBody2D

signal hit_received(
	target_id: String, raw_damage: float, applied_damage: float, is_crit: bool
)

enum TargetType {
	STANDARD,
	ARMORED,
	RUNNER,
}

@export var target_id := "target"
@export var target_type: TargetType = TargetType.STANDARD
@export_range(22.0, 90.0, 1.0) var target_size := 44.0
@export_range(0.0, 0.85, 0.01) var armor_ratio := 0.0
@export var accent_color := Color(0.34, 0.82, 0.92, 1.0)
@export var movement_axis := Vector2.UP
@export_range(0.0, 320.0, 1.0) var movement_span := 0.0
@export_range(0.1, 5.0, 0.1) var movement_speed := 1.0

var hit_count := 0
var total_raw_damage := 0.0
var total_applied_damage := 0.0
var last_applied_damage := 0.0

var _origin := Vector2.ZERO
var _motion_phase := 0.0
var _hit_flash := 0.0
var _impact_offset := Vector2.ZERO


func configure(config: Dictionary) -> void:
	target_id = str(config.get("id", target_id))
	target_type = int(config.get("type", target_type))
	target_size = float(config.get("size", target_size))
	armor_ratio = clampf(float(config.get("armor", armor_ratio)), 0.0, 0.85)
	accent_color = config.get("color", accent_color) as Color
	movement_axis = (config.get("axis", movement_axis) as Vector2).normalized()
	movement_span = float(config.get("span", movement_span))
	movement_speed = float(config.get("speed", movement_speed))


func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 4
	collision_mask = 1
	_origin = position
	var collision := CollisionShape2D.new()
	collision.name = "HitCollider"
	var shape := CircleShape2D.new()
	shape.radius = target_size * (0.62 if target_type == TargetType.ARMORED else 0.52)
	collision.shape = shape
	add_child(collision)
	queue_redraw()


func _physics_process(delta: float) -> void:
	_motion_phase += delta * movement_speed
	if target_type == TargetType.RUNNER and movement_span > 0.0:
		position = _origin + movement_axis * sin(_motion_phase) * movement_span
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta * 5.5)
		_impact_offset = _impact_offset.lerp(Vector2.ZERO, minf(1.0, delta * 14.0))
		queue_redraw()


func take_damage(amount: int, is_crit := false, hit_direction := Vector2.ZERO) -> void:
	var raw := maxf(0.0, float(amount))
	var applied := maxf(1.0, roundf(raw * (1.0 - armor_ratio))) if raw > 0.0 else 0.0
	hit_count += 1
	total_raw_damage += raw
	total_applied_damage += applied
	last_applied_damage = applied
	_hit_flash = 1.0
	_impact_offset = hit_direction.normalized() * 7.0
	_spawn_damage_readout(applied, is_crit)
	queue_redraw()
	hit_received.emit(target_id, raw, applied, is_crit)


func reset_metrics() -> void:
	hit_count = 0
	total_raw_damage = 0.0
	total_applied_damage = 0.0
	last_applied_damage = 0.0
	_hit_flash = 0.0
	_impact_offset = Vector2.ZERO
	queue_redraw()


func get_metrics() -> Dictionary:
	return {
		"target_id": target_id,
		"type": int(target_type),
		"hits": hit_count,
		"raw_damage": total_raw_damage,
		"applied_damage": total_applied_damage,
		"armor_ratio": armor_ratio,
	}


func _spawn_damage_readout(value: float, is_crit: bool) -> void:
	var label := Label.new()
	label.text = "%d%s" % [int(value), " !" if is_crit else ""]
	label.position = Vector2(-26, -target_size - 30)
	label.size = Vector2(72, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20 if is_crit else 17)
	label.add_theme_color_override(
		"font_color", Color(1.0, 0.78, 0.25) if is_crit else Color(0.82, 0.95, 1.0)
	)
	label.z_index = 20
	add_child(label)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 34.0, 0.55)
	tween.tween_property(label, "modulate:a", 0.0, 0.55)
	tween.chain().tween_callback(label.queue_free)


func _draw() -> void:
	var radius := target_size
	var center := _impact_offset
	var shadow := Color(0.015, 0.025, 0.035, 0.9)
	var metal := Color(0.11, 0.15, 0.17, 1.0)
	var rim := accent_color.lerp(Color.WHITE, 0.22 + _hit_flash * 0.38)

	# 支架和接地阴影，保证靶标在昏暗背景中有可读轮廓。
	_draw_ellipse_polygon(Vector2(0, radius * 0.92), Vector2(radius * 0.72, radius * 0.18), shadow)
	draw_line(Vector2(-radius * 0.28, radius * 0.52), Vector2(-radius * 0.5, radius * 1.05), metal, 8.0)
	draw_line(Vector2(radius * 0.28, radius * 0.52), Vector2(radius * 0.5, radius * 1.05), metal, 8.0)
	draw_line(Vector2(-radius * 0.66, radius * 1.05), Vector2(radius * 0.66, radius * 1.05), metal, 9.0)

	match target_type:
		TargetType.ARMORED:
			var plate := PackedVector2Array([
				center + Vector2(-radius * 0.86, -radius * 0.62),
				center + Vector2(-radius, radius * 0.18),
				center + Vector2(-radius * 0.58, radius * 0.78),
				center + Vector2(radius * 0.58, radius * 0.78),
				center + Vector2(radius, radius * 0.18),
				center + Vector2(radius * 0.86, -radius * 0.62),
			])
			draw_colored_polygon(plate, Color(0.12, 0.15, 0.16, 1.0))
			draw_polyline(PackedVector2Array(Array(plate) + [plate[0]]), rim, 5.0, true)
			draw_circle(center, radius * 0.52, Color(0.05, 0.08, 0.09, 1.0))
			draw_arc(center, radius * 0.52, 0.0, TAU, 48, rim, 4.0, true)
		TargetType.RUNNER:
			var diamond := PackedVector2Array([
				center + Vector2(0, -radius),
				center + Vector2(radius * 0.78, 0),
				center + Vector2(0, radius),
				center + Vector2(-radius * 0.78, 0),
			])
			draw_colored_polygon(diamond, Color(0.07, 0.1, 0.12, 1.0))
			draw_polyline(PackedVector2Array(Array(diamond) + [diamond[0]]), rim, 4.0, true)
			draw_circle(center, radius * 0.26, rim.darkened(0.22))
		_:
			draw_circle(center, radius, Color(0.06, 0.085, 0.095, 1.0))
			draw_arc(center, radius, 0.0, TAU, 64, rim, 5.0, true)
			draw_circle(center, radius * 0.58, Color(0.14, 0.18, 0.19, 1.0))
			draw_arc(center, radius * 0.58, 0.0, TAU, 48, rim.darkened(0.2), 3.0, true)
			draw_circle(center, radius * 0.21, rim)

	if _hit_flash > 0.0:
		draw_circle(center, radius * (0.34 + _hit_flash * 0.34), Color(1.0, 0.78, 0.3, _hit_flash * 0.45))

	var type_label := "STANDARD"
	if target_type == TargetType.ARMORED:
		type_label = "ARMOR  %d%%" % int(armor_ratio * 100.0)
	elif target_type == TargetType.RUNNER:
		type_label = "RUNNER"
	draw_string(
		ThemeDB.fallback_font,
		Vector2(-radius, radius * 1.42),
		type_label,
		HORIZONTAL_ALIGNMENT_CENTER,
		radius * 2.0,
		13,
		accent_color.lightened(0.18)
	)


func _draw_ellipse_polygon(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(25):
		var angle := TAU * float(i) / 24.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)
