class_name DungeonMinimap3D
extends Control

const TOWER_GEOMETRY := preload("res://src/world3d/TowerGeometry3D.gd")

## 右上角小地图 · **挺进地牢（Enter the Gungeon）式**。
##
## 设计依据：`docs/v0.1/reference/挺进地牢/minimap实现方式.md`
## 交互样张：`docs/v0.1/reference/挺进地牢/minimap样张.html`
##
## 与已退役的圆形雷达的三条本质区别，改动时不许倒退：
##   1. **固定缩放**。整层的每米像素数是常量（`ROOM_PX_PER_M`），
##      只受"满层上限"一次性夹紧，**不随探索进度、不随玩家位置变化**。
##      理由是原作的两个缩放参数（`s_map_view_scale` / `_big`）都是全局常量。
##   2. **地图不动**。房间出现在自己的绝对坐标上，玩家只是其中一个点。
##      雷达那种"玩家恒居圆心、地图反向平移"的做法已删除。
##   3. **矩形拼图**。房间是"填充 + 一周 1~2px 描边 + 门洞断开"的矩形块，
##      不是四根独立线段；走廊是一根细线，不是通道房间。
##
## 信息层照原作：房型用图标表达（底下一律同色，不靠底色区分房型）、
## 未探索只给问号、已清理给绿色弹夹标记。

# ---------------------------------------------------------------------------
# 显示模式（对应原作 OPTIONS_MINIMAPSTYLE 三档）
# ---------------------------------------------------------------------------

enum DisplayMode {
	ALWAYS,      # OPTIONS_MINIMAPALWAYS：一直显示
	NON_COMBAT,  # OPTIONS_MINIMAPNONCOMBAT：战斗中隐藏，清房后自动恢复（原作默认）
	NEVER,       # OPTIONS_MINIMAPNEVER：完全不显示
}

var display_mode: int = DisplayMode.ALWAYS

# 战术信息不参与瞄准判定；15Hz 足以保持移动/红点连续。
const REDRAW_INTERVAL := 1.0 / 15.0

# 同层房间用严格容差；楼梯/电梯等垂直通道的 position.y 跟玩家脚底差几米，
# 用更宽的容差避免它们被当层过滤掉而消失。
const FLOOR_EPSILON_M := 0.45
const VERTICAL_CHANNEL_EPSILON_M := 12.0

# ---------------------------------------------------------------------------
# 规格常量 —— 全部来自原作实机测量，换算到本工程 1920×1080 设计空间
# ---------------------------------------------------------------------------
# 设计密度：原作 480×270 原生下普通房约 21~24px 宽（≈ 屏宽 4.5%）。
# 本工程普通房 32×26m，要落在同一档 ⇒ 约 3.0 px/m。
const ROOM_PX_PER_M := 3.0
# 角落态内容区留白（设计 px）。真正的缩放上限由**面板实测尺寸**决定，
# 见 `_map_scale()`；不要在这里写死像素上限。
const CORNER_MARGIN := Vector2(10.0, 8.0)

# 配色：原作房间填充 (44,50,88)、描边 (192,194,192)，全房间统一，不按房型着色。
const ROOM_FILL := Color(0.172, 0.196, 0.345, 0.92)      # #2C3258
const ROOM_EDGE := Color(0.753, 0.761, 0.753, 0.95)      # #C0C2C0
const ROOM_EDGE_CURRENT := Color(0.93, 0.97, 1.0, 1.0)   # 玩家所在房，提亮描边
const CORRIDOR_COLOR := Color(0.29, 0.325, 0.565, 0.95)  # #4A5390
const LOCKED_DOOR_COLOR := Color(0.784, 0.118, 0.157)    # #C81E28
const UNEXPLORED_COLOR := Color(0.910, 0.220, 0.784)     # #E838C8 洋红问号
const CLEARED_MARK := Color(0.486, 0.878, 0.235)         # #7CE03C 绿色弹夹
const ENEMY_COLOR := Color(1.0, 0.22, 0.24, 1.0)
const ENEMY_HALO := Color(1.0, 0.22, 0.24, 0.30)
const PLAYER_FILL := Color(0.94, 0.98, 1.0, 1.0)
const PLAYER_EDGE := Color(0.16, 0.72, 0.96, 1.0)

