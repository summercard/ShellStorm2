class_name SpecialItemController3D
extends Node
## Binding + cooldown + open gasoline bottle. InventoryModule alone owns unopened items.
signal changed(snapshot: Dictionary)
signal used(item_id: String)
signal persistent_state_changed()

var item_id := ""
var fuel_units := 0
var cooldown_remaining := 0.0
var pouring := false
var world: SpecialItemWorld3D
var _player: Node3D
var _inventory: InventoryModule
var _input_allowed: Callable
var _last_oil_position := Vector3.ZERO
var _has_oil_position := false
var _require_release := false
var _last_pour_cue := -1.0

func configure(player_node: Node3D, inventory: InventoryModule, input_allowed: Callable) -> void:
	_player = player_node
	_input_allowed = input_allowed
	if _inventory != null and _inventory.inventory_changed.is_connected(_notify):
		_inventory.inventory_changed.disconnect(_notify)
	_inventory = inventory
	_inventory.inventory_changed.connect(_notify)
	if not is_instance_valid(world):
		world = SpecialItemWorld3D.new()
		world.name = "SpecialItemWorld3D"
		_player.get_parent().add_child(world)
	_notify()

func equip(content_id: String) -> Dictionary:
	if not SpecialItemCatalog.contains(content_id):
		return {"success": false, "reason": "invalid_item"}
	if _inventory == null or (_inventory.get_item_count(content_id) <= 0 and not (content_id == SpecialItemCatalog.GASOLINE and fuel_units > 0)):
		return {"success": false, "reason": "no_stock"}
	stop_pouring()
	item_id = content_id
	_notify()
	persistent_state_changed.emit()
	return {"success": true, "reason": ""}

func unequip() -> void:
	stop_pouring()
	item_id = ""
	_notify()
	persistent_state_changed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if not event.pressed:
			stop_pouring(false)
			_require_release = false
			return
		if _require_release or not can_use():
			return
		if item_id == SpecialItemCatalog.GASOLINE:
			pouring = true
			_has_oil_position = false
			_pour_step()
		else:
			request_use()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		stop_pouring()

func can_use() -> bool:
	if not is_instance_valid(_player) or _inventory == null or not is_instance_valid(world):
		return false
	if (_player is Player3D and not (_player as Player3D).combat_enabled) or int(_player.get("current_hp")) <= 0 or bool(_player.get("input_locked")):
		return false
	if _player.has_method("get_state_machine_state") and str(_player.call("get_state_machine_state")) not in ["idle", "moving"]:
		return false
	return not get_tree().paused and (not _input_allowed.is_valid() or bool(_input_allowed.call()))

func request_use() -> Dictionary:
	if not can_use():
		return {"success": false, "reason": "input_locked"}
	if item_id.is_empty():
		return {"success": false, "reason": "empty_slot"}
	if cooldown_remaining > 0.0001:
		return {"success": false, "reason": "cooldown"}
	if item_id == SpecialItemCatalog.GASOLINE:
		return {"success": _pour_step(), "reason": ""}
	if _inventory.get_item_count(item_id) < 1:
		return {"success": false, "reason": "no_stock"}
	var definition := SpecialItemCatalog.get_item(item_id)
	var forward: Vector3 = _player.get("aim_direction")
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	if not world.launch(definition, _player, forward.normalized()):
		return {"success": false, "reason": "world_capacity"}
	_inventory.consume_item(item_id, 1)
	cooldown_remaining = float(definition.cooldown)
	used.emit(item_id)
	_notify()
	persistent_state_changed.emit()
	return {"success": true, "reason": ""}

func _physics_process(delta: float) -> void:
	var was_cooling := cooldown_remaining > 0.0
	cooldown_remaining = maxf(0.0, cooldown_remaining - delta)
	if pouring:
		# Release events may have been consumed by an opened modal; never resume on close.
		if not can_use() or not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			stop_pouring()
		else:
			_pour_step()
	if was_cooling:
		_notify()
	if _require_release and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_require_release = false

func _pour_step() -> bool:
	if not can_use() or item_id != SpecialItemCatalog.GASOLINE or cooldown_remaining > 0.0001:
		return false
	var definition := SpecialItemCatalog.get_item(item_id)
	var at := _player.global_position
	if _has_oil_position:
		var offset := at - _last_oil_position
		if offset.length() < float(definition.spacing):
			return false
		if offset.length() < 4.0:
			at = _last_oil_position + offset.normalized() * float(definition.spacing)
	if fuel_units <= 0 and _inventory.get_item_count(item_id) < 1:
		stop_pouring()
		return false
	var result := world.deposit_oil(at, _player)
	if not bool(result.get("success", false)):
		return false
	if fuel_units <= 0:
		_inventory.consume_item(item_id, 1)
		fuel_units = int(definition.fuel_capacity)
	fuel_units -= 1
	if world.clock - _last_pour_cue >= 0.3:
		AudioManager.emit_event("special.pour", {"source_node": _player, "source_position": at, "volume_db": -10.0, "max_distance": 12.0})
		_last_pour_cue = world.clock
	_last_oil_position = result.position
	_has_oil_position = true
	cooldown_remaining = float(definition.cooldown)
	used.emit(item_id)
	_notify()
	persistent_state_changed.emit()
	return true

func stop_pouring(require_release := true) -> void:
	pouring = false
	_has_oil_position = false
	_require_release = require_release
	_notify()

func get_snapshot() -> Dictionary:
	var definition := SpecialItemCatalog.get_item(item_id)
	return {
		"schema": "special_items_v1", "item_id": item_id,
		"name": str(definition.get("name", "未装备特殊道具")),
		"count": _inventory.get_item_count(item_id) if _inventory != null else 0,
		"cooldown_remaining": cooldown_remaining, "cooldown_total": float(definition.get("cooldown", 0.0)),
		"fuel_units": fuel_units, "fuel_capacity": int(SpecialItemCatalog.get_item(SpecialItemCatalog.GASOLINE).fuel_capacity), "pouring": pouring,
	}

func export_state() -> Dictionary:
	return {"schema": "special_items_v1", "item_id": item_id, "fuel_units": fuel_units, "cooldown_remaining": cooldown_remaining}

func restore_state(snapshot: Dictionary) -> void:
	stop_pouring()
	item_id = str(snapshot.get("item_id", ""))
	if not SpecialItemCatalog.contains(item_id):
		item_id = ""
	fuel_units = clampi(int(snapshot.get("fuel_units", 0)), 0, int(SpecialItemCatalog.get_item(SpecialItemCatalog.GASOLINE).fuel_capacity))
	var maximum_cooldown := 0.0
	for definition: Dictionary in SpecialItemCatalog.definitions():
		maximum_cooldown = maxf(maximum_cooldown, float(definition.cooldown))
	cooldown_remaining = clampf(float(snapshot.get("cooldown_remaining", 0.0)), 0.0, maximum_cooldown)
	_notify()

func clear_world() -> void:
	stop_pouring()
	if is_instance_valid(world):
		world.clear()

func _notify() -> void:
	changed.emit(get_snapshot())
