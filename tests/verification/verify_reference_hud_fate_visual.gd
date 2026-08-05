extends Node

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")
const TOWER_SCENE: PackedScene = preload("res://scenes/TowerDescent3D.tscn")
const OUTPUT_DIR := "res://outputs/verification"


func _ready() -> void:
	var failures: Array[String] = []
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	for _frame in 10:
		await get_tree().process_frame
	dungeon.force_enter_room_for_test("main_01")
	var minimap := dungeon.get_node("HUD/DungeonMinimap3D") as DungeonMinimap3D
	# Freeze dungeon feed so this screenshot can hold two deterministic runtime enemy markers.
	dungeon.set_process(false)
	minimap.set_enemy_positions([
		dungeon.player.global_position + Vector3(4.0, 0.0, 2.0),
		dungeon.player.global_position + Vector3(-3.0, 0.0, -2.0),
	])
	for _frame in 3:
		await get_tree().process_frame

	var hud := dungeon.get_node_or_null("HUD/ReferenceCombatHUD") as Control
	_check(hud != null, "Reference combat HUD root is missing", failures)
	if hud != null:
		var player_status := hud.find_child("PlayerStatusBlock", true, false) as Control
		_check(player_status != null, "Player status block is missing", failures)
		_check(player_status != null and player_status.size.x <= 280.0, "Reference HUD was not reduced to 80% scale", failures)
		_check(hud.find_child("CurrentWeaponPanel", true, false) != null, "Bottom weapon panel is missing", failures)
		_check(hud.find_child("ActionKeyStrip", true, false) != null, "Action key strip is missing", failures)
		var projected_textures := hud.find_children("ProjectedTexture", "TextureRect", true, false)
		var all_textures := hud.find_children("*", "TextureRect", true, false)
		_check(all_textures.size() == 1 and projected_textures.size() == 1, "HUD contains a bitmap texture outside the shared 3D weapon projection", failures)
	var weapon_model := dungeon.get_hud_weapon_model_snapshot()
	_check(bool(weapon_model.get("uses_world_model_factory", false)), "HUD weapon does not reuse the backpack 3D model factory", failures)
	_check(str(weapon_model.get("model_kind", "")) == "weapon" and int(weapon_model.get("mesh_count", 0)) > 0, "HUD weapon 3D projection is empty", failures)
	var weapon_rebuilds := int(weapon_model.get("rebuild_count", 0))
	dungeon.call("_on_ammo_changed", 11, 12)
	_check(int(dungeon.get_hud_weapon_model_snapshot().get("rebuild_count", -1)) == weapon_rebuilds, "HUD weapon model rebuilds on ordinary ammo updates", failures)
	_check(absf(minimap.size.x - minimap.size.y) <= 2.0 and minimap.size.x <= 225.0, "Tactical minimap is not circular or 80% scale", failures)
	_check(minimap.get_snapshot().get("enemy_marker_count", 0) == 2, "Minimap enemy dots are not fed by runtime data", failures)
	_check(_capture("reference_combat_hud.png"), "Could not capture reference combat HUD", failures)

	_check(dungeon.show_reference_fate_overlay_for_test(), "Could not open deterministic fate overlay", failures)
	for _frame in 6:
		await get_tree().process_frame
	var overlay := dungeon.get_node_or_null("HUD/DoorFateOverlay3D") as Control
	_check(overlay != null, "Fate overlay is missing", failures)
	if overlay != null:
		var cards := overlay.find_children("FateChoiceCard_*", "Button", true, false)
		_check(cards.size() == 3, "Fate overlay does not show three vertical cards", failures)
		_check(overlay.find_children("*", "TextureRect", true, false).is_empty(), "Fate overlay uses a bitmap TextureRect", failures)
		var all_text := _collect_label_text(overlay)
		for required in ["星星命运", "太阳命运", "月亮命运", "当前信息", "命 运 卡 三 选 一"]:
			_check(required in all_text, "Fate overlay is missing text: %s" % required, failures)
		for card in cards:
			var card_control := card as Control
			_check(card_control.size.y > card_control.size.x, "Fate choice is not a vertical card", failures)
			_check(card_control.size.x <= 205.0 and card_control.size.y <= 305.0, "Fate card was not reduced to 80% scale", failures)
	_check(_capture("reference_fate_three_choice.png"), "Could not capture reference fate overlay", failures)

	dungeon.queue_free()
	await get_tree().process_frame
	var tower := TOWER_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 4242
	add_child(tower)
	for _frame in 10:
		await get_tree().process_frame
	var tower_info := tower.get_node_or_null("HUD/TowerCurrentInfoHUD") as Control
	var tower_player_status := tower.get_node_or_null("HUD/ReferenceCombatHUD/PlayerStatusBlock") as Control
	_check(tower_info != null, "Tower current information panel is missing", failures)
	if tower_info != null and tower_player_status != null:
		_check(tower_info.global_position.y >= tower_player_status.get_global_rect().end.y + 20.0, "Tower current information was not moved below player status", failures)
		_check(tower_info.find_children("*", "ProgressBar", true, false).is_empty(), "Tower current information still contains the duplicate gray HP bar", failures)
	_check(_capture("reference_tower_hud_compact.png"), "Could not capture compact tower HUD", failures)

	if failures.is_empty():
		print("REFERENCE_HUD_FATE_VISUAL_OK: 80% HUD, separated tower info, shared 3D weapon model and three celestial fate cards render")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _capture(file_name: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var image := get_viewport().get_texture().get_image()
	return image != null and image.save_png("%s/%s" % [OUTPUT_DIR, file_name]) == OK


func _collect_label_text(root: Node) -> String:
	var result := ""
	for label_node in root.find_children("*", "Label", true, false):
		result += "\n" + (label_node as Label).text
	return result


func _check(condition: bool, failure: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(failure)
