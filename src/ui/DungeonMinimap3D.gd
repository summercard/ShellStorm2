class_name DungeonMinimap3D
extends Control
## PH49 实时战术小地图：当前楼层平面投影、玩家位置/朝向、扫描波束与楼层索引。

const REDRAW_INTERVAL := 1.0 / 20.0
const HEADER_HEIGHT := 28.0
const MAP_PADDING := Vector2(18.0, 38.0)
const FLOOR_EPSILON_M := 0.45

var _records: Array[Dictionary] = []
var _edges: Dictionary = {}
var _revealed: Dictionary = {}
var _current_room_id := ""
var _position_by_id: Dictionary = {}
var _record_by_id: Dictionary = {}
var _floor_heights: Array[float] = []
var _has_multiple_floors := false
var _current_floor_y := 0.0
var _player_world_position := Vector3.ZERO
var _player_aim_direction := Vector3.FORWARD
var _scan_phase := 0.0
var _pulse_phase := 0.0
var _redraw_accumulator := 0.0
var _has_realtime_player_state := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_scan_phase = fmod(_scan_phase + delta * 0.82, 1.0)
	_pulse_phase = fmod(_pulse_phase + delta * 0.58, 1.0)
	_redraw_accumulator += delta
	if _redraw_accumulator >= REDRAW_INTERVAL:
		_redraw_accumulator = 0.0
		queue_redraw()


func configure(records: Array[Dictionary], edge_states: Dictionary) -> void:
	_records = records.duplicate(true)
	_edges = edge_states.duplicate(true)
	_position_by_id.clear()
	_record_by_id.clear()
	_floor_heights.clear()
	for record in _records:
		var room_id := str(record.get("id", ""))
		var position := record.get("position", Vector3.ZERO) as Vector3
		_position_by_id[room_id] = position
		_record_by_id[room_id] = record
		var floor_y := snappedf(position.y, 0.01)
		if not _contains_floor_height(floor_y):
			_floor_heights.append(floor_y)
	_floor_heights.sort()
	_has_multiple_floors = _floor_heights.size() > 1
	queue_redraw()


func reveal_room(room_id: String) -> void:
	_revealed[room_id] = true
	queue_redraw()


func set_current_room(room_id: String) -> void:
	_current_room_id = room_id
	var position := _position_by_id.get(room_id, Vector3.ZERO) as Vector3
	_current_floor_y = position.y
	reveal_room(room_id)


func set_player_state(
	world_position: Vector3,
	aim_direction: Vector3
) -> void:
	_player_world_position = world_position
	var planar_aim := Vector3(aim_direction.x, 0.0, aim_direction.z)
	if planar_aim.length_squared() > 0.0001:
		_player_aim_direction = planar_aim.normalized()
	_has_realtime_player_state = true


func set_edge_open(a: String, b: String, opened: bool) -> void:
	_edges[_edge_key(a, b)] = opened
	if opened:
		reveal_room(a)
		reveal_room(b)
	queue_redraw()


func get_snapshot() -> Dictionary:
	return {
		"revealed_count": _revealed.size(),
		"current_room_id": _current_room_id,
		"open_edge_count": _edges.values().count(true),
		"room_count": _records.size(),
		"projection_mode": (
			"current_floor_holographic"
			if _has_multiple_floors
			else "planar_holographic"
		),
		"current_floor_y": _current_floor_y,
		"floor_count": _floor_heights.size(),
		"realtime_player_state": _has_realtime_player_state,
		"realtime_update_hz": int(round(1.0 / REDRAW_INTERVAL)),
		"player_marker": true,
		"player_heading": true,
		"holographic_scan": true,
		"floor_stack_index": _has_multiple_floors,
	}


func _draw() -> void:
	var full_rect := Rect2(Vector2.ZERO, size)
	draw_style_box(_panel_style(), full_rect)
	_draw_frame(full_rect)
	_draw_header()
	if _records.is_empty():
		return
	var map_rect := Rect2(
		MAP_PADDING,
		Vector2(
			maxf(1.0, size.x - MAP_PADDING.x - 30.0),
			maxf(1.0, size.y - MAP_PADDING.y - 16.0)
		)
	)
	_draw_holographic_grid(map_rect)
	var bounds := _bounds_for_current_floor()
	_draw_scan_field(map_rect, bounds)
	_draw_edges(bounds, map_rect)
	_draw_rooms(bounds, map_rect)
	_draw_player(bounds, map_rect)
	if _has_multiple_floors:
		_draw_floor_stack()


func _draw_header() -> void:
	var font := ThemeDB.fallback_font
	draw_string(
		font,
		Vector2(15.0, 20.0),
		"TACTICAL HOLO / %s" % _floor_label(),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		13,
		Color(0.42, 0.96, 1.0, 0.96)
	)
	draw_circle(
		Vector2(size.x - 17.0, 15.0),
		3.0,
		Color(0.34, 1.0, 0.74, 0.92)
	)


