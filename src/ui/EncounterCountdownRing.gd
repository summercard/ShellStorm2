class_name EncounterCountdownRing
extends Control
## 事件快照的只读表现。新警报不自计时、不抖动数字；未配置alert_style保留旧环。

signal presentation_pulse_requested(alert_port_id: String, preparation_active: bool)

const THICKNESS_RATIO := 0.075
const SEGMENTS := 96
const START_ANGLE := -PI * 0.5
const TRACK_COLOR := Color(0.98, 0.76, 0.30, 0.16)
const FILL_COLOR := Color(1.0, 0.76, 0.26, 0.92)
const GLOW_COLOR := Color(0.62, 0.40, 0.06, 0.34)
const GLOW_WIDTH_RATIO := 1.9
const WARNING_COLOR := Color(1.0, 0.12, 0.10, 0.96)
const WARNING_TRACK_COLOR := Color(1.0, 0.16, 0.10, 0.22)
const WARNING_GLOW_COLOR := Color(0.74, 0.02, 0.015, 0.40)

# 作者原版DSEG7 Classic Bold Italic，OFL 1.1；不再用手绘几何模拟字体。
const DIGITAL_FONT_PATH := "res://assets/ui/fonts/dseg/DSEG7Classic-BoldItalic.ttf"
const DIGITAL_COLOR := Color(1.0, 0.65, 0.055, 1.0)
const DIGITAL_OUTLINE := Color(0.12, 0.045, 0.005, 0.96)

var remaining_ratio := 1.0
var remaining_sec := 0.0
var preparation_total_sec := 0.0
var preparation_remaining_sec := 0.0
var preparation_active := false
var alert_port_id := ""
var reduce_motion := false
var _label: Label
var _digital_font: FontFile
var _label_color := Color.WHITE
var _label_font_size := 21
var _paused := false
var _last_pulse_bucket := -1
var _feedback_key := ""
var _last_remaining := INF
var _alert: Dictionary = {}
var _beep_requested := false
var _impact_requested := false
var _last_impact_bucket := -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 正式导入与PCK使用资源重映射；无导入缓存的纯表现夹具直接读取同一TTF。
	if ResourceLoader.exists(DIGITAL_FONT_PATH, "FontFile"):
		_digital_font = load(DIGITAL_FONT_PATH) as FontFile
	else:
		_digital_font = FontFile.new()
		var font_error := _digital_font.load_dynamic_font(DIGITAL_FONT_PATH)
		assert(font_error == OK, "DSEG countdown font missing or invalid")
	assert(_digital_font != null, "DSEG countdown resource must be FontFile")
	_digital_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_digital_font.hinting = TextServer.HINTING_LIGHT
	_digital_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO


func bind_label(label: Label) -> void:
	_label = label
	if _label == null:
		return
	_label_color = _label.get_theme_color("font_color")
	_label_font_size = _label.get_theme_font_size("font_size")
	_label.name = "CountdownTimeLabel"
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _label.get_parent() != self:
		add_child(_label)
	_refresh_label()


func set_reduce_motion(enabled: bool) -> void:
	reduce_motion = enabled
	_refresh_label()
	queue_redraw()


## 最小投影schema：config四键 + alert_phase/remaining/total；兼容preparation原字段。
## alert_phase空串是Director的战斗阶段，不使用elapsed猜阶段或生成第二时钟。
static func project_alert(snapshot: Dictionary) -> Dictionary:
	var config := snapshot.get("config", {}) as Dictionary
	var style := str(config.get("alert_style", ""))
	var modern := config.has("alert_style")
	var phase := str(snapshot.get("alert_phase", ""))
	var remaining := float(snapshot.get("alert_remaining_sec", snapshot.get("preparation_remaining_sec", 0.0)))
	var total := float(snapshot.get("alert_total_sec", snapshot.get("preparation_total_sec", 0.0)))
	if not snapshot.has("alert_phase") and bool(snapshot.get("preparation_active", remaining > 0.0)) and remaining > 0.0:
		phase = "preparation"
	var active := not snapshot.is_empty() and not bool(snapshot.get("terminal", false)) and str(snapshot.get("status", "active")) == "active"
	var countdown := phase in ["preparation", "intermission"] and is_finite(remaining) and is_finite(total) and remaining > 0.0 and total > 0.0
	return {
		"modern": modern, "style": style, "phase": phase,
		"active": active and style in ["red_eva", "subtle"],
		"countdown": countdown, "remaining": maxf(0.0, remaining), "total": maxf(0.0, total),
		"text": str(config.get("alert_text", "WARNING")).left(80),
		"interval": clampf(float(config.get("alert_beep_interval_sec", 1.0)), 0.25, 2.0),
		"pulse": bool(config.get("alert_pulse", true)), "paused": bool(snapshot.get("paused", false)),
		"port_id": str(snapshot.get("alert_port_id", "")),
	}


