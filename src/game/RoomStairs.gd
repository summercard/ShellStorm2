class_name RoomStairs
extends Node2D
## 楼梯房场景 — 垂直楼层连接点
## room_type 决定方向：STAIRS_DOWN=下楼, STAIRS_UP=上楼, ELEVATOR=双向

@onready var stairs_area: Area2D = $StairsArea
var _runtime_room_type: int = -1

func _ready() -> void:
	_configure_stairs_direction()
	# 楼梯房默认不刷怪（过渡区域）
	_set_no_spawn()

func _configure_stairs_direction() -> void:
	if stairs_area == null:
		return
	var room_type := _runtime_room_type
	# 编辑器预览仍可从 Visualizer 读取默认类型。
	var visualizer: Node = get_node_or_null("Visualizer")
	if room_type < 0 and visualizer != null and visualizer.has_method("get_room_type"):
		room_type = visualizer.get_room_type()
	var stairs_interaction: Node = stairs_area.get_child(0) if stairs_area.get_child_count() > 0 else null
	if stairs_interaction != null and stairs_interaction is StairsInteraction:
		_match_direction_to_room_type(room_type, stairs_interaction)

func configure_room_data(room_data: RoomData) -> void:
	if room_data == null:
		return
	_runtime_room_type = room_data.room_type
	_configure_stairs_direction()

func _match_direction_to_room_type(room_type: int, stairs: StairsInteraction) -> void:
	# RoomData.RoomType 枚举值
	const STAIRS_DOWN_VAL := 12  # RoomData.RoomType.STAIRS_DOWN
	const STAIRS_UP_VAL := 13    # RoomData.RoomType.STAIRS_UP
	const ELEVATOR_VAL := 14     # RoomData.RoomType.ELEVATOR
	if room_type == STAIRS_DOWN_VAL:
		stairs.direction = "down"
		stairs.target_vertical = -1  # BASEMENT
	elif room_type == STAIRS_UP_VAL:
		stairs.direction = "up"
		stairs.target_vertical = 1   # UPPER
	else:
		stairs.direction = "both"
		stairs.target_vertical = 0   # MAIN

func _set_no_spawn() -> void:
	# 楼梯房不生成怪物
	var spawner: Node = get_node_or_null("WaveSpawner")
	if spawner != null and spawner.has_method("configure"):
		spawner.configure([], self, null, 1, 0, null, Vector2.ZERO)
