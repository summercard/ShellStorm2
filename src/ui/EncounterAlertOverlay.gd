class_name EncounterAlertOverlay
extends Control
## 只读警报配置与事件阶段；仅red_eva倒计时绘制红边，不创建任何时钟。

const PROJECTION = preload("res://src/ui/EncounterCountdownRing.gd")
const WARNING_COLOR := Color(1.0, 0.08, 0.06)
const EDGE_WIDTH := 4.0
const EDGE_INSET := 8.0
const PULSE_HZ := 1.0

var alert_active := false
var alert_port_id := ""
var preparation_remaining_sec := 0.0
var preparation_total_sec := 0.0
var reduce_motion := false
var _warning_label: Label
var _edge_alpha := 0.48
var _alert: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func bind_warning_label(label: Label) -> void:
	_warning_label = label
	if _warning_label == null:
		return
	_warning_label.name = "EncounterWarningLabel"
	_warning_label.anchor_left = 0.5
	_warning_label.anchor_right = 0.5
	_warning_label.anchor_top = 0.12
	_warning_label.anchor_bottom = 0.12
	_warning_label.offset_left = -280.0
	_warning_label.offset_right = 280.0
	_warning_label.offset_top = -26.0
	_warning_label.offset_bottom = 26.0
	_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warning_label.add_theme_color_override("font_color", WARNING_COLOR)
	if _warning_label.get_parent() != self:
		add_child(_warning_label)
	_refresh_visual()


func set_reduce_motion(enabled: bool) -> void:
	reduce_motion = enabled
	_refresh_visual()


func consume_snapshot(snapshot: Dictionary) -> void:
	_alert = PROJECTION.project_alert(snapshot)
	preparation_remaining_sec = float(_alert.remaining)
	preparation_total_sec = float(_alert.total)
	alert_active = bool(_alert.active) and _alert.style == "red_eva" and (bool(_alert.countdown) or _alert.phase == "trigger_freeze")
	alert_port_id = str(_alert.port_id) if alert_active else ""
	_refresh_visual()


func _refresh_visual() -> void:
	visible = alert_active
	var pulse := bool(_alert.get("pulse", false)) and not reduce_motion and not bool(_alert.get("paused", false))
	var elapsed := maxf(0.0, preparation_total_sec - preparation_remaining_sec)
	_edge_alpha = 0.34 + 0.20 * (0.5 + 0.5 * cos(TAU * PULSE_HZ * elapsed)) if pulse else 0.48
	if _warning_label != null:
		_warning_label.visible = alert_active
		_warning_label.text = str(_alert.get("text", ""))
		_warning_label.modulate.a = 1.0
	queue_redraw()


func get_snapshot() -> Dictionary:
	return {
		"visible": visible, "alert_active": alert_active, "alert_port_id": alert_port_id,
		"preparation_remaining_sec": preparation_remaining_sec, "preparation_total_sec": preparation_total_sec,
		"reduce_motion": reduce_motion, "edge_alpha": _edge_alpha, "pulse_hz": PULSE_HZ,
		"warning_text": _warning_label.text if _warning_label != null and _warning_label.visible else "",
		"mouse_filter": mouse_filter,
	}


func _draw() -> void:
	if not alert_active or minf(size.x, size.y) <= EDGE_INSET * 2.0:
		return
	var rect := Rect2(Vector2.ZERO, size).grow(-EDGE_INSET)
	draw_rect(rect, Color(WARNING_COLOR, _edge_alpha), false, EDGE_WIDTH, true)
	draw_rect(rect.grow(-6.0), Color(WARNING_COLOR, _edge_alpha * 0.20), false, 2.0, true)
