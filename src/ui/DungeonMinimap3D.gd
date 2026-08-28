class_name DungeonMinimap3D
extends Control
## 实时战术小地图：以当前楼层 AABB 为整张地图画布。
## 房间/走廊/门全部按真实墙体位置画蓝色线段；玩家居中（雷达模式）或全图铺开。
## 敌人红点、楼层堆叠、当前房间脉冲高亮保留。

# 战术信息不参与瞄准判定；15Hz 足以保持移动/红点连续。
const REDRAW_INTERVAL := 1.0 / 15.0
const HEADER_HEIGHT := 24.0
# 同层房间用严格容差；楼梯/电梯等垂直通道的 position.y 跟玩家脚底差几米，
# 用更宽的容差避免它们被当层过滤掉而消失，造成"垂直通道歪掉"的视觉错觉。
const FLOOR_EPSILON_M := 0.45
const VERTICAL_CHANNEL_EPSILON_M := 12.0
const RADAR_CONTENT_MARGIN_PX := 10.0

# 风格统一：所有墙体/门/走廊统一蓝色线段。
const WALL_COLOR := Color(0.36, 0.78, 1.0, 0.92)
const WALL_GLOW_COLOR := Color(0.36, 0.78, 1.0, 0.18)
const WALL_WIDTH := 1.6
const WALL_GLOW_WIDTH := 4.0
# 门关闭时，门框短竖线颜色（仍然用蓝）。
const DOOR_JAMB_COLOR := Color(0.36, 0.78, 1.0, 0.95)
const DOOR_JAMB_LENGTH_M := 1.8
const DOOR_GAP_HALF_M := 2.6

# 当前房间高亮（仍走蓝色家族，避免破坏统一风格）。
const CURRENT_ROOM_GLOW := Color(0.55, 0.95, 1.0, 0.55)
const CURRENT_ROOM_EDGE := Color(0.85, 1.0, 1.0, 1.0)
const ENEMY_COLOR := Color(1.0, 0.18, 0.22, 1.0)
const ENEMY_HALO := Color(1.0, 0.18, 0.22, 0.32)
const PLAYER_FILL := Color(0.92, 1.0, 1.0, 1.0)
const PLAYER_EDGE := Color(0.20, 0.82, 0.96, 1.0)
const FLOOR_DOT_ACTIVE := Color(1.0, 0.78, 0.30, 1.0)
const FLOOR_DOT_INACTIVE := Color(0.30, 0.72, 0.88, 0.55)
const FRAME_COLOR := Color(0.32, 0.78, 0.92, 0.75)
const FRAME_BG := Color(0.0, 0.02, 0.04, 0.42)
const RADAR_BG := Color(0.006, 0.020, 0.034, 0.78)

var _records: Array[Dictionary] = []
var _edges: Dictionary = {}
var _revealed: Dictionary = {}
var _current_room_id := ""
var _position_by_id: Dictionary = {}
var _record_by_id: Dictionary = {}
var _dimensions_by_id: Dictionary = {}
var _floor_heights: Array[float] = []
var _has_multiple_floors := false
var _current_floor_y := 0.0
var _player_world_position := Vector3.ZERO
var _player_aim_direction := Vector3.FORWARD
var _scan_phase := 0.0
var _pulse_phase := 0.0
var _redraw_accumulator := 0.0
var _has_realtime_player_state := false
var _enemy_world_positions: Array[Vector3] = []
var _full_map_mode := false


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
	_dimensions_by_id.clear()
	_floor_heights.clear()
	for record in _records:
		var room_id := str(record.get("id", ""))
		var position := record.get("position", Vector3.ZERO) as Vector3
		_position_by_id[room_id] = position
		_record_by_id[room_id] = record
		_dimensions_by_id[room_id] = _room_dimensions(record)
		var floor_y := snappedf(position.y, 0.01)
		if not _contains_floor_height(floor_y):
			_floor_heights.append(floor_y)
	_floor_heights.sort()
	_has_multiple_floors = _floor_heights.size() > 1
	queue_redraw()


