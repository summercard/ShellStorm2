extends Node3D

class Actor extends Node3D:
	var current_hp := 100
	var input_locked := false
	var aim_direction := Vector3.FORWARD
	func get_state_machine_state() -> String:
		return "idle"

class Target extends Node3D:
	var damage_taken := 0
	var last_attacker: Node3D
	func take_projectile_damage(amount: int, _critical: bool, _direction: Vector3, _tags: Array[String], _behavior: Dictionary, attacker: Node3D) -> void:
		damage_taken += amount
		last_attacker = attacker

var failures: Array[String] = []
var checks := 0
var _modal := false

func _ready() -> void:
	call_deferred("_run")

func _check(passed: bool, message: String) -> void:
	checks += 1
	if not passed:
		failures.append(message)
		push_error("SPECIAL_ITEMS_FAIL: " + message)

func _run() -> void:
	# The nonzero floor is deliberate: absolute-y=0 fallbacks must fail here.
	position.y = -1176.0
	_box(Vector3(0, -0.15, 0), Vector3(40, 0.3, 40))
	var actor := Actor.new()
	add_child(actor)
	var target := Target.new()
	add_child(target)
	target.add_to_group("enemy_3d")
	target.position = Vector3(0, 0, -8.0)
	var inventory := InventoryModule.new(40)
	for definition: Dictionary in SpecialItemCatalog.definitions():
		_check(inventory.add_item(definition, 3) == 3, "seed " + str(definition.id))
	var controller := SpecialItemController3D.new()
	actor.add_child(controller)
	controller.configure(actor, inventory, func() -> bool: return not _modal)
	controller.set_physics_process(false)
	controller.world.set_physics_process(false)
	var world := controller.world
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not bool(controller.request_use().success), "empty slot rejected")
	_check(not bool(controller.equip("invalid").success), "foreign item rejected")
	_check(bool(controller.equip(SpecialItemCatalog.GRENADE).success), "grenade equips")
	_modal = true
	_check(not bool(controller.request_use().success) and inventory.get_item_count(SpecialItemCatalog.GRENADE) == 3, "modal does not consume")
	_modal = false
	actor.input_locked = true
	_check(not bool(controller.request_use().success), "player lock rejects")
	actor.input_locked = false
	_check(bool(controller.request_use().success), "throw succeeds")
	_check(inventory.get_item_count(SpecialItemCatalog.GRENADE) == 2, "exactly one grenade consumed")
	_check(not bool(controller.request_use().success) and world.projectiles.size() == 1, "cooldown prevents double throw")
	var initial_y: float = world.projectiles[0].node.global_position.y
	world.advance(0.24)
	_check(world.projectiles.size() == 1 and world.projectiles[0].node.global_position.y > initial_y + 0.2, "actual ballistic apex")
	world.advance(0.85)
	_check(world.projectiles.is_empty(), "grenade sweeps the actual floor")
	_check(target.damage_taken == 90 and target.last_attacker == actor, "grenade radius damage and attribution")
	_check(absf(actor.global_position.y + 1176.0) < 0.01, "nonzero floor retained")
	world.clear()
	await get_tree().process_frame
	var throw_wall := _box(Vector3(0, 1.1, -1.0), Vector3(5, 2.2, 0.12))
	target.damage_taken = 0
	target.position = Vector3(0, 0, -1.7)
	await get_tree().physics_frame
	await get_tree().physics_frame
	world.launch(SpecialItemCatalog.get_item(SpecialItemCatalog.GRENADE), actor, Vector3.FORWARD)
	world.advance(0.18)
	_check(world.projectiles.size() == 1 and world.projectiles[0].node.global_position.z > -0.9, "wall cancels travel without air detonation")
	world.advance(1.4)
	_check(world.projectiles.is_empty() and target.damage_taken == 0, "wall-blocked grenade lands without damaging through wall")
	world.clear()
	throw_wall.queue_free()
	await get_tree().physics_frame
	target.damage_taken = 0
	target.position = Vector3(0, 0, 1)
	world.add_fire(global_position, 2.4, 5.0, 6, actor)
	world.advance(4.99)
	_check(target.damage_taken == 54 and world.fires.size() == 1, "fire nine ticks before five seconds")
	world.advance(0.011)
	_check(target.damage_taken == 60, "fire ten ticks totals sixty damage")
	world.advance(0.1)
	_check(world.fires.is_empty() and target.damage_taken == 60, "fire expires at five seconds")
	world.clear()
	await get_tree().process_frame
	var wall := _box(Vector3(10, 1, 0.7), Vector3(5, 2, 0.2))
	target.position = Vector3(10, 0, 1.4)
	target.damage_taken = 0
	await get_tree().physics_frame
	await get_tree().physics_frame
	world.add_fire(to_global(Vector3(10, 0, 0)), 2.4, 5.0, 6, actor)
	world.advance(0.51)
	_check(target.damage_taken == 0, "solid wall blocks fire damage")
	target.position = Vector3(10, 12, 0)
	world.advance(0.5)
	_check(target.damage_taken == 0, "other floors take no damage")
	world.clear()
	wall.queue_free()
	await get_tree().physics_frame
	var start := to_global(Vector3(-8, 0, 0))
	for index in 4:
		_check(bool(world.deposit_oil(start + Vector3.RIGHT * index * 0.8, actor).success), "oil ground placement %d" % index)
	_check(bool(world.deposit_oil(start + Vector3(0, 0, 3), actor).success), "disconnected patch placement")
	world.add_fire(start, 0.1, 0.05, 6, actor)
	world.advance(0.033)
	_check(float(world.oil[0].burn_until) > 0.0 and float(world.oil[1].burn_until) < 0.0, "first ignition does not instantly flood the chain")
	_check(float(world.oil[0].burn_until) - world.clock > 4.9 and float(world.oil[0].burn_until) - world.clock <= 5.0, "ignited oil has an independently pinned five-second lifetime")
	world.advance(0.45)
	var times: Array[float] = []
	for index in 4:
		times.append(float(world.oil[index].burn_until) - 5.0)
	_check(times[0] < times[1] and times[1] < times[2] and times[2] < times[3], "connected oil ignites in order")
	_check(times[1] - times[0] >= 0.119, "spread delay has actual timing")
	_check(float(world.oil[4].burn_until) < 0.0, "disconnected oil stays unlit")
	world.advance(5.1)
	_check(world.oil.size() == 1, "each burning patch has five-second lifetime")
	world.clear()
	await get_tree().process_frame
	controller.cooldown_remaining = 0.0
	actor.position = Vector3(3, 0, 4)
	_check(bool(controller.equip(SpecialItemCatalog.GASOLINE).success), "gasoline equips")
	_check(bool(controller.request_use().success), "first gasoline deposit succeeds")
	_check(controller.fuel_units == 24 and inventory.get_item_count(SpecialItemCatalog.GASOLINE) == 2, "opening consumes one bottle and one fuel unit")
	controller.cooldown_remaining = 0.0
	_check(not bool(controller.request_use().success) and controller.fuel_units == 24, "standing still does not waste fuel")
	actor.position.x += 0.8
	_check(bool(controller.request_use().success) and controller.fuel_units == 23, "walking leaves next connected patch")
	var saved := controller.export_state()
	controller.unequip()
	controller.restore_state(saved)
	_check(controller.item_id == SpecialItemCatalog.GASOLINE and controller.fuel_units == 23, "save roundtrip preserves binding and open bottle")
	controller.restore_state({})
	_check(controller.item_id.is_empty() and controller.fuel_units == 0, "legacy save defaults are safe")
	controller.equip(SpecialItemCatalog.MOLOTOV)
	controller.cooldown_remaining = 0.0
	actor.position = Vector3(0, 0, 0)
	_check(bool(controller.request_use().success), "molotov actual throw")
	world.advance(1.0)
	_check(world.fires.size() == 1 and float(world.fires[0].radius) == 2.4, "molotov impacts and creates configured fire field")
	_check(world.fires.size() == 1 and float(world.fires[0].until) - world.clock > 4.6 and float(world.fires[0].until) - world.clock <= 5.0, "molotov lifetime independently remains five seconds")
	world.clear()
	await get_tree().process_frame
	# Purchase through the real save/transaction owner; repeated transaction is idempotent.
	var old_data = BaseManager.data
	var old_save_path := BaseManager.save_path
	BaseManager.save_path = "user://special_items_purchase_%s.json" % Time.get_ticks_usec()
	BaseManager.data = BaseData.new()
	BaseManager.data.extraction_points = 1000
	for definition: Dictionary in SpecialItemCatalog.definitions():
		var item := ItemRegistry.get_instance().get_item(str(definition.id))
		_check(bool(item.get("base_shop_enabled", false)), "99F goods listed " + str(definition.id))
		var transaction := "verify_special:" + str(definition.id)
		var before := inventory.get_item_count(str(definition.id))
		var purchase: Dictionary = BaseManager.purchase_base_shop_item_to_inventory(str(definition.id), inventory, transaction)
		_check(bool(purchase.get("success", false)) and inventory.get_item_count(str(definition.id)) == before + 1, "99F purchase delivers " + str(definition.id))
		BaseManager.purchase_base_shop_item_to_inventory(str(definition.id), inventory, transaction)
		_check(inventory.get_item_count(str(definition.id)) == before + 1, "purchase retry no duplicate " + str(definition.id))
		for role: StringName in [ItemModelFactory3D.MODEL_ROLE_PREVIEW, ItemModelFactory3D.MODEL_ROLE_GROUND]:
			var model := ItemModelFactory3D.create_model(item, Color.WHITE, role)
			_check(str(model.get_meta("asset_id", "")) == str(definition.asset_id) and ItemModelFactory3D.count_mesh_instances(model) > 0, "stable model role " + str(definition.id) + " " + str(role))
			model.free()
	BaseManager.data = old_data
	BaseManager.save_path = old_save_path
	var slot := SpecialItemEquipmentSlot.new()
	add_child(slot)
	slot.configure(controller)
	var payload := {"source_kind": "inventory", "item": SpecialItemCatalog.get_item(SpecialItemCatalog.GRENADE)}
	_check(slot._accepts(Vector2.ZERO, payload), "equipment accepts inventory special drag")
	slot._receive(Vector2.ZERO, payload)
	_check(controller.item_id == SpecialItemCatalog.GRENADE, "drag actually equips")
	_check(not slot._accepts(Vector2.ZERO, {"source_kind":"insurance", "item":payload.item}), "insurance cannot alias consumable inventory")
	var hud := SpecialItemHUD.new()
	add_child(hud)
	hud.configure(controller)
	_check(str(hud.get_ui_snapshot().item_id) == SpecialItemCatalog.GRENADE, "HUD subscribes to equipped item")
	for asset_id: StringName in [VfxPool3D.FX01_SPECIAL_FIRE, VfxPool3D.FX01_SPECIAL_OIL, VfxPool3D.FX01_SPECIAL_BLAST]:
		var effect := VfxPool3D.create_unpooled(asset_id)
		add_child(effect)
		_check(effect.find_children("*", "CollisionObject3D", true, false).is_empty(), "pure visual prefab " + str(asset_id))
		effect.activate(global_position, Color.WHITE, 1.2, {"duration": 0.2})
		effect._process(0.21)
		_check(not effect.visible, "effect retires " + str(asset_id))
	controller.clear_world()
	var audio := AudioManager.validate_runtime_assets()
	_check(int(audio.event_count) == 36 and bool(audio.mobile_safe), "legacy 36 audio assets remain mobile safe")
	var audio_requests := AudioManager.get_feedback_debug_snapshot().request_counts as Dictionary
	for cue in ["throw", "blast", "glass", "pour", "ignite", "fire_loop"]:
		var sound_set := AudioManager.get_sound_set("special_" + cue)
		_check(not sound_set.is_empty() and int(audio_requests.get("special_" + cue, 0)) > 0, "actual authored audio cue routed " + cue)
	await get_tree().process_frame
	if failures.is_empty():
		print("SPECIAL_ITEMS_SYSTEM_OK: %d checks" % checks)
	get_tree().quit(0 if failures.is_empty() else 1)

func _box(at: Vector3, dimensions: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dimensions
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	return body