# 线宽与缺口（设计 px）
const WALL_PX := 2.0
const CORRIDOR_PX := 2.0
const DOOR_GAP_PX := 8.0
const DOOR_TICK_PX := 3.0
const ICON_PX := 9.0
const FRAME_BG := Color(0.0, 0.02, 0.04, 0.34)
const FRAME_COLOR := Color(0.32, 0.78, 0.92, 0.42)

# 图标色（全部走同一套低饱和描线，不抢房型底色）
const ICON_CHEST := Color(0.96, 0.76, 0.30)
const ICON_BOSS := Color(0.92, 0.78, 0.36)
const ICON_SHOP := Color(0.42, 0.78, 0.96)
const ICON_EVENT := Color(0.78, 0.55, 0.94)
const ICON_HEAL := Color(0.96, 0.36, 0.42)
const ICON_KEY := Color(0.99, 0.86, 0.36)
const ICON_STAIRS := Color(0.62, 0.90, 0.98)
const ICON_EXTRACT := Color(0.42, 0.95, 0.72)
const ICON_DANGER := Color(0.98, 0.52, 0.24)

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------

var _records: Array[Dictionary] = []
var _edges: Dictionary = {}
var _revealed: Dictionary = {}
var _cleared: Dictionary = {}
var _hidden_room_types: Dictionary = {}
var _visited_room_types: Dictionary = {}
var _current_room_id := ""
var _position_by_id: Dictionary = {}
var _record_by_id: Dictionary = {}
var _dimensions_by_id: Dictionary = {}
var _floor_heights: Array[float] = []
var _has_multiple_floors := false
var _current_floor_y := 0.0
var _player_world_position := Vector3.ZERO
var _player_aim_direction := Vector3.FORWARD
var _redraw_accumulator := 0.0
var _has_realtime_player_state := false
var _enemy_world_positions: Array[Vector3] = []
var _full_map_mode := false
var _in_combat := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_redraw_accumulator += delta
	if _redraw_accumulator >= REDRAW_INTERVAL:
		_redraw_accumulator = 0.0
		queue_redraw()


# ---------------------------------------------------------------------------
# 数据入口（契约不变）
# ---------------------------------------------------------------------------

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


func reset_exploration_for_new_run() -> void:
	# configure() 也用于同一战局内追加新楼层，不能在那里清 revealed。
	# 只有明确的新战局边界才清掉上一局的探索路径和实时敌人投影。
	_revealed.clear()
	_cleared.clear()
	_hidden_room_types.clear()
	_visited_room_types.clear()
	_current_room_id = ""
	_enemy_world_positions.clear()
	_has_realtime_player_state = false
	_in_combat = false
	_current_floor_y = 0.0
	queue_redraw()


func set_full_map_mode(enabled: bool) -> void:
	_full_map_mode = enabled
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func set_display_mode(mode: int) -> void:
	display_mode = mode
	queue_redraw()


func set_in_combat(value: bool) -> void:
	_in_combat = value


func copy_state_from(source: DungeonMinimap3D) -> void:
	if source == null:
		return
	_records = source._records.duplicate(true)
	_edges = source._edges.duplicate(true)
	_revealed = source._revealed.duplicate(true)
	_cleared = source._cleared.duplicate(true)
	_hidden_room_types = source._hidden_room_types.duplicate(true)
	_visited_room_types = source._visited_room_types.duplicate(true)
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
	display_mode = source.display_mode
	_in_combat = source._in_combat
	queue_redraw()


func reveal_room(room_id: String, hide_type: bool = false) -> void:
	_revealed[room_id] = true
	if hide_type and not _visited_room_types.has(room_id):
		_hidden_room_types[room_id] = true
	queue_redraw()


func mark_room_cleared(room_id: String) -> void:
	# 支线子图房间不进 `_records`，也不该进地图的"已清"计数 —— 只认本层正式房间。
	if not _record_by_id.has(room_id):
		return
	_cleared[room_id] = true
	queue_redraw()


func is_room_cleared(room_id: String) -> bool:
	return _cleared.has(room_id)


func get_visible_room_type(room_id: String) -> String:
	if not _revealed.has(room_id) or _hidden_room_types.has(room_id):
		return ""
	return str((_record_by_id.get(room_id, {}) as Dictionary).get("type", ""))


func set_current_room(room_id: String) -> void:
	_current_room_id = room_id
	_visited_room_types[room_id] = true
	_hidden_room_types.erase(room_id)
	var position := _position_by_id.get(room_id, Vector3.ZERO) as Vector3
	_current_floor_y = position.y
	reveal_room(room_id)


