class_name StairsInteraction
extends Area2D
## 楼梯/电梯交互组件 — 挂在楼梯口或电梯节点上
## 玩家按E键交互，触发垂直楼层切换

## 信号
signal vertical_transition_requested(from_level: int, to_level: int, direction: String)
signal interaction_available(available: bool)

## 方向标记常量
const DIR_DOWN := "down"
const DIR_UP := "up"
const DIR_BOTH := "both"

## 配置
@export var direction: String = DIR_DOWN  # "down" | "up" | "both"
@export var target_vertical: int = -1  # 目标 VerticalLevel (enum值)
@export var interaction_radius: float = 80.0

## 状态
var _player_in_range: bool = false
var _interact_label: Label = null
var _transition_cooldown: bool = false


func _ready() -> void:
	_setup_interaction_label()
	_setup_collision()
	interaction_available.emit(false)


func _setup_interaction_label() -> void:
	_interact_label = get_node_or_null("InteractLabel") as Label
	if _interact_label == null:
		_interact_label = get_node_or_null("../InteractLabel") as Label
	if _interact_label != null:
		_interact_label.z_index = 100
		_interact_label.modulate = Color(1, 0.9, 0.5, 0)


func _setup_collision() -> void:
	var shape := CollisionShape2D.new()
	shape.name = "InteractionShape"
	var circle := CircleShape2D.new()
	circle.radius = interaction_radius
	shape.shape = circle
	add_child(shape)
	
	# 连接区域检测
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	if _player_in_range and _interact_label != null:
		var prompt: String = _get_interaction_prompt()
		_interact_label.text = prompt
		_interact_label.modulate = Color(1, 0.9, 0.5, 1)


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("is_player") or body.is_in_group("player"):
		_player_in_range = true
		interaction_available.emit(true)


func _on_body_exited(body: Node2D) -> void:
	if body.has_method("is_player") or body.is_in_group("player"):
		_player_in_range = false
		interaction_available.emit(false)
		if _interact_label != null:
			_interact_label.modulate = Color(1, 0.9, 0.5, 0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _player_in_range and not _transition_cooldown:
		_trigger_vertical_transition()


func _trigger_vertical_transition() -> void:
	_transition_cooldown = true
	
	# 发送垂直切换信号
	vertical_transition_requested.emit(
		0,  # from_level (由 RoomGameMode 提供)
		target_vertical,
		direction
	)
	
	# 2秒冷却（防止重复触发）
	await get_tree().create_timer(2.0).timeout
	_transition_cooldown = false


func _get_interaction_prompt() -> String:
	match direction:
		"down":
			return "[E] 下地下室"
		"up":
			return "[E] 上二楼"
		"both":
			return "[E] 乘电梯"
		_:
			return "[E] 交互"


func set_direction(dir: String) -> void:
	direction = dir


func set_target_vertical(level: int) -> void:
	target_vertical = level