extends Node
## Use isolated APPDATA. Run with a renderer for the facility prompt and menu screenshots.

const ELITE_ID := "elite_arms_taker"
const ARCHIVE_ID := "base_facility:monster_archive"
const ENCOUNTER := "archive_qa:elite"
var failures: Array[String] = []
var tower: TowerDescent3D


func _ready() -> void:
	await get_tree().process_frame
	BaseManager.save_path = "user://monster_archive_qa.json"
	BaseManager.data = BaseData.new()
	BaseManager.data.base_generator_enabled = true
	EliteRosterService.reset_roster_for_test()
	tower = load("res://scenes/TowerDescent3D.tscn").instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	var terminal: BaseFacility3D
	for facility in get_tree().get_nodes_in_group("base_facility"):
		if tower.is_ancestor_of(facility) and facility.facility_id == "monster_archive":
			_check(terminal == null, "Duplicate archive terminal in 99F")
			terminal = facility as BaseFacility3D
	if terminal == null:
		_check(false, "99F archive terminal is missing")
	else:
		await _verify_terminal(terminal)
	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("MONSTER_ARCHIVE_FACILITY_OK")
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_terminal(terminal: BaseFacility3D) -> void:
	_check(terminal.menu_scene_path == "res://scenes/MonsterArchiveMenu.tscn", "Terminal launches the wrong facility menu")
	var room := tower._room_by_id.get("facility") as DungeonRoom3D
	var shape := terminal.get_node("InteractionShape") as CollisionShape3D
	var front := shape.global_position
	tower.player.global_position = Vector3(front.x, room.global_position.y + 6.07, front.z)
	tower._on_room_entered(room)
	tower.player.set_physics_process(false)
	await _settle()
	_check(tower.player.get_interaction_focus_snapshot().get("interaction_id") == ARCHIVE_ID, "The standing point in front of the terminal does not focus the archive")
	_check(terminal.prompt_label.visible and terminal.prompt_label.text.contains("怪物档案"), "Archive prompt is missing or carries old text")
	print("ARCHIVE_TERMINAL standing=%s interaction_center=%s prompt=%s" % [tower.player.global_position, front, terminal.prompt_label.global_position])
	await _capture("terminal")

	tower.player.global_position.x -= 3.4
	await _settle()
	_check(not terminal.prompt_label.visible and tower.player.get_interaction_focus_snapshot().get("interaction_id") != ARCHIVE_ID, "Archive prompt leaked to the adjacent sofa")
	tower.player.global_position = Vector3(front.x, room.global_position.y + 0.05, front.z)
	await _settle()
	_check(not terminal.prompt_label.visible, "Archive can be triggered from downstairs")
	tower.player.global_position = Vector3(front.x, room.global_position.y + 6.07, front.z)
	await _settle()

	_key(KEY_E)
	await _settle()
	var menu := tower.get_active_facility_menu() as MonsterArchiveMenu
	_check(menu != null and tower.player.input_locked, "E did not open archive and lock player input")
	if menu == null:
		return
	_check(menu._records.is_empty() and _has_label(menu, "尚未遭遇精英"), "Fresh profile revealed unknown enemies")
	_check(menu._close.has_focus(), "Archive lacks a safe initial focus")
	_check(menu._preview_model == null and menu._preview_placeholder.visible, "Fresh archive exposed a model preview")
	await _capture("archive_empty")
	_check(not EliteRosterService.confirm_reservation(ELITE_ID, ""), "Missing reservation opened an archive entry")
	_check(EliteRosterService.reserve(ELITE_ID, ENCOUNTER, 1) and menu._records.is_empty(), "Reservation exposed an unencountered elite")
	BaseManager.force_save_failure_for_test = true
	_check(not EliteRosterService.confirm_reservation(ELITE_ID, ENCOUNTER) and menu._records.is_empty(), "Failed discovery write revealed an elite")
	BaseManager.force_save_failure_for_test = false
	_check(EliteRosterService.confirm_reservation(ELITE_ID, ENCOUNTER), "First encounter confirmation failed")
	_check(menu._records.size() == 1 and _has_label(menu, "Lv.1") and _has_label(menu, "暂无持有物品"), "First confirmation did not refresh the card")
	var preview := menu._preview_model
	_check(preview != null and preview.get_meta("content_id") == ELITE_ID, "Archive did not use the formal elite model")
	_check(menu._preview_state.text.contains("已登记") and menu._preview_outcome.text.contains("已确认遭遇"), "Archive did not show the first encounter status")
	if is_instance_valid(preview):
		var first_pose: Dictionary = preview.call("get_presentation_snapshot")
		await _settle()
		var next_pose: Dictionary = preview.call("get_presentation_snapshot")
		_check(next_pose.clip == "idle" and not is_equal_approx(float(first_pose.clip_time), float(next_pose.clip_time)), "Preview did not sample its idle animation")
		_check(menu._preview_viewport.world_3d != tower.player.get_world_3d() and preview.find_children("*", "CollisionObject3D", true, false).is_empty(), "Model preview leaked into gameplay physics")
		_check(preview.get_groups().is_empty(), "Preview registered as an active entity")

	var snapshot := {"valid": true, "checkpoint_id": "archive_qa", "run_id": "archive_qa"}
	for index in 2:
		_check(EliteRosterService.commit_run_record(ELITE_ID, {}, snapshot, {
			"receipt_id": "archive_qa:item:%d" % index, "kind": "item",
			"item": {"id": "item_ammo_pack", "name": "备弹"},
		}), "Stolen item was not recorded")
	_check(EliteRosterService.commit_run_record(ELITE_ID, {}, snapshot, {
		"receipt_id": "archive_qa:currency", "kind": "currency", "amount": 25,
	}), "Stolen currency was not recorded")
	_check(EliteRosterService.settle(ELITE_ID, ENCOUNTER, "escaped", {
		"weapon_snapshot": {"content_id": "weapon_starter_rifle"},
		"roaming_encounter": {"max_hp": 4740, "hp": 4266},
	}), "Growth and translated weapon were not saved")
	_check(_has_label(menu, "备弹  ×2") and _has_label(menu, "夺取货币  25") and _has_label(menu, "Lv.2") and _has_label(menu, "阶段枪技"), "Open archive failed to show live assets and growth")
	_check(menu._preview_model == preview, "Record refresh unnecessarily recreated the preview")
	_check(menu._preview_state.text.contains("装备中") and menu._preview_outcome.text.contains("精英逃脱"), "Escape did not refresh the right-side state")
	_check(menu._preview_health.visible and menu._preview_health.text.contains("4266 / 4740"), "Archive failed to show saved health")
	await _settle()
	_check(menu._preview.get_global_rect().end.x <= get_viewport().get_visible_rect().end.x, "Preview overflowed the menu")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var preview_image := menu._preview_viewport.get_texture().get_image()
		var drawn := preview_image.get_used_rect()
		_check(drawn.size.x > 40 and drawn.size.y > 100, "3D preview did not render at a readable size")
		_check(drawn.position.x > 0 and drawn.position.y > 0 and drawn.end.x < preview_image.get_width() and drawn.end.y < preview_image.get_height(), "Preview camera clipped the elite")
	await _capture("archive_discovered")

	_key(KEY_ESCAPE)
	await _settle()
	_check(tower.get_active_facility_menu() == null and not tower.player.input_locked, "Esc did not return control to the player")
	BaseManager.load_base()
	_joy(JOY_BUTTON_A)
	await _settle()
	menu = tower.get_active_facility_menu() as MonsterArchiveMenu
	_check(menu != null and _has_label(menu, "备弹  ×2") and _has_label(menu, "Lv.2"), "Controller reopen after disk reload lost the archive")
	if menu != null:
		_joy(JOY_BUTTON_DPAD_UP)
		await _settle()
		var focused := get_viewport().gui_get_focus_owner()
		_check(focused != null and str(focused.get_meta("elite_id", "")) == ELITE_ID, "Controller could not focus the elite list")
		_joy(JOY_BUTTON_DPAD_RIGHT)
		await _settle()
		_check(menu._detail_scroll.has_focus(), "Controller could not reach the archive detail")
		await _verify_preview_switch(menu)
	_joy(JOY_BUTTON_B)
	await _settle()
	_check(tower.get_active_facility_menu() == null and not tower.player.input_locked, "Controller B did not return control to the player")


