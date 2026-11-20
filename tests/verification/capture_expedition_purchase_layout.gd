extends Node

## 实拍：正式远征拾取入口的命运卡三选一购卡界面（上半区）真实渲染截图。
##
## 口径：
##   · 场景 `ExpeditionLevel01_3D.tscn`（正式远征），固定 `run_seed_override`。
##   · 正式凭据路径（`item_fate_card_drop` 拾取物 + `perform_interaction`），
##     不走 `show_reference_fate_overlay_for_test()` 测试口。
##   · 只在**窗口模式**产出 PNG —— `--headless` 下 `frame_post_draw` 不触发；
##     必须等 `RenderingServer.frame_post_draw` 再读根视口纹理，只等 `process_frame`
##     会拿到全透明空图。
##   · 同一脚本、同一机位、同一状态序列跑「改前 / 改后」，两组图可直接叠放比对。
##
## 由 scripts/run_expedition_layout_qa.py 设置工程外输出、隔离 user:// 后窗口运行。
## 默认验证新布局与交易；仅用 --baseline 捕捉旧版对照，不签当前布局。

const DUNGEON_PATH := "res://scenes/ExpeditionLevel01_3D.tscn"
const FATE_PICKUP_PATH := "res://src/world3d/FateCardDropPickup3D.gd"
const ROOM_KEY := "room_01"
const SEED_VALUE := 515151


var _tag := "run"
var _res_label := "1280x720"
var _out_dir := ""
var _baseline := false
var _capture_failed := false
var _dungeon: Dungeon3D


func _ready() -> void:
	if OS.get_environment("SS2_UI_QA_ISOLATED") != "1" or OS.get_environment("SS2_UI_QA_OUT").is_empty():
		get_tree().quit(2)
		return
	_out_dir = OS.get_environment("SS2_UI_QA_OUT")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--tag="):
			_tag = argument.trim_prefix("--tag=")
		elif argument.begins_with("--res="):
			_res_label = argument.trim_prefix("--res=")
		elif argument == "--baseline":
			_baseline = true
	DirAccess.make_dir_recursive_absolute(_out_dir)
	call_deferred("run")


func run() -> void:
	_dungeon = (load(DUNGEON_PATH) as PackedScene).instantiate() as Dungeon3D
	_dungeon.test_mode = true
	_dungeon.run_seed_override = SEED_VALUE
	add_child(_dungeon)
	for _frame in 12:
		await get_tree().process_frame
	if _dungeon.player == null:
		print("CAPTURE_FATE_PURCHASE_UI_FAIL player_missing")
		get_tree().quit(1)
		return
	var rooms := _dungeon.get("_room_by_id") as Dictionary
	var room := rooms.get(ROOM_KEY) as DungeonRoom3D
	if room == null:
		print("CAPTURE_FATE_PURCHASE_UI_FAIL room_missing")
		get_tree().quit(1)
		return
	_dungeon.player.global_position = room.global_position + Vector3.UP * 0.1
	_dungeon.force_enter_room_for_test(ROOM_KEY)
	for _frame in 4:
		await get_tree().process_frame

	# 钱包给一个两卡可买、一卡不够的额度，让「可买 / 余额不足」同屏可读。
	GameManager.currency = 85
	if not await _open_formal_offer(room, "capture:ui"):
		print("CAPTURE_FATE_PURCHASE_UI_FAIL offer_not_opened")
		get_tree().quit(1)
		return
	# 进场翻转 / 漂浮稳定：截图要的是落定后的一帧。
	await get_tree().create_timer(1.4).timeout
	_dungeon.call("_refresh_door_fate_prices")
	_clear_focus_and_pointer()
	for _frame in 20:
		await get_tree().process_frame

	# ① 默认态：无鼠标、无焦点（改前改后的主对照图）。
	await _shoot("default")
	if not _check_layout():
		get_tree().quit(1)
		return

	# ② 手柄/键盘焦点态：焦点落在第 1 张卡上。
	var card0 := _dungeon.call("_fate_choice_button", 0) as Button
	if card0 != null:
		card0.grab_focus()
		for _frame in 18:
			await get_tree().process_frame
		await _shoot("focus_card")

	# ③ 鼠标悬停态：直接触发 mouse_entered（与真实鼠标走同一信号）。
	if card0 != null:
		card0.focus_mode = Control.FOCUS_NONE
		card0.release_focus()
		card0.mouse_entered.emit()
		for _frame in 18:
			await get_tree().process_frame
		await _shoot("hover_card")
		card0.mouse_exited.emit()
		card0.focus_mode = Control.FOCUS_ALL
		for _frame in 12:
			await get_tree().process_frame

	# ④ 购买按钮焦点态：焦点落在第 1 张卡的白色购买按钮上。
	var purchase0 := card0.get_meta("tarot_purchase_button") as Button if card0 != null else null
	if purchase0 != null:
		purchase0.grab_focus()
		for _frame in 18:
			await get_tree().process_frame
		await _shoot("focus_purchase")
		purchase0.release_focus()
		for _frame in 12:
			await get_tree().process_frame

	# ⑤ 余额不足态：钱包清零后刷新价签。
	GameManager.currency = 0
	_dungeon.call("_refresh_door_fate_prices")
	for _frame in 20:
		await get_tree().process_frame
	await _shoot("insufficient")
	if _capture_failed or (not _baseline and not await _check_transaction()):
		get_tree().quit(1)
		return

	print("CAPTURE_FATE_PURCHASE_UI_OK tag=%s res=%s baseline=%s" % [_tag, _res_label, _baseline])
	get_tree().quit(0)


