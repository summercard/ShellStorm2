extends Node

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")
# The visible grid tile, not the hidden anchor-cell preview, uses this budget.
# See the 2026-10-15 inventory experience record; pixel QA is a separate visual scene.
const GRID_ICON_LONG_EDGE := 384
const SHOTGUN_ID := "weapon_shotgun"
const ATTACHMENTS := {
	AssemblyNode.SlotType.MUZZLE: "attach_triple_muzzle",
	AssemblyNode.SlotType.MAGAZINE: "attach_big_mag",
	AssemblyNode.SlotType.MUTATOR: "attach_copy_sticker",
}

var _failures: Array[String] = []
var _dungeon: Dungeon3D
var _inventory: InventoryModule
var _ui: InventoryUI


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dungeon = DUNGEON_SCENE.instantiate() as Dungeon3D
	_dungeon.test_mode = true
	_dungeon.run_seed_override = 240725
	add_child(_dungeon)
	await get_tree().process_frame
	_inventory = _dungeon.get_inventory_module()
	_ui = _dungeon.get_node_or_null("HUD/InventoryUI3D") as InventoryUI
	_expect(_inventory != null and _ui != null, "Inventory module or actual InventoryUI3D is missing")
	if _inventory != null and _ui != null:
		await _verify_grid_and_weapon_ownership()
		await _verify_manual_bullet_swap_is_rejected()
		_verify_retired_items_and_healing()
	_dungeon.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("3D_INVENTORY_WEAPON_FLOW_OK: actual grid click, adaptive one-shot projections, per-instance weapon ownership, bullet lock and retired-item routing pass")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_grid_and_weapon_ownership() -> void:
	_inventory.clear_all()
	var player := _dungeon.player
	var equipped_slot := player.get_active_weapon_slot()
	var starting_item := player.get_equipped_weapon_item()
	var starting_id := str(starting_item.get("weapon_instance_id", ""))
	_expect(not starting_id.is_empty() and starting_item.get("assembly_id", "") == BlueprintRegistry.DEFAULT_STARTING_GUN_ID,
		"The real starting gun and its unique instance must be equipped")
	if starting_id.is_empty():
		return
	for slot_type in ATTACHMENTS:
		var attachment := ItemRegistry.get_instance().get_item(ATTACHMENTS[slot_type])
		var added := _inventory.add_item(attachment, 1)
		var anchor := _find_slot(ATTACHMENTS[slot_type])
		_expect(added == 1 and anchor >= 0 and _dungeon._install_attachment_from_inventory(anchor, attachment, equipped_slot, slot_type),
			"Cannot install legal attachment through the inventory transaction: %s" % ATTACHMENTS[slot_type])
	var built_gun := player.get_equipped_weapon_item()
	_expect(_installed_attachments(WeaponInstance.from_item(built_gun)) == ATTACHMENTS, "The starting gun has no verified attachment build")

	var expected_kinds := {SHOTGUN_ID: "weapon", "mod_bullet_standard": "bullet", "item_health_potion": "heal", "item_beacon": "beacon"}
	for item_id in expected_kinds:
		_expect(_inventory.add_item(ItemRegistry.get_instance().get_item(item_id), 1) == 1, "Cannot seed grid fixture: %s" % item_id)
	_ui.set_inventory_panel_open(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var board := _ui.inventory_grid as GridInventoryBoard
	_expect(board != null, "Visible inventory is not a grid board")
	if board == null:
		_ui.set_inventory_panel_open(false)
		return
	var visuals := board.get("_item_visuals") as Dictionary
	for item_id in expected_kinds:
		var visual := visuals.get(_find_slot(item_id)) as Control
		var icon := visual.get_node_or_null("ItemModelIcon3D") as ItemModelIcon3D if visual != null else null
		_expect(icon != null and icon.is_visible_in_tree(), "Missing visible grid icon: %s" % item_id)
		if icon != null:
			_verify_projection(icon, item_id, expected_kinds[item_id])

	var shotgun_anchor := _find_slot(SHOTGUN_ID)
	var incoming := _inventory.get_slot(shotgun_anchor).get("item", {}) as Dictionary
	var shotgun_id := str(incoming.get("weapon_instance_id", ""))
	_expect(not shotgun_id.is_empty() and shotgun_id != starting_id, "The backpack shotgun must have a distinct instance")
	if not shotgun_id.is_empty():
		await _click_item(shotgun_anchor)
		var active := player.get_equipped_weapon_item()
		var root := player.get_weapon_tree().get_root()
		var weapon_view := player.get_weapon_snapshot()
		_expect(active.get("weapon_instance_id", "") == shotgun_id and active.get("id", "") == SHOTGUN_ID
			and root != null and root.node_name == "GunBody_Shotgun",
			"Real grid click did not equip the selected shotgun instance and its current assembly tree")
		_expect(weapon_view.get("gun_id", "") == "bp_shotgun" and bool(weapon_view.get("has_model", false)),
			"The equipped shotgun did not update the live 3D gun model")
		_expect(not _inventory.has_weapon_instance(shotgun_id), "The equipped shotgun must not remain in the backpack")
		_expect(_installed_attachments(player.get_equipped_weapon_instance()).is_empty(), "A fresh shotgun inherited the previous gun's attachments")
		var returned_anchor := _inventory.find_weapon_instance_slot(starting_id)
		var returned_item := _inventory.get_slot(returned_anchor).get("item", {}) as Dictionary
		_expect(returned_anchor >= 0 and returned_item.get("weapon_instance", {}) == built_gun.get("weapon_instance", {}),
			"The old gun's identity, ammo, or assembly snapshot changed when it returned to the backpack")
		if returned_anchor >= 0:
			await _click_item(returned_anchor)
			_expect(player.get_equipped_weapon_instance_id() == starting_id and
				_installed_attachments(player.get_equipped_weapon_instance()) == ATTACHMENTS,
				"Re-equipping must restore the original gun and its own attachments")
			_expect(_inventory.has_weapon_instance(shotgun_id) and not _inventory.has_weapon_instance(starting_id),
				"Re-equipping must leave exactly one owner for both weapon instances")
	_ui.set_inventory_panel_open(false)


func _verify_projection(icon: ItemModelIcon3D, item_id: String, kind: String) -> void:
	var snapshot := icon.get_snapshot()
	var pixels := snapshot.get("viewport_size", Vector2i.ZERO) as Vector2i
	var control_size := icon.size
	_expect(snapshot.get("item_id", "") == item_id and snapshot.get("model_kind", "") == kind
		and int(snapshot.get("mesh_count", 0)) > 0 and bool(snapshot.get("uses_world_model_factory", false)),
		"%s does not use a non-empty projection of the shared world model" % item_id)
	var short_edge := clampi(roundi(GRID_ICON_LONG_EDGE * minf(control_size.x, control_size.y) / maxf(1.0, maxf(control_size.x, control_size.y))), 24, GRID_ICON_LONG_EDGE)
	var expected := Vector2i(GRID_ICON_LONG_EDGE, short_edge) if control_size.x >= control_size.y else Vector2i(short_edge, GRID_ICON_LONG_EDGE)
	_expect(pixels == expected, "%s grid icon viewport is %s, expected %s" % [item_id, pixels, expected])
	var fit := float(snapshot.get("fit_ratio", 0.0))
	var error_px := snapshot.get("center_error_pixels", Vector2.INF) as Vector2
	var viewport := icon.get_node_or_null("ItemPreviewViewport") as SubViewport
	_expect(fit >= 0.5 and fit <= 1.0 and maxf(absf(error_px.x), absf(error_px.y)) <= 2.0,
		"%s must be readable, uncropped, and centered inside its adaptive frame" % item_id)
	_expect(viewport != null and viewport.render_target_update_mode in [SubViewport.UPDATE_ONCE, SubViewport.UPDATE_DISABLED],
		"%s preview continuously redraws instead of being rendered once" % item_id)


func _verify_manual_bullet_swap_is_rejected() -> void:
	_inventory.clear_all()
	var player := _dungeon.player
	var active_slot := player.get_active_weapon_slot()
	var gun_before := player.get_equipped_weapon_item()
	var installed_id := str(player.get_equipped_bullet_item_for_slot(active_slot).get("id", ""))
	var incoming_id := "mod_bullet_sticky" if installed_id != "mod_bullet_sticky" else "mod_bullet_standard"
	var incoming := ItemRegistry.get_instance().get_item(incoming_id)
	_expect(not installed_id.is_empty() and _inventory.add_item(incoming, 2) == 2, "Cannot seed the locked-bullet fixture")
	var anchor := _find_slot(incoming_id)
	if installed_id.is_empty() or anchor < 0:
		return
	_ui.set_inventory_panel_open(true)
	await get_tree().process_frame
	var before := _inventory.get_slots_snapshot()
	await _click_item(anchor)
	_expect(_dungeon.status_label.text == WeaponBulletDrop.manual_swap_block_reason(), "The real bullet click did not reach the explicit workshop-only rejection")
	var weapon_slot := _ui.equipment_weapon_slots[active_slot] as ItemSlot
	var payload := {"inventory_drag": true, "source_kind": "inventory", "source_index": anchor, "item": incoming}
	_expect(weapon_slot != null and not weapon_slot._can_drop_data(Vector2.ZERO, payload), "The equipment slot still accepts a manual bullet-module drag")
	_expect(not _dungeon._install_bullet_module_from_inventory(anchor, incoming, active_slot), "The lower-level transaction accepted a manual bullet swap")
	_expect(player.get_equipped_weapon_item() == gun_before and _inventory.get_slots_snapshot() == before,
		"A rejected bullet swap mutated the equipped gun, stack counts, or grid coordinates")
	_ui.set_inventory_panel_open(false)


func _verify_retired_items_and_healing() -> void:
	_inventory.clear_all()
	var player := _dungeon.player
	var equipped := player.get_equipped_weapon_item()
	var before := _inventory.get_slots_snapshot()
	for retired in [{"id": "bp_rifle", "type": "blueprint"}, {"id": "item_room_key", "type": "key"}]:
		_expect(_inventory.add_item(retired, 1) == 0, "Retired content entered the backpack: %s" % retired["id"])
	_expect(_inventory.get_slots_snapshot() == before and player.get_equipped_weapon_item() == equipped,
		"Rejection of retired contents changed slots or an equipped weapon")
	var rifle := ItemRegistry.get_instance().get_item("weapon_rifle")
	_expect(rifle.get("assembly_id", "") == "bp_rifle" and _inventory.add_item(rifle, 1) == 1,
		"Rejecting a blueprint fragment must not reject a weapon with the same assembly ID")
	player.current_hp = player.max_hp
	var potion := ItemRegistry.get_instance().get_item("item_health_potion")
	_expect(_inventory.add_item(potion, 1) == 1, "Cannot seed the legal consumable")
	var potion_slot := _find_slot("item_health_potion")
	_dungeon._on_inventory_item_clicked(potion_slot, {})
	_expect(_inventory.get_item_count("item_health_potion") == 1, "Healing was wasted at full health")
	player.current_hp = 40
	player.hp_changed.emit(40, player.max_hp)
	_dungeon._on_inventory_item_clicked(potion_slot, {})
	_expect(player.current_hp == mini(player.max_hp, 40 + int(potion.get("heal_amount", 30)))
		and _inventory.get_item_count("item_health_potion") == 0, "Legal healing did not apply its effect and consume exactly one item")


func _click_item(anchor: int) -> void:
	var board := _ui.inventory_grid as GridInventoryBoard
	if board == null or anchor < 0 or anchor >= board.get_cells().size():
		_expect(false, "Cannot find the real grid input cell: %d" % anchor)
		return
	var cell := board.get_cells()[anchor] as ItemSlot
	if cell == null or not cell.is_visible_in_tree():
		_expect(false, "The real grid input cell is not visible: %d" % anchor)
		return
	var point := cell.get_global_transform_with_canvas() * (cell.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await get_tree().process_frame


func _find_slot(item_id: String) -> int:
	for slot in _inventory.get_occupied_slots():
		if str((slot.get("item", {}) as Dictionary).get("id", "")) == item_id:
			return int(slot.get("slot", -1))
	return -1


func _installed_attachments(instance: WeaponInstance) -> Dictionary:
	var installed := {}
	if instance != null:
		for row in instance.get_presentation_snapshot().get("attachment_layout", []):
			var item_id := str(row.get("installed_item_id", ""))
			if not item_id.is_empty():
				installed[int(row["slot_type"])] = item_id
	return installed


func _expect(condition: bool, detail: String) -> void:
	if not condition:
		_failures.append(detail)