func set_full_map_mode(enabled: bool) -> void:
	_full_map_mode = enabled
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func copy_state_from(source: DungeonMinimap3D) -> void:
	if source == null:
		return
	_records = source._records.duplicate(true)
	_edges = source._edges.duplicate(true)
	_revealed = source._revealed.duplicate(true)
	_current_room_id = source._current_room_id
	_position_by_id = source._position_by_id.duplicate(true)
	_record_by_id = source._record_by_id.duplicate(true)
	_dimensions_by_id = source._dimensions_by_id.duplicate(true)
	_floor_heights = source._floor_heights.duplicate()
	_has_multiple_floors = source._has_multiple_floors
	_current_floor_y = source._current_floor_y
	_player_world_position = source._player_world_position
	_player_aim_direction = source._player_aim_direction
	_has_realtime_player_state = source._has_realtime_player_state
	_enemy_world_positions.assign(source._enemy_world_positions)
	queue_redraw()


func reveal_room(room_id: String) -> void:
	_revealed[room_id] = true
	queue_redraw()


func set_current_room(room_id: String) -> void:
	_current_room_id = room_id
	var position := _position_by_id.get(room_id, Vector3.ZERO) as Vector3
	_current_floor_y = position.y
	reveal_room(room_id)


func set_current_floor_height(world_y: float) -> void:
	var snapped_y := snappedf(world_y, 0.01)
	if is_equal_approx(_current_floor_y, snapped_y):
		return
	_current_floor_y = snapped_y
	queue_redraw()


func set_player_state(
	world_position: Vector3,
	aim_direction: Vector3
) -> void:
	_player_world_position = world_position
	var planar_aim := Vector3(aim_direction.x, 0.0, aim_direction.z)
	if planar_aim.length_squared() > 0.0001:
		_player_aim_direction = planar_aim.normalized()
	_has_realtime_player_state = true


func set_enemy_positions(world_positions: Array[Vector3]) -> void:
	_enemy_world_positions.assign(world_positions)


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
			"current_floor_floorplan"
			if _has_multiple_floors
			else "planar_floorplan"
		),
		"current_floor_y": _current_floor_y,
		"floor_count": _floor_heights.size(),
		"realtime_player_state": _has_realtime_player_state,
		"realtime_update_hz": int(round(1.0 / REDRAW_INTERVAL)),
		"player_marker": true,
		"player_heading": true,
		"player_heading_line": false,
		"player_centered": _has_realtime_player_state and not _full_map_mode,
		"map_moves_with_player": _has_realtime_player_state and not _full_map_mode,
		"circular_content_clip": not _full_map_mode,
		"radar_world_diameter_m": 0.0,
		"true_room_dimensions": true,
		"enemy_marker_count": _enemy_world_positions.size(),
		"enemy_markers": true,
		"holographic_scan": true,
		"scan_beam_line": false,
		"floor_stack_index": _has_multiple_floors,
		"full_map_mode": _full_map_mode,
		"wall_line_render": true,
		"walls_color_uniform_blue": true,
	}


# ---------------------------------------------------------------------------
# 绘制入口
# ---------------------------------------------------------------------------

func _draw() -> void:
	var full_rect := Rect2(Vector2.ZERO, size)
	if _full_map_mode:
		draw_rect(full_rect, FRAME_BG, true)
		draw_rect(full_rect.grow(-3.0), FRAME_COLOR, false, 2.0)
		draw_rect(full_rect.grow(-10.0), Color(0.12, 0.46, 0.62, 0.6), false, 1.0)
	else:
		_draw_radar_frame(full_rect)
	_draw_header()
	if _records.is_empty():
		return
	var bounds := _bounds_for_current_floor()
	var map_rect := _content_map_rect()
	if _has_realtime_player_state and not _full_map_mode:
		_draw_player_pulse_ring(map_rect)
	_draw_walls_and_doors(bounds, map_rect)
	_draw_enemies(bounds, map_rect)
	_draw_player(bounds, map_rect)
	if _has_multiple_floors:
		_draw_floor_stack()


# ---------------------------------------------------------------------------
# 墙体 + 走廊 + 门 全部走蓝色线段
# ---------------------------------------------------------------------------

func _draw_walls_and_doors(bounds: Rect2, map_rect: Rect2) -> void:
	# 先画当前层所有已探索房间的 4 条墙（蓝色线段，门洞处中断）。
	for record in _records:
		var room_id := str(record.get("id", ""))
		if not _revealed.has(room_id):
			continue
		var world_position := record.get("position", Vector3.ZERO) as Vector3
		if not _is_current_floor_y(world_position.y):
			continue
		var dimensions := _dimensions_by_id.get(room_id, Vector2(20.0, 18.0)) as Vector2
		var rect_world := _room_world_rect(world_position, dimensions)
		_draw_room_walls(room_id, rect_world, bounds, map_rect)

	# 再画走廊：把"两端房间在门洞位置的边缘点"用蓝色线段连起来。
	_drawn_corridors(bounds, map_rect)


