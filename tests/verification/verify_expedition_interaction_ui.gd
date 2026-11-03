extends Node
## Exercise real GUI hit testing in the expedition, rather than calling purchase handlers.

var _failures: Array[String] = []

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This GUI interaction verification requires a real renderer and window")
		get_tree().quit(1)
		return
	get_window().size = Vector2i(1280, 720)
	Input.use_accumulated_input = false
	call_deferred("_run")

func _run() -> void:
	var dungeon := preload("res://scenes/ExpeditionLevel03_3D.tscn").instantiate() as TowerDescent3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 2034227857
	add_child(dungeon)
	await _settle()
	GameManager.currency = 100000
	GameManager.currency_changed.emit(GameManager.currency)
	dungeon.get_inventory_module().clear_all()
	dungeon.call("_open_merchant")
	await _settle()
	var merchant := dungeon.get("_merchant_ui") as MerchantUI
	_check(merchant != null, "expedition vending did not open")
	if merchant != null:
		_check(dungeon.player.input_locked, "vending did not lock gameplay input")
		_check(merchant._menu._inventory_module == dungeon.get_inventory_module(), "vending is not bound to the live backpack")
		_check(merchant._menu._source_tabs["vault"].is_visible_in_tree() == false, "run vending exposes base vault")
		GameManager.currency = 0
		GameManager.currency_changed.emit(0)
		await _settle()
		for row in merchant._menu._buy_list.get_children():
			var buy := row.find_child("BuyButton", true, false) as Button
			_check(buy != null and buy.disabled and "金币不足" in buy.text, "unaffordable purchase lacks visible reason")
		GameManager.currency = 100000
		GameManager.currency_changed.emit(GameManager.currency)
		await _settle()
		var service := dungeon.get("_merchant_service") as RunMerchantService
		var before := service.get_offers_snapshot().size()
		var target := merchant._menu._buy_list.get_child(0)
		var button := target.find_child("BuyButton", true, false) as Button
		_check(button != null, "vending is missing the shared purchase button")
		await _click(button)
		_check(service.get_offers_snapshot().size() == before - 1, "real mouse click did not purchase expedition stock")
		_check(get_viewport().gui_get_focus_owner() != null, "vending lost gamepad focus after purchase")
		_check("购买成功" in merchant._menu._status_label.text, "purchase result not shown in vending page")
		VerificationOutput.prepare()
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(VerificationOutput.path("expedition_vending.png"))
		get_window().size = Vector2i(1920, 1080)
		await _settle()
		var close_wide := merchant.find_child("CloseButton", true, false) as Button
		_check(get_viewport().get_visible_rect().encloses(close_wide.get_global_rect()), "1920x1080 vending close button outside viewport")
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(VerificationOutput.path("expedition_vending_1920.png"))
		get_window().size = Vector2i(1280, 720)
		await _settle()
		var pad_buy := merchant._menu._buy_list.get_child(0).find_child("BuyButton", true, false) as Button
		pad_buy.grab_focus()
		await _action("ui_accept")
		_check(service.get_offers_snapshot().size() == before - 2, "focused accept did not purchase expedition stock")
		var close := merchant.find_child("CloseButton", true, false) as Button
		_check(close != null, "vending close button missing")
		if close != null:
			await _click(close)
		_check(dungeon.get("_merchant_ui") == null, "real mouse click did not close vending")
		_check(not dungeon.player.input_locked, "vending close did not restore gameplay input")
		if is_instance_valid(merchant) and merchant.visible:
			merchant.hide_merchant()
	await _settle()
	dungeon.call("_open_workbench")
	await _settle()
	var workbench := dungeon.get("_workbench_panel") as WorkbenchPanel
	_check(workbench != null, "expedition workbench did not open")
	if workbench != null:
		var controls := workbench.find_children("*", "Button", true, false)
		for value in controls:
			var control := value as Button
			if control.is_visible_in_tree() and not control.disabled:
				await _hover(control)
				_check(get_viewport().gui_get_hovered_control() == control, "workbench button blocked: %s" % control.text)
		await _click(workbench.find_child("TabButton_catalog", true, false) as Button)
		_check(workbench.get("_active_page") == WorkbenchPanel.PAGE_CATALOG, "workbench catalogue tab did not switch on click")
		await _click(workbench.find_child("TabButton_forge", true, false) as Button)
		_check(workbench.get("_active_page") == WorkbenchPanel.PAGE_FORGE, "workbench forge tab did not switch on click")
		await _action("ui_cancel")
		_check(not is_instance_valid(workbench), "ui_cancel did not close expedition workbench")
	var inventory_ui := dungeon.get("_inventory_ui") as InventoryUI
	await _action("ui_inventory")
	_check(inventory_ui.is_inventory_open(), "inventory shortcut did not open backpack")
	await _click(inventory_ui.close_button)
	_check(not inventory_ui.is_inventory_open(), "backpack close button did not respond")
	dungeon.call("_toggle_full_map")
	await _settle()
	await _click(dungeon.get("_radar_close_button") as Button)
	_check(dungeon.get("_full_map_overlay") == null, "floor map close button did not respond")
	_check(not dungeon.player.input_locked, "modal input lock remained after closing pages")
	dungeon.queue_free()
	await _settle()
	if _failures.is_empty():
		print("EXPEDITION_INTERACTION_UI_OK: shared vending, affordability, mouse/focused purchase, 720p/1080p, workbench tabs/cancel, backpack/map close and input unlock")
	else:
		for failure in _failures:
			push_error(failure)
	get_tree().quit(0 if _failures.is_empty() else 1)

func _hover(control: Control) -> void:
	if not is_instance_valid(control):
		_check(false, "missing control for GUI hover")
		return
	var motion := InputEventMouseMotion.new()
	motion.position = control.get_global_rect().get_center()
	motion.global_position = motion.position
	Input.warp_mouse(motion.position)
	Input.parse_input_event(motion)
	await get_tree().process_frame
	var hovered := get_viewport().gui_get_hovered_control()
	print("GUI_TARGET %s rect=%s hovered=%s" % [control.get_path(), control.get_global_rect(), hovered.get_path() if hovered != null else "none"])

func _click(control: Control) -> void:
	if not is_instance_valid(control):
		_check(false, "missing control for GUI click")
		return
	await _hover(control)
	var point := control.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(event)
		await get_tree().process_frame
	await _settle()

func _action(action: String) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
	await _settle()

func _settle() -> void:
	for frame in 8:
		await get_tree().process_frame

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