func consume_snapshot(snapshot: Dictionary) -> void:
	_beep_requested = false
	_impact_requested = false
	_alert = project_alert(snapshot)
	if _alert.modern:
		visible = bool(_alert.active)
		preparation_active = visible and bool(_alert.countdown)
		preparation_remaining_sec = float(_alert.remaining)
		preparation_total_sec = float(_alert.total)
		alert_port_id = str(_alert.port_id)
		_paused = bool(_alert.paused)
		_set_time_values(preparation_remaining_sec, preparation_total_sec)
		if visible and preparation_active and _alert.style == "red_eva":
			var stage_number := 0
			for stage: Dictionary in snapshot.get("stage_states", []):
				stage_number += int(bool(stage.get("started", false)))
			var key := "%s:%s:%d" % [str(snapshot.get("instance_id", "")), str(_alert.phase), stage_number]
			# 新批次可复用同一phase；剩余值重置也作为Owner新批次的明确证据。
			if key != _feedback_key or remaining_sec > _last_remaining + 0.001:
				_last_pulse_bucket = -1
				_last_impact_bucket = -1
			_feedback_key = key
			var bucket := int(floor(maxf(0.0, preparation_total_sec - remaining_sec) / float(_alert.interval) + 0.000001))
			if not _paused and bucket > _last_pulse_bucket:
				_beep_requested = true
				presentation_pulse_requested.emit(alert_port_id, true)
			_last_pulse_bucket = maxi(_last_pulse_bucket, bucket)
			var impact_bucket := int(floor(maxf(0.0, preparation_total_sec - remaining_sec)))
			_impact_requested = not _paused and not reduce_motion and bool(_alert.pulse) and impact_bucket > _last_impact_bucket
			_last_impact_bucket = maxi(_last_impact_bucket, impact_bucket)
			_last_remaining = remaining_sec
		else:
			_feedback_key = ""
			_last_pulse_bucket = -1
			_last_remaining = INF
		return
	if snapshot.is_empty() or bool(snapshot.get("terminal", false)) or str(snapshot.get("status", "active")) != "active":
		clear_presentation()
		return
	if snapshot.has("preparation_remaining_sec") and snapshot.has("preparation_total_sec"):
		preparation_total_sec = maxf(0.0, float(snapshot.preparation_total_sec))
		preparation_remaining_sec = maxf(0.0, float(snapshot.preparation_remaining_sec))
		preparation_active = bool(snapshot.get("preparation_active", true)) and preparation_remaining_sec > 0.0
		alert_port_id = str(snapshot.get("alert_port_id", ""))
		visible = preparation_active
		_set_time_values(preparation_remaining_sec, preparation_total_sec)
		return
	var config := snapshot.get("config", {}) as Dictionary
	var duration := maxf(0.001, float(config.get("duration_sec", 0.0)))
	set_time(duration - float(snapshot.get("elapsed", 0.0)), duration)
	visible = true


func clear_presentation() -> void:
	visible = false
	preparation_active = false
	preparation_total_sec = 0.0
	preparation_remaining_sec = 0.0
	alert_port_id = ""
	_paused = false
	_last_pulse_bucket = -1
	_feedback_key = ""
	_last_remaining = INF
	_beep_requested = false
	_impact_requested = false
	_last_impact_bucket = -1
	_alert = {}
	_set_time_values(0.0, 0.001)


func set_time(remaining: float, duration: float) -> void:
	preparation_active = false
	preparation_total_sec = 0.0
	preparation_remaining_sec = 0.0
	_alert = {}
	_beep_requested = false
	_impact_requested = false
	_feedback_key = ""
	_last_pulse_bucket = -1
	_last_impact_bucket = -1
	_set_time_values(remaining, duration)


func _set_time_values(remaining: float, duration: float) -> void:
	remaining_sec = maxf(0.0, remaining)
	remaining_ratio = clampf(remaining_sec / maxf(0.001, duration), 0.0, 1.0)
	_refresh_label()
	queue_redraw()


func _refresh_label() -> void:
	if _label == null:
		return
	var modern := bool(_alert.get("modern", false))
	var small: bool = modern and (str(_alert.get("style", "")) == "subtle" or not preparation_active)
	_label.add_theme_font_size_override("font_size", mini(_label_font_size, 16) if small else _label_font_size)
	_label.add_theme_color_override("font_color", WARNING_COLOR if preparation_active and not small else _label_color)
	if modern:
		if preparation_active:
			var caption := "【下一批接敌】" if _alert.phase == "intermission" else "【接敌】"
			_label.text = "%s %s 秒" % [caption, str(int(ceil(remaining_sec))) if reduce_motion else format_preparation_time(remaining_sec)]
		else:
			_label.text = "【清除入侵者】"
	else:
		_label.text = format_preparation_time(remaining_sec) if preparation_active and not reduce_motion else format_time(maxi(0, int(ceil(remaining_sec))))
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 保留原语义文字和节点，避免投影/可访问性及既有探针被视觉变更破坏。
	_label.visible = not _uses_digital_display()


func _uses_digital_display() -> bool:
	return bool(_alert.get("modern", false)) and bool(_alert.get("active", false)) and preparation_active