func _verify_preview_switch(menu: MonsterArchiveMenu) -> void:
	const SECOND_ELITE := "elite_rift_boar_armed"
	const SECOND_ENCOUNTER := "archive_qa:second"
	_check(EliteRosterService.reserve(SECOND_ELITE, SECOND_ENCOUNTER, 98) and EliteRosterService.confirm_reservation(SECOND_ELITE, SECOND_ENCOUNTER), "Second elite could not be registered")
	menu._select(EliteRosterService.get_record(SECOND_ELITE))
	await _settle()
	var preview := menu._preview_model
	_check(preview != null and preview.get_meta("content_id") == SECOND_ELITE and menu._preview_slot.get_child_count() == 1, "Archive did not replace the model when selecting another elite")
	_check(not menu._preview_health.visible and menu._preview_state.text.contains("已登记"), "Switched elite inherited the previous record's health or status")
	menu._select(EliteRosterService.get_record(ELITE_ID))


func _has_label(menu: MonsterArchiveMenu, value: String) -> bool:
	for label in menu.find_children("*", "Label", true, false):
		if label.text.contains(value):
			return true
	return false


func _key(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)


func _joy(index: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = true
	Input.parse_input_event(event)
	var release := event.duplicate() as InputEventJoypadButton
	release.pressed = false
	Input.parse_input_event(release)


func _settle() -> void:
	for frame in 5:
		await get_tree().physics_frame
		await get_tree().process_frame


func _capture(file_name: String) -> void:
	var folder := OS.get_environment("ARCHIVE_QA_DIR")
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path := VerificationOutput.path("monster_archive_" + file_name + ".png") if folder.is_empty() else folder.path_join(file_name + ".png")
	var error := get_viewport().get_texture().get_image().save_png(path)
	_check(error == OK, "Screenshot could not be saved")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