func _check_layout() -> bool:
	var presentation := _dungeon.get("_fate_presentation") as Control
	var board := presentation.get("board") as Control
	var canvas := get_viewport().get_visible_rect()
	var board_rect := board.get_global_rect()
	var centers: Array[float] = []
	print("BOARD_RECT ", board_rect, " CANVAS ", canvas)
	for i in 3:
		var card := _dungeon.call("_fate_choice_button", i) as Button
		if card == null:
			push_error("Missing candidate %d" % i)
			return false
		var caption := card.get_meta("tarot_caption_label") as Label
		var button := card.get_meta("tarot_purchase_button") as Button
		var label := card.get_meta("tarot_price_label") as Label
		var card_rect := card.get_global_rect()
		var caption_rect := caption.get_global_rect()
		var buy_rect := button.get_global_rect()
		var center := card_rect.get_center().x
		centers.append(center)
		print("FATE_LAYOUT ", i, " card=", card_rect, " caption=", caption_rect, " caption_font=", caption.get_theme_font_size("font_size"), " purchase=", buy_rect, " label_font=", label.get_theme_font_size("font_size"), " price=", label.text)
		if _baseline:
			continue
		if not card_rect.size.is_equal_approx(Vector2(143, 222)) \
				or not buy_rect.size.is_equal_approx(Vector2(184, 34)) \
				or caption.get_theme_font_size("font_size") != 20 or caption.max_lines_visible != 3 \
				or label.get_theme_font_size("font_size") != 21 or label.has_theme_font_override("font") \
				or label.get_theme_constant("outline_size") != 0 \
				or absf(buy_rect.get_center().x - center) > 1.0 \
				or card_rect.end.y > caption_rect.position.y or caption_rect.end.y > buy_rect.position.y \
				or buy_rect.end.y > board_rect.position.y \
				or not canvas.encloses(card_rect) or not canvas.encloses(caption_rect) or not canvas.encloses(buy_rect):
			push_error("Candidate %d violates purchase layout geometry or typography" % i)
			return false
	if not _baseline and (absf(centers[1] - canvas.get_center().x) > 1.0 \
			or absf((centers[1] - centers[0]) - (centers[2] - centers[1])) > 1.0):
		push_error("Purchase row not centered and evenly spaced")
		return false
	return true


func _clear_focus_and_pointer() -> void:
	var viewport := get_viewport()
	if viewport != null and viewport.gui_get_focus_owner() != null:
		viewport.gui_get_focus_owner().release_focus()
	for index in range(3):
		var button := _dungeon.call("_fate_choice_button", index) as Button
		if button == null:
			continue
		button.set_meta("fate_feedback_hovered", false)
		button.set_meta("fate_feedback_focused", false)
	_dungeon.call("_refresh_door_fate_prices")