func _draw_frame(rect: Rect2) -> void:
	var cyan := Color(0.18, 0.88, 1.0, 0.76)
	var corner := 13.0
	for corner_data in [
		[rect.position + Vector2(5.0, 5.0), Vector2.RIGHT, Vector2.DOWN],
		[Vector2(rect.end.x - 5.0, rect.position.y + 5.0), Vector2.LEFT, Vector2.DOWN],
		[Vector2(rect.position.x + 5.0, rect.end.y - 5.0), Vector2.RIGHT, Vector2.UP],
		[rect.end - Vector2(5.0, 5.0), Vector2.LEFT, Vector2.UP],
	]:
		var origin := corner_data[0] as Vector2
		draw_line(origin, origin + (corner_data[1] as Vector2) * corner, cyan, 2.0)
		draw_line(origin, origin + (corner_data[2] as Vector2) * corner, cyan, 2.0)


func _draw_holographic_grid(map_rect: Rect2) -> void:
	var grid_color := Color(0.10, 0.62, 0.72, 0.13)
	for index in range(1, 8):
		var ratio := float(index) / 8.0
		var y := lerpf(map_rect.position.y, map_rect.end.y, ratio)
		var inset := absf(ratio - 0.5) * 14.0
		draw_line(
			Vector2(map_rect.position.x + inset, y),
			Vector2(map_rect.end.x - inset, y),
			grid_color,
			1.0
		)
	for index in range(1, 8):
		var ratio := float(index) / 8.0
		var x := lerpf(map_rect.position.x, map_rect.end.x, ratio)
		draw_line(
			Vector2(x, map_rect.position.y + 3.0),
			Vector2(
				lerpf(map_rect.get_center().x, x, 0.78),
				map_rect.end.y
			),
			grid_color,
			1.0
		)


func _draw_scan_field(map_rect: Rect2, bounds: Rect2) -> void:
	var origin := (
		_map_position(_player_world_position, bounds, map_rect)
		if _has_realtime_player_state
		else map_rect.get_center()
	)
	var angle := _scan_phase * TAU - PI * 0.5
	var radius := maxf(map_rect.size.x, map_rect.size.y) * 0.62
	var beam_tip := origin + Vector2.from_angle(angle) * radius
	var beam_left := origin + Vector2.from_angle(angle - 0.16) * radius
	draw_colored_polygon(
		PackedVector2Array([origin, beam_left, beam_tip]),
		Color(0.08, 0.86, 0.94, 0.045)
	)
	draw_line(origin, beam_tip, Color(0.25, 0.95, 1.0, 0.42), 1.4)
	var pulse_radius := 7.0 + _pulse_phase * 46.0
	draw_arc(
		origin,
		pulse_radius,
		0.0,
		TAU,
		40,
		Color(0.28, 0.94, 1.0, (1.0 - _pulse_phase) * 0.38),
		1.2
	)


func _draw_edges(bounds: Rect2, map_rect: Rect2) -> void:
	for edge_key in _edges.keys():
		var ids := str(edge_key).split("|")
		if ids.size() != 2:
			continue
		if not _revealed.has(ids[0]) or not _revealed.has(ids[1]):
			continue
		var from_world := _position_by_id.get(ids[0], Vector3.ZERO) as Vector3
		var to_world := _position_by_id.get(ids[1], Vector3.ZERO) as Vector3
		if not _is_current_floor_y(from_world.y) or not _is_current_floor_y(to_world.y):
			continue
		var from := _map_position(from_world, bounds, map_rect)
		var to := _map_position(to_world, bounds, map_rect)
		var opened := bool(_edges[edge_key])
		var color := (
			Color(0.24, 0.98, 0.78, 0.88)
			if opened
			else Color(1.0, 0.48, 0.18, 0.82)
		)
		draw_line(from, to, Color(color, 0.18), 6.0 if opened else 3.0)
		draw_line(from, to, color, 2.0 if opened else 1.2)


func _draw_rooms(bounds: Rect2, map_rect: Rect2) -> void:
	for record in _records:
		var room_id := str(record.get("id", ""))
		if not _revealed.has(room_id):
			continue
		var world_position := record.get("position", Vector3.ZERO) as Vector3
		if not _is_current_floor_y(world_position.y):
			continue
		var center := _map_position(world_position, bounds, map_rect)
		var color := _room_color(str(record.get("type", "")))
		var radius := (
			7.0
			if str(record.get("size", "")) in ["large", "arena"]
			else 5.2
		)
		draw_circle(center, radius + 3.5, Color(color, 0.14))
		draw_circle(center, radius, Color(color, 0.80))
		draw_arc(center, radius + 1.5, 0.0, TAU, 20, color, 1.2)
		if room_id == _current_room_id:
			draw_arc(
				center,
				radius + 7.0 + sin(_pulse_phase * TAU) * 1.5,
				0.0,
				TAU,
				28,
				Color(1.0, 0.88, 0.30, 0.92),
				2.0
			)