func set_current_floor_height(world_y: float) -> void:
	var snapped_y := snappedf(world_y, 0.01)
	if is_equal_approx(_current_floor_y, snapped_y):
		return
	_current_floor_y = snapped_y
	queue_redraw()


func set_player_state(world_position: Vector3, aim_direction: Vector3) -> void:
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
		"cleared_count": _cleared.size(),
		"hidden_room_types": _hidden_room_types.keys(),
		"current_room_id": _current_room_id,
		"open_edge_count": _edges.values().count(true),
		"room_count": _records.size(),
		"projection_mode": (
			"current_floor_tile_grid"
			if _has_multiple_floors
			else "planar_tile_grid"
		),
		"current_floor_y": _current_floor_y,
		"floor_count": _floor_heights.size(),
		"realtime_player_state": _has_realtime_player_state,
		"realtime_update_hz": int(round(1.0 / REDRAW_INTERVAL)),
		"player_marker": true,
		"player_heading": true,
		# —— 以下四项是 EGT 式渲染的**契约断言点**，改动前先读文件头三条区别 ——
		"player_centered": false,
		"map_moves_with_player": false,
		"circular_content_clip": false,
		"fixed_scale": true,
		"tile_style": "egt_room_tile",
		"px_per_m": _map_scale(),
		"display_mode": _display_mode_name(),
		"radar_world_diameter_m": 0.0,
		"true_room_dimensions": true,
		"enemy_marker_count": _enemy_world_positions.size(),
		"enemy_markers": true,
		"player_heading_line": false,
		"holographic_scan": false,
		"scan_beam_line": false,
		"floor_stack_index": _has_multiple_floors,
		"full_map_mode": _full_map_mode,
		"wall_line_render": false,
		"walls_color_uniform_blue": false,
		"room_fill_uniform": true,
		"icons_by_room_type": true,
	}


func _display_mode_name() -> String:
	match display_mode:
		DisplayMode.NON_COMBAT: return "non_combat"
		DisplayMode.NEVER: return "never"
		_: return "always"


# ---------------------------------------------------------------------------
# 绘制入口
# ---------------------------------------------------------------------------

func _draw() -> void:
	if _full_map_mode:
		_draw_full_map_backdrop()
	elif not _corner_map_visible():
		return
	else:
		# 角落态只画一层极淡背衬，让贴边的小地图不至于糊进场景
		draw_rect(Rect2(Vector2(2.0, 2.0), size - Vector2(4.0, 4.0)), FRAME_BG, true)

	if _records.is_empty():
		return

	_draw_corridors()
	_draw_rooms()
	_draw_room_icons()
	_draw_unexplored_marks()
	_draw_enemies()
	_draw_player()

	if _full_map_mode:
		_draw_full_map_labels()
	elif _has_multiple_floors:
		_draw_floor_stack()


func _corner_map_visible() -> bool:
	if display_mode == DisplayMode.NEVER:
		return false
	if display_mode == DisplayMode.NON_COMBAT and _in_combat:
		return false
	return true


func _draw_full_map_backdrop() -> void:
	var full_rect := Rect2(Vector2.ZERO, size)
	draw_rect(full_rect, FRAME_BG, true)
	draw_rect(full_rect.grow(-3.0), FRAME_COLOR, false, 2.0)
	draw_rect(full_rect.grow(-10.0), Color(0.12, 0.46, 0.62, 0.6), false, 1.0)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(0.0, 26.0),
		"已探索楼层图 / %s" % _floor_label(),
		HORIZONTAL_ALIGNMENT_CENTER,
		size.x,
		14,
		Color(0.48, 0.94, 1.0, 0.84)
	)


# ---------------------------------------------------------------------------
# 走廊：房门中心 ↔ 邻房门中心，一根细线
# ---------------------------------------------------------------------------

