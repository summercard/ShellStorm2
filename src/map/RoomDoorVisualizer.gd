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

var _door_markers: Array[ColorRect] = []
var _configured: bool = false

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
	_configured = false


func _exit_tree() -> void:
	_reset()
