class_name RoomDoorVisualizer
extends Node2D
## 房间门过渡视觉化 — 在房间边缘标记已开启的门的位置
## 显示方向提示（告诉玩家哪个边缘有通路）
## 由 RoomGameMode 在进入房间时通过 configure() 注入连接方向

## 门标记预设（4个边缘方向：上/下/左/右）
## 每组两个标记（表示这个方向有通路）
## 颜色：绿色=普通通路，红色=Boss通路，蓝色=撤离通路

const MARKER_SIZE := Vector2(48, 16)
const MARKER_OFFSET := 28.0  # 距边缘的距离

const DOOR_COLORS := {
	"normal": Color(0.2, 0.55, 0.2, 0.6),
	"boss": Color(0.6, 0.05, 0.05, 0.7),
	"extraction": Color(0.15, 0.40, 0.70, 0.6),
}

## 光效颜色（解锁/可通行时更亮）
const GLOW_COLORS := {
	"normal": Color(0.25, 0.75, 0.25, 0.85),
	"boss": Color(0.75, 0.08, 0.08, 0.9),
	"extraction": Color(0.18, 0.50, 0.85, 0.80),
}

## 门状态
enum DoorState { INACTIVE, ACTIVE, UNLOCKED }

var _door_markers: Array[ColorRect] = []
var _door_states: Array[DoorState] = []
var _configured: bool = false
var _pulse_timer: float = 0.0
var _any_unlocked: bool = false

## 配置门方向（由 RoomVisualizer 或 RoomGameMode 调用）
## directions: Array[Dictionary]，每项包含 from_id, to_id, door_type, direction_vector
func configure(directions: Array[Dictionary]) -> void:
	if _configured:
		_reset()
	_configured = true
	
	for dir_info in directions:
		var dir_vec: Vector2 = dir_info.get("direction", Vector2.ZERO)
		var door_type: String = dir_info.get("door_type", "normal")
		_add_door_marker(dir_vec, door_type)


## 更新单个门的状态（由 RoomGameMode 清怪后调用）
## idx: 门索引（0开始）
## state: DoorState.INACTIVE / ACTIVE / UNLOCKED
func set_door_state(idx: int, state: DoorState) -> void:
	if idx < 0 or idx >= _door_markers.size():
		return
	_door_states[idx] = state
	_update_door_visual(idx)


## 将所有门设为已解锁（房间清理完成后由 RoomGameMode 调用）
func set_all_doors_unlocked() -> void:
	_any_unlocked = true
	for i in _door_states.size():
		if _door_states[i] < DoorState.UNLOCKED:
			_door_states[i] = DoorState.UNLOCKED
	for i in _door_markers.size():
		_update_door_visual(i)


## 脉冲动画（只在有解锁门时运行）
func _process(delta: float) -> void:
	if _door_markers.is_empty() or not _any_unlocked:
		return
	_pulse_timer += delta
	var pulse: float = (sin(_pulse_timer * 2.5) * 0.5 + 0.5)  # 0~1
	for i in _door_markers.size():
		if _door_states[i] == DoorState.UNLOCKED:
			_apply_pulse(i, pulse)


## 应用脉冲效果到已解锁的门
func _apply_pulse(idx: int, t: float) -> void:
	var marker: ColorRect = _door_markers[idx]
	# 基础 alpha + 0.15 脉冲幅度
	var base_alpha: float = marker.color.a
	var pulsed: float = base_alpha + t * 0.20
	marker.color.a = clampf(pulsed, 0.3, 1.0)


## 更新单个门的视觉（颜色/光效）
func _update_door_visual(idx: int) -> void:
	if idx < 0 or idx >= _door_markers.size():
		return
	var marker: ColorRect = _door_markers[idx]
	var state: DoorState = _door_states[idx]
	var base_color: Color = marker.color
	
	match state:
		DoorState.UNLOCKED:
			# 解锁门：更亮，光效颜色
			var glow_c: Color = _get_glow_color_for_type(idx)
			marker.color = Color(glow_c.r, glow_c.g, glow_c.b, 0.75)
		DoorState.ACTIVE:
			# 已激活未解锁：中等亮度
			marker.color = Color(base_color.r, base_color.g, base_color.b, 0.65)
		DoorState.INACTIVE:
			# 未激活：原色
			pass


## 获取门类型对应的光效颜色
func _get_glow_color_for_type(idx: int) -> Color:
	if idx >= _door_markers.size():
		return GLOW_COLORS["normal"]
	# 从标记颜色反推门类型（按颜色匹配粗糙判断）
	var marker: ColorRect = _door_markers[idx]
	var c: Color = marker.color
	if c.b > 0.5:
		return GLOW_COLORS["extraction"]
	if c.r > 0.5:
		return GLOW_COLORS["boss"]
	return GLOW_COLORS["normal"]


## 添加单个门标记
func _add_door_marker(dir: Vector2, door_type: String) -> void:
	if dir == Vector2.ZERO:
		return
	
	var marker := ColorRect.new()
	marker.custom_minimum_size = MARKER_SIZE
	
	# 根据方向旋转标记
	var color: Color = _get_door_color(door_type)
	
	# 8方向映射到4方向（简化处理）
	var normalized_dir: Vector2 = _normalize_direction(dir)
	
	match normalized_dir:
		Vector2.UP:
			marker.size = Vector2(MARKER_SIZE.x, MARKER_SIZE.y)
			marker.position = Vector2(-MARKER_SIZE.x * 0.5, -MARKER_OFFSET - MARKER_SIZE.y)
		Vector2.DOWN:
			marker.size = Vector2(MARKER_SIZE.x, MARKER_SIZE.y)
			marker.position = Vector2(-MARKER_SIZE.x * 0.5, MARKER_OFFSET)
		Vector2.LEFT:
			marker.size = Vector2(MARKER_SIZE.y, MARKER_SIZE.x)  # 旋转90°
			marker.position = Vector2(-MARKER_OFFSET - MARKER_SIZE.y, -MARKER_SIZE.x * 0.5)
		Vector2.RIGHT:
			marker.size = Vector2(MARKER_SIZE.y, MARKER_SIZE.x)
			marker.position = Vector2(MARKER_OFFSET, -MARKER_SIZE.x * 0.5)
	
	marker.color = color
	marker.z_index = 10
	add_child(marker)
	_door_markers.append(marker)
	_door_states.append(DoorState.INACTIVE)


func _normalize_direction(dir: Vector2) -> Vector2:
	# 8方向→4方向归一化
	var ax: float = absf(dir.x)
	var ay: float = absf(dir.y)
	if ax > ay:
		return Vector2.RIGHT if dir.x > 0 else Vector2.LEFT
	else:
		return Vector2.DOWN if dir.y > 0 else Vector2.UP


func _get_door_color(door_type: String) -> Color:
	return DOOR_COLORS.get(door_type, DOOR_COLORS["normal"])


func _reset() -> void:
	for marker in _door_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_door_markers.clear()
	_door_states.clear()
	_any_unlocked = false
	_configured = false
	_pulse_timer = 0.0


func _exit_tree() -> void:
	_reset()