func _draw_corridors() -> void:
	for record in _records:
		var room_id := str(record.get("id", ""))
		if not _revealed.has(room_id):
			continue
		var room_pos := record.get("position", Vector3.ZERO) as Vector3
		if not _is_current_floor_y(room_pos.y):
			continue
		var rect_world := _room_world_rect(room_pos, _dimensions_by_id.get(room_id, Vector2(20.0, 18.0)))
		var door_targets: Dictionary = record.get("door_targets", {})
		# 避免重复画（只画 id 字典序小的 → 大的）。
		for side in door_targets.keys():
			var neighbor_id := str(door_targets[side])
			if neighbor_id.is_empty() or room_id >= neighbor_id:
				continue
			if not _revealed.has(neighbor_id):
				continue
			var neighbor_pos := _position_by_id.get(neighbor_id, Vector3.ZERO) as Vector3
			if not _is_current_floor_y(neighbor_pos.y):
				continue
			var opened := _is_door_opened(room_id, str(side))
			var other_side := _opposite_side(str(side))
			if opened and not _is_door_opened(neighbor_id, other_side):
				opened = false
			var neighbor_rect := _room_world_rect(
				neighbor_pos, _dimensions_by_id.get(neighbor_id, Vector2(20.0, 18.0))
			)
			var p0 := _to_map(_door_world_point(room_pos, rect_world, str(side)))
			var p1 := _to_map(_door_world_point(neighbor_pos, neighbor_rect, other_side))
			if not _segment_hits_map(p0) and not _segment_hits_map(p1):
				continue
			draw_line(p0, p1, LOCKED_DOOR_COLOR if not opened else CORRIDOR_COLOR,
				CORRIDOR_PX, true)


# ---------------------------------------------------------------------------
# 房间：填充 + 一周描边（门洞处断开）+ 门两侧短角标
# ---------------------------------------------------------------------------

func _draw_rooms() -> void:
	for record in _records:
		var room_id := str(record.get("id", ""))
		if not _revealed.has(room_id):
			continue
		var room_pos := record.get("position", Vector3.ZERO) as Vector3
		if not _is_current_floor_y(room_pos.y):
			continue
		_draw_room_tile(record, room_id)


func _draw_room_tile(record: Dictionary, room_id: String) -> void:
	var rect := _room_screen_rect_by_record(record)
	if rect.size.x < 2.0 or rect.size.y < 2.0:
		return
	var is_current := room_id == _current_room_id
	var edge_color := ROOM_EDGE_CURRENT if is_current else ROOM_EDGE

	draw_rect(rect, ROOM_FILL, true)

	var doors: Array = record.get("doors", [])
	var door_set := {}
	for d in doors:
		door_set[str(d)] = true

	# 北 / 南（沿 x 轴的两条边）
	for side in ["north", "south"]:
		var y := rect.position.y if side == "north" else rect.end.y - WALL_PX
		if not door_set.has(side):
			draw_rect(Rect2(rect.position.x, y, rect.size.x, WALL_PX), edge_color, true)
			continue
		var mid_x := rect.position.x + rect.size.x * 0.5
		var gap := minf(DOOR_GAP_PX, rect.size.x * 0.6)
		var left_end := mid_x - gap * 0.5
		var right_start := mid_x + gap * 0.5
		if left_end - rect.position.x > 0.0:
			draw_rect(Rect2(rect.position.x, y, left_end - rect.position.x, WALL_PX), edge_color, true)
		if rect.end.x - right_start > 0.0:
			draw_rect(Rect2(right_start, y, rect.end.x - right_start, WALL_PX), edge_color, true)
		# 门角标：缺口两侧各一条向内短线
		var tick_y := y + WALL_PX if side == "north" else y - DOOR_TICK_PX
		draw_rect(Rect2(left_end, tick_y, WALL_PX, DOOR_TICK_PX), edge_color, true)
		draw_rect(Rect2(right_start - WALL_PX, tick_y, WALL_PX, DOOR_TICK_PX), edge_color, true)

	# 西 / 东（沿 y 轴的两条边）
	for side in ["west", "east"]:
		var x := rect.position.x if side == "west" else rect.end.x - WALL_PX
		if not door_set.has(side):
			draw_rect(Rect2(x, rect.position.y, WALL_PX, rect.size.y), edge_color, true)
			continue
		var mid_y := rect.position.y + rect.size.y * 0.5
		var gap := minf(DOOR_GAP_PX, rect.size.y * 0.6)
		var top_end := mid_y - gap * 0.5
		var bottom_start := mid_y + gap * 0.5
		if top_end - rect.position.y > 0.0:
			draw_rect(Rect2(x, rect.position.y, WALL_PX, top_end - rect.position.y), edge_color, true)
		if rect.end.y - bottom_start > 0.0:
			draw_rect(Rect2(x, bottom_start, WALL_PX, rect.end.y - bottom_start), edge_color, true)
		var tick_x := x + WALL_PX if side == "west" else x - DOOR_TICK_PX
		draw_rect(Rect2(tick_x, top_end, DOOR_TICK_PX, WALL_PX), edge_color, true)
		draw_rect(Rect2(tick_x, bottom_start - WALL_PX, DOOR_TICK_PX, WALL_PX), edge_color, true)

	# 已清理：绿色弹夹标记（原作"已清 + 可传送"的那个图形）
	if _cleared.has(room_id):
		var mark := Rect2(
			rect.position.x + rect.size.x * 0.5 - 1.5,
			rect.end.y - DOOR_TICK_PX - 7.0,
			3.0, 6.0
		)
		if mark.position.y > rect.position.y + 3.0:
			draw_rect(mark, CLEARED_MARK, true)


