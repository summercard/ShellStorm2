class_name MinimapView
extends Control
## 小地图绘制控件
## 自身拥有 _draw()，由 GameUIManager 通过 set_data() 注入数据
## 不依赖 RenderingServer 直接绘制，避免 CanvasLayer._draw() 失效问题

# — 视觉常量 —
const BG_COLOR := Color(0.05, 0.06, 0.10, 0.95)
const BORDER_COLOR := Color(0.4, 0.4, 0.55, 0.7)
const BORDER_WIDTH := 1.0
const HIDDEN_ALPHA := 0.18  # 未揭示房间的透明度
const NODE_BASE_SIZE := 5.0
const NODE_CURRENT_SIZE := 8.0
const PLAYER_OUTER_RADIUS := 4.5
const PLAYER_INNER_RADIUS := 2.0
const DASH_LENGTH := 5.0
const DASH_GAP := 3.0

# — 房间类型颜色（key 对应 RoomData.RoomType 枚举值）—
const ROOM_COLORS := {
	0: Color(0.45, 0.95, 0.55, 0.95),  # PLAYER_SPAWN
	1: Color(0.95, 0.32, 0.32, 0.95),  # COMBAT
	2: Color(1.00, 0.62, 0.15, 0.95),  # ELITE
	3: Color(0.30, 0.78, 1.00, 0.95),  # SCAVENGE
	4: Color(1.00, 0.85, 0.20, 0.95),  # MERCHANT
	5: Color(0.62, 0.42, 1.00, 0.95),  # UPGRADE
	6: Color(0.92, 0.30, 0.90, 0.95),  # EVENT
	7: Color(0.20, 1.00, 0.62, 0.95),  # EXTRACTION
	8: Color(1.00, 0.10, 0.10, 1.00),  # BOSS
	9: Color(0.65, 0.65, 0.75, 0.85),  # STORAGE
	10: Color(0.85, 0.40, 0.30, 0.95), # TRAP
	11: Color(0.30, 0.55, 0.85, 0.95), # BASEMENT
	12: Color(0.55, 0.85, 0.85, 0.85), # STAIRS_DOWN
	13: Color(0.85, 0.85, 0.55, 0.85), # STAIRS_UP
	14: Color(0.50, 0.80, 0.95, 0.85), # ELEVATOR
}

# — 门状态颜色 —
const DOOR_LINE_OPEN := Color(0.45, 0.70, 0.45, 0.85)
const DOOR_LINE_CLOSED := Color(0.50, 0.40, 0.40, 0.55)
const DOOR_LINE_BOSS := Color(0.85, 0.20, 0.20, 0.90)
const DOOR_LINE_EXTRACTION := Color(0.25, 0.55, 0.95, 0.90)

# — 玩家/当前房间颜色 —
const PLAYER_OUTER_COLOR := Color(0.45, 0.85, 1.00, 0.55)
const PLAYER_INNER_COLOR := Color(1.00, 1.00, 1.00, 1.00)
const CURRENT_GLOW_COLOR := Color(1.00, 1.00, 1.00, 1.00)

# — 数据 —
var _nodes: Array[Dictionary] = []  # [{id, node_pos, type, is_current, is_revealed}]
var _connections: Array[Dictionary] = []  # [{from_pos, to_pos, is_open, door_type}]
var _player_world_pos: Vector2 = Vector2.ZERO
var _player_node_pos: Vector2 = Vector2.ZERO
var _has_player_in_current: bool = false
var _font: Font = null
var _pulse_phase: float = 0.0


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_pulse_phase = randf() * TAU
	# 允许鼠标事件穿透（不阻挡玩家点击）
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 注入当前地图数据（房间/地图变化时调用）
func set_data(
	nodes: Array,
	connections: Array,
	player_world_pos: Vector2,
	player_node_pos: Vector2
) -> void:
	_nodes = nodes
	_connections = connections
	_player_world_pos = player_world_pos
	_player_node_pos = player_node_pos
	_has_player_in_current = player_node_pos != Vector2.ZERO
	queue_redraw()