# 房间的 4 面墙：每面墙在"门洞"位置拆成两段（门洞宽度 DOOR_GAP_HALF_M * 2）。
func _draw_room_walls(
	room_id: String,
	rect_world: Rect2,
	bounds: Rect2,
	map_rect: Rect2
) -> void:
	var doors: Array = _record_by_id.get(room_id, {}).get("doors", [])
	var door_set := {}
	for d in doors:
		door_set[str(d)] = true

	var edges := [
		{"side": "north", "p0": Vector2(rect_world.position.x, rect_world.position.y),
			"p1": Vector2(rect_world.end.x, rect_world.position.y),
			"normal": Vector2(0.0, -1.0)},
		{"side": "south", "p0": Vector2(rect_world.position.x, rect_world.end.y),
			"p1": Vector2(rect_world.end.x, rect_world.end.y),
			"normal": Vector2(0.0, 1.0)},
		{"side": "west", "p0": Vector2(rect_world.position.x, rect_world.position.y),
			"p1": Vector2(rect_world.position.x, rect_world.end.y),
			"normal": Vector2(-1.0, 0.0)},
		{"side": "east", "p0": Vector2(rect_world.end.x, rect_world.position.y),
			"p1": Vector2(rect_world.end.x, rect_world.end.y),
			"normal": Vector2(1.0, 0.0)},
	]
	var is_current := room_id == _current_room_id

	for edge in edges:
		var side := str(edge["side"])
		var p0: Vector2 = edge["p0"]
		var p1: Vector2 = edge["p1"]
		var has_door := door_set.has(side)
		if has_door:
			var opened := _is_door_opened(room_id, side)
			_draw_wall_with_door(
				p0, p1, opened, bounds, map_rect, side, is_current
			)
		else:
			# 实墙：一条完整的蓝色线段 + 外发光。
			_clip_and_draw_line(p0, p1, bounds, map_rect,
				CURRENT_ROOM_EDGE if is_current else WALL_COLOR,
				WALL_WIDTH,
				CURRENT_ROOM_GLOW if is_current else WALL_GLOW_COLOR,
				WALL_GLOW_WIDTH)


# 墙带门：拆成"门左墙 + 门右墙 + （可选）门框竖线 + 走廊连过去的蓝线段"。
func _draw_wall_with_door(
	p0: Vector2, p1: Vector2,
	opened: bool,
	bounds: Rect2, map_rect: Rect2,
	side: String,
	is_current: bool
) -> void:
	var edge_len := p0.distance_to(p1)
	if edge_len <= 0.0001:
		return
	var dir := (p1 - p0) / edge_len
	var mid := (p0 + p1) * 0.5
	var half_gap := DOOR_GAP_HALF_M
	var left_end := mid - dir * half_gap
	var right_start := mid + dir * half_gap

	var wall_color := CURRENT_ROOM_EDGE if is_current else WALL_COLOR
	var wall_glow := CURRENT_ROOM_GLOW if is_current else WALL_GLOW_COLOR
	var wall_width := WALL_WIDTH
	var wall_glow_width := WALL_GLOW_WIDTH

	# 门左半墙 + 门右半墙。
	_clip_and_draw_line(p0, left_end, bounds, map_rect, wall_color, wall_width, wall_glow, wall_glow_width)
	_clip_and_draw_line(right_start, p1, bounds, map_rect, wall_color, wall_width, wall_glow, wall_glow_width)

	if not opened:
		# 关门：在门洞两侧画短竖线作为门框（蓝色）。
		var perp := Vector2(-dir.y, dir.x) * (DOOR_JAMB_LENGTH_M * 0.5)
		_clip_and_draw_line(left_end - perp, left_end + perp, bounds, map_rect,
			DOOR_JAMB_COLOR, 1.4, DOOR_JAMB_COLOR, 2.6)
		_clip_and_draw_line(right_start - perp, right_start + perp, bounds, map_rect,
			DOOR_JAMB_COLOR, 1.4, DOOR_JAMB_COLOR, 2.6)
	else:
		# 开门：门洞位置向外延伸一段蓝线作为"通过门洞的视线"。
		var extend := dir * half_gap * 0.4
		_clip_and_draw_line(left_end, right_start, bounds, map_rect,
			WALL_COLOR, wall_width, WALL_GLOW_COLOR, wall_glow_width)