# ---------------------------------------------------------------------------
# 房型图标 —— 信息层照原作：底下一律同色，房型靠图标区分
# ---------------------------------------------------------------------------

func _draw_room_icons() -> void:
	for record in _records:
		var room_id := str(record.get("id", ""))
		if not _revealed.has(room_id):
			continue
		var room_pos := record.get("position", Vector3.ZERO) as Vector3
		if not _is_current_floor_y(room_pos.y):
			continue
		# —— 房型 → 图标 ——
		var kind := _icon_kind_for_type(get_visible_room_type(room_id))
		if kind.is_empty():
			continue
		var rect := _room_screen_rect_by_record(record)
		if rect.size.x < ICON_PX + 4.0 or rect.size.y < ICON_PX + 4.0:
			continue
		var center := rect.get_center()
		# 有清理标记时把图标往上抬，别和绿色弹夹叠在一起
		if _cleared.has(room_id):
			center.y -= 3.0
		_draw_icon(kind, center)


func _icon_kind_for_type(type_id: String) -> String:
	match type_id:
		"BOSS": return "boss"
		"ELITE": return "elite"
		"STORAGE", "SCAVENGE", "TREASURE": return "chest"
		"SHOP", "MERCHANT": return "shop"
		"EVENT": return "event"
		"UPGRADE": return "upgrade"
		"TRAP": return "trap"
		"EXTRACTION": return "extract"
		"STAIRS_UP", "STAIRS_DOWN", "STAIR_LOBBY", "BASEMENT", "ELEVATOR": return "stairs"
		"SAFE", "START", "ENTRANCE": return "start"
		_: return ""


func _draw_icon(kind: String, c: Vector2) -> void:
	var h := ICON_PX * 0.5
	match kind:
		"chest":
			draw_rect(Rect2(c.x - h, c.y - h * 0.8, ICON_PX, ICON_PX * 0.8), ICON_CHEST, true)
			draw_rect(Rect2(c.x - h, c.y - h * 0.2, ICON_PX, ICON_PX * 0.6), ICON_CHEST.darkened(0.35), true)
			draw_rect(Rect2(c.x - 1.0, c.y - h * 0.5, 2.0, ICON_PX * 0.7), ICON_CHEST.lightened(0.4), true)
		"boss":
			draw_circle(c, h, ICON_BOSS)
			draw_circle(c + Vector2(-2.2, -1.0), 1.5, Color(0.1, 0.06, 0.02))
			draw_circle(c + Vector2(2.2, -1.0), 1.5, Color(0.1, 0.06, 0.02))
			draw_rect(Rect2(c.x - 1.0, c.y + 1.5, 2.0, 2.5), Color(0.1, 0.06, 0.02), true)
		"elite":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.0, -h), c + Vector2(h, 0.0),
				c + Vector2(0.0, h), c + Vector2(-h, 0.0),
			]), ICON_DANGER)
		"shop":
			# 原作的商店图标是"光头商人的脸"。我们画一个柜台 + 招牌的形状，
			# 但避免"圆 + 竖线"那种会被读成字母 i 的组合。
			draw_rect(Rect2(c.x - h, c.y + h * 0.15, ICON_PX, ICON_PX * 0.35), ICON_SHOP.darkened(0.35), true)
			draw_rect(Rect2(c.x - h * 0.75, c.y - h * 0.85, ICON_PX * 0.75, ICON_PX * 0.55), ICON_SHOP, true)
			draw_rect(Rect2(c.x - h * 0.35, c.y - h * 0.65, 3.0, 3.0), ICON_SHOP.darkened(0.55), true)
		"event":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.0, -h), c + Vector2(h, h * 0.6), c + Vector2(-h, h * 0.6),
			]), ICON_EVENT)
			draw_rect(Rect2(c.x - 1.0, c.y + 1.0, 2.0, h * 0.5), ICON_EVENT.lightened(0.3), true)
		"upgrade":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.0, -h), c + Vector2(h, 0.0), c + Vector2(0.0, h),
			]), ICON_KEY)
		"trap":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-h, h), c + Vector2(h, h), c + Vector2(0.0, -h),
			]), ICON_DANGER)
		"extract":
			draw_rect(Rect2(c.x - h * 0.7, c.y - h, ICON_PX * 0.7, ICON_PX), ICON_EXTRACT, true)
			draw_rect(Rect2(c.x + h * 0.1, c.y - h * 0.2, 2.0, 2.0), Color(0.04, 0.14, 0.10), true)
		"stairs":
			draw_rect(Rect2(c.x - h, c.y + h * 0.2, ICON_PX, 2.0), ICON_STAIRS, true)
			draw_rect(Rect2(c.x - h * 0.4, c.y - h * 0.2, ICON_PX * 0.8, 2.0), ICON_STAIRS, true)
			draw_rect(Rect2(c.x - 1.0, c.y - h, 2.0, ICON_PX * 0.7), ICON_STAIRS, true)
		"start":
			draw_arc(c, h * 0.9, 0.0, TAU, 16, Color(0.56, 0.85, 1.0), 2.0, true)
			draw_circle(c, h * 0.3, Color(0.56, 0.85, 1.0))