## 轻量更新：仅刷新玩家世界位置（每帧调用，避免重建数据）
func update_player_position(player_world_pos: Vector2) -> void:
	if _player_world_pos == player_world_pos:
		return
	_player_world_pos = player_world_pos
	queue_redraw()


## 主动清空（地图销毁时）
func clear() -> void:
	_nodes = []
	_connections = []
	_has_player_in_current = false
	queue_redraw()


## 是否处于有效追踪状态（外部判断每帧更新是否需要）
func has_active_player() -> bool:
	return _has_player_in_current and not _nodes.is_empty()


## 仅在存在脉冲元素（当前房间）时驱动重绘
func _process(delta: float) -> void:
	if _nodes.is_empty() or not _has_player_in_current:
		return
	_pulse_phase += delta * 2.4
	queue_redraw()


## 绘制小地图内容
func _draw() -> void:
	var sz: Vector2 = size
	# 背景
	draw_rect(Rect2(Vector2.ZERO, sz), BG_COLOR, true)
	# 边框
	draw_rect(Rect2(Vector2.ZERO, sz), BORDER_COLOR, false, BORDER_WIDTH)

	if _nodes.is_empty():
		_draw_empty_state(sz)
		return

	var bounds: Rect2 = _calc_bounds()

	# 1) 连接线（先画线，再画点，让点盖在线上）
	_draw_connections(bounds, sz)

	# 2) 房间节点
	_draw_room_nodes(bounds, sz)

	# 3) 玩家点（最上层）
	_draw_player(bounds, sz)


func _draw_empty_state(sz: Vector2) -> void:
	if _font == null:
		return
	var text := "等待地图..."
	var font_size := 12
	var ts := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(
		_font,
		(sz - ts) * 0.5,
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1,
		font_size,
		Color(0.55, 0.55, 0.70, 0.8)
	)


func _draw_connections(bounds: Rect2, sz: Vector2) -> void:
	for conn in _connections:
		var from_pos: Vector2 = conn.get("from_pos", Vector2.ZERO)
		var to_pos: Vector2 = conn.get("to_pos", Vector2.ZERO)
		var is_open: bool = conn.get("is_open", false)
		var door_type: String = conn.get("door_type", "normal")

		var a: Vector2 = _world_to_view(from_pos, bounds, sz)
		var b: Vector2 = _world_to_view(to_pos, bounds, sz)

		# 颜色根据门类型与开闭状态
		var col: Color
		if not is_open:
			col = DOOR_LINE_CLOSED
		elif door_type == "boss":
			col = DOOR_LINE_BOSS
		elif door_type == "extraction":
			col = DOOR_LINE_EXTRACTION
		else:
			col = DOOR_LINE_OPEN

		if is_open:
			draw_line(a, b, col, 1.6)
		else:
			_draw_dashed_line(a, b, col, 1.2)


func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var delta: Vector2 = to - from
	var length: float = delta.length()
	if length < 1.0:
		return
	var step: float = DASH_LENGTH + DASH_GAP
	var dir: Vector2 = delta / length
	var t: float = 0.0
	while t < length:
		var seg_end: float = minf(t + DASH_LENGTH, length)
		draw_line(from + dir * t, from + dir * seg_end, color, width)
		t += step


