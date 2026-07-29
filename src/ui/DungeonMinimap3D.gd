class_name DungeonMinimap3D
extends Control
## 3D 关卡的小地图仍是屏幕空间信息层；只显示已揭示房间、门边状态和当前房。

var _records: Array[Dictionary] = []
var _edges: Dictionary = {}
var _revealed: Dictionary = {}
var _current_room_id := ""
var _position_by_id: Dictionary = {}
var _vertical_stack_mode := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func configure(records: Array[Dictionary], edge_states: Dictionary) -> void:
	_records = records.duplicate(true)
	_edges = edge_states.duplicate(true)
	_position_by_id.clear()
	var min_planar := Vector2(INF, INF)
	var max_planar := Vector2(-INF, -INF)
	var min_height := INF
	var max_height := -INF
	for record in _records:
		var position := record.get("position", Vector3.ZERO) as Vector3
		_position_by_id[str(record.get("id", ""))] = position
		min_planar.x = minf(min_planar.x, position.x)
		min_planar.y = minf(min_planar.y, position.z)
		max_planar.x = maxf(max_planar.x, position.x)
		max_planar.y = maxf(max_planar.y, position.z)
		min_height = minf(min_height, position.y)
		max_height = maxf(max_height, position.y)
	_vertical_stack_mode = (
		max_planar.distance_to(min_planar) < 1.0
		and max_height - min_height > 1.0
	)
	queue_redraw()


func reveal_room(room_id: String) -> void:
	_revealed[room_id] = true
	queue_redraw()


func set_current_room(room_id: String) -> void:
	_current_room_id = room_id
	reveal_room(room_id)


func set_edge_open(a: String, b: String, opened: bool) -> void:
	_edges[_edge_key(a, b)] = opened
	if opened:
		reveal_room(a)
		reveal_room(b)
	queue_redraw()


func get_snapshot() -> Dictionary:
	return {
		"revealed_count": _revealed.size(), "current_room_id": _current_room_id,
		"open_edge_count": _edges.values().count(true), "room_count": _records.size(),
		"projection_mode": "vertical_stack" if _vertical_stack_mode else "planar",
	}


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_style_box(_panel_style(), rect)
	if _records.is_empty():
		return
	var bounds := _bounds()
	for edge_key in _edges.keys():
		var ids := str(edge_key).split("|")
		if ids.size() != 2 or not _revealed.has(ids[0]) or not _revealed.has(ids[1]):
			continue
		var from := _map_position(_position_by_id.get(ids[0], Vector3.ZERO), bounds)
		var to := _map_position(_position_by_id.get(ids[1], Vector3.ZERO), bounds)
		var color := Color(0.32, 0.86, 0.65, 0.92) if bool(_edges[edge_key]) else Color(0.82, 0.48, 0.22, 0.72)
		draw_line(from, to, color, 3.0 if bool(_edges[edge_key]) else 1.5)
	for record in _records:
		var room_id := str(record.get("id", ""))
		if not _revealed.has(room_id):
			continue
		var center := _map_position(record.get("position", Vector3.ZERO), bounds)
		var radius := 7.0 if str(record.get("size", "")) in ["large", "arena"] else 5.5
		var color := _room_color(str(record.get("type", "")))
		if room_id == _current_room_id:
			draw_circle(center, radius + 4.0, Color(1.0, 0.90, 0.35, 0.30))
			draw_arc(center, radius + 4.0, 0, TAU, 24, Color(1.0, 0.90, 0.35), 2.0)
		draw_circle(center, radius, color)


func _bounds() -> Rect2:
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for record in _records:
		var p := record.get("position", Vector3.ZERO) as Vector3
		var projected := _project_world_position(p)
		min_pos.x = minf(min_pos.x, projected.x)
		min_pos.y = minf(min_pos.y, projected.y)
		max_pos.x = maxf(max_pos.x, projected.x)
		max_pos.y = maxf(max_pos.y, projected.y)
	return Rect2(min_pos, max_pos - min_pos)


func _map_position(world_position: Vector3, bounds: Rect2) -> Vector2:
	var padding := 16.0
	var usable := size - Vector2.ONE * padding * 2.0
	var projected := _project_world_position(world_position)
	var normalized := Vector2(
		(projected.x - bounds.position.x) / maxf(1.0, bounds.size.x),
		(projected.y - bounds.position.y) / maxf(1.0, bounds.size.y)
	)
	return Vector2(padding, padding) + normalized * usable


func _project_world_position(world_position: Vector3) -> Vector2:
	if _vertical_stack_mode:
		return Vector2(0.0, -world_position.y)
	return Vector2(world_position.x, world_position.z)


func _room_color(type_id: String) -> Color:
	return {
		"START": Color(0.35, 0.75, 1.0), "COMBAT": Color(0.92, 0.30, 0.24),
		"FACILITY": Color(0.30, 0.88, 0.76),
		"ELITE": Color(0.90, 0.32, 0.88), "BOSS": Color(1.0, 0.12, 0.06),
		"EXTRACTION": Color(0.30, 1.0, 0.62), "SCAVENGE": Color(0.90, 0.72, 0.24),
		"STORAGE": Color(0.64, 0.54, 0.32), "MERCHANT": Color(0.36, 0.88, 0.84),
		"UPGRADE": Color(0.46, 0.62, 1.0), "EVENT": Color(0.68, 0.40, 0.95),
		"TRAP": Color(1.0, 0.48, 0.16),
		"BASEMENT": Color(0.38, 0.26, 0.52), "STAIRS_DOWN": Color(0.46, 0.52, 0.58),
		"STAIRS_UP": Color(0.62, 0.72, 0.82), "ELEVATOR": Color(0.30, 0.72, 0.82),
	}.get(type_id, Color(0.62, 0.66, 0.70))


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.045, 0.78)
	style.set_border_width_all(1)
	style.border_color = Color(0.28, 0.42, 0.52, 0.8)
	style.set_corner_radius_all(8)
	return style


func _edge_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]