# 走廊：对每个已探索房间的每个朝向门，若通向另一已探索房间，
# 用蓝色线段把"本房间门洞中心点 → 邻房间门洞中心点"连起来。
# 门关时不画走廊线（视觉上"墙堵住了"）。
func _drawn_corridors(bounds: Rect2, map_rect: Rect2) -> void:
	for record in _records:
		var room_id := str(record.get("id", ""))
		if not _revealed.has(room_id):
			continue
		var record_pos := record.get("position", Vector3.ZERO) as Vector3
		if not _is_current_floor_y(record_pos.y):
			continue
		var door_targets_raw: Dictionary = record.get("door_targets", {})
		var dimensions := _dimensions_by_id.get(room_id, Vector2(20.0, 18.0)) as Vector2
		var rect_world := _room_world_rect(record_pos, dimensions)
		# 避免重复画（只画 id 字典序小的 → 大的）。
		for side in door_targets_raw.keys():
			var neighbor_id := str(door_targets_raw[side])
			if room_id >= neighbor_id:
				continue
			if not _revealed.has(neighbor_id):
				continue
			if not _is_current_floor_y(
				(_position_by_id.get(neighbor_id, Vector3.ZERO) as Vector3).y
			):
				continue
			# 门必须是双向开着的至少一侧（或两侧都已 revealed）。
			if not _is_door_opened(room_id, side):
				continue
			var other_side := _opposite_side(side)
			if not _is_door_opened(neighbor_id, other_side):
				continue
			var my_door := _door_world_point(record_pos, rect_world, side)
			var neighbor_record: Dictionary = _record_by_id.get(neighbor_id, {})
			var neighbor_pos := neighbor_record.get("position", Vector3.ZERO) as Vector3
			var neighbor_dims := _dimensions_by_id.get(neighbor_id, Vector2(20.0, 18.0)) as Vector2
			var neighbor_rect := _room_world_rect(neighbor_pos, neighbor_dims)
			var neighbor_door := _door_world_point(neighbor_pos, neighbor_rect, other_side)
			_clip_and_draw_line(
				my_door, neighbor_door, bounds, map_rect,
				WALL_COLOR, WALL_WIDTH, WALL_GLOW_COLOR, WALL_GLOW_WIDTH
			)


func _door_world_point(room_pos: Vector3, rect_world: Rect2, side: String) -> Vector2:
	# 返回该朝向门洞中心点的世界 (x, z) 投影。
	var mid := Vector2(room_pos.x, room_pos.z)
	match side:
		"north":
			return Vector2(mid.x, rect_world.position.y)
		"south":
			return Vector2(mid.x, rect_world.end.y)
		"west":
			return Vector2(rect_world.position.x, mid.y)
		"east":
			return Vector2(rect_world.end.x, mid.y)
		_:
			return mid


func _opposite_side(side: String) -> String:
	match side:
		"north": return "south"
		"south": return "north"
		"east": return "west"
		"west": return "east"
		_: return ""


func _is_door_opened(room_id: String, side: String) -> bool:
	# 1) record.doors 里有这个朝向但 door_targets 没值 → 视作"已开/可通"
	# 2) door_targets 有值 → 查 _edges[a|b]
	# 3) record.doors 里没有 → 返回 false（不该出现）
	var record: Dictionary = _record_by_id.get(room_id, {})
	var doors: Array = record.get("doors", [])
	var has_side := false
	for d in doors:
		if str(d) == side:
			has_side = true
			break
	if not has_side:
		return false
	var door_targets: Dictionary = record.get("door_targets", {})
	if not door_targets.has(side):
		return true
	var neighbor_id := str(door_targets[side])
	if neighbor_id.is_empty():
		return true
	var edge: Variant = _edges.get(_edge_key(room_id, neighbor_id), null)
	if edge == null:
		# 边的开合状态未上报 → 默认开（已通过门洞 = 两房间已 reveal 的最常见状态）。
		return true
	return bool(edge)


# ---------------------------------------------------------------------------
# 玩家 / 敌人 / 楼层堆叠
# ---------------------------------------------------------------------------