func _draw_room_nodes(bounds: Rect2, sz: Vector2) -> void:
	var pulse: float = (sin(_pulse_phase) * 0.5 + 0.5)  # 0~1

	for nd in _nodes:
		var node_pos: Vector2 = nd.get("node_pos", Vector2.ZERO)
		var pos: Vector2 = _world_to_view(node_pos, bounds, sz)
		var room_type: int = nd.get("type", -1)
		var is_current: bool = nd.get("is_current", false)
		var is_revealed: bool = nd.get("is_revealed", true)

		var color: Color = ROOM_COLORS.get(room_type, Color(0.7, 0.7, 0.75, 0.9))
		if not is_revealed and not is_current:
			color = Color(color.r, color.g, color.b, HIDDEN_ALPHA)

		var nsize: float = NODE_BASE_SIZE
		if is_current:
			nsize = NODE_CURRENT_SIZE

		if is_current:
			# 当前房间：脉冲光圈
			var glow_r: float = nsize + 4.0 + pulse * 5.0
			draw_circle(pos, glow_r, Color(1, 1, 1, 0.12 + pulse * 0.18))
			draw_circle(pos, glow_r + 2.5, Color(1, 1, 1, 0.05))

		# 房间圆点
		draw_circle(pos, nsize, color)

		# BOSS 房：菱形叠加标识
		if room_type == 8:
			var d := nsize + 1.5
			var diamond := PackedVector2Array([
				pos + Vector2(0, -d),
				pos + Vector2(d, 0),
				pos + Vector2(0, d),
				pos + Vector2(-d, 0),
			])
			draw_colored_polygon(diamond, Color(1.0, 0.95, 0.45, 0.95))
		# 撤离房：四角星标识
		elif room_type == 7:
			var d := nsize + 1.0
			var star := PackedVector2Array([
				pos + Vector2(0, -d),
				pos + Vector2(d * 0.4, -d * 0.4),
				pos + Vector2(d, 0),
				pos + Vector2(d * 0.4, d * 0.4),
				pos + Vector2(0, d),
				pos + Vector2(-d * 0.4, d * 0.4),
				pos + Vector2(-d, 0),
				pos + Vector2(-d * 0.4, -d * 0.4),
			])
			draw_colored_polygon(star, Color(0.2, 1.0, 0.6, 0.95))
		# 玩家出生房：外环白圈
		elif room_type == 0 and not is_current:
			draw_arc(pos, nsize + 2.0, 0.0, TAU, 24, Color(1, 1, 1, 0.6), 1.2, true)


func _draw_player(bounds: Rect2, sz: Vector2) -> void:
	if not _has_player_in_current:
		return
	# 玩家在当前房间内的相对偏移（归一化）
	var rel: Vector2 = Vector2.ZERO
	if bounds.size.x > 0 and bounds.size.y > 0:
		rel = (_player_world_pos - _player_node_pos) / bounds.size
	# 偏移限幅（最大不超过小地图半径的 18%）
	var max_off: float = minf(sz.x, sz.y) * 0.18
	var offset := Vector2(
		clamp(rel.x * sz.x * 0.3, -max_off, max_off),
		clamp(rel.y * sz.y * 0.3, -max_off, max_off)
	)
	var dot_pos: Vector2 = _world_to_view(_player_node_pos, bounds, sz) + offset

	# 外圈柔光
	draw_circle(dot_pos, PLAYER_OUTER_RADIUS + 1.5, Color(0.4, 0.85, 1.0, 0.25))
	# 外圈实心
	draw_circle(dot_pos, PLAYER_OUTER_RADIUS, PLAYER_OUTER_COLOR)
	# 内圈白点
	draw_circle(dot_pos, PLAYER_INNER_RADIUS, PLAYER_INNER_COLOR)


## 计算所有节点的世界坐标包围盒
func _calc_bounds() -> Rect2:
	if _nodes.is_empty():
		return Rect2(0, 0, 1, 1)
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for nd in _nodes:
		var p: Vector2 = nd.get("node_pos", Vector2.ZERO)
		min_x = minf(min_x, p.x)
		min_y = minf(min_y, p.y)
		max_x = maxf(max_x, p.x)
		max_y = maxf(max_y, p.y)
	var pad: float = 60.0
	return Rect2(
		min_x - pad,
		min_y - pad,
		(max_x - min_x) + pad * 2.0,
		(max_y - min_y) + pad * 2.0
	)


## 世界坐标 → 视图坐标
func _world_to_view(world_pos: Vector2, bounds: Rect2, view_size: Vector2) -> Vector2:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return view_size * 0.5
	var norm: Vector2 = (world_pos - bounds.position) / bounds.size
	return Vector2(norm.x * view_size.x, norm.y * view_size.y)