func _digital_text() -> String:
	return str(int(ceil(remaining_sec))) if reduce_motion else format_preparation_time(remaining_sec)


func _draw_digital_countdown() -> void:
	var text := _digital_text()
	var digit_size := 40
	var metrics := _digital_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, digit_size)
	var available_height := maxf(16.0, size.y - 22.0)
	var fit := minf(1.0, minf(available_height / maxf(metrics.y, 1.0), (size.x - 24.0) / maxf(metrics.x, 1.0)))
	digit_size = maxi(12, int(floor(digit_size * fit)))
	metrics = _digital_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, digit_size)
	var origin := Vector2((size.x - metrics.x) * 0.5, 20.0 + _digital_font.get_ascent(digit_size))
	var caption := "下一批接敌" if str(_alert.get("phase", "")) == "intermission" else "接敌倒计时"
	var font := ThemeDB.fallback_font
	var caption_size := 12
	var caption_width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_size).x
	var caption_origin := Vector2((size.x - caption_width) * 0.5, 13.0)
	draw_string_outline(font, caption_origin, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_size, 3, DIGITAL_OUTLINE)
	draw_string(font, caption_origin, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_size, DIGITAL_COLOR)
	# 字距、小数点、切角和斜度全部使用字体原始度量，不人工拼接单个数字。
	draw_string_outline(_digital_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, digit_size, 1, DIGITAL_OUTLINE)
	draw_string(_digital_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, digit_size, DIGITAL_COLOR)


static func format_time(total_seconds: int) -> String:
	return "%d:%02d" % [total_seconds / 60, total_seconds % 60]


## 百分秒向上量化，误差小于0.01s；不随机、不插值，不提前把非零时间显示为零。
static func format_preparation_time(seconds: float) -> String:
	var hundredths := maxi(0, int(ceil(maxf(0.0, seconds) * 100.0 - 0.000001)))
	return "%d.%02d" % [hundredths / 100, hundredths % 100]


func get_snapshot() -> Dictionary:
	var outer_radius := minf(size.x, size.y) * 0.5
	var thickness := outer_radius * THICKNESS_RATIO
	return {
		"visible": visible, "remaining_ratio": remaining_ratio, "remaining_sec": remaining_sec,
		"digital_display": _uses_digital_display(), "digital_text": _digital_text(),
		"digital_color": DIGITAL_COLOR, "digital_style": "dseg7_classic_bold_italic",
		"digital_font_path": DIGITAL_FONT_PATH, "digital_font_name": _digital_font.get_font_name(),
		"text": _label.text if _label != null else "", "preparation_active": preparation_active,
		"preparation_remaining_sec": preparation_remaining_sec, "preparation_total_sec": preparation_total_sec,
		"alert_port_id": alert_port_id, "reduce_motion": reduce_motion, "paused": _paused,
		"label_offset_px": _label.position.x if _label != null else 0.0,
		"beep_requested": _beep_requested, "impact_requested": _impact_requested, "alert": _alert.duplicate(true),
		"size": size, "center": global_position + size * 0.5,
		"outer_diameter_px": outer_radius * 2.0, "outer_radius_px": outer_radius,
		"stroke_radius_px": outer_radius - thickness * 0.5, "thickness_px": thickness,
		"thickness_ratio": THICKNESS_RATIO, "glow_width_px": thickness * GLOW_WIDTH_RATIO,
		"glow_width_ratio": GLOW_WIDTH_RATIO, "segments": SEGMENTS, "start_angle": START_ANGLE,
		"fill_color": WARNING_COLOR if preparation_active else FILL_COLOR,
		"track_color": WARNING_TRACK_COLOR if preparation_active else TRACK_COLOR,
		"glow_color": WARNING_GLOW_COLOR if preparation_active else GLOW_COLOR,
	}


func _draw() -> void:
	if _uses_digital_display():
		_draw_digital_countdown()
		return
	if bool(_alert.get("modern", false)):
		return
	var outer_radius := minf(size.x, size.y) * 0.5
	if outer_radius <= 1.0:
		return
	var thickness := outer_radius * THICKNESS_RATIO
	var stroke_radius := outer_radius - thickness * 0.5
	var center := size * 0.5
	var track := WARNING_TRACK_COLOR if preparation_active else TRACK_COLOR
	var fill := WARNING_COLOR if preparation_active else FILL_COLOR
	var glow := WARNING_GLOW_COLOR if preparation_active else GLOW_COLOR
	draw_arc(center, stroke_radius, 0.0, TAU, SEGMENTS, track, thickness, true)
	if remaining_ratio <= 0.0:
		return
	var points := maxi(2, int(ceil(float(SEGMENTS) * remaining_ratio)))
	draw_arc(center, stroke_radius, START_ANGLE, START_ANGLE + TAU * remaining_ratio, points, glow, thickness * GLOW_WIDTH_RATIO, true)
	draw_arc(center, stroke_radius, START_ANGLE, START_ANGLE + TAU * remaining_ratio, points, fill, thickness, true)
