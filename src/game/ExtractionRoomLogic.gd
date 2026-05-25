class_name ExtractionRoomLogic
extends Node2D
## 撤离房逻辑：中央装置需要玩家靠近按 E，启动后交由 RoomGameMode 组织守点撤离。

signal extraction_activated

## 状态
var _activation_started: bool = false
var _controller: Node = null
var _player_in_range := false

## 引用
var _extraction_circle: ColorRect = null
var _exit_markers: Array[ColorRect] = []
var _switch_label: Label = null
var _switch_plate: ColorRect = null
var _pulse_timer: float = 0.0


func _ready() -> void:
	_setup_extraction_room()
	_build_extraction_switch()


func _process(delta: float) -> void:
	# 撤离光圈脉冲动画
	if _activation_started and _extraction_circle != null:
		_pulse_timer += delta
		var pulse: float = (sin(_pulse_timer * 2.5) * 0.5 + 0.5) * 0.15 + 0.08
		_extraction_circle.color = Color(0.10, 0.35, 0.70, pulse)
	if _player_in_range and not _activation_started and Input.is_action_just_pressed("interact"):
		_try_use_switch()


func _setup_extraction_room() -> void:
	# 查找撤离光圈
	_extraction_circle = get_node_or_null("ExtractionCircle") as ColorRect

	# 查找方向标记
	var marker_names: Array[String] = [
		"ExitMarker_N", "ExitMarker_S", "ExitMarker_W", "ExitMarker_E"
	]
	for name in marker_names:
		var marker: ColorRect = get_node_or_null(name) as ColorRect
		if marker != null:
			_exit_markers.append(marker)


func arm_switch(controller: Node) -> void:
	_controller = controller
	if _switch_label != null and not _activation_started:
		_switch_label.text = "[E] 启动撤离装置"


func _build_extraction_switch() -> void:
	var switch_area := Area2D.new()
	switch_area.name = "ExtractionSwitch"
	switch_area.collision_layer = 0
	switch_area.collision_mask = 2
	switch_area.body_entered.connect(_on_switch_body_entered)
	switch_area.body_exited.connect(_on_switch_body_exited)
	add_child(switch_area)

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 72.0
	shape.shape = circle
	switch_area.add_child(shape)

	_switch_plate = ColorRect.new()
	_switch_plate.name = "SwitchPlate"
	_switch_plate.position = Vector2(-42, -18)
	_switch_plate.size = Vector2(84, 36)
	_switch_plate.color = Color(0.12, 0.62, 0.82, 0.9)
	_switch_plate.z_index = 20
	switch_area.add_child(_switch_plate)

	_switch_label = Label.new()
	_switch_label.name = "SwitchLabel"
	_switch_label.text = "[E] 启动撤离装置"
	_switch_label.position = Vector2(-86, -54)
	_switch_label.size = Vector2(172, 24)
	_switch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_switch_label.add_theme_font_size_override("font_size", 13)
	_switch_label.add_theme_color_override("font_color", Color(0.5, 0.92, 1.0, 1.0))
	_switch_label.z_index = 21
	_switch_label.visible = false
	switch_area.add_child(_switch_label)


func _on_switch_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		if _switch_label != null and not _activation_started:
			_switch_label.visible = true


func _on_switch_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		if _switch_label != null and not _activation_started:
			_switch_label.visible = false


func _try_use_switch() -> bool:
	if _activation_started or _controller == null:
		return false
	if not _controller.has_method("request_extraction_switch_activation"):
		return false
	if not bool(_controller.call("request_extraction_switch_activation")):
		return false
	activate_extraction()
	return true


## 启动装置后的视觉状态。
func activate_extraction() -> void:
	if _activation_started:
		return
	_activation_started = true
	extraction_activated.emit()

	# 高亮撤离光圈
	if _extraction_circle != null:
		_extraction_circle.color = Color(0.10, 0.35, 0.70, 0.12)

	# 强化方向标记可见性
	for marker in _exit_markers:
		marker.color = Color(0.15, 0.60, 1.0, 0.85)

	if _switch_plate != null:
		_switch_plate.color = Color(0.15, 0.95, 0.62, 0.94)
	if _switch_label != null:
		_switch_label.text = "撤离信号发送中"
		_switch_label.visible = true

	print("[ExtractionRoomLogic] 撤离装置已启动，防守倒计时开始")


func reset_switch() -> void:
	_activation_started = false
	_pulse_timer = 0.0
	if _extraction_circle != null:
		_extraction_circle.color = Color(0.10, 0.35, 0.70, 0.08)
	if _switch_plate != null:
		_switch_plate.color = Color(0.12, 0.62, 0.82, 0.9)
	if _switch_label != null:
		_switch_label.text = "[E] 重新启动撤离装置"
		_switch_label.visible = _player_in_range


## 获取激活状态
func is_activated() -> bool:
	return _activation_started
