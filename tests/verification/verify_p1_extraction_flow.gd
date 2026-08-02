extends Node

class FakeRoomMode:
	extends Node
	var should_start: bool = false
	var begin_calls: int = 0

	func begin_extraction(_etype: String, _countdown: float = 5.0) -> bool:
		begin_calls += 1
		return should_start

func _ready() -> void:
	var failures: Array[String] = []
	var ui_scene: PackedScene = load("res://scenes/GameUIManager.tscn") as PackedScene
	if ui_scene == null:
		_finish(["GameUIManager scene does not load"])
		return

	var ui: GameUIManager = ui_scene.instantiate() as GameUIManager
	add_child(ui)
	await get_tree().process_frame

	var module := ExtractionModule.new()
	var fake_mode := FakeRoomMode.new()
	add_child(fake_mode)
	ui.set_extraction_module(module)
	ui.set_room_game_mode(fake_mode)
	ui._on_extraction_ready()
	await get_tree().process_frame

	var extraction_panel: Control = ui.get_node("ExtractionPanel") as Control
	var countdown_bar: Control = ui.get_node("ExtractionPanel/VBox/CountdownBar") as Control
	var countdown_label: Control = ui.get_node("ExtractionPanel/VBox/CountdownLabel") as Control
	var buttons: VBoxContainer = ui.get_node("ExtractionPanel/VBox/ExtractionButtons") as VBoxContainer
	var room_info: Label = ui.get_node("GameHUD/RoomInfoLabel") as Label

	if extraction_panel == null or countdown_bar == null or countdown_label == null or buttons == null:
		_finish(["Extraction UI nodes missing"])
		return

	if not extraction_panel.visible:
		failures.append("Extraction choice panel is not visible when extraction becomes ready")
	if countdown_bar.visible or countdown_label.visible:
		failures.append("Choice panel shows countdown widgets before the player commits")
	if not _all_buttons_visible(buttons):
		failures.append("Choice panel hides extraction options before countdown starts")

	fake_mode.should_start = false
	ui._on_extraction_type_button_pressed("STANDARD")
	await get_tree().process_frame
	if fake_mode.begin_calls != 1:
		failures.append("STANDARD extraction did not ask the backend to start")
	if countdown_bar.visible or countdown_label.visible:
		failures.append("Backend refusal still shows extraction countdown")
	if not extraction_panel.visible or not _all_buttons_visible(buttons):
		failures.append("Backend refusal does not return the player to extraction choices")
	if room_info == null or not room_info.text.contains("撤离启动失败"):
		failures.append("Backend refusal does not explain the failed start to the player")

	fake_mode.should_start = true
	ui._on_extraction_type_button_pressed("STANDARD")
	await get_tree().process_frame
	if fake_mode.begin_calls != 2:
		failures.append("Second extraction attempt did not reach backend")
	if not countdown_bar.visible or not countdown_label.visible:
		failures.append("Successful extraction start does not show countdown feedback")
	if _all_buttons_visible(buttons):
		failures.append("Successful extraction start leaves choice buttons visible during countdown")

	_finish(failures)

func _all_buttons_visible(buttons: VBoxContainer) -> bool:
	for child in buttons.get_children():
		if child is Control and not child.visible:
			return false
	return buttons.get_child_count() > 0

func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("P1_EXTRACTION_FLOW_OK: extraction UI only enters countdown after backend acceptance")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
