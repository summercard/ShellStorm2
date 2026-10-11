class_name RooftopExpeditionEntrance3D
extends Node3D
## 交互控制器负责 E/手柄；门前圆点另支持鼠标点击。
var _dialog: ConfirmationDialog
var _player: Player3D
var _previous_lock := false
var _departing := false

func _ready() -> void:
	add_to_group(PlayerInteractionController3D.PROVIDER_GROUP)
	_dialog = ConfirmationDialog.new()
	_dialog.title = "远征关卡01"
	_dialog.dialog_text = "是否进入远征关卡01？"
	_dialog.ok_button_text = "是"
	_dialog.cancel_button_text = "否"
	_dialog.confirmed.connect(_confirm)
	_dialog.canceled.connect(_cancel)
	add_child(_dialog)

func _tower() -> TowerDescent3D:
	var node := get_parent()
	while node != null:
		if node is TowerDescent3D:
			return node
		node = node.get_parent()
	return null

func get_interaction_candidate(player: Player3D) -> Dictionary:
	if _departing or _dialog.visible or player == null or player.input_locked:
		return {}
	if absf(player.global_position.y - global_position.y) > 1.5 or Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length() > 3.2:
		return {}
	return {"available": true, "interaction_id": "tower03_expedition01", "position": global_position,
		"priority": 85, "prompt": "进入远征关卡01", "dot_anchor": global_position + Vector3.UP * 1.7}

func get_interaction_dot_anchor() -> Vector3:
	return global_position + Vector3.UP * 1.7

func perform_interaction(player: Player3D, _candidate: Dictionary) -> bool:
	if get_interaction_candidate(player).is_empty():
		return false
	_player = player
	_previous_lock = player.input_locked
	player.set_input_locked(true)
	_dialog.popup_centered(Vector2i(420, 160))
	return true

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var tower := _tower()
	var camera := get_viewport().get_camera_3d()
	if tower == null or camera == null or get_interaction_candidate(tower.player).is_empty():
		return
	var plane := Plane(Vector3.BACK, global_position.z - 0.65)
	var hit: Variant = plane.intersects_ray(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
	if hit == null or absf(hit.x - global_position.x) > 1.3 or hit.y < global_position.y or hit.y > global_position.y + 3.4:
		return
	get_viewport().set_input_as_handled()
	perform_interaction(tower.player, {})

func _cancel() -> void:
	if is_instance_valid(_player):
		_player.set_input_locked(_previous_lock)

func _confirm() -> void:
	if _departing:
		return
	var tower := _tower()
	if tower == null or not GameDesignConfig.select_expedition_level("expedition_01"):
		_cancel()
		return
	_departing = true
	var ticket := ExpeditionDepartureService.prepare(tower, ExpeditionEntryContext.TOWER03)
	if not bool(ticket.get("success", false)):
		_failed(str(ticket.get("message", "出发失败")))
		return
	var request_id := GameEntryFlow.request_gameplay_entry(GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT)
	if DisplayServer.get_name() != "headless" and IrisTransition != null:
		await IrisTransition.iris_close(IrisTransition.CLOSE_SECONDS)
	var error := get_tree().change_scene_to_file("res://scenes/ExpeditionLoadingScreen.tscn")
	if error != OK:
		GameEntryFlow.cancel_request(request_id)
		ExpeditionDepartureService.rollback(ticket)
		_failed("读取界面加载失败，请重试")

func _failed(message: String) -> void:
	if IrisTransition != null:
		IrisTransition.clear_now()
	_departing = false
	GameDesignConfig.pending_expedition_level_id = ""
	_cancel()
	var tower := _tower()
	if tower != null:
		tower.status_label.text = message