func _draw_player(bounds: Rect2, map_rect: Rect2) -> void:
	if not _has_realtime_player_state:
		return
	var center := _map_position(_player_world_position, bounds, map_rect)
	var heading := Vector2(
		_player_aim_direction.x,
		_player_aim_direction.z
	).normalized()
	if heading.length_squared() <= 0.0001:
		heading = Vector2.UP
	var perpendicular := Vector2(-heading.y, heading.x)
	var points := PackedVector2Array([
		center + heading * 10.0,
		center - heading * 6.0 + perpendicular * 5.0,
		center - heading * 6.0 - perpendicular * 5.0,
	])
	draw_colored_polygon(points, Color(0.72, 1.0, 1.0, 0.96))
	draw_polyline(
		PackedVector2Array([points[0], points[1], points[2], points[0]]),
		Color(0.12, 0.78, 0.92),
		1.4
	)
	draw_line(
		center,
		center + heading * 22.0,
		Color(0.50, 0.98, 1.0, 0.54),
		1.2
	)


func _draw_floor_stack() -> void:
	var x := size.x - 13.0
	var top := HEADER_HEIGHT + 14.0
	var bottom := size.y - 18.0
	draw_line(
		Vector2(x, top),
		Vector2(x, bottom),
		Color(0.20, 0.72, 0.82, 0.34),
		1.0
	)
	for index in range(_floor_heights.size()):
		var ratio := (
			0.5
			if _floor_heights.size() <= 1
			else float(index) / float(_floor_heights.size() - 1)
		)
		var point := Vector2(x, lerpf(top, bottom, ratio))
		var active := is_equal_approx(_floor_heights[index], snappedf(_current_floor_y, 0.01))
		draw_circle(
			point,
			4.0 if active else 2.2,
			Color(1.0, 0.76, 0.24) if active else Color(0.26, 0.82, 0.90, 0.62)
		)


func _bounds_for_current_floor() -> Rect2:
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for record in _records:
		var position := record.get("position", Vector3.ZERO) as Vector3
		if not _is_current_floor_y(position.y):
			continue
		var projected := Vector2(position.x, position.z)
		min_pos.x = minf(min_pos.x, projected.x)
		min_pos.y = minf(min_pos.y, projected.y)
		max_pos.x = maxf(max_pos.x, projected.x)
		max_pos.y = maxf(max_pos.y, projected.y)
	if min_pos.x == INF:
		min_pos = Vector2(-1.0, -1.0)
		max_pos = Vector2(1.0, 1.0)
	var minimum_span := Vector2(28.0, 28.0)
	var span := max_pos - min_pos
	if span.x < minimum_span.x:
		var expand_x := (minimum_span.x - span.x) * 0.5
		min_pos.x -= expand_x
		max_pos.x += expand_x
	if span.y < minimum_span.y:
		var expand_y := (minimum_span.y - span.y) * 0.5
		min_pos.y -= expand_y
		max_pos.y += expand_y
	return Rect2(min_pos, max_pos - min_pos)


func _map_position(
	world_position: Vector3,
	bounds: Rect2,
	map_rect: Rect2
) -> Vector2:
	var projected := Vector2(world_position.x, world_position.z)
	var normalized := Vector2(
		(projected.x - bounds.position.x) / maxf(1.0, bounds.size.x),
		(projected.y - bounds.position.y) / maxf(1.0, bounds.size.y)
	)
	return map_rect.position + normalized * map_rect.size


func _is_current_floor_y(value: float) -> bool:
	return absf(value - _current_floor_y) <= FLOOR_EPSILON_M


func _contains_floor_height(value: float) -> bool:
	for existing in _floor_heights:
		if is_equal_approx(existing, value):
			return true
	return false


func _floor_label() -> String:
	if _has_multiple_floors:
		return "%dF" % int(round(100.0 + _current_floor_y / 9.0))
	return "LIVE"


func _room_color(type_id: String) -> Color:
	return {
		"START": Color(0.35, 0.75, 1.0),
		"COMBAT": Color(0.96, 0.24, 0.20),
		"FACILITY": Color(0.22, 0.96, 0.74),
		"STAIR_LOBBY": Color(0.28, 0.82, 0.96),
		"ELITE": Color(0.92, 0.30, 0.94),
		"BOSS": Color(1.0, 0.10, 0.05),
		"EXTRACTION": Color(0.26, 1.0, 0.60),
		"SCAVENGE": Color(0.98, 0.76, 0.20),
		"STORAGE": Color(0.70, 0.56, 0.26),
		"MERCHANT": Color(0.30, 0.92, 0.86),
		"UPGRADE": Color(0.42, 0.64, 1.0),
		"EVENT": Color(0.70, 0.38, 0.98),
		"TRAP": Color(1.0, 0.43, 0.12),
		"BASEMENT": Color(0.42, 0.28, 0.58),
		"STAIRS_DOWN": Color(0.46, 0.52, 0.58),
		"STAIRS_UP": Color(0.62, 0.72, 0.82),
	}.get(type_id, Color(0.62, 0.72, 0.76))


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.008, 0.026, 0.040, 0.91)
	style.set_border_width_all(1)
	style.border_color = Color(0.16, 0.76, 0.88, 0.72)
	style.set_corner_radius_all(5)
	style.shadow_color = Color(0.0, 0.36, 0.46, 0.32)
	style.shadow_size = 8
	return style


func _edge_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]
