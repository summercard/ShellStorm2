extends Node
## Official expedition HUD, deterministic inventory fixtures and real InputMap events.

func _ready() -> void:
	if OS.get_environment("SS2_UI_QA_ISOLATED") != "1" or OS.get_environment("SS2_UI_QA_OUT").is_empty():
		get_tree().quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	var dungeon := (load("res://scenes/ExpeditionLevel01_3D.tscn") as PackedScene).instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 515151
	add_child(dungeon)
	await get_tree().physics_frame
	var room := (dungeon.get("_room_by_id") as Dictionary).get("room_01") as DungeonRoom3D
	if room == null or dungeon.player == null:
		_fail("official room or player missing")
		return
	dungeon.player.global_position = room.global_position + Vector3.UP * 0.1
	dungeon.force_enter_room_for_test("room_01")
	var quick := dungeon.get("_quick_inventory") as InventoryModule
	quick.clear_all()
	var potion := ItemRegistry.get_instance().get_item("item_health_potion")
	if not quick.put_item_in_empty_slot(0, potion, 2):
		_fail("cannot seed slot 3")
		return
	dungeon.call("_sync_quick_item_state")
	dungeon.player.current_hp = 40
	dungeon.player.hp_changed.emit(40, dungeon.player.max_hp)
	await get_tree().create_timer(1.2).timeout
	var hud := dungeon.get_node("HUD/ReferenceCombatHUD") as Control
	var left := hud.get_node("QuickItemHUD_0") as PanelContainer
	var right := hud.get_node("QuickItemHUD_1") as PanelContainer
	var dash := hud.get_node("HudDashCooldownRing") as Control
	var clock := hud.get_node("EncounterCountdownRing") as Control
	var labels := dungeon.get("_hud_quick_item_labels") as Array
	print("HUD_LAYOUT left=", left.get_global_rect(), " right=", right.get_global_rect(), " dash=", dash.get_global_rect(), " countdown=", clock.get_global_rect(), " alpha=", (left.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.a, " labels=", labels[0].text, " / ", labels[1].text)
	if not await _shoot("mixed"):
		return
	if not "--baseline" in OS.get_cmdline_user_args() and not "--tag=hud_before" in OS.get_cmdline_user_args():
		var a := left.get_global_rect()
		var b := right.get_global_rect()
		var c := clock.get_global_rect()
		var alpha := (left.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.a
		if a.position.x <= dash.get_global_rect().end.x or a.end.x >= b.position.x or not is_equal_approx(a.end.y, b.end.y) or a.intersects(c) or b.intersects(c) or alpha < 0.35 or alpha > 0.51:
			_fail("quick slots overlap the dash, each other or countdown, or have the wrong background")
			return
		if not labels[0].text.begins_with("[3]") or not labels[0].text.ends_with("×2") or labels[1].text != "[4] 空":
			_fail("mixed slot labels and count were not refreshed")
			return
		await _key(KEY_4)
		if dungeon.player.current_hp != 40 or not quick.get_slot(1).is_empty():
			_fail("empty input changed inventory or HP")
			return
		await _key(KEY_3)
		if dungeon.player.current_hp <= 40 or int(quick.get_slot(0).get("count", 0)) != 1:
			_fail("physical-key-3 event did not consume one and heal")
			return
		if not quick.put_item_in_empty_slot(1, potion, 1):
			_fail("cannot seed slot 4")
			return
		dungeon.call("_sync_quick_item_state")
		dungeon.player.current_hp = 40
		await _key(KEY_4)
		if dungeon.player.current_hp <= 40 or not quick.get_slot(1).is_empty() or int(quick.get_slot(0).get("count", 0)) != 1:
			_fail("physical-key-4 event did not consume its own item and heal")
			return
		print("HUD_KEYS_OK mapped_physical_keycodes_injected=true [3]=2_to_1 [4]=1_to_empty")
	print("HUD_CAPTURE_OK")
	get_tree().quit(0)


func _key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await get_tree().process_frame


func _shoot(state: String) -> bool:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := OS.get_environment("SS2_UI_QA_OUT").path_join("quick_slots_" + state + ".png")
	if image == null or image.is_empty() or image.save_png(path) != OK:
		_fail("could not save real rendered HUD frame")
		return false
	print("HUD_SHOT ", path, " ", image.get_size())
	return true


func _fail(reason: String) -> void:
	push_error(reason)
	get_tree().quit(1)