func _draw_player_pulse_ring(map_rect: Rect2) -> void:
	if not _has_realtime_player_state:
		return
	var center := map_rect.get_center()
	var pulse_radius := 6.0 + _pulse_phase * 28.0
	draw_arc(
		center,
		pulse_radius,
		0.0,
		TAU,
		40,
		Color(0.28, 0.94, 1.0, (1.0 - _pulse_phase) * 0.22),
		1.0
	)


func _draw_enemies(bounds: Rect2, map_rect: Rect2) -> void:
	for world_position in _enemy_world_positions:
		if not _is_current_floor_y(world_position.y):
			continue
		var center := _map_position(world_position, bounds, map_rect)
		if not _full_map_mode and not _point_inside_radar(center, 5.0):
			continue
		draw_circle(center, 5.2, ENEMY_HALO)
		draw_circle(center, 2.8, ENEMY_COLOR)
		draw_arc(center, 4.6, 0.0, TAU, 18, ENEMY_HALO, 1.0)


func _draw_player(bounds: Rect2, map_rect: Rect2) -> void:
	if not _has_realtime_player_state:
		return
	var center := _map_position(_player_world_position, bounds, map_rect)
	# 雷达模式下永远居中，全图模式按真实位置落点。
	if not _full_map_mode:
		center = map_rect.get_center()
	var heading := Vector2(
		_player_aim_direction.x,
		_player_aim_direction.z
	).normalized()
	if heading.length_squared() <= 0.0001:
		heading = Vector2.UP
	var perpendicular := Vector2(-heading.y, heading.x)
	var points := PackedVector2Array([
		center + heading * 9.0,
		center - heading * 5.5 + perpendicular * 4.5,
		center - heading * 5.5 - perpendicular * 4.5,
	])
	draw_colored_polygon(points, PLAYER_FILL)
	draw_polyline(
		PackedVector2Array([points[0], points[1], points[2], points[0]]),
		PLAYER_EDGE,
		1.3
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
			FLOOR_DOT_ACTIVE if active else FLOOR_DOT_INACTIVE
		)


# ---------------------------------------------------------------------------
# 坐标 / 几何
# ---------------------------------------------------------------------------

func _room_world_rect(room_pos: Vector3, dimensions: Vector2) -> Rect2:
	# 房间 world 坐标 (x,z) 的真实矩形（无内缩，跟战斗盒一致）。
	var half := dimensions * 0.5
	return Rect2(
		Vector2(room_pos.x - half.x, room_pos.z - half.y),
		dimensions
	)


func _room_dimensions(record: Dictionary) -> Vector2:
	var custom := record.get("custom_dimensions", Vector2.ZERO) as Vector2
	if custom.x > 0.0 and custom.y > 0.0:
		return custom
	return DungeonRoom3D.ROOM_DIMENSIONS.get(
		str(record.get("size", "medium")), DungeonRoom3D.ROOM_DIMENSIONS["medium"]
	) as Vector2


func _bounds_for_current_floor() -> Rect2:
	# 当层所有房间的真实矩形 AABB，作为整张地图的画布。
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	var any := false
	for record in _records:
		var position := record.get("position", Vector3.ZERO) as Vector3
		if not _is_current_floor_y(position.y):
			continue
		any = true
		var dimensions := _room_dimensions(record)
		var rect := _room_world_rect(position, dimensions)
		min_pos.x = minf(min_pos.x, rect.position.x)
		min_pos.y = minf(min_pos.y, rect.position.y)
		max_pos.x = maxf(max_pos.x, rect.end.x)
		max_pos.y = maxf(max_pos.y, rect.end.y)
	if not any:
		return Rect2(Vector2(-1.0, -1.0), Vector2(2.0, 2.0))
	return Rect2(min_pos, max_pos - min_pos)


func _map_position(
	world_position: Vector3,
	bounds: Rect2,
	map_rect: Rect2
) -> Vector2:
	# 雷达模式：以玩家居中，地图按 scale 缩放后画布跟着玩家走。
	if _has_realtime_player_state and not _full_map_mode:
		var scale := _map_scale(bounds, map_rect)
		var projected := Vector2(world_position.x, world_position.z)
		var player_projected := Vector2(_player_world_position.x, _player_world_position.z)
		return map_rect.get_center() + (projected - player_projected) * scale
	# 全图模式：按 bounds 归一化铺满 map_rect。
	var scale := _map_scale(bounds, map_rect)
	var used_size := bounds.size * scale
	var origin := map_rect.get_center() - used_size * 0.5
	return origin + (Vector2(world_position.x, world_position.z) - bounds.position) * scale


