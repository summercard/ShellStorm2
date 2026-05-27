class_name RoomLightSwitch
extends Area2D
## Wall-mounted switch controlling one physical room light.

signal light_toggled(is_on: bool)

const INTERACTION_RANGE := 46.0
const WALL_INSET := 34.0
const WALL_MARGIN := 116.0
const DOOR_CLEARANCE := 106.0

var _controlled_light: PointLight2D = null
var _light_on := false
var _player_in_range := false
var _prompt: Label = null


func configure(room_size: Vector2, controlled_light: PointLight2D, starts_on: bool, seed_value: int) -> void:
	_controlled_light = controlled_light
	position = _choose_wall_position(room_size, seed_value)
	_set_light_state(starts_on, false)
	_ensure_nodes()
	queue_redraw()


func is_light_on() -> bool:
	return _light_on


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	monitorable = true
	_ensure_nodes()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range and event.is_action_pressed("interact"):
		_set_light_state(not _light_on, true)
		get_viewport().set_input_as_handled()


func _ensure_nodes() -> void:
	if get_node_or_null("InteractionShape") == null:
		var shape := CollisionShape2D.new()
		shape.name = "InteractionShape"
		var circle := CircleShape2D.new()
		circle.radius = INTERACTION_RANGE
		shape.shape = circle
		add_child(shape)
	if _prompt == null or not is_instance_valid(_prompt):
		_prompt = Label.new()
		_prompt.name = "InteractLabel"
		_prompt.position = Vector2(-52.0, 20.0)
		_prompt.size = Vector2(104.0, 22.0)
		_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_prompt.text = "[E] 开灯" if not _light_on else "[E] 关灯"
		_prompt.visible = false
		_prompt.z_index = 40
		add_child(_prompt)


func _set_light_state(enabled: bool, emit_change: bool) -> void:
	_light_on = enabled
	if _controlled_light != null and is_instance_valid(_controlled_light):
		_controlled_light.enabled = enabled
	if _prompt != null:
		_prompt.text = "[E] 关灯" if enabled else "[E] 开灯"
	queue_redraw()
	if emit_change:
		light_toggled.emit(enabled)


func _choose_wall_position(room_size: Vector2, seed_value: int) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var side := rng.randi_range(0, 3)
	var half := room_size * 0.5
	if side < 2:
		var x := _random_wall_coordinate(rng, half.x)
		return Vector2(x, -half.y + WALL_INSET if side == 0 else half.y - WALL_INSET)
	var y := _random_wall_coordinate(rng, half.y)
	return Vector2(-half.x + WALL_INSET if side == 2 else half.x - WALL_INSET, y)


func _random_wall_coordinate(rng: RandomNumberGenerator, half_extent: float) -> float:
	var value := rng.randf_range(-half_extent + WALL_MARGIN, half_extent - WALL_MARGIN)
	if absf(value) < DOOR_CLEARANCE:
		value = DOOR_CLEARANCE if value >= 0.0 else -DOOR_CLEARANCE
	return value


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		if _prompt != null:
			_prompt.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		if _prompt != null:
			_prompt.visible = false


func _draw() -> void:
	draw_rect(Rect2(-13.0, -16.0, 26.0, 32.0), Color(0.12, 0.13, 0.15, 1.0), true)
	draw_rect(Rect2(-13.0, -16.0, 26.0, 32.0), Color(0.45, 0.49, 0.54, 1.0), false, 2.0)
	var indicator := Color(0.36, 0.9, 0.48, 1.0) if _light_on else Color(0.76, 0.19, 0.16, 1.0)
	draw_circle(Vector2(0.0, -7.0), 4.0, indicator)
	draw_line(Vector2(0.0, 2.0), Vector2(0.0, 10.0), Color(0.82, 0.84, 0.86, 1.0), 2.0)