func _shoot(state: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var file_name := "%s_%s_%s.png" % [_tag, state, _res_label]
	var path := "%s/%s" % [_out_dir, file_name]
	var err := image.save_png(path)
	if err == OK:
		print("CAPTURE_SHOT ok=%s %dx%d state=%s" % [path, image.get_width(), image.get_height(), state])
	else:
		_capture_failed = true
		push_error("CAPTURE_SHOT fail=%s err=%d state=%s" % [path, err, state])


func _open_formal_offer(room: DungeonRoom3D, pickup_id: String) -> bool:
	var pickup := (load(FATE_PICKUP_PATH) as GDScript).new() as FateCardDropPickup3D
	pickup.interaction_handler = Callable(_dungeon, "_on_fate_pickup_interacted")
	pickup.configure({
		"type": "fate_pickup",
		"id": "item_fate_card_drop",
		"name": "命运卡",
		"fate_pickup_id": pickup_id,
		"fate_source": "verification",
		"source_room_id": room.room_id,
		"source_chest_id": "capture_chest",
	}, Color(0.72, 0.34, 1.0))
	room.add_child(pickup)
	pickup.global_position = _dungeon.player.global_position
	for _frame in 2:
		await get_tree().process_frame
	var candidate := pickup.get_interaction_candidate(_dungeon.player)
	if candidate.is_empty():
		return false
	if not pickup.perform_interaction(_dungeon.player, candidate):
		return false
	for _frame in 3:
		await get_tree().process_frame
	return bool(_dungeon.get("_door_fate_active"))


func _click_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = down
		get_viewport().push_input(event, true)
		await get_tree().process_frame


func _check_transaction() -> bool:
	var choices := _dungeon.get("_door_fate_choices") as Array
	var bought := _dungeon.get("_door_fate_purchased") as Array
	var index := 0
	for i in choices.size():
		if (choices[i] as FateCard).scope == FateCard.Scope.WEAPON:
			index = i
			break
	var card := _dungeon.call("_fate_choice_button", index) as Button
	var button := card.get_meta("tarot_purchase_button") as Button
	var label := card.get_meta("tarot_price_label") as Label
	var price := int(_dungeon.call("_fate_price", choices[index]))
	if price <= 0 or label.text != "购买  %d" % price or button.tooltip_text != "金币不足" or button.disabled:
		push_error("Shortage fixture cannot exercise the shown purchase button at the quoted price")
		return false
	await _click_at(button.get_global_rect().get_center())
	if GameManager.currency != 0 or bool(bought[index]) or not bool(_dungeon.get("_door_fate_active")):
		push_error("insufficient funds changed transaction state")
		return false
	print("CAPTURE_SHORTAGE_OK wallet=0 price=", price)
	GameManager.currency = 500
	_dungeon.call("_refresh_door_fate_prices")
	await get_tree().create_timer(0.5).timeout
	card.grab_focus()
	var down := InputEventJoypadButton.new()
	down.button_index = JOY_BUTTON_DPAD_DOWN
	down.pressed = true
	get_viewport().push_input(down)
	await get_tree().process_frame
	down.pressed = false
	get_viewport().push_input(down)
	if not button.has_focus():
		push_error("controller down did not focus the buy button")
		return false
	await _click_at(button.get_global_rect().get_center())
	var confirm := _dungeon.get("_fate_confirm") as Control
	if is_instance_valid(confirm):
		await get_tree().process_frame
		for node in confirm.find_children("*", "Button", true, false):
			var choice := node as Button
			if choice.text == "是":
				await _click_at(choice.get_global_rect().get_center())
				break
	await get_tree().create_timer(1.0).timeout
	if GameManager.currency != 500 - price or not bool(bought[index]):
		push_error("purchase failed: index=%d wallet=%d quoted=%d booked=%s status=%s" % [index, GameManager.currency, price, str(bought[index]), _dungeon.status_label.text])
		return false
	print("CAPTURE_TRADE_OK quoted=", price, " deducted=", 500 - GameManager.currency, " simulated_mouse_and_pad=true")
	return true