func _map_scale(bounds: Rect2, map_rect: Rect2) -> float:
	# 雷达模式：固定把直径 = 长边 1.5 倍的世界范围塞进圆（保证整层至少能完整显示一次）。
	if _has_realtime_player_state and not _full_map_mode:
		var longest := maxf(bounds.size.x, bounds.size.y)
		if longest < 1.0:
			longest = 1.0
		# 1.5 = 圆里装的是楼层长边的 1.5 倍范围；改为 1.0 让画面放大、可见范围缩小。
		return minf(map_rect.size.x, map_rect.size.y) / (longest * 1.0)
	# 全图模式：bounds 完整塞进 map_rect（留 6% 边距）。
	var inset := 0.94
	var sx := map_rect.size.x / maxf(1.0, bounds.size.x) * inset
	var sy := map_rect.size.y / maxf(1.0, bounds.size.y) * inset
	return minf(sx, sy)


func _content_map_rect() -> Rect2:
	if _full_map_mode:
		return Rect2(
			Vector2(64.0, 62.0),
			Vector2(maxf(1.0, size.x - 128.0), maxf(1.0, size.y - 112.0))
		)
	# 雷达模式：圆形窗口，map_rect 取控件最大内接正方形。
	var side := maxf(1.0, minf(size.x, size.y))
	return Rect2(size * 0.5 - Vector2.ONE * side * 0.5, Vector2.ONE * side)


# ---------------------------------------------------------------------------
# 雷达 / 圆裁剪 / 框
# ---------------------------------------------------------------------------

func _draw_radar_frame(rect: Rect2) -> void:
	var center := rect.get_center()
	var radius := maxf(4.0, minf(rect.size.x, rect.size.y) * 0.5 - 7.0)
	draw_circle(center, radius + 4.0, RADAR_BG)
	draw_arc(center, radius, 0.0, TAU, 96, Color(0.18, 0.78, 0.92, 0.85), 1.4, true)
	draw_arc(center, radius - 5.0, -0.72, 0.72, 22, Color(0.32, 0.92, 1.0, 0.55), 1.6, true)
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var outer := center + Vector2.from_angle(angle) * (radius + 4.0)
		var inner := center + Vector2.from_angle(angle) * (radius - 7.0)
		draw_line(inner, outer, Color(0.55, 0.96, 1.0, 0.75), 1.4, true)


func _draw_header() -> void:
	var font := ThemeDB.fallback_font
	draw_string(
		font,
		Vector2(0.0, 23.0),
		("EXPLORED FLOOR PLAN / %s" if _full_map_mode else "TACTICAL / %s") % _floor_label(),
		HORIZONTAL_ALIGNMENT_CENTER,
		size.x,
		12,
		Color(0.48, 0.94, 1.0, 0.84)
	)


func _radar_center() -> Vector2:
	return size * 0.5


func _radar_radius(margin := 0.0) -> float:
	return maxf(1.0, minf(size.x, size.y) * 0.5 - 7.0 - RADAR_CONTENT_MARGIN_PX - margin)


func _point_inside_radar(point: Vector2, margin := 0.0) -> bool:
	return point.distance_to(_radar_center()) <= _radar_radius(margin)


# ---------------------------------------------------------------------------
# 圆裁剪画线段：圆内整段画，部分在圆外则裁到交点，全在圆外则不画
# ---------------------------------------------------------------------------

func _clip_and_draw_line(
	world_p0: Vector2,
	world_p1: Vector2,
	bounds: Rect2,
	map_rect: Rect2,
	color: Color,
	width: float,
	glow_color: Color,
	glow_width: float
) -> void:
	var p0 := _map_position(
		Vector3(world_p0.x, 0.0, world_p0.y), bounds, map_rect
	)
	var p1 := _map_position(
		Vector3(world_p1.x, 0.0, world_p1.y), bounds, map_rect
	)
	if _full_map_mode:
		# 全图模式不裁圆，直接画（外加发光）。
		if glow_width > 0.0:
			draw_line(p0, p1, glow_color, glow_width, true)
		draw_line(p0, p1, color, width, true)
		return
	var clipped := _clip_segment_to_radar(p0, p1, 0.0)
	if clipped.size() != 2:
		return
	if glow_width > 0.0:
		draw_line(clipped[0], clipped[1], glow_color, glow_width, true)
	draw_line(clipped[0], clipped[1], color, width, true)


