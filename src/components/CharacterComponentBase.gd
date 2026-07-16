## CharacterComponentBase - 角色组件基类（2026-06-10）

class_name CharacterComponentBase
extends Node2D

enum FeedbackType {
	NONE = 0,
	FLASH_DAMAGE = 1,
	FLASH_HEAL = 2,
	SHAKE = 3,
	PULSE = 4,
	INVINCIBLE_BLINK = 5,
}

var _current_feedback: int = FeedbackType.NONE
var _feedback_timer: float = 0.0
var _cached_color: Color = Color.WHITE
var _cached_modulate: Color = Color.WHITE
var _cached_scale: Vector2 = Vector2.ONE
var _cached_position: Vector2 = Vector2.ZERO
var _cached_rotation: float = 0.0
var _shake_intensity: float = 0.0
var _pulse_phase: float = 0.0

func _ready() -> void:
	pass

func get_visual_node() -> Node:
	return null

func get_component_root() -> Node2D:
	return self

func apply_feedback(feedback_type: int, duration: float = 0.15, intensity: float = 1.0) -> void:
	if _current_feedback != FeedbackType.NONE:
		_end_feedback(_current_feedback)
	_current_feedback = feedback_type
	_feedback_timer = duration
	var v: Node = get_visual_node()
	if v != null:
		if v is CanvasItem:
			_cached_modulate = (v as CanvasItem).modulate
			_cached_color = _get_node_color(v)
		if v is Node2D:
			var n2d: Node2D = v as Node2D
			_cached_scale = n2d.scale
			_cached_position = n2d.position
			_cached_rotation = n2d.rotation
	_start_feedback(feedback_type, intensity)

func tick_feedback(delta: float) -> void:
	if _current_feedback == FeedbackType.NONE:
		return
	_feedback_timer -= delta
	_update_feedback(_current_feedback, delta)
	if _feedback_timer <= 0.0:
		_end_feedback(_current_feedback)
		_current_feedback = FeedbackType.NONE

func reset() -> void:
	if _current_feedback != FeedbackType.NONE:
		_end_feedback(_current_feedback)
		_current_feedback = FeedbackType.NONE

# ===== 子类重写的钩子 =====

func _start_feedback(feedback_type: int, intensity: float) -> void:
	match feedback_type:
		FeedbackType.FLASH_DAMAGE:
			_set_node_color(Color(1.0, 1.0, 1.0, 0.95))
		FeedbackType.FLASH_HEAL:
			_set_node_color(Color(0.4, 1.0, 0.5, 1.0))
		FeedbackType.SHAKE:
			_shake_intensity = 4.0 * intensity
		FeedbackType.PULSE:
			_pulse_phase = 0.0
		FeedbackType.INVINCIBLE_BLINK:
			_set_modulate(Color(1.0, 1.0, 1.0, 0.4))
		_:
			pass

func _update_feedback(feedback_type: int, delta: float) -> void:
	match feedback_type:
		FeedbackType.SHAKE:
			var n: Node2D = null
			var v_n: Node = get_visual_node()
			if v_n is Node2D:
				n = v_n
			if n != null:
				n.position = _cached_position + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake_intensity
		FeedbackType.PULSE:
			_pulse_phase += delta * 8.0
			var n: Node2D = null
			var v_n: Node = get_visual_node()
			if v_n is Node2D:
				n = v_n
			if n != null:
				var s: float = 1.0 + 0.15 * sin(_pulse_phase)
				n.scale = _cached_scale * s
		FeedbackType.INVINCIBLE_BLINK:
			var n: CanvasItem = null
			var v_n2: Node = get_visual_node()
			if v_n2 is CanvasItem:
				n = v_n2
			if n != null:
				var blink_alpha: float = 0.4 if fmod(_feedback_timer, 0.16) < 0.08 else 1.0
				n.modulate = Color(1.0, 1.0, 1.0, blink_alpha)
		_:
			pass

func _end_feedback(feedback_type: int) -> void:
	match feedback_type:
		FeedbackType.FLASH_DAMAGE, FeedbackType.FLASH_HEAL:
			_set_node_color(_cached_color)
			_set_modulate(_cached_modulate)
		FeedbackType.SHAKE:
			var n: Node2D = null
			var v_n: Node = get_visual_node()
			if v_n is Node2D:
				n = v_n
			if n != null:
				n.position = _cached_position
		FeedbackType.PULSE:
			var n: Node2D = null
			var v_n: Node = get_visual_node()
			if v_n is Node2D:
				n = v_n
			if n != null:
				n.scale = _cached_scale
		FeedbackType.INVINCIBLE_BLINK:
			_set_modulate(_cached_modulate)
		_:
			pass
	_shake_intensity = 0.0

# ===== 辅助方法 =====

func _get_node_color(n: Node) -> Color:
	if n is ColorRect:
		return (n as ColorRect).color
	elif n is Polygon2D:
		return (n as Polygon2D).color
	elif n is Label:
		return Color.WHITE
	elif n is Sprite2D:
		return (n as Sprite2D).modulate
	return Color.WHITE

func _set_node_color(c: Color) -> void:
	var n: Node = get_visual_node()
	if n == null:
		return
	if n is ColorRect:
		(n as ColorRect).color = c
	elif n is Polygon2D:
		(n as Polygon2D).color = c
	elif n is Label:
		(n as Label).add_theme_color_override("font_color", c)

func _set_modulate(c: Color) -> void:
	var n: Node = get_visual_node()
	if n is CanvasItem:
		(n as CanvasItem).modulate = c
