class_name RoomDoorInteraction
extends Area2D
## 房间门交互区域：玩家靠近后按 E 开门；门开后玩家直接走过物理门洞。

var _game_mode: Node = null
var _from_id: int = -1
var _to_id: int = -1
var _direction: Vector2 = Vector2.ZERO
var _door_type: String = "normal"
var _is_open := false
var _player_in_range := false
var _label: Label = null
var _plate: ColorRect = null

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_visuals()
	_refresh_visuals()

func setup(game_mode: Node, from_id: int, to_id: int, direction: Vector2, door_type: String, is_open: bool) -> void:
	_game_mode = game_mode
	_from_id = from_id
	_to_id = to_id
	_direction = direction
	_door_type = door_type
	_is_open = is_open
	_refresh_visuals()

func set_open(value: bool) -> void:
	_is_open = value
	_refresh_visuals()

func get_target_room_id() -> int:
	return _to_id

func _build_visuals() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(96, 76)
	shape.shape = rect
	add_child(shape)

	_plate = ColorRect.new()
	_plate.name = "DoorPlate"
	_plate.size = Vector2(82, 18)
	_plate.position = Vector2(-41, -9)
	_plate.z_index = 170
	add_child(_plate)

	_label = Label.new()
	_label.name = "DoorLabel"
	_label.position = Vector2(-76, -48)
	_label.size = Vector2(152, 38)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 12)
	_label.z_index = 171
	_label.visible = false
	add_child(_label)

func _refresh_visuals() -> void:
	if _plate == null or _label == null:
		return
	var color := Color(0.20, 0.72, 0.42, 0.82) if _is_open else Color(0.95, 0.68, 0.20, 0.82)
	if _door_type == "boss":
		color = Color(0.85, 0.12, 0.10, 0.86) if _is_open else Color(0.55, 0.18, 0.12, 0.78)
	elif _door_type == "extraction":
		color = Color(0.15, 0.58, 0.95, 0.86) if _is_open else Color(0.20, 0.38, 0.70, 0.78)
	_plate.color = color
	_label.text = "已打开" if _is_open else "[E] 用钥匙开门"
	_plate.visible = not _is_open

func _process(_delta: float) -> void:
	if _player_in_range and Input.is_action_just_pressed("interact"):
		if _game_mode != null and _game_mode.has_method("try_open_room_door"):
			_game_mode.call("try_open_room_door", _to_id)
		elif _game_mode != null and _game_mode.has_method("try_enter_room_via_door"):
			_game_mode.call("try_enter_room_via_door", _to_id)

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = true
	if _label:
		_label.visible = true

func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = false
	if _label:
		_label.visible = false