# ---------------------------------------------------------------------------
# 未探索标记：已侦测但没进过的房间 —— 只给问号，不给轮廓
# ---------------------------------------------------------------------------

func _draw_unexplored_marks() -> void:
	for record in _records:
		var room_id := str(record.get("id", ""))
		if _revealed.has(room_id):
			continue
		var room_pos := record.get("position", Vector3.ZERO) as Vector3
		if not _is_current_floor_y(room_pos.y):
			continue
		# 只有"贴着已探索房间"的未知房才画问号 —— 远处的未知不提前暴露
		var exposed := false
		var door_targets: Dictionary = record.get("door_targets", {})
		for side in door_targets.keys():
			if _revealed.has(str(door_targets[side])):
				exposed = true
				break
		if not exposed:
			for other in _records:
				var other_id := str(other.get("id", ""))
				if not _revealed.has(other_id):
					continue
				var other_targets: Dictionary = other.get("door_targets", {})
				for side in other_targets.keys():
					if str(other_targets[side]) == room_id:
						exposed = true
						break
				if exposed:
					break
		if not exposed:
			continue
		var rect := _room_screen_rect_by_record(record)
		if not _rect_hits_map(rect):
			continue
		if _hidden_room_types.has(room_id):
			continue
		_draw_question_mark(rect.get_center())


func _draw_question_mark(c: Vector2) -> void:
	# 用 5×7 像素点阵画问号 —— 直接 draw_rect 拼几何形状在 3px 大小下会糊成散点，
	# 原作就是一张 5~7px 的像素图标，照抄点阵反而更清楚。
	const PATTERN := [
		"01110",
		"10001",
		"00001",
		"00110",
		"00100",
		"00000",
		"00100",
	]
	var px := 1.4
	var w := 5 * px
	var h := 7 * px
	var origin := c - Vector2(w * 0.5, h * 0.5)
	for row in range(PATTERN.size()):
		var line: String = PATTERN[row]
		for col in range(line.length()):
			if line[col] != "1":
				continue
			draw_rect(Rect2(origin + Vector2(col * px, row * px), Vector2(px, px)), UNEXPLORED_COLOR, true)


# ---------------------------------------------------------------------------
# 玩家 / 敌人
# ---------------------------------------------------------------------------

