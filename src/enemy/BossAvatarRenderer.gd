class_name BossAvatarRenderer
extends Node2D
## Programmatic boss art separated from BossActor's combat authority.  It gives
## the encounter a readable silhouette now and remains a single replacement
## point for future authored assets.

const OUTLINE := Color("250b13")
const SHELL_DARK := Color("4f1422")
const SHELL_MID := Color("a82d36")
const SHELL_HOT := Color("f06a46")
const CORE := Color("ffd36c")

var _presentation_scale := 1.0
var _phase := 1
var _time := 0.0
var _flash_time := 0.0
var _dead := false


func _ready() -> void:
	z_index = 4


func set_presentation_scale(value: float) -> void:
	_presentation_scale = maxf(0.75, value)
	queue_redraw()


func set_phase(value: int) -> void:
	_phase = maxi(1, value)
	_flash_time = 0.22
	queue_redraw()


func flash_hit(is_crit: bool) -> void:
	_flash_time = 0.10 if not is_crit else 0.20
	queue_redraw()


func play_defeat() -> void:
	_dead = true
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.52)
	tween.tween_property(self, "scale", Vector2.ONE * 1.25, 0.52)


func _process(delta: float) -> void:
	_time += delta
	_flash_time = maxf(0.0, _flash_time - delta)
	if not _dead:
		queue_redraw()


func _draw() -> void:
	var scale_factor := _presentation_scale
	var bob := sin(_time * 2.4) * 1.5
	draw_set_transform(Vector2(0.0, 31.0 + bob), 0.0, Vector2(1.55 * scale_factor, 0.43 * scale_factor))
	draw_circle(Vector2.ZERO, 42.0, Color(0.02, 0.0, 0.01, 0.62))
	draw_set_transform(Vector2(0.0, bob), 0.0, Vector2.ONE * scale_factor)

	# Four segmented legs establish a distinct, hostile silhouette.
	for leg_y in [-18.0, 18.0]:
		draw_line(Vector2(-24, leg_y), Vector2(-47, leg_y * 1.25), OUTLINE, 11.0, true)
		draw_line(Vector2(-24, leg_y), Vector2(-47, leg_y * 1.25), SHELL_DARK, 6.0, true)
		draw_line(Vector2(24, leg_y), Vector2(47, leg_y * 1.25), OUTLINE, 11.0, true)
		draw_line(Vector2(24, leg_y), Vector2(47, leg_y * 1.25), SHELL_DARK, 6.0, true)

	# Shell, armor plates and exposed reactor core.
	draw_circle(Vector2.ZERO, 44.0, OUTLINE)
	draw_circle(Vector2.ZERO, 39.0, SHELL_DARK)
	draw_circle(Vector2(-3.0, -3.0), 33.0, SHELL_MID)
	draw_arc(Vector2.ZERO, 30.0, -2.25, 2.25, 20, SHELL_HOT, 4.0, true)
	draw_arc(Vector2.ZERO, 20.0, 0.55, 2.58, 12, Color(0.34, 0.05, 0.10, 1.0), 5.0, true)
	draw_circle(Vector2(10, -4), 13.0, OUTLINE)
	draw_circle(Vector2(10, -4), 9.0, CORE)
	draw_circle(Vector2(12, -5), 4.5 + sin(_time * 5.0) * 1.1, Color(1.0, 0.96, 0.7, 1.0))

	# Phase slashes read even when the boss is partly in darkness.
	for i in range(_phase):
		var y := -18.0 + i * 12.0
		draw_line(Vector2(-26, y), Vector2(-8, y - 5), Color(1.0, 0.78, 0.36, 0.92), 2.4, true)
	if _flash_time > 0.0:
		draw_circle(Vector2.ZERO, 48.0, Color(1.0, 0.92, 0.82, _flash_time / 0.22))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