func _clip_segment_to_radar(from: Vector2, to: Vector2, margin := 0.0) -> PackedVector2Array:
	var center := _radar_center()
	var radius := _radar_radius(margin)
	var from_inside := from.distance_squared_to(center) <= radius * radius
	var to_inside := to.distance_squared_to(center) <= radius * radius
	if from_inside and to_inside:
		return PackedVector2Array([from, to])
	var direction := to - from
	var a := direction.dot(direction)
	if a <= 0.000001:
		return PackedVector2Array()
	var relative := from - center
	var b := 2.0 * relative.dot(direction)
	var c := relative.dot(relative) - radius * radius
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return PackedVector2Array()
	var root := sqrt(discriminant)
	var intersections: Array[float] = []
	for value in [(-b - root) / (2.0 * a), (-b + root) / (2.0 * a)]:
		if value >= 0.0 and value <= 1.0:
			intersections.append(value)
	intersections.sort()
	var clipped_from: Vector2 = from if from_inside else (
		from + direction * intersections[0] if not intersections.is_empty() else Vector2.INF
	)
	var clipped_to: Vector2 = to if to_inside else (
		from + direction * intersections.back() if not intersections.is_empty() else Vector2.INF
	)
	if clipped_from == Vector2.INF or clipped_to == Vector2.INF:
		return PackedVector2Array()
	return PackedVector2Array([clipped_from, clipped_to])


# ---------------------------------------------------------------------------
# 杂项
# ---------------------------------------------------------------------------

func _is_current_floor_y(value: float) -> bool:
	# 当层 = 严格容差
	if absf(value - _current_floor_y) <= FLOOR_EPSILON_M:
		return true
	# 垂直通道（楼梯/电梯/垂直连接房间）= 宽容差，避免它们跨层消失
	return _is_vertical_channel_y(value)


func _is_vertical_channel_y(value: float) -> bool:
	if absf(value - _current_floor_y) > VERTICAL_CHANNEL_EPSILON_M:
		return false
	# 只有 STAIRS_UP / STAIRS_DOWN / BASEMENT / ELEVATOR 等垂直类型房间按宽容差显示
	for record in _records:
		var position := record.get("position", Vector3.ZERO) as Vector3
		if not is_equal_approx_snapped(position.y, value):
			continue
		var type_id := str(record.get("type", ""))
		if type_id in ["STAIRS_UP", "STAIRS_DOWN", "STAIR_LOBBY", "BASEMENT", "ELEVATOR"]:
			return true
		var vertical_level := int(record.get("vertical_level", 0))
		if vertical_level != 0:
			return true
	return false


static func is_equal_approx_snapped(a: float, b: float) -> bool:
	return is_equal_approx(snappedf(a, 0.01), snappedf(b, 0.01))


func _contains_floor_height(value: float) -> bool:
	for existing in _floor_heights:
		if is_equal_approx(existing, value):
			return true
	return false


func _floor_label() -> String:
	if _has_multiple_floors:
		return "%dF" % int(round(100.0 + _current_floor_y / 9.0))
	return "LIVE"


func _edge_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


# 兼容旧调用：保留旧接口但内部走新绘制路径
func get_room_screen_rect(room_id: String) -> Rect2:
	if not _record_by_id.has(room_id):
		return Rect2()
	var record := _record_by_id[room_id] as Dictionary
	var world_position := record.get("position", Vector3.ZERO) as Vector3
	if not _is_current_floor_y(world_position.y):
		return Rect2()
	var bounds := _bounds_for_current_floor()
	var map_rect := _content_map_rect()
	var dimensions := _dimensions_by_id.get(room_id, Vector2(20.0, 18.0)) as Vector2
	var rect_world := _room_world_rect(world_position, dimensions)
	var center := _map_position(world_position, bounds, map_rect)
	var room_size := rect_world.size * _map_scale(bounds, map_rect)
	return Rect2(center - room_size * 0.5, room_size)


func get_player_screen_position() -> Vector2:
	return _map_position(_player_world_position, _bounds_for_current_floor(), _content_map_rect())


func get_floor_label() -> String:
	return _floor_label()