func _draw_player() -> void:
	if not _has_realtime_player_state:
		return
	var center := _to_map(Vector2(_player_world_position.x, _player_world_position.z))
	if not _point_hits_map(center):
		return
	var heading := Vector2(_player_aim_direction.x, _player_aim_direction.z)
	if heading.length_squared() <= 0.0001:
		heading = Vector2.UP
	heading = heading.normalized()
	var perpendicular := Vector2(-heading.y, heading.x)
	var points := PackedVector2Array([
		center + heading * 7.0,
		center - heading * 4.0 + perpendicular * 3.4,
		center - heading * 4.0 - perpendicular * 3.4,
	])
	draw_colored_polygon(points, PLAYER_FILL)
	draw_polyline(
		PackedVector2Array([points[0], points[1], points[2], points[0]]),
		PLAYER_EDGE, 1.4
	)


func _draw_enemies() -> void:
	if _enemy_world_positions.is_empty():
		return
	for world_position in _enemy_world_positions:
		if not _is_current_floor_y(world_position.y):
			continue
		var center := _to_map(Vector2(world_position.x, world_position.z))
		if not _point_hits_map(center):
			continue
		draw_circle(center, 4.2, ENEMY_HALO)
		draw_circle(center, 2.2, ENEMY_COLOR)


func _draw_floor_stack() -> void:
	var x := size.x - 8.0
	var top := CORNER_MARGIN.y + 6.0
	var bottom := size.y - 12.0
	if bottom <= top:
		return
	draw_line(Vector2(x, top), Vector2(x, bottom), Color(0.20, 0.72, 0.82, 0.34), 1.0)
	for index in range(_floor_heights.size()):
		var ratio := (
			0.5
			if _floor_heights.size() <= 1
			else float(index) / float(_floor_heights.size() - 1)
		)
		var point := Vector2(x, lerpf(top, bottom, ratio))
		var active := is_equal_approx(_floor_heights[index], snappedf(_current_floor_y, 0.01))
		draw_circle(point, 3.0 if active else 1.8,
			Color(1.0, 0.78, 0.30) if active else Color(0.30, 0.72, 0.88, 0.55))


func _draw_full_map_labels() -> void:
	if not _full_map_mode:
		return
	var font := ThemeDB.fallback_font
	for record in _records:
		var room_id := str(record.get("id", ""))
		if not _revealed.has(room_id):
			continue
		var room_pos := record.get("position", Vector3.ZERO) as Vector3
		if not _is_current_floor_y(room_pos.y):
			continue
		var visible_type := get_visible_room_type(room_id)
		if visible_type.is_empty():
			continue
		var rect := _room_screen_rect_by_record(record)
		draw_string(font, rect.get_center() + Vector2(-40.0, rect.size.y * 0.5 + 14.0),
			visible_type, HORIZONTAL_ALIGNMENT_CENTER, 80.0, 11, ROOM_EDGE)


# ---------------------------------------------------------------------------
# 坐标 / 几何 —— 固定缩放，右上锚定
# ---------------------------------------------------------------------------

func _room_world_rect(room_pos: Vector3, dimensions: Vector2) -> Rect2:
	var half := dimensions * 0.5
	return Rect2(Vector2(room_pos.x - half.x, room_pos.z - half.y), dimensions)


func _room_dimensions(record: Dictionary) -> Vector2:
	var custom := record.get("custom_dimensions", Vector2.ZERO) as Vector2
	if custom.x > 0.0 and custom.y > 0.0:
		return custom
	return DungeonRoom3D.ROOM_DIMENSIONS.get(
		str(record.get("size", "medium")), DungeonRoom3D.ROOM_DIMENSIONS["medium"]
	) as Vector2


func _floor_bounds_world() -> Rect2:
	# 当层**全部**房间（含未探索）的真实 AABB。
	# 用全量而非"已探索"是刻意的：这样探索过程中地图不移动、不重新缩放，
	# 只有房间逐间点亮 —— 与原作"固定版图"的观感一致。
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	var any := false
	for record in _records:
		var position := record.get("position", Vector3.ZERO) as Vector3
		if not _is_current_floor_y(position.y):
			continue
		any = true
		var rect := _room_world_rect(position, _room_dimensions(record))
		min_pos.x = minf(min_pos.x, rect.position.x)
		min_pos.y = minf(min_pos.y, rect.position.y)
		max_pos.x = maxf(max_pos.x, rect.end.x)
		max_pos.y = maxf(max_pos.y, rect.end.y)
	if not any:
		return Rect2(Vector2(-1.0, -1.0), Vector2(2.0, 2.0))
	return Rect2(min_pos, max_pos - min_pos)


func _content_map_rect() -> Rect2:
	if _full_map_mode:
		return Rect2(
			Vector2(56.0, 64.0),
			Vector2(maxf(1.0, size.x - 112.0), maxf(1.0, size.y - 116.0))
		)
	# 角落态：内容区就是控件本身（背衬以内）
	return Rect2(CORNER_MARGIN, Vector2(
		maxf(1.0, size.x - CORNER_MARGIN.x - 6.0),
		maxf(1.0, size.y - CORNER_MARGIN.y - 6.0)
	))


func _map_scale() -> float:
	var bounds := _floor_bounds_world()
	var content := _content_map_rect()
	if _full_map_mode:
		var sx := content.size.x / maxf(0.001, bounds.size.x)
		var sy := content.size.y / maxf(0.001, bounds.size.y)
		return maxf(0.4, minf(sx, sy) * 0.94)
	# 角落态：先取设计密度，再按**面板实际可用尺寸**夹一次。
	# 不能写死像素上限 —— 面板经 HUD_UI_SCALE(0.80) 之后只有 366×277，
	# 写死 430 会让满层直接溢出到面板外（2026-10-28 实测发现并修掉）。
	var scale_px := ROOM_PX_PER_M
	if bounds.size.x > 0.001:
		scale_px = minf(scale_px, content.size.x / bounds.size.x)
	if bounds.size.y > 0.001:
		scale_px = minf(scale_px, content.size.y / bounds.size.y)
	return maxf(0.6, scale_px)


func _to_map(world_xz: Vector2) -> Vector2:
	var bounds := _floor_bounds_world()
	var s := _map_scale()
	if _full_map_mode:
		var content := _content_map_rect()
		var used := bounds.size * s
		var origin := content.position + (content.size - used) * 0.5
		return origin + (world_xz - bounds.position) * s
	# 右上锚定：地图块的右上角贴住控件右上角，向左下生长 —— 与原作一致。
	# 贴顶是对的：原作小地图就是"贴着屏幕上沿的一团"，纵向居中反而会在上下
	# 各留一条黑带（2026-10-28 出图对比过两种，贴顶更像原作）。
	var origin := Vector2(
		size.x - CORNER_MARGIN.x - bounds.size.x * s,
		CORNER_MARGIN.y
	)
	return origin + (world_xz - bounds.position) * s


func _room_screen_rect_by_record(record: Dictionary) -> Rect2:
	var position := record.get("position", Vector3.ZERO) as Vector3
	var rect_world := _room_world_rect(position, _room_dimensions(record))
	var top_left := _to_map(rect_world.position)
	var s := _map_scale()
	return Rect2(top_left, rect_world.size * s)


func _point_hits_map(point: Vector2) -> bool:
	return _content_map_rect().grow(ICON_PX).has_point(point)


func _rect_hits_map(rect: Rect2) -> bool:
	return _content_map_rect().intersects(rect)


func _segment_hits_map(point: Vector2) -> bool:
	return _content_map_rect().grow(6.0).has_point(point)


func _door_world_point(room_pos: Vector3, rect_world: Rect2, side: String) -> Vector2:
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
# 杂项
# ---------------------------------------------------------------------------

func _is_current_floor_y(value: float) -> bool:
	if absf(value - _current_floor_y) <= FLOOR_EPSILON_M:
		return true
	return _is_vertical_channel_y(value)


func _is_vertical_channel_y(value: float) -> bool:
	if absf(value - _current_floor_y) > VERTICAL_CHANNEL_EPSILON_M:
		return false
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
		return "%dF" % int(round(100.0 + _current_floor_y / TOWER_GEOMETRY.FLOOR_HEIGHT_M))
	return "LIVE"


func _edge_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


# ---------------------------------------------------------------------------
# 对外查询（探针与存档用，语义随渲染一起改）
# ---------------------------------------------------------------------------

func get_room_screen_rect(room_id: String) -> Rect2:
	if not _record_by_id.has(room_id):
		return Rect2()
	var record := _record_by_id[room_id] as Dictionary
	var world_position := record.get("position", Vector3.ZERO) as Vector3
	if not _is_current_floor_y(world_position.y):
		return Rect2()
	return _room_screen_rect_by_record(record)


func get_player_screen_position() -> Vector2:
	return _to_map(Vector2(_player_world_position.x, _player_world_position.z))


func get_floor_label() -> String:
	return _floor_label()
